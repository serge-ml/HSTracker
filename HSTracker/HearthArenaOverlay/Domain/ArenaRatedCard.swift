//
//  ArenaRatedCard.swift
//  HSTracker
//

import Foundation

enum RatingMatchStatus: String {
    case exactCardId
    case exactName
    case neutralCardId
    case neutralName
    case missing
}

struct ArenaRatedCard: Equatable {
    let card: OfferedCard
    let score: Int?
    let rank: Int?
    let matchStatus: RatingMatchStatus
}

struct ArenaRatedOffer: Equatable {
    let offer: ArenaOffer
    let cards: [ArenaRatedCard]
    let packages: [[ArenaRatedCard]]
}

struct ArenaRatedDeckEdit: Equatable {
    let deckEdit: ArenaDeckEdit
    let discardedCards: [ArenaRatedCard]
}
