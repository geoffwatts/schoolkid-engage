import WidgetKit
import SwiftUI
import SEQTAKit

@main
struct SchoolkidWidgets: WidgetBundle {
    var body: some Widget { SchoolDayWidget() }
}

/// Today's cycle day (with Week A/B at fortnightly schools) and the lesson now or next.
struct SchoolDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SchoolDay", provider: SchoolDayProvider()) { entry in
            SchoolDayView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
                // It's a timetable widget, so a tap opens the timetable on the day it describes.
                .widgetURL(URL(string: "schoolkidengage://timetable"))
        }
        .configurationDisplayName("School day")
        .description("Today's cycle day and the next lesson.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryRectangular, .accessoryCircular])
    }
}

struct SchoolDayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SchoolDayProvider: TimelineProvider {
    func placeholder(in context: Context) -> SchoolDayEntry { SchoolDayEntry(date: .now, snapshot: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (SchoolDayEntry) -> Void) {
        completion(SchoolDayEntry(date: .now, snapshot: WidgetSnapshot.load() ?? (context.isPreview ? .sample : nil)))
    }
    /// One entry now, then one at every lesson start and end over the next day and a half, plus midnight, so "now" and
    /// "next" roll over on time without the app running.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SchoolDayEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load(), now = Date(), horizon = now.addingTimeInterval(36 * 3600)
        var dates: Set<Date> = [now, Calendar.current.startOfDay(for: now.addingTimeInterval(86_400))]
        for lesson in snapshot?.lessons ?? [] {
            for moment in [lesson.start, lesson.end] where moment > now && moment < horizon { dates.insert(moment) }
        }
        completion(Timeline(entries: dates.sorted().map { SchoolDayEntry(date: $0, snapshot: snapshot) }, policy: .after(horizon)))
    }
}

struct SchoolDayView: View {
    let entry: SchoolDayEntry
    @Environment(\.widgetFamily) private var family
    private var snapshot: WidgetSnapshot? { entry.snapshot.flatMap { $0.isStale(at: entry.date) ? nil : $0 } }
    var body: some View {
        if let snapshot {
            Group {
                switch family {
                case .accessoryInline: inline(snapshot)
                case .accessoryCircular: circular(snapshot)
                case .accessoryRectangular: rectangular(snapshot)
                case .systemMedium: medium(snapshot)
                default: small(snapshot)
                }
            }
            // A widget's space is fixed, so text grows up to the largest standard size, not the accessibility sizes.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        } else {
            // Nothing to show until the app has loaded a timetable (or it hasn't been opened in a couple of weeks).
            Text(family == .accessoryInline ? "Open Schoolkid Engage" : "Open Schoolkid Engage to load the timetable.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: Pieces

    /// "Day 3" plus the week glyph, or nothing on days without a cycle (weekends, holidays).
    @ViewBuilder private func cycle(_ snapshot: WidgetSnapshot, on day: Date, font: Font) -> some View {
        if let parts = snapshot.cycleParts(on: day) {
            HStack(spacing: 4) {
                Text("Day \(parts.day)").font(font).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                if let week = parts.week { WeekLetterGlyph(letter: week).font(font) }
            }
        }
    }
    /// The day the widget is describing: today while there's a lesson on or still to come today, otherwise the day of
    /// the next lesson (so after school it reads "Day 4, Thursday" alongside Thursday's lessons, not today's).
    private func shownDay(_ snapshot: WidgetSnapshot) -> Date {
        guard snapshot.current(at: entry.date) == nil, let next = snapshot.upcoming(after: entry.date, limit: 1).first,
              !Calendar.current.isDate(next.start, inSameDayAs: entry.date) else { return entry.date }
        return next.start
    }
    private func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
    /// "Now" for a lesson in progress, "Next" later today, otherwise the day ("Tomorrow", "Monday").
    private func caption(for lesson: WidgetSnapshot.Lesson) -> String {
        if lesson.start <= entry.date { return "Now" }
        if Calendar.current.isDate(lesson.start, inSameDayAs: entry.date) { return "Next" }
        if Calendar.current.isDateInTomorrow(lesson.start) && Calendar.current.isDateInToday(entry.date) { return "Tomorrow" }
        return lesson.start.formatted(.dateTime.weekday(.wide))
    }
    private func focus(_ snapshot: WidgetSnapshot) -> WidgetSnapshot.Lesson? {
        snapshot.current(at: entry.date) ?? snapshot.upcoming(after: entry.date, limit: 1).first
    }

    // MARK: Families

    private func small(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            cycle(snapshot, on: shownDay(snapshot), font: .headline)
            Spacer(minLength: 0)
            if let lesson = focus(snapshot) {
                Text(caption(for: lesson).uppercased()).font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
                Text(lesson.subject).font(.headline).lineLimit(2).minimumScaleFactor(0.8)
                Text(lesson.start <= entry.date ? "until \(time(lesson.end))" : time(lesson.start)).font(.subheadline).monospacedDigit()
                if !lesson.room.isEmpty { Text(lesson.room).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            } else {
                Text("No lessons coming up").font(.subheadline).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func medium(_ snapshot: WidgetSnapshot) -> some View {
        let day = shownDay(snapshot)
        return HStack(alignment: .top, spacing: 12) {
            // The child's name is the first thing to go when the text is too big for it.
            ViewThatFits(in: .vertical) {
                dayColumn(snapshot, day: day, showsName: true)
                dayColumn(snapshot, day: day, showsName: false)
            }.frame(width: 100, alignment: .leading)
            // As many lessons as fit at the reader's text size: three normally, fewer as the text grows.
            ViewThatFits(in: .vertical) {
                lessonList(snapshot, day: day, rows: 3)
                lessonList(snapshot, day: day, rows: 2)
                lessonList(snapshot, day: day, rows: 1)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func dayColumn(_ snapshot: WidgetSnapshot, day: Date, showsName: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            cycle(snapshot, on: day, font: .title3.weight(.semibold))
            Text(day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))).font(.caption).foregroundStyle(.secondary)
                .lineLimit(2).minimumScaleFactor(0.8)
            if showsName {
                Spacer(minLength: 0)
                Text(snapshot.childName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func lessonList(_ snapshot: WidgetSnapshot, day: Date, rows: Int) -> some View {
        let now = snapshot.current(at: entry.date)
        let next = snapshot.upcoming(after: entry.date, limit: now == nil ? rows : rows - 1)
        return VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(([now].compactMap { $0 } + next).enumerated()), id: \.offset) { _, lesson in
                let isNow = lesson.start <= entry.date
                // The left column already names the day; only say it again for a lesson on a different one.
                let otherDay = Calendar.current.isDate(lesson.start, inSameDayAs: day) ? nil : caption(for: lesson)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    // Times never wrap: they take the width they need and the subject gives way.
                    Text(isNow ? "Now" : time(lesson.start)).font(.caption.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(isNow ? Color.teal : .primary)
                        .lineLimit(1).fixedSize().frame(minWidth: 46, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(lesson.subject).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text([otherDay, lesson.room.isEmpty ? nil : lesson.room].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                // The lesson in progress sits on a soft teal band; every row has the same inset so columns align.
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background { if isNow { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.teal.opacity(0.2)) } }
            }
            if now == nil && next.isEmpty { Text("No lessons coming up").font(.subheadline).foregroundStyle(.secondary) }
        }
    }

    private func rectangular(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            cycle(snapshot, on: shownDay(snapshot), font: .headline)
            if let lesson = focus(snapshot) {
                Text("\(caption(for: lesson)) \(lesson.subject)").font(.subheadline).lineLimit(1)
                Text([lesson.start <= entry.date ? "until \(time(lesson.end))" : time(lesson.start), lesson.room].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inline(_ snapshot: WidgetSnapshot) -> some View {
        let day = snapshot.cycleText(on: entry.date)
        let lesson = focus(snapshot).map { "\($0.subject) \($0.start <= entry.date ? "now" : time($0.start))" }
        return Text([day, lesson].compactMap { $0 }.joined(separator: " · "))
    }

    private func circular(_ snapshot: WidgetSnapshot) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            if let parts = snapshot.cycleParts(on: entry.date) {
                VStack(spacing: 0) {
                    Text("Day").font(.system(size: 10, weight: .semibold))
                    Text("\(parts.day)").font(.title2.weight(.bold)).monospacedDigit()
                    if let week = parts.week { WeekLetterGlyph(letter: week).font(.caption2) }
                }
            } else {
                Image(systemName: "calendar").font(.title3)
            }
        }
    }
}

extension WidgetSnapshot {
    /// Shown in the widget gallery before the app has written real data.
    static var sample: WidgetSnapshot {
        let start = Calendar.current.date(bySettingHour: 9, minute: 35, second: 0, of: .now) ?? .now
        return WidgetSnapshot(childName: "Your child", generatedAt: .now, weekLetters: true,
                              cycles: [dayKey(.now): ["Day 3"]],
                              lessons: [.init(subject: "Mathematics", start: start, end: start.addingTimeInterval(50 * 60), room: "M1")])
    }
}
