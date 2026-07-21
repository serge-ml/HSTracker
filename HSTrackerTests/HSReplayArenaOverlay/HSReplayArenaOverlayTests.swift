//
//  HSReplayArenaOverlayTests.swift
//  HSTrackerTests
//

import XCTest

#if SWIFT_PACKAGE
@testable import HSReplayArenaCore
#else
@testable import HSTracker
#endif

final class HSReplayArenaOverlayTests: XCTestCase {
    func testParserAggregatesFirestoneHeroPowersByClass() throws {
        let snapshot = try HSReplayArenaJSONParser().parse(
            data: Self.firestoneSampleData
        )

        XCTAssertEqual(
            snapshot.fetchedAt.timeIntervalSince1970,
            1_784_636_772.479,
            accuracy: 0.001
        )
        XCTAssertEqual(snapshot.stats.count, 3)

        let mage = try XCTUnwrap(
            snapshot.stats.first { $0.heroClass == .mage }
        )
        XCTAssertEqual(mage.draftCount, 250)
        XCTAssertEqual(mage.winRate, 60, accuracy: 0.001)
        XCTAssertEqual(mage.pickRate ?? -1, 50, accuracy: 0.001)
    }

    func testParserMapsHSReplayDeckClassesAndOptionalCounts() throws {
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let parser = HSReplayArenaJSONParser(now: { fetchedAt })
        let snapshot = try parser.parse(data: Self.sampleData)

        XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
        XCTAssertEqual(snapshot.stats.count, 11)

        let deathKnight = try XCTUnwrap(
            snapshot.stats.first { $0.heroClass == .deathKnight }
        )
        XCTAssertEqual(deathKnight.winRate, 51.2)
        XCTAssertEqual(deathKnight.pickRate, 10.4)
        XCTAssertEqual(deathKnight.draftCount, 1_204)

        let demonHunter = try XCTUnwrap(
            snapshot.stats.first { $0.heroClass == .demonHunter }
        )
        XCTAssertEqual(demonHunter.draftCount, 998)
    }

    func testParserIgnoresUnknownDeckClasses() throws {
        let data = Data(
            """
            {
              "data": [
                {"deck_class": 99, "win_rate": 99.0},
                {"deck_class": 4, "win_rate": 52.1},
                {"deck_class": 5, "win_rate": 51.1},
                {"deck_class": 6, "win_rate": 50.1}
              ]
            }
            """.utf8
        )
        let snapshot = try HSReplayArenaJSONParser().parse(data: data)
        XCTAssertEqual(snapshot.stats.count, 3)
        XCTAssertFalse(
            snapshot.stats.contains { $0.heroClass.rawValue == "99" }
        )
    }

    func testValidatorRejectsDuplicateAndOutOfRangeStats() throws {
        let valid = try HSReplayArenaJSONParser().parse(data: Self.sampleData)
        XCTAssertNoThrow(
            try HSReplayArenaClassStatsValidator().validate(valid)
        )

        let duplicate = HSReplayArenaClassStatsSnapshot(
            fetchedAt: Date(),
            stats: [
                valid.stats[0],
                valid.stats[0],
                valid.stats[1]
            ]
        )
        XCTAssertThrowsError(
            try HSReplayArenaClassStatsValidator().validate(duplicate)
        )

        let invalid = HSReplayArenaClassStatsSnapshot(
            fetchedAt: Date(),
            stats: [
                HSReplayArenaClassStat(
                    heroClass: .mage,
                    winRate: 101,
                    pickRate: nil,
                    draftCount: nil
                ),
                valid.stats[1],
                valid.stats[2]
            ]
        )
        XCTAssertThrowsError(
            try HSReplayArenaClassStatsValidator().validate(invalid)
        )
    }

    func testCacheIsIndependentAndBecomesStale() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let fileURL = directory.appendingPathComponent(
            "class-winrates-v1.json"
        )
        let cache = HSReplayArenaClassStatsCache(
            fileURL: fileURL,
            maxAge: 60
        )
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let parsed = try HSReplayArenaJSONParser(
            now: { fetchedAt }
        ).parse(data: Self.sampleData)

        try cache.save(parsed)

        let fresh = cache.load(now: fetchedAt.addingTimeInterval(60))
        XCTAssertEqual(fresh.freshness, .fresh)
        XCTAssertEqual(fresh.snapshot, parsed)

        let stale = cache.load(now: fetchedAt.addingTimeInterval(61))
        XCTAssertEqual(stale.freshness, .stale)
        XCTAssertEqual(stale.snapshot?.stats.count, 11)
    }

    func testDeckClassMappingCoversAllPlayableClasses() {
        let mapped = Set(
            [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 14].compactMap {
                HSReplayArenaHeroClass(hsReplayDeckClass: $0)
            }
        )
        XCTAssertEqual(mapped, Set(HSReplayArenaHeroClass.allCases))
        XCTAssertNil(
            HSReplayArenaHeroClass(hsReplayDeckClass: 12)
        )
    }

    private static let sampleData = Data(
        """
        {
          "data": [
            {"deck_class": 1, "win_rate": 51.2, "pick_rate": 10.4, "num_drafts": 1204},
            {"deck_class": 2, "win_rate": 48.3, "pick_rate": 8.1, "num_drafts": 901},
            {"deck_class": 3, "win_rate": 52.5, "pick_rate": 11.0, "num_drafts": 1322},
            {"deck_class": 4, "win_rate": 53.0, "pick_rate": 13.5, "num_drafts": 1550},
            {"deck_class": 5, "win_rate": 55.1, "pick_rate": 15.2, "num_drafts": 1701},
            {"deck_class": 6, "win_rate": 49.7, "pick_rate": 8.9, "num_drafts": 999},
            {"deck_class": 7, "win_rate": 50.8, "pick_rate": 9.7, "num_drafts": 1102},
            {"deck_class": 8, "win_rate": 47.9, "pick_rate": 6.4, "num_drafts": 744},
            {"deck_class": 9, "win_rate": 50.2, "pick_rate": 7.8, "num_drafts": 850},
            {"deck_class": 10, "win_rate": 46.5, "pick_rate": 4.6, "num_drafts": 510},
            {"deck_class": 14, "win_rate": 49.1, "pick_rate": 7.1, "num_games": 998}
          ],
          "metadata": {"is_dual_class": false},
          "selected_params": ["BGT_UNDERGROUND_ARENA", "CURRENT_PATCH"]
        }
        """.utf8
    )

    private static let firestoneSampleData = Data(
        """
        {
          "lastUpdated": "2026-07-21T12:26:12.479Z",
          "stats": [
            {"playerClass": "mage", "totalGames": 200, "totalsWins": 118},
            {"playerClass": "mage", "totalGames": 50, "totalsWins": 32},
            {"playerClass": "priest", "totalGames": 150, "totalsWins": 75},
            {"playerClass": "rogue", "totalGames": 100, "totalsWins": 44},
            {"playerClass": "neutral", "totalGames": 999, "totalsWins": 999}
          ]
        }
        """.utf8
    )
}
