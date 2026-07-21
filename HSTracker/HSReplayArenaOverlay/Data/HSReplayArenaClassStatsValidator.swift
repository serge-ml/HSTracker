//
//  HSReplayArenaClassStatsValidator.swift
//  HSTracker
//

import Foundation

enum HSReplayArenaValidationError: LocalizedError {
    case unsupportedSchema(Int)
    case tooFewClasses(Int)
    case duplicateClass(HSReplayArenaHeroClass)
    case invalidWinRate(HSReplayArenaHeroClass, Double)
    case invalidPickRate(HSReplayArenaHeroClass, Double)
    case invalidDraftCount(HSReplayArenaHeroClass, Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "Unsupported Arena class-statistics schema \(version)."
        case .tooFewClasses(let count):
            return "Arena class data contains only \(count) classes."
        case .duplicateClass(let heroClass):
            return "Arena class data contains duplicate \(heroClass.rawValue) rows."
        case .invalidWinRate(let heroClass, let value):
            return "Arena data contains invalid \(heroClass.rawValue) win rate \(value)."
        case .invalidPickRate(let heroClass, let value):
            return "Arena data contains invalid \(heroClass.rawValue) pick rate \(value)."
        case .invalidDraftCount(let heroClass, let value):
            return "Arena data contains invalid \(heroClass.rawValue) draft count \(value)."
        }
    }
}

struct HSReplayArenaClassStatsValidator {
    let minimumClassCount: Int

    init(minimumClassCount: Int = 3) {
        self.minimumClassCount = minimumClassCount
    }

    func validate(_ snapshot: HSReplayArenaClassStatsSnapshot) throws {
        guard
            snapshot.schemaVersion ==
                HSReplayArenaClassStatsSnapshot.currentSchemaVersion
        else {
            throw HSReplayArenaValidationError.unsupportedSchema(
                snapshot.schemaVersion
            )
        }
        guard snapshot.stats.count >= minimumClassCount else {
            throw HSReplayArenaValidationError.tooFewClasses(
                snapshot.stats.count
            )
        }

        var seen = Set<HSReplayArenaHeroClass>()
        for stat in snapshot.stats {
            guard seen.insert(stat.heroClass).inserted else {
                throw HSReplayArenaValidationError.duplicateClass(
                    stat.heroClass
                )
            }
            guard stat.winRate.isFinite, (0...100).contains(stat.winRate)
            else {
                throw HSReplayArenaValidationError.invalidWinRate(
                    stat.heroClass,
                    stat.winRate
                )
            }
            if let pickRate = stat.pickRate {
                guard pickRate.isFinite, (0...100).contains(pickRate) else {
                    throw HSReplayArenaValidationError.invalidPickRate(
                        stat.heroClass,
                        pickRate
                    )
                }
            }
            if let draftCount = stat.draftCount, draftCount < 0 {
                throw HSReplayArenaValidationError.invalidDraftCount(
                    stat.heroClass,
                    draftCount
                )
            }
        }
    }
}
