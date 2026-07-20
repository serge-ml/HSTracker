//
//  HearthArenaOverlayTests.swift
//  HSTrackerTests
//

import XCTest

#if SWIFT_PACKAGE
@testable import HearthArenaCore
#else
@testable import HSTracker
#endif

final class HearthArenaOverlayTests: XCTestCase {
    func testParserExtractsAllClassesCardIdsEntitiesAndScores() throws {
        let snapshot = try fixtureSnapshot()

        XCTAssertEqual(snapshot.ratings.count, HearthArenaHeroClass.allCases.count)
        XCTAssertEqual(Set(snapshot.ratings.map { $0.heroClass }).count, 12)

        let deathKnight = try XCTUnwrap(
            snapshot.ratings.first { $0.heroClass == .deathKnight }
        )
        XCTAssertEqual(deathKnight.cardId, "CORE_CATA_009")
        XCTAssertEqual(deathKnight.cardName, "Death's Advance")
        XCTAssertEqual(deathKnight.score, 59)
    }

    func testValidatorAcceptsCompleteFixtureWithRelaxedCountPolicy() throws {
        let snapshot = try fixtureSnapshot()
        let validator = TierListValidator(
            policy: TierListValidationPolicy(
                minimumRatingCount: 12,
                minimumRatingsPerClass: 1,
                allowedScoreRange: 0...200,
                maximumDuplicateRatio: 0,
                minimumPreviousCoverageRatio: 0.5,
                requiredClasses: Set(HearthArenaHeroClass.allCases)
            )
        )

        XCTAssertNoThrow(try validator.validate(snapshot))
    }

    func testNameNormalizationHandlesEntitiesTypographyAndWhitespace() {
        let value = "  Death’s   Advance — Test &amp; More  "
        XCTAssertEqual(
            HearthArenaTextNormalizer.canonicalCardName(value),
            "death's advance - test & more"
        )
    }

    func testResolverPrefersExactCardIdThenUsesNeutralFallback() {
        let snapshot = TierListSnapshot(
            fetchedAt: Date(),
            contentHash: "test",
            ratings: [
                TierRating(
                    heroClass: .mage,
                    cardId: "MAGE_001",
                    cardName: "Mage Card",
                    score: 95
                ),
                TierRating(
                    heroClass: .neutral,
                    cardId: "NEUTRAL_001",
                    cardName: "Neutral Card",
                    score: 70
                )
            ]
        )
        let resolver = CardIdentityResolver(snapshot: snapshot)

        let exact = resolver.rating(
            for: OfferedCard(
                cardId: "mage_001",
                dbfId: 1,
                englishName: "Wrong Name"
            ),
            heroClass: .mage
        )
        XCTAssertEqual(exact.rating?.score, 95)
        XCTAssertEqual(exact.status, .exactCardId)

        let neutral = resolver.rating(
            for: OfferedCard(
                cardId: "NEUTRAL_001",
                dbfId: 2,
                englishName: "Neutral Card"
            ),
            heroClass: .hunter
        )
        XCTAssertEqual(neutral.rating?.score, 70)
        XCTAssertEqual(neutral.status, .neutralCardId)
    }

    func testResolverMatchesCoreAndVanillaCardIdAliases() {
        let snapshot = TierListSnapshot(
            fetchedAt: Date(),
            contentHash: "test",
            ratings: [
                TierRating(
                    heroClass: .paladin,
                    cardId: "CS2_093",
                    cardName: "Consecration",
                    score: 83
                ),
                TierRating(
                    heroClass: .mage,
                    cardId: "CORE_CS2_029",
                    cardName: "Fireball",
                    score: 91
                )
            ]
        )
        let resolver = CardIdentityResolver(snapshot: snapshot)

        let core = resolver.rating(
            for: OfferedCard(
                cardId: "CORE_CS2_093",
                dbfId: nil,
                englishName: ""
            ),
            heroClass: .paladin
        )
        XCTAssertEqual(core.rating?.score, 83)
        XCTAssertEqual(core.status, .exactCardId)

        let vanilla = resolver.rating(
            for: OfferedCard(
                cardId: "VAN_CS2_029",
                dbfId: nil,
                englishName: ""
            ),
            heroClass: .mage
        )
        XCTAssertEqual(vanilla.rating?.score, 91)
        XCTAssertEqual(vanilla.status, .exactCardId)
    }

    func testResolverMatchesReprintByEnglishName() {
        let snapshot = TierListSnapshot(
            fetchedAt: Date(),
            contentHash: "test",
            ratings: [
                TierRating(
                    heroClass: .paladin,
                    cardId: "WON_045",
                    cardName: "Ivory Knight",
                    score: 90
                )
            ]
        )
        let result = CardIdentityResolver(snapshot: snapshot).rating(
            for: OfferedCard(
                cardId: "CORE_KAR_057",
                dbfId: 130821,
                englishName: "Ivory Knight"
            ),
            heroClass: .paladin
        )

        XCTAssertEqual(result.rating?.score, 90)
        XCTAssertEqual(result.status, .exactName)
    }

    func testResolverRanksThreeKnownCardsAndLeavesUnknownWithoutRank() {
        let snapshot = TierListSnapshot(
            fetchedAt: Date(),
            contentHash: "test",
            ratings: [
                TierRating(heroClass: .mage, cardId: "A", cardName: "A", score: 70),
                TierRating(heroClass: .mage, cardId: "B", cardName: "B", score: 95)
            ]
        )
        let offer = ArenaOffer(
            offerVersion: 7,
            draftSlot: 3,
            heroClass: .mage,
            isUnderground: false,
            cards: [
                OfferedCard(cardId: "A", dbfId: 1, englishName: "A"),
                OfferedCard(cardId: "B", dbfId: 2, englishName: "B"),
                OfferedCard(cardId: "C", dbfId: 3, englishName: "C")
            ],
            packages: []
        )

        let cards = CardIdentityResolver(snapshot: snapshot).rate(offer).cards
        XCTAssertEqual(cards.map { $0.score }, [70, 95, nil])
        XCTAssertEqual(cards.map { $0.rank }, [2, 1, nil])
    }

    func testPackageCardsHaveIndividualScoresWithoutRanks() {
        let snapshot = TierListSnapshot(
            fetchedAt: Date(),
            contentHash: "test",
            ratings: [
                TierRating(heroClass: .mage, cardId: "A", cardName: "A", score: 70),
                TierRating(heroClass: .mage, cardId: "B", cardName: "B", score: 95)
            ]
        )
        let package = [
            OfferedCard(cardId: "A", dbfId: 1, englishName: "A"),
            OfferedCard(cardId: "B", dbfId: 2, englishName: "B")
        ]
        let offer = ArenaOffer(
            offerVersion: 8,
            draftSlot: 4,
            heroClass: .mage,
            isUnderground: false,
            cards: [],
            packages: [package, package, package]
        )

        let rated = CardIdentityResolver(snapshot: snapshot).rate(offer)
        XCTAssertEqual(rated.packages.count, 3)
        XCTAssertEqual(rated.packages[0].map { $0.score }, [70, 95])
        XCTAssertEqual(rated.packages[0].map { $0.rank }, [nil, nil])
    }

    func testDeckEditRanksFiveDiscardedCards() {
        let snapshot = TierListSnapshot(
            fetchedAt: Date(),
            contentHash: "test",
            ratings: [
                TierRating(
                    heroClass: .mage,
                    cardId: "CUT_A",
                    cardName: "Cut A",
                    score: 42
                ),
                TierRating(
                    heroClass: .mage,
                    cardId: "CUT_B",
                    cardName: "Cut B",
                    score: 93
                )
            ]
        )
        let cutA = OfferedCard(
            cardId: "CUT_A",
            dbfId: 2,
            englishName: "Cut A"
        )
        let cutB = OfferedCard(
            cardId: "CUT_B",
            dbfId: 3,
            englishName: "Cut B"
        )
        let missing = OfferedCard(
            cardId: "MISSING",
            dbfId: 4,
            englishName: "Missing"
        )
        let edit = ArenaDeckEdit(
            heroClass: .mage,
            isUnderground: true,
            discardedCards: [cutA, cutB, missing, cutA, cutB]
        )

        let rated = CardIdentityResolver(snapshot: snapshot).rate(edit)

        XCTAssertEqual(
            rated.discardedCards.map { $0.score },
            [42, 93, nil, 42, 93]
        )
        XCTAssertEqual(
            rated.discardedCards.map { $0.rank },
            [3, 1, nil, 4, 2]
        )
    }

    func testDiscardTrackerFollowsSwappedSlotsAndDuplicates() throws {
        let originalDeck =
            Array(repeating: "DECK_A", count: 2) +
            Array(repeating: "DECK_B", count: 28)
        let initialDiscard = ["CUT_A", "CUT_B", "CUT_C", "CUT_D", "CUT_E"]
        var tracker = try XCTUnwrap(
            ArenaDiscardTracker(
                originalDeckCardIds: originalDeck,
                initialDiscardCardIds: initialDiscard,
                currentDeckCardIds: originalDeck
            )
        )

        var currentDeck = originalDeck
        currentDeck.removeFirst()
        currentDeck.append("CUT_B")
        XCTAssertTrue(tracker.update(currentDeckCardIds: currentDeck))
        XCTAssertEqual(
            tracker.discardedCardIds,
            ["CUT_A", "DECK_A", "CUT_C", "CUT_D", "CUT_E"]
        )

        currentDeck.removeFirst()
        currentDeck.append("CUT_D")
        XCTAssertTrue(tracker.update(currentDeckCardIds: currentDeck))
        XCTAssertEqual(
            tracker.discardedCardIds,
            ["CUT_A", "DECK_A", "CUT_C", "DECK_A", "CUT_E"]
        )

        currentDeck.removeLast()
        currentDeck.append("DECK_A")
        XCTAssertTrue(tracker.update(currentDeckCardIds: currentDeck))
        XCTAssertEqual(
            tracker.discardedCardIds,
            ["CUT_A", "DECK_A", "CUT_C", "CUT_D", "CUT_E"]
        )
    }

    func testCacheReportsStaleSnapshotAndRoundTripsExactDate() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = TierListCache(
            fileURL: directory.appendingPathComponent("tierlist.json"),
            maxAge: 60
        )
        let fetchedAt = Date(
            timeIntervalSinceReferenceDate: 806_123_456.123_456_7
        )
        let snapshot = TierListSnapshot(
            fetchedAt: fetchedAt,
            contentHash: "test",
            ratings: [
                TierRating(heroClass: .mage, cardId: "A", cardName: "A", score: 70)
            ]
        )

        try cache.save(snapshot)
        try cache.saveRefreshAttempt(fetchedAt)
        let state = cache.load(now: fetchedAt.addingTimeInterval(61))

        XCTAssertEqual(state.freshness, .stale)
        XCTAssertEqual(state.snapshot, snapshot)
        XCTAssertEqual(cache.loadRefreshAttempt(), fetchedAt)
        XCTAssertEqual(
            cache.freshness(of: snapshot, now: fetchedAt.addingTimeInterval(59)),
            .fresh
        )
        XCTAssertEqual(
            cache.freshness(of: snapshot, now: fetchedAt.addingTimeInterval(61)),
            .stale
        )
        try cache.reset()
        XCTAssertNil(cache.loadRefreshAttempt())
        XCTAssertEqual(cache.load().freshness, .missing)
    }

    func testCacheDecoderReadsLegacyISODate() throws {
        let data = Data(#"{"date":"2023-11-14T22:13:20Z"}"#.utf8)
        let decoded = try TierListCache.decoder.decode(
            LegacyDateContainer.self,
            from: data
        )

        XCTAssertEqual(
            decoded.date,
            Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    func testCacheDecoderReadsLegacyUnixTimestamp() throws {
        let data = Data(#"{"date":1700000000.125}"#.utf8)
        let decoded = try TierListCache.decoder.decode(
            LegacyDateContainer.self,
            from: data
        )

        XCTAssertEqual(
            decoded.date,
            Date(timeIntervalSince1970: 1_700_000_000.125)
        )
    }

    func testOfferStateMachineDeduplicatesAndIgnoresStaleVisibility() {
        let first = makeOffer(version: 1)
        let second = makeOffer(version: 2)
        var stateMachine = ArenaOfferStateMachine()

        XCTAssertTrue(stateMachine.accept(first))
        XCTAssertFalse(stateMachine.accept(first))
        XCTAssertTrue(stateMachine.accept(second))
        XCTAssertFalse(stateMachine.markVisible(for: first))
        XCTAssertTrue(stateMachine.markOffline(for: second))
        XCTAssertTrue(stateMachine.markVisible(for: second))

        let underground = ArenaOffer(
            offerVersion: second.offerVersion,
            draftSlot: second.draftSlot,
            heroClass: second.heroClass,
            isUnderground: true,
            cards: second.cards,
            packages: second.packages
        )
        XCTAssertTrue(stateMachine.accept(underground))

        stateMachine.choicePicked()
        XCTAssertEqual(stateMachine.state, .hidden)
        stateMachine.closeDraft()
        XCTAssertEqual(stateMachine.state, .idle)
    }

    func testDiagnosticsReportsCurrentAndSessionMatchCoverage() {
        let diagnostics = HearthArenaDiagnostics()
        let offer = makeOffer(version: 1)
        diagnostics.update(offer: offer)
        let ratedOffer = ArenaRatedOffer(
            offer: offer,
            cards: [
                ArenaRatedCard(
                    card: offer.cards[0],
                    score: 80,
                    rank: 1,
                    matchStatus: .exactCardId
                ),
                ArenaRatedCard(
                    card: offer.cards[1],
                    score: 70,
                    rank: 2,
                    matchStatus: .exactCardId
                ),
                ArenaRatedCard(
                    card: offer.cards[2],
                    score: nil,
                    rank: nil,
                    matchStatus: .missing
                )
            ],
            packages: []
        )
        diagnostics.update(ratedOffer: ratedOffer)

        var snapshot = diagnostics.snapshot()
        XCTAssertEqual(snapshot.currentMatchedCardCount, 2)
        XCTAssertEqual(snapshot.currentOfferedCardCount, 3)
        XCTAssertEqual(snapshot.currentMatchCoverage, 2.0 / 3.0)
        XCTAssertEqual(snapshot.sessionMatchCoverage, 2.0 / 3.0)

        diagnostics.update(ratedOffer: ratedOffer)
        snapshot = diagnostics.snapshot()
        XCTAssertEqual(snapshot.sessionMatchedCardCount, 2)
        XCTAssertEqual(snapshot.sessionOfferedCardCount, 3)

        diagnostics.clearOffer()
        snapshot = diagnostics.snapshot()
        XCTAssertNil(snapshot.currentMatchCoverage)
        XCTAssertEqual(snapshot.sessionMatchCoverage, 2.0 / 3.0)
    }

    func testStoreKeepsPreviousSnapshotWhenNewHTMLIsInvalid() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = TierListCache(
            fileURL: directory.appendingPathComponent("tierlist.json")
        )
        let previous = try fixtureSnapshot()
        try cache.save(previous)
        let validator = TierListValidator(
            policy: TierListValidationPolicy(
                minimumRatingCount: 12,
                minimumRatingsPerClass: 1,
                allowedScoreRange: 0...200,
                maximumDuplicateRatio: 0,
                minimumPreviousCoverageRatio: 0.5,
                requiredClasses: Set(HearthArenaHeroClass.allCases)
            )
        )
        let store = HearthArenaTierListStore(
            client: StubFetcher(result: .success(Data("<html></html>".utf8))),
            parser: HearthArenaHTMLParser(),
            validator: validator,
            cache: cache
        )

        let loadExpectation = expectation(description: "cache loaded")
        store.load {
            loadExpectation.fulfill()
        }
        wait(for: [loadExpectation], timeout: 2)

        let refreshExpectation = expectation(description: "refresh rejected")
        store.refreshIfNeeded(force: true) { result in
            if case .success = result {
                XCTFail("Invalid HTML must not replace the valid snapshot")
            }
            refreshExpectation.fulfill()
        }
        wait(for: [refreshExpectation], timeout: 2)

        let snapshotExpectation = expectation(description: "snapshot read")
        store.currentSnapshot { snapshot in
            XCTAssertEqual(snapshot, previous)
            snapshotExpectation.fulfill()
        }
        wait(for: [snapshotExpectation], timeout: 2)
    }

    func testAutomaticRefreshIsThrottledAfterFailure() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var currentTime = Date(timeIntervalSince1970: 1_700_000_000)
        let fetcher = StubFetcher(result: .failure(StubFailure.offline))
        let store = HearthArenaTierListStore(
            client: fetcher,
            parser: HearthArenaHTMLParser(),
            validator: TierListValidator(),
            cache: TierListCache(
                fileURL: directory.appendingPathComponent("tierlist.json")
            ),
            automaticRefreshInterval: 60,
            now: { currentTime }
        )

        let first = expectation(description: "first refresh")
        store.refreshIfNeeded { _ in first.fulfill() }
        wait(for: [first], timeout: 2)
        XCTAssertEqual(fetcher.fetchCount, 1)

        let throttled = expectation(description: "throttled refresh")
        store.refreshIfNeeded { _ in throttled.fulfill() }
        wait(for: [throttled], timeout: 2)
        XCTAssertEqual(fetcher.fetchCount, 1)

        currentTime = currentTime.addingTimeInterval(61)
        let afterWindow = expectation(description: "refresh after window")
        store.refreshIfNeeded { _ in afterWindow.fulfill() }
        wait(for: [afterWindow], timeout: 2)
        XCTAssertEqual(fetcher.fetchCount, 2)
    }

    private func fixtureSnapshot() throws -> TierListSnapshot {
        #if SWIFT_PACKAGE
        let fixtureBundle = Bundle.module
        #else
        let fixtureBundle = Bundle(for: type(of: self))
        #endif
        let url = try XCTUnwrap(
            fixtureBundle.url(
                forResource: "heartharena-tierlist-sample",
                withExtension: "html"
            )
        )
        return try HearthArenaHTMLParser().parse(data: Data(contentsOf: url))
    }

    private func makeOffer(version: Int) -> ArenaOffer {
        return ArenaOffer(
            offerVersion: version,
            draftSlot: version,
            heroClass: .mage,
            isUnderground: false,
            cards: [
                OfferedCard(cardId: "A", dbfId: 1, englishName: "A"),
                OfferedCard(cardId: "B", dbfId: 2, englishName: "B"),
                OfferedCard(cardId: "C", dbfId: 3, englishName: "C")
            ],
            packages: []
        )
    }
}

private final class StubFetcher: HearthArenaFetching {
    let result: Result<Data, Error>
    private(set) var fetchCount = 0

    init(result: Result<Data, Error>) {
        self.result = result
    }

    func fetch(completion: @escaping (Result<Data, Error>) -> Void) {
        fetchCount += 1
        completion(result)
    }
}

private enum StubFailure: Error {
    case offline
}

private struct LegacyDateContainer: Decodable {
    let date: Date
}
