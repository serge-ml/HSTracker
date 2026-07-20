//
//  UpdatePreferencesController.swift
//  HSTracker
//

import AppKit
@preconcurrency import Preferences

@MainActor
final class UpdatePreferencesController:
    PreferencePaneController,
    @preconcurrency PreferencePane {
    var preferencePaneIdentifier = Preferences.PaneIdentifier.updates
    var preferencePaneTitle = "Updates"
    var toolbarItemIcon =
        NSImage(named: "settings-general") ??
        NSImage(size: NSSize(width: 32, height: 32))

    private let automaticChecksButton = NSButton(
        checkboxWithTitle: "Automatically check for updates",
        target: nil,
        action: nil
    )
    private let automaticDownloadsButton = NSButton(
        checkboxWithTitle: "Download updates automatically",
        target: nil,
        action: nil
    )
    private let statusLabel = NSTextField(wrappingLabelWithString: "")

    private var updateController: UpdateController {
        UpdateController.shared
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 310))
        root.translatesAutoresizingMaskIntoConstraints = false
        root.heightAnchor.constraint(equalToConstant: 310).isActive = true
        view = root

        let title = NSTextField(labelWithString: "HSTracker Arena updates")
        title.font = NSFont.systemFont(ofSize: 18, weight: .semibold)

        let subtitle = NSTextField(
            wrappingLabelWithString:
                "Updates are delivered from this fork's signed GitHub release feed. " +
                "HearthSim's upstream update channel is not used."
        )
        subtitle.textColor = .secondaryLabelColor

        automaticChecksButton.target = self
        automaticChecksButton.action = #selector(updateSettingChanged(_:))
        automaticDownloadsButton.target = self
        automaticDownloadsButton.action = #selector(updateSettingChanged(_:))

        let checkButton = NSButton(
            title: "Check for Updates…",
            target: self,
            action: #selector(checkForUpdates)
        )
        let releasesButton = NSButton(
            title: "Open Releases",
            target: self,
            action: #selector(openReleases)
        )
        let buttonRow = NSStackView(views: [checkButton, releasesButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [
            title,
            subtitle,
            separator(),
            automaticChecksButton,
            automaticDownloadsButton,
            buttonRow,
            separator(),
            statusLabel
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 22),
            subtitle.widthAnchor.constraint(equalToConstant: 552),
            statusLabel.widthAnchor.constraint(equalToConstant: 552)
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(diagnosticsChanged),
            name: .updateDiagnosticsDidChange,
            object: nil
        )
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        updateController.start()
        reloadControls()
    }

    @objc private func updateSettingChanged(_ sender: NSButton) {
        if sender == automaticChecksButton {
            updateController.setAutomaticallyChecksForUpdates(
                sender.state == .on
            )
        } else if sender == automaticDownloadsButton {
            updateController.setAutomaticallyDownloadsUpdates(
                sender.state == .on
            )
        }
        reloadControls()
    }

    @objc private func diagnosticsChanged() {
        reloadControls()
    }

    @objc private func checkForUpdates() {
        updateController.checkForUpdates(self)
        reloadControls()
    }

    @objc private func openReleases() {
        guard let url = URL(
            string: "https://github.com/serge-ml/HSTracker/releases"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func reloadControls() {
        let updater = updateController.updater
        automaticChecksButton.state =
            updater.automaticallyChecksForUpdates ? .on : .off
        automaticDownloadsButton.state =
            updater.automaticallyDownloadsUpdates ? .on : .off
        automaticDownloadsButton.isEnabled =
            updater.automaticallyChecksForUpdates &&
            updater.allowsAutomaticUpdates

        let version =
            Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "unknown"
        let build =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
                as? String ?? "unknown"
        let lastCheck = updater.lastUpdateCheckDate.map {
            DateFormatter.localizedString(
                from: $0,
                dateStyle: .medium,
                timeStyle: .short
            )
        } ?? "never"
        var lines = [
            "Installed: \(version) (\(build))",
            "Feed: serge-ml.github.io/HSTracker/appcast.xml",
            "Last check: \(lastCheck)"
        ]
        if let failure = updateController.lastFailureDescription {
            lines.append("Last error: \(failure)")
        }
        statusLabel.stringValue = lines.joined(separator: "  •  ")
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 552).isActive = true
        return box
    }
}

extension Preferences.PaneIdentifier {
    static let updates = Self("updates")
}
