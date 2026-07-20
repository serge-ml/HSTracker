//
//  ArenaOffer.swift
//  HSTracker
//

import Foundation

struct ArenaOffer: Equatable {
    let offerVersion: Int
    let draftSlot: Int
    let heroClass: HearthArenaHeroClass
    let isUnderground: Bool
    let cards: [OfferedCard]
    let packages: [[OfferedCard]]

    var identityKey: String {
        let cardIds = cards.map { $0.cardId }.joined(separator: ",")
        let packageIds = packages
            .map { package in package.map { $0.cardId }.joined(separator: "+") }
            .joined(separator: ",")
        return [
            String(offerVersion),
            String(draftSlot),
            isUnderground ? "underground" : "arena",
            heroClass.rawValue,
            cardIds,
            packageIds
        ].joined(separator: "|")
    }
}

struct OfferedCard: Equatable, Hashable {
    let cardId: String
    let dbfId: Int?
    let englishName: String
}

struct ArenaDeckEdit: Equatable {
    let heroClass: HearthArenaHeroClass
    let isUnderground: Bool
    let discardedCards: [OfferedCard]

    var identityKey: String {
        let discardedIds = discardedCards
            .map { $0.cardId }
            .joined(separator: ",")
        return [
            isUnderground ? "underground-edit" : "arena-edit",
            heroClass.rawValue,
            discardedIds
        ].joined(separator: "|")
    }
}

struct ArenaDiscardTracker: Equatable {
    private let poolCardIds: [String]
    private(set) var discardedCardIds: [String]

    init?(
        originalDeckCardIds: [String],
        initialDiscardCardIds: [String],
        currentDeckCardIds: [String]
    ) {
        guard
            originalDeckCardIds.count == 30,
            initialDiscardCardIds.count == 5,
            currentDeckCardIds.count == 30
        else {
            return nil
        }
        poolCardIds = originalDeckCardIds + initialDiscardCardIds
        discardedCardIds = initialDiscardCardIds
        guard update(currentDeckCardIds: currentDeckCardIds) else {
            return nil
        }
    }

    @discardableResult
    mutating func update(currentDeckCardIds: [String]) -> Bool {
        guard currentDeckCardIds.count == 30 else {
            return false
        }

        var outsideCounts = Self.counts(for: poolCardIds)
        for cardId in currentDeckCardIds {
            guard let count = outsideCounts[cardId], count > 0 else {
                return false
            }
            if count == 1 {
                outsideCounts.removeValue(forKey: cardId)
            } else {
                outsideCounts[cardId] = count - 1
            }
        }
        guard outsideCounts.values.reduce(0, +) == 5 else {
            return false
        }

        var remainingCounts = outsideCounts
        var vacatedIndexes = [Int]()
        for index in discardedCardIds.indices {
            let cardId = discardedCardIds[index]
            if let count = remainingCounts[cardId], count > 0 {
                if count == 1 {
                    remainingCounts.removeValue(forKey: cardId)
                } else {
                    remainingCounts[cardId] = count - 1
                }
            } else {
                vacatedIndexes.append(index)
            }
        }

        var replacements = [String]()
        for cardId in poolCardIds {
            guard let count = remainingCounts[cardId], count > 0 else {
                continue
            }
            replacements.append(cardId)
            if count == 1 {
                remainingCounts.removeValue(forKey: cardId)
            } else {
                remainingCounts[cardId] = count - 1
            }
        }
        guard
            replacements.count == vacatedIndexes.count,
            remainingCounts.isEmpty
        else {
            return false
        }
        for (index, cardId) in zip(vacatedIndexes, replacements) {
            discardedCardIds[index] = cardId
        }
        return true
    }

    private static func counts(for cardIds: [String]) -> [String: Int] {
        cardIds.reduce(into: [:]) { result, cardId in
            result[cardId, default: 0] += 1
        }
    }
}
