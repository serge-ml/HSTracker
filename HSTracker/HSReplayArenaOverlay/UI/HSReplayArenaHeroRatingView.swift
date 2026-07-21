//
//  HSReplayArenaHeroRatingView.swift
//  HSTracker
//

import AppKit

final class HSReplayArenaHeroRatingView: NSView {
    private let winRateLabel = NSTextField(labelWithString: "—")
    private let rankLabel = NSTextField(labelWithString: "")
    private let sourceLabel = NSTextField(labelWithString: "Firestone")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor =
            NSColor.white.withAlphaComponent(0.35).cgColor

        winRateLabel.alignment = .center
        winRateLabel.textColor = .white
        winRateLabel.font = NSFont.monospacedDigitSystemFont(
            ofSize: 25,
            weight: .bold
        )

        rankLabel.alignment = .center
        rankLabel.textColor = .white
        rankLabel.font = NSFont.monospacedDigitSystemFont(
            ofSize: 11,
            weight: .bold
        )
        rankLabel.wantsLayer = true
        rankLabel.layer?.backgroundColor =
            NSColor.black.withAlphaComponent(0.45).cgColor

        sourceLabel.alignment = .center
        sourceLabel.textColor = NSColor.white.withAlphaComponent(0.88)
        sourceLabel.font = NSFont.systemFont(ofSize: 9, weight: .medium)

        addSubview(winRateLabel)
        addSubview(rankLabel)
        addSubview(sourceLabel)
    }

    override func layout() {
        super.layout()
        let scale = max(0.7, bounds.height / 52)
        let rankSize = 18 * scale

        rankLabel.frame = NSRect(
            x: bounds.width - rankSize - 5 * scale,
            y: bounds.height - rankSize - 4 * scale,
            width: rankSize,
            height: rankSize
        )
        winRateLabel.frame = NSRect(
            x: 5 * scale,
            y: 14 * scale,
            width: bounds.width - 10 * scale,
            height: 31 * scale
        )
        sourceLabel.frame = NSRect(
            x: 4 * scale,
            y: 3 * scale,
            width: bounds.width - 8 * scale,
            height: 12 * scale
        )

        winRateLabel.font = NSFont.monospacedDigitSystemFont(
            ofSize: 25 * scale,
            weight: .bold
        )
        rankLabel.font = NSFont.monospacedDigitSystemFont(
            ofSize: 11 * scale,
            weight: .bold
        )
        sourceLabel.font = NSFont.systemFont(
            ofSize: 9 * scale,
            weight: .medium
        )
        rankLabel.layer?.cornerRadius = rankSize / 2
        layer?.cornerRadius = 10 * scale
    }

    func update(
        with ratedHero: HSReplayArenaRatedHero,
        showRank: Bool
    ) {
        if let winRate = ratedHero.stat?.winRate {
            winRateLabel.stringValue = String(format: "%.1f%%", winRate)
        } else {
            winRateLabel.stringValue = "—"
        }

        if showRank, let rank = ratedHero.rank {
            rankLabel.stringValue = String(rank)
            rankLabel.isHidden = false
        } else {
            rankLabel.stringValue = ""
            rankLabel.isHidden = true
        }

        layer?.backgroundColor = Self.color(
            for: ratedHero.rank,
            hasStat: ratedHero.stat != nil
        ).cgColor
        toolTip = Self.tooltip(for: ratedHero)
    }

    private static func color(for rank: Int?, hasStat: Bool) -> NSColor {
        guard hasStat, let rank = rank else {
            return NSColor(calibratedWhite: 0.20, alpha: 0.88)
        }
        switch rank {
        case 1...3:
            return NSColor(
                calibratedRed: 0.12,
                green: 0.52,
                blue: 0.32,
                alpha: 0.92
            )
        case 4...7:
            return NSColor(
                calibratedRed: 0.68,
                green: 0.45,
                blue: 0.08,
                alpha: 0.92
            )
        default:
            return NSColor(
                calibratedRed: 0.62,
                green: 0.17,
                blue: 0.14,
                alpha: 0.92
            )
        }
    }

    private static func tooltip(
        for ratedHero: HSReplayArenaRatedHero
    ) -> String {
        var values = [ratedHero.hero.heroClass.displayName]
        if let rank = ratedHero.rank {
            values.append("Arena rank #\(rank)")
        }
        if let pickRate = ratedHero.stat?.pickRate {
            values.append(String(format: "Picked %.1f%%", pickRate))
        }
        if let draftCount = ratedHero.stat?.draftCount {
            values.append("\(draftCount) drafts")
        }
        return values.joined(separator: " • ")
    }
}
