import Foundation

public struct TimetableEntry: Identifiable, Sendable {
    public let id: String
    public let date: String
    public let subject: String
    public let code: String
    public let period: String
    public let teacher: String
    /// The teacher's school email, when SEQTA includes it.
    public let teacherEmail: String
    /// The class (SEQTA "metaclass") this lesson belongs to; assessments carry the same ID as `metaclassID`.
    public let classID: String
    public let room: String
    public let roomChanged: Bool
    public let start: Date
    public let end: Date
    public let raw: JSONValue
    public init(json: JSONValue, timeZone: TimeZone = .current) throws {
        date = String(try json.required("date").prefix(10))
        let from = try json.required("from"), until = try json.required("until")
        guard let start = Self.parse(date: date, time: from, timeZone: timeZone),
              let end = Self.parse(date: date, time: until, timeZone: timeZone), end > start else {
            throw SEQTAError.schema("Invalid timetable lesson time")
        }
        self.start = start; self.end = end
        subject = json["description"].string ?? json["code"].string ?? "Lesson"
        code = json["code"].string ?? ""; period = json["period"].string ?? ""
        teacher = json["staff"].string ?? ""; room = json["room"].string ?? ""
        teacherEmail = json["staffEmail"].string ?? ""; classID = json["metaID"].string ?? ""
        roomChanged = json["room_changed"].bool ?? false
        id = date + ":" + from + ":" + (json["ci"].string ?? json["id"].string ?? code + ":" + subject)
        raw = json
    }
    private static func parse(date: String, time: String, timeZone: TimeZone) -> Date? {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = timeZone
        let text = time.count > 10 ? time.replacingOccurrences(of: "T", with: " ") : date + " " + time
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd HH:mm:ss.SSSSSS"] {
            formatter.dateFormat = format
            if let value = formatter.date(from: text) { return value }
        }
        return nil
    }
}

public struct TimetableSchedule: Sendable {
    public let entries: [TimetableEntry]
    public let cycles: [String: [String]]
    public init(json: JSONValue, timeZone: TimeZone = .current) throws {
        entries = try json["items"].requiredArray().filter { $0["type"].string == "class" || $0["type"].string == "tutorial" }.map { try TimetableEntry(json: $0, timeZone: timeZone) }.sorted { $0.start < $1.start }
        if case .object(let values) = json["cycles"] { cycles = values.mapValues { $0.array?.compactMap(\.string) ?? [] } }
        else { cycles = [:] }
    }
}

/// Formats SEQTA's cycle-day strings for a fortnightly timetable: days 1–5 are Week A, days 6–10 are Week B.
public enum CycleLabel {
    /// The cycle day number in SEQTA's label ("Day 7" → 7), when there is exactly one such label.
    public static func day(in cycle: [String]) -> Int? {
        let parts = cycle.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard parts.count == 1, let match = parts[0].wholeMatch(of: #/(?i)day\s*(\d+)/#) else { return nil }
        return Int(match.1)
    }
    /// Week A/B only makes sense for a ten-day (fortnightly) cycle. A school's cycle length isn't published, so it's
    /// judged from the highest day seen: exactly 10 means a fortnight. Six- or eight-day cycles never reach 10.
    public static func isFortnight(maxDaySeen: Int?) -> Bool { maxDaySeen == 10 }
    /// "Day 7, Week B" for a fortnightly school, "Day 7" otherwise. Labels that already name a week, or aren't a plain
    /// day, are shown as SEQTA wrote them.
    public static func text(for cycle: [String], weekLetters: Bool) -> String? {
        let parts = cycle.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        if parts.contains(where: { $0.localizedCaseInsensitiveContains("week") }) { return parts.joined(separator: ", ") }
        guard let day = day(in: parts) else { return parts.joined(separator: ", ") }
        guard weekLetters, (1...10).contains(day) else { return "Day \(day)" }
        return "Day \(day), Week \(day <= 5 ? "A" : "B")"
    }
    /// Just the week ("Week A" or "Week B"), when the cycle identifies one.
    public static func week(for cycle: [String], weekLetters: Bool) -> String? {
        guard let text = text(for: cycle, weekLetters: weekLetters), let range = text.range(of: #"(?i)week\s*\w+"#, options: .regularExpression) else { return nil }
        return String(text[range])
    }
}

/// Side-by-side placement for lessons that overlap in time (e.g. an instrumental lesson during a class).
public struct TimetableLane: Equatable, Sendable {
    public let index: Int
    public let count: Int
    public init(index: Int, count: Int) { self.index = index; self.count = count }
}

public enum TimetableLayout {
    /// Assigns each lesson a lane within its cluster of overlapping lessons, keyed by lesson ID.
    /// Lessons that don't overlap anything get `TimetableLane(index: 0, count: 1)`.
    public static func lanes(for entries: [TimetableEntry]) -> [String: TimetableLane] {
        let sorted = entries.sorted { $0.start != $1.start ? $0.start < $1.start : $0.end > $1.end }
        var result: [String: TimetableLane] = [:]
        var cluster: [(id: String, lane: Int)] = []
        var laneEnds: [Date] = []
        var clusterEnd = Date.distantPast
        func close() {
            for item in cluster { result[item.id] = TimetableLane(index: item.lane, count: laneEnds.count) }
            cluster = []; laneEnds = []
        }
        for entry in sorted {
            if entry.start >= clusterEnd { close() }
            if let free = laneEnds.firstIndex(where: { $0 <= entry.start }) {
                laneEnds[free] = entry.end; cluster.append((entry.id, free))
            } else {
                laneEnds.append(entry.end); cluster.append((entry.id, laneEnds.count - 1))
            }
            clusterEnd = max(clusterEnd, entry.end)
        }
        close()
        return result
    }
}
