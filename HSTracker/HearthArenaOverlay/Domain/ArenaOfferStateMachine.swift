//
//  ArenaOfferStateMachine.swift
//  HSTracker
//

import Foundation

enum ArenaOfferPresentationState: Equatable {
    case idle
    case loading(String)
    case visible(String)
    case hidden
    case offline(String)
}
struct ArenaOfferStateMachine {
    private(set) var state = ArenaOfferPresentationState.idle
    private(set) var currentOfferKey: String?

    mutating func accept(_ offer: ArenaOffer) -> Bool {
        let key = offer.identityKey
        guard key != currentOfferKey else {
            return false
        }
        currentOfferKey = key
        state = .loading(key)
        return true
    }

    mutating func markVisible(for offer: ArenaOffer) -> Bool {
        guard offer.identityKey == currentOfferKey else {
            return false
        }
        state = .visible(offer.identityKey)
        return true
    }

    mutating func markOffline(for offer: ArenaOffer) -> Bool {
        guard offer.identityKey == currentOfferKey else {
            return false
        }
        state = .offline(offer.identityKey)
        return true
    }

    mutating func choicePicked() {
        currentOfferKey = nil
        state = .hidden
    }

    mutating func closeDraft() {
        currentOfferKey = nil
        state = .idle
    }
}
