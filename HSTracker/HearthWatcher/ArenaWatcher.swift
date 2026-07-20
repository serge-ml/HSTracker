//
//  ArenaWatcher.swift
//  HSTracker
//
//  Created by Francisco Moraes on 11/9/24.
//  Copyright © 2024 Benjamin Michotte. All rights reserved.
//

import Foundation
import Atomics

enum ArenaSessionState: Int {
    case invalid = -1,
         no_run,
         drafting,
         midrun,
         redrafting,
         editing_deck,
         rewards,
         midrun_redraft_pending
}

struct CompleteDeckEventArgs {
    let info: MirrorArenaInfo
}

struct RewardsEventArgs {
    let info: MirrorArenaInfo
}

struct ChoicesChangedEventArgs {
    let choices: [MirrorCard]
    let deck: MirrorDeck
    let currentSlot: Int
    let isUnderground: Bool
    let packages: [[MirrorCard]]
    let version: Int
}

struct DeckEditChangedEventArgs {
    let deck: MirrorDeck
    let discardedCardIds: [String]
    let isUnderground: Bool
}

final class ArenaWatcher {
    private let delay: TimeInterval

    private var _running = ManagedAtomic<Bool>(false)
    private var _watch = ManagedAtomic<Bool>(false)
    internal var queue: DispatchQueue?
    
    private var _prevSlot = -1
    private var _prevRedraftSlot = -1
    private var _prevChoices: [MirrorCard]?
    private var _prevPackages: [[MirrorCard]]?
    private var _prevChoicesVersion = -1
    private var _prevInfo: MirrorArenaInfo?
    private var _prevIsUnderground: Bool?
    private var _prevArenaSessionState = ArenaSessionState.invalid
    private var _prevDeckEditSignature: String?
    private var _discardTracker: ArenaDiscardTracker?
    private let _arenaLogLock = NSLock()
    private var _arenaLogDeckCandidate = [String]()
    private var _arenaLogOriginalDeck: [String]?
    private final let maxDeckSize = 30
    private final let maxRedraftDeckSize = 5
    
    public var onCompleteDeck: ((ArenaWatcher, CompleteDeckEventArgs) -> Void)?
    public var onRewards: ((RewardsEventArgs) -> Void)?
    public var onChoicesChanged: ((ArenaWatcher, ChoicesChangedEventArgs) -> Void)?
    public var onDeckEditChanged: ((ArenaWatcher, DeckEditChangedEventArgs) -> Void)?
    public var onChoicePicked: ((ArenaWatcher) -> Void)?
    public var onDraftClosed: ((ArenaWatcher) -> Void)?

    init(delay: TimeInterval = 0.500) {
        self.delay = delay
    }
    
    func run() {
        _watch.store(true, ordering: .sequentiallyConsistent)
        if _running.load(ordering: .sequentiallyConsistent) {
            return
        }
        if queue == nil {
            queue = DispatchQueue(label: "\(type(of: self))",
                                  attributes: [])
        }
        if let queue = queue {
            queue.async { [weak self] in
                guard let self else { return }
                Thread.current.name = queue.label
                self.watch()
            }
        }
    }
    
    func stop() {
        let wasWatching = _watch.exchange(false, ordering: .sequentiallyConsistent)
        if wasWatching {
            onDraftClosed?(self)
        }
    }

    func watch() {
        _running.store(true, ordering: .sequentiallyConsistent)
        _prevSlot = -1
        _prevRedraftSlot = -1
        _prevInfo = nil
        _prevChoices = nil
        _prevChoicesVersion = -1
        _prevPackages = nil
        _prevIsUnderground = nil
        _prevArenaSessionState = .invalid
        _prevDeckEditSignature = nil
        _discardTracker = nil
        while _watch.load(ordering: .sequentiallyConsistent) {
            Thread.sleep(forTimeInterval: delay)

            if !_watch.load(ordering: .sequentiallyConsistent) {
                break
            }
            if update() {
                break
            }
        }
        _running .store(false, ordering: .sequentiallyConsistent)
    }
    
    func update() -> Bool {
        guard let arenaInfo = DeckImporter.fromArena(false) else {
            return false
        }
        
        if arenaInfo.sessionState.intValue == ArenaSessionState.midrun.rawValue {
            if _prevArenaSessionState == .drafting {
                let numCards = arenaInfo.deck.cards.reduce(0, { $0 + $1.count.intValue })
                if numCards == maxDeckSize {
                    if _prevSlot == maxDeckSize {
                        cardPicked(arenaInfo)
                    }
                }
            }
            onCompleteDeck?(self, CompleteDeckEventArgs(info: arenaInfo))
            if arenaInfo.rewards.count > 0 {
                onRewards?(RewardsEventArgs(info: arenaInfo))
            }
            _watch.store(false, ordering: .sequentiallyConsistent)
            onDraftClosed?(self)
            return true
        }
        
        if arenaInfo.sessionState.intValue == ArenaSessionState.editing_deck.rawValue {
            return updateDeckEditing(arenaInfo)
        }
        
        if arenaInfo.sessionState.intValue == ArenaSessionState.redrafting.rawValue || arenaInfo.sessionState.intValue == ArenaSessionState.midrun_redraft_pending.rawValue {
            return updateRedraft(arenaInfo)
        }

        // Hide the previous offer as soon as the slot advances. The next set of
        // choices can arrive a poll later, so waiting for it leaves stale badges
        // visible after the user has already picked a card.
        if
            _prevSlot > 0,
            arenaInfo.currentSlot.intValue > _prevSlot,
            _prevIsUnderground == arenaInfo.isUnderground
        {
            cardPicked(arenaInfo)
            _prevSlot = arenaInfo.currentSlot.intValue
        }

        guard let choices = MirrorHelper.getArenaDraftChoices(), choices.choices.count > 0 else {
            return false
        }
        
        if
            _prevChoicesVersion == choices.version.intValue,
            _prevIsUnderground == arenaInfo.isUnderground
        {
            return false
        }
        
        // we need to check _prevIsUnderground == arenaInfo.IsUnderground
        // otherwise changing arena mode would trigger Hero/CardPicked
        if _prevSlot == 0 && arenaInfo.currentSlot.intValue == 1 && _prevIsUnderground == arenaInfo.isUnderground {
            heroPicked(arenaInfo)
        }

        if arenaInfo.currentSlot.intValue > 0 {
            onChoicesChanged?(
                self,
                ChoicesChangedEventArgs(
                    choices: choices.choices,
                    deck: arenaInfo.deck,
                    currentSlot: arenaInfo.currentSlot.intValue,
                    isUnderground: arenaInfo.isUnderground,
                    packages: choices.packages,
                    version: choices.version.intValue
                )
            )
        }
        _prevSlot = arenaInfo.currentSlot.intValue
        _prevRedraftSlot = -1
        _prevInfo = arenaInfo
        _prevChoices = choices.choices
        _prevChoicesVersion = choices.version.intValue
        _prevPackages = choices.packages
        _prevIsUnderground = arenaInfo.isUnderground
        _prevArenaSessionState = ArenaSessionState(rawValue: arenaInfo.sessionState.intValue) ?? .invalid
        return false
    }

    func observeArenaLog(_ line: String) {
        let cardMarker =
            "DraftManager.OnChoicesAndContents - Draft deck contains card "
        _arenaLogLock.lock()
        defer { _arenaLogLock.unlock() }

        if line.contains(
            "DraftManager.OnChoicesAndContents - Draft Deck ID:"
        ) {
            _arenaLogDeckCandidate.removeAll(keepingCapacity: true)
        } else if let range = line.range(of: cardMarker) {
            let cardId = line[range.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cardId.isEmpty {
                _arenaLogDeckCandidate.append(cardId)
            }
        } else if line.contains("SetDraftMode - REDRAFTING"),
                  _arenaLogDeckCandidate.count == maxDeckSize {
            _arenaLogOriginalDeck = _arenaLogDeckCandidate
        }
    }

    private func updateDeckEditing(_ arenaInfo: MirrorArenaInfo) -> Bool {
        let poolCardCount = arenaInfo.redraftDeck.cards.reduce(
            0,
            { $0 + $1.count.intValue }
        )
        if poolCardCount == maxDeckSize {
            if _prevRedraftSlot == maxRedraftDeckSize - 1 {
                redraftLastCardPicked(arenaInfo)
                _prevRedraftSlot = -1
            }
            _prevDeckEditSignature = nil
            _discardTracker = nil
            return false
        }

        let signature = [
            deckSignature(arenaInfo.deck),
            deckSignature(arenaInfo.redraftDeck),
            arenaInfo.isUnderground ? "underground" : "arena"
        ].joined(separator: "|")
        guard signature != _prevDeckEditSignature else {
            return false
        }

        let currentDeckCardIds = expandedCardIds(arenaInfo.deck)
        let initialDiscardCardIds = expandedCardIds(arenaInfo.redraftDeck)
        if _discardTracker == nil {
            let originalDeckCardIds =
                arenaLogOriginalDeck() ?? currentDeckCardIds
            _discardTracker = ArenaDiscardTracker(
                originalDeckCardIds: originalDeckCardIds,
                initialDiscardCardIds: initialDiscardCardIds,
                currentDeckCardIds: currentDeckCardIds
            )
        } else if !_discardTracker!.update(
            currentDeckCardIds: currentDeckCardIds
        ) {
            logger.warning(
                "Arena deck edit could not reconcile the current 30-card " +
                "deck with its original 35-card pool."
            )
        }
        guard
            let discardedCardIds = _discardTracker?.discardedCardIds,
            discardedCardIds.count == maxRedraftDeckSize
        else {
            return false
        }

        _prevDeckEditSignature = signature
        _prevArenaSessionState = .editing_deck
        _prevIsUnderground = arenaInfo.isUnderground
        onDeckEditChanged?(
            self,
            DeckEditChangedEventArgs(
                deck: arenaInfo.deck,
                discardedCardIds: discardedCardIds,
                isUnderground: arenaInfo.isUnderground
            )
        )
        return false
    }

    private func arenaLogOriginalDeck() -> [String]? {
        _arenaLogLock.lock()
        defer { _arenaLogLock.unlock() }
        return _arenaLogOriginalDeck
    }

    private func expandedCardIds(_ deck: MirrorDeck) -> [String] {
        deck.cards.flatMap {
            Array(repeating: $0.cardId, count: $0.count.intValue)
        }
    }

    private func deckSignature(_ deck: MirrorDeck) -> String {
        let cards = deck.cards
            .map { "\($0.cardId):\($0.count.intValue)" }
            .sorted()
            .joined(separator: ",")
        return "\(deck.hero)|\(cards)"
    }
    
    private func updateRedraft(_ arenaInfo: MirrorArenaInfo) -> Bool {
        _discardTracker = nil
        let redraftSlot = arenaInfo.redraftCurrentSlot.intValue
        
        guard let choices = MirrorHelper.getArenaDraftChoices(), choices.choices.count > 0 else {
            return false
        }
        
        if _prevInfo != nil && redraftSlot <= _prevRedraftSlot && _prevIsUnderground == arenaInfo.isUnderground && _prevChoicesVersion == choices.version.intValue {
            return false
        }
        
        if
            _prevRedraftSlot >= 0,
            redraftSlot > _prevRedraftSlot,
            _prevIsUnderground == arenaInfo.isUnderground
        {
            redraftCardPicked(arenaInfo)
        }

        onChoicesChanged?(
            self,
            ChoicesChangedEventArgs(
                choices: choices.choices,
                deck: arenaInfo.deck,
                currentSlot: redraftSlot + 1,
                isUnderground: arenaInfo.isUnderground,
                packages: choices.packages,
                version: choices.version.intValue
            )
        )
        
        _prevSlot = -1
        _prevRedraftSlot = redraftSlot
        _prevInfo = arenaInfo
        _prevChoices = choices.choices
        _prevChoicesVersion = choices.version.intValue
        _prevPackages = choices.packages
        _prevIsUnderground = arenaInfo.isUnderground
        _prevArenaSessionState = ArenaSessionState(rawValue: arenaInfo.sessionState.intValue) ?? .invalid
        return false
    }
    
    private func heroPicked(_ arenaInfo: MirrorArenaInfo) {
        // TODO
    }
    
    private func cardPicked(_ arenaInfo: MirrorArenaInfo) {
        onChoicePicked?(self)
    }
    
    private func redraftCardPicked(_ arenaInfo: MirrorArenaInfo) {
        onChoicePicked?(self)
    }
    
    private func redraftLastCardPicked(_ arenaInfo: MirrorArenaInfo) {
        onChoicePicked?(self)
        onDraftClosed?(self)
    }
}
