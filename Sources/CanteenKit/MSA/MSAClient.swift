import Foundation

/// My Student Account's `CanteenService`: one portal session, for one saved school account. Sends only the portal's own
/// cookies, only to the portal's host, and never follows redirects (a redirect means the session has ended).
public actor MSAClient: CanteenService {
    public let portal: MSAPortal
    private let transport: any HTTPTransport
    private var cookies: [String: String]
    private let timeZone: TimeZone
    /// Bumped whenever the portal refreshes a cookie, so the caller can save the newer session.
    public private(set) var cookieVersion = 0

    public init(link: MSALink, transport: any HTTPTransport = URLSessionTransport(), timeZone: TimeZone = .current) {
        portal = link.portal; cookies = link.cookies; self.transport = transport; self.timeZone = timeZone
    }
    public var link: MSALink { MSALink(portal: portal, cookies: cookies) }
    public func replaceCookies(_ cookies: [String: String]) { self.cookies = cookies; cookieVersion += 1 }

    public func accounts() async throws -> [CanteenAccount] {
        let page = try await html("Profile/Accounts")
        let accounts = MSAPages.accounts(html: page)
        // A signed-in account list always has the sign-out form; without it this is some other page.
        if accounts.isEmpty && !page.contains("SignOut") { throw CanteenError.signInRequired }
        return accounts
    }
    public func menus(account: Int) async throws -> [CanteenMenuSummary] {
        MSAPages.menus(html: try await html("Account/Order/\(account)"), account: account)
    }
    public func menu(account: Int, menu: Int) async throws -> CanteenMenu {
        try CanteenMenu(msaJSON: try await json("order/getmenu/", query: ["id": String(account), "menuid": String(menu)]))
    }
    public func remaining(account: Int, menu: Int, day: CanteenDay) async throws -> [CanteenRemaining] {
        CanteenRemaining.list(try await json("order/getmenuitemsbydate/", query: ["id": String(account), "menuid": String(menu), "orderdate": day.slashed]))
    }
    public func verify(_ order: CanteenOrder, account: Int, menu: Int) async throws -> [String] {
        order.msaProblems(in: try await json("order/verify/", body: order.msaBody(account: account, menu: menu)))
    }
    public func place(_ order: CanteenOrder, account: Int, menu: Int) async throws -> [String] {
        // The portal's client checks the session first, so an expired one fails before anything is submitted.
        _ = try await send(request("status/", query: [:], accept: "application/json, text/plain, */*"))
        let receipt = try await json("order/save/", body: order.msaBody(account: account, menu: menu))
        let numbers = (receipt["orderReceipts"].array ?? []).compactMap { $0["orderNumber"].string }.filter { !$0.isEmpty }
        guard !numbers.isEmpty else { throw CanteenError.schema("no order number in the receipt") }
        return numbers
    }
    public func transactions(account: Int) async throws -> [CanteenTransaction] {
        MSAPages.transactions(html: try await html("Account/History/\(account)"), timeZone: timeZone)
    }
    public func orderHistory(account: Int) async throws -> [CanteenPastOrder] {
        MSAPages.orderHistory(html: try await html("Account/OrderHistory/\(account)"))
    }

    // MARK: Requests

    private func request(_ path: String, query: [String: String], accept: String) -> URLRequest {
        var query = query
        // The portal's client adds this to every API request so no cache answers it.
        if !path.hasPrefix("Profile/") && !path.hasPrefix("Account/") { query["noCache"] = String(Int(Date().timeIntervalSince1970 * 1000)) }
        var request = URLRequest(url: portal.url(path, query: query))
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        if !cookies.isEmpty {
            request.setValue(cookies.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        }
        return request
    }
    private func html(_ path: String) async throws -> String {
        let (data, _) = try await send(request(path, query: [:], accept: "text/html"))
        guard let page = String(data: data, encoding: .utf8) else { throw CanteenError.schema("a page that isn't text") }
        if page.contains("login.microsoftonline.com") || page.contains("/Profile/Authenticate") && !page.contains("SignOut") {
            throw CanteenError.signInRequired
        }
        return page
    }
    private func json(_ path: String, query: [String: String] = [:], body: JSONValue? = nil) async throws -> JSONValue {
        var request = request(path, query: query, accept: "application/json, text/plain, */*")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json;charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, _) = try await send(request)
        do { return try JSONDecoder().decode(JSONValue.self, from: data) }
        catch {
            // An HTML page where JSON was expected is the portal's sign-in screen.
            if String(data: data.prefix(512), encoding: .utf8)?.contains("<") == true { throw CanteenError.signInRequired }
            throw CanteenError.schema("unreadable JSON")
        }
    }
    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await transport.send(request)
        absorbCookies(from: response)
        switch response.statusCode {
        case 200..<300: return (data, response)
        case 301, 302, 303, 307, 308, 401, 403: throw CanteenError.signInRequired
        default:
            // The portal explains refusals (a closed day, a sold-out item) as plain text or a JSON string.
            if let message = String(data: data.prefix(500), encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\" \n")),
               !message.isEmpty, !message.contains("<") {
                throw CanteenError.rejected(message)
            }
            throw CanteenError.server(response.statusCode)
        }
    }
    /// Keeps the portal's refreshed cookies (sliding sign-in expiry), ignoring any set for another host.
    private func absorbCookies(from response: HTTPURLResponse) {
        guard let url = response.url, url.host?.lowercased() == portal.host else { return }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { if let k = $1.key as? String, let v = $1.value as? String { $0[k] = v } }
        let fresh = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
        var changed = false
        for cookie in fresh where !cookie.name.hasPrefix(".AspNetCore.Correlation") {
            if let expires = cookie.expiresDate, expires <= Date() {
                if cookies.removeValue(forKey: cookie.name) != nil { changed = true }
            } else if cookies[cookie.name] != cookie.value {
                cookies[cookie.name] = cookie.value; changed = true
            }
        }
        if changed { cookieVersion += 1 }
    }
}
