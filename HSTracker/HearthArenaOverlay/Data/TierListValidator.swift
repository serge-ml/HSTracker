//
//  TierListValidator.swift
//  HSTracker
//

import Foundation

struct TierListValidationPolicy {
    let minimumRatingCount: Int
    let minimumRatingsPerClass: Int
    let allowedScoreRange: ClosedRange<Int>
    let maximumDuplicateRatio: Double
    let minimumPreviousCoverageRatio: Double
    let requiredClasses: Set<HearthArenaHeroClass>

    static let production = TierListValidationPolicy(
        minimumRatingCount: 500,
        minimumRatingsPerClass: 50,
        allowedScoreRange: 0...200,
        maximumDuplicateRatio: 0.02,
        minimumPreviousCoverageRatio: 0.65,
        requiredClasses: Set(HearthArenaHeroClass.allCases)
    )
}

enum TierListValidationError: LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case unsupportedParser(Int)
    case invalidSource
    case tooFewRatings(actual: Int, minimum: Int)
    case tooFewRatingsForClass(
        heroClass: HearthArenaHeroClass,
        actual: Int,
        minimum: Int
    )
    case missingClasses([HearthArenaHeroClass])
    case scoreOutOfRange(cardName: String, score: Int)
    case tooManyDuplicates(actual: Int, allowed: Int)
    case coverageDropped(actual: Int, previous: Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "Unsupported HearthArena cache schema \(version)."
        case .unsupportedParser(let version):
            return "Unsupported HearthArena parser version \(version)."
        case .invalidSource:
            return "The tier list snapshot has an unexpected source."
        case .tooFewRatings(let actual, let minimum):
            return "Tier list contains \(actual) ratings; at least \(minimum) are required."
        case .tooFewRatingsForClass(let heroClass, let actual, let minimum):
            return "\(heroClass.rawValue) contains \(actual) ratings; at least \(minimum) are required."
        case .missingClasses(let classes):
            return "Tier list is missing: \(classes.map { $0.rawValue }.joined(separator: ", "))."
        case .scoreOutOfRange(let cardName, let score):
            return "Tier score \(score) for \(cardName) is outside the accepted range."
        case .tooManyDuplicates(let actual, let allowed):
            return "Tier list contains \(actual) duplicate entries; at most \(allowed) are allowed."
        case .coverageDropped(let actual, let previous):
            return "Tier list coverage dropped from \(previous) to \(actual) entries."
        }
    }
}

final class TierListValidator {
    private let policy: TierListValidationPolicy

    init(policy: TierListValidationPolicy = .production) {
        self.policy = policy
    }

    func validate(
        _ snapshot: TierListSnapshot,
        previous: TierListSnapshot? = nil
    ) throws {
        guard snapshot.schemaVersion == TierListSnapshot.currentSchemaVersion else {
            throw TierListValidationError.unsupportedSchema(snapshot.schemaVersion)
        }
        guard snapshot.parserVersion == TierListSnapshot.currentParserVersion else {
            throw TierListValidationError.unsupportedParser(snapshot.parserVersion)
        }
        guard snapshot.source == TierListSnapshot.sourceURL else {
            throw TierListValidationError.invalidSource
        }
        guard snapshot.ratings.count >= policy.minimumRatingCount else {
            throw TierListValidationError.tooFewRatings(
                actual: snapshot.ratings.count,
                minimum: policy.minimumRatingCount
            )
        }

        let presentClasses = Set(snapshot.ratings.map { $0.heroClass })
        let missingClasses = policy.requiredClasses
            .subtracting(presentClasses)
            .sorted { $0.rawValue < $1.rawValue }
        guard missingClasses.isEmpty else {
            throw TierListValidationError.missingClasses(missingClasses)
        }
        for heroClass in policy.requiredClasses {
            let classCount = snapshot.ratings.reduce(into: 0) { count, rating in
                if rating.heroClass == heroClass {
                    count += 1
                }
            }
            guard classCount >= policy.minimumRatingsPerClass else {
                throw TierListValidationError.tooFewRatingsForClass(
                    heroClass: heroClass,
                    actual: classCount,
                    minimum: policy.minimumRatingsPerClass
                )
            }
        }

        for rating in snapshot.ratings where !policy.allowedScoreRange.contains(rating.score) {
            throw TierListValidationError.scoreOutOfRange(
                cardName: rating.cardName,
                score: rating.score
            )
        }

        let duplicateCount = countDuplicates(in: snapshot.ratings)
        let allowedDuplicates = Int(
            Double(snapshot.ratings.count) * policy.maximumDuplicateRatio
        )
        guard duplicateCount <= allowedDuplicates else {
            throw TierListValidationError.tooManyDuplicates(
                actual: duplicateCount,
                allowed: allowedDuplicates
            )
        }

        if let previous = previous {
            let minimumCount = Int(
                Double(previous.ratings.count) * policy.minimumPreviousCoverageRatio
            )
            guard snapshot.ratings.count >= minimumCount else {
                throw TierListValidationError.coverageDropped(
                    actual: snapshot.ratings.count,
                    previous: previous.ratings.count
                )
            }
        }
    }

    private func countDuplicates(in ratings: [TierRating]) -> Int {
        var keys = Set<String>()
        var duplicates = 0

        for rating in ratings {
            let identity = rating.cardId?.uppercased()
                ?? HearthArenaTextNormalizer.canonicalCardName(rating.cardName)
            let key = "\(rating.heroClass.rawValue)|\(identity)"
            if !keys.insert(key).inserted {
                duplicates += 1
            }
        }
        return duplicates
    }
}
