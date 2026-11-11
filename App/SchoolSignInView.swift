import SwiftUI
import WebKit
import SEQTAKit

/// One fresh in-memory browser per login attempt. Password fields stay in the school's / identity provider's page.
@MainActor
final class SchoolLoginBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
    let webView: WKWebView
    private let schoolHost: String
    @Published var sessionVersion = 0
    @Published var host: String
    @Published var loading = true
    @Published var error: String?
    init(school: School) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
        host = school.url.host ?? ""
        schoolHost = school.url.host ?? ""
        super.init()
        webView.navigationDelegate = self; webView.uiDelegate = self
        webView.configuration.websiteDataStore.httpCookieStore.add(self)
        webView.load(URLRequest(url: school.url))
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loading = true; error = nil; host = webView.url?.host ?? host
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading = false; host = webView.url?.host ?? host
        if host == schoolHost { sessionVersion += 1 }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loading = false; self.error = error.localizedDescription
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loading = false; self.error = error.localizedDescription
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let scheme = action.request.url?.scheme?.lowercased()
        if scheme == "https" || action.request.url?.absoluteString == "about:blank" { decisionHandler(.allow) }
        else { error = "This sign-in needs another app. If it cannot complete here, use a Connect mobile app setup link."; decisionHandler(.cancel) }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if action.targetFrame == nil, action.request.url?.scheme == "https" { webView.load(action.request) }
        return nil
    }
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        if webView.url?.host == schoolHost { sessionVersion += 1 }
    }
    func sessionID(for school: School) async -> String? {
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        let host = school.url.host?.lowercased() ?? ""
        return cookies.filter { cookie in
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return cookie.name == "JSESSIONID" && (host == domain || host.hasSuffix("." + domain)) &&
                "/seqta/parent/".hasPrefix(cookie.path) && (cookie.expiresDate == nil || cookie.expiresDate! > Date())
        }.sorted { $0.path.count > $1.path.count }.first?.value
    }
}

struct SchoolSignInView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let school: School
    let connected: () -> Void
    @StateObject private var browser: SchoolLoginBrowser
    @State private var finishing = false
    @State private var error: String?
    init(school: School, connected: @escaping () -> Void) {
        self.school = school; self.connected = connected
        _browser = StateObject(wrappedValue: SchoolLoginBrowser(school: school))
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "lock.fill")
                    Text(browser.host).lineLimit(1).font(.caption)
                    Spacer()
                    if browser.loading { ProgressView().controlSize(.small).accessibilityIdentifier("school-login-progress") }
                }.padding(12).background(.bar)
                SchoolWebView(browser: browser)
                VStack(alignment: .leading, spacing: 6) {
                    Text(finishing ? "Connecting your school account…" : "Sign in through your school. We’ll open the reader automatically when sign-in completes.").font(.footnote)
                    if let message = error ?? browser.error { Text(message).font(.caption).foregroundStyle(.red).accessibilityIdentifier("school-login-error") }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.bar)
            }.navigationTitle("School sign-in").navigationBarTitleDisplayMode(.inline)
                .task(id: browser.sessionVersion) {
                    if browser.webView.url?.host == school.url.host { await finish(automatic: true) }
                }
                .interactiveDismissDisabled(finishing)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(finishing) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Continue to reader") { Task { await finish(automatic: false) } }.disabled(finishing)
                    }
                }
        }
    }
    @MainActor
    private func finish(automatic: Bool) async {
        guard !finishing else { return }
        finishing = true; error = nil
        defer { finishing = false }
        do {
            guard let session = await browser.sessionID(for: school) else { throw SEQTAError.authenticationRequired }
            try Task.checkCancellation()
            try await model.connect(school: school, sessionID: session)
            dismiss(); connected()
        } catch {
            if !automatic { self.error = "Complete your school’s sign-in first, then continue to the reader. \(error.localizedDescription)" }
        }
    }

}

private struct SchoolWebView: UIViewRepresentable {
    @ObservedObject var browser: SchoolLoginBrowser
    func makeCoordinator() -> SchoolLoginBrowser { browser }
    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ view: WKWebView, context: Context) { }
    static func dismantleUIView(_ view: WKWebView, coordinator: SchoolLoginBrowser) { view.configuration.websiteDataStore.httpCookieStore.remove(coordinator); view.stopLoading(); view.navigationDelegate = nil; view.uiDelegate = nil }
}
