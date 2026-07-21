//
//  HSReplayArenaJSONParser.swift
//  HSTracker
//

import Foundation

enum HSReplayArenaJSONParserError: LocalizedError {
    case unsupportedSchema(Int)
    case noSupportedClasses
    case invalidSourceTimestamp(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "Unsupported Arena class-statistics cache schema \(version)."
        case .noSupportedClasses:
            return "The Arena statistics source did not return supported classes."
        case .invalidSourceTimestamp(let value):
            return "The Arena statistics source returned invalid timestamp \(value)."
        }
    }
}

struct HSReplayArenaJSONParser {
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    func parse(data: Data) throws -> HSReplayArenaClassStatsSnapshot {
        if let payload = try? JSONDecoder().decode(
            FirestonePayload.self,
            from: data
        ) {
            return try parseFirestone(payload)
        }
        return try parseLegacyHSReplay(data: data)
    }

    private func parseFirestone(
        _ payload: FirestonePayload
    ) throws -> HSReplayArenaClassStatsSnapshot {
        var totals = [HSReplayArenaHeroClass: FirestoneAggregate]()
        for entry in payload.stats {
            guard
                let heroClass = HSReplayArenaHeroClass(
                    rawValue: entry.playerClass.uppercased()
                ),
                entry.totalGames > 0,
                entry.totalsWins >= 0
            else {
                continue
            }
            var aggregate = totals[heroClass] ?? FirestoneAggregate()
            aggregate.totalGames += entry.totalGames
            aggregate.totalWins += entry.totalsWins
            totals[heroClass] = aggregate
        }
        guard !totals.isEmpty else {
            throw HSReplayArenaJSONParserError.noSupportedClasses
        }

        let allGames = totals.values.reduce(0) {
            $0 + $1.totalGames
        }
        let stats = totals.map { heroClass, aggregate in
            HSReplayArenaClassStat(
                heroClass: heroClass,
                winRate: 100 * Double(aggregate.totalWins) /
                    Double(aggregate.totalGames),
                pickRate: allGames > 0
                    ? 100 * Double(aggregate.totalGames) / Double(allGames)
                    : nil,
                draftCount: aggregate.totalGames
            )
        }.sorted { $0.heroClass.rawValue < $1.heroClass.rawValue }

        guard let fetchedAt = Self.sourceDateFormatter.date(
            from: payload.lastUpdated
        ) ?? Self.sourceDateFormatterWithoutFractionalSeconds.date(
            from: payload.lastUpdated
        ) else {
            throw HSReplayArenaJSONParserError.invalidSourceTimestamp(
                payload.lastUpdated
            )
        }
        return HSReplayArenaClassStatsSnapshot(
            fetchedAt: fetchedAt,
            stats: stats
        )
    }

    private func parseLegacyHSReplay(
        data: Data
    ) throws -> HSReplayArenaClassStatsSnapshot {
        let payload = try JSONDecoder().decode(
            LegacyHSReplayPayload.self,
            from: data
        )
        let stats = payload.data.compactMap { entry -> HSReplayArenaClassStat? in
            guard
                let heroClass = HSReplayArenaHeroClass(
                    hsReplayDeckClass: entry.deckClass
                )
            else {
                return nil
            }
            return HSReplayArenaClassStat(
                heroClass: heroClass,
                winRate: entry.winRate,
                pickRate: entry.pickRate,
                draftCount: entry.draftCount ?? entry.gameCount
            )
        }
        guard !stats.isEmpty else {
            throw HSReplayArenaJSONParserError.noSupportedClasses
        }
        return HSReplayArenaClassStatsSnapshot(
            fetchedAt: now(),
            stats: stats
        )
    }

    private static let sourceDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        return formatter
    }()

    private static let sourceDateFormatterWithoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private struct FirestonePayload: Decodable {
    let lastUpdated: String
    let stats: [FirestoneEntry]
}

private struct FirestoneEntry: Decodable {
    let playerClass: String
    let totalGames: Int
    let totalsWins: Int
}

private struct FirestoneAggregate {
    var totalGames = 0
    var totalWins = 0
}

private struct LegacyHSReplayPayload: Decodable {
    let data: [LegacyHSReplayEntry]
}

private struct LegacyHSReplayEntry: Decodable {
    let deckClass: Int
    let winRate: Double
    let pickRate: Double?
    let draftCount: Int?
    let gameCount: Int?

    private enum CodingKeys: String, CodingKey {
        case deckClass = "deck_class"
        case winRate = "win_rate"
        case pickRate = "pick_rate"
        case draftCount = "num_drafts"
        case gameCount = "num_games"
    }
}
