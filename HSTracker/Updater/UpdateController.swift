//
//  UpdateController.swift
//  HSTracker
//

import Foundation
import Sparkle

extension Notification.Name {
    static let updateDiagnosticsDidChange =
        Notification.Name("HSTrackerArenaUpdateDiagnosticsDidChange")
}

@MainActor
final class UpdateController: NSObject, SPUUpdaterDelegate {
    static let shared = UpdateController()

    private var standardUpdaterController: SPUStandardUpdaterController!
    private(set) var lastFailureDescription: String?
    private(set) var isStarted = false

    var updater: SPUUpdater {
        standardUpdaterController.updater
    }

    private override init() {
        super.init()
        standardUpdaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    func start() {
        guard !isStarted else {
            return
        }
        standardUpdaterController.startUpdater()
        isStarted = true
        logger.info(
            "Fork updater started; automaticChecks=" +
            "\(updater.automaticallyChecksForUpdates), " +
            "automaticDownloads=\(updater.automaticallyDownloadsUpdates)"
        )
        notifyDiagnosticsChanged()
    }

    @IBAction func checkForUpdates(_ sender: Any?) {
        start()
        lastFailureDescription = nil
        logger.info("User requested an update check")
        standardUpdaterController.checkForUpdates(sender)
        notifyDiagnosticsChanged()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        start()
        updater.automaticallyChecksForUpdates = enabled
        logger.info("Automatic update checks changed to \(enabled)")
        notifyDiagnosticsChanged()
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        start()
        updater.automaticallyDownloadsUpdates = enabled
        logger.info("Automatic update downloads changed to \(enabled)")
        notifyDiagnosticsChanged()
    }

    func updater(
        _ updater: SPUUpdater,
        didFindValidUpdate item: SUAppcastItem
    ) {
        lastFailureDescription = nil
        logger.info(
            "Fork updater found version \(item.displayVersionString) " +
            "(build \(item.versionString))"
        )
        notifyDiagnosticsChanged()
    }

    func updaterDidNotFindUpdate(
        _ updater: SPUUpdater,
        error: Error
    ) {
        lastFailureDescription = nil
        logger.info("Fork updater completed without a newer version")
        notifyDiagnosticsChanged()
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        if let error = error {
            let sparkleError = error as NSError
            let isExpectedStop =
                sparkleError.domain == SUSparkleErrorDomain &&
                (
                    sparkleError.code ==
                        Int(SUError.noUpdateError.rawValue) ||
                    sparkleError.code ==
                        Int(SUError.installationCanceledError.rawValue)
                )
            if isExpectedStop {
                lastFailureDescription = nil
                logger.info("Fork updater cycle completed without installation")
            } else {
                lastFailureDescription = error.localizedDescription
                logger.warning(
                    "Fork updater cycle failed: \(error.localizedDescription)"
                )
            }
        } else {
            lastFailureDescription = nil
            logger.info("Fork updater cycle completed")
        }
        notifyDiagnosticsChanged()
    }

    func updater(
        _ updater: SPUUpdater,
        willScheduleUpdateCheckAfterDelay delay: TimeInterval
    ) {
        logger.debug(
            "Fork updater scheduled its next check in \(Int(delay)) seconds"
        )
        notifyDiagnosticsChanged()
    }

    func updaterWillNotScheduleUpdateCheck(_ updater: SPUUpdater) {
        logger.debug("Fork updater has no automatic check scheduled")
        notifyDiagnosticsChanged()
    }

    private func notifyDiagnosticsChanged() {
        NotificationCenter.default.post(
            name: .updateDiagnosticsDidChange,
            object: self
        )
    }
}
