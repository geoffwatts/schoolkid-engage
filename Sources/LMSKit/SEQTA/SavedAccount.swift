import Foundation

/// A saved SEQTA sign-in. Sensitive session material: persist through KeychainAccountStore rather than UserDefaults or
/// logs. Services linked to the account (such as lunch orders) are stored separately, keyed by `id`.
public struct SavedAccount: Codable, Identifiable, Sendable {
    public let id: UUID
    public let school: School
    public let name: String
    public let username: String
    public let personID: String
    let sessionID: String
    /// The account's own website data store, which keeps the identity provider's sign-in (cookies) for this account
    /// only, so a linked service that signs in the same way can sign in, and renew its sign-in, without asking again.
    public var webStoreID: UUID?
    public init(id: UUID = UUID(), school: School, person: Person, sessionID: String) {
        self.id = id; self.school = school; name = person.name; username = person.username
        personID = person.id; self.sessionID = sessionID
    }
}
