import SwiftUI
import WebKit
import LMSKit
import CanteenKit

/// A browser on a lunch-order portal, in the school account's own website data store. The identity provider's pages
/// handle any sign-in; the app only reads back the portal's own cookies once a signed-in portal page loads.
@MainActor
final class CanteenBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    let portal: MSAPortal
    @Published var host = ""
    @Published var loading = true
    @Published var error: String?
    /// Bumped each time a signed-in portal page finishes loading.
    @Published var signedInVersion = 0
    private(set) var lastFinished = Date()
    private var loadTimeout: Task<Void, Never>?
    private let formHints: Bool
    private var focusing: Task<Void, Never>?

    /// `formHints` for pages where the user fills in the portal's forms (topping up): see `CanteenFormHints`.
    init(portal: MSAPortal, storeID: UUID, formHints: Bool = false) {
        self.portal = portal; self.formHints = formHints
        host = portal.host
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: storeID)
        if formHints { config.userContentController.addUserScript(CanteenFormHints.script(portal: portal)) }
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self; webView.uiDelegate = self
    }
    /// Puts the saved portal session into the browser first, so a signed-in page opens without a sign-in round trip.
    func open(_ url: URL, cookies: [String: String] = [:]) async {
        for (name, value) in cookies {
            if let cookie = HTTPCookie(properties: [.name: name, .value: value, .domain: portal.host, .path: portal.path, .secure: "TRUE"]) {
                await webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
            }
        }
        beginLoading()
        webView.load(URLRequest(url: url, timeoutInterval: 30))
    }
    func portalCookies() async -> [String: String] {
        MSALink.portalCookies(await webView.configuration.websiteDataStore.httpCookieStore.allCookies(), portal: portal)
    }
    var isOnSignedInPage: Bool { portal.isSignedInPage(webView.url) }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        focusing?.cancel()
        beginLoading(); host = webView.url?.host ?? host
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadTimeout?.cancel()
        loading = false; host = webView.url?.host ?? host; lastFinished = Date()
        if isOnSignedInPage { signedInVersion += 1 }
        if formHints && isOnSignedInPage { focusFirstField() }
    }

    /// Puts the cursor in the field the page is for, scrolled into view: the amount on Recharge, the card number on
    /// Process Payment (drawn by the page's script after load, so this retries for a few seconds). Done through
    /// `evaluateJavaScript`, since a page's own `autofocus` doesn't bring up the keyboard in a web view.
    private func focusFirstField() {
        focusing?.cancel()
        focusing = Task { @MainActor [weak self] in
            for _ in 0..<20 {
                guard let self, !Task.isCancelled else { return }
                if let done = try? await self.webView.evaluateJavaScript(CanteenFormHints.focusScript) as? Bool, done { return }
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        loadTimeout?.cancel()
        loading = false; lastFinished = Date(); self.error = error.localizedDescription
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        loadTimeout?.cancel()
        loading = false; lastFinished = Date(); self.error = error.localizedDescription
    }
    private func beginLoading() {
        loadTimeout?.cancel()
        loading = true; error = nil
        loadTimeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self else { return }
            self.webView.stopLoading()
            self.loading = false
            self.error = "The sign-in page took too long to load. Check your connection and try again."
        }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loadTimeout?.cancel()
        loading = false
        error = "The sign-in page closed unexpectedly. Try loading it again."
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let scheme = action.request.url?.scheme?.lowercased()
        let allowed = scheme == "https" || action.request.url?.absoluteString == "about:blank"
        if !allowed {
            loadTimeout?.cancel(); loading = false
            error = "This sign-in tried to open an unsupported address. Try again or check the MSA website address."
        }
        decisionHandler(allowed ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if action.targetFrame == nil, action.request.url?.scheme == "https" { webView.load(action.request) }
        return nil
    }

    /// Signs the portal in again without showing anything: opens it in the account's data store, where the identity
    /// provider still knows the parent, and waits for a signed-in page. Nil if the provider wants the user (a password,
    /// a second factor, or a sign-in that has itself expired).
    static func renew(portal: MSAPortal, storeID: UUID, timeout: TimeInterval = 25) async -> [String: String]? {
        let browser = CanteenBrowser(portal: portal, storeID: storeID)
        await browser.open(portal.accountsPage)
        let started = Date()
        while Date().timeIntervalSince(started) < timeout {
            try? await Task.sleep(for: .milliseconds(400))
            if !browser.loading && browser.isOnSignedInPage {
                let cookies = await browser.portalCookies()
                return cookies.isEmpty ? nil : cookies
            }
            // Settled on the identity provider's page for a few seconds: it's waiting for the user.
            if !browser.loading, browser.host != portal.host, Date().timeIntervalSince(browser.lastFinished) > 4 { return nil }
        }
        return nil
    }
}

private struct CanteenWebView: UIViewRepresentable {
    @ObservedObject var browser: CanteenBrowser
    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ view: WKWebView, context: Context) { }
    static func dismantleUIView(_ view: WKWebView, coordinator: ()) { view.stopLoading() }
}

/// Links (or signs in again to) the lunch-order portal for the current school account.
struct CanteenSignInView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var address: String
    @State private var browser: CanteenBrowser?
    @State private var storeID: UUID?
    @State private var finishing = false
    @State private var error: String?
    init(portal: MSAPortal? = nil) { _address = State(initialValue: portal?.base.absoluteString ?? "") }
    var body: some View {
        NavigationStack {
            Group {
                if let browser {
                    CanteenLoginContent(browser: browser, finishing: finishing, error: error,
                                        finish: { await finish(browser) }, changeAddress: {
                        browser.webView.stopLoading()
                        self.browser = nil
                        error = nil
                    })
                } else {
                    Form {
                        Section {
                            TextField("msa.yourschool.edu.au", text: $address).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        } header: { Text("My Student Account address") } footer: {
                            Text("Enter your school’s My Student Account website, such as msa.yourschool.edu.au, or paste the address of any page from it.")
                        }
                        Section {
                            Button("Continue") { start() }.disabled((try? MSAPortal(address)) == nil)
                        }
                    }
                }
            }
            .navigationTitle("Lunch orders").navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(finishing)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(finishing) } }
            .onDisappear {
                if let storeID { model.webStoresInUse.remove(storeID) }
                model.removeUnusedWebStores()
            }
        }
    }
    private func start() {
        guard let portal = try? MSAPortal(address) else { return }
        // The school account's own data store, so the school's sign-in carries over; a new one if it has none yet.
        let id = model.account?.webStoreID ?? UUID()
        storeID = id; model.webStoresInUse.insert(id)
        let browser = CanteenBrowser(portal: portal, storeID: id)
        self.browser = browser
    }
    private func finish(_ browser: CanteenBrowser) async {
        guard !finishing, let storeID else { return }
        finishing = true; error = nil
        defer { finishing = false }
        do {
            let cookies = await browser.portalCookies()
            guard !cookies.isEmpty else { throw CanteenError.signInRequired }
            try await model.linkCanteen(portal: browser.portal, cookies: cookies, storeID: storeID)
            dismiss()
        } catch {
            self.error = "This page isn’t the My Student Account list yet. \(error.localizedDescription)"
        }
    }
}

/// Observe the browser itself: storing it in @State in the parent doesn't subscribe to its published changes.
private struct CanteenLoginContent: View {
    @ObservedObject var browser: CanteenBrowser
    let finishing: Bool
    let error: String?
    let finish: () async -> Void
    let changeAddress: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "lock.fill")
                Text(browser.host).lineLimit(1).font(.caption)
                Spacer()
                if browser.loading || finishing {
                    ProgressView().controlSize(.small).accessibilityIdentifier("canteen-login-progress")
                }
            }.padding(12).background(.bar)
            CanteenWebView(browser: browser)
            VStack(alignment: .leading, spacing: 6) {
                Text(finishing ? "Connecting lunch orders…" : "Sign in with your school account if asked. Lunch orders connect as soon as the portal opens.").font(.footnote)
                if let message = error ?? browser.error {
                    Text(message).font(.caption).foregroundStyle(.red).accessibilityIdentifier("canteen-login-error")
                }
                HStack {
                    Button("Try again") { Task { await browser.open(browser.portal.accountsPage) } }
                    Spacer()
                    Button("Change address", action: changeAddress)
                }.font(.footnote).disabled(finishing)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.bar)
        }
        .task { await browser.open(browser.portal.accountsPage) }
        .task(id: browser.signedInVersion) { if browser.signedInVersion > 0 { await finish() } }
    }
}

/// A portal page shown as the portal draws it, for what the app leaves to the portal: topping up with a card.
struct CanteenPageView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let title: String
    let url: URL?
    /// What to do on the page, shown above it (e.g. the amount to top up).
    var note: String? = nil
    @State private var browser: CanteenBrowser?
    var body: some View {
        NavigationStack {
            Group {
                if let browser {
                    CanteenPortalPageContent(browser: browser, note: note)
                } else if model.isDemo {
                    ContentUnavailableView("Top up on the canteen’s page", systemImage: "creditcard",
                                           description: Text([note, "With a real account, this opens My Student Account’s own top-up page. Card details go to the canteen, never to this app."].compactMap { $0 }.joined(separator: "\n\n")))
                } else { ContentUnavailableView("Lunch orders aren’t connected", systemImage: "fork.knife") }
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task {
            guard browser == nil, let url, let account = model.account, let link = model.canteenLink, let storeID = account.webStoreID else { return }
            model.webStoresInUse.insert(storeID)
            let browser = CanteenBrowser(portal: link.portal, storeID: storeID, formHints: true)
            self.browser = browser
            await browser.open(url, cookies: link.cookies)
        }
        .onDisappear {
            if let storeID = model.account?.webStoreID { model.webStoresInUse.remove(storeID) }
            Task { await model.refreshLunch() }
        }
    }
}

/// Top-up pages need to observe navigation too, so their loading indicator clears when WebKit finishes.
private struct CanteenPortalPageContent: View {
    @ObservedObject var browser: CanteenBrowser
    let note: String?
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "lock.fill")
                Text(browser.host).lineLimit(1).font(.caption)
                Spacer()
                if browser.loading { ProgressView().controlSize(.small) }
            }.padding(12).background(.bar)
            if let note {
                Label(note, systemImage: "info.circle").font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.bottom, 10).background(.bar)
            }
            CanteenWebView(browser: browser)
            if let error = browser.error {
                Text(error).font(.caption).foregroundStyle(.red).padding(12)
            }
        }
    }
}
