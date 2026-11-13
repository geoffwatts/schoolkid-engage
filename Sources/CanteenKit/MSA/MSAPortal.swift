import Foundation

// My Student Account (MSA): a school canteen and student-account portal, often hosted by the school beside its LMS and
// signed in through the same identity provider. Pages are server-rendered HTML; the ordering screens call a small JSON
// API. Everything in MSA/ mirrors what the portal's own web client sends and reads.

/// The portal's base address, such as `https://canteen.example/wp/`. Pasting any page from the portal works: the path
/// is cut back to the part before the portal's own sections (Profile, Account, Order…). A host alone defaults to `/wp/`.
public struct MSAPortal: Codable, Hashable, Sendable {
    public let base: URL
    private static let sections: Set<String> = ["profile", "account", "order", "home", "creditcard", "recharge", "status", "signin-adfs"]
    public init(_ input: String) throws {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var c = URLComponents(string: text.contains("://") ? text : "https://" + text), c.scheme?.lowercased() == "https",
              let host = c.host, !host.isEmpty, c.user == nil, c.password == nil else { throw CanteenError.invalidPortalURL }
        let segments = c.path.split(separator: "/").map(String.init)
        let kept = segments.prefix { !Self.sections.contains($0.lowercased()) }
        c.scheme = "https"; c.host = host.lowercased(); c.query = nil; c.fragment = nil
        c.path = segments.isEmpty ? "/wp/" : "/" + kept.map { $0 + "/" }.joined()
        guard let url = c.url else { throw CanteenError.invalidPortalURL }
        base = url
    }
    public init(from decoder: Decoder) throws { try self.init(try decoder.singleValueContainer().decode(String.self)) }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(base.absoluteString) }
    public var host: String { base.host ?? "" }
    /// The portal's path, e.g. "/wp/", which its cookies are scoped to.
    public var path: String { base.path.hasSuffix("/") ? base.path : base.path + "/" }
    func url(_ path: String, query: [String: String] = [:]) -> URL {
        var c = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if path.hasSuffix("/"), !(c.path.hasSuffix("/")) { c.path += "/" }
        if !query.isEmpty { c.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        return c.url!
    }
    /// The page the portal opens on after sign-in; also where silent sign-in renewal starts.
    public var accountsPage: URL { url("Profile/Accounts") }
    public func rechargePage(account: Int) -> URL { url("Account/Recharge/\(account)") }
    /// Whether a page is part of the signed-in portal rather than its sign-in handshake.
    public func isSignedInPage(_ url: URL?) -> Bool {
        guard let url, url.host?.lowercased() == host, url.path.lowercased().hasPrefix(path.lowercased()) else { return false }
        let lower = url.path.lowercased()
        return !lower.contains("/profile/authenticate") && !lower.contains("/signin-adfs") && !lower.contains("/profile/signin")
    }
}

/// The portal session: the cookies its sign-in set for the portal's host. Sensitive; kept in `CanteenLinkStore`.
public struct MSALink: Codable, Hashable, Sendable {
    public let portal: MSAPortal
    public var cookies: [String: String]
    public init(portal: MSAPortal, cookies: [String: String]) { self.portal = portal; self.cookies = cookies }
    /// The cookies worth keeping from a browser: the portal's own, not the identity provider's one-off handshake ones.
    public static func portalCookies(_ cookies: [HTTPCookie], portal: MSAPortal, now: Date = Date()) -> [String: String] {
        var kept: [String: String] = [:]
        for cookie in cookies {
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard portal.host == domain || portal.host.hasSuffix("." + domain),
                  portal.path.lowercased().hasPrefix(cookie.path.lowercased()) || cookie.path.lowercased().hasPrefix(portal.path.lowercased()),
                  cookie.expiresDate.map({ $0 > now }) ?? true,
                  !cookie.name.hasPrefix(".AspNetCore.Correlation"), !cookie.name.hasPrefix(".AspNetCore.OpenIdConnect.Nonce") else { continue }
            kept[cookie.name] = cookie.value
        }
        return kept
    }
}
