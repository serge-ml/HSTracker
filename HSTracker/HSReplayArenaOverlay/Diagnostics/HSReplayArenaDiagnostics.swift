//
//  HSReplayArenaDiagnostics.swift
//  HSTracker
//

import Foundation

enum HSReplayArenaFeatureState: String {
    case idle
    case loading
    case visible
    case hidden
    case offline
}

struct HSReplayArenaDiagnosticsSnapshot {
    let state: HSReplayArenaFeatureState
    let offerVersion: Int?
    let isUnderground: Bool?
    let offeredClassCount: Int
    let matchedClassCount: Int
    let dataStatus: HSReplayArenaDataStatus?
}

final class HSReplayArenaDiagnostics {
    private let lock = NSLock()
    private var state = HSReplayArenaFeatureState.idle
    private var offerVersion: Int?
    private var underground: Bool?
    private var offeredClasses = 0
    private var matchedClasses = 0
    private var dataStatus: HSReplayArenaDataStatus?

    func update(state: HSReplayArenaFeatureState) {
        lock.lock()
        self.state = state
        lock.unlock()
    }

    func update(offer: HSReplayArenaHeroOffer) {
        lock.lock()
        offerVersion = offer.offerVersion
        underground = offer.isUnderground
        offeredClasses = offer.heroes.count
        matchedClasses = 0
        lock.unlock()
    }

    func update(ratedOffer: HSReplayArenaRatedHeroOffer) {
        lock.lock()
        guard offerVersion == ratedOffer.offer.offerVersion else {
            lock.unlock()
            return
        }
        matchedClasses = ratedOffer.heroes.filter { $0.stat != nil }.count
        lock.unlock()
    }

    func update(dataStatus: HSReplayArenaDataStatus) {
        lock.lock()
        self.dataStatus = dataStatus
        lock.unlock()
    }

    func clearOffer() {
        lock.lock()
        offerVersion = nil
        underground = nil
        offeredClasses = 0
        matchedClasses = 0
        lock.unlock()
    }

    func snapshot() -> HSReplayArenaDiagnosticsSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return HSReplayArenaDiagnosticsSnapshot(
            state: state,
            offerVersion: offerVersion,
            isUnderground: underground,
            offeredClassCount: offeredClasses,
            matchedClassCount: matchedClasses,
            dataStatus: dataStatus
        )
    }
}
