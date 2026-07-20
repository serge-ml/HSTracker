//
//  HearthArenaTierListStore.swift
//  HSTracker
//

import Foundation

struct HearthArenaDataStatus {
    let freshness: TierListFreshness
    let fetchedAt: Date?
    let ratingCount: Int
    let isRefreshing: Bool
    let lastError: String?
}

final class HearthArenaTierListStore {
    typealias StatusHandler = (HearthArenaDataStatus) -> Void
    static let defaultAutomaticRefreshInterval: TimeInterval = 24 * 60 * 60

    private let client: HearthArenaFetching
    private let parser: HearthArenaHTMLParser
    private let validator: TierListValidator
    private let cache: TierListCache
    private let automaticRefreshInterval: TimeInterval
    private let now: () -> Date
    private let queue = DispatchQueue(label: "HSTracker.HearthArenaTierListStore")

    private var snapshot: TierListSnapshot?
    private var freshness = TierListFreshness.missing
    private var refreshing = false
    private var lastRefreshAttemptAt: Date?
    private var lastError: String?

    var onStatusChanged: StatusHandler?

    init(
        client: HearthArenaFetching,
        parser: HearthArenaHTMLParser,
        validator: TierListValidator,
        cache: TierListCache,
        automaticRefreshInterval: TimeInterval =
            HearthArenaTierListStore.defaultAutomaticRefreshInterval,
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
            let state = self.cache.load()
            if let snapshot = state.snapshot {
                do {
                    try self.validator.validate(snapshot)
                    self.snapshot = snapshot
                    self.freshness = state.freshness
                    self.lastError = nil
                } catch {
                    self.loadBundledFallback(after: error)
                }
            } else {
                self.loadBundledFallback(
                    after: state.errorDescription.map { StoreError.message($0) }
                )
            }
            self.publishStatus()
            DispatchQueue.main.async {
                completion?()
            }
        }
    }

    func currentStatus(completion: @escaping (HearthArenaDataStatus) -> Void) {
        queue.async {
            self.refreshFreshnessFromClock()
            let status = HearthArenaDataStatus(
                freshness: self.freshness,
                fetchedAt: self.snapshot?.fetchedAt,
                ratingCount: self.snapshot?.ratings.count ?? 0,
                isRefreshing: self.refreshing,
                lastError: self.lastError
            )
            DispatchQueue.main.async {
                completion(status)
            }
        }
    }

    func currentSnapshot(completion: @escaping (TierListSnapshot?) -> Void) {
        queue.async {
            let value = self.snapshot
            DispatchQueue.main.async {
                completion(value)
            }
        }
    }

    func refreshIfNeeded(
        force: Bool = false,
        completion: ((Result<TierListSnapshot, Error>) -> Void)? = nil
    ) {
        queue.async {
            self.refreshFreshnessFromClock()
            if self.refreshing {
                self.complete(
                    .failure(StoreError.refreshInProgress),
                    completion: completion
                )
                return
            }
            if !force, self.freshness == .fresh, let snapshot = self.snapshot {
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
                    let error = StoreError.automaticRefreshThrottled
                    self.lastError = Self.safeDescription(for: error)
                    self.publishStatus()
                    self.complete(
                        .failure(error),
                        completion: completion
                    )
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
                        self.complete(.failure(error), completion: completion)
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
        completion: ((Result<TierListSnapshot, Error>) -> Void)?
    ) {
        do {
            let newSnapshot = try parser.parse(data: data)
            try validator.validate(newSnapshot, previous: snapshot)
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

    private func loadBundledFallback(after error: Error?) {
        guard
            let url = Bundle.main.url(
                forResource: "heartharena-tierlist-fallback",
                withExtension: "json"
            ),
            let data = try? Data(contentsOf: url),
            let bundled = try? TierListCache.decoder.decode(
                TierListSnapshot.self,
                from: data
            ),
            (try? validator.validate(bundled)) != nil
        else {
            snapshot = nil
            freshness = error == nil ? .missing : .invalid
            lastError = error.map { Self.safeDescription(for: $0) }
            return
        }

        snapshot = bundled
        freshness = .stale
        lastError = error.map { Self.safeDescription(for: $0) }
    }

    private func publishStatus() {
        refreshFreshnessFromClock()
        let handler = onStatusChanged
        let status = HearthArenaDataStatus(
            freshness: freshness,
            fetchedAt: snapshot?.fetchedAt,
            ratingCount: snapshot?.ratings.count ?? 0,
            isRefreshing: refreshing,
            lastError: lastError
        )
        DispatchQueue.main.async {
            handler?(status)
        }
    }

    private func complete(
        _ result: Result<TierListSnapshot, Error>,
        completion: ((Result<TierListSnapshot, Error>) -> Void)?
    ) {
        DispatchQueue.main.async {
            completion?(result)
        }
    }

    private static func safeDescription(for error: Error) -> String {
        let description = error.localizedDescription
            .replacingOccurrences(of: "\n", with: " ")
        return String(description.prefix(300))
    }

    private func refreshFreshnessFromClock() {
        guard let snapshot = snapshot, freshness == .fresh || freshness == .stale else {
            return
        }
        freshness = cache.freshness(of: snapshot)
    }
}

private enum StoreError: LocalizedError {
    case message(String)
    case refreshInProgress
    case automaticRefreshThrottled

    var errorDescription: String? {
        switch self {
        case .message(let value): return value
        case .refreshInProgress:
            return "A HearthArena tier-list refresh is already in progress."
        case .automaticRefreshThrottled:
            return "The automatic HearthArena refresh is waiting for its next 24-hour window."
        }
    }
}
