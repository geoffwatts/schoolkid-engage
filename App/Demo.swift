import Foundation
import SEQTAKit
import UIKit

enum Demo {
    static func notices() throws -> [Notice] {
        try [
            JSONValue.object(["id": .number(1), "title": .string("A week of curiosity"), "label_title": .string("From the school"), "staff": .string("School office"), "contents": .string("<p>Our learning showcase is coming up this Friday. Families are welcome to join us from 3:30 pm to see what students have been exploring this term.</p><p>Year 4 will share their marble-run designs and the science behind them, Year 5 has a gallery of charcoal self-portraits, and the Year 6 choir will open proceedings in the hall.</p><p>Light refreshments will be served by the Parents & Friends Association. Please sign in at the front office when you arrive.</p><p>We look forward to seeing you there.</p>")]),
            .object(["id": .number(2), "title": .string("Term dates & a few reminders"), "label_title": .string("Community"), "staff": .string("School office"), "contents": .string("<p>The library is open before school from 8 am. A reminder to return borrowed books before the end of term.</p>")]),
            .object(["id": .number(3), "title": .string("Athletics carnival this Thursday"), "label_title": .string("Sport"), "staff": .string("Mr Hale, Sport coordinator"), "contents": .string("<p>Students should wear house colours, bring a hat and a full water bottle. Families are welcome to cheer from the grandstand.</p>")]),
            .object(["id": .number(4), "title": .string("Book Week parade"), "label_title": .string("Library"), "staff": .string("Ms Rivera, Library"), "contents": .string("<p>Come dressed as your favourite book character on Friday morning. The parade starts at 8:45 am on the oval.</p>")])
        ].map(Notice.init)
    }
    static func assessments(child: Child) throws -> [Assessment] {
        try [JSONValue.object(["id": .number(1), "title": .string(child.id == "101" ? "Persuasive writing" : "Exploring ecosystems"), "subject": .string(child.id == "101" ? "English" : "Science"), "due": .string("Friday, 13 November"), "status": .string("UPCOMING"), "metaclassID": .number(10)]),
             .object(["id": .number(2), "title": .string("Patterns and problem solving"), "subject": .string("Mathematics"), "due": .string("Monday, 16 November"), "status": .string("UPCOMING"), "metaclassID": .number(11)]),
             .object(["id": .number(4), "title": .string("Field trip reflection"), "subject": .string("Humanities"), "due": .string("Friday, 6 November"), "status": .string("PENDING"), "overdue": .bool(true), "metaclassID": .number(12)]),
             .object(["id": .number(6), "title": .string("Science fair proposal"), "subject": .string("Physics"), "due": .string("Wednesday, 18 November"), "status": .string("UPCOMING"), "metaclassID": .number(13)]),
             .object(["id": .number(7), "title": .string("Self-portrait in charcoal"), "subject": .string("Visual Arts"), "due": .string("Friday, 20 November"), "status": .string("UPCOMING"), "metaclassID": .number(14)])].map { try Assessment(json: $0) }
    }
    static func courses() throws -> [Course] {
        try [("English", 10), ("Mathematics", 11), ("Humanities", 12), ("Physics", 13), ("Visual Arts", 14)].map { title, metaclass in
            try Course(json: .object(["programme": .number(1), "metaclass": .number(Double(metaclass)), "title": .string(title)]), term: "2026", active: true)
        }
    }
    static func results() throws -> [Assessment] {
        [try Assessment(json: .object(["id": .number(5), "title": .string("Book talk"), "subject": .string("English"), "status": .string("FEEDBACK_RELEASED"), "due": .string("2026-10-28"), "hasFeedback": .bool(true), "metaclassID": .number(10)])),
         try Assessment(json: .object(["id": .number(3), "title": .string("Reading journal"), "subject": .string("English"), "status": .string("MARKS_RELEASED"), "grade": .string("A"), "due": .string("2026-11-03"), "hasFeedback": .bool(true), "results": .object(["percentage": .number(90), "score": .number(18)]), "metaclassID": .number(10)])),
         try Assessment(json: .object(["id": .number(8), "title": .string("Fractions in action"), "subject": .string("Mathematics"), "status": .string("MARKS_RELEASED"), "grade": .string("B+"), "due": .string("2026-10-30"), "hasFeedback": .bool(true), "results": .object(["percentage": .number(84)]), "metaclassID": .number(11)])),
         try Assessment(json: .object(["id": .number(9), "title": .string("Forces and motion investigation"), "subject": .string("Physics"), "status": .string("MARKS_RELEASED"), "grade": .string("A"), "due": .string("2026-10-23"), "results": .object(["percentage": .number(94)]), "metaclassID": .number(13)])),
         try Assessment(json: .object(["id": .number(10), "title": .string("Ancient civilisations poster"), "subject": .string("Humanities"), "status": .string("MARKS_RELEASED"), "grade": .string("B"), "due": .string("2026-10-16"), "results": .object(["percentage": .number(76)]), "metaclassID": .number(12)])),
         try Assessment(json: .object(["id": .number(11), "title": .string("Still life drawing"), "subject": .string("Visual Arts"), "status": .string("MARKS_RELEASED"), "grade": .string("A-"), "due": .string("2026-10-09"), "results": .object(["percentage": .number(88)]), "metaclassID": .number(14)]))]
    }
    static func reports() throws -> [AcademicReport] {
        [try AcademicReport(json: .object(["uuid": .string("demo-report"), "year": .number(2026), "terms": .string("Semester 1"), "types": .string("Student progress report"), "created_date": .string("26 June 2026")])),
         try AcademicReport(json: .object(["uuid": .string("demo-report-2025"), "year": .number(2025), "terms": .string("Semester 2"), "types": .string("End of year report"), "created_date": .string("5 December 2025")]))]
    }
    static func assessmentDetails() -> JSONValue {
        .object([
            "description": .string("<p>Read the task outline and prepare your response for class.</p>"),
            "engagement": .object(["feedbackComment": .string("<p>A thoughtful response with clear examples.</p><table><tr><th>Strength</th><th>Next step</th></tr><tr><td>Clear evidence supports the main idea, with relevant examples explained throughout the response.</td><td>Develop the conclusion by connecting the strongest examples back to your main idea.</td></tr></table>")]),
            "criteria": .array([.object([
                "id": .number(1), "label": .string("Written response"), "target": .number(20),
                "results": .object(["grade": .string("A"), "score": .number(18), "target": .number(20), "percentage": .number(90)]),
                "rubric": .object(["mode": .string("numeric"), "lines": .array([.object([
                    "id": .number(11), "title": .string("Evidence"), "weight": .number(1),
                    "descriptors": .array([
                        .object(["id": .number(21), "content": .string("Uses relevant examples"), "score": .number(4)]),
                        .object(["id": .number(22), "content": .string("Develops clear supporting evidence"), "score": .number(5)])
                    ])
                ]), .object([
                    "id": .number(12), "title": .string("Structure and organisation"), "weight": .number(1),
                    "descriptors": .array([
                        .object(["id": .number(31), "content": .string("Organises ideas logically"), "score": .number(7)]),
                        .object(["id": .number(32), "content": .string("Builds a clear, well-sequenced argument from start to finish"), "score": .number(10)])
                    ])
                ])])]),
                "rubricScore": .object(["11": .object(["id": .number(22)]), "12": .object(["id": .number(32)])])
            ])])
        ])
    }
    static func activity() throws -> [ActivityItem] {
        let feed: [(Int, String, String, String, Int, Int)] = [
            (1, "2026-11-10T09:00:00", "Reading journal feedback released", "English", 3, 10),
            (2, "2026-11-09T15:20:00", "Fractions in action results released", "Mathematics", 8, 11),
            (3, "2026-11-06T11:05:00", "Forces and motion investigation results released", "Physics", 9, 13),
            (4, "2026-11-04T14:40:00", "Ancient civilisations poster results released", "Humanities", 10, 12),
            (5, "2026-10-30T10:15:00", "Still life drawing results released", "Visual Arts", 11, 14)
        ]
        return try feed.map { id, time, title, subject, assessment, metaclass in
            try ActivityItem(json: .object([
                "notificationID": .number(Double(id)), "type": .string("coneqtassessments"), "timestamp": .string(time),
                "coneqtAssessments": .object(["title": .string(title), "subtitle": .string("Alex Morgan’s \(subject) assessment"), "studentID": .number(101),
                                              "assessmentID": .number(Double(assessment)), "metaclassID": .number(Double(metaclass))])
            ]))
        }
    }
    static func attachments() throws -> [AssessmentAttachment] {
        [try AssessmentAttachment(file: .object(["uuid": .string("demo-photo"), "filename": .string("Annotated work photo"), "mimetype": .string("image/png")]), type: "resource"),
         try AssessmentAttachment(file: .object(["uuid": .string("demo-pdf"), "filename": .string("Marked assessment.pdf"), "mimetype": .string("application/pdf")]), type: "submission"),
         try AssessmentAttachment(file: .object(["uuid": .string("demo-docx"), "filename": .string("Essay feedback.docx"), "mimetype": .string("application/vnd.openxmlformats-officedocument.wordprocessingml.document")]), type: "resource")]
    }
    static func mediaData(_ attachment: AssessmentAttachment) -> Data {
        if attachment.mimeType.contains("pdf") { return pdf(child: "Demo assessment") }
        if attachment.mimeType.contains("word") { return Data(base64Encoded: demoDocx)! }
        // A fictional page of marked work: lined paper, a student's handwriting and the teacher's red ticks.
        return UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1200)).pngData { context in
            let page = CGRect(x: 0, y: 0, width: 900, height: 1200)
            UIColor(red: 0.99, green: 0.98, blue: 0.95, alpha: 1).setFill(); context.fill(page)
            UIColor(red: 0.62, green: 0.75, blue: 0.92, alpha: 0.55).setFill()
            for y in stride(from: 170.0, to: 1180, by: 56) { context.fill(CGRect(x: 0, y: y, width: 900, height: 2)) }
            UIColor(red: 0.93, green: 0.45, blue: 0.45, alpha: 0.7).setFill(); context.fill(CGRect(x: 110, y: 0, width: 3, height: 1200))
            let hand = UIFont(name: "Noteworthy-Light", size: 34) ?? .italicSystemFont(ofSize: 34)
            let ink = UIColor(red: 0.12, green: 0.2, blue: 0.48, alpha: 1)
            ("Reading journal — Week 4" as NSString).draw(at: CGPoint(x: 140, y: 92), withAttributes: [.font: UIFont(name: "Noteworthy-Bold", size: 40) ?? hand, .foregroundColor: ink])
            // A made-up book, so the screenshots carry no real titles or characters.
            let lines = ["In Finn and the Silver Kite, Finn is brave", "because he climbs the cliff path even", "though he is scared of heights. When the", "storm comes he keeps going to save the", "kite for his sister. This shows courage", "is doing something while you feel afraid.", "", "My favourite part is when the whole", "village helps fix the kite. It shows", "how kindness can change everyone."]
            for (i, line) in lines.enumerated() {
                (line as NSString).draw(at: CGPoint(x: 140, y: 178 + Double(i) * 56), withAttributes: [.font: hand, .foregroundColor: ink])
            }
            let red = UIColor(red: 0.82, green: 0.12, blue: 0.12, alpha: 1)
            let marker = UIFont(name: "MarkerFelt-Wide", size: 46) ?? .boldSystemFont(ofSize: 46)
            for y in [190.0, 470.0, 640.0] { ("✓" as NSString).draw(at: CGPoint(x: 800, y: y), withAttributes: [.font: marker, .foregroundColor: red]) }
            ("Great evidence!" as NSString).draw(at: CGPoint(x: 470, y: 760), withAttributes: [.font: UIFont(name: "MarkerFelt-Thin", size: 40) ?? marker, .foregroundColor: red])
            ("A" as NSString).draw(at: CGPoint(x: 760, y: 980), withAttributes: [.font: UIFont(name: "MarkerFelt-Wide", size: 96) ?? marker, .foregroundColor: red])
        }
    }
    static func timetable(on day: Date) throws -> TimetableSchedule {
        var calendar = Calendar(identifier: .gregorian); calendar.firstWeekday = 2
        let start = calendar.dateInterval(of: .weekOfYear, for: day)!.start
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        var items: [JSONValue] = []; var cycles: [String: JSONValue] = [:]
        // Alternate Week A / Week B from a fixed Monday so the fictional fortnight is stable.
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 1, day: 5))!
        let weeks = calendar.dateComponents([.weekOfYear], from: anchor, to: start).weekOfYear ?? 0
        // A ten-day fortnight (Week A/B); UI tests can ask for another length, such as an eight-day cycle.
        var cycleLength = 10
        #if DEBUG
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--demo-cycle-length=") }),
           let length = Int(argument.dropFirst("--demo-cycle-length=".count)), length > 0 { cycleLength = length }
        #endif
        let subjects = [("English", "08:40", "09:30", "E2"), ("Mathematics", "09:35", "10:25", "M1"), ("Physics", "10:50", "11:40", "Science 3"), ("Visual Arts", "12:25", "13:15", "Studio 1"), ("Humanities", "13:20", "14:10", "H2")]
        // Fictional teachers, keyed to the demo assessments' class IDs so the assessment header can name them.
        let teachers = ["English": ("Ms Rivera", "rivera@banksia.example", 10), "Mathematics": ("Mr Okafor", "okafor@banksia.example", 11),
                        "Physics": ("Dr Lin", "lin@banksia.example", 13), "Visual Arts": ("Ms Novak", "novak@banksia.example", 14),
                        "Humanities": ("Mr Hale", "hale@banksia.example", 12)]
        for offset in 0..<5 {
            let date = formatter.string(from: calendar.date(byAdding: .day, value: offset, to: start)!)
            // An instrumental lesson that overlaps a class, as many schools timetable them.
            if offset == 1 { items.append(.object(["ci": .number(99), "type": .string("class"), "date": .string(date), "description": .string("Piano"), "code": .string("Piano"), "period": .string("Instrumental"), "from": .string("08:30"), "until": .string("09:00"), "room": .string("Music 2"), "staff": .string("Demo tutor")])) }
            cycles[date] = .array([.string("Day \(((weeks * 5 + offset) % cycleLength + cycleLength) % cycleLength + 1)")])
            for (index, subject) in subjects.enumerated() {
                items.append(.object(["ci": .number(Double(offset * 10 + index)), "type": .string("class"), "date": .string(date), "description": .string(subject.0), "code": .string(subject.0), "period": .string("Period \(index + 1)"), "from": .string(subject.1), "until": .string(subject.2), "room": .string(subject.3), "staff": .string(teachers[subject.0]!.0), "staffEmail": .string(teachers[subject.0]!.1), "metaID": .number(Double(teachers[subject.0]!.2))]))
            }
        }
        return try TimetableSchedule(json: .object(["items": .array(items), "cycles": .object(cycles)]))
    }
    static func pdf(child: String) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            context.beginPage()
            let title = "BANKSIA COLLEGE\nDemo progress report\n\n\(child)\nSemester 1 · 2026"
            (title as NSString).draw(in: CGRect(x: 48, y: 60, width: 490, height: 260), withAttributes: [.font: UIFont.systemFont(ofSize: 25, weight: .semibold)])
            ("English     A\nMathematics     B\nScience     A\n\nA thoughtful and engaged learner.\n\nThis is fictional demo data." as NSString).draw(in: CGRect(x: 48, y: 340, width: 490, height: 350), withAttributes: [.font: UIFont.systemFont(ofSize: 17)])
        }
    }
}

/// A small fictional Word document (generated with macOS `textutil`) so the demo exercises inline DOCX previews.
private let demoDocx = "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"
