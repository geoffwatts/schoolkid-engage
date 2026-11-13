import SwiftUI
import PDFKit
import LMSKit

/// Media lives directly in the assessment's scroll, including every page of a PDF.
struct AttachmentCard: View {
    @EnvironmentObject private var model: AppModel
    let attachment: AssessmentAttachment
    /// Separates this file from the next; the last file on the page ends without a rule.
    var showsRule = true
    var onRotation: ((Data) -> Void)? = nil
    @State private var originalData: Data?
    @State private var data: Data?
    @State private var document: PDFDocument?
    @State private var image: UIImage?
    @State private var error: String?
    @State private var fullSize = false
    /// The enclosing list's scroll view, so a rotation can hold the page still (see `rotate()`).
    @State private var scroll = WeakScrollView()
    @State private var rotating = false
    @State private var quarterTurns = 0
    private var shareName: String {
        quarterTurns != 0 && image != nil ? (attachment.name as NSString).deletingPathExtension + ".png" : attachment.name
    }
    private var isOfficeDocument: Bool {
        attachment.mimeType.contains("word") || ["docx", "doc"].contains((attachment.name as NSString).pathExtension.lowercased())
    }
    private var canOpenFullSize: Bool { image != nil || document != nil || (data != nil && isOfficeDocument) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(attachment.name).readingStyle(.item).textSelection(.enabled)
                if canOpenFullSize {
                    Button { fullSize = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                        .buttonStyle(.borderless).accessibilityLabel("Open \(attachment.name) full size")
                }
                Spacer()
                if let data {
                    if image != nil || document != nil {
                        Button { Task { await rotate() } } label: {
                            if rotating { ProgressView() } else { Image(systemName: "rotate.right") }
                        }.buttonStyle(.borderless).disabled(rotating).accessibilityLabel("Rotate \(attachment.name) clockwise").accessibilityValue("\(quarterTurns * 90) degrees")
                    }
                    ShareFileButton(data: data, name: shareName, mimeType: image != nil && quarterTurns != 0 ? "image/png" : attachment.mimeType)
                }
            }.padding(.horizontal, 16)
            if let image {
                Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity)
                    .accessibilityLabel(attachment.name).openFullSizeOnTap { fullSize = true }
            } else if let document {
                ForEach(0..<document.pageCount, id: \.self) { page in
                    PDFPagePreview(document: document, index: page).id("\(page)-\(quarterTurns)")
                        .openFullSizeOnTap { fullSize = true }
                    if document.pageCount > 1 { Text("Page \(page + 1) of \(document.pageCount)").readingStyle(.meta).padding(.horizontal, 16) }
                }
            } else if let data, isOfficeDocument {
                OfficeDocumentInlinePreview(data: data, name: attachment.name)
                    .accessibilityLabel("Preview of \(attachment.name)")
                    .openFullSizeOnTap { fullSize = true }
            } else if let error {
                Text(error).foregroundStyle(.secondary).padding(.horizontal, 16)
                Button("Try again") { Task { await load() } }.padding(.horizontal, 16)
            } else if data != nil {
                Text("Preview unavailable. Use Share to open this file in another app.").readingStyle(.meta).padding(.horizontal, 16)
            } else { ProgressView("Opening attachment…").frame(maxWidth: .infinity).padding(.vertical, 30) }
            if showsRule { ReadingRule().padding(.horizontal, 16).padding(.top, 8) }
        }.padding(.vertical, 8).task { await load() }
            .background(TimetableScrollCapture { scroll.view = $0 })
            .sheet(isPresented: $fullSize) {
                NavigationStack {
                    AttachmentView(attachment: attachment, initialData: data)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { fullSize = false } } }
                }
            }
    }
    private func rotate() async {
        guard let data else { return }
        rotating = true; defer { rotating = false }
        let turns = (quarterTurns + 1) % 4
        let original = turns == 0 ? originalData : nil
        let value: Data?
        if let original { value = original }
        else { value = await Task.detached(priority: .userInitiated) { AttachmentRotation.clockwise(data: data) }.value }
        guard let value else { return }
        // Swapping in media with a new shape changes this row's height, and the list could jump to the top when it
        // re-measured. Nothing above this card changes, so restoring the offset keeps the card where it was.
        let savedOffset = scroll.view?.contentOffset
        self.data = value; quarterTurns = turns; onRotation?(value)
        if value.starts(with: Data("%PDF-".utf8)) { document = PDFDocument(data: value); image = nil }
        else { image = UIImage(data: value); document = nil }
        if let savedOffset { scroll.hold(savedOffset) }
    }
    private func load() async {
        error = nil
        do {
            let value: Data
            if model.isDemo { value = Demo.mediaData(attachment) }
            else if let client = model.client { value = try await client.attachmentData(attachment) }
            else { return }
            try Task.checkCancellation(); originalData = value; data = value
            if value.starts(with: Data("%PDF-".utf8)) { document = PDFDocument(data: value) }
            else { image = UIImage(data: value) }
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

private struct PDFPagePreview: View {
    let document: PDFDocument
    let index: Int
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity).background(.white).accessibilityLabel("PDF page \(index + 1)").accessibilityIdentifier("assessment-pdf-page-\(index)") }
            else { ProgressView().frame(maxWidth: .infinity, minHeight: 160) }
        }.task {
            image = document.page(at: index)?.thumbnail(of: CGSize(width: 1200, height: 1600), for: .mediaBox)
        }
    }
}

struct ShareFileButton: View {
    let data: Data
    let name: String
    let mimeType: String
    @State private var export: FileExport?
    @State private var error: String?
    var body: some View {
        Button {
            do {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Share-" + UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                var filename = (name as NSString).lastPathComponent
                if filename.isEmpty { filename = "Assessment attachment" }
                if (filename as NSString).pathExtension.isEmpty {
                    filename += data.starts(with: Data("%PDF-".utf8)) ? ".pdf" : data.starts(with: [0x89, 0x50, 0x4e, 0x47]) ? ".png" : mimeType.hasPrefix("image/") ? ".jpg" : ""
                }
                let url = directory.appendingPathComponent(filename)
                try data.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                export = FileExport(url: url)
            } catch { self.error = error.localizedDescription }
        } label: { Image(systemName: "square.and.arrow.up") }
            .buttonStyle(.borderless).accessibilityLabel("Share \(name)")
            .sheet(item: $export, onDismiss: { export = nil }) { file in FileShareSheet(url: file.url) }
            .alert("Couldn’t prepare file", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
}
private struct FileExport: Identifiable { var id: URL { url }; let url: URL }
private struct FileShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}

private extension View {
    /// Tapping an inline preview opens it full size; VoiceOver users get the same action via the button trait.
    func openFullSizeOnTap(_ action: @escaping () -> Void) -> some View {
        contentShape(Rectangle()).onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton).accessibilityHint("Opens full size")
    }
}

/// A weak reference to a list's scroll view that can pin its offset across the layout passes following a change.
final class WeakScrollView {
    weak var view: UIScrollView?
    func hold(_ offset: CGPoint) {
        // SwiftUI applies the change over the next few layout passes; restore after each so a late re-measure can't win.
        for delay in [0.0, 0.05, 0.15, 0.3] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                // Never fight the reader: once they scroll, their position wins.
                guard let view = self?.view, !view.isDragging, !view.isDecelerating else { return }
                view.layoutIfNeeded()
                let maxY = max(-view.adjustedContentInset.top, view.contentSize.height - view.bounds.height + view.adjustedContentInset.bottom)
                let target = CGPoint(x: offset.x, y: min(maxY, max(-view.adjustedContentInset.top, offset.y)))
                if abs(view.contentOffset.y - target.y) > 0.5 { view.setContentOffset(target, animated: false) }
            }
        }
    }
}

/// A small fanned pile of the assessment's media beside its title: a glance at what's attached, and a shortcut down to it.
struct AttachmentStack: View {
    @EnvironmentObject private var model: AppModel
    let attachments: [AssessmentAttachment]
    /// Media the reader has rotated below, so the pile matches what they'll find.
    var rotated: [String: Data] = [:]
    let action: () -> Void
    private static let cardSize = CGSize(width: 44, height: 56)
    private var shown: [AssessmentAttachment] { Array(attachments.prefix(3)) }
    var body: some View {
        Button(action: action) {
            ZStack {
                // The first file sits on top; the others fan out behind it.
                ForEach(Array(shown.enumerated().reversed()), id: \.element.id) { index, attachment in
                    AttachmentThumbnail(attachment: attachment, data: rotated[attachment.id])
                        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white, lineWidth: 2))
                        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                        .rotationEffect(.degrees(fan(index)), anchor: .bottom)
                        .offset(x: index == 1 ? 6 : (index == 2 ? -4 : 0))
                }
            }
            .frame(width: Self.cardSize.width + 18, height: Self.cardSize.height + 8)
            .overlay(alignment: .topTrailing) {
                if attachments.count > 1 {
                    Text("\(attachments.count)").font(.caption2.weight(.bold)).monospacedDigit()
                        .foregroundStyle(.white).padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                        .background(Capsule().fill(.tint)).offset(x: 4, y: -6)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PileButtonStyle())
        .accessibilityLabel(attachments.count == 1 ? "1 photo or document" : "\(attachments.count) photos and documents")
        .accessibilityHint("Scrolls down to them")
        .accessibilityIdentifier("assessment-attachment-stack")
    }
    private func fan(_ index: Int) -> Double { index == 0 ? -3 : (index == 1 ? 9 : -12) }
}

/// Lifts the pile a touch while pressed, like picking up a stack of prints.
private struct PileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.08 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

private struct AttachmentThumbnail: View {
    @EnvironmentObject private var model: AppModel
    let attachment: AssessmentAttachment
    var data: Data?
    @State private var image: UIImage?
    @State private var failed = false
    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else if failed { Image(systemName: "doc.text").font(.title3).foregroundStyle(.secondary) }
            else { ProgressView().controlSize(.mini) }
        }
        .task(id: data) { await load() }
    }
    private func load() async {
        let value: Data
        if let data { value = data }
        else if model.isDemo { value = Demo.mediaData(attachment) }
        else if let client = model.client, let fetched = try? await client.attachmentData(attachment) { value = fetched }
        else { failed = true; return }
        let size = CGSize(width: 132, height: 168)
        let thumbnail = await Task.detached(priority: .utility) { () -> UIImage? in
            if value.starts(with: Data("%PDF-".utf8)) {
                return PDFDocument(data: value)?.page(at: 0)?.thumbnail(of: size, for: .mediaBox)
            }
            return UIImage(data: value)?.preparingThumbnail(of: size)
        }.value
        guard !Task.isCancelled else { return }
        if let thumbnail { image = thumbnail } else { failed = true }
    }
}
