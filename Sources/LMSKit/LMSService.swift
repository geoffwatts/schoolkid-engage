import Foundation

/// What the app reads from a school's learning platform, for one signed-in account. SEQTA (`SEQTAClient`) is the only
/// provider so far; another would conform to this and produce the same models. Signing in is provider-specific and
/// stays with each provider's client.
public protocol LMSService: Sendable {
    func schoolDisplayName() async throws -> String?
    func validateSession() async throws -> Person
    /// Signs out locally: forgets the session and everything cached with it.
    func forgetSession() async
    func clearCache() async

    func children() async throws -> [Child]
    func activity() async throws -> [ActivityItem]
    func news(on date: Date, timeZone: TimeZone) async throws -> [Notice]
    func timetable(for child: Child, from: Date, until: Date, timeZone: TimeZone) async throws -> TimetableSchedule
    func courses(for child: Child) async throws -> [Course]
    func upcomingAssessments(for child: Child) async throws -> [Assessment]
    func pastAssessments(for child: Child, course: Course) async throws -> [Assessment]
    func allPastAssessments(for child: Child) async throws -> [Assessment]
    func assessmentDetails(_ assessment: Assessment, for child: Child) async throws -> JSONValue
    func assessmentAttachments(_ assessment: Assessment, for child: Child, details: JSONValue) async throws -> [AssessmentAttachment]
    func attachmentData(_ attachment: AssessmentAttachment) async throws -> Data
    func reports(for child: Child) async throws -> [AcademicReport]
    func reportPDF(_ report: AcademicReport) async throws -> Data
}

public extension LMSService {
    func news(on date: Date = Date()) async throws -> [Notice] { try await news(on: date, timeZone: .current) }
    func timetable(for child: Child, from: Date, until: Date) async throws -> TimetableSchedule {
        try await timetable(for: child, from: from, until: until, timeZone: .current)
    }
}

extension SEQTAClient: LMSService {}
