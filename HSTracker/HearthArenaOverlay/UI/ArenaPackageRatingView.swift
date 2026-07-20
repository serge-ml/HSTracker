//
//  ArenaPackageRatingView.swift
//  HSTracker
//

import AppKit

final class ArenaPackageRatingView: NSView {
    private let titleLabel = NSTextField(labelWithString: "Individual scores")
    private let scoresLabel = NSTextField(wrappingLabelWithString: "")
    private let sourceLabel = NSTextField(
        labelWithString: "HearthArena • no package rank"
    )

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
        layer?.backgroundColor = NSColor(
            calibratedRed: 0.08,
            green: 0.10,
            blue: 0.14,
            alpha: 0.93
        ).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 12
        layer?.masksToBounds = true

        titleLabel.alignment = .center
        titleLabel.textColor = .white

        scoresLabel.alignment = .left
        scoresLabel.textColor = .white
        scoresLabel.lineBreakMode = .byTruncatingTail

        sourceLabel.alignment = .center
        sourceLabel.textColor = NSColor.white.withAlphaComponent(0.72)

        addSubview(titleLabel)
        addSubview(scoresLabel)
        addSubview(sourceLabel)
    }

    override func layout() {
        super.layout()
        let scale = max(0.7, bounds.width / 220)
        let horizontalPadding = 10 * scale
        let sourceHeight = 14 * scale
        let titleHeight = 20 * scale

        sourceLabel.frame = NSRect(
            x: horizontalPadding,
            y: 6 * scale,
            width: bounds.width - horizontalPadding * 2,
            height: sourceHeight
        )
        scoresLabel.frame = NSRect(
            x: horizontalPadding,
            y: sourceLabel.frame.maxY + 3 * scale,
            width: bounds.width - horizontalPadding * 2,
            height: max(
                0,
                bounds.height - sourceHeight - titleHeight - 22 * scale
            )
        )
        titleLabel.frame = NSRect(
            x: horizontalPadding,
            y: bounds.height - titleHeight - 5 * scale,
            width: bounds.width - horizontalPadding * 2,
            height: titleHeight
        )

        titleLabel.font = NSFont.systemFont(
            ofSize: 12 * scale,
            weight: .semibold
        )
        scoresLabel.font =
            NSFont.userFixedPitchFont(ofSize: 11 * scale) ??
            NSFont.systemFont(ofSize: 11 * scale, weight: .medium)
        sourceLabel.font = NSFont.systemFont(
            ofSize: 8.5 * scale,
            weight: .regular
        )
        layer?.cornerRadius = 12 * scale
    }

    func update(with cards: [ArenaRatedCard]) {
        let maximumVisibleCards = 6
        var rows = cards.prefix(maximumVisibleCards).map { card -> String in
            let score = card.score.map(String.init) ?? "—"
            let name = card.card.englishName.isEmpty
                ? card.card.cardId
                : card.card.englishName
            return "\(score)  \(name)"
        }
        if cards.count > maximumVisibleCards {
            rows.append("+\(cards.count - maximumVisibleCards) more")
        }
        scoresLabel.stringValue = rows.joined(separator: "\n")
    }
}
