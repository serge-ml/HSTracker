//
//  HSReplayArenaHeroChoiceAdapter.swift
//  HSTracker
//

import Foundation

enum HSReplayArenaHeroChoiceAdapterError: LocalizedError {
    case invalidChoiceCount(Int)
    case missingHero(String)
    case unsupportedHeroClass(CardClass)

    var errorDescription: String? {
        switch self {
        case .invalidChoiceCount(let count):
            return "Arena hero selection contains \(count) choices."
        case .missingHero(let cardId):
            return "Arena hero selection has unknown card ID \(cardId)."
        case .unsupportedHeroClass(let cardClass):
            return "Arena hero class \(cardClass.rawValue) is unsupported."
        }
    }
}

final class HSReplayArenaHeroChoiceAdapter {
    func makeOffer(
        from args: ArenaHeroChoicesChangedEventArgs
    ) throws -> HSReplayArenaHeroOffer {
        guard args.choices.count == 3 else {
            throw HSReplayArenaHeroChoiceAdapterError.invalidChoiceCount(
                args.choices.count
            )
        }

        let heroes = try args.choices.map { choice -> HSReplayArenaHeroChoice in
            let cardId = choice.cardId
            guard
                let hero = Cards.hero(byId: cardId) ??
                    Cards.any(byId: cardId)
            else {
                throw HSReplayArenaHeroChoiceAdapterError.missingHero(cardId)
            }
            guard
                let heroClass = HSReplayArenaHeroClass(
                    cardClass: hero.playerClass
                )
            else {
                throw HSReplayArenaHeroChoiceAdapterError
                    .unsupportedHeroClass(hero.playerClass)
            }
            return HSReplayArenaHeroChoice(
                cardId: cardId,
                heroName: hero.englishName,
                heroClass: heroClass
            )
        }

        return HSReplayArenaHeroOffer(
            offerVersion: args.version,
            isUnderground: args.isUnderground,
            heroes: heroes
        )
    }
}

private extension HSReplayArenaHeroClass {
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
        default: return nil
        }
    }
}
