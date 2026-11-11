import Foundation
import SwiftUI
import SEQTAKit

/// What the widgets show: the selected child's lessons and cycle days for roughly the next two weeks, written by the app
/// whenever it loads them and read by the widget extension. It lives in the shared App Group container on this device
/// only; nothing here is sent anywhere.
struct WidgetSnapshot: Codable, Equatable {
    struct Lesson: Codable, Equatable {
        let subject: String
        let start: Date
        let end: Date
        let room: String
    }
    let childName: String
    let generatedAt: Date
    /// Whether this school runs a ten-day cycle, so labels can say "Week A/B".
    let weekLetters: Bool
    /// SEQTA's cycle labels by day ("yyyy-MM-dd" → ["Day 3"]).
    let cycles: [String: [String]]
    /// Sorted by start time.
    let lessons: [Lesson]

    static let appGroup = "group.au.schoolkid.engage"
    private static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appendingPathComponent("widget-snapshot.json")
    }
    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
    /// Readable after first unlock, so Lock Screen widgets can show it.
    func save() {
        guard let url = Self.fileURL else { return }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        try? encoder.encode(self).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func clear() { if let url = fileURL { try? FileManager.default.removeItem(at: url) } }

    static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    /// "Day 3, Week A" (or "Day 3") for a date, when SEQTA gave one.
    func cycleText(on date: Date) -> String? { cycles[Self.dayKey(date)].flatMap { CycleLabel.text(for: $0, weekLetters: weekLetters) } }
    /// The cycle day number and, at fortnightly schools, its week letter.
    func cycleParts(on date: Date) -> (day: Int, week: Character?)? {
        guard let labels = cycles[Self.dayKey(date)], let day = CycleLabel.day(in: labels) else { return nil }
        return (day, CycleLabel.week(for: labels, weekLetters: weekLetters)?.last)
    }
    /// The lesson in progress at `date`, if any.
    func current(at date: Date) -> Lesson? { lessons.last { $0.start <= date && date < $0.end } }
    /// Lessons starting after `date`.
    func upcoming(after date: Date, limit: Int) -> [Lesson] { Array(lessons.filter { $0.start > date }.prefix(limit)) }
    /// True once the snapshot no longer covers `date` (the app hasn't been opened for a while).
    func isStale(at date: Date) -> Bool { (lessons.last?.end ?? generatedAt) < date && cycles[Self.dayKey(date)] == nil }
}

/// The Week A / Week B mark: an orange circled A or a purple squared B, so the weeks differ by shape as well as colour
/// (which also survives the Lock Screen's single-colour rendering).
struct WeekLetterGlyph: View {
    let letter: Character
    var body: some View {
        Image(systemName: letter == "A" ? "a.circle.fill" : "b.square.fill")
            .foregroundStyle(letter == "A" ? Color.orange : Color.purple)
            .accessibilityLabel("Week \(String(letter))")
    }
}
