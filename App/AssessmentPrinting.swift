import UIKit
import PDFKit
import SEQTAKit

/// One assessment, ready to print: its details, released files, and the context the app knows around it.
/// A printout of several assessments (a term's worth, say) is a list of these, each starting on a fresh page.
struct PrintableAssessment {
    let assessment: Assessment
    let details: JSONValue
    let media: [(AssessmentAttachment, Data)]
    /// Already worded, e.g. "Due 10 November 2026".
    var date: String?
    var teacher: String?
    var student: String?
}

@MainActor
enum AssessmentPrinting {
    static func present(_ assessments: [PrintableAssessment], jobName: String) throws {
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil); info.outputType = .general; info.jobName = jobName
        controller.printInfo = info
        controller.printingItem = nil; controller.printingItems = nil
        controller.printFormatter = nil
        controller.printingItem = try makePDF(assessments)
        controller.showsNumberOfCopies = false
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
           let window = scene.windows.first(where: \.isKeyWindow) {
            controller.present(from: CGRect(x: window.bounds.midX, y: 0, width: 1, height: 1), in: window, animated: true, completionHandler: nil)
        }
    }

    /// The printed write-up of one assessment: a header with its details and result, the marks, the full rubric,
    /// feedback, and a list of the files that follow on their own pages.
    static func html(for item: PrintableAssessment) -> String {
        let assessment = item.assessment, details = item.details
        var body = "<table class='head'><tr><td class='about'>"
        if assessment.subject != "Assessment" { body += "<div class='kicker'>" + escape(assessment.subject) + "</div>" }
        body += "<h1>" + escape(assessment.displayTitle) + "</h1>"
        for line in [item.date, item.teacher.map { "Teacher: " + $0 }, item.student.map { "Student: " + $0 }].compactMap({ $0 }) {
            body += "<div class='meta'>" + escape(line) + "</div>"
        }
        body += "</td><td class='result'>"
        if let result = AssessmentResult.overall(assessment: assessment, details: details) {
            // The headline is the grade if there is one, otherwise the percentage, otherwise the score; the rest sits beneath.
            let headline = result.grade ?? result.displayPercentage ?? result.displayScore ?? ""
            let rest = [result.displayScore, result.displayPercentage].compactMap { $0 }.filter { $0 != headline }
            body += "<div class='label'>Result</div><div class='big'>" + escape(headline) + "</div>"
            if !rest.isEmpty { body += "<div class='small'>" + escape(rest.joined(separator: " · ")) + "</div>" }
        } else {
            body += "<div class='label'>Result</div><div class='none'>Not released</div>"
        }
        body += "</td></tr></table>"

        if let overview = details["description"].string, !overview.isEmpty { body += "<h2>Overview</h2>" + safeMarkup(overview) }
        let criteria = details["criteria"].array ?? []
        if !criteria.isEmpty {
            func has(_ key: String) -> Bool { criteria.contains { $0["results"][key].string != nil } }
            let grades = has("grade"), scores = has("score"), percentages = has("percentage")
            body += "<h2>Marks</h2><table><tr><th>Criterion</th>"
            if grades { body += "<th>Grade</th>" }
            if scores { body += "<th class='num'>Score</th><th class='num'>Out of</th>" }
            if percentages { body += "<th class='num'>%</th>" }
            body += "</tr>"
            for criterion in criteria {
                let results = criterion["results"]
                body += "<tr><td>" + escape(criterion["label"].string ?? "Criterion") + "</td>"
                if grades { body += "<td><strong>" + escape(results["grade"].string ?? "—") + "</strong></td>" }
                if scores {
                    body += "<td class='num'>" + escape(results["score"].string.map(ScorePresentation.format) ?? "—") + "</td>"
                    body += "<td class='num'>" + escape((results["target"].string ?? criterion["target"].string).map(ScorePresentation.format) ?? "—") + "</td>"
                }
                if percentages { body += "<td class='num'>" + escape(results["percentage"].string.map { ScorePresentation.format($0) + "%" } ?? "—") + "</td>" }
                body += "</tr>"
            }
            body += "</table>"
            for criterion in criteria {
                let mode = criterion["rubric"]["mode"].string ?? "numeric"
                if let lines = criterion["rubric"]["lines"].array, !lines.isEmpty {
                    body += "<h3>Rubric" + (criteria.count > 1 ? " · " + escape(criterion["label"].string ?? "") : "") + "</h3><table class='rubric'>"
                    for line in lines {
                        body += "<tr><th>" + escape(line["title"].string ?? "Criterion") + "</th>"
                        for descriptor in RubricPresentation.orderedDescriptors(in: line, mode: mode) {
                            let selected = descriptor["id"].string != nil && descriptor["id"].string == criterion["rubricScore"][line["id"].string ?? ""]["id"].string
                            body += selected ? "<td class='selected'><div class='awarded'>Awarded</div>" : "<td>"
                            if let mark = RubricPresentation.mark(for: descriptor, mode: mode) { body += "<strong>" + escape(mark) + "</strong><br>" }
                            body += safeMarkup(descriptor["content"].string ?? "") + "</td>"
                        }
                        body += "</tr>"
                    }
                    body += "</table>"
                }
                if let feedback = criterion["engagement"]["feedbackComment"].string ?? criterion["feedback"].string, !feedback.isEmpty {
                    body += "<h3>Feedback · " + escape(criterion["label"].string ?? "Criterion") + "</h3>" + safeMarkup(feedback)
                }
            }
        }
        if let feedback = details["engagement"]["feedbackComment"].string ?? details["feedback"].string, !feedback.isEmpty {
            body += "<h2>Feedback</h2>" + safeMarkup(feedback)
        }
        if !item.media.isEmpty {
            // Photos and PDFs follow as pages; anything else (a Word document, say) can only be named here.
            func printable(_ data: Data) -> Bool { PDFDocument(data: data) != nil || UIImage(data: data) != nil }
            body += "<h2>Attached files</h2><ul>"
            for (attachment, data) in item.media {
                body += "<li>" + escape(attachment.name) + (printable(data) ? "" : " <span class='meta'>(not included in this printout)</span>") + "</li>"
            }
            body += "</ul>"
            if item.media.contains(where: { printable($0.1) }) { body += "<p class='meta'>The photos and PDFs follow on the next pages.</p>" }
        }
        return """
        <!doctype html><html><head><meta charset="utf-8"><style>
        body { font: 11pt -apple-system, Helvetica, sans-serif; color: #172126; }
        .head { width: 100%; border-collapse: collapse; margin: 0 0 6pt; }
        .head td { border: none; padding: 0; vertical-align: top; }
        .kicker { font-size: 9pt; font-weight: 600; letter-spacing: 1.5pt; text-transform: uppercase; color: #297d71; }
        h1 { font-size: 22pt; margin: 3pt 0 6pt; } .meta { color: #52606a; line-height: 1.5; }
        .result { width: 120pt; text-align: center; }
        .result .label { font-size: 8pt; font-weight: 600; letter-spacing: 1.5pt; text-transform: uppercase; color: #52606a; padding-top: 8pt; }
        .result .big { font-size: 34pt; font-weight: 700; color: #297d71; line-height: 1.1; }
        .result .small { font-size: 11pt; color: #172126; padding-bottom: 8pt; }
        .result .none { font-size: 11pt; color: #52606a; padding: 6pt 0 8pt; }
        td.result { border: 1.5pt solid #297d71; border-radius: 8pt; background: #f1f8f6; }
        h2 { font-size: 15pt; margin: 20pt 0 6pt; padding-bottom: 3pt; border-bottom: 1px solid #d5dde2; }
        h3 { font-size: 12pt; margin: 14pt 0 4pt; } p { line-height: 1.45; }
        table { border-collapse: collapse; width: 100%; margin: 6pt 0; font-size: 10pt; }
        th, td { border: 1px solid #bdc7ce; padding: 6pt; text-align: left; vertical-align: top; }
        th { background: #edf2f4; } .num { text-align: right; }
        .rubric { font-size: 9pt; } .rubric th { width: 18%; }
        .selected { background: #e2f3ee; border: 2px solid #297d71; }
        .awarded { font-size: 7.5pt; font-weight: 700; letter-spacing: 1pt; text-transform: uppercase; color: #297d71; }
        tr { page-break-inside: avoid; }
        </style></head><body>\(body)</body></html>
        """
    }

    private final class A4Renderer: UIPrintPageRenderer {
        override var paperRect: CGRect { CGRect(x: 0, y: 0, width: 595.28, height: 841.89) }
        override var printableRect: CGRect { paperRect.insetBy(dx: 36, dy: 36) }
    }
    /// Each assessment starts on a fresh page: its write-up, then its photos and PDFs.
    static func makePDF(_ assessments: [PrintableAssessment]) throws -> Data {
        let output = PDFDocument()
        let paper = A4Renderer().paperRect
        for item in assessments {
            let renderer = A4Renderer()
            renderer.addPrintFormatter(UIMarkupTextPrintFormatter(markupText: html(for: item)), startingAtPageAt: 0)
            renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
            let textData = UIGraphicsPDFRenderer(bounds: paper).pdfData { context in
                for page in 0..<renderer.numberOfPages { context.beginPage(); renderer.drawPage(at: page, in: paper) }
            }
            if let text = PDFDocument(data: textData) { append(text, to: output) }
            for (attachment, data) in item.media {
                if let pdf = PDFDocument(data: data) { append(pdf, to: output) }
                else if let image = UIImage(data: data) {
                    let pageData = UIGraphicsPDFRenderer(bounds: paper).pdfData { context in
                        context.beginPage()
                        (attachment.name as NSString).draw(in: CGRect(x: 36, y: 28, width: 523, height: 35), withAttributes: [.font: UIFont.systemFont(ofSize: 13, weight: .semibold)])
                        let area = CGRect(x: 36, y: 75, width: 523, height: 731)
                        let scale = min(area.width / image.size.width, area.height / image.size.height)
                        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                        image.draw(in: CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height))
                    }
                    if let page = PDFDocument(data: pageData) { append(page, to: output) }
                }
            }
        }
        guard output.pageCount > 0, let data = output.dataRepresentation() else { throw SEQTAError.schema("Could not prepare assessment PDF") }
        return data
    }
    private static func append(_ document: PDFDocument, to output: PDFDocument) {
        for index in 0..<document.pageCount {
            if let page = document.page(at: index)?.copy() as? PDFPage { output.insert(page, at: output.pageCount) }
        }
    }
    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    /// Keep text and simple structure; remove active content, links, remote images and all tag attributes.
    private static func safeMarkup(_ value: String) -> String {
        var text = value.replacingOccurrences(of: "(?is)<(script|style)\\b[^>]*>.*?</\\1>", with: "", options: .regularExpression)
        guard let regex = try? NSRegularExpression(pattern: "(?is)<(/?)([a-z0-9]+)\\b[^>]*>") else { return escape(value) }
        let allowed: Set<String> = ["p", "br", "b", "strong", "em", "i", "ul", "ol", "li", "table", "thead", "tbody", "tr", "th", "td", "h1", "h2", "h3", "h4", "blockquote"]
        let original = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: original.length)).reversed() {
            let tag = original.substring(with: match.range(at: 2)).lowercased()
            let slash = original.substring(with: match.range(at: 1))
            if let range = Range(match.range, in: text) { text.replaceSubrange(range, with: allowed.contains(tag) ? "<" + slash + tag + ">" : "") }
        }
        return text
    }
}
