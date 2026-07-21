//
// Compile with ArenaOffer.swift, TierRating.swift and ArenaChoiceAdapter.swift.
// The small mirror/card stubs make the adapter boundary executable without the
// complete HSTracker target.
//

import Foundation

enum CardClass: String {
    case deathknight
    case demonhunter
    case druid
    case hunter
    case mage
    case paladin
    case priest
    case rogue
    case shaman
    case warlock
    case warrior
    case neutral
    case invalid
}

struct MirrorCard {
    let cardId: String
    let count: NSNumber

    init(cardId: String, count: Int = 1) {
        self.cardId = cardId
        self.count = NSNumber(value: count)
    }
}

struct MirrorDeck {
    let hero: String
    let cards: [MirrorCard]

    init(hero: String, cards: [MirrorCard] = []) {
        self.hero = hero
        self.cards = cards
    }
}

struct ChoicesChangedEventArgs {
    let choices: [MirrorCard]
    let heroCardId: String
    let currentSlot: Int
    let isUnderground: Bool
    let packages: [[MirrorCard]]
    let version: Int

    init(
        choices: [MirrorCard],
        heroCardId: String,
        currentSlot: Int,
        isUnderground: Bool,
        packages: [[MirrorCard]],
        version: Int
    ) {
        self.choices = choices
        self.heroCardId = heroCardId
        self.currentSlot = currentSlot
        self.isUnderground = isUnderground
        self.packages = packages
        self.version = version
    }

    init(
        choices: [MirrorCard],
        deck: MirrorDeck,
        currentSlot: Int,
        isUnderground: Bool,
        packages: [[MirrorCard]],
        version: Int
    ) {
        self.init(
            choices: choices,
            heroCardId: deck.hero,
            currentSlot: currentSlot,
            isUnderground: isUnderground,
            packages: packages,
            version: version
        )
    }
}

struct DeckEditChangedEventArgs {
    let deck: MirrorDeck
    let discardedCardIds: [String]
    let isUnderground: Bool
}

struct StubCard {
    let playerClass: CardClass
    let dbfId: Int
    let englishName: String
    let cost: Int
    let name: String

    init(
        playerClass: CardClass,
        dbfId: Int,
        englishName: String,
        cost: Int = 0,
        name: String? = nil
    ) {
        self.playerClass = playerClass
        self.dbfId = dbfId
        self.englishName = englishName
        self.cost = cost
        self.name = name ?? englishName
    }
}

typealias Card = StubCard

enum Cards {
    private static let heroes = [
        "HERO_MAGE": StubCard(
            playerClass: .mage,
            dbfId: 637,
            englishName: "Jaina Proudmoore"
        ),
        "HERO_INVALID": StubCard(
            playerClass: .invalid,
            dbfId: 0,
            englishName: "Invalid"
        )
    ]
    private static let cards = [
        "CARD_A": StubCard(
            playerClass: .mage,
            dbfId: 101,
            englishName: "Card A"
        ),
        "CARD_B": StubCard(
            playerClass: .neutral,
            dbfId: 102,
            englishName: "Card B",
            cost: 2
        ),
        "CARD_C": StubCard(
            playerClass: .neutral,
            dbfId: 103,
            englishName: "Card C",
            cost: 3
        ),
        "KAR_057": StubCard(
            playerClass: .paladin,
            dbfId: 39439,
            englishName: "Ivory Knight"
        )
    ]

    static func hero(byId: String) -> StubCard? {
        heroes[byId]
    }

    static func any(byId: String) -> StubCard? {
        cards[byId]
    }
}

@main
enum HearthArenaAdapterSmoke {
    static func main() throws {
        let adapter = ArenaChoiceAdapter()
        let package = [
            MirrorCard(cardId: "CARD_A"),
            MirrorCard(cardId: "CARD_B")
        ]
        let offer = try adapter.makeOffer(
            from: ChoicesChangedEventArgs(
                choices: [
                    MirrorCard(cardId: "CARD_A"),
                    MirrorCard(cardId: "CARD_B"),
                    MirrorCard(cardId: "CORE_KAR_057")
                ],
                heroCardId: "HERO_MAGE",
                currentSlot: 7,
                isUnderground: true,
                packages: [package, package, package],
                version: 42
            )
        )

        try require(offer.heroClass == .mage, "hero class")
        try require(offer.draftSlot == 7, "draft slot")
        try require(offer.offerVersion == 42, "offer version")
        try require(offer.isUnderground, "Underground flag")
        try require(
            offer.cards.map(\.cardId) == [
                "CARD_A", "CARD_B", "CORE_KAR_057"
            ],
            "choice IDs"
        )
        try require(
            offer.cards.map(\.dbfId) == [101, 102, 39439],
            "database IDs"
        )
        try require(
            offer.cards.map(\.englishName) == [
                "Card A", "Card B", "Ivory Knight"
            ],
            "English-name lookup and CORE fallback"
        )
        try require(
            offer.packages.count == 3 &&
                offer.packages.allSatisfy {
                    $0.map(\.cardId) == ["CARD_A", "CARD_B"]
                },
            "package conversion"
        )

        try expectMissingHero(adapter)
        try expectUnsupportedClass(adapter)
        try expectEmptyChoices(adapter)
        try testDeckEdit(adapter)
        print("heartharena_adapter_smoke=passed")
    }

    private static func testDeckEdit(
        _ adapter: ArenaChoiceAdapter
    ) throws {
        let deck = MirrorDeck(
            hero: "HERO_MAGE",
            cards: [
                MirrorCard(cardId: "CARD_B", count: 28),
                MirrorCard(cardId: "CARD_A", count: 2)
            ]
        )
        let edit = try adapter.makeDeckEdit(
            from: DeckEditChangedEventArgs(
                deck: deck,
                discardedCardIds: [
                    "CARD_A", "CARD_C", "CARD_C", "CARD_C", "CARD_C"
                ],
                isUnderground: true
            )
        )

        try require(
            edit.discardedCards.map(\.cardId) == [
                "CARD_A", "CARD_C", "CARD_C", "CARD_C", "CARD_C"
            ],
            "five physical discard slots preserve their order"
        )
    }

    private static func expectMissingHero(
        _ adapter: ArenaChoiceAdapter
    ) throws {
        do {
            _ = try adapter.makeOffer(
                from: arguments(hero: "MISSING_HERO")
            )
            throw AdapterSmokeFailure("Missing hero unexpectedly accepted")
        } catch ArenaChoiceAdapterError.missingHero(let cardId) {
            try require(cardId == "MISSING_HERO", "missing-hero context")
        }
    }

    private static func expectUnsupportedClass(
        _ adapter: ArenaChoiceAdapter
    ) throws {
        do {
            _ = try adapter.makeOffer(
                from: arguments(hero: "HERO_INVALID")
            )
            throw AdapterSmokeFailure(
                "Unsupported hero class unexpectedly accepted"
            )
        } catch ArenaChoiceAdapterError.unsupportedHeroClass(let cardClass) {
            try require(cardClass == .invalid, "unsupported-class context")
        }
    }

    private static func expectEmptyChoices(
        _ adapter: ArenaChoiceAdapter
    ) throws {
        do {
            _ = try adapter.makeOffer(
                from: ChoicesChangedEventArgs(
                    choices: [],
                    deck: MirrorDeck(hero: "HERO_MAGE"),
                    currentSlot: 1,
                    isUnderground: false,
                    packages: [],
                    version: 1
                )
            )
            throw AdapterSmokeFailure("Empty choices unexpectedly accepted")
        } catch ArenaChoiceAdapterError.emptyChoices {
            return
        }
    }

    private static func arguments(hero: String) -> ChoicesChangedEventArgs {
        ChoicesChangedEventArgs(
            choices: [MirrorCard(cardId: "CARD_A")],
            deck: MirrorDeck(hero: hero),
            currentSlot: 1,
            isUnderground: false,
            packages: [],
            version: 1
        )
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ description: String
    ) throws {
        guard condition() else {
            throw AdapterSmokeFailure("Failed: \(description)")
        }
    }
}

private struct AdapterSmokeFailure: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
