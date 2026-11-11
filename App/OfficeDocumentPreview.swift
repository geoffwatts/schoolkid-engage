import SwiftUI
import QuickLook
import WebKit

/// Apple's local Office-document renderer; documents are never uploaded to a conversion service.
struct OfficeDocumentPreview: UIViewControllerRepresentable {
    let data: Data
    let name: String
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let directory: URL
        let url: URL
        init(data: Data, name: String) {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("DocumentPreview-" + UUID().uuidString, isDirectory: true)
            var filename = (name as NSString).lastPathComponent
            if (filename as NSString).pathExtension.isEmpty { filename += ".docx" }
            url = directory.appendingPathComponent(filename)
            super.init()
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try? data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
    func makeCoordinator() -> Coordinator { Coordinator(data: data, name: name) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController(); controller.dataSource = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) { }
    static func dismantleUIViewController(_ controller: QLPreviewController, coordinator: Coordinator) {
        controller.dataSource = nil
        try? FileManager.default.removeItem(at: coordinator.directory)
    }
}

/// An inline, non-interactive render of an Office document for the reading layout.
///
/// The live QuickLook preview renders in a separate process and keeps taking trackpad and scroll-wheel events even with
/// hit testing disabled, so it's reserved for full screen. WebKit renders Word files locally too, but its views live in
/// this app, so turning off interaction hands every scroll back to the page. JavaScript is off; nothing is fetched.
struct OfficeDocumentInlinePreview: View {
    let data: Data
    let name: String
    /// Sized once to the rendered document's height, so short files don't leave a blank page. It starts small because
    /// WebKit reports at least the view's own height as the content height.
    @State private var height: CGFloat = 120
    var body: some View {
        OfficeDocumentWebView(data: data, name: name) { value in
            height = min(max(value, 120), 6000)
        }.frame(height: height)
    }
}

private struct OfficeDocumentWebView: UIViewRepresentable {
    let data: Data
    let name: String
    var onContentHeight: (CGFloat) -> Void
    /// Measures the document once after it loads. Following every content-size change fed back into the frame
    /// (resizing changed the reported size, which resized again), so the app never went idle.
    final class Coordinator: NSObject, WKNavigationDelegate {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DocumentInline-" + UUID().uuidString, isDirectory: true)
        var onContentHeight: (CGFloat) -> Void = { _ in }
        private var measured = false
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !measured else { return }
            measured = true
            // Give WebKit a moment to lay out the converted document before reading its size.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak webView, onContentHeight] in
                guard let height = webView?.scrollView.contentSize.height, height > 0 else { return }
                onContentHeight(height)
            }
        }
        deinit { try? FileManager.default.removeItem(at: directory) }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isUserInteractionEnabled = false
        view.scrollView.isScrollEnabled = false
        view.isOpaque = false; view.backgroundColor = .white
        view.accessibilityElementsHidden = true
        context.coordinator.onContentHeight = onContentHeight
        view.navigationDelegate = context.coordinator
        var filename = (name as NSString).lastPathComponent
        if (filename as NSString).pathExtension.isEmpty { filename += ".docx" }
        let directory = context.coordinator.directory, url = directory.appendingPathComponent(filename)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try data.write(to: url, options: .atomic)
            view.loadFileURL(url, allowingReadAccessTo: directory)
        } catch { }
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) { }
}
