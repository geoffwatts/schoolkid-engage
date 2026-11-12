import SwiftUI
import SEQTAKit
import PDFKit
import ImageIO

/// School feedback often contains marking tables. Render their rows and cells natively rather than flattening them.
struct FeedbackView: View {
    let html: String
    private enum Block { case text(String), table([[String]]) }
    private var blocks: [Block] {
        let source = html as NSString
        guard let expression = try? NSRegularExpression(pattern: "(?is)<table\\b[^>]*>.*?</table>") else { return [.text(html)] }
        var result: [Block] = []; var end = 0
        for table in expression.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            if table.range.location > end { result.append(.text(source.substring(with: NSRange(location: end, length: table.range.location - end)))) }
            let tableHTML = source.substring(with: table.range) as NSString
            let rows = (try? NSRegularExpression(pattern: "(?is)<tr\\b[^>]*>(.*?)</tr>"))?.matches(in: tableHTML as String, range: NSRange(location: 0, length: tableHTML.length)) ?? []
            let cells = rows.map { row -> [String] in
                let rowHTML = tableHTML.substring(with: row.range(at: 1)) as NSString
                let matches = (try? NSRegularExpression(pattern: "(?is)<t[dh]\\b[^>]*>(.*?)</t[dh]>"))?.matches(in: rowHTML as String, range: NSRange(location: 0, length: rowHTML.length)) ?? []
                return matches.map { rowHTML.substring(with: $0.range(at: 1)) }
            }
            result.append(.table(cells)); end = NSMaxRange(table.range)
        }
        if end < source.length { result.append(.text(source.substring(from: end))) }
        return result.isEmpty ? [.text(html)] : result
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let value): ReadableHTML(html: value)
                case .table(let rows):
                    TableScroll {
                        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, cells in
                                GridRow {
                                    ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                                        ReadableHTML(html: cell).fontWeight(rowIndex == 0 ? .semibold : .regular)
                                            .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
                                            .padding(12).frame(width: 250, alignment: .topLeading)
                                            .frame(maxHeight: .infinity, alignment: .topLeading)
                            .background(rowIndex == 0 ? Color.teal.opacity(0.12) : Color(.systemBackground))
                                            .overlay(Rectangle().stroke(Color.secondary.opacity(0.25), lineWidth: 0.5))
                                    }
                                }
                            }
                        }.fixedSize(horizontal: true, vertical: true) // rows hug their tallest cell rather than filling offered height
                    }.accessibilityLabel("Feedback marking table")
                }
            }
        }
    }
}

struct GradingView: View {
    let criteria: [JSONValue]
    private var hasGrades: Bool { criteria.contains { $0["results"]["grade"].string != nil } }
    private var hasScores: Bool { criteria.contains { $0["results"]["score"].string != nil } }
    private var hasPercentages: Bool { criteria.contains { $0["results"]["percentage"].string != nil } }
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // A table fitted to the page, long criteria wrapping; at accessibility text sizes the columns can't fit,
            // so each criterion gets its own line with its marks beneath.
            // A labelled group, not one element: VoiceOver (and UI tests) still reach each criterion and mark inside.
            Group { if typeSize.isAccessibilitySize { stackedMarks } else { marksTable } }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("SEQTA grades")
            ForEach(Array(criteria.enumerated()), id: \.offset) { _, criterion in
                if let lines = criterion["rubric"]["lines"].array, !lines.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        // Three aligned columns: criterion, mark, awarded descriptor. A Grid sizes the mark column to its
                        // widest entry and right-aligns it, so "5" and "10" line up and every descriptor starts together.
                        Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 8) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                let selectedID = criterion["rubricScore"][line["id"].string ?? ""]["id"].string
                                let selected = (line["descriptors"].array ?? []).first { $0["id"].string == selectedID && selectedID != nil }
                                let mark = selected.flatMap { RubricPresentation.mark(for: $0, mode: criterion["rubric"]["mode"].string ?? "numeric") }
                                GridRow {
                                    Text(line["title"].string ?? "Criterion").readingStyle(.meta).frame(width: 100, alignment: .leading)
                                    Text(mark ?? "").font(.footnote.bold()).foregroundStyle(.teal).monospacedDigit()
                                        .gridColumnAlignment(.trailing)
                                    if let selected {
                                        ReadableHTML(html: selected["content"].string ?? "", font: .footnote, selectable: false).lineLimit(2)
                                    } else { Text("Not marked").readingStyle(.meta) }
                                }
                                // One VoiceOver element per rubric line ("Evidence, 5, Develops clear…"), at a full row height.
                                .frame(minHeight: 44, alignment: .topLeading)
                                .accessibilityElement(children: .combine)
                            }
                        }
                        DisclosureGroup {
                            CompactRubricGrid(criterion: criterion, lines: lines).padding(.top, 6)
                        } label: { Text("Full rubric").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle()) }.font(.footnote)
                    }
                }
                if let text = criterion["engagement"]["feedbackComment"].string ?? criterion["feedback"].string, !text.isEmpty {
                    Text(criterion["label"].string ?? "Criterion feedback").readingStyle(.item)
                    FeedbackView(html: text)
                }
            }
        }
    }

    private func grade(_ c: JSONValue) -> String? { c["results"]["grade"].string }
    private func score(_ c: JSONValue) -> String { ScorePresentation.format(c["results"]["score"].string ?? "—") }
    private func target(_ c: JSONValue) -> String { ScorePresentation.format(c["results"]["target"].string ?? c["target"].string ?? "—") }
    private func percentage(_ c: JSONValue) -> String { c["results"]["percentage"].string.map { ScorePresentation.format($0) + "%" } ?? "—" }

    private var stackedMarks: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(criteria.enumerated()), id: \.offset) { _, criterion in
                VStack(alignment: .leading, spacing: 4) {
                    Text(criterion["label"].string ?? "Criterion").foregroundStyle(.tint)
                        .fixedSize(horizontal: false, vertical: true)
                    let marks = [hasGrades ? grade(criterion) ?? "—" : nil, hasScores ? "\(score(criterion)) / \(target(criterion))" : nil,
                                 hasPercentages ? percentage(criterion) : nil].compactMap { $0 }
                    if marks.isEmpty { Text("Not released").foregroundStyle(.secondary) }
                    else { Text(marks.joined(separator: " · ")).monospacedDigit() }
                }.accessibilityElement(children: .combine)
            }
        }.padding(.vertical, 4)
    }

    private var marksTable: some View {
        // Marks sit level with the first line of a criterion that wraps.
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 12) {
            GridRow {
                Text("Criterion").readingStyle(.meta)
                if hasGrades { Text("Grade").readingStyle(.meta).lineLimit(1).fixedSize() }
                if hasScores {
                    Text("Score").readingStyle(.meta).lineLimit(1).fixedSize().gridColumnAlignment(.trailing)
                    Text("Out of").readingStyle(.meta).lineLimit(1).fixedSize().gridColumnAlignment(.trailing)
                }
                if hasPercentages { Text("%").readingStyle(.meta).lineLimit(1).fixedSize().gridColumnAlignment(.trailing) }
                if !hasGrades && !hasScores && !hasPercentages { Text("Result").readingStyle(.meta) }
            }
            Divider().gridCellUnsizedAxes(.horizontal)
            ForEach(Array(criteria.enumerated()), id: \.offset) { _, criterion in
                GridRow {
                    // The criterion is the row's heading, so it takes the accent colour like the marks. It takes the
                    // width the marks leave and wraps, so the table always fits the page.
                    Text(criterion["label"].string ?? "Criterion").foregroundStyle(.tint)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if hasGrades { Text(criterion["results"]["grade"].string ?? "—").bold().foregroundStyle(.teal).lineLimit(1).fixedSize() }
                    if hasScores {
                        Text(ScorePresentation.format(criterion["results"]["score"].string ?? "—")).monospacedDigit().lineLimit(1).fixedSize()
                        Text(ScorePresentation.format(criterion["results"]["target"].string ?? criterion["target"].string ?? "—")).monospacedDigit().lineLimit(1).fixedSize()
                    }
                    if hasPercentages {
                        Text(criterion["results"]["percentage"].string.map { ScorePresentation.format($0) + "%" } ?? "—").monospacedDigit().lineLimit(1).fixedSize()
                    }
                    if !hasGrades && !hasScores && !hasPercentages { Text("Not released").foregroundStyle(.secondary) }
                }
            }
        }.padding(.vertical, 4)
    }
}

private struct CompactRubricGrid: View {
    let criterion: JSONValue
    let lines: [JSONValue]
    var body: some View {
        TableScroll {
            Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    GridRow {
                        Text(line["title"].string ?? "Criterion").font(.caption2.bold()).padding(6).frame(width: 90, alignment: .topLeading)
                            .background(.teal.opacity(0.08)).overlay(Rectangle().stroke(.secondary.opacity(0.25), lineWidth: 0.5))
                        ForEach(Array(RubricPresentation.orderedDescriptors(in: line, mode: criterion["rubric"]["mode"].string ?? "numeric").enumerated()), id: \.offset) { _, descriptor in
                            let selected = descriptor["id"].string != nil && descriptor["id"].string == criterion["rubricScore"][line["id"].string ?? ""]["id"].string
                            VStack(alignment: .leading, spacing: 4) {
                                if let mark = RubricPresentation.mark(for: descriptor, mode: criterion["rubric"]["mode"].string ?? "numeric") { Text(mark).font(.caption.bold()) }
                                ReadableHTML(html: descriptor["content"].string ?? "", font: .caption2)
                            }.padding(6).frame(width: 115, alignment: .topLeading)
                                .background(selected ? Color.teal.opacity(0.15) : Color(.systemBackground))
                                .overlay(Rectangle().stroke(selected ? Color.teal : Color.secondary.opacity(0.25), lineWidth: selected ? 1.5 : 0.5))
                                .accessibilityLabel(selected ? "Awarded descriptor" : "Rubric descriptor")
                        }
                    }
                }
            }.fixedSize(horizontal: true, vertical: false)
        }
    }
}

struct AttachmentRow: View {
    @EnvironmentObject private var model: AppModel
    let attachment: AssessmentAttachment
    @State private var thumbnail: UIImage?
    var body: some View {
        HStack(spacing: 14) {
            if let thumbnail { Image(uiImage: thumbnail).resizable().scaledToFill().frame(width: 72, height: 72).clipped() }
            else { Image(systemName: attachment.mimeType.contains("pdf") ? "doc.richtext" : "photo").font(.title).frame(width: 60, height: 60).foregroundStyle(.teal) }
            VStack(alignment: .leading, spacing: 5) {
                Text(attachment.name).readingStyle(.item)
                Text(attachment.mimeType.contains("pdf") ? "Open PDF" : "Open photo or file").readingStyle(.meta)
            }
        }.padding(.vertical, 6).task {
            if attachment.mimeType.hasPrefix("image/") {
                let data = model.isDemo ? Demo.mediaData(attachment) : try? await model.client?.attachmentData(attachment)
                if let data, !Task.isCancelled { if let source = CGImageSourceCreateWithData(data as CFData, nil),
                       let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 144, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) {
                        thumbnail = UIImage(cgImage: image)
                    } }
            }
        }
    }
}

struct AttachmentView: View {
    @EnvironmentObject private var model: AppModel
    let attachment: AssessmentAttachment
    var initialData: Data? = nil
    @State private var rotating = false
    @State private var quarterTurns = 0
    @State private var data: Data?
    @State private var error: String?
    var body: some View {
        Group {
            if let data {
                if data.starts(with: Data("%PDF-".utf8)), PDFDocument(data: data) != nil { PDFReader(data: data).id(quarterTurns) }
                else if let image = UIImage(data: data) { ZoomablePhoto(image: image).id(quarterTurns) }
                else if attachment.mimeType.contains("word") || ["docx", "doc"].contains((attachment.name as NSString).pathExtension.lowercased()) { OfficeDocumentPreview(data: data, name: attachment.name) }
                else { ContentUnavailableView("File format not supported", systemImage: "doc", description: Text("Photos, PDFs and Word documents can be viewed here.")) }
            } else if let error { ContentUnavailableView("Couldn’t open attachment", systemImage: "doc.badge.ellipsis", description: Text(error)) }
            else { ProgressView("Opening attachment…") }
        }.toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let data {
                    if data.starts(with: Data("%PDF-".utf8)) || UIImage(data: data) != nil {
                        Button { Task { await rotate() } } label: {
                            Label("Rotate clockwise", systemImage: "rotate.right")
                        }.disabled(rotating).accessibilityLabel("Rotate clockwise").accessibilityValue("\(quarterTurns * 90) degrees")
                    }
                    ShareFileButton(data: data, name: data.starts(with: [0x89, 0x50, 0x4e, 0x47]) ? (attachment.name as NSString).deletingPathExtension + ".png" : attachment.name, mimeType: data.starts(with: Data("%PDF-".utf8)) ? "application/pdf" : data.starts(with: [0x89, 0x50, 0x4e, 0x47]) ? "image/png" : attachment.mimeType)
                }
            }
        }.navigationTitle(attachment.name).navigationBarTitleDisplayMode(.inline)
            .task {
            do {
                let value: Data?
                if let initialData { value = initialData }
                else if model.isDemo { value = Demo.mediaData(attachment) }
                else { value = try await model.client?.attachmentData(attachment) }
                try Task.checkCancellation(); data = value
            }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private func rotate() async {
        guard let data else { return }
        rotating = true; defer { rotating = false }
        if let value = await Task.detached(priority: .userInitiated, operation: { AttachmentRotation.clockwise(data: data) }).value {
            self.data = value; quarterTurns = (quarterTurns + 1) % 4
        }
    }

}

private struct ZoomablePhoto: UIViewRepresentable {
    let image: UIImage
    final class Coordinator: NSObject, UIScrollViewDelegate {
        let imageView = UIImageView()
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIScrollView {
        let view = UIScrollView(); view.delegate = context.coordinator
        view.minimumZoomScale = 1; view.maximumZoomScale = 5; view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let imageView = context.coordinator.imageView; imageView.image = image; imageView.contentMode = .scaleAspectFit
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]; imageView.frame = view.bounds
        view.addSubview(imageView); return view
    }
    func updateUIView(_ view: UIScrollView, context: Context) { if view.zoomScale == 1 { context.coordinator.imageView.frame = view.bounds } }
}

/// A sideways-scrolling table. iOS 26 softens the edges of scrolling content, which fades table text where it meets
/// the screen edge and drops it below readable contrast, so tables turn that effect off.
struct TableScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        if #available(iOS 26, *) { ScrollView(.horizontal) { content() }.scrollEdgeEffectHidden(true, for: .horizontal) }
        else { ScrollView(.horizontal) { content() } }
    }
}
