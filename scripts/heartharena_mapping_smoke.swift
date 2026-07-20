//
// Compare HearthArena's current exact card IDs with the English card database
// consumed by the HSTracker data pipeline.
//

import Foundation

@main
enum HearthArenaMappingSmoke {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            throw MappingSmokeFailure(
                "Usage: heartharena-mapping-smoke tierlist.html cards.json"
            )
        }

        let tierData = try Data(
            contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])
        )
        let cardsData = try Data(
            contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])
        )
        let snapshot = try HearthArenaHTMLParser().parse(data: tierData)
        let cards = try JSONDecoder().decode(
            [HearthstoneJSONCard].self,
            from: cardsData
        )

        var ratingsById = [String: [TierRating]]()
        for rating in snapshot.ratings {
            guard let cardId = rating.cardId, !cardId.isEmpty else {
                continue
            }
            ratingsById[cardId.uppercased(), default: []].append(rating)
        }
        let cardsById = Dictionary(
            uniqueKeysWithValues: cards.map {
                ($0.id.uppercased(), $0)
            }
        )

        let tierIds = Set(ratingsById.keys)
        let matchedIds = tierIds.intersection(cardsById.keys)
        let missingIds = tierIds.subtracting(cardsById.keys).sorted()
        let coverage = tierIds.isEmpty
            ? 0
            : Double(matchedIds.count) / Double(tierIds.count)

        var nameMatchCount = 0
        for cardId in matchedIds {
            guard
                let databaseCard = cardsById[cardId],
                let ratings = ratingsById[cardId]
            else {
                continue
            }
            let databaseName = HearthArenaTextNormalizer.canonicalCardName(
                databaseCard.name
            )
            if ratings.contains(where: {
                HearthArenaTextNormalizer.canonicalCardName($0.cardName) ==
                    databaseName
            }) {
                nameMatchCount += 1
            }
        }

        print("unique_tier_cards=\(tierIds.count)")
        print("database_matches=\(matchedIds.count)")
        print(String(format: "card_id_coverage=%.3f%%", coverage * 100))
        print("canonical_name_matches=\(nameMatchCount)")
        if !missingIds.isEmpty {
            print(
                "missing_card_ids=" +
                missingIds.prefix(20).joined(separator: ",")
            )
        }

        guard tierIds.count >= 100 else {
            throw MappingSmokeFailure(
                "Tier list contains too few unique card IDs for a coverage audit."
            )
        }
        guard coverage >= 0.995 else {
            throw MappingSmokeFailure(
                String(
                    format:
                        "Exact card-ID coverage %.3f%% is below the 99.5%% target.",
                    coverage * 100
                )
            )
        }
    }
}

private struct HearthstoneJSONCard: Decodable {
    let id: String
    let name: String
}

private struct MappingSmokeFailure: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
