//
//  HSReplayArenaPreferencesController.swift
//  HSTracker
//

import AppKit
import Preferences

final class HSReplayArenaPreferencesController:
    PreferencePaneController,
    PreferencePane
{
    var preferencePaneIdentifier = Preferences.PaneIdentifier.hsReplayArena
    var preferencePaneTitle = "Arena Stats"
    var toolbarItemIcon =
        NSImage(named: "settings-hsreplay") ??
        NSImage(size: NSSize(width: 32, height: 32))

    private let enabledButton = NSButton(
        checkboxWithTitle: "Show class win rates during hero selection",
        target: nil,
        action: nil
    )
    private let rankButton = NSButton(
        checkboxWithTitle: "Show overall Arena class rank",
        target: nil,
        action: nil
    )
    private let hideInBackgroundButton = NSButton(
        checkboxWithTitle: "Hide when Hearthstone is in the background",
        target: nil,
        action: nil
    )
    private let scaleSlider = NSSlider(
        value: 1,
        minValue: 0.75,
        maxValue: 1.5,
        target: nil,
        action: nil
    )
    private let offsetSlider = NSSlider(
        value: 0,
        minValue: -200,
        maxValue: 200,
        target: nil,
        action: nil
    )
    private let scaleValueLabel = NSTextField(labelWithString: "")
    private let offsetValueLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(
        wrappingLabelWithString: "Loading Arena data status…"
    )
    private let diagnosticsLabel = NSTextField(
        wrappingLabelWithString: ""
    )

    override func loadView() {
        let root = NSView(
            frame: NSRect(x: 0, y: 0, width: 600, height: 500)
        )
        root.translatesAutoresizingMaskIntoConstraints = false
        root.heightAnchor.constraint(equalToConstant: 500).isActive = true
        view = root

        let title = NSTextField(
            labelWithString: "Arena class win rates"
        )
        title.font = NSFont.systemFont(ofSize: 18, weight: .semibold)

        let subtitle = NSTextField(
            wrappingLabelWithString:
                "Shows recent Firestone class statistics over the three " +
                "heroes offered at the start of an Arena draft."
        )
        subtitle.textColor = .secondaryLabelColor

        configureControls()

        let buttonRow = NSStackView(views: [
            NSButton(
                title: "Refresh now",
                target: self,
                action: #selector(refreshStats)
            ),
            NSButton(
                title: "Reset overlay position",
                target: self,
                action: #selector(resetOverlayPosition)
            ),
            NSButton(
                title: "Reset data cache",
                target: self,
                action: #selector(resetCache)
            )
        ])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let attributionButton = NSButton(
            title: "View Firestone data source",
            target: self,
            action: #selector(openHSReplayArena)
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
            hideInBackgroundButton,
            makeSliderRow(
                title: "Overlay scale",
                slider: scaleSlider,
                valueLabel: scaleValueLabel
            ),
            makeSliderRow(
                title: "Vertical offset",
                slider: offsetSlider,
                valueLabel: offsetValueLabel
            ),
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
            stack.leadingAnchor.constraint(
                equalTo: root.leadingAnchor,
                constant: 24
            ),
            stack.trailingAnchor.constraint(
                equalTo: root.trailingAnchor,
                constant: -24
            ),
            stack.topAnchor.constraint(
                equalTo: root.topAnchor,
                constant: 22
            ),
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
        for button in [
            enabledButton,
            rankButton,
            hideInBackgroundButton
        ] {
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
        enabledButton.state = HSReplayArenaSettings.enabled ? .on : .off
        rankButton.state = HSReplayArenaSettings.showRank ? .on : .off
        hideInBackgroundButton.state =
            HSReplayArenaSettings.hideWhenHearthstoneIsInBackground
                ? .on
                : .off
        scaleSlider.doubleValue = HSReplayArenaSettings.overlayScale
        offsetSlider.doubleValue = HSReplayArenaSettings.verticalOffset
        updateSliderLabels()
    }

    @objc private func checkboxChanged(_ sender: NSButton) {
        let value = sender.state == .on
        switch sender {
        case enabledButton:
            HSReplayArenaSettings.enabled = value
        case rankButton:
            HSReplayArenaSettings.showRank = value
        case hideInBackgroundButton:
            HSReplayArenaSettings.hideWhenHearthstoneIsInBackground = value
        default:
            break
        }
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        if sender == scaleSlider {
            HSReplayArenaSettings.overlayScale = sender.doubleValue
        } else if sender == offsetSlider {
            HSReplayArenaSettings.verticalOffset = sender.doubleValue
        }
        updateSliderLabels()
    }

    private func updateSliderLabels() {
        scaleValueLabel.stringValue = String(
            format: "%.0f%%",
            HSReplayArenaSettings.overlayScale * 100
        )
        offsetValueLabel.stringValue = String(
            format: "%+.0f pt",
            HSReplayArenaSettings.verticalOffset
        )
    }

    @objc private func refreshStats() {
        statusLabel.stringValue = "Refreshing Arena class data…"
        HSReplayArenaFeatureBootstrap.shared.classStatsStore
            .refreshIfNeeded(force: true) { [weak self] _ in
                self?.reloadStatus()
            }
    }

    @objc private func resetOverlayPosition() {
        HSReplayArenaSettings.resetOverlayPosition()
        reloadControls()
    }

    @objc private func resetCache() {
        HSReplayArenaFeatureBootstrap.shared.classStatsStore.reset {
            [weak self] error in
            guard error == nil else {
                self?.reloadStatus()
                return
            }
            HSReplayArenaFeatureBootstrap.shared.classStatsStore
                .refreshIfNeeded(force: true) { [weak self] _ in
                    self?.reloadStatus()
                }
        }
    }

    @objc private func openHSReplayArena() {
        if let url = URL(
            string: HSReplayArenaClassStatsSnapshot.pageURL
        ) {
            NSWorkspace.shared.open(url)
        }
    }

    private func reloadStatus() {
        HSReplayArenaFeatureBootstrap.shared.classStatsStore.currentStatus {
            [weak self] status in
            guard let self = self else { return }
            let timestamp = status.fetchedAt.map {
                DateFormatter.localizedString(
                    from: $0,
                    dateStyle: .medium,
                    timeStyle: .short
                )
            } ?? "never"
            var lines = [
                "Data: \(status.freshness.rawValue.capitalized)",
                "Last successful update: \(timestamp)",
                "Classes: \(status.classCount)"
            ]
            if status.isRefreshing {
                lines.append("Refresh in progress")
            }
            if let error = status.lastError {
                lines.append("Last error: \(error)")
            }
            self.statusLabel.stringValue = lines.joined(separator: "  •  ")

            let diagnostics =
                HSReplayArenaFeatureBootstrap.shared.diagnostics.snapshot()
            let offer = diagnostics.offerVersion.map(String.init) ?? "—"
            self.diagnosticsLabel.stringValue =
                "Schema: " +
                "\(HSReplayArenaClassStatsSnapshot.currentSchemaVersion)" +
                "  •  State: \(diagnostics.state.rawValue)" +
                "  •  Offer: \(offer)" +
                "  •  Coverage: \(diagnostics.matchedClassCount)/" +
                "\(diagnostics.offeredClassCount)"
        }
    }

    private func makeSliderRow(
        title: String,
        slider: NSSlider,
        valueLabel: NSTextField
    ) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.widthAnchor.constraint(
            equalToConstant: 120
        ).isActive = true
        slider.widthAnchor.constraint(equalToConstant: 300).isActive = true
        valueLabel.alignment = .right
        valueLabel.widthAnchor.constraint(
            equalToConstant: 70
        ).isActive = true

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
    static let hsReplayArena = Self("hsreplay-arena")
}
