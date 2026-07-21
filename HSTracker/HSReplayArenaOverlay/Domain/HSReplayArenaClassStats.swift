//
//  HSReplayArenaClassStats.swift
//  HSTracker
//

import Foundation

enum HSReplayArenaHeroClass: String, Codable, CaseIterable {
    case deathKnight = "DEATHKNIGHT"
    case demonHunter = "DEMONHUNTER"
    case druid = "DRUID"
    case hunter = "HUNTER"
    case mage = "MAGE"
    case paladin = "PALADIN"
    case priest = "PRIEST"
    case rogue = "ROGUE"
    case shaman = "SHAMAN"
    case warlock = "WARLOCK"
    case warrior = "WARRIOR"

    init?(hsReplayDeckClass: Int) {
        switch hsReplayDeckClass {
        case 1: self = .deathKnight
        case 2: self = .druid
        case 3: self = .hunter
        case 4: self = .mage
        case 5: self = .paladin
        case 6: self = .priest
        case 7: self = .rogue
        case 8: self = .shaman
        case 9: self = .warlock
        case 10: self = .warrior
        case 14: self = .demonHunter
        default: return nil
        }
    }

    var displayName: String {
        switch self {
        case .deathKnight: return "Death Knight"
        case .demonHunter: return "Demon Hunter"
        case .druid: return "Druid"
        case .hunter: return "Hunter"
        case .mage: return "Mage"
        case .paladin: return "Paladin"
        case .priest: return "Priest"
        case .rogue: return "Rogue"
        case .shaman: return "Shaman"
        case .warlock: return "Warlock"
        case .warrior: return "Warrior"
        }
    }
}

struct HSReplayArenaClassStat: Codable, Equatable {
    let heroClass: HSReplayArenaHeroClass
    let winRate: Double
    let pickRate: Double?
    let draftCount: Int?
}

struct HSReplayArenaClassStatsSnapshot: Codable, Equatable {
    static let currentSchemaVersion = 1
    static let sourceURL =
        "https://static.zerotoheroes.com/api/arena/stats/classes/" +
        "all/past-7/overview.gz.json"
    static let pageURL =
        "https://github.com/Zero-to-Heroes/firestone"

    let schemaVersion: Int
    let fetchedAt: Date
    let stats: [HSReplayArenaClassStat]

    init(
        schemaVersion: Int = currentSchemaVersion,
        fetchedAt: Date,
        stats: [HSReplayArenaClassStat]
    ) {
        self.schemaVersion = schemaVersion
        self.fetchedAt = fetchedAt
        self.stats = stats
    }
}

struct HSReplayArenaHeroChoice: Equatable {
    let cardId: String
    let heroName: String
    let heroClass: HSReplayArenaHeroClass
}

struct HSReplayArenaHeroOffer: Equatable {
    let offerVersion: Int
    let isUnderground: Bool
    let heroes: [HSReplayArenaHeroChoice]

    var identityKey: String {
        [
            String(offerVersion),
            isUnderground ? "underground" : "arena",
            heroes.map { $0.cardId }.joined(separator: ",")
        ].joined(separator: "|")
    }
}

struct HSReplayArenaRatedHero: Equatable {
    let hero: HSReplayArenaHeroChoice
    let stat: HSReplayArenaClassStat?
    let rank: Int?
}

struct HSReplayArenaRatedHeroOffer: Equatable {
    let offer: HSReplayArenaHeroOffer
    let heroes: [HSReplayArenaRatedHero]
}
