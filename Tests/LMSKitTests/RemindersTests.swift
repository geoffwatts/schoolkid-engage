import XCTest
@testable import LMSKit

final class RemindersTests: XCTestCase {
    private func kind(_ subject: String) -> String {
        switch subject.lowercased() {
        case "physical education", "hpe": return "health/general"
        case "dance": return "health/dance"
        case "music", "music ensemble": return "arts/music"
        default: return "general/general"
        }
    }
    private let week: [(subject: String, day: String)] = [
        ("English", "2026-11-16"), ("Physical Education", "2026-11-16"),
        ("Music", "2026-11-17"), ("Mathematics", "2026-11-17"),
        ("Dance", "2026-11-18"), ("Music Ensemble", "2026-11-18"),
        ("English", "2026-11-19")
    ]

    func testAKindCoversItsWholeFamilyAndASpecialismOnlyItself() {
        let sport = ReminderRule(note: "PE uniform", kinds: ["health"])
        let dance = ReminderRule(note: "Dance shoes", kinds: ["health/dance"])
        let notes = Reminders.notes(rules: [sport, dance], lessons: week, kind: kind).mapValues { $0.map(\.text) }
        XCTAssertEqual(notes["2026-11-16"], ["PE uniform"])
        XCTAssertEqual(notes["2026-11-18"], ["PE uniform", "Dance shoes"])
        XCTAssertNil(notes["2026-11-17"])
    }

    func testNamesMatchAnywhereInTheLessonIgnoringCase() {
        let tuba = ReminderRule(note: "Take tuba", subjects: ["music"])
        let notes = Reminders.notes(rules: [tuba], lessons: week, kind: kind).mapValues { $0.map(\.text) }
        XCTAssertEqual(notes["2026-11-17"], ["Take tuba"])
        XCTAssertEqual(notes["2026-11-18"], ["Take tuba"], "“music” matches Music Ensemble too")
        XCTAssertEqual(notes.count, 2)
    }

    func testSwitchedOffEmptyAndUntriggeredRulesShowNothing() {
        let rules = [ReminderRule(note: "PE uniform", isEnabled: false, kinds: ["health"]),
                     ReminderRule(note: "   ", kinds: ["health"]),
                     ReminderRule(note: "Nothing chosen")]
        XCTAssertTrue(Reminders.notes(rules: rules, lessons: week, kind: kind).isEmpty)
    }

    func testTheSameNoteFromTwoRulesShowsOnceInTheFirstRulesColour() {
        let rules = [ReminderRule(note: "Take tuba", subjects: ["Music"], color: "blue"), ReminderRule(note: " PE uniform", subjects: ["Dance"]),
                     ReminderRule(note: "PE uniform", kinds: ["health"], color: "red")]
        // Each note also remembers the rule it came from, so tapping it can open that rule.
        XCTAssertEqual(Reminders.notes(rules: rules, lessons: week, kind: kind)["2026-11-18"],
                       [ReminderNote(text: "Take tuba", color: "blue", ruleID: rules[0].id), ReminderNote(text: "PE uniform", ruleID: rules[1].id)])
    }

    func testANoteTakesTheIconOfTheFirstLessonThatSetItOff() {
        let symbol: (String) -> String? = { ["Physical Education": "figure.run", "Dance": "figure.dance"][$0] }
        let rules = [ReminderRule(note: "PE uniform", kinds: ["health"]), ReminderRule(note: "Take tuba", subjects: ["Music"])]
        let notes = Reminders.notes(rules: rules, lessons: week, kind: kind, symbol: symbol)
        XCTAssertEqual(notes["2026-11-16"]?.map(\.symbol), ["figure.run"])
        XCTAssertEqual(notes["2026-11-18"]?.map(\.symbol), ["figure.dance", nil], "Dance comes first that day; Music has no icon")
        // Snapshots written before icons existed still load, without one.
        XCTAssertNil(try JSONDecoder().decode(ReminderNote.self, from: Data(#"{"text":"PE uniform"}"#.utf8)).symbol)
    }

    func testExceptedLessonsKeepAReminderOffTheirDay() {
        let lessons: [(subject: String, day: String)] = [
            ("Physical Education", "2026-11-16"), ("Chapel", "2026-11-16"),
            ("Physical Education", "2026-11-17"),
            ("Dance", "2026-11-18"), ("Whole School Assembly", "2026-11-18"),
            ("Music", "2026-11-19")
        ]
        let rule = ReminderRule(note: "PE uniform", kinds: ["health"], exceptSubjects: ["assembly", "Chapel"])
        XCTAssertEqual(Reminders.notes(rules: [rule], lessons: lessons, kind: kind).keys.sorted(), ["2026-11-17"],
                       "Monday has Chapel and Wednesday an assembly, so only Tuesday keeps the reminder")
        let byKind = ReminderRule(note: "Gym bag", subjects: ["Physical Education"], exceptKinds: ["arts/music"])
        XCTAssertEqual(Reminders.notes(rules: [byKind], lessons: lessons + [("Music", "2026-11-17")], kind: kind).keys.sorted(), ["2026-11-16"])
    }

    func testRulesSurviveARoundTrip() throws {
        let rule = ReminderRule(note: "PE uniform", isEnabled: false, subjects: ["Dance"], kinds: ["health"], exceptSubjects: ["Chapel"], color: "green")
        XCTAssertEqual(try JSONDecoder().decode(ReminderRule.self, from: JSONEncoder().encode(rule)), rule)
        // Rules saved before colours existed still load, in the default colour.
        let old = #"{"id":"\#(rule.id.uuidString)","note":"PE uniform","isEnabled":true,"subjects":[],"kinds":["health"]}"#
        XCTAssertNil(try JSONDecoder().decode(ReminderRule.self, from: Data(old.utf8)).color)
        XCTAssertEqual(try JSONDecoder().decode(ReminderRule.self, from: Data(old.utf8)).exceptSubjects, [])
    }
}
