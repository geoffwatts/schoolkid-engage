import SwiftUI
import SEQTAKit

/// The kinds of lesson a reminder can follow, worked out by the app's subject classifier, so "Sport, PE & dance"
/// catches "Physical Education", "HPE", "Year 7 Sport" and "Dance" without naming each one.
struct LessonKind: Identifiable, Hashable {
    /// "family" for every specialism in a family, or "family/specialism".
    let key: String
    let label: String
    let symbol: String
    var id: String { key }

    static let sport = LessonKind(key: "health", label: "Sport, PE & dance", symbol: "figure.run")
    static let all: [LessonKind] = [
        sport,
        LessonKind(key: "health/dance", label: "Dance", symbol: "figure.dance"),
        LessonKind(key: "arts/music", label: "Music", symbol: "music.note"),
        LessonKind(key: "arts/drama", label: "Drama", symbol: "theatermasks"),
        LessonKind(key: "arts/visual", label: "Visual art", symbol: "paintpalette"),
        LessonKind(key: "science", label: "Science", symbol: "flask"),
        LessonKind(key: "technology", label: "Technology", symbol: "desktopcomputer"),
        LessonKind(key: "mathematics", label: "Maths", symbol: "function"),
        LessonKind(key: "languages", label: "English & languages", symbol: "text.book.closed"),
        LessonKind(key: "humanities", label: "Humanities", symbol: "globe.asia.australia")
    ]
    static func named(_ key: String) -> LessonKind? { all.first { $0.key == key } }
    /// A lesson's icon, as shown beside it elsewhere in the app; nil for a subject with no icon of its own.
    static func symbol(for subject: String) -> String? {
        let identity = SubjectIdentity.fallback(subject: subject)
        return identity.family == .general ? nil : identity.symbol
    }
    /// A lesson's kind as "family/specialism", from the same on-device rules that pick each subject's icon and colour.
    static func key(for subject: String) -> String {
        let identity = SubjectIdentity.fallback(subject: subject)
        return "\(identity.family.rawValue)/\(identity.specialism)"
    }
}

/// Settings → Reminders: the selected child's rules, each switched on or off in place.
struct RemindersView: View {
    @EnvironmentObject private var model: AppModel
    @State private var editing: ReminderRule?
    @AppStorage(ReminderAlerts.enabledKey) private var alertOn = false
    @AppStorage(ReminderAlerts.timeKey) private var alertMinutes = ReminderAlerts.defaultMinutes
    @State private var alertDenied = false
    @Environment(\.openURL) private var openURL
    /// The alert time as a date today, for the time picker.
    private var alertTime: Binding<Date> {
        Binding {
            Calendar.current.date(byAdding: .minute, value: alertMinutes, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            alertMinutes = (parts.hour ?? 7) * 60 + (parts.minute ?? 0)
        }
    }
    var body: some View {
        List {
            Section {
                ForEach($model.reminderRules) { $rule in
                    Toggle(isOn: $rule.isEnabled) {
                        Button { editing = rule } label: {
                            HStack(spacing: 12) {
                                Circle().fill(ReminderPalette.color(rule.color).opacity(0.6)).frame(width: 14, height: 14).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rule.trimmedNote.isEmpty ? "No note yet" : rule.trimmedNote)
                                        .foregroundStyle(rule.trimmedNote.isEmpty ? .secondary : .primary)
                                    Text(ReminderSummary.trigger(rule)).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityHint("Edit this reminder")
                    }
                }
                .onDelete { model.reminderRules.remove(atOffsets: $0) }
                Button { editing = ReminderRule() } label: { Label("Add a reminder", systemImage: "plus.circle.fill") }
            } footer: {
                Text("Reminders show in a bar at the top of every screen and on the widget on days with the lessons you choose. After school, they show the next school day’s, so you can pack the night before. They’re kept on this device.")
            }
            Section {
                Toggle("Alert me in the morning", isOn: $alertOn)
                if alertOn { DatePicker("Time", selection: alertTime, displayedComponents: .hourAndMinute) }
                if alertOn && alertDenied {
                    Button {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    } label: {
                        Label("Notifications are off for this app. Turn them on in Settings", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            } header: { Text("Morning alert") } footer: {
                Text("On days with reminders, a notification at this time lists them. Alerts cover the next two weeks of the timetable as last loaded, so open the app now and then to keep them current.")
            }
        }
        .navigationTitle(model.child.map { "Reminders for \($0.name.split(separator: " ").first.map(String.init) ?? $0.name)" } ?? "Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if !model.reminderRules.isEmpty { EditButton() } }
        // Arrived from a reminder tapped in the header: open its editor.
        .onAppear {
            guard let id = model.reminderToOpen else { return }
            model.reminderToOpen = nil
            editing = model.reminderRules.first { $0.id == id }
        }
        .onChange(of: alertOn) { _, on in
            Task {
                if on { alertDenied = !(await ReminderAlerts.requestPermission()); model.scheduleReminderAlerts() }
                else { await ReminderAlerts.removeAll() }
            }
        }
        .onChange(of: alertMinutes) { _, _ in model.scheduleReminderAlerts() }
        .task { if alertOn { alertDenied = !(await ReminderAlerts.requestPermission()) } }
        .sheet(item: $editing) { rule in
            ReminderEditor(rule: rule) { saved in
                if let index = model.reminderRules.firstIndex(where: { $0.id == saved.id }) { model.reminderRules[index] = saved }
                else { model.reminderRules.append(saved) }
            }
        }
    }
}

enum ReminderSummary {
    /// "Days with Sport, PE & dance or Music", then ", not Assembly or Chapel" when some days are excepted.
    static func trigger(_ rule: ReminderRule) -> String {
        let names = rule.kinds.compactMap { LessonKind.named($0)?.label } + rule.subjects
        guard !names.isEmpty else { return "Choose the lessons it follows" }
        let except = rule.exceptKinds.compactMap { LessonKind.named($0)?.label } + rule.exceptSubjects
        return "Days with " + either(names) + (except.isEmpty ? "" : ", not " + either(except))
    }
    /// "A, B or C".
    private static func either(_ names: [String]) -> String {
        ListFormatter.localizedString(byJoining: names).replacingOccurrences(of: " and ", with: " or ")
    }
}

/// One reminder: its note, the lessons that set it off, and the days it will show over the coming fortnight.
struct ReminderEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var rule: ReminderRule
    @State private var lessons: [TimetableEntry]?
    @State private var loadError: String?
    let save: (ReminderRule) -> Void
    init(rule: ReminderRule, save: @escaping (ReminderRule) -> Void) {
        _rule = State(initialValue: rule); self.save = save
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. PE uniform, Take tuba", text: $rule.note)
                    Toggle("Show this reminder", isOn: $rule.isEnabled)
                } header: { Text("Note") }
                Section {
                    ColourSwatches(selection: $rule.color)
                    ReminderBar(day: nil, notes: [ReminderNote(text: rule.trimmedNote.isEmpty ? "Your note" : rule.trimmedNote, color: rule.color,
                                                                symbol: rule.kinds.first.flatMap { LessonKind.named($0)?.symbol }
                                                                    ?? rule.subjects.first.flatMap(LessonKind.symbol(for:)))])
                        .listRowBackground(Color(.systemBackground))
                } header: { Text("Colour") }
                Section {
                    ForEach(rule.kinds, id: \.self) { key in
                        Label(LessonKind.named(key)?.label ?? key, systemImage: LessonKind.named(key)?.symbol ?? "square.grid.2x2")
                    }.onDelete { rule.kinds.remove(atOffsets: $0) }
                    ForEach(rule.subjects, id: \.self) { name in
                        Label(name, systemImage: "text.magnifyingglass")
                    }.onDelete { rule.subjects.remove(atOffsets: $0) }
                    NavigationLink {
                        LessonPicker(subjects: $rule.subjects, kinds: $rule.kinds, lessons: lessons, loadError: loadError)
                    } label: { Label(rule.kinds.isEmpty && rule.subjects.isEmpty ? "Choose lessons" : "Change lessons", systemImage: "checklist") }
                } header: { Text("On days with any of") } footer: {
                    Text("A kind of lesson covers every subject the app sorts into it. A lesson name matches any lesson whose name includes it.")
                }
                Section {
                    ForEach(rule.exceptKinds, id: \.self) { key in
                        Label(LessonKind.named(key)?.label ?? key, systemImage: LessonKind.named(key)?.symbol ?? "square.grid.2x2")
                    }.onDelete { rule.exceptKinds.remove(atOffsets: $0) }
                    ForEach(rule.exceptSubjects, id: \.self) { name in
                        Label(name, systemImage: "text.magnifyingglass")
                    }.onDelete { rule.exceptSubjects.remove(atOffsets: $0) }
                    NavigationLink {
                        LessonPicker(subjects: $rule.exceptSubjects, kinds: $rule.exceptKinds, title: "Lessons to skip", lessons: lessons, loadError: loadError)
                    } label: {
                        Label(rule.exceptKinds.isEmpty && rule.exceptSubjects.isEmpty ? "Choose lessons to skip" : "Change lessons to skip", systemImage: "nosign")
                    }
                } header: { Text("But not on days with any of") } footer: {
                    Text("For example Assembly or Chapel, on days the uniform isn’t worn.")
                }
                Section {
                    if let lessons {
                        let days = upcomingDays(in: lessons)
                        if rule.kinds.isEmpty && rule.subjects.isEmpty { Text("Choose lessons to see which days this applies to.").foregroundStyle(.secondary) }
                        else if days.isEmpty { Text("No matching lessons in the next two weeks.").foregroundStyle(.secondary) }
                        ForEach(days, id: \.day) { day in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(day.day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                                Text(day.subjects.joined(separator: ", ")).font(.subheadline).foregroundStyle(.secondary)
                            }.accessibilityElement(children: .combine)
                        }
                    } else if let loadError {
                        Text(loadError).foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                } header: { Text("Coming up") }
            }
            .navigationTitle(rule.trimmedNote.isEmpty ? "Reminder" : rule.trimmedNote).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(rule); dismiss() }.disabled(rule.trimmedNote.isEmpty)
                }
            }
            .task {
                do { lessons = try await model.lessonsAroundToday() }
                catch { loadError = "The timetable couldn’t be read, so lessons can’t be listed. You can still type a lesson name." }
            }
        }
    }
    /// The school days from today on that this rule would mark, with the lessons that set it off.
    private func upcomingDays(in lessons: [TimetableEntry]) -> [(day: Date, subjects: [String])] {
        let today = Calendar.current.startOfDay(for: Date())
        let byDay = Dictionary(grouping: lessons.filter { $0.start >= today }) { Calendar.current.startOfDay(for: $0.start) }
        // A day with an excepted lesson is left out, as the reminder itself would be.
        let grouped = byDay.compactMapValues { day -> [TimetableEntry]? in
            if day.contains(where: { rule.excludes(subject: $0.subject, kind: LessonKind.key(for: $0.subject)) }) { return nil }
            let matching = day.filter { rule.matches(subject: $0.subject, kind: LessonKind.key(for: $0.subject)) }
            return matching.isEmpty ? nil : matching
        }
        return grouped.keys.sorted().map { day in (day, grouped[day]!.map(\.subject).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }) }
    }
}

/// A row of colour circles; the chosen one is ringed and ticked.
struct ColourSwatches: View {
    @Binding var selection: String?
    var body: some View {
        // One row, sharing the width evenly: the circles are a fixed size, so text size never makes them wrap.
        HStack(spacing: 0) {
            ForEach(ReminderPalette.names, id: \.self) { name in
                let chosen = (selection ?? "yellow") == name
                Button { selection = name == "yellow" ? nil : name } label: {
                    Circle().fill(ReminderPalette.color(name).opacity(0.55))
                        .overlay { if chosen { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.primary) } }
                        .overlay(Circle().strokeBorder(chosen ? Color.primary : .clear, lineWidth: 2))
                        .frame(width: 28, height: 28).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel(ReminderPalette.label(name))
                    .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }.padding(.vertical, 2)
    }
}

/// Kinds of lesson, then every lesson name in the past and coming fortnight, searchable; a search that matches nothing
/// can be added as a name of its own.
struct LessonPicker: View {
    /// The rule's lesson names and kinds being chosen: those that set it off, or those that keep it off a day.
    @Binding var subjects: [String]
    @Binding var kinds: [String]
    var title = "Choose lessons"
    let lessons: [TimetableEntry]?
    let loadError: String?
    @State private var search = ""
    /// Distinct lesson names, alphabetical.
    private var names: [String] {
        Array(Set((lessons ?? []).map(\.subject))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private func shown(_ text: String) -> Bool { query.isEmpty || text.localizedCaseInsensitiveContains(query) }
    var body: some View {
        List {
            let shownKinds = LessonKind.all.filter { kind in shown(kind.label) || names.contains { shown($0) && LessonKind.key(for: $0).matchesKind(kind.key) } }
            if !shownKinds.isEmpty {
                Section {
                    ForEach(shownKinds) { kind in
                        let examples = names.filter { LessonKind.key(for: $0).matchesKind(kind.key) }
                        toggleRow(selected: kinds.contains(kind.key), title: kind.label, symbol: kind.symbol,
                                  detail: examples.isEmpty ? "None in this timetable" : examples.joined(separator: ", ")) {
                            if let index = kinds.firstIndex(of: kind.key) { kinds.remove(at: index) } else { kinds.append(kind.key) }
                        }
                    }
                } header: { Text("Kinds of lesson") }
            }
            Section {
                ForEach(names.filter(shown), id: \.self) { name in
                    toggleRow(selected: subjects.contains { $0.caseInsensitiveCompare(name) == .orderedSame }, title: name, symbol: nil, detail: nil) {
                        if let index = subjects.firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { subjects.remove(at: index) }
                        else { subjects.append(name) }
                    }
                }
                if !query.isEmpty && !names.contains(where: { $0.caseInsensitiveCompare(query) == .orderedSame })
                    && !subjects.contains(where: { $0.caseInsensitiveCompare(query) == .orderedSame }) {
                    Button { subjects.append(query); search = "" } label: {
                        Label("Match lessons named “\(query)”", systemImage: "plus.circle.fill")
                    }
                }
                // Typed names that aren't in this timetable, so they can still be removed here.
                ForEach(subjects.filter { name in shown(name) && !names.contains { $0.caseInsensitiveCompare(name) == .orderedSame } }, id: \.self) { name in
                    toggleRow(selected: true, title: name, symbol: nil, detail: "Not in the past or coming fortnight") {
                        subjects.removeAll { $0 == name }
                    }
                }
                if lessons == nil && loadError == nil { ProgressView() }
            } header: { Text("Lessons in the past and coming fortnight") } footer: {
                if let loadError { Text(loadError) }
            }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search lessons")
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
    private func toggleRow(selected: Bool, title: String, symbol: String?, detail: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let symbol { Image(systemName: symbol).foregroundStyle(.teal).frame(width: 24).accessibilityHidden(true) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                }
                Spacer(minLength: 8)
                if selected { Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(.teal) }
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private extension String {
    /// Whether this lesson kind ("family/specialism") falls under `key` ("family" or "family/specialism").
    func matchesKind(_ key: String) -> Bool { self == key || hasPrefix(key + "/") }
}
