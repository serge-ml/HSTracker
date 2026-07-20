//
//  HearthArenaPreferencesController.swift
//  HSTracker
//

import AppKit
import Preferences

final class HearthArenaPreferencesController: PreferencePaneController, PreferencePane {
    var preferencePaneIdentifier = Preferences.PaneIdentifier.hearthArena
    var preferencePaneTitle = "HearthArena"
    var toolbarItemIcon =
        NSImage(named: "settings-game") ??
        NSImage(size: NSSize(width: 32, height: 32))

    private let enabledButton = NSButton(checkboxWithTitle: "Enable HearthArena ratings", target: nil, action: nil)
    private let rankButton = NSButton(checkboxWithTitle: "Show rank 1–3", target: nil, action: nil)
    private let colorsButton = NSButton(checkboxWithTitle: "Use tier colors", target: nil, action: nil)
    private let hideInBackgroundButton = NSButton(
        checkboxWithTitle: "Hide when Hearthstone is in the background",
        target: nil,
        action: nil
    )
    private let scaleSlider = NSSlider(value: 1, minValue: 0.75, maxValue: 1.5, target: nil, action: nil)
    private let offsetSlider = NSSlider(value: 0, minValue: -200, maxValue: 200, target: nil, action: nil)
    private let scaleValueLabel = NSTextField(labelWithString: "")
    private let offsetValueLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "Loading data status…")
    private let diagnosticsLabel = NSTextField(wrappingLabelWithString: "")

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 570))
        root.translatesAutoresizingMaskIntoConstraints = false
        root.heightAnchor.constraint(equalToConstant: 570).isActive = true
        view = root

        let title = NSTextField(labelWithString: "HearthArena Arena ratings")
        title.font = NSFont.systemFont(ofSize: 18, weight: .semibold)

        let subtitle = NSTextField(
            wrappingLabelWithString:
                "Shows public base tier-list scores during Arena drafts. " +
                "This is not HearthArena's dynamic deck-synergy advice."
        )
        subtitle.textColor = .secondaryLabelColor

        configureControls()

        let scaleRow = makeSliderRow(
            title: "Overlay scale",
            slider: scaleSlider,
            valueLabel: scaleValueLabel
        )
        let offsetRow = makeSliderRow(
            title: "Vertical offset",
            slider: offsetSlider,
            valueLabel: offsetValueLabel
        )

        let refreshButton = NSButton(
            title: "Refresh tier list now",
            target: self,
            action: #selector(refreshTierList)
        )
        let resetPositionButton = NSButton(
            title: "Reset overlay position",
            target: self,
            action: #selector(resetOverlayPosition)
        )
        let resetCacheButton = NSButton(
            title: "Reset data cache",
            target: self,
            action: #selector(resetCache)
        )
        let openLogsButton = NSButton(
            title: "Open logs",
            target: self,
            action: #selector(openLogs)
        )
        let buttonRow = NSStackView(views: [
            refreshButton, resetPositionButton, resetCacheButton, openLogsButton
        ])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let attributionButton = NSButton(
            title: "Open HearthArena tier list",
            target: self,
            action: #selector(openTierList)
        )
        attributionButton.bezelStyle = .inline

        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        diagnosticsLabel.font =
            NSFont.userFixedPitchFont(ofSize: 11) ??
            NSFont.systemFont(ofSize: 11)
        diagnosticsLabel.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [
            title,
            subtitle,
            separator(),
            enabledButton,
            rankButton,
            colorsButton,
            hideInBackgroundButton,
            scaleRow,
            offsetRow,
            buttonRow,
            separator(),
            statusLabel,
            diagnosticsLabel,
            attributionButton
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 11
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 22),
            subtitle.widthAnchor.constraint(equalToConstant: 552),
            statusLabel.widthAnchor.constraint(equalToConstant: 552),
            diagnosticsLabel.widthAnchor.constraint(equalToConstant: 552)
        ])
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        reloadControls()
        reloadStatus()
    }

    private func configureControls() {
        for button in [enabledButton, rankButton, colorsButton, hideInBackgroundButton] {
            button.target = self
            button.action = #selector(checkboxChanged(_:))
        }
        for slider in [scaleSlider, offsetSlider] {
            slider.target = self
            slider.action = #selector(sliderChanged(_:))
            slider.isContinuous = true
        }
    }

    private func reloadControls() {
        enabledButton.state = HearthArenaSettings.enabled ? .on : .off
        rankButton.state = HearthArenaSettings.showRank ? .on : .off
        colorsButton.state = HearthArenaSettings.useTierColors ? .on : .off
        hideInBackgroundButton.state =
            HearthArenaSettings.hideWhenHearthstoneIsInBackground ? .on : .off
        scaleSlider.doubleValue = HearthArenaSettings.overlayScale
        offsetSlider.doubleValue = HearthArenaSettings.verticalOffset
        updateSliderLabels()
    }

    @objc private func checkboxChanged(_ sender: NSButton) {
        let value = sender.state == .on
        switch sender {
        case enabledButton:
            HearthArenaSettings.enabled = value
        case rankButton:
            HearthArenaSettings.showRank = value
        case colorsButton:
            HearthArenaSettings.useTierColors = value
        case hideInBackgroundButton:
            HearthArenaSettings.hideWhenHearthstoneIsInBackground = value
        default:
            break
        }
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        if sender == scaleSlider {
            HearthArenaSettings.overlayScale = sender.doubleValue
        } else if sender == offsetSlider {
            HearthArenaSettings.verticalOffset = sender.doubleValue
        }
        updateSliderLabels()
    }

    private func updateSliderLabels() {
        scaleValueLabel.stringValue = String(
            format: "%.0f%%",
            HearthArenaSettings.overlayScale * 100
        )
        offsetValueLabel.stringValue = String(
            format: "%+.0f pt",
            HearthArenaSettings.verticalOffset
        )
    }

    @objc private func refreshTierList() {
        statusLabel.stringValue = "Refreshing HearthArena tier list…"
        HearthArenaFeatureBootstrap.shared.tierListStore.refreshIfNeeded(force: true) {
            [weak self] _ in
            self?.reloadStatus()
        }
    }

    @objc private func resetOverlayPosition() {
        HearthArenaSettings.resetOverlayPosition()
        reloadControls()
    }

    @objc private func resetCache() {
        HearthArenaFeatureBootstrap.shared.tierListStore.reset { [weak self] error in
            guard error == nil else {
                self?.reloadStatus()
                return
            }
            HearthArenaFeatureBootstrap.shared.tierListStore.refreshIfNeeded(force: true) {
                [weak self] _ in
                self?.reloadStatus()
            }
        }
    }

    @objc private func openTierList() {
        if let url = URL(string: TierListSnapshot.sourceURL) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openLogs() {
        NSWorkspace.shared.activateFileViewerSelecting([Paths.logs])
    }

    private func reloadStatus() {
        HearthArenaFeatureBootstrap.shared.tierListStore.currentStatus {
            [weak self] status in
            guard let self = self else { return }
            let timestamp = status.fetchedAt.map {
                DateFormatter.localizedString(
                    from: $0,
                    dateStyle: .medium,
                    timeStyle: .short
                )
            } ?? "never"
            let age = status.fetchedAt.map {
                self.ageDescription(since: $0)
            } ?? "—"
            var lines = [
                "Data: \(status.freshness.rawValue.capitalized)",
                "Last successful update: \(timestamp)",
                "Age: \(age)",
                "Ratings: \(status.ratingCount)"
            ]
            if status.isRefreshing {
                lines.append("Refresh in progress")
            }
            if let error = status.lastError {
                lines.append("Last error: \(error)")
            }
            self.statusLabel.stringValue = lines.joined(separator: "  •  ")

            let diagnostics = HearthArenaFeatureBootstrap.shared.diagnostics.snapshot()
            let offer = diagnostics.currentOfferVersion.map(String.init) ?? "—"
            let slot = diagnostics.currentDraftSlot.map(String.init) ?? "—"
            let upstreamVersion = Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "unknown"
            let forkRevision = Bundle.main.object(
                forInfoDictionaryKey: "HearthArenaForkRevision"
            ) as? String ?? "dev"
            let mode: String
            if diagnostics.isPackageOffer == true {
                mode = diagnostics.isUnderground == true
                    ? "Underground package"
                    : "Arena package"
            } else if diagnostics.isUnderground == true {
                mode = "Underground"
            } else if diagnostics.isUnderground == false {
                mode = "Arena"
            } else {
                mode = "—"
            }
            let currentCoverage = diagnostics.currentMatchCoverage.map {
                String(format: "%.1f%%", $0 * 100)
            } ?? "—"
            let sessionCoverage = diagnostics.sessionMatchCoverage.map {
                String(format: "%.1f%%", $0 * 100)
            } ?? "—"
            self.diagnosticsLabel.stringValue =
                "App: \(upstreamVersion)-\(forkRevision)  •  " +
                "Parser/schema: \(TierListSnapshot.currentParserVersion)/" +
                "\(TierListSnapshot.currentSchemaVersion)  •  " +
                "State: \(diagnostics.state.rawValue)  •  " +
                "Mode: \(mode)  •  Offer: \(offer)  •  Slot: \(slot)  •  " +
                "Coverage: \(currentCoverage) current, " +
                "\(sessionCoverage) session  •  " +
                "Unknown cards: \(diagnostics.unknownCardCount)"
        }
    }

    private func ageDescription(since date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 60 {
            return "less than a minute"
        }
        if seconds < 60 * 60 {
            return "\(Int(seconds / 60)) min"
        }
        if seconds < 24 * 60 * 60 {
            return "\(Int(seconds / (60 * 60))) h"
        }
        return "\(Int(seconds / (24 * 60 * 60))) d"
    }

    private func makeSliderRow(
        title: String,
        slider: NSSlider,
        valueLabel: NSTextField
    ) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.widthAnchor.constraint(equalToConstant: 120).isActive = true
        slider.widthAnchor.constraint(equalToConstant: 300).isActive = true
        valueLabel.alignment = .right
        valueLabel.widthAnchor.constraint(equalToConstant: 70).isActive = true

        let row = NSStackView(views: [titleLabel, slider, valueLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 552).isActive = true
        return box
    }
}

extension Preferences.PaneIdentifier {
    static let hearthArena = Self("heartharena")
}
