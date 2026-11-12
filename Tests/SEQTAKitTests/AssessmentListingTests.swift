import XCTest
@testable import SEQTAKit

final class AssessmentListingTests: XCTestCase {
    private func item(_ id: Int, _ subject: String, due: String = "", status: String = "", grade: String? = nil,
                      percentage: Double? = nil, score: Double? = nil, feedback: Bool = false, overdue: Bool = false,
                      title: String? = nil) throws -> Assessment {
        var json: [String: JSONValue] = ["id": .number(Double(id)), "title": .string(title ?? "Task \(id)"), "subject": .string(subject),
                                         "due": .string(due), "status": .string(status), "hasFeedback": .bool(feedback), "overdue": .bool(overdue)]
        var results: [String: JSONValue] = [:]
        if let grade { results["grade"] = .string(grade) }
        if let percentage { results["percentage"] = .number(percentage) }
        if let score { results["score"] = .number(score) }
        if !results.isEmpty { json["results"] = .object(results) }
        return try Assessment(json: .object(json))
    }
    private var list: [Assessment] {
        get throws {
            [try item(1, "English", due: "2026-10-28", status: "FEEDBACK_RELEASED", feedback: true, title: "Book talk"),
             try item(2, "Mathematics", due: "2026-10-30", status: "MARKS_RELEASED", grade: "B+", percentage: 84),
             try item(3, "Physics", due: "2026-10-23", status: "MARKS_RELEASED", grade: "A", percentage: 94, feedback: true),
             try item(4, "Humanities", due: "2026-11-04", status: "PENDING", overdue: true),
             try item(5, "Visual Arts", due: "2026-10-09", status: "MARKS_RELEASED", grade: "A-"),
             try item(6, "English", status: "MARKS_RELEASED", score: 18)]
        }
    }
    private func ids(_ items: [Assessment]) -> [String] { items.map(\.id) }

    func testDatesSortEitherWayWithUndatedLast() throws {
        XCTAssertEqual(ids(AssessmentListing.arrange(try list, sort: .newestFirst)), ["4", "2", "1", "3", "5", "6"])
        XCTAssertEqual(ids(AssessmentListing.arrange(try list, sort: .oldestFirst)), ["5", "3", "1", "2", "4", "6"])
    }

    func testMarksSortByPercentageThenGradeWithUnplaceableLast() throws {
        // Physics 94%, Visual Arts A- (≈90), Maths 84%; English 18 has no total and the rest have no mark.
        XCTAssertEqual(ids(AssessmentListing.arrange(try list, sort: .highestMark)).prefix(3), ["3", "5", "2"])
        XCTAssertEqual(ids(AssessmentListing.arrange(try list, sort: .lowestMark)).prefix(3), ["2", "5", "3"])
    }

    func testSubjectSortGroupsSubjectsNewestFirstWithin() throws {
        XCTAssertEqual(ids(AssessmentListing.arrange(try list, sort: .subject)), ["1", "6", "4", "2", "3", "5"])
    }

    func testShowFilters() throws {
        let all = try list
        XCTAssertEqual(Set(ids(AssessmentListing.arrange(all, sort: .newestFirst, show: .marked))), ["2", "3", "5", "6"])
        XCTAssertEqual(Set(ids(AssessmentListing.arrange(all, sort: .newestFirst, show: .feedback))), ["1", "3"])
        XCTAssertEqual(ids(AssessmentListing.arrange(all, sort: .newestFirst, show: .awaiting)), ["4"])
        XCTAssertEqual(ids(AssessmentListing.arrange(all, sort: .newestFirst, show: .overdue)), ["4"])
    }

    func testSubjectAndSearch() throws {
        XCTAssertEqual(ids(AssessmentListing.arrange(try list, sort: .newestFirst, subject: "English")), ["1", "6"])
        XCTAssertEqual(ids(AssessmentListing.arrange(try list, sort: .newestFirst, search: "book")), ["1"])
        XCTAssertEqual(ids(AssessmentListing.arrange(try list, sort: .newestFirst, search: "phys")), ["3"], "Search matches the subject too")
    }

    func testMarkValues() throws {
        XCTAssertEqual(try item(1, "X", grade: "A+").markValue, 97)
        XCTAssertEqual(try item(1, "X", grade: "C-").markValue, 70)
        XCTAssertEqual(try item(1, "X", grade: "B", percentage: 61).markValue, 61, "A percentage wins over a grade")
        XCTAssertNil(try item(1, "X", grade: "Excellent").markValue)
        XCTAssertNil(try item(1, "X", score: 18).markValue)
        XCTAssertTrue(try item(1, "X", score: 18).hasMark)
    }
}
