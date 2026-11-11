import Foundation

/// One client represents exactly one school account. Read operations use POST because SEQTA's API does.
/// Create a distinct client for every account, including two accounts at the same school.
public actor SEQTAClient {
    public let school: School
    private let transport: any SEQTATransport
    private var sessionID: String?
    private var generation = 0
    private var fileCache: [String: (expires: Date, data: Data)] = [:]
    private let cacheLifetime: TimeInterval
    private var cache: [String: (expires: Date, payload: JSONValue)] = [:]
    private let cacheableRoutes: Set<String> = ["load/subjects", "load/timetable", "load/notices", "assessment/list/past", "assessment/list/upcoming", "assessment/get", "assessment/submissions/get"]

    public init(school: School, transport: any SEQTATransport = URLSessionTransport(), cacheLifetime: TimeInterval = 300) {
        self.school = school; self.transport = transport; self.cacheLifetime = cacheLifetime
    }
    public init(account: SavedAccount, transport: any SEQTATransport = URLSessionTransport(), cacheLifetime: TimeInterval = 300) {
        school = account.school; sessionID = account.sessionID; self.transport = transport; self.cacheLifetime = cacheLifetime
    }

    /// Passwords and setup JWTs are used for this exchange only; neither is retained.
    public func signIn(_ credentials: Credentials) async throws -> SavedAccount {
        generation += 1; sessionID = nil; cache.removeAll(); fileCache.removeAll()
        if case .password = credentials {
            let capabilities = try await request("login", body: .object([:]), authenticated: false)
            if capabilities["basic"].bool != true { throw SEQTAError.unsupportedAuthentication }
        }
        let payload = try await request("login", body: credentials.body, authenticated: false)
        if let status = payload["status"].string, status != "200" { throw SEQTAError.authenticationRequired }
        let person = try Person(json: payload)
        guard let sessionID, !sessionID.isEmpty else { throw SEQTAError.authenticationRequired }
        return SavedAccount(school: school, person: person, sessionID: sessionID)
    }

    /// Imports a session obtained by the caller's isolated school SSO browser, then verifies the authenticated person.
    /// Do not pass cookies from a shared or unrelated browser session.
    public func connect(sessionID: String) async throws -> SavedAccount {
        guard !sessionID.isEmpty, !sessionID.contains(where: { $0.isWhitespace || $0 == ";" }) else {
            throw SEQTAError.authenticationRequired
        }
        generation += 1; cache.removeAll(); fileCache.removeAll(); self.sessionID = sessionID
        let current = generation
        do {
            let person = try await validateSession()
            guard let verifiedSession = self.sessionID else { throw SEQTAError.authenticationRequired }
            return SavedAccount(school: school, person: person, sessionID: verifiedSession)
        } catch {
            if current == generation { self.sessionID = nil }
            throw error
        }
    }

    /// Public school metadata. Use a client without a saved session for the capability response.
    public func schoolDisplayName() async throws -> String? {
        let payload = try await request("login", authenticated: false)
        return payload["site.name"].string ?? payload["site.name.abbrev"].string
    }

    public func validateSession() async throws -> Person {
        let payload = try await request("login")
        if let status = payload["status"].string, status != "200" { throw SEQTAError.authenticationRequired }
        return try Person(json: payload)
    }

    /// Clears this client's credentials immediately; does not mutate another saved account.
    public func forgetSession() { generation += 1; sessionID = nil; cache.removeAll(); fileCache.removeAll() }

    /// Clears this account's in-memory read cache. Explicit refresh should call this before loading.
    public func clearCache() { cache.removeAll(); fileCache.removeAll() }

    /// Available children from the report selector. A school's permissions still govern every subsequent read.
    public func children() async throws -> [Child] {
        try await request("load/reports", body: .object(["list": .bool(true)])).requiredArray().map(Child.init)
    }

    public func activity() async throws -> [ActivityItem] {
        let payload = try await request("heartbeat", body: .object(["timestamp": .string("1970-01-01 00:00:00")]))
        return try payload["notifications"].requiredArray().map(ActivityItem.init).sorted { $0.timestamp > $1.timestamp }
    }

    /// School notices are account-wide; the upstream request does not take a child ID.
    public func news(on date: Date = Date(), timeZone: TimeZone = .current) async throws -> [Notice] {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone; f.dateFormat = "yyyy-MM-dd"
        return try await request("load/notices", body: .object(["date": .string(f.string(from: date))])).requiredArray().map(Notice.init)
    }

    public func timetable(for child: Child, from: Date, until: Date, timeZone: TimeZone = .current) async throws -> TimetableSchedule {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone; formatter.dateFormat = "yyyy-MM-dd"
        let payload = try await request("load/timetable", body: .object([
            "student": identifier(child.id), "from": .string(formatter.string(from: from)), "until": .string(formatter.string(from: until))
        ]))
        return try TimetableSchedule(json: payload, timeZone: timeZone)
    }

    public func courses(for child: Child) async throws -> [Course] {
        let students = try await request("load/subjects").requiredArray()
        guard let student = students.first(where: { $0["id"].string == child.id }) else { return [] }
        return try student["terms"].requiredArray().flatMap { term in
            try term["subjects"].requiredArray().map {
                try Course(json: $0, term: term["code"].string ?? "", active: term["active"].bool ?? false)
            }
        }
    }

    public func upcomingAssessments(for child: Child) async throws -> [Assessment] {
        try await request("assessment/list/upcoming", body: .object(["student": identifier(child.id)])).requiredArray().map { try Assessment(json: $0) }
    }

    /// Released results, feedback and pending results for a specific course and timetable period.
    public func pastAssessments(for child: Child, course: Course) async throws -> [Assessment] {
        let payload = try await request("assessment/list/past", body: .object([
            "student": identifier(child.id), "programme": identifier(course.programme),
            "metaclass": identifier(course.metaclass), "request": .string("task")
        ]))
        guard case .object = payload else { throw SEQTAError.schema("Expected assessment results") }
        var result: [Assessment] = []; var seen = Set<String>()
        for key in ["tasks", "feedback", "pending"] {
            for value in payload[key].array ?? [] {
                let item = try Assessment(json: value, course: course)
                if seen.insert(item.id).inserted { result.append(item) }
            }
        }
        return result
    }

    /// Results across every course and timetable period, newest due date first. No course filter is applied.
    public func allPastAssessments(for child: Child) async throws -> [Assessment] {
        let list = try await courses(for: child)
        var seen = Set<String>()
        let unique = list.filter { seen.insert($0.programme + ":" + $0.metaclass).inserted }
        return try await withThrowingTaskGroup(of: [Assessment].self) { group in
            var next = unique.makeIterator()
            for _ in 0..<4 {
                if let course = next.next() { group.addTask { try await self.pastAssessments(for: child, course: course) } }
            }
            var items: [String: Assessment] = [:]
            for try await batch in group {
                for item in batch { items[item.id] = item }
                if let course = next.next() { group.addTask { try await self.pastAssessments(for: child, course: course) } }
            }
            return items.values.sorted {
                if $0.due != $1.due { return $0.due > $1.due }
                if $0.title != $1.title { return $0.title < $1.title }
                return $0.id < $1.id
            }
        }
    }

    /// Includes description, resources, criteria and released feedback, preserving school-specific fields.
    public func assessmentDetails(_ assessment: Assessment, for child: Child) async throws -> JSONValue {
        var body: [String: JSONValue] = ["assessment": identifier(assessment.id), "student": identifier(child.id)]
        if let meta = assessment.metaclass { body["metaclass"] = identifier(meta) }
        if let syllabus = assessment.syllabus { body["syllabus"] = identifier(syllabus) }
        return try await request("assessment/get", body: .object(body))
    }

    public func reports(for child: Child) async throws -> [AcademicReport] {
        try await request("load/reports", body: .object(["student": identifier(child.id)])).requiredArray().map(AcademicReport.init)
    }

    public func assessmentAttachments(_ assessment: Assessment, for child: Child, details: JSONValue) async throws -> [AssessmentAttachment] {
        var files = try (details["resources"].array ?? []).compactMap { resource -> AssessmentAttachment? in
            guard resource["userfile"]["uuid"].string != nil else { return nil }
            return try AssessmentAttachment(file: resource["userfile"], type: "resource", name: resource["name"].string)
        }
        if case .object = details["submissionSettings"] {
            var body: [String: JSONValue] = ["assessment": identifier(assessment.id), "student": identifier(child.id)]
            if let meta = assessment.metaclass { body["metaclass"] = identifier(meta) }
            let submissions = try await request("assessment/submissions/get", body: .object(body)).requiredArray()
            for file in submissions where file["uuid"].string != nil {
                files.append(try AssessmentAttachment(file: file, type: "submission"))
            }
        }
        var html = [details["description"].string, details["engagement"]["feedbackComment"].string, details["feedback"].string].compactMap { $0 }
        html += (details["criteria"].array ?? []).compactMap { $0["engagement"]["feedbackComment"].string }
        for value in html { files += AssessmentAttachment.inlineFiles(in: value, school: school) }
        var seen = Set<String>(); return files.filter { seen.insert($0.id).inserted }
    }

    public func attachmentData(_ attachment: AssessmentAttachment) async throws -> Data {
        try await downloadFile(type: attachment.type, uuid: attachment.uuid)
    }

    /// Authenticated PDF download, including the school's redirect to its file stream.
    public func reportPDF(_ report: AcademicReport) async throws -> Data {
        let data = try await downloadFile(type: "report", uuid: report.id)
        guard data.starts(with: Data("%PDF-".utf8)) else { throw SEQTAError.invalidDocument }
        return data
    }

    private func downloadFile(type: String, uuid: String) async throws -> Data {
        guard sessionID != nil else { throw SEQTAError.authenticationRequired }
        let cacheKey = type + ":" + uuid
        if let entry = fileCache[cacheKey], entry.expires > Date() { return entry.data }
        var c = URLComponents(url: school.endpoint("load/file"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "type", value: type), URLQueryItem(name: "file", value: uuid)]
        var req = makeRequest(c.url!, method: "GET")
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        let current = generation
        var visited = Set<URL>()
        for _ in 0..<8 {
            guard let currentURL = req.url, visited.insert(currentURL).inserted else { throw SEQTAError.server("Report redirect loop") }
            let (data, response) = try await transport.send(req)
            guard generation == current else { throw CancellationError() }
            if [301, 302, 303, 307, 308].contains(response.statusCode) {
                guard let location = response.value(forHTTPHeaderField: "Location"),
                      let target = URL(string: location, relativeTo: response.url ?? currentURL)?.absoluteURL,
                      target.scheme?.lowercased() == "https", target.user == nil, target.password == nil else {
                    throw SEQTAError.server("Invalid report redirect")
                }
                let sameOrigin = target.host == school.url.host && (target.port ?? 443) == (school.url.port ?? 443)
                req = URLRequest(url: target); req.httpMethod = "GET"; req.httpShouldHandleCookies = false
                req.setValue("*/*", forHTTPHeaderField: "Accept")
                if sameOrigin, let sessionID { req.setValue("JSESSIONID=\(sessionID)", forHTTPHeaderField: "Cookie") }
                continue
            }
            try checkHTTP(response)
            // Bound the per-account media cache to 64 MB; it never goes to disk.
            fileCache = fileCache.filter { $0.value.expires > Date() }
            if fileCache.values.reduce(0, { $0 + $1.data.count }) + data.count > 64 * 1024 * 1024 { fileCache.removeAll() }
            if data.count <= 64 * 1024 * 1024 && cacheLifetime > 0 {
                fileCache[cacheKey] = (Date().addingTimeInterval(cacheLifetime), data)
            }
            return data
        }
        throw SEQTAError.server("Too many report redirects")
    }

    #if DEBUG
    public func diagnosticReads() async {
        for (path, body) in [
            ("heartbeat", JSONValue.object(["timestamp": .string("1970-01-01 00:00:00")])),
            ("login", JSONValue.object([:])),
            ("load/reports", .object(["list": .bool(true)])),
            ("load/subjects", .object([:])),
            ("load/notices", .object(["date": .string("2026-11-10")]))
        ] { _ = try? await request(path, body: body) }
        if let children = try? await children(), let child = children.first {
            _ = try? await request("load/timetable", body: .object(["from": .string("2026-11-09"), "until": .string("2026-11-15"), "student": identifier(child.id)]))
            _ = try? await upcomingAssessments(for: child)
            if let assessments = try? await allPastAssessments(for: child) {
                for assessment in assessments.prefix(3) {
                    if let detail = try? await assessmentDetails(assessment, for: child) {
                        _ = try? await assessmentAttachments(assessment, for: child, details: detail)
                    }
                }
            }
            if let reports = try? await reports(for: child), let report = reports.first { _ = try? await reportPDF(report) }
        }
    }
    #endif

    private func identifier(_ text: String) -> JSONValue {
        if let n = Int(text), abs(Double(n)) < 9_007_199_254_740_992 { return .number(Double(n)) }; return .string(text)
    }

    private func makeRequest(_ url: URL, method: String = "POST") -> URLRequest {
        var r = URLRequest(url: url); r.httpMethod = method; r.httpShouldHandleCookies = false
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue("SchoolkidEngage/0.1 SEQTAMobile/107", forHTTPHeaderField: "User-Agent")
        if let sessionID { r.setValue("JSESSIONID=\(sessionID)", forHTTPHeaderField: "Cookie") }
        return r
    }

    private func request(_ path: String, body: JSONValue = .object([:]), authenticated: Bool = true) async throws -> JSONValue {
        if authenticated && sessionID == nil { throw SEQTAError.authenticationRequired }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let bodyData = try encoder.encode(body)
        let key = path + ":" + bodyData.base64EncodedString()
        let cacheable = authenticated && cacheableRoutes.contains(path) && cacheLifetime > 0
        if cacheable, let entry = cache[key], entry.expires > Date() { return entry.payload }
        let current = generation
        var req = makeRequest(school.endpoint(path)); req.httpBody = bodyData
        let (data, response) = try await transport.send(req)
        guard current == generation else { throw CancellationError() }
        try checkHTTP(response)
        let json: JSONValue
        do { json = try JSONDecoder().decode(JSONValue.self, from: data) }
        catch { throw SEQTAError.schema("Expected a JSON response") }
        guard let status = json["status"].string else { throw SEQTAError.schema("Missing response status") }
        if status == "401" || status == "403" { sessionID = nil; cache.removeAll(); fileCache.removeAll(); throw SEQTAError.authenticationRequired }
        guard status == "200" else { throw SEQTAError.server(status) }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, field in
            result[String(describing: field.key)] = String(describing: field.value)
        }
        // Only persist a cookie from our requested origin. The default transport refuses all redirects.
        if let url = response.url, url.host == school.url.host, url.scheme == "https", url.port == school.url.port {
            for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: url) where cookie.name == "JSESSIONID" {
                guard !cookie.value.contains("\r"), !cookie.value.contains("\n"), !cookie.value.contains(";") else { continue }
                sessionID = cookie.value
            }
        }
        if cacheable { cache[key] = (Date().addingTimeInterval(cacheLifetime), json["payload"]) }
        return json["payload"]
    }

    private func checkHTTP(_ response: HTTPURLResponse) throws {
        if response.statusCode == 401 || response.statusCode == 403 { sessionID = nil; cache.removeAll(); fileCache.removeAll(); throw SEQTAError.authenticationRequired }
        guard (200..<300).contains(response.statusCode) else { throw SEQTAError.server(String(response.statusCode)) }
    }
}
