import Foundation
import WebKit
import LMSKit
import CanteenKit

/// Lunch orders through a school's My Student Account portal, linked to a saved school account. The portal signs in
/// through the same identity provider as the school, in the account's own website data store, so linking and renewing
/// usually needs no typing.
extension AppModel {
    /// Stands in for a saved account's ID in the demo.
    static let demoCanteenKey = UUID(uuidString: "00000000-0000-0000-0000-00000000C0DE")!
    private var canteenKey: UUID? { isDemo ? Self.demoCanteenKey : accountID }

    /// Whether the current account has lunch orders (always, in the demo).
    var hasLunch: Bool { isDemo || canteenLink != nil }
    var canteenService: (any CanteenService)? { isDemo ? demoCanteen : accountID.flatMap { canteenClients[$0] } }
    var lunchSignInNeeded: Bool { !isDemo && accountID.map { canteenSignInNeeded.contains($0) } == true }

    /// The selected child's lunch account: the one with the child's name, or the only one when there's one child.
    var lunchAccount: CanteenAccount? {
        guard let key = canteenKey, let list = canteenAccounts[key], let child else { return nil }
        if let match = list.first(where: { $0.matches(childName: child.name) }) { return match }
        return list.count == 1 && children.count == 1 ? list[0] : nil
    }
    /// Whether the current account's lunch accounts have loaded, so "no account for this child" can be said.
    var lunchAccountsLoaded: Bool { canteenKey.map { canteenAccounts[$0] != nil } ?? false }

    func makeCanteenClient(_ link: MSALink) -> MSAClient { MSAClient(link: link, transport: ActivityTransport()) }

    /// An account's My Student Account link (the only canteen provider so far).
    func canteenLink(for id: UUID?) -> MSALink? { id.flatMap { canteenLinks[$0]?.msa } }
    /// The selected account's.
    var canteenLink: MSALink? { isDemo ? nil : canteenLink(for: accountID) }

    func saveCanteenLink(_ link: MSALink?, for id: UUID) throws {
        var links = canteenLinks
        links[id] = link.map { .myStudentAccount($0) }
        guard links != canteenLinks else { return }
        try canteenStore.save(links)
        canteenLinks = links
    }

    /// The saved links; on the first launch after they moved out of the accounts' JSON (builds 19–20 kept them there),
    /// moves them across and saves the accounts without them.
    func loadCanteenLinks() -> [UUID: CanteenConnection] {
        do { if let links = try canteenStore.load() { return links } } catch { return [:] }
        guard let data = try? store.loadData() else { return [:] }
        let legacy = CanteenLinkStore.legacyLinks(fromAccountsJSON: data)
        do {
            try canteenStore.save(legacy)
            // Re-saving drops the old copies, which `SavedAccount` no longer has a field for.
            if !legacy.isEmpty { try store.save(accounts) }
        } catch { }
        return legacy
    }

    /// Reloads the current account's lunch accounts and balances (what the header and Lunch tab show).
    func refreshLunch() async {
        guard hasLunch, let key = canteenKey, let service = canteenService else { return }
        if let list = try? await withCanteenRenewal({ try await service.accounts() }) { canteenAccounts[key] = list; updateWidgetLunchBalance() }
    }

    /// Runs a portal request. If the portal's sign-in has ended, renews it once, silently, through the account's data
    /// store and tries again; when that can't be done without the user, the Lunch tab offers to sign in.
    /// `retry: false` for anything that changes the portal (placing an order is never sent twice).
    func withCanteenRenewal<T>(retry: Bool = true, _ work: () async throws -> T) async throws -> T {
        // The account the request is for, even if another is selected while it runs.
        let id = isDemo ? nil : accountID
        do {
            let result = try await work(); await saveRefreshedCanteenCookies(for: id); return result
        } catch CanteenError.signInRequired where id != nil {
            guard let id else { throw CanteenError.signInRequired }
            guard await renewCanteenSession(for: id) else { canteenSignInNeeded.insert(id); throw CanteenError.signInRequired }
            guard retry else { throw CanteenError.signInRequired }
            let result = try await work(); await saveRefreshedCanteenCookies(for: id); return result
        }
    }

    /// Signs the portal in again in a hidden browser using the account's data store. True when it worked.
    func renewCanteenSession(for id: UUID) async -> Bool {
        if let running = canteenRenewals[id] { return await running.value }
        guard let account = accounts.first(where: { $0.id == id }), let link = canteenLink(for: id), let storeID = account.webStoreID else { return false }
        let task = Task { @MainActor [weak self] () -> Bool in
            self?.webStoresInUse.insert(storeID)
            defer { self?.webStoresInUse.remove(storeID) }
            guard let cookies = await CanteenBrowser.renew(portal: link.portal, storeID: storeID), let self else { return false }
            return await self.storeCanteenCookies(cookies, for: id)
        }
        canteenRenewals[id] = task
        let renewed = await task.value
        canteenRenewals[id] = nil
        return renewed
    }

    /// Saves renewed cookies and hands them to the account's client before returning, so a retry uses them.
    @discardableResult
    func storeCanteenCookies(_ cookies: [String: String], for id: UUID) async -> Bool {
        guard var link = canteenLink(for: id), !cookies.isEmpty else { return false }
        link.cookies = cookies
        do { try saveCanteenLink(link, for: id) } catch { return false }
        if let client = canteenClients[id] { await client.replaceCookies(cookies); canteenCookieVersions[id] = await client.cookieVersion }
        canteenSignInNeeded.remove(id)
        return true
    }

    /// Saves the portal's refreshed cookies (it extends a sign-in as it's used), so a relaunch carries on with them.
    private func saveRefreshedCanteenCookies(for id: UUID?) async {
        guard let id, let client = canteenClients[id] else { return }
        let version = await client.cookieVersion
        guard version != canteenCookieVersions[id] else { return }
        canteenCookieVersions[id] = version
        let link = await client.link
        guard canteenLink(for: id) != link else { return }
        try? saveCanteenLink(link, for: id)
    }

    /// Links the current account to a lunch-order portal, after its sign-in in `storeID`. Checks the session by
    /// reading the portal's account list first.
    func linkCanteen(portal: MSAPortal, cookies: [String: String], storeID: UUID) async throws {
        guard let id = accountID, var account = account else { throw CanteenError.signInRequired }
        let link = MSALink(portal: portal, cookies: cookies)
        let client = makeCanteenClient(link)
        let list = try await client.accounts()
        try saveCanteenLink(await client.link, for: id)
        account.webStoreID = storeID
        try update(account)
        canteenClients[id] = client; canteenAccounts[id] = list; canteenSignInNeeded.remove(id)
        canteenCookieVersions[id] = await client.cookieVersion
        updateWidgetLunchBalance()
        removeUnusedWebStores()
    }

    /// Deletes website data stores no saved account uses: from sign-ins that didn't finish, or removed accounts.
    func removeUnusedWebStores() {
        let used = Set(accounts.compactMap(\.webStoreID)).union(webStoresInUse)
        // Listing the stores before WebKit has started crashes inside WebKit; touching the default store starts it.
        _ = WKWebsiteDataStore.default()
        Task {
            for id in await WKWebsiteDataStore.allDataStoreIdentifiers where !used.contains(id) {
                try? await WKWebsiteDataStore.remove(forIdentifier: id)
            }
        }
    }
}
