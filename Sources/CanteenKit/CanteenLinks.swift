import Foundation

/// A school account's link to its canteen provider. Each case is a provider, holding that provider's session.
public enum CanteenConnection: Codable, Hashable, Sendable {
    case myStudentAccount(MSALink)
    public var msa: MSALink? { if case .myStudentAccount(let link) = self { return link }; return nil }
}

/// Saved school accounts' canteen links, keyed by the account's ID, in a Keychain item of their own (beside the
/// accounts, not inside them, so the LMS and canteen sides stay independent).
public struct CanteenLinkStore {
    private let item: KeychainItem
    public init(service: String = "au.disengage.accounts") { item = KeychainItem(service: service, account: "canteen-links") }

    /// Nil when nothing has ever been saved, which is when links from older builds need migrating.
    public func load() throws -> [UUID: CanteenConnection]? {
        guard let data = try item.load() else { return nil }
        let stored = try JSONDecoder().decode([String: CanteenConnection].self, from: data)
        return Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in UUID(uuidString: key).map { ($0, value) } })
    }
    public func save(_ links: [UUID: CanteenConnection]) throws {
        try item.save(JSONEncoder().encode(Dictionary(uniqueKeysWithValues: links.map { ($0.key.uuidString, $0.value) })))
    }
    public func removeAll() throws { try item.remove() }

    /// Links that builds 19 and 20 saved inside each account's JSON (`"canteen": {portal, cookies}`).
    public static func legacyLinks(fromAccountsJSON data: Data) -> [UUID: CanteenConnection] {
        struct Legacy: Decodable { let id: UUID; let canteen: MSALink? }
        guard let accounts = try? JSONDecoder().decode([Legacy].self, from: data) else { return [:] }
        return Dictionary(accounts.compactMap { account in account.canteen.map { (account.id, .myStudentAccount($0)) } }) { first, _ in first }
    }
}
