//
//  ArenaChoiceAdapter.swift
//  HSTracker
//

import Foundation

enum ArenaChoiceAdapterError: LocalizedError {
    case missingHero(String)
    case unsupportedHeroClass(CardClass)
    case emptyChoices
    case invalidDeckEdit(deckCount: Int, discardCount: Int)

    var errorDescription: String? {
        switch self {
        case .missingHero(let cardId):
            return "Arena deck has an unknown hero card ID: \(cardId)."
        case .unsupportedHeroClass(let cardClass):
            return "Arena hero class is not supported: \(cardClass.rawValue)."
        case .emptyChoices:
            return "Arena offer does not contain any cards."
        case .invalidDeckEdit(let deckCount, let discardCount):
            return "Arena deck edit has \(deckCount) deck cards, " +
                "and \(discardCount) cards on discard."
        }
    }
}

final class ArenaChoiceAdapter {
    func makeOffer(from args: ChoicesChangedEventArgs) throws -> ArenaOffer {
        let heroCardId = args.heroCardId
        guard let hero = Cards.hero(byId: heroCardId) else {
            throw ArenaChoiceAdapterError.missingHero(heroCardId)
        }
        guard let heroClass = HearthArenaHeroClass(cardClass: hero.playerClass) else {
            throw ArenaChoiceAdapterError.unsupportedHeroClass(hero.playerClass)
        }

        let cards = args.choices.map(makeOfferedCard)
        guard !cards.isEmpty else {
            throw ArenaChoiceAdapterError.emptyChoices
        }

        return ArenaOffer(
            offerVersion: args.version,
            draftSlot: args.currentSlot,
            heroClass: heroClass,
            isUnderground: args.isUnderground,
            cards: cards,
            packages: args.packages.map { $0.map(makeOfferedCard) }
        )
    }

    func makeDeckEdit(
        from args: DeckEditChangedEventArgs
    ) throws -> ArenaDeckEdit {
        let heroCardId = args.deck.hero as String
        guard let hero = Cards.hero(byId: heroCardId) else {
            throw ArenaChoiceAdapterError.missingHero(heroCardId)
        }
        guard let heroClass = HearthArenaHeroClass(cardClass: hero.playerClass)
        else {
            throw ArenaChoiceAdapterError.unsupportedHeroClass(
                hero.playerClass
            )
        }

        let deckCount = args.deck.cards.reduce(0) {
            $0 + $1.count.intValue
        }
        let discardedCards = args.discardedCardIds.map(makeOfferedCard)
        guard deckCount == 30, discardedCards.count == 5 else {
            throw ArenaChoiceAdapterError.invalidDeckEdit(
                deckCount: deckCount,
                discardCount: discardedCards.count
            )
        }

        return ArenaDeckEdit(
            heroClass: heroClass,
            isUnderground: args.isUnderground,
            discardedCards: discardedCards
        )
    }

    private func makeOfferedCard(_ mirrorCard: MirrorCard) -> OfferedCard {
        makeOfferedCard(mirrorCard.cardId)
    }

    private func makeOfferedCard(_ cardId: String) -> OfferedCard {
        let card = databaseCard(for: cardId)
        return OfferedCard(
            cardId: cardId,
            dbfId: card?.dbfId,
            englishName: card?.englishName ?? ""
        )
    }

    private func databaseCard(for cardId: String) -> Card? {
        var card = Cards.any(byId: cardId)
        if card == nil {
            for prefix in ["CORE_", "VAN_"] where cardId.hasPrefix(prefix) {
                card = Cards.any(
                    byId: String(cardId.dropFirst(prefix.count))
                )
                break
            }
        }
        return card
    }

}

private extension HearthArenaHeroClass {
    init?(cardClass: CardClass) {
        switch cardClass {
        case .deathknight: self = .deathKnight
        case .demonhunter: self = .demonHunter
        case .druid: self = .druid
        case .hunter: self = .hunter
        case .mage: self = .mage
        case .paladin: self = .paladin
        case .priest: self = .priest
        case .rogue: self = .rogue
        case .shaman: self = .shaman
        case .warlock: self = .warlock
        case .warrior: self = .warrior
        case .neutral: self = .neutral
        default: return nil
        }
    }
}
