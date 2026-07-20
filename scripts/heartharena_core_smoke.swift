//
// Compile this file together with HearthArenaOverlay/Domain and Data sources.
// It provides executable core checks on machines that only have Command Line Tools.
//

import Foundation

@main
enum HearthArenaCoreSmoke {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw SmokeFailure("Usage: heartharena-core-smoke /path/to/sample.html")
        }

        try testParserFixture(at: CommandLine.arguments[1])
        try testParserRejectsEmptyHTML()
        try testValidatorFailures(at: CommandLine.arguments[1])
        try testNormalization()
        try testResolverAndRanking()
        try testClientResponses()
        try testCache()
        try testStoreRejectsInvalidReplacement(
            at: CommandLine.arguments[1]
        )
        try testStoreThrottle()
        try testStateMachine()
        try testDiagnostics()
        print("heartharena_core_smoke=passed")
    }

    private static func testParserFixture(at path: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let snapshot = try HearthArenaHTMLParser().parse(data: data)
        try require(snapshot.ratings.count == 12, "fixture rating count")
        try require(
            Set(snapshot.ratings.map { $0.heroClass }).count == 12,
            "fixture class count"
        )
        let rating = snapshot.ratings.first { $0.heroClass == .deathKnight }
        try require(rating?.cardId == "CORE_CATA_009", "fixture card ID")
        try require(rating?.cardName == "Death's Advance", "fixture card name")
        try require(rating?.score == 59, "fixture score")
    }

    private static func testNormalization() throws {
        let normalized = HearthArenaTextNormalizer.canonicalCardName(
            "  Death’s   Advance — Test &amp; More  "
        )
        try require(
            normalized == "death's advance - test & more",
            "card-name normalization"
        )
    }

    private static func testParserRejectsEmptyHTML() throws {
        do {
            _ = try HearthArenaHTMLParser().parse(html: "<html></html>")
            throw SmokeFailure("Empty HTML unexpectedly parsed")
        } catch HearthArenaParserError.noRatings {
            return
        }
    }

    private static func testValidatorFailures(at path: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let complete = try HearthArenaHTMLParser().parse(data: data)

        let missingClass = TierListSnapshot(
            fetchedAt: complete.fetchedAt,
            contentHash: "missing-class",
            ratings: complete.ratings.filter { $0.heroClass != .neutral }
        )
        try expectValidationFailure(.missingClasses([.neutral])) {
            try relaxedValidator().validate(missingClass)
        }

        var outOfRangeRatings = complete.ratings
        let first = outOfRangeRatings[0]
        outOfRangeRatings[0] = TierRating(
            heroClass: first.heroClass,
            cardId: first.cardId,
            cardName: first.cardName,
            score: 201
        )
        let outOfRange = TierListSnapshot(
            fetchedAt: complete.fetchedAt,
            contentHash: "out-of-range",
            ratings: outOfRangeRatings
        )
        do {
            try relaxedValidator().validate(outOfRange)
            throw SmokeFailure("Out-of-range score unexpectedly validated")
        } catch TierListValidationError.scoreOutOfRange {
            // Expected.
        }

        let duplicated = TierListSnapshot(
            fetchedAt: complete.fetchedAt,
            contentHash: "duplicated",
            ratings: complete.ratings + [complete.ratings[0]]
        )
        do {
            try relaxedValidator().validate(duplicated)
            throw SmokeFailure("Duplicate rating unexpectedly validated")
        } catch TierListValidationError.tooManyDuplicates {
            // Expected.
        }

        let previous = TierListSnapshot(
            fetchedAt: complete.fetchedAt,
            contentHash: "previous",
            ratings: complete.ratings + complete.ratings
        )
        do {
            try relaxedValidator(
                maximumDuplicateRatio: 1,
                minimumPreviousCoverageRatio: 0.75
            ).validate(complete, previous: previous)
            throw SmokeFailure("Coverage drop unexpectedly validated")
        } catch TierListValidationError.coverageDropped {
            // Expected.
        }
    }

    private static func relaxedValidator(
        maximumDuplicateRatio: Double = 0,
        minimumPreviousCoverageRatio: Double = 0.5
    ) -> TierListValidator {
        TierListValidator(
            policy: TierListValidationPolicy(
                minimumRatingCount: 1,
                minimumRatingsPerClass: 1,
                allowedScoreRange: 0...200,
                maximumDuplicateRatio: maximumDuplicateRatio,
                minimumPreviousCoverageRatio:
                    minimumPreviousCoverageRatio,
                requiredClasses: Set(HearthArenaHeroClass.allCases)
            )
        )
    }

    private static func expectValidationFailure(
        _ expected: TierListValidationError,
        operation: () throws -> Void
    ) throws {
        do {
            try operation()
            throw SmokeFailure("Validation unexpectedly succeeded")
        } catch let error as TierListValidationError {
            try require(error == expected, "expected validation error")
        }
    }

    private static func testResolverAndRanking() throws {
        let snapshot = TierListSnapshot(
            fetchedAt: Date(),
            contentHash: "test",
            ratings: [
                TierRating(heroClass: .mage, cardId: "A", cardName: "A", score: 70),
                TierRating(heroClass: .mage, cardId: "B", cardName: "B", score: 95),
                TierRating(
                    heroClass: .neutral,
                    cardId: "NEUTRAL_001",
                    cardName: "Neutral Card",
                    score: 65
                ),
                TierRating(
                    heroClass: .hunter,
                    cardId: "HUNTER_SHARED",
                    cardName: "Shared Name",
                    score: 88
                ),
                TierRating(
                    heroClass: .mage,
                    cardId: "MAGE_SHARED",
                    cardName: "Shared Name",
                    score: 77
                ),
                TierRating(
                    heroClass: .paladin,
                    cardId: "CS2_093",
                    cardName: "Consecration",
                    score: 83
                )
            ]
        )
        let resolver = CardIdentityResolver(snapshot: snapshot)
        let neutral = resolver.rating(
            for: OfferedCard(
                cardId: "NEUTRAL_001",
                dbfId: 3,
                englishName: "Neutral Card"
            ),
            heroClass: .hunter
        )
        try require(neutral.rating?.score == 65, "neutral fallback")
        try require(neutral.status == .neutralCardId, "neutral fallback status")
        let exactName = resolver.rating(
            for: OfferedCard(
                cardId: "UNKNOWN_ID",
                dbfId: nil,
                englishName: "Shared Name"
            ),
            heroClass: .hunter
        )
        try require(exactName.rating?.score == 88, "class-aware name lookup")
        try require(exactName.status == .exactName, "exact-name status")
        let neutralName = resolver.rating(
            for: OfferedCard(
                cardId: "UNKNOWN_NEUTRAL_ID",
                dbfId: nil,
                englishName: "Neutral Card"
            ),
            heroClass: .warrior
        )
        try require(neutralName.rating?.score == 65, "neutral name fallback")
        try require(neutralName.status == .neutralName, "neutral-name status")
        let coreAlias = resolver.rating(
            for: OfferedCard(
                cardId: "CORE_CS2_093",
                dbfId: nil,
                englishName: ""
            ),
            heroClass: .paladin
        )
        try require(coreAlias.rating?.score == 83, "CORE card-ID alias")
        try require(coreAlias.status == .exactCardId, "CORE alias status")
        let unknown = resolver.rating(
            for: OfferedCard(
                cardId: "UNKNOWN",
                dbfId: nil,
                englishName: "Definitely Missing"
            ),
            heroClass: .mage
        )
        try require(unknown.rating == nil, "unknown card has no score")
        try require(unknown.status == .missing, "unknown card status")

        let offer = ArenaOffer(
            offerVersion: 1,
            draftSlot: 1,
            heroClass: .mage,
            isUnderground: false,
            cards: [
                OfferedCard(cardId: "A", dbfId: 1, englishName: "A"),
                OfferedCard(cardId: "B", dbfId: 2, englishName: "B"),
                OfferedCard(cardId: "C", dbfId: 3, englishName: "C")
            ],
            packages: []
        )
        let rated = resolver.rate(offer).cards
        try require(rated.map { $0.score } == [70, 95, nil], "resolved scores")
        try require(rated.map { $0.rank } == [2, 1, nil], "resolved ranks")

        let packageOffer = ArenaOffer(
            offerVersion: 2,
            draftSlot: 2,
            heroClass: .mage,
            isUnderground: false,
            cards: [],
            packages: [
                Array(offer.cards.prefix(2)),
                Array(offer.cards.prefix(2)),
                Array(offer.cards.prefix(2))
            ]
        )
        let packages = resolver.rate(packageOffer).packages
        try require(packages.count == 3, "three packages resolved")
        try require(
            packages[0].map { $0.score } == [70, 95],
            "individual package scores"
        )
        try require(
            packages[0].allSatisfy { $0.rank == nil },
            "package cards have no aggregate rank"
        )
    }

    private static func testCache() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = TierListCache(
            fileURL: directory.appendingPathComponent("tierlist.json"),
            maxAge: 60
        )
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
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
        try require(state.freshness == .stale, "stale cache state")
        try require(state.snapshot == snapshot, "cache round trip")
        try require(
            cache.loadRefreshAttempt() == fetchedAt,
            "refresh-attempt round trip"
        )
        try require(
            cache.freshness(
                of: snapshot,
                now: fetchedAt.addingTimeInterval(59)
            ) == .fresh,
            "running cache remains fresh before max age"
        )
        try require(
            cache.freshness(
                of: snapshot,
                now: fetchedAt.addingTimeInterval(61)
            ) == .stale,
            "running cache becomes stale after max age"
        )
        try cache.reset()
        try require(cache.loadRefreshAttempt() == nil, "attempt reset")
        try require(cache.load().freshness == .missing, "cache reset")
    }

    private static func testClientResponses() throws {
        let session = makeStubSession()
        let invalidURLResult = try fetch(
            HearthArenaClient(sourceURL: nil, session: session)
        )
        if case .failure(HearthArenaClientError.invalidSourceURL) =
            invalidURLResult
        {
            // Expected.
        } else {
            throw SmokeFailure("Invalid source URL was not rejected")
        }

        StubURLProtocol.responseFactory = {
            try stubResponse(statusCode: 503, data: Data("down".utf8))
        }
        let serverError = try fetch(
            HearthArenaClient(
                sourceURL: URL(string: TierListSnapshot.sourceURL),
                session: session
            )
        )
        if case .failure(HearthArenaClientError.httpStatus(503)) = serverError {
            // Expected.
        } else {
            throw SmokeFailure("HTTP 503 was not rejected")
        }

        StubURLProtocol.responseFactory = {
            try stubResponse(statusCode: 200, data: Data())
        }
        let emptyResponse = try fetch(
            HearthArenaClient(
                sourceURL: URL(string: TierListSnapshot.sourceURL),
                session: session
            )
        )
        if case .failure(HearthArenaClientError.emptyResponse) = emptyResponse {
            // Expected.
        } else {
            throw SmokeFailure("Empty HTTP response was not rejected")
        }

        let expected = Data("<html>ok</html>".utf8)
        StubURLProtocol.responseFactory = {
            try stubResponse(statusCode: 200, data: expected)
        }
        let success = try fetch(
            HearthArenaClient(
                sourceURL: URL(string: TierListSnapshot.sourceURL),
                session: session
            )
        )
        switch success {
        case .success(let data):
            try require(data == expected, "successful HTTP response")
        case .failure(let error):
            throw SmokeFailure(
                "Successful HTTP response failed: \(error.localizedDescription)"
            )
        }
        session.invalidateAndCancel()
        StubURLProtocol.responseFactory = nil
    }

    private static func makeStubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func stubResponse(
        statusCode: Int,
        data: Data
    ) throws -> (HTTPURLResponse, Data) {
        guard
            let url = URL(string: TierListSnapshot.sourceURL),
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/html"]
            )
        else {
            throw SmokeFailure("Unable to build stub HTTP response")
        }
        return (response, data)
    }

    private static func fetch(
        _ client: HearthArenaClient
    ) throws -> Result<Data, Error> {
        let box = FetchResultBox()
        client.fetch { result in
            box.result = result
        }
        let deadline = Date().addingTimeInterval(2)
        while box.result == nil && Date() < deadline {
            _ = RunLoop.current.run(
                mode: .default,
                before: Date().addingTimeInterval(0.01)
            )
        }
        guard let result = box.result else {
            throw SmokeFailure("HTTP client completion timed out")
        }
        return result
    }

    private static func testStateMachine() throws {
        let first = makeOffer(version: 1)
        let second = makeOffer(version: 2)
        var stateMachine = ArenaOfferStateMachine()
        try require(stateMachine.accept(first), "first offer accepted")
        try require(!stateMachine.accept(first), "duplicate offer ignored")
        try require(stateMachine.accept(second), "second offer accepted")
        try require(!stateMachine.markVisible(for: first), "stale offer ignored")
        try require(
            stateMachine.markOffline(for: second),
            "current offer can enter offline state"
        )
        try require(stateMachine.markVisible(for: second), "current offer visible")

        let underground = ArenaOffer(
            offerVersion: second.offerVersion,
            draftSlot: second.draftSlot,
            heroClass: second.heroClass,
            isUnderground: true,
            cards: second.cards,
            packages: second.packages
        )
        try require(
            stateMachine.accept(underground),
            "mode change is a distinct offer"
        )
        stateMachine.choicePicked()
        try require(stateMachine.state == .hidden, "choice hides offer")
        stateMachine.closeDraft()
        try require(stateMachine.state == .idle, "closing draft resets state")
    }

    private static func testDiagnostics() throws {
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
        try require(
            snapshot.currentMatchedCardCount == 2 &&
                snapshot.currentOfferedCardCount == 3,
            "current diagnostic counts"
        )
        try require(
            snapshot.currentMatchCoverage == 2.0 / 3.0,
            "current diagnostic coverage"
        )
        try require(
            snapshot.sessionMatchCoverage == 2.0 / 3.0,
            "session diagnostic coverage"
        )

        diagnostics.update(ratedOffer: ratedOffer)
        snapshot = diagnostics.snapshot()
        try require(
            snapshot.sessionMatchedCardCount == 2 &&
                snapshot.sessionOfferedCardCount == 3,
            "diagnostic rerender is not double-counted"
        )

        try require(
            diagnostics.recordUnknown(card: offer.cards[2]),
            "first unknown card is recorded"
        )
        try require(
            !diagnostics.recordUnknown(card: offer.cards[2]),
            "unknown card is deduplicated"
        )
        diagnostics.clearOffer()
        snapshot = diagnostics.snapshot()
        try require(
            snapshot.currentMatchCoverage == nil &&
                snapshot.sessionMatchCoverage == 2.0 / 3.0,
            "clearing an offer retains session diagnostics"
        )
    }

    private static func testStoreThrottle() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var currentTime = Date(timeIntervalSince1970: 1_700_000_000)
        let fetcher = CountingFetcher()
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

        try waitForRefresh(store)
        try require(fetcher.fetchCount == 1, "first refresh attempted")
        try waitForRefresh(store)
        try require(fetcher.fetchCount == 1, "automatic refresh throttled")

        let restartedFetcher = CountingFetcher()
        let restartedStore = HearthArenaTierListStore(
            client: restartedFetcher,
            parser: HearthArenaHTMLParser(),
            validator: TierListValidator(),
            cache: TierListCache(
                fileURL: directory.appendingPathComponent("tierlist.json")
            ),
            automaticRefreshInterval: 60,
            now: { currentTime }
        )
        try waitForLoad(restartedStore)
        try waitForRefresh(restartedStore)
        try require(
            restartedFetcher.fetchCount == 0,
            "refresh throttle persists across launch"
        )

        currentTime = currentTime.addingTimeInterval(61)
        try waitForRefresh(store)
        try require(fetcher.fetchCount == 2, "refresh resumes after throttle")
    }

    private static func testStoreRejectsInvalidReplacement(
        at path: String
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = TierListCache(
            fileURL: directory.appendingPathComponent("tierlist.json")
        )
        let fixtureData = try Data(contentsOf: URL(fileURLWithPath: path))
        let previous = try HearthArenaHTMLParser().parse(
            data: fixtureData,
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try cache.save(previous)

        let partialHTML = """
        <section id="mage">
          <dl class="card">
            <dt data-card-image="/ONE.webp">One</dt>
            <dd class="score">80</dd>
          </dl>
        </section>
        """
        let store = HearthArenaTierListStore(
            client: ResultFetcher(
                result: .success(Data(partialHTML.utf8))
            ),
            parser: HearthArenaHTMLParser(),
            validator: relaxedValidator(),
            cache: cache
        )
        try waitForLoad(store)
        try waitForRefresh(store, force: true)

        let afterFailure = cache.load().snapshot
        try require(
            afterFailure == previous,
            "invalid replacement keeps previous snapshot"
        )
    }

    private static func waitForLoad(
        _ store: HearthArenaTierListStore
    ) throws {
        let flag = CompletionFlag()
        store.load {
            flag.finished = true
        }
        try waitUntil(flag, description: "asynchronous cache load")
    }

    private static func waitForRefresh(
        _ store: HearthArenaTierListStore,
        force: Bool = false
    ) throws {
        let flag = CompletionFlag()
        store.refreshIfNeeded(force: force) { _ in
            flag.finished = true
        }
        try waitUntil(flag, description: "asynchronous refresh completion")
    }

    private static func waitUntil(
        _ flag: CompletionFlag,
        description: String
    ) throws {
        let deadline = Date().addingTimeInterval(2)
        while !flag.finished && Date() < deadline {
            _ = RunLoop.current.run(
                mode: .default,
                before: Date().addingTimeInterval(0.01)
            )
        }
        try require(flag.finished, description)
    }

    private static func makeOffer(version: Int) -> ArenaOffer {
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

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ description: String
    ) throws {
        guard condition() else {
            throw SmokeFailure("Failed: \(description)")
        }
    }
}

private struct SmokeFailure: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { return message }
}

private final class CountingFetcher: HearthArenaFetching {
    private(set) var fetchCount = 0

    func fetch(completion: @escaping (Result<Data, Error>) -> Void) {
        fetchCount += 1
        completion(.failure(SmokeNetworkFailure.offline))
    }
}

private enum SmokeNetworkFailure: Error {
    case offline
}

private final class CompletionFlag {
    var finished = false
}

private final class FetchResultBox {
    var result: Result<Data, Error>?
}

private final class StubURLProtocol: URLProtocol {
    static var responseFactory: (() throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let responseFactory = Self.responseFactory else {
            client?.urlProtocol(
                self,
                didFailWithError: SmokeFailure(
                    "Stub URL response was not configured"
                )
            )
            return
        }

        do {
            let (response, data) = try responseFactory()
            client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            if !data.isEmpty {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class ResultFetcher: HearthArenaFetching {
    let result: Result<Data, Error>

    init(result: Result<Data, Error>) {
        self.result = result
    }

    func fetch(completion: @escaping (Result<Data, Error>) -> Void) {
        completion(result)
    }
}
