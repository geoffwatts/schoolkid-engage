import Foundation

/// A note to show on days with certain lessons, e.g. "PE uniform" on any day with a sport lesson, or "Take tuba" on
/// days with Music. A rule matches a lesson by name (case-insensitive, anywhere in the lesson's name) or by its kind,
/// as judged by the app's subject classifier (e.g. "health" for every PE, sport and dance lesson).
public struct ReminderRule: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var note: String
    public var isEnabled: Bool
    /// Lesson names, matched case-insensitively anywhere in the lesson's name.
    public var subjects: [String]
    /// Kinds of lesson: a family ("health") matches every specialism in it; "arts/music" matches only that one.
    public var kinds: [String]
    /// The note's background colour, by palette name ("yellow", "blue", …); nil is the default yellow.
    public var color: String?
    public init(id: UUID = UUID(), note: String = "", isEnabled: Bool = true, subjects: [String] = [], kinds: [String] = [], color: String? = nil) {
        self.id = id; self.note = note; self.isEnabled = isEnabled; self.subjects = subjects; self.kinds = kinds; self.color = color
    }
    public var trimmedNote: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Whether a lesson called `subject`, classified as `kind` ("family/specialism"), sets this rule off.
    public func matches(subject: String, kind: String) -> Bool {
        subjects.contains { name in
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return !name.isEmpty && subject.range(of: name, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        } || kinds.contains { kind == $0 || kind.hasPrefix($0 + "/") }
    }
}

/// One reminder as shown on a day: its text, the colour chosen for it, and the icon of the lesson that set it off.
public struct ReminderNote: Codable, Equatable, Hashable, Sendable {
    public let text: String
    public let color: String?
    /// The SF Symbol of the day's first lesson that set the reminder off, as shown beside that subject elsewhere in
    /// the app; nil when that subject has no icon of its own. Absent in snapshots written before it existed.
    public let symbol: String?
    public init(text: String, color: String? = nil, symbol: String? = nil) { self.text = text; self.color = color; self.symbol = symbol }
}

public enum Reminders {
    /// The notes for each day ("yyyy-MM-dd" → notes), from the switched-on rules with a note, in the rules' order.
    /// `kind` classifies a lesson name as "family/specialism"; `symbol` gives a lesson name's icon, if it has one.
    /// Lessons are taken in the order given, so a note's icon is that of the earliest lesson that set it off.
    public static func notes(rules: [ReminderRule], lessons: [(subject: String, day: String)], kind: (String) -> String,
                             symbol: (String) -> String? = { _ in nil }) -> [String: [ReminderNote]] {
        let active = rules.filter { $0.isEnabled && !$0.trimmedNote.isEmpty && !($0.subjects.isEmpty && $0.kinds.isEmpty) }
        guard !active.isEmpty else { return [:] }
        var kinds: [String: String] = [:]
        var subjectsByDay: [String: [String]] = [:]
        for lesson in lessons { subjectsByDay[lesson.day, default: []].append(lesson.subject) }
        var result: [String: [ReminderNote]] = [:]
        for (day, subjects) in subjectsByDay {
            var notes: [ReminderNote] = []
            for rule in active {
                guard let trigger = subjects.first(where: { subject in
                    let lessonKind = kinds[subject] ?? kind(subject); kinds[subject] = lessonKind
                    return rule.matches(subject: subject, kind: lessonKind)
                }), !notes.contains(where: { $0.text == rule.trimmedNote }) else { continue }
                notes.append(ReminderNote(text: rule.trimmedNote, color: rule.color, symbol: symbol(trigger)))
            }
            if !notes.isEmpty { result[day] = notes }
        }
        return result
    }
}
