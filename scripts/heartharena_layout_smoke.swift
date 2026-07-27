//
// Compile with ArenaOverlayLayout.swift to validate overlay geometry without
// launching Hearthstone or the complete app target.
//

import AppKit

@main
enum HearthArenaLayoutSmoke {
    static func main() throws {
        let sizes = [
            NSSize(width: 1280, height: 720),
            NSSize(width: 1440, height: 922),
            NSSize(width: 2560, height: 1440)
        ]

        for size in sizes {
            for scale in [0.75, 1.0, 1.5] {
                let badges = ArenaOverlayLayout.badgeFrames(
                    in: size,
                    scale: scale,
                    verticalOffset: 0
                )
                try validate(
                    badges,
                    inside: size,
                    allowOverlap: false,
                    description: "card badges"
                )

                let packages = ArenaOverlayLayout.packageFrames(
                    in: size,
                    packageCardCounts: [2, 4, 6],
                    scale: scale,
                    verticalOffset: 0
                )
                try validate(
                    packages,
                    inside: size,
                    expectedCount: 3,
                    allowOverlap: false,
                    description: "package lists"
                )
                try require(
                    packages[0].height < packages[1].height &&
                        packages[1].height < packages[2].height,
                    "package height follows visible card count"
                )
                try require(
                    badges.allSatisfy { $0.midY < size.height * 0.5 },
                    "card badges stay in the strip below the cards"
                )

                let redraftBadges = ArenaOverlayLayout.redraftBadgeFrames(
                    in: size,
                    scale: scale,
                    verticalOffset: 0
                )
                try validate(
                    redraftBadges,
                    inside: size,
                    expectedCount: 5,
                    allowOverlap: true,
                    description: "redraft discard badges"
                )
                try require(
                    redraftBadges[0].midX == redraftBadges[1].midX &&
                        redraftBadges[0].midY > redraftBadges[1].midY,
                    "left redraft column follows HearthMirror slot order"
                )
                try require(
                    redraftBadges[3].midX == redraftBadges[4].midX &&
                        redraftBadges[3].midY > redraftBadges[4].midY,
                    "right redraft column follows HearthMirror slot order"
                )
                try require(
                    redraftBadges[0].midX < redraftBadges[2].midX &&
                        redraftBadges[2].midX < redraftBadges[3].midX,
                    "redraft columns remain ordered left to right"
                )

            }
        }

        let referenceBadges = ArenaOverlayLayout.badgeFrames(
            in: NSSize(width: 1440, height: 922),
            scale: 1,
            verticalOffset: 0
        )
        try require(
            abs(referenceBadges[0].midX - 338.91) < 0.1 &&
                abs(referenceBadges[1].midX - 572.48) < 0.1 &&
                abs(referenceBadges[2].midX - 806.05) < 0.1,
            "card badges align with the three Arena card centers"
        )
        try require(
            abs(referenceBadges[0].midY - 396.46) < 0.1,
            "card badges use the lower Arena strip"
        )
        let referenceRedraftBadges = ArenaOverlayLayout.redraftBadgeFrames(
            in: NSSize(width: 1440, height: 922),
            scale: 1,
            verticalOffset: 0
        )
        try require(
            abs(referenceRedraftBadges[1].midY - 129.08) < 0.1 &&
                abs(referenceRedraftBadges[4].midY - 129.08) < 0.1,
            "HearthMirror lower-slot badges align with the lower cards"
        )
        try require(
            abs(referenceRedraftBadges[0].midX - 338.91) < 0.1 &&
                abs(referenceRedraftBadges[1].midX - 338.91) < 0.1 &&
                abs(referenceRedraftBadges[2].midX - 572.48) < 0.1 &&
                abs(referenceRedraftBadges[3].midX - 806.05) < 0.1 &&
                abs(referenceRedraftBadges[4].midX - 806.05) < 0.1,
            "redraft frames match HearthMirror's column-major card order"
        )

        try require(
            ArenaOverlayLayout.badgeFrames(
                in: .zero,
                scale: 1,
                verticalOffset: 0
            ).isEmpty,
            "zero-sized card layout is rejected"
        )
        try require(
            ArenaOverlayLayout.packageFrames(
                in: NSSize(width: 1440, height: 922),
                packageCardCounts: [1, 2],
                scale: 1,
                verticalOffset: 0
            ).isEmpty,
            "package layout requires exactly three choices"
        )
        try require(
            ArenaOverlayLayout.redraftBadgeFrames(
                in: .zero,
                scale: 1,
                verticalOffset: 0
            ).isEmpty,
            "zero-sized redraft layout is rejected"
        )
        print("heartharena_layout_smoke=passed")
    }

    private static func validate(
        _ frames: [NSRect],
        inside size: NSSize,
        expectedCount: Int = 3,
        allowOverlap: Bool,
        description: String
    ) throws {
        try require(frames.count == expectedCount, "\(description) count")
        let bounds = NSRect(origin: .zero, size: size)
        for frame in frames {
            try require(
                bounds.contains(frame),
                "\(description) remain inside Hearthstone"
            )
            try require(
                frame.width > 0 && frame.height > 0,
                "\(description) have positive size"
            )
        }
        if expectedCount == 3 {
            try require(
                frames[0].midX < frames[1].midX &&
                    frames[1].midX < frames[2].midX,
                "\(description) preserve offer order"
            )
        }
        if !allowOverlap, expectedCount == 3 {
            try require(
                !frames[0].intersects(frames[1]) &&
                    !frames[1].intersects(frames[2]),
                "\(description) do not overlap"
            )
        }
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ description: String
    ) throws {
        guard condition() else {
            throw LayoutSmokeFailure(description)
        }
    }
}

private struct LayoutSmokeFailure: LocalizedError {
    let description: String

    init(_ description: String) {
        self.description = description
    }

    var errorDescription: String? {
        "Failed: \(description)"
    }
}
