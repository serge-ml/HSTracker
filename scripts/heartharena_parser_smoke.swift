//
// Compile this file together with HearthArenaOverlay/Domain and Data sources.
// It intentionally has no dependency on the HSTracker app target.
//

import Foundation

@main
enum HearthArenaParserSmoke {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw SmokeError.usage
        }

        let fileURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let data = try Data(contentsOf: fileURL)
        let snapshot = try HearthArenaHTMLParser().parse(data: data)
        try TierListValidator().validate(snapshot)

        let classes = Set(snapshot.ratings.map { $0.heroClass })
        let withCardId = snapshot.ratings.filter { $0.cardId != nil }.count
        print("ratings=\(snapshot.ratings.count)")
        print("classes=\(classes.count)")
        print("card_ids=\(withCardId)")
        print("hash=\(snapshot.contentHash)")
    }
}

private enum SmokeError: LocalizedError {
    case usage

    var errorDescription: String? {
        return "Usage: heartharena-parser-smoke /path/to/tierlist.html"
    }
}
