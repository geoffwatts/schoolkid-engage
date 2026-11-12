import Foundation

extension Assessment {
    /// Whether a grade, percentage or score has been released.
    public var hasMark: Bool { !grade.isEmpty || !percentage.isEmpty || !score.isEmpty }
    /// The result on a 0–100 scale for ordering: the percentage when SEQTA gives one, otherwise the usual midpoint of
    /// a letter grade (A+ 97, A 93, A- 90, B+ 87 … E 30). A bare score has no total, so it can't be placed; nil.
    public var markValue: Double? {
        if let value = Double(percentage.trimmingCharacters(in: .whitespaces)) { return value }
        let letter = grade.trimmingCharacters(in: .whitespaces).uppercased()
        guard let base = ["A": 93.0, "B": 83, "C": 73, "D": 63, "E": 50, "F": 30][String(letter.prefix(1))], letter.count <= 2 else { return nil }
        return base + (letter.hasSuffix("+") ? 4 : letter.hasSuffix("-") ? -3 : 0)
    }
    /// The due date when it's an ISO date ("2026-11-13", optionally with a time), as SEQTA sends it.
    public var dueDate: Date? {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(due.prefix(10)))
    }
}

/// How an assessment list is ordered. Date orders keep undated assessments at the end; mark orders keep unmarked ones
/// at the end, so the extremes are always real results.
public enum AssessmentSort: String, CaseIterable, Sendable {
    case newestFirst, oldestFirst, subject, highestMark, lowestMark
    public var usesMarks: Bool { self == .highestMark || self == .lowestMark }
}

/// Which assessments a list shows.
public enum AssessmentShow: String, CaseIterable, Sendable {
    case all
    /// A grade, percentage or score has been released.
    case marked
    /// Written feedback has been released.
    case feedback
    /// Neither a mark nor feedback yet.
    case awaiting
    /// Past due without a submission.
    case overdue
    public func includes(_ assessment: Assessment) -> Bool {
        switch self {
        case .all: return true
        case .marked: return assessment.hasMark
        case .feedback: return assessment.hasFeedback
        case .awaiting: return !assessment.hasMark && !assessment.hasFeedback
        case .overdue: return assessment.overdue
        }
    }
}

public enum AssessmentListing {
    /// Filters by what's shown, subject (exact, when given) and a search of the title and subject, then sorts.
    public static func arrange(_ items: [Assessment], sort: AssessmentSort, show: AssessmentShow = .all,
                               subject: String? = nil, search: String = "") -> [Assessment] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let kept = items.filter { item in
            show.includes(item) && (subject == nil || item.subject == subject)
                && (query.isEmpty || item.displayTitle.localizedCaseInsensitiveContains(query) || item.subject.localizedCaseInsensitiveContains(query))
        }
        // Ties keep SEQTA's order, so equal dates or marks don't shuffle between loads.
        let indexed = Array(kept.enumerated())
        func last<T: Comparable>(_ a: T?, _ b: T?, _ ascending: Bool) -> Bool? {
            switch (a, b) {
            case let (x?, y?): return x == y ? nil : (ascending ? x < y : x > y)
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return nil
            }
        }
        return indexed.sorted { lhs, rhs in
            let (a, b) = (lhs.element, rhs.element)
            let decided: Bool?
            switch sort {
            case .newestFirst: decided = last(a.dueDate, b.dueDate, false)
            case .oldestFirst: decided = last(a.dueDate, b.dueDate, true)
            case .subject:
                let order = a.subject.localizedCaseInsensitiveCompare(b.subject)
                decided = order == .orderedSame ? last(a.dueDate, b.dueDate, false) : order == .orderedAscending
            case .highestMark: decided = last(a.markValue, b.markValue, false)
            case .lowestMark: decided = last(a.markValue, b.markValue, true)
            }
            return decided ?? (lhs.offset < rhs.offset)
        }.map(\.element)
    }
}
