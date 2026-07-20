//
//  TierListCache.swift
//  HSTracker
//

import Foundation

enum TierListFreshness: String {
    case fresh
    case stale
    case invalid
    case missing
}

struct TierListCacheState {
    let freshness: TierListFreshness
    let snapshot: TierListSnapshot?
    let errorDescription: String?
}

final class TierListCache {
    static let defaultMaxAge: TimeInterval = 24 * 60 * 60

    let fileURL: URL
    private let fileManager: FileManager
    private let maxAge: TimeInterval
    private var refreshAttemptFileURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent(
            "tierlist-refresh-attempt-v1.json",
            isDirectory: false
        )
    }

    init(
        fileURL: URL,
        fileManager: FileManager = .default,
        maxAge: TimeInterval = TierListCache.defaultMaxAge
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.maxAge = maxAge
    }

    func load(now: Date = Date()) -> TierListCacheState {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return TierListCacheState(
                freshness: .missing,
                snapshot: nil,
                errorDescription: nil
            )
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let snapshot = try Self.decoder.decode(TierListSnapshot.self, from: data)
            return TierListCacheState(
                freshness: freshness(of: snapshot, now: now),
                snapshot: snapshot,
                errorDescription: nil
            )
        } catch {
            return TierListCacheState(
                freshness: .invalid,
                snapshot: nil,
                errorDescription: error.localizedDescription
            )
        }
    }

    func freshness(
        of snapshot: TierListSnapshot,
        now: Date = Date()
    ) -> TierListFreshness {
        let age = max(0, now.timeIntervalSince(snapshot.fetchedAt))
        return age <= maxAge ? .fresh : .stale
    }

    func save(_ snapshot: TierListSnapshot) throws {
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
            let value = try? Self.decoder.decode(
                RefreshAttempt.self,
                from: data
            )
        else {
            return nil
        }
        return value.attemptedAt
    }

    func saveRefreshAttempt(_ date: Date) throws {
        let directory = refreshAttemptFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let data = try Self.encoder.encode(RefreshAttempt(attemptedAt: date))
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
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.container(
                keyedBy: CachedDateCodingKeys.self
            )
            try container.encode(
                date.timeIntervalSinceReferenceDate,
                forKey: .timeIntervalSinceReferenceDate
            )
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        let legacyFormatter = ISO8601DateFormatter()
        legacyFormatter.formatOptions = [.withInternetDateTime]

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            if
                let container = try? decoder.container(
                    keyedBy: CachedDateCodingKeys.self
                ),
                let timestamp = try? container.decode(
                    Double.self,
                    forKey: .timeIntervalSinceReferenceDate
                )
            {
                return Date(timeIntervalSinceReferenceDate: timestamp)
            }

            let container = try decoder.singleValueContainer()
            if let timestamp = try? container.decode(Double.self) {
                // Compatibility with snapshots written before the
                // lossless reference-date representation was introduced.
                return Date(timeIntervalSince1970: timestamp)
            }

            let value = try container.decode(String.self)
            if let date =
                fractionalFormatter.date(from: value) ??
                legacyFormatter.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid cached date: \(value)"
            )
        }
        return decoder
    }()
}

private enum CachedDateCodingKeys: String, CodingKey {
    case timeIntervalSinceReferenceDate
}

private struct RefreshAttempt: Codable {
    let attemptedAt: Date
}
