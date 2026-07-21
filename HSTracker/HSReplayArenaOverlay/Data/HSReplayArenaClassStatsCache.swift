//
//  HSReplayArenaClassStatsCache.swift
//  HSTracker
//

import Foundation

enum HSReplayArenaDataFreshness: String {
    case fresh
    case stale
    case invalid
    case missing
}

struct HSReplayArenaCacheState {
    let freshness: HSReplayArenaDataFreshness
    let snapshot: HSReplayArenaClassStatsSnapshot?
    let errorDescription: String?
}

final class HSReplayArenaClassStatsCache {
    static let defaultMaxAge: TimeInterval = 6 * 60 * 60

    let fileURL: URL
    private let fileManager: FileManager
    private let maxAge: TimeInterval
    private var refreshAttemptFileURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent(
            "class-winrates-refresh-attempt-v1.json",
            isDirectory: false
        )
    }

    init(
        fileURL: URL,
        fileManager: FileManager = .default,
        maxAge: TimeInterval =
            HSReplayArenaClassStatsCache.defaultMaxAge
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.maxAge = maxAge
    }

    func load(now: Date = Date()) -> HSReplayArenaCacheState {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return HSReplayArenaCacheState(
                freshness: .missing,
                snapshot: nil,
                errorDescription: nil
            )
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let snapshot = try Self.decoder.decode(
                HSReplayArenaClassStatsSnapshot.self,
                from: data
            )
            return HSReplayArenaCacheState(
                freshness: freshness(of: snapshot, now: now),
                snapshot: snapshot,
                errorDescription: nil
            )
        } catch {
            return HSReplayArenaCacheState(
                freshness: .invalid,
                snapshot: nil,
                errorDescription: error.localizedDescription
            )
        }
    }

    func freshness(
        of snapshot: HSReplayArenaClassStatsSnapshot,
        now: Date = Date()
    ) -> HSReplayArenaDataFreshness {
        let age = max(0, now.timeIntervalSince(snapshot.fetchedAt))
        return age <= maxAge ? .fresh : .stale
    }

    func save(_ snapshot: HSReplayArenaClassStatsSnapshot) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let data = try Self.encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    func loadRefreshAttempt() -> Date? {
        guard
            let data = try? Data(contentsOf: refreshAttemptFileURL),
            let attempt = try? Self.decoder.decode(
                RefreshAttempt.self,
                from: data
            )
        else {
            return nil
        }
        return attempt.attemptedAt
    }

    func saveRefreshAttempt(_ date: Date) throws {
        let directory = refreshAttemptFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let data = try Self.encoder.encode(
            RefreshAttempt(attemptedAt: date)
        )
        try data.write(to: refreshAttemptFileURL, options: .atomic)
    }

    func reset() throws {
        for url in [fileURL, refreshAttemptFileURL]
        where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}

private struct RefreshAttempt: Codable {
    let attemptedAt: Date
}
