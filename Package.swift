// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "HearthArenaCore",
    platforms: [
        .macOS(.v10_14)
    ],
    products: [
        .library(
            name: "HearthArenaCore",
            targets: ["HearthArenaCore"]
        )
    ],
    targets: [
        .target(
            name: "HearthArenaCore",
            path: "HSTracker/HearthArenaOverlay",
            exclude: [
                "Integration",
                "Settings",
                "UI"
            ],
            sources: [
                "Domain/ArenaOffer.swift",
                "Domain/ArenaOfferStateMachine.swift",
                "Domain/ArenaRatedCard.swift",
                "Domain/TierRating.swift",
                "Data/CardIdentityResolver.swift",
                "Data/HearthArenaClient.swift",
                "Data/HearthArenaHTMLParser.swift",
                "Data/HearthArenaTextNormalizer.swift",
                "Data/HearthArenaTierListStore.swift",
                "Data/TierListCache.swift",
                "Data/TierListValidator.swift",
                "Diagnostics/HearthArenaDiagnostics.swift"
            ]
        ),
        .testTarget(
            name: "HearthArenaCoreTests",
            dependencies: ["HearthArenaCore"],
            path: "HSTrackerTests/HearthArenaOverlay",
            sources: ["HearthArenaOverlayTests.swift"],
            resources: [
                .copy("Fixtures/heartharena-tierlist-sample.html")
            ]
        )
    ]
)
