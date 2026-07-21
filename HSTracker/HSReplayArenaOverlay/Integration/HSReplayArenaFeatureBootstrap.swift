//
//  HSReplayArenaFeatureBootstrap.swift
//  HSTracker
//

import Foundation

final class HSReplayArenaFeatureBootstrap {
    static let shared = HSReplayArenaFeatureBootstrap()

    let diagnostics = HSReplayArenaDiagnostics()
    let classStatsStore: HSReplayArenaClassStatsStore

    private let adapter = HSReplayArenaHeroChoiceAdapter()
    private let overlayController =
        HSReplayArenaHeroOverlayController()
    private var currentOffer: HSReplayArenaHeroOffer?
    private var enabledObserver: NSObjectProtocol?
    private var hearthstoneClosedObserver: NSObjectProtocol?
    private var started = false

    private init() {
        let cacheURL = Paths.hsReplayArena.appendingPathComponent(
            "class-winrates-v1.json",
            isDirectory: false
        )
        classStatsStore = HSReplayArenaClassStatsStore(
            client: HSReplayArenaClient(),
            parser: HSReplayArenaJSONParser(),
            validator: HSReplayArenaClassStatsValidator(),
            cache: HSReplayArenaClassStatsCache(fileURL: cacheURL)
        )
    }

    func start(watcher: ArenaWatcher) {
        guard !started else { return }
        started = true

        watcher.onHeroChoicesChanged = { [weak self] _, args in
            self?.handleHeroChoicesChanged(args)
        }
        watcher.onHeroChoicePicked = { [weak self] _ in
            self?.handleHeroSelectionClosed()
        }
        watcher.onHeroSelectionClosed = { [weak self] _ in
            self?.handleHeroSelectionClosed()
        }

        classStatsStore.onStatusChanged = { [weak self] status in
            guard let self = self else { return }
            self.diagnostics.update(dataStatus: status)
            self.log(status: status)
            if status.classCount > 0, self.currentOffer != nil {
                self.renderCurrentOffer()
            } else if
                status.classCount == 0,
                !status.isRefreshing,
                status.lastError != nil
            {
                self.updateState(.offline)
                self.overlayController.hide(clearOffer: false)
            }
        }

        enabledObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name(
                rawValue: HSReplayArenaSettings.enabledKey
            ),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.enabledChanged()
        }
        hearthstoneClosedObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name(rawValue: Events.hearthstone_closed),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleHeroSelectionClosed()
        }

        classStatsStore.load { [weak self] in
            guard
                let self = self,
                HSReplayArenaSettings.enabled
            else {
                return
            }
            self.classStatsStore.refreshIfNeeded()
        }
    }

    private func handleHeroChoicesChanged(
        _ args: ArenaHeroChoicesChangedEventArgs
    ) {
        do {
            let offer = try adapter.makeOffer(from: args)
            DispatchQueue.main.async { [weak self] in
                self?.accept(offer: offer)
            }
        } catch {
            logger.warning(
                "Arena class stats ignored hero offer: " +
                    error.localizedDescription
            )
            DispatchQueue.main.async { [weak self] in
                self?.handleHeroSelectionClosed()
            }
        }
    }

    private func accept(offer: HSReplayArenaHeroOffer) {
        guard currentOffer?.identityKey != offer.identityKey else {
            return
        }
        currentOffer = offer
        diagnostics.update(offer: offer)
        updateState(.loading)

        let classes = offer.heroes
            .map { $0.heroClass.rawValue }
            .joined(separator: ",")
        logger.info(
            "Arena class stats hero offer version=\(offer.offerVersion) " +
                "classes=[\(classes)]"
        )

        guard HSReplayArenaSettings.enabled else {
            updateState(.hidden)
            overlayController.hide(clearOffer: false)
            return
        }

        renderCurrentOffer()
        classStatsStore.refreshIfNeeded()
    }

    private func renderCurrentOffer() {
        guard
            HSReplayArenaSettings.enabled,
            let expectedOffer = currentOffer
        else {
            overlayController.hide(clearOffer: false)
            return
        }

        classStatsStore.currentSnapshot { [weak self] snapshot in
            guard
                let self = self,
                let currentOffer = self.currentOffer,
                currentOffer.identityKey == expectedOffer.identityKey,
                let snapshot = snapshot
            else {
                return
            }

            let stats = Dictionary(
                uniqueKeysWithValues: snapshot.stats.map {
                    ($0.heroClass, $0)
                }
            )
            let ranks = Dictionary(
                uniqueKeysWithValues: snapshot.stats
                    .sorted {
                        if $0.winRate == $1.winRate {
                            return $0.heroClass.rawValue <
                                $1.heroClass.rawValue
                        }
                        return $0.winRate > $1.winRate
                    }
                    .enumerated()
                    .map { ($0.element.heroClass, $0.offset + 1) }
            )
            let ratedHeroes = currentOffer.heroes.map {
                HSReplayArenaRatedHero(
                    hero: $0,
                    stat: stats[$0.heroClass],
                    rank: ranks[$0.heroClass]
                )
            }
            guard ratedHeroes.contains(where: { $0.stat != nil }) else {
                self.updateState(.offline)
                self.overlayController.hide(clearOffer: false)
                return
            }

            let ratedOffer = HSReplayArenaRatedHeroOffer(
                offer: currentOffer,
                heroes: ratedHeroes
            )
            self.diagnostics.update(ratedOffer: ratedOffer)
            self.updateState(.visible)
            self.overlayController.show(ratedOffer)
        }
    }

    private func handleHeroSelectionClosed() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentOffer = nil
            self.diagnostics.clearOffer()
            self.updateState(.idle)
            self.overlayController.hide()
        }
    }

    private func enabledChanged() {
        if HSReplayArenaSettings.enabled {
            renderCurrentOffer()
            classStatsStore.refreshIfNeeded()
        } else {
            updateState(.hidden)
            overlayController.hide(clearOffer: false)
        }
    }

    private func updateState(_ state: HSReplayArenaFeatureState) {
        diagnostics.update(state: state)
    }

    private func log(status: HSReplayArenaDataStatus) {
        let fetchedAt = status.fetchedAt.map {
            ISO8601DateFormatter().string(from: $0)
        } ?? "never"
        logger.info(
            "Arena class stats status=\(status.freshness.rawValue) " +
                "classes=\(status.classCount) fetchedAt=\(fetchedAt) " +
                "refreshing=\(status.isRefreshing) " +
                "error=\(status.lastError ?? "none")"
        )
    }
}
