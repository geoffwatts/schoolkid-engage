import WidgetKit
import SwiftUI
import LMSKit

struct SchoolDayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SchoolDayView: View {
    let entry: SchoolDayEntry
    var familyOverride: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var environmentFamily
    private var family: WidgetFamily { familyOverride ?? environmentFamily }
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
    private func shownDay(_ snapshot: WidgetSnapshot) -> Date { snapshot.shownDay(at: entry.date) }
    /// The reader's reminders for the shown day, one chip per line. No day is named: on a widget the reminders are
    /// always for the day of the lesson beside them, which already says so.
    /// Reminders matter more than anything else in their column, so each chip wraps to show its whole note and the
    /// layouts drop the child's name, date and cycle day to make room. `lines: 1` cuts them short, as a last resort.
    @ViewBuilder private func reminders(_ snapshot: WidgetSnapshot, lines: Int = 3) -> some View {
        if let reminder = snapshot.reminderNotes(at: entry.date) { ReminderBar(day: nil, notes: reminder.notes, compact: true, compactLines: lines) }
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
        // Reminders outrank everything but the lesson itself: when space runs short the room goes first, then the
        // child's name, then the cycle day. Only then are reminders cut to one line.
        ViewThatFits(in: .vertical) {
            smallBody(snapshot, showsRoom: true, showsName: true)
            smallBody(snapshot, showsRoom: false, showsName: true)
            smallBody(snapshot, showsRoom: false, showsName: false)
            smallBody(snapshot, showsRoom: false, showsName: false, showsCycle: false)
            smallBody(snapshot, showsRoom: false, showsName: false, showsCycle: false, reminderLines: 1)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func smallBody(_ snapshot: WidgetSnapshot, showsRoom: Bool, showsName: Bool, showsCycle: Bool = true,
                           reminderLines: Int = 2) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if showsCycle { cycle(snapshot, on: shownDay(snapshot), font: .headline) }
                Spacer(minLength: 0)
                lunchBalance(snapshot, font: .system(size: 10))
            }
            reminders(snapshot, lines: reminderLines)
            Spacer(minLength: 0)
            if let lesson = focus(snapshot) {
                // The child's name heads the lesson; "until" or a start time says whether it's on now.
                if showsName { Text(snapshot.childName).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1) }
                Text(lesson.subject).font(.headline).lineLimit(2).minimumScaleFactor(0.8)
                Text(lessonTime(lesson)).font(.subheadline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                if showsRoom && !lesson.room.isEmpty { Text(lesson.room).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            } else {
                Text("No lessons coming up").font(.subheadline).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
    /// "until 11:50" for a lesson on now, "11:55" later today, "Tomorrow 8:40" or "Monday 8:40" on another day.
    private func lessonTime(_ lesson: WidgetSnapshot.Lesson) -> String {
        if lesson.start <= entry.date { return "until \(time(lesson.end))" }
        if Calendar.current.isDate(lesson.start, inSameDayAs: entry.date) { return time(lesson.start) }
        return "\(caption(for: lesson)) \(time(lesson.start))"
    }

    private func medium(_ snapshot: WidgetSnapshot) -> some View {
        let day = shownDay(snapshot)
        return HStack(alignment: .top, spacing: 12) {
            // Reminders head the day column, leaving the lessons their full height, and may fill it: the child's name
            // goes first, then the date, then the cycle day. Only then are the reminders cut short.
            ViewThatFits(in: .vertical) {
                dayColumn(snapshot, day: day, showsName: true, showsDate: true)
                dayColumn(snapshot, day: day, showsName: false, showsDate: true)
                dayColumn(snapshot, day: day, showsName: false, showsDate: false)
                dayColumn(snapshot, day: day, showsName: false, showsDate: false, showsCycle: false)
                dayColumn(snapshot, day: day, showsName: false, showsDate: false, showsCycle: false, reminderLines: 1)
            }
            // A little wider on reminder days, so a chip like "PE uniform" fits on one line.
            .frame(width: snapshot.reminderNotes(at: entry.date) == nil ? 100 : 118, alignment: .leading)
            // As many lessons as fit at the reader's text size: three normally, fewer as the text grows.
            ViewThatFits(in: .vertical) {
                lessonList(snapshot, day: day, rows: 3)
                lessonList(snapshot, day: day, rows: 2)
                lessonList(snapshot, day: day, rows: 1)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func dayColumn(_ snapshot: WidgetSnapshot, day: Date, showsName: Bool, showsDate: Bool, showsCycle: Bool = true,
                           reminderLines: Int = 4) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            reminders(snapshot, lines: reminderLines)
            if showsCycle { cycle(snapshot, on: day, font: .title3.weight(.semibold)) }
            if showsDate {
                Text(day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).minimumScaleFactor(0.8)
            }
            lunchBalance(snapshot, font: .caption2)
            if showsName {
                Spacer(minLength: 0)
                Text(snapshot.childName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    @ViewBuilder private func lunchBalance(_ snapshot: WidgetSnapshot, font: Font) -> some View {
        if let balance = snapshot.lunchBalance {
            let text = balance.formatted(.currency(code: "AUD").locale(Locale(identifier: "en_AU")))
            Text(text)
                .font(font).monospacedDigit().foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityLabel("Lunch balance \(text)")
        }
    }

    private func lessonList(_ snapshot: WidgetSnapshot, day: Date, rows: Int) -> some View {
        let now = snapshot.current(at: entry.date)
        let next = snapshot.upcoming(after: entry.date, limit: now == nil ? rows : rows - 1)
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(([now].compactMap { $0 } + next).enumerated()), id: \.offset) { _, lesson in
                let isNow = lesson.start <= entry.date
                // The left column already names the day; only say it again for a lesson on a different one.
                let otherDay = Calendar.current.isDate(lesson.start, inSameDayAs: day) ? nil : caption(for: lesson)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    // Times never wrap: they take the width they need and the subject gives way.
                    Text(isNow ? "Now" : time(lesson.start)).font(.caption.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(isNow ? Color.teal : .primary)
                        .lineLimit(1).fixedSize().frame(minWidth: 46, alignment: .leading)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(lesson.subject).font(.footnote.weight(.semibold)).lineLimit(1)
                        Text([otherDay, lesson.room.isEmpty ? nil : lesson.room].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                // The lesson in progress sits on a soft teal band; every row has the same inset so columns align.
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background { if isNow { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.teal.opacity(0.2)) } }
            }
            if now == nil && next.isEmpty { Text("No lessons coming up").font(.subheadline).foregroundStyle(.secondary) }
        }
    }

    private func rectangular(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            // Three lines only: a reminder takes the cycle day's place, since it's the thing to act on.
            if let reminder = snapshot.reminderNotes(at: entry.date) {
                Label(reminder.notes.map(\.text).joined(separator: " · "), systemImage: "backpack.fill")
                    .font(.headline).lineLimit(1)
            } else {
                cycle(snapshot, on: shownDay(snapshot), font: .headline)
            }
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
