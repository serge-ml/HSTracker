//
//  HearthArenaFeatureBootstrap.swift
//  HSTracker
//

import Foundation

final class HearthArenaFeatureBootstrap {
    static let shared = HearthArenaFeatureBootstrap()

    let diagnostics = HearthArenaDiagnostics()
    let tierListStore: HearthArenaTierListStore

    private let adapter = ArenaChoiceAdapter()
    private let overlayController = ArenaOverlayController()
    private var currentOffer: ArenaOffer?
    private var currentDeckEdit: ArenaDeckEdit?
    private var stateMachine = ArenaOfferStateMachine()
    private var resolver: CardIdentityResolver?
    private var resolverContentHash: String?
    private var lastLoggedState = HearthArenaFeatureState.idle
    private var lastLoggedDataStatus: String?
    private var enabledObserver: NSObjectProtocol?
    private var hearthstoneClosedObserver: NSObjectProtocol?
    private var started = false

    private init() {
        let cacheURL = Paths.hearthArena.appendingPathComponent(
            "tierlist-v1.json",
            isDirectory: false
        )
        tierListStore = HearthArenaTierListStore(
            client: HearthArenaClient(),
            parser: HearthArenaHTMLParser(),
            validator: TierListValidator(),
            cache: TierListCache(fileURL: cacheURL)
        )
    }

    func start(watcher: ArenaWatcher) {
        guard !started else {
            return
        }
        started = true

        watcher.onChoicesChanged = { [weak self] _, args in
            self?.handleChoicesChanged(args)
        }
        watcher.onDeckEditChanged = { [weak self] _, args in
            self?.handleDeckEditChanged(args)
        }
        watcher.onChoicePicked = { [weak self] _ in
            self?.handleChoicePicked()
        }
        watcher.onDraftClosed = { [weak self] _ in
            self?.handleDraftClosed()
        }

        tierListStore.onStatusChanged = { [weak self] status in
            guard let self = self else { return }
            self.log(dataStatus: status)
            self.diagnostics.update(dataStatus: status)
            if
                status.ratingCount > 0,
                self.currentOffer != nil || self.currentDeckEdit != nil
            {
                self.renderCurrentPresentation()
            }
        }

        enabledObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name(rawValue: HearthArenaSettings.enabledKey),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.enabledChanged()
        }
        hearthstoneClosedObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name(rawValue: Events.hearthstone_closed),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDraftClosed()
        }

        tierListStore.load { [weak self] in
            guard let self = self, HearthArenaSettings.enabled else { return }
            self.tierListStore.refreshIfNeeded()
        }
    }

    private func handleChoicesChanged(_ args: ChoicesChangedEventArgs) {
        do {
            let offer = try adapter.makeOffer(from: args)
            DispatchQueue.main.async { [weak self] in
                self?.accept(offer: offer)
            }
        } catch {
            logger.warning("HearthArena ignored Arena offer: \(error.localizedDescription)")
            DispatchQueue.main.async { [weak self] in
                self?.discardCurrentOffer(reason: "invalid Arena offer")
            }
        }
    }

    private func handleDeckEditChanged(_ args: DeckEditChangedEventArgs) {
        do {
            let deckEdit = try adapter.makeDeckEdit(from: args)
            DispatchQueue.main.async { [weak self] in
                self?.accept(deckEdit: deckEdit)
            }
        } catch {
            logger.warning(
                "HearthArena ignored Arena deck edit: " +
                error.localizedDescription
            )
            DispatchQueue.main.async { [weak self] in
                self?.discardCurrentPresentation(
                    reason: "invalid Arena deck edit"
                )
            }
        }
    }

    private func accept(offer: ArenaOffer) {
        guard stateMachine.accept(offer) else {
            return
        }
        currentOffer = offer
        currentDeckEdit = nil
        diagnostics.update(offer: offer)
        updateState(.loading, reason: "new Arena offer")

        let ids = offer.cards.map { $0.cardId }.joined(separator: ", ")
        logger.info(
            "HearthArena Arena offer class=\(offer.heroClass.rawValue) " +
            "slot=\(offer.draftSlot) version=\(offer.offerVersion) cards=[\(ids)]"
        )

        guard HearthArenaSettings.enabled else {
            updateState(.hidden, reason: "feature disabled")
            overlayController.hide()
            return
        }

        if !offer.packages.isEmpty {
            logger.info(
                "HearthArena package offer detected; showing individual " +
                "scores without aggregate ranking."
            )
            guard
                offer.packages.count == 3,
                offer.packages.allSatisfy({ !$0.isEmpty })
            else {
                logger.warning(
                    "HearthArena expected three non-empty Arena packages, " +
                    "got \(offer.packages.count)."
                )
                discardCurrentOffer(reason: "invalid package offer")
                return
            }
        } else if offer.cards.count != 3 {
            logger.warning(
                "HearthArena expected three Arena choices, got \(offer.cards.count)."
            )
            discardCurrentOffer(reason: "unexpected choice count")
            return
        }
        tierListStore.refreshIfNeeded()
        renderCurrentPresentation()
    }

    private func accept(deckEdit: ArenaDeckEdit) {
        guard deckEdit.identityKey != currentDeckEdit?.identityKey else {
            return
        }
        currentOffer = nil
        currentDeckEdit = deckEdit
        stateMachine.choicePicked()
        diagnostics.clearOffer()
        updateState(.loading, reason: "Arena deck edit changed")

        let discardedIds = deckEdit.discardedCards
            .map { $0.cardId }
            .joined(separator: ", ")
        logger.info(
            "HearthArena Arena deck edit class=\(deckEdit.heroClass.rawValue) " +
            "discard=[\(discardedIds)]"
        )

        guard HearthArenaSettings.enabled else {
            updateState(.hidden, reason: "feature disabled")
            overlayController.hide()
            return
        }
        tierListStore.refreshIfNeeded()
        renderCurrentPresentation()
    }

    private func renderCurrentPresentation() {
        guard HearthArenaSettings.enabled else {
            overlayController.hide(clearOffer: false)
            return
        }
        if let deckEdit = currentDeckEdit {
            render(deckEdit: deckEdit)
        } else if let offer = currentOffer {
            render(offer: offer)
        } else {
            overlayController.hide(clearOffer: false)
        }
    }

    private func render(offer: ArenaOffer) {
        let expectedKey = offer.identityKey
        tierListStore.currentSnapshot { [weak self] snapshot in
            guard
                let self = self,
                let current = self.currentOffer,
                current.identityKey == expectedKey,
                HearthArenaSettings.enabled
            else {
                return
            }
            guard let snapshot = snapshot else {
                guard self.stateMachine.markOffline(for: current) else {
                    return
                }
                self.updateState(.offline, reason: "no valid tier-list snapshot")
                self.overlayController.hide()
                self.tierListStore.refreshIfNeeded()
                return
            }

            let resolver = self.resolver(for: snapshot)
            let ratedOffer = resolver.rate(current)
            self.diagnostics.update(ratedOffer: ratedOffer)
            let displayedCards = ratedOffer.packages.isEmpty
                ? ratedOffer.cards
                : ratedOffer.packages.flatMap { $0 }
            self.logUnknownCards(displayedCards)
            guard self.stateMachine.markVisible(for: current) else {
                return
            }
            self.updateState(.visible, reason: "ratings resolved")
            self.overlayController.show(ratedOffer)
        }
    }

    private func render(deckEdit: ArenaDeckEdit) {
        let expectedKey = deckEdit.identityKey
        tierListStore.currentSnapshot { [weak self] snapshot in
            guard
                let self = self,
                let current = self.currentDeckEdit,
                current.identityKey == expectedKey,
                HearthArenaSettings.enabled
            else {
                return
            }
            guard let snapshot = snapshot else {
                self.updateState(
                    .offline,
                    reason: "no valid tier-list snapshot"
                )
                self.overlayController.hide()
                self.tierListStore.refreshIfNeeded()
                return
            }

            let ratedDeckEdit = self.resolver(for: snapshot).rate(current)
            self.logUnknownCards(ratedDeckEdit.discardedCards)
            self.updateState(.visible, reason: "deck-edit ratings resolved")
            self.overlayController.show(ratedDeckEdit)
        }
    }

    private func logUnknownCards(_ cards: [ArenaRatedCard]) {
        for ratedCard in cards where ratedCard.score == nil {
            if diagnostics.recordUnknown(card: ratedCard.card) {
                let canonicalName =
                    HearthArenaTextNormalizer.canonicalCardName(
                        ratedCard.card.englishName
                    )
                logger.warning(
                    "HearthArena has no rating for " +
                    "cardId=\(ratedCard.card.cardId) " +
                    "canonicalName=\(canonicalName)"
                )
            }
        }
    }

    private func resolver(for snapshot: TierListSnapshot) -> CardIdentityResolver {
        if
            let resolver = resolver,
            resolverContentHash == snapshot.contentHash
        {
            return resolver
        }
        let resolver = CardIdentityResolver(snapshot: snapshot)
        self.resolver = resolver
        resolverContentHash = snapshot.contentHash
        return resolver
    }

    private func handleChoicePicked() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentOffer = nil
            self.currentDeckEdit = nil
            self.stateMachine.choicePicked()
            self.updateState(.hidden, reason: "card picked")
            self.diagnostics.clearOffer()
            self.overlayController.hide()
        }
    }

    private func handleDraftClosed() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentOffer = nil
            self.currentDeckEdit = nil
            self.stateMachine.closeDraft()
            self.updateState(.idle, reason: "Arena draft closed")
            self.diagnostics.clearOffer()
            self.overlayController.hide()
        }
    }

    private func enabledChanged() {
        if HearthArenaSettings.enabled {
            tierListStore.refreshIfNeeded()
            renderCurrentPresentation()
        } else {
            updateState(.hidden, reason: "feature disabled")
            overlayController.hide(clearOffer: false)
        }
    }

    private func discardCurrentOffer(reason: String) {
        discardCurrentPresentation(reason: reason)
    }

    private func discardCurrentPresentation(reason: String) {
        currentOffer = nil
        currentDeckEdit = nil
        stateMachine.choicePicked()
        diagnostics.clearOffer()
        updateState(.hidden, reason: reason)
        overlayController.hide()
    }

    private func updateState(
        _ state: HearthArenaFeatureState,
        reason: String
    ) {
        diagnostics.update(state: state)
        guard state != lastLoggedState else {
            return
        }
        logger.info(
            "HearthArena state \(lastLoggedState.rawValue) -> " +
            "\(state.rawValue): \(reason)"
        )
        lastLoggedState = state
    }

    private func log(dataStatus: HearthArenaDataStatus) {
        let key = [
            dataStatus.freshness.rawValue,
            String(dataStatus.ratingCount),
            dataStatus.isRefreshing ? "refreshing" : "idle",
            dataStatus.lastError ?? ""
        ].joined(separator: "|")
        guard key != lastLoggedDataStatus else {
            return
        }
        lastLoggedDataStatus = key
        logger.info(
            "HearthArena data freshness=\(dataStatus.freshness.rawValue) " +
            "ratings=\(dataStatus.ratingCount) " +
            "refreshing=\(dataStatus.isRefreshing) " +
            "parser=\(TierListSnapshot.currentParserVersion) " +
            "schema=\(TierListSnapshot.currentSchemaVersion)"
        )
        if let error = dataStatus.lastError {
            logger.warning("HearthArena data error: \(error)")
        }
    }
}
