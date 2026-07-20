//
//  ArenaOverlayLayout.swift
//  HSTracker
//

import AppKit

enum ArenaOverlayLayout {
    private static let referenceHeight: CGFloat = 922
    private static let cardCenterRatios: [CGFloat] = [0.19, 0.38, 0.57]

    static func badgeFrames(
        in contentSize: NSSize,
        scale userScale: CGFloat,
        verticalOffset: CGFloat
    ) -> [NSRect] {
        guard contentSize.width > 0, contentSize.height > 0 else {
            return []
        }

        let screenScale = contentSize.height / referenceHeight
        let scale = max(0.5, screenScale * userScale)
        let badgeSize = NSSize(width: 112 * scale, height: 68 * scale)
        let boardWidth = min(contentSize.width, contentSize.height * (4.0 / 3.0))
        let boardOriginX = (contentSize.width - boardWidth) / 2
        let centerY = contentSize.height * 0.43 + verticalOffset * screenScale

        return cardCenterRatios.map { ratio in
            let centerX = boardOriginX + boardWidth * ratio
            let originX = min(
                max(centerX - badgeSize.width / 2, 0),
                contentSize.width - badgeSize.width
            )
            let originY = min(
                max(centerY - badgeSize.height / 2, 0),
                contentSize.height - badgeSize.height
            )
            return NSRect(origin: NSPoint(x: originX, y: originY), size: badgeSize)
        }
    }

    static func packageFrames(
        in contentSize: NSSize,
        packageCardCounts: [Int],
        scale userScale: CGFloat,
        verticalOffset: CGFloat
    ) -> [NSRect] {
        guard
            contentSize.width > 0,
            contentSize.height > 0,
            packageCardCounts.count == cardCenterRatios.count
        else {
            return []
        }

        let screenScale = contentSize.height / referenceHeight
        let scale = max(0.5, screenScale * userScale)
        let boardWidth = min(
            contentSize.width,
            contentSize.height * (4.0 / 3.0)
        )
        let boardOriginX = (contentSize.width - boardWidth) / 2
        let centerY = contentSize.height * 0.70 + verticalOffset * screenScale
        let centerSpacing = boardWidth * (
            cardCenterRatios[1] - cardCenterRatios[0]
        )
        let maximumWidth = min(
            contentSize.width,
            centerSpacing * 0.92
        )
        let layoutScale = min(
            scale,
            max(0.01, maximumWidth / 220)
        )

        return zip(cardCenterRatios, packageCardCounts).map { ratio, count in
            let visibleRows = CGFloat(min(max(count, 1), 6))
            let size = NSSize(
                width: 220 * layoutScale,
                height: (51 + visibleRows * 17) * layoutScale
            )
            let centerX = boardOriginX + boardWidth * ratio
            let originX = min(
                max(centerX - size.width / 2, 0),
                contentSize.width - size.width
            )
            let originY = min(
                max(centerY - size.height / 2, 0),
                contentSize.height - size.height
            )
            return NSRect(
                origin: NSPoint(x: originX, y: originY),
                size: size
            )
        }
    }

    static func redraftBadgeFrames(
        in contentSize: NSSize,
        scale userScale: CGFloat,
        verticalOffset: CGFloat
    ) -> [NSRect] {
        let topFrames = badgeFrames(
            in: contentSize,
            scale: userScale,
            verticalOffset: verticalOffset
        )
        guard topFrames.count == 3 else {
            return []
        }

        let screenScale = contentSize.height / referenceHeight
        let scale = max(0.5, screenScale * userScale)
        let badgeSize = NSSize(width: 112 * scale, height: 68 * scale)
        let boardWidth = min(
            contentSize.width,
            contentSize.height * (4.0 / 3.0)
        )
        let boardOriginX = (contentSize.width - boardWidth) / 2
        let centerY =
            contentSize.height * 0.14 + verticalOffset * screenScale

        let bottomFrames = [cardCenterRatios[0], cardCenterRatios[2]].map {
            ratio -> NSRect in
            let centerX = boardOriginX + boardWidth * ratio
            let originX = min(
                max(centerX - badgeSize.width / 2, 0),
                contentSize.width - badgeSize.width
            )
            let originY = min(
                max(centerY - badgeSize.height / 2, 0),
                contentSize.height - badgeSize.height
            )
            return NSRect(
                origin: NSPoint(x: originX, y: originY),
                size: badgeSize
            )
        }
        return topFrames + bottomFrames
    }

}
