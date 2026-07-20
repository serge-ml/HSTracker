//
//  HearthArenaHTMLParser.swift
//  HSTracker
//

import Foundation

enum HearthArenaParserError: LocalizedError {
    case invalidEncoding
    case noRatings

    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "The HearthArena response is not valid UTF-8."
        case .noRatings:
            return "The HearthArena page did not contain any tier ratings."
        }
    }
}

final class HearthArenaHTMLParser {
    func parse(data: Data, fetchedAt: Date = Date()) throws -> TierListSnapshot {
        guard let html = String(data: data, encoding: .utf8) else {
            throw HearthArenaParserError.invalidEncoding
        }
        return try parse(html: html, fetchedAt: fetchedAt)
    }

    func parse(html: String, fetchedAt: Date = Date()) throws -> TierListSnapshot {
        var ratings = [TierRating]()

        for heroClass in HearthArenaHeroClass.allCases {
            guard let section = sectionHTML(for: heroClass, in: html) else {
                continue
            }
            ratings.append(contentsOf: parseRatings(in: section, heroClass: heroClass))
        }

        guard !ratings.isEmpty else {
            throw HearthArenaParserError.noRatings
        }

        let data = html.data(using: .utf8) ?? Data()
        return TierListSnapshot(
            fetchedAt: fetchedAt,
            contentHash: HearthArenaContentHasher.hash(data),
            ratings: ratings
        )
    }

    private func sectionHTML(
        for heroClass: HearthArenaHeroClass,
        in html: String
    ) -> String? {
        let slug = NSRegularExpression.escapedPattern(for: heroClass.tierListSlug)
        let pattern = "(?is)<section\\b[^>]*\\bid=[\"']\(slug)[\"'][^>]*>(.*?)</section>"
        guard
            let expression = try? NSRegularExpression(pattern: pattern),
            let match = expression.firstMatch(
                in: html,
                range: NSRange(html.startIndex..., in: html)
            ),
            let range = Range(match.range(at: 1), in: html)
        else {
            return nil
        }
        return String(html[range])
    }

    private func parseRatings(
        in section: String,
        heroClass: HearthArenaHeroClass
    ) -> [TierRating] {
        let pattern = [
            "(?is)<dl\\b[^>]*class=[\"'][^\"']*\\bcard\\b[^\"']*[\"'][^>]*>",
            "\\s*<dt\\b([^>]*)>(.*?)</dt>",
            "\\s*<dd\\b[^>]*class=[\"'][^\"']*\\bscore\\b[^\"']*[\"'][^>]*>(.*?)</dd>",
            "\\s*</dl>"
        ].joined()

        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        return expression.matches(
            in: section,
            range: NSRange(section.startIndex..., in: section)
        ).compactMap { match in
            guard
                let attributesRange = Range(match.range(at: 1), in: section),
                let nameRange = Range(match.range(at: 2), in: section),
                let scoreRange = Range(match.range(at: 3), in: section)
            else {
                return nil
            }

            let attributes = String(section[attributesRange])
            let nameMarkup = removingBadgeMarkup(from: String(section[nameRange]))
            let rawName = HearthArenaTextNormalizer.strippingHTMLTags(nameMarkup)
            let cardName = HearthArenaTextNormalizer.decodeHTMLEntities(rawName)
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            let rawScore = HearthArenaTextNormalizer.strippingHTMLTags(
                String(section[scoreRange])
            )
            guard
                !cardName.isEmpty,
                let score = firstInteger(in: rawScore)
            else {
                return nil
            }

            return TierRating(
                heroClass: heroClass,
                cardId: cardId(from: attributes),
                cardName: cardName,
                score: score
            )
        }
    }

    private func cardId(from attributes: String) -> String? {
        let pattern = "(?i)data-card-image=[\"'][^\"']*/([^/\"'?]+)\\.(?:webp|png|jpe?g)(?:\\?[^\"']*)?[\"']"
        guard
            let expression = try? NSRegularExpression(pattern: pattern),
            let match = expression.firstMatch(
                in: attributes,
                range: NSRange(attributes.startIndex..., in: attributes)
            ),
            let range = Range(match.range(at: 1), in: attributes)
        else {
            return nil
        }
        return HearthArenaTextNormalizer.decodeHTMLEntities(String(attributes[range]))
    }

    private func removingBadgeMarkup(from value: String) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: [
                "(?is)<span\\b[^>]*\\bclass=[\"']",
                "[^\"']*(?:\\bnew\\b|\\bbadge\\b)[^\"']*[\"'][^>]*>",
                ".*?</span>"
            ].joined()
        ) else {
            return value
        }
        return expression.stringByReplacingMatches(
            in: value,
            range: NSRange(value.startIndex..., in: value),
            withTemplate: ""
        )
    }

    private func firstInteger(in value: String) -> Int? {
        guard
            let expression = try? NSRegularExpression(pattern: "-?[0-9]+"),
            let match = expression.firstMatch(
                in: value,
                range: NSRange(value.startIndex..., in: value)
            ),
            let range = Range(match.range(at: 0), in: value)
        else {
            return nil
        }
        return Int(value[range])
    }
}

private enum HearthArenaContentHasher {
    static func hash(_ data: Data) -> String {
        var value: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            value ^= UInt64(byte)
            value = value &* 1_099_511_628_211
        }
        return String(format: "fnv1a64:%016llx", value)
    }
}
