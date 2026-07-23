//
//  ReplayUploadTests.swift
//  HSTracker
//
//  Created by Istvan Fehervari on 09/05/2017.
//  Copyright © 2017 Benjamin Michotte. All rights reserved.
//

import XCTest

@testable import HSTracker

class ReplayUploadTests: HSTrackerTests {
	
	override func setUp() {
		super.setUp()
	}
	
	override func tearDown() {
		super.tearDown()
	}
	
	func testMetadataEncoding() throws {
		let player = UploadMetaData.Player()
		
//		player.rank = 1
//		player.legendRank = 0
		player.stars = 1
		player.wins = 20
		player.losses = 10
		player.deck = ["one", "two"]
		player.deck_id = 12345
		player.cardback = 3
		
		let data = try JSONEncoder().encode(player)
		let wrappedPlayer = try XCTUnwrap(
			try JSONSerialization.jsonObject(with: data) as? [String: Any]
		)
		
//		XCTAssert(wrappedPlayer["rank"] as! Int == player.rank!)
		XCTAssertEqual(wrappedPlayer["cardback"] as? Int, player.cardback)
		XCTAssertEqual(wrappedPlayer["deck"] as? [String], player.deck)
	}

    func testHSGuruPayloadUsesPublicAPIFieldNames() throws {
        let payload = makeHSGuruPayload()
        let request = try HSGuruUploader.makeRequest(payload: payload)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let player = try XCTUnwrap(json["player"] as? [String: Any])
        let playedCards = try XCTUnwrap(player["cards_with_created_by"] as? [[String: Any]])

        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url, HSGuruUploader.endpoint)
        XCTAssertEqual(json["game_id"] as? String, payload.gameId)
        XCTAssertEqual(json["duration_seconds"] as? Int, payload.durationSeconds)
        XCTAssertEqual(json["source"] as? String, HSGuruGamePayload.source)
        XCTAssertNil(json["replay_url"])
        XCTAssertEqual(player["battletag"] as? String, "Player#1234")
        XCTAssertEqual(player["deckcode"] as? String, "AAECA-test")
        XCTAssertEqual(playedCards.first?["createdBy"] as? String, HSGuruGamePayload.source)
    }

    func testHSGuruReplayUpdateKeepsGameIdentity() {
        let payload = makeHSGuruPayload()
        let updated = payload.adding(replayURL: "https://hsreplay.net/replay/example")

        XCTAssertEqual(updated.gameId, payload.gameId)
        XCTAssertEqual(updated.player, payload.player)
        XCTAssertEqual(updated.replayURL, "https://hsreplay.net/replay/example")
    }

    func testHSGuruOutboxPersistsAndDeduplicatesPayloads() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hsguru-tests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("outbox.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let payload = makeHSGuruPayload()
        let store = HSGuruOutboxStore(fileURL: fileURL)
        XCTAssertTrue(store.enqueue(payload))
        XCTAssertFalse(store.enqueue(payload))
        XCTAssertEqual(store.entries.count, 1)

        let updated = payload.adding(replayURL: "https://hsreplay.net/replay/example")
        XCTAssertTrue(store.enqueue(updated))

        let reloaded = HSGuruOutboxStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.entries.map(\.payload), [payload, updated])
    }

    private func makeHSGuruPayload() -> HSGuruGamePayload {
        let player = HSGuruPlayerPayload(
            battleTag: "Player#1234",
            rank: 5,
            legendRank: nil,
            deckcode: "AAECA-test",
            playerClass: "MAGE",
            cardsBeforeMulligan: [HSGuruCardReference(cardId: "CARD_001", cardDbfId: 1)],
            cardsInHandAfterMulligan: [HSGuruCardReference(cardId: "CARD_001", cardDbfId: 1)],
            cardsDrawnFromInitialDeck: [HSGuruDrawnCard(cardId: "CARD_002", cardDbfId: 2, turn: 1)],
            cardsPlayed: [HSGuruPlayedCard(cardId: "CARD_003", turn: 2, createdBy: HSGuruGamePayload.source)]
        )
        let opponent = HSGuruPlayerPayload(
            battleTag: nil,
            rank: nil,
            legendRank: nil,
            deckcode: nil,
            playerClass: "WARRIOR",
            cardsBeforeMulligan: nil,
            cardsInHandAfterMulligan: nil,
            cardsDrawnFromInitialDeck: nil,
            cardsPlayed: nil
        )
        return HSGuruGamePayload(
            gameId: "game-123",
            gameType: GameType.gt_ranked.rawValue,
            format: FormatType.ft_standard.rawValue,
            result: "WIN",
            region: "REGION_EU",
            durationSeconds: 480,
            turns: 8,
            replayURL: nil,
            mode: GameMode.ranked.rawValue,
            playerHasCoin: false,
            source: HSGuruGamePayload.source,
            sourceVersion: "test",
            player: player,
            opponent: opponent
        )
    }
}
