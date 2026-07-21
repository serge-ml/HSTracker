//
//  HSReplayArenaOverlayLayout.swift
//  HSTracker
//

import AppKit

enum HSReplayArenaOverlayLayout {
    private static let referenceHeight: CGFloat = 922
    private static let heroCenterRatios: [CGFloat] = [0.225, 0.515, 0.80]

    static func heroBadgeFrames(
        in contentSize: NSSize,
        scale userScale: CGFloat,
        verticalOffset: CGFloat
    ) -> [NSRect] {
        guard contentSize.width > 0, contentSize.height > 0 else {
            return []
        }

        let screenScale = contentSize.height / referenceHeight
        let scale = max(0.5, screenScale * userScale)
        let badgeSize = NSSize(width: 156 * scale, height: 52 * scale)
        // Hearthstone's centered 4:3 area contains a square Arena board on
        // the left and the deck column on the right.
        let gameWidth = min(
            contentSize.width,
            contentSize.height * (4.0 / 3.0)
        )
        let boardWidth = min(gameWidth, contentSize.height)
        let boardOriginX = (contentSize.width - gameWidth) / 2
        let centerY =
            contentSize.height * 0.45 + verticalOffset * screenScale

        return heroCenterRatios.map { ratio in
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
    }
}
