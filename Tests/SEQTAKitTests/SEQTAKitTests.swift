import XCTest
@testable import SEQTAKit

private actor MockTransport: SEQTATransport {
    struct Reply: Sendable {
        var json: String
        var status: Int = 200
        var cookie: String? = nil
        var headers: [String: String] = [:]
    }
    var replies: [Reply]
    private var requests: [URLRequest] = []
    init(_ replies: [Reply]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw SEQTAError.schema("Unexpected request") }
        let reply = replies.removeFirst()
        var headers = reply.headers
        if let cookie = reply.cookie { headers["Set-Cookie"] = "JSESSIONID=\(cookie); Path=/; Secure; HttpOnly" }
        return (Data(reply.json.utf8), HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: headers)!)
    }
    func captured() -> [URLRequest] { requests }
}

final class SEQTAKitTests: XCTestCase {
    private let person = #"{"status":"200","payload":{"id":7,"userDesc":"Test Parent","userName":"parent","status":"200"}}"#
    private func account(_ secret: String = "account-a") throws -> SavedAccount {
        SavedAccount(school: try School("https://school.example"), person: try Person(json: .object(["id": .number(7), "userDesc": .string("Parent")])), sessionID: secret)
    }

    func testSchoolRejectsCredentialAndPathInjection() throws {
        for input in ["http://school.example", "https://user:pass@school.example", "https://school.example/other", "https://school.example?jwt=secret", "https://school.example/#token"] {
            XCTAssertThrowsError(try School(input), input)
        }
        XCTAssertEqual(try School(" https://SCHOOL.example/ ").url.absoluteString, "https://school.example")
        XCTAssertThrowsError(try JSONDecoder().decode(School.self, from: Data(#""http://school.example""#.utf8)))
    }

    func testSetupLinkUsesObservedEnvelopeAndRejectsWrongApp() throws {
        let envelope = Data(#"{"u":"https://school.example","t":"secret-jwt"}"#.utf8).base64EncodedString()
        let link = try SetupLink("seqtaengage://sso/" + envelope)
        XCTAssertEqual(link.token, "secret-jwt")
        XCTAssertEqual(link.school, try School("https://school.example"))
        XCTAssertThrowsError(try SetupLink("seqtalearn://sso/" + envelope))
        XCTAssertThrowsError(try SetupLink("seqtaengage://sso/not-base64"))
        let bad = Data(#"{"u":"http://school.example","t":"secret"}"#.utf8).base64EncodedString()
        XCTAssertThrowsError(try SetupLink("seqtaengage://sso/" + bad))
    }

    func testPasswordSignInProbesThenExchangesJSONAndRetainsSessionOnly() async throws {
        let transport = MockTransport([.init(json: #"{"status":"200","payload":{"basic":true}}"#), .init(json: person, cookie: "new-session")])
        let client = SEQTAClient(school: try School("https://school.example"), transport: transport)
        let saved = try await client.signIn(.password(username: "parent", password: "private"))
        XCTAssertEqual(saved.sessionID, "new-session")
        let requests = await transport.captured()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].url?.path, "/seqta/parent/login")
        let body = try JSONDecoder().decode(JSONValue.self, from: requests[1].httpBody!)
        XCTAssertEqual(body["password"].string, "private")
        XCTAssertNil(requests[1].value(forHTTPHeaderField: "Cookie"))
        let persisted = String(data: try JSONEncoder().encode(saved), encoding: .utf8)!
        XCTAssertFalse(persisted.contains("private")); XCTAssertFalse(persisted.contains("password"))
    }

    func testSSOOnlySchoolDoesNotReceivePassword() async throws {
        let transport = MockTransport([.init(json: #"{"status":"200","payload":{"basic":false}}"#)])
        let client = SEQTAClient(school: try School("https://school.example"), transport: transport)
        do { _ = try await client.signIn(.password(username: "u", password: "p")); XCTFail() }
        catch { XCTAssertEqual(error as? SEQTAError, .unsupportedAuthentication) }
        let requests = await transport.captured(); XCTAssertEqual(requests.count, 1)
    }

    func testSAMLOnlySchoolDoesNotReceivePassword() async throws {
        let transport = MockTransport([.init(json: #"{"status":"200","payload":{"site.name":"Banksia College","saml":[{}]}}"#)])
        let client = SEQTAClient(school: try School("https://engage.banksia.example"), transport: transport)
        do { _ = try await client.signIn(.password(username: "u", password: "p")); XCTFail() }
        catch { XCTAssertEqual(error as? SEQTAError, .unsupportedAuthentication) }
        let requests = await transport.captured(); XCTAssertEqual(requests.count, 1)
    }

    func testBrowserSessionMustBeVerifiedBeforeSavingAccount() async throws {
        let transport = MockTransport([.init(json: person)])
        let client = SEQTAClient(school: try School("https://school.example"), transport: transport)
        let saved = try await client.connect(sessionID: "browser-session")
        XCTAssertEqual(saved.personID, "7"); XCTAssertEqual(saved.sessionID, "browser-session")
        let requests = await transport.captured()
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Cookie"), "JSESSIONID=browser-session")
        XCTAssertEqual(requests[0].httpBody, Data("{}".utf8))
    }

    func testAnonymousBrowserCookieCannotBecomeAnAccount() async throws {
        let transport = MockTransport([.init(json: #"{"status":"200","payload":{"saml":[{}]}}"#)])
        let client = SEQTAClient(school: try School("https://school.example"), transport: transport)
        do { _ = try await client.connect(sessionID: "anonymous"); XCTFail() } catch { }
        do { _ = try await client.children(); XCTFail() } catch { XCTAssertEqual(error as? SEQTAError, .authenticationRequired) }
        let requests = await transport.captured(); XCTAssertEqual(requests.count, 1)
    }

    func testTwoAccountsAtSameSchoolNeverShareCookies() async throws {
        let reply = MockTransport.Reply(json: #"{"status":"200","payload":[]}"#)
        let transportA = MockTransport([reply]); let transportB = MockTransport([reply])
        let a = SEQTAClient(account: try account("cookie-a"), transport: transportA)
        let b = SEQTAClient(account: try account("cookie-b"), transport: transportB)
        _ = try await a.children(); _ = try await b.children()
        let requestsA = await transportA.captured(); let requestsB = await transportB.captured()
        XCTAssertEqual(requestsA.first?.value(forHTTPHeaderField: "Cookie"), "JSESSIONID=cookie-a")
        XCTAssertEqual(requestsB.first?.value(forHTTPHeaderField: "Cookie"), "JSESSIONID=cookie-b")
        await a.forgetSession()
        do { _ = try await a.children(); XCTFail() } catch { XCTAssertEqual(error as? SEQTAError, .authenticationRequired) }
    }

    func testApplicationLevelExpiryIsNotAnEmptyList() async throws {
        let transport = MockTransport([.init(json: #"{"status":"401","payload":[]}"#)])
        let client = SEQTAClient(account: try account(), transport: transport)
        do { _ = try await client.children(); XCTFail() } catch { XCTAssertEqual(error as? SEQTAError, .authenticationRequired) }
        do { _ = try await client.children(); XCTFail() } catch { XCTAssertEqual(error as? SEQTAError, .authenticationRequired) }
        let requests = await transport.captured(); XCTAssertEqual(requests.count, 1)
    }

    func testChildAndCourseAreExplicitInAssessmentRequests() async throws {
        let transport = MockTransport([
            .init(json: #"{"status":"200","payload":[{"id":42,"title":"Essay","metaclassID":8}]}"#),
            .init(json: #"{"status":"200","payload":{"tasks":[{"id":42,"title":"Essay","results":{"score":18,"grade":"A"}}],"feedback":[],"pending":[]}}"#)
        ])
        let child = Child(id: "101", name: "Child")
        let course = try Course(json: .object(["title": .string("English"), "programme": .number(9), "metaclass": .number(8)]), term: "2026", active: true)
        let client = SEQTAClient(account: try account(), transport: transport)
        let upcoming = try await client.upcomingAssessments(for: child)
        XCTAssertEqual(upcoming[0].metaclass, "8")
        let past = try await client.pastAssessments(for: child, course: course)
        XCTAssertEqual(past[0].grade, "A"); XCTAssertEqual(past[0].score, "18")
        let requests = await transport.captured()
        let body = try JSONDecoder().decode(JSONValue.self, from: requests[1].httpBody!)
        XCTAssertEqual(body["student"], .number(101)); XCTAssertEqual(body["metaclass"], .number(8))
        XCTAssertEqual(body["programme"], .number(9)); XCTAssertEqual(body["request"], .string("task"))
    }

    func testMalformedNewsIsAnErrorRatherThanSilentEmpty() async throws {
        let transport = MockTransport([.init(json: #"{"status":"200","payload":{"unexpected":true}}"#)])
        let client = SEQTAClient(account: try account(), transport: transport)
        do { _ = try await client.news(); XCTFail() } catch { XCTAssertEqual(error as? SEQTAError, .schema("Expected a list")) }
    }

    func testReportRejectsHTMLLoginPageAndEncodesFileID() async throws {
        let transport = MockTransport([.init(json: "<html>Sign in</html>")])
        let client = SEQTAClient(account: try account(), transport: transport)
        let report = try AcademicReport(json: .object(["uuid": .string("a&file=other")]))
        do { _ = try await client.reportPDF(report); XCTFail() } catch { XCTAssertEqual(error as? SEQTAError, .invalidDocument) }
        let requests = await transport.captured()
        let query = URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.filter { $0.name == "file" }.map(\.value), ["a&file=other"])
        XCTAssertEqual(requests[0].httpMethod, "GET")
    }

    func testNoticesWithoutServerIDsHaveStableContentIdentity() throws {
        let first = try Notice(json: .object(["title": .string("School news"), "contents": .string("A notice")]))
        let second = try Notice(json: .object(["contents": .string("A notice"), "title": .string("School news")]))
        let changed = try Notice(json: .object(["title": .string("Other news"), "contents": .string("A notice")]))
        XCTAssertEqual(first.id, second.id); XCTAssertNotEqual(first.id, changed.id)
    }

    func testReportFollows301AndPreservesCookieOnlyAtSchoolOrigin() async throws {
        let transport = MockTransport([
            .init(json: "", status: 301, headers: ["Location": "/reports/file.pdf"]),
            .init(json: "", status: 302, headers: ["Location": "https://files.example/report.pdf?signature=test"]),
            .init(json: "%PDF-test")
        ])
        let client = SEQTAClient(account: try account(), transport: transport)
        let report = try AcademicReport(json: .object(["uuid": .string("report-id")]))
        let data = try await client.reportPDF(report)
        XCTAssertTrue(data.starts(with: Data("%PDF-".utf8)))
        let requests = await transport.captured()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Cookie"), "JSESSIONID=account-a")
        XCTAssertNil(requests[2].value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(requests[2].value(forHTTPHeaderField: "Authorization"))
    }

    func testReportRejectsInsecureRedirectAndLoops() async throws {
        for location in ["http://files.example/file.pdf", "/seqta/parent/load/file?type=report&file=report-id"] {
            let transport = MockTransport([.init(json: "", status: 301, headers: ["Location": location])])
            let client = SEQTAClient(account: try account(), transport: transport)
            let report = try AcademicReport(json: .object(["uuid": .string("report-id")]))
            do { _ = try await client.reportPDF(report); XCTFail() } catch { }
            let requests = await transport.captured(); XCTAssertEqual(requests.count, 1)
        }
    }

    func testReadCacheAvoidsRepeatRequestsAndExplicitRefreshBypassesIt() async throws {
        let reply = MockTransport.Reply(json: #"{"status":"200","payload":[]}"#)
        let transport = MockTransport([reply, reply])
        let client = SEQTAClient(account: try account(), transport: transport)
        _ = try await client.news(); _ = try await client.news()
        var requests = await transport.captured(); XCTAssertEqual(requests.count, 1)
        await client.clearCache(); _ = try await client.news()
        requests = await transport.captured(); XCTAssertEqual(requests.count, 2)
    }

    func testReadCacheExpiresAndChildBodiesStaySeparate() async throws {
        let reply = MockTransport.Reply(json: #"{"status":"200","payload":[]}"#)
        let transport = MockTransport([reply, reply, reply])
        let client = SEQTAClient(account: try account(), transport: transport, cacheLifetime: 0.01)
        _ = try await client.upcomingAssessments(for: Child(id: "1", name: "A"))
        _ = try await client.upcomingAssessments(for: Child(id: "2", name: "B"))
        try await Task.sleep(nanoseconds: 20_000_000)
        _ = try await client.upcomingAssessments(for: Child(id: "1", name: "A"))
        let requests = await transport.captured(); XCTAssertEqual(requests.count, 3)
    }

    func testNumericTermFlagsAndAllCourseResultsAreChronological() async throws {
        let transport = MockTransport([
            .init(json: #"{"status":"200","payload":[{"id":1,"name":"Child","terms":[{"code":"2026","active":1,"subjects":[{"title":"English","programme":2,"metaclass":3}]}]}]}"#),
            .init(json: #"{"status":"200","payload":{"tasks":[{"id":1,"title":"Older","due":"2026-01-02"},{"id":2,"title":"Newer","due":"2026-11-01"}]}}"#)
        ])
        let client = SEQTAClient(account: try account(), transport: transport)
        let child = Child(id: "1", name: "Child")
        let courses = try await client.courses(for: child); XCTAssertTrue(courses[0].active)
        let items = try await client.allPastAssessments(for: child)
        XCTAssertEqual(items.map(\.title), ["Newer", "Older"])
    }

    func testBellFeedUsesHistoricalTimestampAndPreservesAssessmentLink() async throws {
        let transport = MockTransport([.init(json: #"{"status":"200","payload":{"notifications":[{"notificationID":7,"timestamp":"2026-11-10T12:00:00","type":"coneqtassessments","coneqtAssessments":{"title":"Feedback released","studentID":1,"assessmentID":42,"metaclassID":3}}]}}"#)])
        let client = SEQTAClient(account: try account(), transport: transport)
        let feed = try await client.activity()
        XCTAssertEqual(feed[0].childID, "1"); XCTAssertEqual(feed[0].assessment?.id, "42")
        let requests = await transport.captured()
        let body = try JSONDecoder().decode(JSONValue.self, from: requests[0].httpBody!)
        XCTAssertEqual(body["timestamp"].string, "1970-01-01 00:00:00")
    }

    func testBellFeedKeepsEventsItCannotFullyRead() async throws {
        let transport = MockTransport([.init(json: #"{"status":"200","payload":{"notifications":[{"notificationID":7,"timestamp":"2026-11-10T12:00:00","type":"coneqtassessments","coneqtAssessments":{"title":"Feedback released","studentID":1,"assessmentID":42}},{"timestamp":"2026-11-09T12:00:00","type":"report","report":{"title":"Semester report available"}},{"notificationID":9,"timestamp":"2026-11-08T12:00:00","type":"mystery","payload":{"title":"Excursion reminder","subtitle":"Bring a hat"}},{"notificationID":10,"timestamp":"2026-11-07T12:00:00","type":"mystery"},"not an object"]}}"#)])
        let feed = try await SEQTAClient(account: try account(), transport: transport).activity()
        // A malformed event no longer takes the feed down: titles are found wherever they are, a well-formed event
        // with none keeps the generic row, and something with no title, ID or type is skipped.
        XCTAssertEqual(feed.map(\.title), ["Feedback released", "Semester report available", "Excursion reminder", "School update"])
        XCTAssertEqual(feed[0].assessment?.id, "42")
        XCTAssertNil(feed[1].assessment); XCTAssertNil(feed[2].assessment)
        XCTAssertEqual(feed[2].subtitle, "Bring a hat")
        // Without a notificationID the event still gets a stable identity, so it isn't news on every read.
        XCTAssertEqual(feed[1].id, "untyped:2026-11-09T12:00:00:Semester report available")
    }

    func testOverallResultPrefersSEQTAThenWorksItOutFromCriteria() throws {
        let bare = try Assessment(json: .object(["id": .string("1"), "title": .string("Test")]))
        func criterion(_ grade: String?, _ score: Double?, _ target: Double?) -> JSONValue {
            var results: [String: JSONValue] = [:]
            if let grade { results["grade"] = .string(grade) }
            if let score { results["score"] = .number(score) }
            if let target { results["target"] = .number(target) }
            return .object(["results": .object(results)])
        }
        // The assessment's own result wins.
        let own = JSONValue.object(["results": .object(["grade": .string("B"), "percentage": .number(72)]), "criteria": .array([criterion("A", 9, 10)])])
        XCTAssertEqual(AssessmentResult.overall(assessment: bare, details: own), AssessmentResult(grade: "B", percentage: "72"))
        // One criterion is the result, with the percentage worked out.
        let one = AssessmentResult.overall(assessment: bare, details: .object(["criteria": .array([criterion("A", 48, 50)])]))
        XCTAssertEqual(one?.grade, "A"); XCTAssertEqual(one?.displayScore, "48 / 50"); XCTAssertEqual(one?.displayPercentage, "96%")
        // Several add up; differing grades give no overall grade.
        let two = AssessmentResult.overall(assessment: bare, details: .object(["criteria": .array([criterion("A", 48, 50), criterion("B", 9, 10)])]))
        XCTAssertNil(two?.grade); XCTAssertEqual(two?.displayScore, "57 / 60"); XCTAssertEqual(two?.displayPercentage, "95%")
        // Partly marked: no total that would mislead.
        XCTAssertNil(AssessmentResult.overall(assessment: bare, details: .object(["criteria": .array([criterion("A", 48, 50), criterion(nil, nil, 10)])])))
        // Nothing released.
        XCTAssertNil(AssessmentResult.overall(assessment: bare, details: .object(["criteria": .array([criterion(nil, nil, 20)])])))
    }

    private func bell(_ id: Int, _ timestamp: String) throws -> ActivityItem {
        try ActivityItem(json: .object(["notificationID": .number(Double(id)), "type": .string("coneqtassessments"), "timestamp": .string(timestamp),
                                        "coneqtAssessments": .object(["title": .string("Item \(id)")])]))
    }

    func testFirstLookAtBellFeedIsABaselineNotNews() throws {
        let feed = [try bell(1, "2026-11-01T09:00:00"), try bell(2, "2026-11-02T09:00:00")]
        let first = SeenActivity.record(feed, after: nil)
        XCTAssertTrue(first.new.isEmpty)
        XCTAssertEqual(first.seen.ids, ["2", "1"])
        // An account with an empty feed has history, so its first event is news.
        XCTAssertEqual(SeenActivity.record([feed[0]], after: SeenActivity()).new.map(\.id), ["1"])
    }

    func testBellFeedReportsOnlyUnseenEventsOldestFirst() throws {
        let previous = SeenActivity(ids: ["1"])
        let feed = [try bell(3, "2026-11-03T09:00:00"), try bell(1, "2026-11-01T09:00:00"), try bell(2, "2026-11-02T09:00:00")]
        let result = SeenActivity.record(feed, after: previous)
        XCTAssertEqual(result.new.map(\.id), ["2", "3"])
        XCTAssertEqual(result.seen.ids, ["3", "2", "1"])
        XCTAssertTrue(SeenActivity.record(feed, after: result.seen).new.isEmpty)
    }

    func testSeenBellFeedKeepsOlderIDsButStaysBounded() throws {
        let previous = SeenActivity(ids: (0..<SeenActivity.limit + 20).map { "old\($0)" })
        XCTAssertEqual(previous.ids.count, SeenActivity.limit)
        let result = SeenActivity.record([try bell(9, "2026-11-09T09:00:00")], after: previous)
        XCTAssertEqual(result.seen.ids.first, "9"); XCTAssertEqual(result.seen.ids[1], "old0")
        XCTAssertEqual(result.seen.ids.count, SeenActivity.limit)
    }

    func testInlineFeedbackFilesStayScopedToSchool() throws {
        let html = "<img src='/seqta/parent/load/file?type=resource&amp;file=photo'><a href='https://other.example/load/file?type=resource&amp;file=other'>Other</a>"
        let files = AssessmentAttachment.inlineFiles(in: html, school: try School("https://school.example"))
        XCTAssertEqual(files.count, 1); XCTAssertEqual(files[0].uuid, "photo"); XCTAssertEqual(files[0].mimeType, "image/*")
    }

    func testAssessmentResourcesAndTeacherFilesUseTheirOwnFileTypes() async throws {
        let transport = MockTransport([.init(json: #"{"status":"200","payload":[{"uuid":"marked","filename":"Marked.pdf","mimetype":"application/pdf","staff":"Teacher"}]}"#)])
        let client = SEQTAClient(account: try account(), transport: transport)
        let assessment = try Assessment(json: .object(["id": .number(42), "title": .string("Test"), "metaclassID": .number(8)]))
        let details: JSONValue = .object([
            "submissionSettings": .object([:]),
            "resources": .array([.object(["name": .string("Task photo"), "userfile": .object(["uuid": .string("photo"), "filename": .string("work.jpg"), "mimetype": .string("image/jpeg")])])])
        ])
        let files = try await client.assessmentAttachments(assessment, for: Child(id: "1", name: "Child"), details: details)
        XCTAssertEqual(files.map(\.type), ["resource", "submission"])
        XCTAssertEqual(files.map(\.name), ["Task photo", "Marked.pdf"])
    }

    func testMediaDownloadIsCachedForFastReopening() async throws {
        let transport = MockTransport([.init(json: "%PDF-demo")])
        let client = SEQTAClient(account: try account(), transport: transport)
        let file = try AssessmentAttachment(file: .object(["uuid": .string("marked"), "filename": .string("Marked.pdf")]), type: "submission")
        _ = try await client.attachmentData(file); _ = try await client.attachmentData(file)
        let requests = await transport.captured(); XCTAssertEqual(requests.count, 1)
        let query = URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first(where: { $0.name == "type" })?.value, "submission")
    }

    func testRubricGradeBandsShowAThroughEWithoutChangingAwardedIDs() {
        let line: JSONValue = .object(["descriptors": .array([
            .object(["id": .number(5), "grade": .string("E")]),
            .object(["id": .number(1), "grade": .string("A")]),
            .object(["id": .number(3), "grade": .string("C")])
        ])])
        let descriptors = RubricPresentation.orderedDescriptors(in: line, mode: "graded")
        XCTAssertEqual(descriptors.compactMap { RubricPresentation.mark(for: $0, mode: "graded") }, ["A", "C", "E"])
        XCTAssertEqual(descriptors.compactMap { $0["id"].string }, ["1", "3", "5"])
    }

    func testNumericRubricScoresGoFromHighestToLowestWithoutInventingLetterGrades() {
        let line: JSONValue = .object(["descriptors": .array([.object(["score": .number(1)]), .object(["score": .number(4)]), .object(["score": .number(2)])])])
        XCTAssertEqual(RubricPresentation.orderedDescriptors(in: line).compactMap { RubricPresentation.mark(for: $0) }, ["4", "2", "1"])
    }

    func testScoresUseAtMostTwoDecimalPlacesAndPreserveGradeLetters() {
        XCTAssertEqual(ScorePresentation.format("5.670000076293945"), "5.67")
        XCTAssertEqual(ScorePresentation.format("18"), "18")
        XCTAssertEqual(ScorePresentation.format("2.345"), "2.35")
        XCTAssertEqual(ScorePresentation.format("A"), "A")
    }

    func testOverlappingLessonsShareTheColumnSideBySide() throws {
        func lesson(_ subject: String, _ from: String, _ until: String) throws -> TimetableEntry {
            try TimetableEntry(json: .object(["date": .string("2026-11-10"), "from": .string(from), "until": .string(until), "description": .string(subject), "code": .string(subject)]))
        }
        let english = try lesson("English", "08:40", "09:30")
        let piano = try lesson("Piano", "08:30", "09:00")
        let maths = try lesson("Maths", "09:35", "10:25")
        let lanes = TimetableLayout.lanes(for: [english, piano, maths])
        XCTAssertEqual(lanes[piano.id], TimetableLane(index: 0, count: 2))
        XCTAssertEqual(lanes[english.id], TimetableLane(index: 1, count: 2))
        XCTAssertEqual(lanes[maths.id], TimetableLane(index: 0, count: 1))
    }

    func testAssessmentReadsStatusFlagsAndPercentage() throws {
        let past = try Assessment(json: .object(["id": .number(7), "title": .string("Essay"), "overdue": .bool(false), "hasFeedback": .bool(true),
                                                  "results": .object(["percentage": .number(87.5), "score": .number(35)])]))
        XCTAssertTrue(past.hasFeedback); XCTAssertFalse(past.overdue)
        XCTAssertEqual(past.displayPercentage, "87.5%")
        let late = try Assessment(json: .object(["id": .number(8), "title": .string("Reflection"), "overdue": .bool(true)]))
        XCTAssertTrue(late.overdue); XCTAssertFalse(late.hasFeedback); XCTAssertNil(late.displayPercentage)
    }

    func testCycleLabelSplitsFortnightIntoWeeks() {
        XCTAssertEqual(CycleLabel.text(for: ["Day 1"], weekLetters: true), "Day 1, Week A")
        XCTAssertEqual(CycleLabel.text(for: ["Day 5"], weekLetters: true), "Day 5, Week A")
        XCTAssertEqual(CycleLabel.text(for: ["Day 6"], weekLetters: true), "Day 6, Week B")
        XCTAssertEqual(CycleLabel.text(for: ["day 10"], weekLetters: true), "Day 10, Week B")
        XCTAssertEqual(CycleLabel.text(for: ["Day 3", "Week B"], weekLetters: true), "Day 3, Week B")
        XCTAssertEqual(CycleLabel.text(for: ["Day 12"], weekLetters: true), "Day 12")
        XCTAssertEqual(CycleLabel.text(for: ["Sports carnival"], weekLetters: true), "Sports carnival")
        XCTAssertNil(CycleLabel.text(for: [], weekLetters: true))
        XCTAssertNil(CycleLabel.text(for: [" "], weekLetters: true))
        XCTAssertEqual(CycleLabel.week(for: ["Day 2"], weekLetters: true), "Week A")
        XCTAssertEqual(CycleLabel.week(for: ["Day 7"], weekLetters: true), "Week B")
        XCTAssertNil(CycleLabel.week(for: ["Day 12"], weekLetters: true))
    }

    func testSessionExpiryMatchesClientRules() {
        XCTAssertTrue(SessionExpiry.isExpired(statusCode: 401, body: Data()))
        XCTAssertTrue(SessionExpiry.isExpired(statusCode: 200, body: Data(#"{"status":"401"}"#.utf8)))
        XCTAssertTrue(SessionExpiry.isExpired(statusCode: 200, body: Data(#"{"status":403}"#.utf8)))
        XCTAssertFalse(SessionExpiry.isExpired(statusCode: 200, body: Data(#"{"status":"200","payload":[]}"#.utf8)))
        XCTAssertFalse(SessionExpiry.isExpired(statusCode: 200, body: Data("%PDF-1.7".utf8)))
    }

    func testWeekLettersOnlyForTenDayCycles() {
        XCTAssertTrue(CycleLabel.isFortnight(maxDaySeen: 10))
        for other in [nil, 5, 6, 8, 12] { XCTAssertFalse(CycleLabel.isFortnight(maxDaySeen: other)) }
        // A six-day school: day 6 is just "Day 6", never "Week B".
        XCTAssertEqual(CycleLabel.text(for: ["Day 6"], weekLetters: false), "Day 6")
        XCTAssertNil(CycleLabel.week(for: ["Day 2"], weekLetters: false))
        XCTAssertEqual(CycleLabel.day(in: ["Day 9"]), 9)
        XCTAssertNil(CycleLabel.day(in: ["Assembly"]))
    }

    func testTimetableUsesExplicitChildWeekAndLocalLessonTimes() async throws {
        let transport = MockTransport([.init(json: #"{"status":"200","payload":{"items":[{"ci":1,"type":"class","date":"2026-11-10","from":"08:40:00","until":"09:30:00","description":"Physics","code":"PHY","room":"Lab 2","staff":"Teacher","period":"1"}],"cycles":{"2026-11-10":["Day 2"]}}}"#)])
        let client = SEQTAClient(account: try account(), transport: transport)
        let start = ISO8601DateFormatter().date(from: "2026-11-09T00:00:00Z")!
        let schedule = try await client.timetable(for: Child(id: "101", name: "Child"), from: start, until: start.addingTimeInterval(6 * 86400), timeZone: TimeZone(identifier: "Australia/Perth")!)
        XCTAssertEqual(schedule.entries.count, 1); XCTAssertEqual(schedule.entries[0].subject, "Physics")
        XCTAssertEqual(schedule.entries[0].end.timeIntervalSince(schedule.entries[0].start), 3000)
        XCTAssertEqual(schedule.cycles["2026-11-10"], ["Day 2"])
        let requests = await transport.captured()
        let body = try JSONDecoder().decode(JSONValue.self, from: requests[0].httpBody!)
        XCTAssertEqual(body["student"], .number(101)); XCTAssertEqual(body["from"].string, "2026-11-09")
    }

    func testNumericRubricNeverDisplaysTheIncidentalLetterGradeField() {
        let descriptor: JSONValue = .object(["id": .number(100), "grade": .string("E"), "score": .number(10)])
        XCTAssertEqual(RubricPresentation.mark(for: descriptor, mode: "numeric"), "10")
        XCTAssertEqual(RubricPresentation.mark(for: descriptor, mode: "graded"), "E")
        let line: JSONValue = .object(["descriptors": .array([
            .object(["id": .number(200), "grade": .string("A"), "score": .number(0)]), descriptor
        ])])
        XCTAssertEqual(RubricPresentation.orderedDescriptors(in: line, mode: "numeric").first?["id"].string, "100")
        XCTAssertEqual(RubricPresentation.orderedDescriptors(in: line, mode: "graded").first?["id"].string, "200")
    }

    func testNewsDateUsesRequestedSchoolTimezoneAndNotChild() async throws {
        let transport = MockTransport([.init(json: #"{"status":200,"payload":[]}"#)])
        let client = SEQTAClient(account: try account(), transport: transport)
        let date = ISO8601DateFormatter().date(from: "2026-11-10T20:00:00Z")!
        _ = try await client.news(on: date, timeZone: TimeZone(identifier: "Australia/Perth")!)
        let requests = await transport.captured()
        let body = try JSONDecoder().decode(JSONValue.self, from: requests[0].httpBody!)
        XCTAssertEqual(body["date"].string, "2026-11-11"); XCTAssertEqual(body["student"], .null)
    }
}
