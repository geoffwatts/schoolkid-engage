import SwiftUI
import SEQTAKit

struct TimetableWeekView: View {
    let schedule: TimetableSchedule
    let days: [Date]
    @Binding var fitWeek: Bool
    /// Each day's reminders ("yyyy-MM-dd" → notes), shown under that day's heading.
    var reminders: [String: [ReminderNote]] = [:]
    var openReminder: (ReminderNote) -> Void = { _ in }
    var selectDay: (Date) -> Void
    /// The reminders row's height, so the time axis beside it stays level with the lessons.
    @State private var reminderRowHeight: CGFloat = 0
    @State private var selectedLesson: TimetableEntry?
    /// Points per minute; grows with Dynamic Type so larger text still fits inside each lesson block.
    @ScaledMetric(relativeTo: .caption2) private var fitScale: CGFloat = 0.95
    @ScaledMetric(relativeTo: .caption) private var detailScale: CGFloat = 1.3
    @ScaledMetric(relativeTo: .caption) private var dateHeaderHeight: CGFloat = 36
    @ScaledMetric(relativeTo: .caption2) private var cycleLineHeight: CGFloat = 15
    /// Each day's cycle day number ("Day 4" → 4), when SEQTA gives one.
    private func cycleDay(_ day: Date) -> Int? { schedule.cycles[WidgetSnapshot.dayKey(day)].flatMap(CycleLabel.day(in:)) }
    /// Room for "Day 4" under each date, in weeks that have cycle days.
    private var headerHeight: CGFloat { dateHeaderHeight + (days.contains { cycleDay($0) != nil } ? cycleLineHeight : 0) }
    @ScaledMetric(relativeTo: .caption2) private var axisWidth: CGFloat = 34
    private var calendar: Calendar { Calendar(identifier: .gregorian) }
    private func minute(_ date: Date) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
    private var startMinute: Int { ((schedule.entries.map { minute($0.start) }.min() ?? 480) / 60) * 60 }
    private var endMinute: Int { max(startMinute + 60, Int(ceil(Double(schedule.entries.map { minute($0.end) }.max() ?? 900) / 60)) * 60) }
    private var scale: CGFloat { fitWeek ? fitScale : detailScale }
    private var timelineHeight: CGFloat { CGFloat(endMinute - startMinute) * scale }
    private var timeAxis: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(stride(from: startMinute, through: endMinute, by: 60)), id: \.self) { time in
                let hour = time / 60
                Text("\((hour + 11) % 12 + 1)\(hour < 12 ? "a" : "p")")
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    .offset(y: max(0, CGFloat(time - startMinute) * scale - 6))
            }
        }.frame(width: axisWidth, height: timelineHeight, alignment: .topLeading)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geometry in
                let columnWidth = fitWeek ? max(55, (geometry.size.width - axisWidth) / CGFloat(max(1, days.count))) : 145
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: headerHeight + reminderRowHeight)
                        timeAxis
                    }.frame(width: axisWidth).background(Color(.systemBackground)).zIndex(1)
                    ScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(days, id: \.self) { day in
                                Button { selectDay(day) } label: {
                                    VStack(spacing: 3) {
                                        Text(day.formatted(.dateTime.weekday(.abbreviated))).font(.caption.weight(.semibold))
                                        Text(day.formatted(.dateTime.day())).font(.caption2).monospacedDigit()
                                        if let cycle = cycleDay(day) { Text("Day \(cycle)").font(.caption2).monospacedDigit().foregroundStyle(.secondary).lineLimit(1) }
                                    }.frame(width: columnWidth, height: headerHeight)
                                        .foregroundStyle(calendar.isDateInToday(day) ? .teal : .primary)
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                    .accessibilityLabel("Show " + day.formatted(date: .complete, time: .omitted) + (cycleDay(day).map { ", Day \($0)" } ?? ""))
                                    .accessibilityHint("Opens the day agenda")
                            }
                        }
                        if days.contains(where: { !(reminders[WidgetSnapshot.dayKey($0)] ?? []).isEmpty }) {
                            reminderRow(columnWidth: columnWidth)
                        }
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(days, id: \.self) { day in
                                ZStack(alignment: .top) {
                                    ForEach(Array(stride(from: startMinute, through: endMinute, by: 60)), id: \.self) { time in
                                        Rectangle().fill(.secondary.opacity(0.16)).frame(height: 0.5)
                                            .offset(y: CGFloat(time - startMinute) * scale)
                                    }
                                    let dayLessons = schedule.entries.filter { calendar.isDate($0.start, inSameDayAs: day) }
                                    let lanes = TimetableLayout.lanes(for: dayLessons)
                                    ForEach(dayLessons) { lesson in
                                        let height = max(22, CGFloat(lesson.end.timeIntervalSince(lesson.start) / 60) * scale - 2)
                                        // Overlapping lessons split the column so each stays visible and tappable.
                                        let lane = lanes[lesson.id] ?? TimetableLane(index: 0, count: 1)
                                        let laneWidth = (columnWidth - 4) / CGFloat(lane.count)
                                        SubjectStyle(subject: lesson.subject, context: lesson.code) { identity in
                                            Button { selectedLesson = lesson } label: {
                                                VStack(spacing: 2) {
                                                    if height >= 40, lane.count == 1 || !fitWeek { Image(systemName: identity.symbol).font(.caption2).foregroundStyle(identity.color).accessibilityHidden(true) }
                                                    Text(lesson.subject).font(fitWeek ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                                                        .lineLimit(fitWeek ? 2 : 3).minimumScaleFactor(0.8).multilineTextAlignment(.center)
                                                    if height >= 65, !lesson.room.isEmpty { Text(lesson.room).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                                                }.padding(3).frame(width: laneWidth - (lane.count > 1 ? 1 : 0), height: height)
                                                    .foregroundStyle(.primary)
                                                    .background(identity.color.opacity(0.15))
                                                    .overlay(alignment: .leading) { Rectangle().fill(identity.color).frame(width: 2) }
                                            }.buttonStyle(.plain)
                                                .accessibilityLabel("\(lesson.subject), \(lesson.start.formatted(date: .omitted, time: .shortened))")
                                                .accessibilityHint("Shows room and teacher")
                                        }.position(x: 2 + laneWidth * (CGFloat(lane.index) + 0.5), y: CGFloat(minute(lesson.start) - startMinute) * scale + height / 2)
                                    }
                                    if calendar.isDateInToday(day) { nowLine }
                                }.frame(width: columnWidth, height: timelineHeight)
                                    .background(calendar.isDateInToday(day) ? Color.teal.opacity(0.025) : .clear)
                            }
                        }
                    }.frame(width: columnWidth * CGFloat(days.count))
                    }
                }
            }.frame(height: timelineHeight + headerHeight + reminderRowHeight + 6)
                .onPreferenceChange(ReminderRowHeight.self) { reminderRowHeight = $0 }
        }.sheet(item: $selectedLesson) { lesson in
            NavigationStack {
                List {
                    SubjectPill(subject: lesson.subject, context: lesson.code)
                    LabeledContent("Day", value: lesson.start.formatted(date: .complete, time: .omitted))
                    LabeledContent("Time", value: lesson.start.formatted(date: .omitted, time: .shortened) + " – " + lesson.end.formatted(date: .omitted, time: .shortened))
                    if !lesson.room.isEmpty { LabeledContent("Room", value: lesson.room) }
                    if !lesson.teacher.isEmpty { LabeledContent("Teacher", value: lesson.teacher) }
                    if !lesson.period.isEmpty { LabeledContent("Period", value: lesson.period) }
                }.listStyle(.plain).navigationTitle(lesson.subject).navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { selectedLesson = nil } } }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
}

private struct ReminderRowHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private extension TimetableWeekView {
    /// Each day's reminders under its heading, small enough for a narrow column; tapping one opens its settings.
    func reminderRow(columnWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(days, id: \.self) { day in
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(reminders[WidgetSnapshot.dayKey(day)] ?? [], id: \.self) { note in
                        Button { openReminder(note) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Image(systemName: note.symbol ?? "backpack.fill").foregroundStyle(.primary.opacity(0.7))
                                Text(note.text).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                            }
                            .font(.caption2.weight(.semibold)).foregroundStyle(.primary)
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(ReminderPalette.color(note.color).opacity(0.3)))
                        }.buttonStyle(.plain)
                            .accessibilityLabel("Reminder for \(day.formatted(.dateTime.weekday(.wide))): \(note.text)")
                            .accessibilityHint("Opens this reminder’s settings")
                    }
                }.padding(.horizontal, 2).frame(width: columnWidth, alignment: .topLeading)
            }
        }
        .padding(.bottom, 4)
        .background(GeometryReader { Color.clear.preference(key: ReminderRowHeight.self, value: $0.size.height) })
    }

    /// A marker for the current time in today's column, matching the day view's live progress.
    var nowLine: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = minute(context.date)
            if now >= startMinute && now <= endMinute {
                HStack(spacing: 0) {
                    Circle().fill(Color.teal).frame(width: 6, height: 6)
                    Rectangle().fill(Color.teal).frame(height: 1.5)
                }.offset(x: -3, y: CGFloat(now - startMinute) * scale - 3)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }.frame(maxHeight: .infinity, alignment: .top)
    }
}
