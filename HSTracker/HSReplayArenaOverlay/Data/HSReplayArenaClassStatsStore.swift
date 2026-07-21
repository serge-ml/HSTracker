//
//  HSReplayArenaClassStatsStore.swift
//  HSTracker
//

import Foundation

struct HSReplayArenaDataStatus {
    let freshness: HSReplayArenaDataFreshness
    let fetchedAt: Date?
    let classCount: Int
    let isRefreshing: Bool
    let lastError: String?
}

final class HSReplayArenaClassStatsStore {
    typealias StatusHandler = (HSReplayArenaDataStatus) -> Void
    static let defaultAutomaticRefreshInterval: TimeInterval = 6 * 60 * 60

    private let client: HSReplayArenaFetching
    private let parser: HSReplayArenaJSONParser
    private let validator: HSReplayArenaClassStatsValidator
    private let cache: HSReplayArenaClassStatsCache
    private let automaticRefreshInterval: TimeInterval
    private let now: () -> Date
    private let queue = DispatchQueue(
        label: "HSTracker.HSReplayArenaClassStatsStore"
    )

    private var snapshot: HSReplayArenaClassStatsSnapshot?
    private var freshness = HSReplayArenaDataFreshness.missing
    private var refreshing = false
    private var lastRefreshAttemptAt: Date?
    private var lastError: String?

    var onStatusChanged: StatusHandler?

    init(
        client: HSReplayArenaFetching,
        parser: HSReplayArenaJSONParser,
        validator: HSReplayArenaClassStatsValidator,
        cache: HSReplayArenaClassStatsCache,
        automaticRefreshInterval: TimeInterval =
            HSReplayArenaClassStatsStore.defaultAutomaticRefreshInterval,
        now: @escaping () -> Date = Date.init
    ) {
        self.client = client
        self.parser = parser
        self.validator = validator
        self.cache = cache
        self.automaticRefreshInterval = automaticRefreshInterval
        self.now = now
    }

    func load(completion: (() -> Void)? = nil) {
        queue.async {
            self.lastRefreshAttemptAt = self.cache.loadRefreshAttempt()
            let state = self.cache.load(now: self.now())
            if let snapshot = state.snapshot {
                do {
                    try self.validator.validate(snapshot)
                    self.snapshot = snapshot
                    self.freshness = state.freshness
                    self.lastError = nil
                } catch {
                    self.snapshot = nil
                    self.freshness = .invalid
                    self.lastError = Self.safeDescription(for: error)
                }
            } else {
                self.snapshot = nil
                self.freshness = state.freshness
                self.lastError = state.errorDescription
            }
            self.publishStatus()
            DispatchQueue.main.async {
                completion?()
            }
        }
    }

    func currentStatus(
        completion: @escaping (HSReplayArenaDataStatus) -> Void
    ) {
        queue.async {
            self.refreshFreshnessFromClock()
            let status = self.makeStatus()
            DispatchQueue.main.async {
                completion(status)
            }
        }
    }

    func currentSnapshot(
        completion: @escaping (HSReplayArenaClassStatsSnapshot?) -> Void
    ) {
        queue.async {
            let value = self.snapshot
            DispatchQueue.main.async {
                completion(value)
            }
        }
    }

    func refreshIfNeeded(
        force: Bool = false,
        completion: ((
            Result<HSReplayArenaClassStatsSnapshot, Error>
        ) -> Void)? = nil
    ) {
        queue.async {
            self.refreshFreshnessFromClock()
            if self.refreshing {
                self.complete(
                    .failure(HSReplayArenaStoreError.refreshInProgress),
                    completion: completion
                )
                return
            }
            if
                !force,
                self.freshness == .fresh,
                let snapshot = self.snapshot
            {
                self.complete(.success(snapshot), completion: completion)
                return
            }
            if
                !force,
                let lastAttempt = self.lastRefreshAttemptAt,
                self.now().timeIntervalSince(lastAttempt) <
                    self.automaticRefreshInterval
            {
                if let snapshot = self.snapshot {
                    self.complete(.success(snapshot), completion: completion)
                } else {
                    let error =
                        HSReplayArenaStoreError.automaticRefreshThrottled
                    self.lastError = Self.safeDescription(for: error)
                    self.publishStatus()
                    self.complete(.failure(error), completion: completion)
                }
                return
            }

            let attemptTime = self.now()
            self.lastRefreshAttemptAt = attemptTime
            try? self.cache.saveRefreshAttempt(attemptTime)
            self.refreshing = true
            self.publishStatus()
            self.client.fetch { result in
                self.queue.async {
                    switch result {
                    case .failure(let error):
                        self.refreshing = false
                        self.lastError = Self.safeDescription(for: error)
                        self.publishStatus()
                        self.complete(
                            .failure(error),
                            completion: completion
                        )
                    case .success(let data):
                        self.accept(data: data, completion: completion)
                    }
                }
            }
        }
    }

    func reset(completion: ((Error?) -> Void)? = nil) {
        queue.async {
            do {
                try self.cache.reset()
                self.snapshot = nil
                self.freshness = .missing
                self.lastRefreshAttemptAt = nil
                self.lastError = nil
                self.publishStatus()
                DispatchQueue.main.async { completion?(nil) }
            } catch {
                self.lastError = Self.safeDescription(for: error)
                self.publishStatus()
                DispatchQueue.main.async { completion?(error) }
            }
        }
    }

    private func accept(
        data: Data,
        completion: ((
            Result<HSReplayArenaClassStatsSnapshot, Error>
        ) -> Void)?
    ) {
        do {
            let newSnapshot = try parser.parse(data: data)
            try validator.validate(newSnapshot)
            try cache.save(newSnapshot)
            snapshot = newSnapshot
            freshness = .fresh
            refreshing = false
            lastError = nil
            publishStatus()
            complete(.success(newSnapshot), completion: completion)
        } catch {
            refreshing = false
            lastError = Self.safeDescription(for: error)
            publishStatus()
            complete(.failure(error), completion: completion)
        }
    }

    private func makeStatus() -> HSReplayArenaDataStatus {
        HSReplayArenaDataStatus(
            freshness: freshness,
            fetchedAt: snapshot?.fetchedAt,
            classCount: snapshot?.stats.count ?? 0,
            isRefreshing: refreshing,
            lastError: lastError
        )
    }

    private func publishStatus() {
        refreshFreshnessFromClock()
        let status = makeStatus()
        let handler = onStatusChanged
        DispatchQueue.main.async {
            handler?(status)
        }
    }

    private func complete(
        _ result: Result<HSReplayArenaClassStatsSnapshot, Error>,
        completion: ((
            Result<HSReplayArenaClassStatsSnapshot, Error>
        ) -> Void)?
    ) {
        DispatchQueue.main.async {
            completion?(result)
        }
    }

    private func refreshFreshnessFromClock() {
        guard
            let snapshot = snapshot,
            freshness == .fresh || freshness == .stale
        else {
            return
        }
        freshness = cache.freshness(of: snapshot, now: now())
    }

    private static func safeDescription(for error: Error) -> String {
        let description = error.localizedDescription
            .replacingOccurrences(of: "\n", with: " ")
        return String(description.prefix(300))
    }
}

private enum HSReplayArenaStoreError: LocalizedError {
    case refreshInProgress
    case automaticRefreshThrottled

    var errorDescription: String? {
        switch self {
        case .refreshInProgress:
            return "An Arena class-statistics refresh is already in progress."
        case .automaticRefreshThrottled:
            return "The automatic Arena class-statistics refresh is waiting for its next six-hour window."
        }
    }
}
