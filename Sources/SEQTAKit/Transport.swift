import Foundation

/// Injectable for integration tests and custom networking. Implementations must not forward credentials across origins.
public protocol SEQTATransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

private final class RedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // JSON API routes do not require redirects. In particular, never forward a login body to SSO or another host.
        completionHandler(nil)
    }
}

public final class URLSessionTransport: SEQTATransport, @unchecked Sendable {
    private let session: URLSession
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config, delegate: RedirectPolicy(), delegateQueue: nil)
    }
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SEQTAError.schema("Expected HTTP") }
        return (data, http)
    }
}

/// Sensitive session material. Persist through KeychainAccountStore rather than UserDefaults or logs.
public struct SavedAccount: Codable, Identifiable, Sendable {
    public let id: UUID
    public let school: School
    public let name: String
    public let username: String
    public let personID: String
    let sessionID: String
    public init(id: UUID = UUID(), school: School, person: Person, sessionID: String) {
        self.id = id; self.school = school; name = person.name; username = person.username
        personID = person.id; self.sessionID = sessionID
    }
}
