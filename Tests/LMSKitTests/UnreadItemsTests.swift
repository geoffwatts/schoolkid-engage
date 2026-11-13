import XCTest
@testable import LMSKit

final class UnreadItemsTests: XCTestCase {
    func testOpeningOneItemClearsOnlyThatItemAndScope() {
        var items = UnreadItems()
        items.record(["a", "b", "b"], in: "account1/news")
        items.record(["a"], in: "account2/news")
        items.record(["a"], in: "account1/reports/child1")
        items.record(["a"], in: "account1/reports/child2")
        items.markRead("a", in: "account1/news")
        XCTAssertEqual(items.count(in: "account1/news"), 1)
        for scope in ["account2/news", "account1/reports/child1", "account1/reports/child2"] {
            XCTAssertTrue(items.isUnread("a", in: scope))
        }
    }
    func testAccumulatedAndReplacedLists() {
        var items = UnreadItems()
        items.record(["old"], in: "news")
        items.record(["new"], in: "news")
        XCTAssertEqual(items.count(in: "news"), 2)
        items.markRead("old", in: "news")
        items.record(["old"], in: "news")
        XCTAssertEqual(items.count(in: "news"), 1)
        items.record(["old", "new"], in: "reports", replacing: true)
        items.record(["new"], in: "reports", replacing: true)
        XCTAssertEqual(items.count(in: "reports"), 1)
        XCTAssertFalse(items.isUnread("old", in: "reports"))
    }
    func testPersistenceAndAccountRemoval() throws {
        var items = UnreadItems()
        items.record(["a", "b"], in: "account1/news")
        items.markRead("a", in: "account1/news")
        items.record(["a"], in: "account2/news")
        let restored = try JSONDecoder().decode(UnreadItems.self, from: JSONEncoder().encode(items))
        XCTAssertEqual(restored, items)
        XCTAssertEqual(restored.count(in: "account1/news"), 1)
        items.remove(accountPrefix: "account1/")
        XCTAssertEqual(items.count(in: "account1/news"), 0)
        XCTAssertEqual(items.count(in: "account2/news"), 1)
    }
    func testShowingNewsClearsTheBadgeAndDropsUnavailableNotices() {
        var items = UnreadItems()
        items.record(["expired", "a", "b"], in: "account/news")
        items.didShow(["a", "b"], in: "account/news")
        XCTAssertEqual(items.count(in: "account/news"), 0)
        items.record(["a", "b", "c"], in: "account/news", replacing: true)
        XCTAssertEqual(items.count(in: "account/news"), 1)
        XCTAssertTrue(items.isUnread("c", in: "account/news"))
    }
    func testReportBaselineSuppressesHistoricalAndUnknownDatesButAllowsNewReports() throws {
        var items = UnreadItems()
        let installed = Date(timeIntervalSince1970: 1_800_000_000)
        // Migrate reports which were incorrectly badged by the previous version.
        items.record(["old", "unknown"], in: "account/reports/child1")
        let baseline = items.startTracking(in: "account/reports", at: installed)
        XCTAssertEqual(items.count(in: "account/reports/child1"), 0, "Historical badges clear as soon as tracking starts")
        items.recordDated([("old", installed.addingTimeInterval(-86_400)), ("unknown", nil),
                           ("new", installed.addingTimeInterval(86_400))], in: "account/reports/child1", since: baseline)
        XCTAssertEqual(items.count(in: "account/reports/child1"), 1)
        XCTAssertTrue(items.isUnread("new", in: "account/reports/child1"))
        XCTAssertFalse(items.isUnread("old", in: "account/reports/child1"))
        items.markRead("new", in: "account/reports/child1")
        XCTAssertEqual(items.count(in: "account/reports/child1"), 0)
        var restored = try JSONDecoder().decode(UnreadItems.self, from: JSONEncoder().encode(items))
        XCTAssertEqual(restored.startTracking(in: "account/reports", at: installed.addingTimeInterval(100_000)), installed)
        // A second child uses the account's original baseline, not the date the child was first selected.
        restored.recordDated([("new", installed.addingTimeInterval(86_400))], in: "account/reports/child2", since: baseline)
        XCTAssertEqual(restored.count(in: "account/reports/child2"), 1)
    }
    func testReportDateParsing() throws {
        func report(_ text: String) throws -> AcademicReport {
            try AcademicReport(json: .object(["uuid": .string("r"), "created_date": .string(text)]))
        }
        for date in ["2026-11-12", "2026-11-12T09:00:00+08:00", "2026-11-12T09:00:00.123+08:00", "12 November 2026", "12 Nov 2026", "12/11/2026"] {
            XCTAssertNotNil(try report(date).publishedAt, date)
        }
        XCTAssertNil(try report("not a date").publishedAt)
    }

}
