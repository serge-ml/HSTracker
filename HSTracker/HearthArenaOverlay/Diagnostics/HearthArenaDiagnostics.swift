//
//  HearthArenaDiagnostics.swift
//  HSTracker
//

import Foundation

enum HearthArenaFeatureState: String, Equatable {
    case idle
    case loading
    case visible
    case hidden
    case offline
}

struct HearthArenaDiagnosticsSnapshot {
    let state: HearthArenaFeatureState
    let currentOfferVersion: Int?
    let currentDraftSlot: Int?
    let isUnderground: Bool?
    let isPackageOffer: Bool?
    let currentMatchedCardCount: Int
    let currentOfferedCardCount: Int
    let sessionMatchedCardCount: Int
    let sessionOfferedCardCount: Int
    let unknownCardCount: Int
    let dataStatus: HearthArenaDataStatus?

    var currentMatchCoverage: Double? {
        guard currentOfferedCardCount > 0 else { return nil }
        return Double(currentMatchedCardCount) /
            Double(currentOfferedCardCount)
    }

    var sessionMatchCoverage: Double? {
        guard sessionOfferedCardCount > 0 else { return nil }
        return Double(sessionMatchedCardCount) /
            Double(sessionOfferedCardCount)
    }
}

final class HearthArenaDiagnostics {
    private let lock = NSLock()
    private var featureState = HearthArenaFeatureState.idle
    private var offerVersion: Int?
    private var draftSlot: Int?
    private var underground: Bool?
    private var packageOffer: Bool?
    private var activeOfferKey: String?
    private var currentMatchedCards = 0
    private var currentOfferedCards = 0
    private var sessionMatchedCards = 0
    private var sessionOfferedCards = 0
    private var unknownCards = Set<String>()
    private var tierListStatus: HearthArenaDataStatus?

    func update(state: HearthArenaFeatureState) {
        lock.lock()
        featureState = state
        lock.unlock()
    }

    func update(offer: ArenaOffer) {
        lock.lock()
        if activeOfferKey != offer.identityKey {
            activeOfferKey = offer.identityKey
            currentMatchedCards = 0
            currentOfferedCards = 0
        }
        offerVersion = offer.offerVersion
        draftSlot = offer.draftSlot
        underground = offer.isUnderground
        packageOffer = !offer.packages.isEmpty
        lock.unlock()
    }

    func update(ratedOffer: ArenaRatedOffer) {
        let displayedCards = ratedOffer.packages.isEmpty
            ? ratedOffer.cards
            : ratedOffer.packages.flatMap { $0 }
        let matched = displayedCards.filter { $0.score != nil }.count

        lock.lock()
        guard activeOfferKey == ratedOffer.offer.identityKey else {
            lock.unlock()
            return
        }
        sessionMatchedCards += matched - currentMatchedCards
        sessionOfferedCards += displayedCards.count - currentOfferedCards
        currentMatchedCards = matched
        currentOfferedCards = displayedCards.count
        lock.unlock()
    }

    @discardableResult
    func recordUnknown(card: OfferedCard) -> Bool {
        lock.lock()
        let inserted = unknownCards.insert(
            card.cardId.isEmpty ? card.englishName : card.cardId
        ).inserted
        lock.unlock()
        return inserted
    }

    func update(dataStatus: HearthArenaDataStatus) {
        lock.lock()
        tierListStatus = dataStatus
        lock.unlock()
    }

    func clearOffer() {
        lock.lock()
        offerVersion = nil
        draftSlot = nil
        underground = nil
        packageOffer = nil
        activeOfferKey = nil
        currentMatchedCards = 0
        currentOfferedCards = 0
        lock.unlock()
    }

    func snapshot() -> HearthArenaDiagnosticsSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return HearthArenaDiagnosticsSnapshot(
            state: featureState,
            currentOfferVersion: offerVersion,
            currentDraftSlot: draftSlot,
            isUnderground: underground,
            isPackageOffer: packageOffer,
            currentMatchedCardCount: currentMatchedCards,
            currentOfferedCardCount: currentOfferedCards,
            sessionMatchedCardCount: sessionMatchedCards,
            sessionOfferedCardCount: sessionOfferedCards,
            unknownCardCount: unknownCards.count,
            dataStatus: tierListStatus
        )
    }
}
