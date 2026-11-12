import Foundation

/// An assessment's overall result, for headlines such as a printed page's corner: the best of whatever SEQTA reports.
public struct AssessmentResult: Equatable, Sendable {
    public let grade: String?
    public let score: String?
    public let outOf: String?
    public let percentage: String?

    public init(grade: String? = nil, score: String? = nil, outOf: String? = nil, percentage: String? = nil) {
        func clean(_ value: String?) -> String? { value.flatMap { $0.isEmpty ? nil : $0 } }
        self.grade = clean(grade); self.score = clean(score); self.outOf = clean(outOf)
        // A percentage SEQTA didn't give can still be worked out from the marks.
        self.percentage = clean(percentage) ?? {
            guard let s = clean(score).flatMap(Double.init), let t = clean(outOf).flatMap(Double.init), t > 0 else { return nil }
            return ScorePresentation.format(String((s / t * 100 * 10).rounded() / 10))
        }()
    }

    var isEmpty: Bool { grade == nil && score == nil && percentage == nil }
    /// "48 / 50", or the bare score when there's no total.
    public var displayScore: String? {
        score.map { ScorePresentation.format($0) + (outOf.map { " / " + ScorePresentation.format($0) } ?? "") }
    }
    /// "96%".
    public var displayPercentage: String? { percentage.map { ScorePresentation.format($0) + "%" } }

    /// Takes the assessment's own result from its details, then from the list it came from, and otherwise works it
    /// out from the criteria: one criterion's result is the assessment's; several add up when every one has marks, and
    /// share a grade only when they all agree. Nil when nothing, or only some criteria, have been released.
    public static func overall(assessment: Assessment, details: JSONValue?) -> AssessmentResult? {
        let detail = details?["results"] ?? .null
        let fromDetails = AssessmentResult(grade: detail["grade"].string, score: detail["score"].string,
                                           outOf: detail["target"].string ?? details?["target"].string, percentage: detail["percentage"].string)
        if !fromDetails.isEmpty { return fromDetails }
        let fromList = AssessmentResult(grade: assessment.grade, score: assessment.score,
                                        outOf: assessment.raw["results"]["target"].string ?? assessment.raw["target"].string,
                                        percentage: assessment.percentage)
        if !fromList.isEmpty { return fromList }
        let criteria = details?["criteria"].array ?? []
        let results = criteria.map { c in
            AssessmentResult(grade: c["results"]["grade"].string, score: c["results"]["score"].string,
                             outOf: c["results"]["target"].string ?? c["target"].string, percentage: c["results"]["percentage"].string)
        }.filter { !$0.isEmpty }
        // Only some criteria marked: any total would mislead, so there's no overall result yet.
        guard !results.isEmpty, results.count == criteria.count else { return nil }
        if results.count == 1 { return results[0] }
        return combined(results)
    }

    private static func combined(_ results: [AssessmentResult]) -> AssessmentResult? {
        let grades = Set(results.compactMap(\.grade))
        let grade = grades.count == 1 && results.allSatisfy({ $0.grade != nil }) ? grades.first : nil
        var score: String?, outOf: String?
        let scores = results.compactMap { r in r.score.flatMap(Double.init).flatMap { s in r.outOf.flatMap(Double.init).map { (s, $0) } } }
        if scores.count == results.count {
            score = ScorePresentation.format(String(scores.map(\.0).reduce(0, +)))
            outOf = ScorePresentation.format(String(scores.map(\.1).reduce(0, +)))
        }
        let result = AssessmentResult(grade: grade, score: score, outOf: outOf)
        return result.isEmpty ? nil : result
    }
}
