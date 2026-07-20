//
//  ArenaCardRatingView.swift
//  HSTracker
//

import AppKit

final class ArenaCardRatingView: NSView {
    private let scoreLabel = NSTextField(labelWithString: "—")
    private let rankLabel = NSTextField(labelWithString: "")
    private let sourceLabel = NSTextField(labelWithString: "HearthArena")

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
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor

        scoreLabel.alignment = .center
        scoreLabel.textColor = .white
        scoreLabel.font = NSFont.monospacedDigitSystemFont(
            ofSize: 31,
            weight: .bold
        )
        scoreLabel.maximumNumberOfLines = 1

        rankLabel.alignment = .center
        rankLabel.textColor = .white
        rankLabel.font = NSFont.monospacedDigitSystemFont(
            ofSize: 13,
            weight: .bold
        )
        rankLabel.wantsLayer = true
        rankLabel.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        rankLabel.layer?.cornerRadius = 9

        sourceLabel.alignment = .center
        sourceLabel.textColor = NSColor.white.withAlphaComponent(0.88)
        sourceLabel.font = NSFont.systemFont(ofSize: 9, weight: .medium)

        addSubview(scoreLabel)
        addSubview(rankLabel)
        addSubview(sourceLabel)
    }

    override func layout() {
        super.layout()
        let scale = max(0.7, bounds.height / 68)
        let rankSize = 19 * scale

        rankLabel.frame = NSRect(
            x: bounds.width - rankSize - 6 * scale,
            y: bounds.height - rankSize - 5 * scale,
            width: rankSize,
            height: rankSize
        )
        scoreLabel.frame = NSRect(
            x: 5 * scale,
            y: 18 * scale,
            width: bounds.width - 10 * scale,
            height: 39 * scale
        )
        sourceLabel.frame = NSRect(
            x: 4 * scale,
            y: 5 * scale,
            width: bounds.width - 8 * scale,
            height: 13 * scale
        )
        scoreLabel.font = NSFont.monospacedDigitSystemFont(
            ofSize: 31 * scale,
            weight: .bold
        )
        rankLabel.font = NSFont.monospacedDigitSystemFont(
            ofSize: 13 * scale,
            weight: .bold
        )
        sourceLabel.font = NSFont.systemFont(ofSize: 9 * scale, weight: .medium)
        rankLabel.layer?.cornerRadius = rankSize / 2
        layer?.cornerRadius = 12 * scale
    }

    func update(
        with ratedCard: ArenaRatedCard,
        showRank: Bool,
        useTierColors: Bool
    ) {
        scoreLabel.stringValue = ratedCard.score.map(String.init) ?? "—"
        if showRank, let rank = ratedCard.rank {
            rankLabel.stringValue = String(rank)
            rankLabel.isHidden = false
        } else {
            rankLabel.stringValue = ""
            rankLabel.isHidden = true
        }

        let color = useTierColors
            ? Self.tierColor(for: ratedCard.score)
            : NSColor(calibratedWhite: 0.08, alpha: 0.90)
        layer?.backgroundColor = color.cgColor
        toolTip = ratedCard.card.englishName.isEmpty
            ? ratedCard.card.cardId
            : ratedCard.card.englishName
    }

    static func tierColor(for score: Int?) -> NSColor {
        guard let score = score else {
            return NSColor(calibratedWhite: 0.20, alpha: 0.88)
        }
        switch score {
        case 100...:
            return NSColor(calibratedRed: 0.42, green: 0.20, blue: 0.64, alpha: 0.92)
        case 90...:
            return NSColor(calibratedRed: 0.13, green: 0.40, blue: 0.68, alpha: 0.92)
        case 80...:
            return NSColor(calibratedRed: 0.12, green: 0.52, blue: 0.44, alpha: 0.92)
        case 70...:
            return NSColor(calibratedRed: 0.28, green: 0.55, blue: 0.20, alpha: 0.92)
        case 60...:
            return NSColor(calibratedRed: 0.68, green: 0.52, blue: 0.10, alpha: 0.92)
        case 40...:
            return NSColor(calibratedRed: 0.72, green: 0.32, blue: 0.10, alpha: 0.92)
        default:
            return NSColor(calibratedRed: 0.62, green: 0.13, blue: 0.13, alpha: 0.92)
        }
    }
}
