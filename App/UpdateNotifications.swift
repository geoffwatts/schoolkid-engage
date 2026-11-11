import BackgroundTasks
import Foundation
import SEQTAKit
import UserNotifications

/// Announces new bell-feed events with local notifications. There is no push server: iOS wakes the app for
/// background app refresh at times of its choosing, and the app reads each saved account's feed directly from
/// the school. Sessions are Keychain items readable only while the device is unlocked, so a refresh that runs
/// while it's locked finds nothing and tries again later.
@MainActor
final class UpdateNotifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = UpdateNotifier()
    static let refreshTaskID = "au.schoolkid.engage.updates"
    /// The account and child named by a notification the user tapped, for the root view to open.
    struct Destination: Equatable { let accountID: UUID; let childID: String? }
    @Published var destination: Destination?
    /// The user's preference. Delivery also needs the system permission, requested the first time it applies.
    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled { Task { await requestAuthorizationIfNeeded(); scheduleRefresh() } }
            else { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshTaskID) }
        }
    }
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined

    private static let enabledKey = "updateNotifications"
    private static let seenKey = "seenUpdateIDs"
    /// What the Updates screen has shown, per account. Separate from `seenKey`, which records what's been *announced*:
    /// an alerted update still counts as unread until it's looked at.
    private static let viewedKey = "viewedUpdateIDs"
    private static let unviewedKey = "unviewedUpdateCounts"
    /// Updates not yet looked at, per account: the Updates tab's badge, and (summed) the app icon's.
    @Published private(set) var unviewed: [UUID: Int] = [:]
    /// More new events than this at once become one summary notification instead of a stack of banners.
    private static let individualLimit = 3
    private let defaults = UserDefaults.standard
    private let center = UNUserNotificationCenter.current()
    private var checking = false

    private override init() {
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        super.init()
        let stored = defaults.dictionary(forKey: Self.unviewedKey) as? [String: Int] ?? [:]
        unviewed = Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in UUID(uuidString: key).map { ($0, value) } })
    }

    /// Installs the delegate; call once at launch, before a tapped notification can be delivered.
    func activate() {
        center.delegate = self
        Task { await refreshAuthorization() }
    }

    func refreshAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    func requestAuthorizationIfNeeded() async {
        await refreshAuthorization()
        guard isEnabled, authorization == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        await refreshAuthorization()
    }

    /// Asks iOS for a background refresh once some account's feed has a baseline to compare against.
    /// iOS decides when, if ever, it runs; the earliest date is only a floor.
    func scheduleRefresh() {
        guard isEnabled, !seenByAccount().isEmpty else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// The Updates screen shows these events, so they're no longer news. The first load for an account is also
    /// the moment notifications become relevant, so it's when the system permission is requested.
    func didShow(_ feed: [ActivityItem], account: UUID) async {
        var viewed = viewedByAccount(); viewed[account] = Array((feed.map(\.id) + (viewed[account] ?? [])).prefix(SeenActivity.limit))
        saveViewed(viewed); setUnviewed(0, for: account)
        update(account) { SeenActivity.record(feed, after: $0).seen }
        await requestAuthorizationIfNeeded()
        scheduleRefresh()
    }

    /// Background refresh: reads every saved account's feed and announces what's new since it was last seen.
    func checkForUpdates() async {
        defer { scheduleRefresh() }
        guard isEnabled, !checking else { return }
        checking = true; defer { checking = false }
        await refreshAuthorization()
        guard authorization == .authorized || authorization == .provisional,
              let accounts = try? KeychainAccountStore().load() else { return }
        forget(except: Set(accounts.map(\.id)))
        for account in accounts {
            if Task.isCancelled { return }
            let client = SEQTAClient(account: account, transport: ActivityTransport())
            guard let feed = try? await client.activity() else { continue }
            // Unread count for the badges: everything in the feed the Updates screen hasn't shown yet.
            if let viewed = viewedByAccount()[account.id].map(Set.init) { setUnviewed(feed.filter { !viewed.contains($0.id) }.count, for: account.id) }
            var fresh: [ActivityItem] = []
            update(account.id) { previous in
                let result = SeenActivity.record(feed, after: previous); fresh = result.new; return result.seen
            }
            // Only assessment updates are worth an alert; other events are still recorded as seen above.
            fresh = fresh.filter { $0.assessment != nil }
            guard !fresh.isEmpty else { continue }
            // Child names come from the school on demand rather than being kept on the device.
            let children = (try? await client.children()) ?? []
            await announce(fresh, account: account, children: children)
        }
    }

    #if DEBUG
    /// Simulator testing, where background refresh never runs: forgets each account's newest assessment event, then
    /// runs the same check background refresh would, so that event is announced through the normal path.
    func debugAnnounceNewest() async {
        await requestAuthorizationIfNeeded()
        var all = seenByAccount()
        for account in (try? KeychainAccountStore().load()) ?? [] {
            guard let seen = all[account.id],
                  let feed = try? await SEQTAClient(account: account, transport: ActivityTransport()).activity(),
                  let newest = feed.filter({ $0.assessment != nil }).max(by: { $0.timestamp < $1.timestamp }) else { continue }
            all[account.id] = SeenActivity(ids: seen.ids.filter { $0 != newest.id })
            // Also un-view it, so the badges show it as unread.
            var viewed = viewedByAccount(); viewed[account.id] = viewed[account.id]?.filter { $0 != newest.id }; saveViewed(viewed)
        }
        save(all)
        await checkForUpdates()
    }
    #endif

    /// Clears what's remembered for removed accounts and withdraws their notifications.
    func forget(except accountIDs: Set<UUID>) {
        let staleViews = viewedByAccount().filter { !accountIDs.contains($0.key) }
        if !staleViews.isEmpty { saveViewed(viewedByAccount().filter { accountIDs.contains($0.key) }) }
        for id in unviewed.keys where !accountIDs.contains(id) { setUnviewed(0, for: id) }
        var all = seenByAccount()
        let removed = all.keys.filter { !accountIDs.contains($0) }
        guard !removed.isEmpty else { return }
        for id in removed { all[id] = nil }
        save(all)
        let threads = Set(removed.map(\.uuidString))
        center.getDeliveredNotifications { delivered in
            let ids = delivered.filter { threads.contains($0.request.content.threadIdentifier) }.map(\.request.identifier)
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    private func announce(_ items: [ActivityItem], account: SavedAccount, children: [Child]) async {
        func name(_ childID: String?) -> String? { children.first { $0.id == childID }?.name }
        if items.count > Self.individualLimit {
            let content = UNMutableNotificationContent()
            let childIDs = Set(items.map(\.childID))
            let only = childIDs.count == 1 ? name(childIDs.first ?? nil) : nil
            content.title = "\(items.count) new updates"
            content.body = only.map { "For \($0). Open Schoolkid Engage to read them." } ?? "Open Schoolkid Engage to read them."
            content.threadIdentifier = account.id.uuidString
            content.sound = .default
            content.userInfo = userInfo(account: account.id, child: childIDs.count == 1 ? childIDs.first ?? nil : nil)
            try? await center.add(UNNotificationRequest(identifier: "\(account.id)-summary-\(items.last!.id)", content: content, trigger: nil))
            return
        }
        for item in items {
            let content = UNMutableNotificationContent()
            if let assessment = item.assessment {
                // Same as the Updates row: the trimmed title, plus whose and which subject. SEQTA's own subtitle
                // ("Alex Morgan's Science assessment …") only repeats those, so there's no body.
                content.title = assessment.displayTitle
                let subject = assessment.subject == "Assessment" ? nil : assessment.subject
                content.subtitle = [name(item.childID), subject].compactMap { $0 }.joined(separator: " · ")
            } else {
                content.title = item.title
                if let child = name(item.childID) { content.subtitle = child }
                if !item.subtitle.isEmpty { content.body = item.subtitle }
            }
            content.threadIdentifier = account.id.uuidString
            content.sound = .default
            content.userInfo = userInfo(account: account.id, child: item.childID)
            try? await center.add(UNNotificationRequest(identifier: "\(account.id)-\(item.id)", content: content, trigger: nil))
        }
    }

    private func userInfo(account: UUID, child: String?) -> [String: String] {
        var info = ["accountID": account.uuidString]
        if let child { info["childID"] = child }
        return info
    }

    // MARK: Unread badges

    private func viewedByAccount() -> [UUID: [String]] {
        let stored = defaults.dictionary(forKey: Self.viewedKey) as? [String: [String]] ?? [:]
        return Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in UUID(uuidString: key).map { ($0, value) } })
    }
    private func saveViewed(_ all: [UUID: [String]]) {
        defaults.set(Dictionary(uniqueKeysWithValues: all.map { ($0.key.uuidString, $0.value) }), forKey: Self.viewedKey)
    }
    private func setUnviewed(_ count: Int, for account: UUID) {
        if count == 0 { unviewed[account] = nil } else { unviewed[account] = count }
        defaults.set(Dictionary(uniqueKeysWithValues: unviewed.map { ($0.key.uuidString, $0.value) }), forKey: Self.unviewedKey)
        // The icon shows every account's unread updates together.
        let total = unviewed.values.reduce(0, +)
        center.setBadgeCount(total) { _ in }
    }

    // MARK: Seen events, stored per account as IDs only

    private func seenByAccount() -> [UUID: SeenActivity] {
        guard let data = defaults.data(forKey: Self.seenKey),
              let stored = try? JSONDecoder().decode([String: SeenActivity].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in UUID(uuidString: key).map { ($0, value) } })
    }
    private func save(_ all: [UUID: SeenActivity]) {
        let stored = Dictionary(uniqueKeysWithValues: all.map { ($0.key.uuidString, $0.value) })
        defaults.set(try? JSONEncoder().encode(stored), forKey: Self.seenKey)
    }
    private func update(_ account: UUID, _ change: (SeenActivity?) -> SeenActivity) {
        var all = seenByAccount(); all[account] = change(all[account]); save(all)
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let account = (info["accountID"] as? String).flatMap(UUID.init(uuidString:)) else { return }
        let child = info["childID"] as? String
        await MainActor.run { destination = Destination(accountID: account, childID: child) }
    }
}
