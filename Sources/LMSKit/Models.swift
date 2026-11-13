import Foundation
import CryptoKit

public enum SEQTAError: Error, LocalizedError, Equatable {
    case invalidSchoolURL, invalidMagicLink, authenticationRequired, unsupportedAuthentication
    case server(String), schema(String), invalidDocument
    public var errorDescription: String? {
        switch self {
        case .invalidSchoolURL: return "Enter an HTTPS school portal URL without a path, query, or credentials."
        case .invalidMagicLink: return "This is not a valid SEQTA Engage setup link."
        case .authenticationRequired: return "Your session has expired. Sign in to this school again."
        case .unsupportedAuthentication: return "This school requires a different sign-in method. Use a Connect mobile app setup link."
        case .server(let status): return "SEQTA returned status \(status)."
        case .schema(let detail): return "This school's response is not yet supported: \(detail)."
        case .invalidDocument: return "The server did not return a PDF report."
        }
    }
}

/// A validated HTTPS origin. Paths and credentials are never accepted as school identifiers.
public struct School: Codable, Hashable, Sendable {
    public let url: URL
    public init(_ input: String) throws {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var c = URLComponents(string: text), c.scheme?.lowercased() == "https",
              let host = c.host, !host.isEmpty, c.user == nil, c.password == nil,
              c.query == nil, c.fragment == nil, c.path.isEmpty || c.path == "/" else {
            throw SEQTAError.invalidSchoolURL
        }
        c.scheme = "https"; c.host = host.lowercased(); c.path = ""
        guard let url = c.url else { throw SEQTAError.invalidSchoolURL }; self.url = url
    }
    public init(from decoder: Decoder) throws { try self.init(try decoder.singleValueContainer().decode(String.self)) }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(url.absoluteString) }
    func endpoint(_ path: String) -> URL { url.appendingPathComponent("seqta/parent/" + path) }
}

public enum Credentials: Sendable {
    case password(username: String, password: String)
    case jwt(String)
    var body: JSONValue {
        switch self {
        case .password(let u, let p): return .object(["username": .string(u), "password": .string(p)])
        case .jwt(let t): return .object(["jwt": .string(t)])
        }
    }
}

/// Decodes the vendor's setup-link envelope; decoding does not authenticate the token.
public struct SetupLink: Sendable {
    public let school: School
    public let token: String
    public init(_ text: String) throws {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "seqtaengage", url.host == "sso" else { throw SEQTAError.invalidMagicLink }
        var base64 = url.lastPathComponent.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64), let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              let origin = value["u"].string, let token = value["t"].string, !token.isEmpty else { throw SEQTAError.invalidMagicLink }
        school = try School(origin); self.token = token
    }
}

public struct Person: Sendable {
    public let id: String
    public let name: String
    public let username: String
    public init(json: JSONValue) throws {
        id = try json.required("id"); name = try json.required("userDesc"); username = json["userName"].string ?? ""
    }
}

public struct Child: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
    public init(json: JSONValue) throws { id = try json.required("id"); name = try json.required("name") }
}

public struct Notice: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let author: String
    public let label: String
    public let html: String
    public init(json: JSONValue) throws {
        title = try json.required("title")
        if let serverID = json["id"].string { id = serverID }
        else {
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            let content = try encoder.encode(json)
            id = SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined()
        }
        author = json["staff"].string ?? ""; label = json["label_title"].string ?? "School news"
        html = json["contents"].string ?? ""
    }
}

public struct Course: Identifiable, Sendable {
    public var id: String { "\(term):\(programme):\(metaclass)" }
    public let title: String
    public let programme: String
    public let metaclass: String
    public let term: String
    public let active: Bool
    public init(json: JSONValue, term: String, active: Bool) throws {
        title = try json.required("title"); programme = try json.required("programme"); metaclass = try json.required("metaclass")
        self.term = term; self.active = active
    }
}

public struct Assessment: Identifiable, Sendable {
    public var displayScore: String { ScorePresentation.format(score) }
    public var statusLabel: String {
        switch status {
        case "MARKS_RELEASED": return "Mark"
        case "FEEDBACK_RELEASED": return "Feedback"
        default: return status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    public var displayTitle: String {
        title.replacingOccurrences(of: "(?i)^results and feedback for\\s+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?i)\\s+released[.!]?$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public let id: String
    public let title: String
    public let subject: String
    public let due: String
    public let status: String
    public let score: String
    public let grade: String
    /// The overall result as a percentage (0–100), when SEQTA reports one.
    public let percentage: String
    /// Past the due date without a submission, as flagged by SEQTA.
    public let overdue: Bool
    /// Teacher feedback has been released for this assessment.
    public let hasFeedback: Bool
    /// "90%", or nil when there's no percentage.
    public var displayPercentage: String? { percentage.isEmpty ? nil : ScorePresentation.format(percentage) + "%" }
    public let metaclass: String?
    public let syllabus: String?
    public let raw: JSONValue
    public init(json: JSONValue, course: Course? = nil) throws {
        id = try json.required("id"); title = try json.required("title")
        subject = json["subject"].string ?? course?.title ?? "Assessment"
        due = json["due"].string ?? ""; status = json["status"].string ?? ""
        score = json["results"]["score"].string ?? json["score"].string ?? ""; grade = json["results"]["grade"].string ?? json["grade"].string ?? ""
        percentage = json["results"]["percentage"].string ?? json["percentage"].string ?? ""
        overdue = json["overdue"].bool ?? false; hasFeedback = json["hasFeedback"].bool ?? false
        metaclass = json["metaclassID"].string ?? course?.metaclass
        syllabus = json["syllabusId"].string; raw = json
    }
}

public struct AcademicReport: Identifiable, Sendable {
    public let id: String
    public let year: String
    public let term: String
    public let title: String
    public let date: String
    /// Publication timestamp when supplied; date-only values use local midnight.
    public var publishedAt: Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = iso.date(from: date) { return parsed }
        iso.formatOptions = [.withInternetDateTime]
        if let parsed = iso.date(from: date) { return parsed }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX"); parser.isLenient = false
        for format in ["yyyy-MM-dd", "d MMMM yyyy", "d MMM yyyy", "dd/MM/yyyy"] {
            parser.dateFormat = format
            if let parsed = parser.date(from: date) { return parsed }
        }
        return nil
    }
    public init(json: JSONValue) throws {
        id = try json.required("uuid"); year = json["year"].string ?? ""
        term = json["terms"].string ?? ""; title = json["types"].string ?? "Academic report"
        date = json["created_date"].string ?? ""
    }
}

/// Recognises SEQTA's "signed out" answers, the same way `SEQTAClient` treats them: HTTP 401/403, or a JSON body
/// whose `status` is "401"/"403". Lets an app notice expiry centrally rather than in every screen's error handling.
public enum SessionExpiry {
    public static func isExpired(statusCode: Int, body: Data) -> Bool {
        if statusCode == 401 || statusCode == 403 { return true }
        guard body.first == UInt8(ascii: "{"), let json = try? JSONDecoder().decode(JSONValue.self, from: body) else { return false }
        return ["401", "403"].contains(json["status"].string ?? "")
    }
}
