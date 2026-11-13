import Foundation

/// Stores all account metadata and session secrets in the app's private Keychain access group.
/// No passwords, analytics, cloud synchronization, or school content caches.
public struct KeychainAccountStore {
    private let item: KeychainItem
    public init(service: String = "au.disengage.accounts") {
        // The simulator fallback keeps its original file name, so debug sign-ins carry over.
        item = KeychainItem(service: service, account: "accounts", fileName: service + ".json")
    }
    public func load() throws -> [SavedAccount] {
        guard let data = try item.load() else { return [] }
        return try JSONDecoder().decode([SavedAccount].self, from: data)
    }
    /// The stored JSON as saved, for migrating fields that have moved out of `SavedAccount`.
    public func loadData() throws -> Data? { try item.load() }
    public func save(_ accounts: [SavedAccount]) throws { try item.save(JSONEncoder().encode(accounts)) }
    public func removeAll() throws { try item.remove() }
}
