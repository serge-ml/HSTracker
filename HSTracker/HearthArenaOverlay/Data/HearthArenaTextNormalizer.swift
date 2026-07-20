//
//  HearthArenaTextNormalizer.swift
//  HSTracker
//

import Foundation

enum HearthArenaTextNormalizer {
    static func canonicalCardName(_ value: String) -> String {
        let decoded = decodeHTMLEntities(value)
        let punctuationNormalized = decoded
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{02BC}", with: "'")
            .replacingOccurrences(of: "\u{2010}", with: "-")
            .replacingOccurrences(of: "\u{2011}", with: "-")
            .replacingOccurrences(of: "\u{2012}", with: "-")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .replacingOccurrences(of: "\u{2212}", with: "-")

        return punctuationNormalized
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    static func decodeHTMLEntities(_ value: String) -> String {
        var result = value
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")

        let pattern = "&#(x[0-9A-Fa-f]+|[0-9]+);"
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return result
        }

        let matches = expression.matches(
            in: result,
            range: NSRange(result.startIndex..., in: result)
        ).reversed()

        for match in matches {
            guard
                let entityRange = Range(match.range(at: 1), in: result),
                let fullRange = Range(match.range(at: 0), in: result)
            else {
                continue
            }

            let entity = String(result[entityRange])
            let radix = entity.hasPrefix("x") ? 16 : 10
            let digits = entity.hasPrefix("x") ? String(entity.dropFirst()) : entity
            guard
                let scalarValue = UInt32(digits, radix: radix),
                let scalar = UnicodeScalar(scalarValue)
            else {
                continue
            }
            result.replaceSubrange(fullRange, with: String(Character(scalar)))
        }
        return result
    }

    static func strippingHTMLTags(_ value: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: "<[^>]+>") else {
            return value
        }
        let range = NSRange(value.startIndex..., in: value)
        return expression.stringByReplacingMatches(in: value, range: range, withTemplate: "")
    }
}
