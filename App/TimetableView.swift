import SwiftUI
import SEQTAKit

struct TimetableView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedDate = Date()
    @State private var schedule: TimetableSchedule?
    @State private var loading = false
    @State private var error: String?
    @AppStorage("timetableWeekView") private var weekView = true
    @State private var fitWeek = true
    @State private var choosingWeek = false
    /// Set once the opening day has been decided, so later reloads never move the reader's chosen date.
    @State private var choseStartDay = false
    @State private var listScrollView: UIScrollView?
    @State private var pendingOffset: CGPoint?
    @State private var loadedKey: String?
    private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.firstWeekday = 2; return value }
    private var weekStart: Date { calendar.dateInterval(of: .weekOfYear, for: selectedDate)!.start }
    private var days: [Date] { (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) } }
    private var lessons: [TimetableEntry] { schedule?.entries.filter { calendar.isDate($0.start, inSameDayAs: selectedDate) } ?? [] }
    private var requestKey: String { "\(model.childID ?? "")-\(dateKey(weekStart))" }
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Picker("Timetable view", selection: $weekView) {
                            Text("Week").tag(true); Text("Day").tag(false)
                        }.pickerStyle(.segmented)
                        if weekView {
                            Button { fitWeek.toggle() } label: {
                                Image(systemName: fitWeek ? "arrow.left.and.right" : "arrow.right.and.line.vertical.and.arrow.left")
                                    .frame(width: 44, height: 32)
                            }.buttonStyle(.borderless)
                                .accessibilityLabel(fitWeek ? "Show more detail" : "Fit week to screen")
                        }
                    }
                    if !weekView { HStack(spacing: 5) {
                        ForEach(days, id: \.self) { day in
                            let selected = calendar.isDate(day, inSameDayAs: selectedDate)
                            Button { selectedDate = day } label: {
                                VStack(spacing: 5) {
                                    Text(day.formatted(.dateTime.weekday(.abbreviated))).font(.caption2)
                                    Text(day.formatted(.dateTime.day())).font(.subheadline.bold())
                                    Circle().fill(calendar.isDateInToday(day) ? Color.teal : .clear).frame(width: 4, height: 4)
                                }.frame(maxWidth: .infinity, minHeight: 44).padding(.vertical, 3)
                                    .background(selected ? Color.teal.opacity(0.15) : Color.clear)
                                    .foregroundStyle(selected ? .teal : .primary)
                                    // Plain buttons only respond where something is drawn; make the whole cell tappable.
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                                .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    } }
                }.padding(.vertical, 5)
            }
            if let error { ErrorRow(message: error, retry: load) }
            if model.child == nil { ChildPlaceholder() }
            else if weekView, let schedule {
                TimetableWeekView(schedule: schedule, days: Array(days.prefix(5)), fitWeek: $fitWeek) { day in selectedDate = day; weekView = false }
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)).listRowSeparator(.hidden)
            }
            else if lessons.isEmpty && !loading && error == nil {
                ContentUnavailableView("No lessons scheduled", systemImage: "sun.max", description: Text("Choose another day to see the timetable."))
            } else {
                Section {
                    ForEach(lessons) { lesson in
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            TimetableLessonCard(lesson: lesson, now: context.date)
                        }.background(TimetableScrollCapture { view in
                            if listScrollView !== view { listScrollView = view }
                        }).listRowSeparator(.hidden).listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    }
                }
            }
        }.listStyle(.plain).navigationTitle("Timetable")
            .safeAreaInset(edge: .top, spacing: 0) { dateNavigation }
            .onChange(of: selectedDate) { _, _ in restorePositionIfReady() }
            .onChange(of: model.timetableOpenRequest) { _, _ in
                // Opened from the widget: back to today, or tomorrow once today's lessons are over, as on first open.
                selectedDate = Date()
                // If this week is already loaded, decide now; otherwise the reload for this week decides.
                if loadedKey == requestKey, let schedule { if let next = dayAfterSchoolFinished(in: schedule) { selectedDate = next } }
                else { choseStartDay = false }
            }
            .overlay { if loading { ProgressView("Reading timetable…").padding(20).background(.regularMaterial) } }
            .task(id: requestKey) { await load() }
            .refreshable { await model.client?.clearCache(); await load() }
    }
    private var dateNavigation: some View {
        HStack {
            Button { step(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .buttonStyle(.borderless).accessibilityLabel(weekView ? "Previous week" : "Previous day")
            if weekView {
                Button { choosingWeek = true } label: {
                    Text(weekRange).font(.body).monospacedDigit().foregroundStyle(.primary)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }.buttonStyle(.plain).layoutPriority(1)
                    .accessibilityLabel("Week of " + weekStart.formatted(date: .long, time: .omitted))
                    .accessibilityHint("Choose a different week")
            } else {
                DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.compact).layoutPriority(1)
            }
            // Beside the date it describes, rather than out by the next arrow.
            if let cycle = cycleBadge {
                CycleBadge(text: cycle)
                    .accessibilityLabel("School cycle: " + cycle)
            }
            Spacer(minLength: 8)
            Button { step(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .buttonStyle(.borderless).accessibilityLabel(weekView ? "Next week" : "Next day")
        }.padding(.horizontal, 12).padding(.vertical, 4).background(.bar)
            .overlay(alignment: .bottom) { ReadingRule() }
            .sheet(isPresented: $choosingWeek) {
                NavigationStack {
                    DatePicker("Week", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical).padding(.horizontal)
                        .onChange(of: selectedDate) { _, _ in choosingWeek = false }
                        .navigationTitle("Choose a week").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { choosingWeek = false } } }
                }.presentationDetents([.medium, .large])
            }
    }
    /// Once today's lessons are over, tomorrow's timetable is the useful one, provided tomorrow is a school day.
    /// School ends at today's last lesson (3:30pm on days without lessons). A tomorrow in this week counts as a school
    /// day if it has lessons; one in the next week (Sunday evening) is judged by weekday rather than fetching early.
    private func dayAfterSchoolFinished(in schedule: TimetableSchedule) -> Date? {
        let now = Date()
        guard calendar.isDateInToday(selectedDate) else { return nil }
        let todaysEnd = schedule.entries.filter { calendar.isDate($0.start, inSameDayAs: now) }.map(\.end).max()
            ?? calendar.date(bySettingHour: 15, minute: 30, second: 0, of: now)!
        guard now >= todaysEnd, let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return nil }
        if calendar.isDate(tomorrow, equalTo: weekStart, toGranularity: .weekOfYear) {
            return schedule.entries.contains { calendar.isDate($0.start, inSameDayAs: tomorrow) } ? tomorrow : nil
        }
        return (2...6).contains(calendar.component(.weekday, from: tomorrow)) ? tomorrow : nil
    }
    /// "9–13 Nov", or "30 Nov – 4 Dec" when the school week crosses a month.
    private var weekRange: String {
        let end = days[min(4, days.count - 1)]
        let sameMonth = calendar.component(.month, from: weekStart) == calendar.component(.month, from: end)
        let first = sameMonth ? weekStart.formatted(.dateTime.day()) : weekStart.formatted(.dateTime.day().month(.abbreviated))
        return "\(first)\(sameMonth ? "–" : " – ")\(end.formatted(.dateTime.day().month(.abbreviated)))"
    }
    /// The selected day's cycle in day view; the fortnight week (e.g. "Week A") in week view.
    private var cycleBadge: String? {
        if weekView {
            for day in days.prefix(5) {
                if let cycle = schedule?.cycles[dateKey(day)], let week = CycleLabel.week(for: cycle, weekLetters: model.showsWeekLetters) { return week }
            }
            return nil
        }
        guard let cycle = schedule?.cycles[dateKey(selectedDate)] else { return nil }
        return CycleLabel.text(for: cycle, weekLetters: model.showsWeekLetters)
    }
    private func step(_ direction: Int) {
        pendingOffset = listScrollView?.contentOffset
        selectedDate = calendar.date(byAdding: .day, value: direction * (weekView ? 7 : 1), to: selectedDate) ?? selectedDate
        restorePositionIfReady()
    }
    private func restorePositionIfReady() {
        guard loadedKey == requestKey else { return }
        DispatchQueue.main.async {
            if let offset = pendingOffset, let view = listScrollView {
                pendingOffset = nil
                DispatchQueue.main.async {
                    view.layoutIfNeeded()
                    let maxY = max(-view.adjustedContentInset.top, view.contentSize.height - view.bounds.height + view.adjustedContentInset.bottom)
                    let y = min(maxY, max(-view.adjustedContentInset.top, offset.y))
                    view.setContentOffset(CGPoint(x: offset.x, y: y), animated: false)
                }
            }
        }
    }
    private func dateKey(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    private func load() async {
        guard let child = model.child else { return }
        let key = requestKey
        loading = true; error = nil; defer { if key == requestKey { loading = false } }
        do {
            let value: TimetableSchedule
            if model.isDemo { value = try Demo.timetable(on: selectedDate) }
            else if let client = model.client {
                let end = calendar.date(byAdding: .day, value: 6, to: weekStart)!
                value = try await client.timetable(for: child, from: weekStart, until: end)
            } else { return }
            try Task.checkCancellation(); guard key == requestKey else { return }; schedule = value; loadedKey = key
            model.recordTeachers(from: value, child: child); model.recordCycles(from: value)
            if !choseStartDay { choseStartDay = true; if let next = dayAfterSchoolFinished(in: value) { selectedDate = next } }
            restorePositionIfReady()
        } catch { if !Task.isCancelled && key == requestKey { self.error = error.localizedDescription } }
    }
}

private struct TimetableLessonCard: View {
    let lesson: TimetableEntry
    let now: Date
    private var current: Bool { now >= lesson.start && now < lesson.end }
    private var finished: Bool { now >= lesson.end }
    var body: some View {
        SubjectStyle(subject: lesson.subject, context: lesson.code) { identity in
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lesson.start.formatted(date: .omitted, time: .shortened)).font(.caption.weight(.semibold))
                    Text(lesson.end.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                }.monospacedDigit().frame(width: 65, alignment: .leading).padding(.top, 12)
                HStack(alignment: .top, spacing: 10) {
                    // Decorative: the subject name beside it says the same, and VoiceOver would read the symbol's name.
                    Image(systemName: identity.symbol).font(.title3).foregroundStyle(identity.color).accessibilityHidden(true)
                        .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(lesson.subject).font(.headline).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            if current { Text("NOW").font(.caption2.bold()).foregroundStyle(identity.color) }
                        }
                        if !lesson.teacher.isEmpty { Text(lesson.teacher).font(.caption).foregroundStyle(.secondary) }
                        HStack(spacing: 12) {
                            if !lesson.room.isEmpty { Label(lesson.room + (lesson.roomChanged ? " · changed" : ""), systemImage: "door.left.hand.open").foregroundStyle(lesson.roomChanged ? .orange : .secondary) }
                            if !lesson.period.isEmpty { Text(lesson.period) }
                        }.font(.caption2)
                        if current {
                            ProgressView(value: now.timeIntervalSince(lesson.start), total: lesson.end.timeIntervalSince(lesson.start)).tint(identity.color)
                                // The "min remaining" text says the same; as its own element the thin bar is an undersized target.
                                .accessibilityHidden(true)
                            Text("\(max(1, Int(lesson.end.timeIntervalSince(now) / 60))) min remaining").font(.caption2).foregroundStyle(identity.color)
                        }
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(current ? identity.color.opacity(0.10) : .clear)
                    .overlay(alignment: .leading) { Rectangle().fill(identity.color).frame(width: 3) }
                    .overlay(alignment: .bottom) { ReadingRule().padding(.leading, 12) }
            }.opacity(finished ? 0.8 : 1) // dimmer than 0.8 takes secondary text below 4.5:1
        }
    }
}

/// A school-cycle label whose fortnight letter is a glyph, so A and B differ at a glance by colour and shape:
/// "Day 2, Week" followed by an orange circled A, or a purple squared B. Other labels show as plain text.
struct CycleBadge: View {
    let text: String
    private var parts: (prefix: String, week: Character)? {
        guard let match = text.firstMatch(of: #/(?i)(week)\s*([AB])\b/#) else { return nil }
        let prefix = String(text[..<match.range.lowerBound]) + String(match.1)
        return (prefix, Character(match.2.uppercased()))
    }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let parts {
                Text(parts.prefix).foregroundStyle(.secondary)
                Image(systemName: parts.week == "A" ? "a.circle.fill" : "b.square.fill")
                    .font(.body).foregroundStyle(parts.week == "A" ? Color.orange : Color.purple)
            } else {
                Text(text).foregroundStyle(.secondary)
            }
        }.font(.subheadline).monospacedDigit()
            .lineLimit(1).fixedSize()
    }
}
