//
//  HSGuru.swift
//  HSTracker
//
//  Sends completed game summaries to HS Guru when explicitly enabled by the user.
//

import Foundation

struct HSGuruCardReference: Codable, Equatable {
    let cardId: String
    let cardDbfId: Int?

    private enum CodingKeys: String, CodingKey {
        case cardId = "card_id"
        case cardDbfId = "card_dbf_id"
    }
}

struct HSGuruDrawnCard: Codable, Equatable {
    let cardId: String
    let cardDbfId: Int?
    let turn: Int

    private enum CodingKeys: String, CodingKey {
        case cardId = "card_id"
        case cardDbfId = "card_dbf_id"
        case turn
    }
}

struct HSGuruPlayedCard: Codable, Equatable {
    let cardId: String
    let turn: Int
    let createdBy: String?
}

struct HSGuruPlayerPayload: Codable, Equatable {
    let battleTag: String?
    let rank: Int?
    let legendRank: Int?
    let deckcode: String?
    let playerClass: String
    let cardsBeforeMulligan: [HSGuruCardReference]?
    let cardsInHandAfterMulligan: [HSGuruCardReference]?
    let cardsDrawnFromInitialDeck: [HSGuruDrawnCard]?
    let cardsPlayed: [HSGuruPlayedCard]?

    private enum CodingKeys: String, CodingKey {
        case battleTag = "battletag"
        case rank
        case legendRank = "legend_rank"
        case deckcode
        case playerClass = "class"
        case cardsBeforeMulligan = "cards_before_mulligan"
        case cardsInHandAfterMulligan = "cards_in_hand_after_mulligan"
        case cardsDrawnFromInitialDeck = "cards_drawn_from_initial_deck"
        case cardsPlayed = "cards_with_created_by"
    }
}

struct HSGuruGamePayload: Codable, Equatable {
    static let source = "hstracker"

    let gameId: String
    let gameType: Int
    let format: Int?
    let result: String
    let region: String
    let durationSeconds: Int
    let turns: Int
    let replayURL: String?
    let mode: Int
    let playerHasCoin: Bool
    let source: String
    let sourceVersion: String
    let player: HSGuruPlayerPayload
    let opponent: HSGuruPlayerPayload

    private enum CodingKeys: String, CodingKey {
        case gameId = "game_id"
        case gameType = "game_type"
        case format
        case result
        case region
        case durationSeconds = "duration_seconds"
        case turns
        case replayURL = "replay_url"
        case mode
        case playerHasCoin = "player_has_coin"
        case source
        case sourceVersion = "source_version"
        case player
        case opponent
    }

    func adding(replayURL: String) -> HSGuruGamePayload {
        return HSGuruGamePayload(
            gameId: gameId,
            gameType: gameType,
            format: format,
            result: result,
            region: region,
            durationSeconds: durationSeconds,
            turns: turns,
            replayURL: replayURL,
            mode: mode,
            playerHasCoin: playerHasCoin,
            source: source,
            sourceVersion: sourceVersion,
            player: player,
            opponent: opponent
        )
    }
}

struct HSGuruOutboxEntry: Codable, Equatable {
    let id: UUID
    let payload: HSGuruGamePayload
    var attemptCount: Int
    var nextAttemptAt: Date?

    init(payload: HSGuruGamePayload) {
        id = UUID()
        self.payload = payload
        attemptCount = 0
        nextAttemptAt = nil
    }
}

final class HSGuruOutboxStore {
    private let fileURL: URL
    private let maximumEntryCount: Int
    private(set) var entries: [HSGuruOutboxEntry]

    init(fileURL: URL, maximumEntryCount: Int = 200) {
        self.fileURL = fileURL
        self.maximumEntryCount = maximumEntryCount
        entries = []
        load()
    }

    @discardableResult
    func enqueue(_ payload: HSGuruGamePayload) -> Bool {
        guard !entries.contains(where: { $0.payload == payload }) else {
            return false
        }

        entries.append(HSGuruOutboxEntry(payload: payload))
        if entries.count > maximumEntryCount {
            entries.removeFirst(entries.count - maximumEntryCount)
        }
        persist()
        return true
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    func update(_ entry: HSGuruOutboxEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else {
            return
        }
        entries[index] = entry
        persist()
    }

    func removeAll() {
        entries.removeAll()
        persist()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            entries = try JSONDecoder().decode([HSGuruOutboxEntry].self, from: data)
        } catch {
            logger.error("Could not load HS Guru upload queue: \(error)")
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Could not persist HS Guru upload queue: \(error)")
        }
    }
}

final class HSGuruUploader {
    static let shared = HSGuruUploader()
    static let endpoint = URL(string: "https://www.hsguru.com/api/dt/game?source=hstracker")!

    private let stateQueue = DispatchQueue(label: "net.hearthsim.hstracker.hsguru-uploader")
    private let session: URLSession
    private let store: HSGuruOutboxStore
    private let endpointURL: URL
    private var currentTask: URLSessionDataTask?
    private var scheduledRetry: DispatchWorkItem?

    init(
        session: URLSession = .shared,
        store: HSGuruOutboxStore = HSGuruOutboxStore(
            fileURL: Paths.HSTracker.appendingPathComponent("hsguru-upload-queue.json")
        ),
        endpointURL: URL = HSGuruUploader.endpoint
    ) {
        self.session = session
        self.store = store
        self.endpointURL = endpointURL
    }

    func submit(_ payload: HSGuruGamePayload) {
        stateQueue.async {
            guard Settings.hsGuruUploadMatches else {
                return
            }
            _ = self.store.enqueue(payload)
            self.drain()
        }
    }

    func resumePendingUploads() {
        stateQueue.async {
            self.drain()
        }
    }

    func cancelAndClearPendingUploads() {
        stateQueue.async {
            self.scheduledRetry?.cancel()
            self.scheduledRetry = nil
            self.currentTask?.cancel()
            self.currentTask = nil
            self.store.removeAll()
        }
    }

    static func makeRequest(payload: HSGuruGamePayload, endpointURL: URL = endpoint) throws -> URLRequest {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "PUT"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Version.buildName, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    private func drain() {
        dispatchPrecondition(condition: .onQueue(stateQueue))

        guard Settings.hsGuruUploadMatches, currentTask == nil, scheduledRetry == nil,
              let entry = store.entries.first else {
            return
        }

        if let nextAttemptAt = entry.nextAttemptAt, nextAttemptAt > Date() {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.scheduledRetry = nil
                self.drain()
            }
            scheduledRetry = workItem
            stateQueue.asyncAfter(deadline: .now() + nextAttemptAt.timeIntervalSinceNow, execute: workItem)
            return
        }

        let request: URLRequest
        do {
            request = try HSGuruUploader.makeRequest(payload: entry.payload, endpointURL: endpointURL)
        } catch {
            logger.error("Could not encode HS Guru game \(entry.payload.gameId): \(error)")
            store.remove(id: entry.id)
            drain()
            return
        }

        logger.info("Uploading completed game \(entry.payload.gameId) to HS Guru")
        currentTask = session.dataTask(with: request) { [weak self] _, response, error in
            guard let self else { return }
            self.stateQueue.async {
                self.currentTask = nil
                self.handleCompletion(entry: entry, response: response, error: error)
            }
        }
        currentTask?.resume()
    }

    private func handleCompletion(entry: HSGuruOutboxEntry, response: URLResponse?, error: Error?) {
        dispatchPrecondition(condition: .onQueue(stateQueue))

        if let statusCode = (response as? HTTPURLResponse)?.statusCode,
           (200...299).contains(statusCode) {
            logger.info("Uploaded game \(entry.payload.gameId) to HS Guru")
            store.remove(id: entry.id)
            drain()
            return
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode
        if let statusCode, (400...499).contains(statusCode), statusCode != 408, statusCode != 429 {
            logger.error("HS Guru rejected game \(entry.payload.gameId) with HTTP \(statusCode)")
            store.remove(id: entry.id)
            drain()
            return
        }

        var retryEntry = entry
        retryEntry.attemptCount += 1
        retryEntry.nextAttemptAt = Date().addingTimeInterval(Self.retryDelay(for: retryEntry.attemptCount))
        store.update(retryEntry)
        if let error {
            logger.warning("HS Guru upload failed for game \(entry.payload.gameId): \(error)")
        } else {
            logger.warning("HS Guru upload failed for game \(entry.payload.gameId), HTTP \(statusCode ?? 0)")
        }
        drain()
    }

    private static func retryDelay(for attemptCount: Int) -> TimeInterval {
        let exponent = min(max(attemptCount - 1, 0), 6)
        return min(5 * pow(2, Double(exponent)), 300)
    }
}
