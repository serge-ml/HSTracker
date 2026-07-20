//
//  TierRating.swift
//  HSTracker
//

import Foundation

enum HearthArenaHeroClass: String, Codable, CaseIterable {
    case deathKnight = "DEATH_KNIGHT"
    case demonHunter = "DEMON_HUNTER"
    case druid = "DRUID"
    case hunter = "HUNTER"
    case mage = "MAGE"
    case paladin = "PALADIN"
    case priest = "PRIEST"
    case rogue = "ROGUE"
    case shaman = "SHAMAN"
    case warlock = "WARLOCK"
    case warrior = "WARRIOR"
    case neutral = "NEUTRAL"

    var tierListSlug: String {
        switch self {
        case .deathKnight: return "death-knight"
        case .demonHunter: return "demon-hunter"
        case .neutral: return "any"
        default: return rawValue.lowercased()
        }
    }
}
struct TierRating: Codable, Equatable {
    let heroClass: HearthArenaHeroClass
    let cardId: String?
    let cardName: String
    let score: Int
}

struct TierListSnapshot: Codable, Equatable {
    static let currentSchemaVersion = 1
    static let currentParserVersion = 1
    static let sourceURL = "https://www.heartharena.com/tierlist"

    let schemaVersion: Int
    let parserVersion: Int
    let source: String
    let fetchedAt: Date
    let contentHash: String
    let ratings: [TierRating]

    init(fetchedAt: Date, contentHash: String, ratings: [TierRating]) {
        self.schemaVersion = TierListSnapshot.currentSchemaVersion
        self.parserVersion = TierListSnapshot.currentParserVersion
        self.source = TierListSnapshot.sourceURL
        self.fetchedAt = fetchedAt
        self.contentHash = contentHash
        self.ratings = ratings
    }
}
