import Foundation

/// Local identities only: no notice text, report titles or student names. Each caller supplies an account/child scope.
public struct UnreadItems: Codable, Equatable, Sendable {
    private struct Collection: Codable, Equatable, Sendable {
        var known: Set<String> = []
        var read: Set<String> = []
        var baseline: Date?
    }
    private var collections: [String: Collection] = [:]
    public init() {}

    /// Replace a complete feed, or accumulate identities from a partial list.
    public mutating func record(_ ids: [String], in scope: String, replacing: Bool = false) {
        var collection = collections[scope] ?? Collection()
        if replacing { collection.known = Set(ids) } else { collection.known.formUnion(ids) }
        collections[scope] = collection
    }
    /// The first time this account began tracking. Kept across launches and shared by its report collections.
    public mutating func startTracking(in scope: String, at now: Date = Date()) -> Date {
        var collection = collections[scope] ?? Collection()
        if let baseline = collection.baseline { return baseline }
        collection.baseline = now
        collections[scope] = collection
        // Existing child collections belong to the period before tracking began (including old app versions).
        for key in Array(collections.keys) where key.hasPrefix(scope + "/") {
            guard var existing = collections[key] else { continue }
            existing.read.formUnion(existing.known)
            collections[key] = existing
        }
        return now
    }
    /// Only publications dated after the account baseline can be unread. Unknown dates don't create badges.
    /// `replacing: false` adds to the collection (a list other than the current one, such as an earlier day's news).
    public mutating func recordDated(_ items: [(id: String, date: Date?)], in scope: String, since baseline: Date, replacing: Bool = true) {
        record(items.map(\.id), in: scope, replacing: replacing)
        for item in items where item.date.map({ $0 <= baseline }) ?? true { markRead(item.id, in: scope) }
    }
    public mutating func didShow(_ ids: [String], in scope: String) {
        record(ids, in: scope, replacing: true)
        for id in ids { markRead(id, in: scope) }
    }
    public func count(in scope: String) -> Int {
        guard let collection = collections[scope] else { return 0 }
        return collection.known.subtracting(collection.read).count
    }
    public func isUnread(_ id: String, in scope: String) -> Bool {
        guard let collection = collections[scope] else { return false }
        return collection.known.contains(id) && !collection.read.contains(id)
    }
    public mutating func markRead(_ id: String, in scope: String) {
        var collection = collections[scope] ?? Collection()
        collection.read.insert(id)
        collections[scope] = collection
    }
    public mutating func remove(accountPrefix: String) {
        collections = collections.filter { !$0.key.hasPrefix(accountPrefix) }
    }
}
