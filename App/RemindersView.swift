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
        }
        .navigationTitle(model.child.map { "Reminders for \($0.name.split(separator: " ").first.map(String.init) ?? $0.name)" } ?? "Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if !model.reminderRules.isEmpty { EditButton() } }
        .sheet(item: $editing) { rule in
            ReminderEditor(rule: rule) { saved in
                if let index = model.reminderRules.firstIndex(where: { $0.id == saved.id }) { model.reminderRules[index] = saved }
                else { model.reminderRules.append(saved) }
            }
        }
    }
}

enum ReminderSummary {
    /// "Days with Sport, PE & dance or Music".
    static func trigger(_ rule: ReminderRule) -> String {
        let names = rule.kinds.compactMap { LessonKind.named($0)?.label } + rule.subjects
        guard !names.isEmpty else { return "Choose the lessons it follows" }
        return "Days with " + ListFormatter.localizedString(byJoining: names).replacingOccurrences(of: " and ", with: " or ")
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
                        LessonPicker(rule: $rule, lessons: lessons, loadError: loadError)
                    } label: { Label(rule.kinds.isEmpty && rule.subjects.isEmpty ? "Choose lessons" : "Change lessons", systemImage: "checklist") }
                } header: { Text("On days with any of") } footer: {
                    Text("A kind of lesson covers every subject the app sorts into it. A lesson name matches any lesson whose name includes it.")
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
        let matching = lessons.filter { $0.start >= today && rule.matches(subject: $0.subject, kind: LessonKind.key(for: $0.subject)) }
        let grouped = Dictionary(grouping: matching) { Calendar.current.startOfDay(for: $0.start) }
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
    @Binding var rule: ReminderRule
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
            let kinds = LessonKind.all.filter { kind in shown(kind.label) || names.contains { shown($0) && LessonKind.key(for: $0).matchesKind(kind.key) } }
            if !kinds.isEmpty {
                Section {
                    ForEach(kinds) { kind in
                        let examples = names.filter { LessonKind.key(for: $0).matchesKind(kind.key) }
                        toggleRow(selected: rule.kinds.contains(kind.key), title: kind.label, symbol: kind.symbol,
                                  detail: examples.isEmpty ? "None in this timetable" : examples.joined(separator: ", ")) {
                            if let index = rule.kinds.firstIndex(of: kind.key) { rule.kinds.remove(at: index) } else { rule.kinds.append(kind.key) }
                        }
                    }
                } header: { Text("Kinds of lesson") }
            }
            Section {
                ForEach(names.filter(shown), id: \.self) { name in
                    toggleRow(selected: rule.subjects.contains { $0.caseInsensitiveCompare(name) == .orderedSame }, title: name, symbol: nil, detail: nil) {
                        if let index = rule.subjects.firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { rule.subjects.remove(at: index) }
                        else { rule.subjects.append(name) }
                    }
                }
                if !query.isEmpty && !names.contains(where: { $0.caseInsensitiveCompare(query) == .orderedSame })
                    && !rule.subjects.contains(where: { $0.caseInsensitiveCompare(query) == .orderedSame }) {
                    Button { rule.subjects.append(query); search = "" } label: {
                        Label("Match lessons named “\(query)”", systemImage: "plus.circle.fill")
                    }
                }
                // Typed names that aren't in this timetable, so they can still be removed here.
                ForEach(rule.subjects.filter { name in shown(name) && !names.contains { $0.caseInsensitiveCompare(name) == .orderedSame } }, id: \.self) { name in
                    toggleRow(selected: true, title: name, symbol: nil, detail: "Not in the past or coming fortnight") {
                        rule.subjects.removeAll { $0 == name }
                    }
                }
                if lessons == nil && loadError == nil { ProgressView() }
            } header: { Text("Lessons in the past and coming fortnight") } footer: {
                if let loadError { Text(loadError) }
            }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search lessons")
        .navigationTitle("Choose lessons").navigationBarTitleDisplayMode(.inline)
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
