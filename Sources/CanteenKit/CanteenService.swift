import Foundation

/// What the app needs from a canteen provider, for one linked account. Account and menu IDs are the provider's own.
/// `MSAClient` (My Student Account) and the app's demo provide it.
public protocol CanteenService: Sendable {
    func accounts() async throws -> [CanteenAccount]
    func menus(account: Int) async throws -> [CanteenMenuSummary]
    func menu(account: Int, menu: Int) async throws -> CanteenMenu
    func remaining(account: Int, menu: Int, day: CanteenDay) async throws -> [CanteenRemaining]
    /// Problems the portal finds with an order (sold out, closed day…); empty when it can be placed.
    func verify(_ order: CanteenOrder, account: Int, menu: Int) async throws -> [String]
    /// Places an order paid from the account balance. Returns the portal's order numbers. Never retried automatically.
    func place(_ order: CanteenOrder, account: Int, menu: Int) async throws -> [String]
    func transactions(account: Int) async throws -> [CanteenTransaction]
    func orderHistory(account: Int) async throws -> [CanteenPastOrder]
}
