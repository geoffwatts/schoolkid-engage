import Foundation

/// A bell-feed event, ordered by its arrival timestamp rather than an assessment's due date.
public struct ActivityItem: Identifiable, Sendable {
    public let id: String
    public let type: String
    public let timestamp: String
    public let title: String
    public let subtitle: String
    public let childID: String?
    public let assessment: Assessment?
    public let raw: JSONValue
    public init(json: JSONValue) throws {
        id = try json.required("notificationID"); type = try json.required("type")
        timestamp = json["timestamp"].string ?? ""
        let key = type == "coneqtassessments" ? "coneqtAssessments" : type
        raw = json[key]
        title = raw["title"].string ?? "School update"; subtitle = raw["subtitle"].string ?? ""
        childID = raw["studentID"].string
        var subject = raw["subjectCode"]
        if let regex = try? NSRegularExpression(pattern: "(?i)(?:'s|’s)\\s+(.+?)\\s+assessment\\b"),
           let match = regex.firstMatch(in: subtitle, range: NSRange(location: 0, length: (subtitle as NSString).length)) {
            subject = .string((subtitle as NSString).substring(with: match.range(at: 1)))
        }
        if let assessmentID = raw["assessmentID"].string {
            assessment = try Assessment(json: .object([
                "id": .string(assessmentID), "title": .string(title), "subject": subject,
                "metaclassID": raw["metaclassID"], "programmeID": raw["programmeID"]
            ]))
        } else { assessment = nil }
    }
}

public struct AssessmentAttachment: Identifiable, Sendable {
    public var id: String { type + ":" + uuid }
    public let uuid: String
    public let type: String
    public let name: String
    public let mimeType: String
    public init(file: JSONValue, type: String, name: String? = nil) throws {
        uuid = try file.required("uuid"); self.type = type
        self.name = name ?? file["filename"].string ?? "Attachment"
        mimeType = file["mimetype"].string ?? "application/octet-stream"
    }
    public static func inlineFiles(in html: String, school: School) -> [AssessmentAttachment] {
        let pattern = "(?is)<(img|a)\\b[^>]*(?:src|href)\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let source = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: source.length)).compactMap { match in
            let tag = source.substring(with: match.range(at: 1)).lowercased()
            let text = source.substring(with: match.range(at: 2)).replacingOccurrences(of: "&amp;", with: "&")
            guard let url = URL(string: text, relativeTo: school.url)?.absoluteURL,
                  url.scheme == "https", url.host == school.url.host,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let uuid = components.queryItems?.first(where: { $0.name == "file" })?.value,
                  let type = components.queryItems?.first(where: { $0.name == "type" })?.value else { return nil }
            return try? AssessmentAttachment(file: .object([
                "uuid": .string(uuid.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))),
                "filename": .string(tag == "img" ? "Feedback photo" : "Feedback attachment"),
                "mimetype": .string(tag == "img" ? "image/*" : "application/octet-stream")
            ]), type: type)
        }
    }

}

/// The bell-feed events an account has already seen, so only new arrivals are announced.
/// Holds notification IDs only, never titles or other school content.
public struct SeenActivity: Codable, Equatable, Sendable {
    /// Most recent first, bounded by `limit`.
    public private(set) var ids: [String]
    public static let limit = 500
    public init(ids: [String] = []) { self.ids = Array(ids.prefix(Self.limit)) }

    /// Records `feed` as seen and returns its events that weren't seen before, oldest first.
    /// Without any history (a newly connected account, or one never checked) nothing is new:
    /// the existing feed becomes the baseline rather than a burst of announcements.
    public static func record(_ feed: [ActivityItem], after previous: SeenActivity?) -> (seen: SeenActivity, new: [ActivityItem]) {
        let known = Set(previous?.ids ?? [])
        let newest = feed.sorted { $0.timestamp > $1.timestamp }
        let fresh = previous == nil ? [] : newest.filter { !known.contains($0.id) }
        var ids = newest.map(\.id)
        let current = Set(ids)
        ids += (previous?.ids ?? []).filter { !current.contains($0) }
        return (SeenActivity(ids: ids), fresh.reversed())
    }
}
