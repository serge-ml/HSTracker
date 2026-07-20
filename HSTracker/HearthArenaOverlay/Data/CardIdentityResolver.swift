//
//  CardIdentityResolver.swift
//  HSTracker
//

import Foundation

final class CardIdentityResolver {
    private struct LookupKey: Hashable {
        let heroClass: HearthArenaHeroClass
        let identity: String
    }

    private let ratingsByCardId: [LookupKey: TierRating]
    private let ratingsByCardIdAlias: [LookupKey: TierRating]
    private let ratingsByName: [LookupKey: TierRating]

    init(snapshot: TierListSnapshot) {
        var byCardId = [LookupKey: TierRating]()
        var byCardIdAlias = [LookupKey: TierRating]()
        var ambiguousCardIdAliases = Set<LookupKey>()
        var byName = [LookupKey: TierRating]()

        for rating in snapshot.ratings {
            if let cardId = rating.cardId, !cardId.isEmpty {
                let normalizedCardId = cardId.uppercased()
                let key = LookupKey(
                    heroClass: rating.heroClass,
                    identity: normalizedCardId
                )
                if byCardId[key] == nil {
                    byCardId[key] = rating
                }

                for alias in Self.cardIdAliases(for: normalizedCardId) {
                    let aliasKey = LookupKey(
                        heroClass: rating.heroClass,
                        identity: alias
                    )
                    if let existing = byCardIdAlias[aliasKey],
                       existing.cardId?.uppercased() != normalizedCardId {
                        ambiguousCardIdAliases.insert(aliasKey)
                    } else if !ambiguousCardIdAliases.contains(aliasKey) {
                        byCardIdAlias[aliasKey] = rating
                    }
                }
            }

            let canonicalName = HearthArenaTextNormalizer.canonicalCardName(
                rating.cardName
            )
            guard !canonicalName.isEmpty else {
                continue
            }
            let key = LookupKey(
                heroClass: rating.heroClass,
                identity: canonicalName
            )
            if byName[key] == nil {
                byName[key] = rating
            }
        }

        for key in ambiguousCardIdAliases {
            byCardIdAlias.removeValue(forKey: key)
        }
        self.ratingsByCardId = byCardId
        self.ratingsByCardIdAlias = byCardIdAlias
        self.ratingsByName = byName
    }

    func rating(
        for card: OfferedCard,
        heroClass: HearthArenaHeroClass
    ) -> (rating: TierRating?, status: RatingMatchStatus) {
        let cardId = card.cardId.uppercased()
        if !cardId.isEmpty {
            if let rating = rating(
                forCardId: cardId,
                heroClass: heroClass
            ) {
                return (rating, .exactCardId)
            }
        }

        let canonicalName = HearthArenaTextNormalizer.canonicalCardName(
            card.englishName
        )
        if !canonicalName.isEmpty {
            let exactNameKey = LookupKey(
                heroClass: heroClass,
                identity: canonicalName
            )
            if let rating = ratingsByName[exactNameKey] {
                return (rating, .exactName)
            }
        }

        guard heroClass != .neutral else {
            return (nil, .missing)
        }

        if !cardId.isEmpty {
            if let rating = rating(
                forCardId: cardId,
                heroClass: .neutral
            ) {
                return (rating, .neutralCardId)
            }
        }

        if !canonicalName.isEmpty {
            let neutralNameKey = LookupKey(
                heroClass: .neutral,
                identity: canonicalName
            )
            if let rating = ratingsByName[neutralNameKey] {
                return (rating, .neutralName)
            }
        }

        return (nil, .missing)
    }

    private func rating(
        forCardId cardId: String,
        heroClass: HearthArenaHeroClass
    ) -> TierRating? {
        let identities = [cardId] + Self.cardIdAliases(for: cardId)
        for identity in identities {
            let key = LookupKey(heroClass: heroClass, identity: identity)
            if let rating = ratingsByCardId[key] {
                return rating
            }
        }
        for identity in identities {
            let key = LookupKey(heroClass: heroClass, identity: identity)
            if let rating = ratingsByCardIdAlias[key] {
                return rating
            }
        }
        return nil
    }

    private static func cardIdAliases(for cardId: String) -> [String] {
        for prefix in ["CORE_", "VAN_"] where cardId.hasPrefix(prefix) {
            return [String(cardId.dropFirst(prefix.count))]
        }
        return []
    }

    func rate(_ offer: ArenaOffer) -> ArenaRatedOffer {
        let cards = rate(
            cards: offer.cards,
            heroClass: offer.heroClass,
            includeRanks: true
        )
        let packages = offer.packages.map {
            rate(
                cards: $0,
                heroClass: offer.heroClass,
                includeRanks: false
            )
        }
        return ArenaRatedOffer(offer: offer, cards: cards, packages: packages)
    }

    func rate(_ deckEdit: ArenaDeckEdit) -> ArenaRatedDeckEdit {
        let ratedDiscardedCards = rate(
            cards: deckEdit.discardedCards,
            heroClass: deckEdit.heroClass,
            includeRanks: true
        )
        return ArenaRatedDeckEdit(
            deckEdit: deckEdit,
            discardedCards: ratedDiscardedCards
        )
    }

    private func rate(
        cards: [OfferedCard],
        heroClass: HearthArenaHeroClass,
        includeRanks: Bool
    ) -> [ArenaRatedCard] {
        let resolved = cards.map { card -> (OfferedCard, Int?, RatingMatchStatus) in
            let result = rating(for: card, heroClass: heroClass)
            return (card, result.rating?.score, result.status)
        }

        let sortedIndexes = resolved.indices.sorted { left, right in
            let leftScore = resolved[left].1 ?? Int.min
            let rightScore = resolved[right].1 ?? Int.min
            if leftScore == rightScore {
                return left < right
            }
            return leftScore > rightScore
        }
        var rankByIndex = [Int: Int]()
        if includeRanks {
            for (offset, index) in sortedIndexes.enumerated()
            where resolved[index].1 != nil {
                rankByIndex[index] = offset + 1
            }
        }

        return resolved.enumerated().map { index, item in
            ArenaRatedCard(
                card: item.0,
                score: item.1,
                rank: rankByIndex[index],
                matchStatus: item.2
            )
        }
    }
}
