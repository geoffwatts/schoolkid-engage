import UIKit
import PDFKit
import SEQTAKit

@MainActor
enum AssessmentPrinting {
    static func present(assessment: Assessment, details: JSONValue, media: [(AssessmentAttachment, Data)]) throws {
        var body = "<h1>" + escape(assessment.displayTitle) + "</h1>"
        if assessment.subject != "Assessment" { body += "<p class='meta'>" + escape(assessment.subject) + " assessment</p>" }
        if !assessment.due.isEmpty { body += "<p>Due: " + escape(reportDate(assessment.due)) + "</p>" }
        if let overview = details["description"].string { body += "<h2>Overview</h2>" + safeMarkup(overview) }
        let criteria = details["criteria"].array ?? []
        if !criteria.isEmpty {
            body += "<h2>Grades &amp; rubric</h2><table><tr><th>Criterion</th><th>Grade</th><th>Score</th></tr>"
            for criterion in criteria {
                let score = criterion["results"]["score"].string
                let target = criterion["results"]["target"].string ?? criterion["target"].string
                let scoreText = score.map { ScorePresentation.format($0) + (target.map { " / " + ScorePresentation.format($0) } ?? "") } ?? "—"
                body += "<tr><td>" + escape(criterion["label"].string ?? "Criterion") + "</td><td>" + escape(criterion["results"]["grade"].string ?? "—") + "</td><td>" + escape(scoreText) + "</td></tr>"
            }
            body += "</table>"
            for criterion in criteria {
                if let lines = criterion["rubric"]["lines"].array, !lines.isEmpty {
                    body += "<h3>" + escape(criterion["label"].string ?? "Rubric") + "</h3><table>"
                    for line in lines {
                        body += "<tr><th>" + escape(line["title"].string ?? "Criterion") + "</th>"
                        for descriptor in RubricPresentation.orderedDescriptors(in: line, mode: criterion["rubric"]["mode"].string ?? "numeric") {
                            let selected = descriptor["id"].string != nil && descriptor["id"].string == criterion["rubricScore"][line["id"].string ?? ""]["id"].string
                            body += selected ? "<td class='selected'>" : "<td>"
                            if selected { body += "<strong>Awarded</strong><br>" }
                            if let mark = RubricPresentation.mark(for: descriptor, mode: criterion["rubric"]["mode"].string ?? "numeric") { body += "<strong>" + escape(mark) + "</strong><br>" }
                            body += safeMarkup(descriptor["content"].string ?? "")
                            body += "</td>"
                        }
                        body += "</tr>"
                    }
                    body += "</table>"
                }
                if let feedback = criterion["engagement"]["feedbackComment"].string {
                    body += "<h3>" + escape(criterion["label"].string ?? "Criterion feedback") + "</h3>" + safeMarkup(feedback)
                }
            }
        }
        if let feedback = details["engagement"]["feedbackComment"].string ?? details["feedback"].string {
            body += "<h2>Feedback</h2>" + safeMarkup(feedback)
        }
        if !media.isEmpty {
            body += "<h2>Attached files</h2><ul>"
            for (attachment, _) in media { body += "<li>" + escape(attachment.name) + "</li>" }
            body += "</ul><p>The following pages contain the attached photos and PDFs.</p>"
        }
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><style>
        body { font: 12pt -apple-system, Helvetica, sans-serif; color: #172126; }
        h1 { font-size: 23pt; margin-bottom: 6pt; } h2 { font-size: 17pt; margin-top: 24pt; }
        h3 { font-size: 13pt; } p { line-height: 1.45; } .meta { color: #52606a; }
        table { border-collapse: collapse; width: 100%; margin: 10pt 0; font-size: 10pt; }
        th, td { border: 1px solid #bdc7ce; padding: 7pt; text-align: left; vertical-align: top; }
        th { background: #edf2f4; } .selected { background: #e2f3ee; border: 2px solid #297d71; }
        tr { page-break-inside: avoid; } img { max-width: 100%; max-height: 650pt; object-fit: contain; }
        .media { page-break-inside: avoid; margin: 10pt 0; }
        </style></head><body>\(body)</body></html>
        """
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil); info.outputType = .general; info.jobName = assessment.displayTitle
        controller.printInfo = info
        controller.printingItem = nil; controller.printingItems = nil
        controller.printFormatter = nil
        controller.printingItem = try makePDF(html: html, media: media)
        controller.showsNumberOfCopies = false
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
           let window = scene.windows.first(where: \.isKeyWindow) {
            controller.present(from: CGRect(x: window.bounds.midX, y: 0, width: 1, height: 1), in: window, animated: true, completionHandler: nil)
        }
    }
    private final class A4Renderer: UIPrintPageRenderer {
        override var paperRect: CGRect { CGRect(x: 0, y: 0, width: 595.28, height: 841.89) }
        override var printableRect: CGRect { paperRect.insetBy(dx: 36, dy: 36) }
    }
    private static func makePDF(html: String, media: [(AssessmentAttachment, Data)]) throws -> Data {
        let renderer = A4Renderer()
        renderer.addPrintFormatter(UIMarkupTextPrintFormatter(markupText: html), startingAtPageAt: 0)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        let textData = UIGraphicsPDFRenderer(bounds: renderer.paperRect).pdfData { context in
            for page in 0..<renderer.numberOfPages {
                context.beginPage(); renderer.drawPage(at: page, in: renderer.paperRect)
            }
        }
        guard let output = PDFDocument(data: textData) else { throw SEQTAError.schema("Could not prepare assessment PDF") }
        for (attachment, data) in media {
            if let pdf = PDFDocument(data: data) {
                for index in 0..<pdf.pageCount {
                    if let page = pdf.page(at: index)?.copy() as? PDFPage { output.insert(page, at: output.pageCount) }
                }
            } else if let image = UIImage(data: data) {
                let pageData = UIGraphicsPDFRenderer(bounds: renderer.paperRect).pdfData { context in
                    context.beginPage()
                    (attachment.name as NSString).draw(in: CGRect(x: 36, y: 28, width: 523, height: 35), withAttributes: [.font: UIFont.systemFont(ofSize: 13, weight: .semibold)])
                    let area = CGRect(x: 36, y: 75, width: 523, height: 731)
                    let scale = min(area.width / image.size.width, area.height / image.size.height)
                    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    image.draw(in: CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height))
                }
                if let page = PDFDocument(data: pageData)?.page(at: 0)?.copy() as? PDFPage { output.insert(page, at: output.pageCount) }
            }
        }
        guard let data = output.dataRepresentation(), output.pageCount > 0 else { throw SEQTAError.schema("Could not prepare assessment PDF") }
        return data
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
