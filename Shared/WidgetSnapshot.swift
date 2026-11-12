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
    /// The reader's reminder notes by day ("yyyy-MM-dd" → "PE uniform" in yellow), worked out by the app from its
    /// reminder rules. Absent in snapshots written before reminders existed.
    var dayReminders: [String: [ReminderNote]]?

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
    /// The day being described: today while there's a lesson on or still to come today, otherwise the day of the next
    /// lesson (so after school it's Thursday's lessons and reminders, ready for packing the bag the night before).
    func shownDay(at date: Date) -> Date {
        guard current(at: date) == nil, let next = upcoming(after: date, limit: 1).first,
              !Calendar.current.isDate(next.start, inSameDayAs: date) else { return date }
        return next.start
    }
    /// The reminder notes for the shown day, and how to name that day when it isn't today ("Tomorrow", "Monday").
    func reminderNotes(at date: Date) -> (day: String?, notes: [ReminderNote])? {
        let day = shownDay(at: date)
        guard let notes = dayReminders?[Self.dayKey(day)], !notes.isEmpty else { return nil }
        let calendar = Calendar.current
        if calendar.isDate(day, inSameDayAs: date) { return (nil, notes) }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: date), calendar.isDate(day, inSameDayAs: tomorrow) { return ("Tomorrow", notes) }
        return (day.formatted(.dateTime.weekday(.wide)), notes)
    }
    /// True once the snapshot no longer covers `date` (the app hasn't been opened for a while).
    func isStale(at date: Date) -> Bool { (lessons.last?.end ?? generatedAt) < date && cycles[Self.dayKey(date)] == nil }
}

/// The colours a reminder can have, by the name saved with its rule. Each is shown as a soft tint behind primary
/// text, which reads in light and dark appearances alike.
enum ReminderPalette {
    static let names = ["yellow", "orange", "red", "pink", "purple", "blue", "teal", "green", "grey"]
    static func color(_ name: String?) -> Color {
        switch name {
        case "orange": return .orange
        case "red": return .red
        case "pink": return .pink
        case "purple": return .purple
        case "blue": return .blue
        case "teal": return .teal
        case "green": return .green
        case "grey": return .gray
        default: return .yellow
        }
    }
    static func label(_ name: String?) -> String { (name ?? "yellow").capitalized }
}

/// The reader's reminders for a day, each on its own chip in the colour chosen for it, at the top of every screen and
/// widget. Chips run left to right and wrap onto another line only when the next doesn't fit. A day other than today
/// is named in the first chip ("Tomorrow: PE uniform").
struct ReminderBar: View {
    let day: String?
    let notes: [ReminderNote]
    var compact = false
    /// How many lines a compact chip's note may wrap to before it's cut short.
    var compactLines = 1
    var body: some View {
        ChipFlow(spacing: compact ? 4 : 6) {
            ForEach(Array(notes.enumerated()), id: \.offset) { index, note in chip(note, first: index == 0) }
        }
        .font(compact ? .footnote.weight(.semibold) : .subheadline.weight(.semibold))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reminder\(notes.count == 1 ? "" : "s")\(day.map { " for \($0)" } ?? " for today"): \(notes.map(\.text).joined(separator: ", "))")
    }
    private func chip(_ note: ReminderNote, first: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: compact ? 4 : 6) {
            if first { Image(systemName: "backpack.fill").foregroundStyle(.primary.opacity(0.7)) }
            (Text(first ? day.map { "\($0): " } ?? "" : "").foregroundStyle(.secondary) + Text(note.text))
                .lineLimit(compact ? compactLines : 3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, compact ? 7 : 10).padding(.vertical, compact ? 3 : 6)
        .background(RoundedRectangle(cornerRadius: compact ? 7 : 10, style: .continuous).fill(ReminderPalette.color(note.color).opacity(0.3)))
    }
}

/// Lays its views out left to right, starting a new line when the next one won't fit; a view wider than the space
/// is offered the full width (so its text wraps).
struct ChipFlow: Layout {
    var spacing: CGFloat = 4
    private func rows(_ subviews: Subviews, width: CGFloat?) -> [(views: [(index: Int, size: CGSize)], height: CGFloat)] {
        let limit = width ?? .infinity
        var rows: [(views: [(index: Int, size: CGSize)], height: CGFloat)] = [([], 0)]
        var x: CGFloat = 0
        for (index, view) in subviews.enumerated() {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > limit { rows.append(([], 0)); x = 0 }
            rows[rows.count - 1].views.append((index, size))
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
            x += size.width + spacing
        }
        return rows
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(subviews, width: proposal.width)
        let width = rows.map { row in row.views.map(\.size.width).reduce(0, +) + spacing * CGFloat(max(0, row.views.count - 1)) }.max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            var x = bounds.minX
            for item in row.views {
                subviews[item.index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(item.size.width, bounds.width), height: item.size.height))
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }
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
