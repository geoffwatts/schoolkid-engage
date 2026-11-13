import Foundation
import SwiftUI
import LMSKit
import CanteenKit
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
    @Published var accounts: [SavedAccount] = []
    @Published var accountID: UUID?
    @Published var children: [Child] = []
    @Published var childID: String?
    @Published var isDemo = false
    @Published var isLoading = false
    @Published var error: String?
    @Published var selectionVersion = UUID()
    /// Today's school cycle for the selected child, e.g. "Day 5, Week A".
    /// SEQTA's raw cycle label for today (e.g. ["Day 7"]); `todayCycle` is how it's shown.
    @Published private(set) var todayCycleParts: [String]?
    /// Today's cycle as shown: "Day 7, Week B" at a fortnightly school, "Day 7" elsewhere.
    var todayCycle: String? { todayCycleParts.flatMap { CycleLabel.text(for: $0, weekLetters: showsWeekLetters) } }
    /// The highest cycle day seen at each school (keyed by portal URL, or "demo"). Only ever rises, and persists.
    @Published private var cycleMaxDays: [String: Int] = UserDefaults.standard.dictionary(forKey: "cycleMaxDays") as? [String: Int] ?? [:]
    private var cycleSchoolKey: String { isDemo ? "demo" : account?.school.url.absoluteString ?? "" }
    /// Whether this school runs a ten-day (Week A/B) cycle, judged from the days seen so far.
    var showsWeekLetters: Bool { CycleLabel.isFortnight(maxDaySeen: cycleMaxDays[cycleSchoolKey]) }
    /// Learns the school's cycle length from any loaded timetable. The timetable screen calls this for every week shown.
    func recordCycles(from schedule: TimetableSchedule) {
        guard let highest = schedule.cycles.values.compactMap(CycleLabel.day(in:)).max(), highest > cycleMaxDays[cycleSchoolKey] ?? 0 else { return }
        cycleMaxDays[cycleSchoolKey] = highest
        UserDefaults.standard.set(cycleMaxDays, forKey: "cycleMaxDays")
    }
    /// Each child's teachers by class ID, from timetable lessons (assessments carry no teacher of their own).
    @Published private(set) var classTeachers: [String: [String: ClassTeacher]] = [:]
    private var teachersRequested: Set<String> = []
    /// Each saved account's learning-platform client (SEQTA, the only LMS provider so far).
    private var clients: [UUID: any LMSService] = [:]
    let store = KeychainAccountStore()
    @Published private var schoolNames: [String: String] = UserDefaults.standard.dictionary(forKey: "publicSchoolNames") as? [String: String] ?? [:]
    var account: SavedAccount? { accounts.first { $0.id == accountID } }
    var child: Child? { children.first { $0.id == childID } }
    var client: (any LMSService)? { accountID.flatMap { clients[$0] } }
    var schoolName: String { isDemo ? "Banksia College" : account.flatMap { schoolNames[$0.school.url.absoluteString] } ?? "School" }
    var identityHeader: String { child.map { "\($0.name) (\(schoolName))" } ?? schoolName }

    // MARK: News and report read state

    @Published private var unreadItems: UnreadItems = {
        guard let data = UserDefaults.standard.data(forKey: "readingUnreadItems") else { return UnreadItems() }
        return (try? JSONDecoder().decode(UnreadItems.self, from: data)) ?? UnreadItems()
    }()
    private var readingAccount: String { isDemo ? "demo" : accountID?.uuidString ?? "none" }
    var readingScope: String { "\(readingAccount)/\(childID ?? "")" }
    var newsScope: String { "\(readingAccount)/news" }
    var reportsScope: String { "\(readingAccount)/reports/\(childID ?? "")" }
    var unreadNewsCount: Int { unreadItems.count(in: newsScope) }
    var unreadReportCount: Int { unreadItems.count(in: reportsScope) }
    func isNewsUnread(_ id: String) -> Bool { unreadItems.isUnread(id, in: newsScope) }
    func isReportUnread(_ id: String) -> Bool { unreadItems.isUnread(id, in: reportsScope) }
    private func saveReadState() {
        var saved = unreadItems
        saved.remove(accountPrefix: "demo/")
        guard let data = try? JSONEncoder().encode(saved) else { return }
        UserDefaults.standard.set(data, forKey: "readingUnreadItems")
    }
    /// A day's notices. They're unread until opened, except those from before the account began tracking (its first
    /// sign-in, or the first launch of a build with this): days before that count as read. Today's list is what the
    /// badge counts; other days add to it without replacing it.
    func recordNews(_ notices: [Notice], on date: Date) {
        let calendar = Calendar.current
        let baseline = unreadItems.startTracking(in: newsScope)
        // Notices carry no time of their own, only the day they're listed under; the baseline's whole day is unread.
        let cutoff = calendar.startOfDay(for: baseline).addingTimeInterval(-1)
        let day = calendar.startOfDay(for: date)
        unreadItems.recordDated(notices.map { (id: $0.id, date: day) }, in: newsScope, since: cutoff,
                                replacing: calendar.isDateInToday(date))
        saveReadState()
    }
    func recordReports(_ reports: [AcademicReport]) {
        if isDemo {
            unreadItems.record(reports.map(\.id), in: reportsScope, replacing: true)
        } else {
            let baseline = unreadItems.startTracking(in: "\(readingAccount)/reports")
            unreadItems.recordDated(reports.map { (id: $0.id, date: $0.publishedAt) }, in: reportsScope, since: baseline)
        }
        saveReadState()
    }
    func markNewsRead(_ id: String, scope: String) {
        unreadItems.markRead(id, in: scope); saveReadState()
    }
    func markReportRead(_ id: String, scope: String) {
        unreadItems.markRead(id, in: scope); saveReadState()
    }
    /// Load counts before either screen is opened. Errors leave the last known count intact.
    func refreshReadingBadges() async {
        guard let child, isDemo || client != nil else { return }
        let scope = readingScope, client = client, demo = isDemo
        async let news: [Notice]? = try? (demo ? Demo.notices() : await client?.news(on: Date()) ?? [])
        async let reports: [AcademicReport]? = try? (demo ? Demo.reports() : await client?.reports(for: child) ?? [])
        let (notices, documents) = await (news, reports)
        guard scope == readingScope, !Task.isCancelled else { return }
        if let notices { recordNews(notices, on: Date()) }
        if let documents { recordReports(documents) }
    }

    // MARK: Lunch orders (state; the logic is in AppModel+Lunch.swift)

    /// Each saved account's canteen link, kept in its own Keychain item (`canteenStore`), not in the account.
    @Published var canteenLinks: [UUID: CanteenConnection] = [:]
    let canteenStore = CanteenLinkStore()
    /// Each saved account's lunch-order accounts and balances, as the portal last listed them; in memory only.
    @Published var canteenAccounts: [UUID: [CanteenAccount]] = [:]
    /// Saved accounts whose lunch-order sign-in has ended and couldn't be renewed without the user.
    @Published var canteenSignInNeeded: Set<UUID> = []
    /// Bumped by the header's balance to open the Lunch tab.
    @Published var lunchOpenRequest = UUID()
    var canteenClients: [UUID: MSAClient] = [:]
    var canteenCookieVersions: [UUID: Int] = [:]
    var canteenRenewals: [UUID: Task<Bool, Never>] = [:]
    /// Website data stores a sign-in browser is using right now, which a clean-up mustn't remove.
    var webStoresInUse: Set<UUID> = []
    let demoCanteen = DemoCanteen()

    init() {
        do {
            accounts = try store.load()
            clients = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, SEQTAClient(account: $0, transport: ActivityTransport(expiry: SessionExpiryRelay(model: self, accountID: $0.id)))) })
            canteenLinks = loadCanteenLinks()
            for account in accounts { if let link = canteenLink(for: account.id) { canteenClients[account.id] = makeCanteenClient(link) } }
            accountID = accounts.first?.id
            for account in accounts {
                _ = unreadItems.startTracking(in: "\(account.id.uuidString)/reports")
                _ = unreadItems.startTracking(in: "\(account.id.uuidString)/news")
            }
            saveReadState()
        } catch { self.error = error.localizedDescription }
    }

    /// Saves a changed account (its website data store) without changing what's selected.
    func update(_ account: SavedAccount) throws {
        let updated = accounts.map { $0.id == account.id ? account : $0 }
        try store.save(updated)
        accounts = updated
    }

    func addAccount(school: String, username: String, password: String, setupLink: String) async throws {
        let target: School; let credentials: Credentials
        if !setupLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let link = try SetupLink(setupLink); target = link.school; credentials = .jwt(link.token)
        } else {
            target = try School(school); credentials = .password(username: username, password: password)
        }
        let relay = SessionExpiryRelay(model: self)
        let client = SEQTAClient(school: target, transport: ActivityTransport(expiry: relay))
        let saved = try await client.signIn(credentials)
        relay.accountID = saved.id
        try saveAccount(saved, client: client)
    }

    /// `webStoreID` is the website data store the school sign-in used; it stays with the account.
    func connect(school: School, sessionID: String, webStoreID: UUID? = nil) async throws {
        let relay = SessionExpiryRelay(model: self)
        let client = SEQTAClient(school: school, transport: ActivityTransport(expiry: relay))
        var saved = try await client.connect(sessionID: sessionID)
        saved.webStoreID = webStoreID
        relay.accountID = saved.id
        try saveAccount(saved, client: client)
    }

    private func saveAccount(_ saved: SavedAccount, client: SEQTAClient) throws {
        var saved = saved
        let duplicates = accounts.filter { $0.school == saved.school && $0.personID == saved.personID }
        // Signing in again keeps the account's lunch-order link, and its data store if this sign-in didn't use one.
        let carriedLink = canteenLinks[saved.id] ?? duplicates.lazy.compactMap { self.canteenLinks[$0.id] }.first
        if saved.webStoreID == nil { saved.webStoreID = duplicates.first { $0.webStoreID != nil }?.webStoreID }
        let updated = accounts.filter { existing in !duplicates.contains { $0.id == existing.id } } + [saved]
        try store.save(updated)
        accounts = updated
        var links = canteenLinks
        for old in duplicates { links.removeValue(forKey: old.id) }
        links[saved.id] = carriedLink
        if links != canteenLinks { try? canteenStore.save(links); canteenLinks = links }
        for old in duplicates {
            clients.removeValue(forKey: old.id); canteenClients.removeValue(forKey: old.id)
            canteenAccounts.removeValue(forKey: old.id); canteenSignInNeeded.remove(old.id)
        }
        clients[saved.id] = client
        if let link = canteenLink(for: saved.id) { canteenClients[saved.id] = makeCanteenClient(link) }
        selectAccount(saved.id)
        removeUnusedWebStores()
    }

    /// The selected account's school session has ended; every tab shows a "Sign in again" banner until it's renewed.
    @Published var sessionHasExpired = false
    /// Bumped when something (the widget) asks for the timetable as of now; the timetable returns to today.
    @Published var timetableOpenRequest = UUID()
    /// Shows sign-in for the expired account's school.
    @Published var reauthenticating = false
    var expiredSchoolURL: String? { account?.school.url.absoluteString }
    func sessionExpired(for id: UUID) { if id == accountID, !sessionHasExpired { sessionHasExpired = true } }
    func selectAccount(_ id: UUID) {
        clearWidgets(); schoolDays = nil
        isDemo = false; accountID = id; children = []; childID = nil; error = nil; sessionHasExpired = false
        selectionVersion = UUID()
    }
    /// The child to select once the current account's children load, e.g. from a tapped notification.
    private var preferredChildID: String?
    /// Shows a saved account and, if given, one of its children. Returns false for an account no longer saved.
    @discardableResult
    func open(account id: UUID, child: String?) -> Bool {
        guard accounts.contains(where: { $0.id == id }) else { return false }
        if isDemo || accountID != id { preferredChildID = child; selectAccount(id) }
        else if let child, children.contains(where: { $0.id == child }) { selectChild(child) }
        else { preferredChildID = child; selectionVersion = UUID() }
        return true
    }
    /// Child, account and date the current `todayCycle` was loaded for. Every tab's header asks for the cycle as it appears;
    /// reloading (and clearing) it each time made the header re-truncate the child's name on every tab switch.
    private var todayCycleKey: String?
    /// The lookup in flight and its key. It belongs to the model, not to a header's `.task`: at launch the root view is
    /// replaced as the session loads, and a view-owned request was cancelled with nothing left to retry it.
    private var todayCycleRequestKey: String?
    private var todayCycleTask: Task<Void, Never>?
    private func todayCycleKey(for date: String) -> String { "\(accountID?.uuidString ?? "demo")-\(childID ?? "")-\(date)" }
    private static func cycleDateKey(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    /// Starts loading today's cycle for the selected child unless it's loaded or already loading.
    func refreshTodayCycle() {
        let today = Date(), date = Self.cycleDateKey(today), key = todayCycleKey(for: date)
        guard key != todayCycleKey, key != todayCycleRequestKey else { return }
        // A different child, account or day: the previous label no longer applies.
        todayCycleTask?.cancel(); todayCycleParts = nil; todayCycleKey = nil; todayCycleRequestKey = nil; schoolDays = nil
        guard let child, isDemo || client != nil else { return }
        todayCycleRequestKey = key
        let client = client, isDemo = isDemo
        todayCycleTask = Task { [weak self] in
            // A first request can still fail while the saved session is being restored, so retry briefly.
            for attempt in 1...4 {
                do {
                    // Today plus the next two school weeks in one request: enough to see every day of a ten-day cycle,
                    // which is how the app learns whether this school has a Week A and B.
                    let horizon = Calendar.current.date(byAdding: .day, value: 13, to: today)!
                    let schedule = isDemo ? try Demo.timetable(on: today) : try await client!.timetable(for: child, from: today, until: horizon)
                    guard let self, self.todayCycleRequestKey == key else { return }
                    // The demo serves one week per call; the following week holds the other half of its fortnight.
                    let nextWeek = isDemo ? try? Demo.timetable(on: today.addingTimeInterval(7 * 86_400)) : nil
                    if let nextWeek { self.recordCycles(from: nextWeek) }
                    self.recordCycles(from: schedule)
                    self.todayCycleParts = schedule.cycles[date]
                    self.updateWidgets(child: child, schedules: [schedule] + [nextWeek].compactMap { $0 })
                    self.todayCycleKey = key; self.todayCycleRequestKey = nil
                    return
                } catch {
                    if Task.isCancelled { return }
                    try? await Task.sleep(for: .seconds(Double(attempt)))
                }
            }
            if let self, self.todayCycleRequestKey == key { self.todayCycleRequestKey = nil }
        }
    }
    func teacher(forClass classID: String?, child: Child) -> ClassTeacher? {
        classID.flatMap { classTeachers[child.id]?[$0] }
    }
    /// Adds the teachers named in a loaded timetable. The timetable screen calls this for every week it shows.
    func recordTeachers(from schedule: TimetableSchedule, child: Child) {
        var known = classTeachers[child.id] ?? [:]
        for lesson in schedule.entries where !lesson.classID.isEmpty && !lesson.teacher.isEmpty {
            let teacher = ClassTeacher(name: lesson.teacher, email: lesson.teacherEmail)
            if known[lesson.classID] != teacher { known[lesson.classID] = teacher }
        }
        if known != classTeachers[child.id] { classTeachers[child.id] = known }
    }
    /// Fetches this week's timetable once per child, over the same range the timetable screen requests, so the two
    /// share the client's cached response rather than calling SEQTA again.
    func loadTeachersIfNeeded(for child: Child) async {
        guard !teachersRequested.contains(child.id) else { return }
        teachersRequested.insert(child.id)
        var calendar = Calendar(identifier: .gregorian); calendar.firstWeekday = 2
        let start = calendar.dateInterval(of: .weekOfYear, for: Date())!.start
        let schedule: TimetableSchedule?
        if isDemo { schedule = try? Demo.timetable(on: Date()) }
        else { schedule = try? await client?.timetable(for: child, from: start, until: calendar.date(byAdding: .day, value: 6, to: start)!) }
        if let schedule { recordTeachers(from: schedule, child: child) } else { teachersRequested.remove(child.id) }
    }
    /// Hands the widgets this child's next two weeks; they read it from the shared App Group container.
    private func updateWidgets(child: Child, schedules: [TimetableSchedule]) {
        let lessons = schedules.flatMap(\.entries).sorted { $0.start < $1.start }
            .map { WidgetSnapshot.Lesson(subject: $0.subject, start: $0.start, end: $0.end, room: $0.room) }
        let cycles = schedules.reduce(into: [String: [String]]()) { result, schedule in result.merge(schedule.cycles) { current, _ in current } }
        var snapshot = WidgetSnapshot(childName: child.name, generatedAt: Date(), weekLetters: showsWeekLetters, cycles: cycles, lessons: lessons)
        snapshot.dayReminders = reminderNotes(for: snapshot.lessons)
        snapshot.lunchBalance = lunchAccount?.balance
        snapshot.selectionKey = readingScope
        schoolDays = snapshot
        snapshot.save()
        scheduleReminderAlerts()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Keep the widget's last loaded balance in sync after refreshes, orders, linking and unlinking.
    func updateWidgetLunchBalance() {
        guard var snapshot = schoolDays, snapshot.selectionKey == readingScope else { return }
        snapshot.lunchBalance = lunchAccount?.balance
        schoolDays = snapshot
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Reminders

    /// The selected child's next two weeks, as handed to the widgets; the header's reminder bar reads it too.
    @Published private(set) var schoolDays: WidgetSnapshot?
    /// Every child's reminder rules, keyed by `reminderKey`. A child seen for the first time gets the example rule.
    @Published private var allReminderRules: [String: [ReminderRule]] = {
        guard let data = UserDefaults.standard.data(forKey: "reminderRules") else { return [:] }
        return (try? JSONDecoder().decode([String: [ReminderRule]].self, from: data)) ?? [:]
    }()
    private var reminderKey: String? { childID.map { "\(isDemo ? "demo" : accountID?.uuidString ?? "")-\($0)" } }
    /// The example everyone starts with, switched on: "PE uniform" on days with a sport lesson.
    static let exampleReminder = ReminderRule(note: "PE uniform", isEnabled: true, kinds: [LessonKind.sport.key])
    /// The selected child's reminder rules. Changing them updates the header and the widgets straight away.
    var reminderRules: [ReminderRule] {
        get { reminderKey.flatMap { allReminderRules[$0] } ?? [Self.exampleReminder] }
        set {
            guard let key = reminderKey else { return }
            allReminderRules[key] = newValue
            if let data = try? JSONEncoder().encode(allReminderRules) { UserDefaults.standard.set(data, forKey: "reminderRules") }
            applyReminders()
        }
    }
    /// A reminder tapped in the header bar: Settings opens on Reminders, then on this rule's editor.
    @Published var reminderToOpen: UUID?
    /// Opens the rule behind a tapped note; notes saved before they recorded their rule are matched by their text.
    func openReminder(_ note: ReminderNote) {
        reminderToOpen = note.ruleID ?? reminderRules.first { $0.trimmedNote == note.text }?.id
    }
    /// The selected child's reminders for each day of a loaded timetable week, for the timetable screen.
    func reminderNotes(for lessons: [TimetableEntry]) -> [String: [ReminderNote]] {
        Reminders.notes(rules: reminderRules, lessons: lessons.map { ($0.subject, WidgetSnapshot.dayKey($0.start)) },
                        kind: LessonKind.key(for:), symbol: LessonKind.symbol(for:))
    }
    private func reminderNotes(for lessons: [WidgetSnapshot.Lesson]) -> [String: [ReminderNote]] {
        Reminders.notes(rules: reminderRules, lessons: lessons.map { ($0.subject, WidgetSnapshot.dayKey($0.start)) },
                        kind: LessonKind.key(for:), symbol: LessonKind.symbol(for:))
    }
    /// Re-reads the rules into the current snapshot without fetching the timetable again.
    /// Reschedules the selected child's morning alerts from the current snapshot (never in the demo). The Reminders
    /// screen calls this when the alert is switched on or its time changes.
    func scheduleReminderAlerts() {
        guard !isDemo, let key = reminderKey, let snapshot = schoolDays else { return }
        Task { await ReminderAlerts.schedule(snapshot.dayReminders ?? [:], childKey: key, childName: snapshot.childName) }
    }
    private func applyReminders() {
        guard var snapshot = schoolDays else { return }
        snapshot.dayReminders = reminderNotes(for: snapshot.lessons)
        schoolDays = snapshot
        snapshot.save()
        scheduleReminderAlerts()
        WidgetCenter.shared.reloadAllTimelines()
    }
    /// The selected child's lessons over the past and coming fortnight, for choosing which lessons a reminder follows.
    func lessonsAroundToday() async throws -> [TimetableEntry] {
        guard let child else { return [] }
        let calendar = Calendar.current, today = Date()
        let from = calendar.date(byAdding: .day, value: -14, to: today)!, until = calendar.date(byAdding: .day, value: 14, to: today)!
        if isDemo {
            return try (-2...2).flatMap { try Demo.timetable(on: today.addingTimeInterval(Double($0) * 7 * 86_400)).entries }
        }
        guard let client else { return [] }
        return try await client.timetable(for: child, from: from, until: until).entries
    }
    /// The widgets must never keep showing a child from an account or demo that's gone.
    private func clearWidgets() { WidgetSnapshot.clear(); WidgetCenter.shared.reloadAllTimelines() }
    func selectChild(_ id: String) { clearWidgets(); schoolDays = nil; childID = id; selectionVersion = UUID() }
    func startDemo() {
        clearWidgets(); schoolDays = nil
        isDemo = true; accountID = nil
        children = [Child(id: "101", name: "Alex Morgan"), Child(id: "102", name: "Sam Morgan")]
        childID = children.first?.id; error = nil; selectionVersion = UUID()
    }
    func endDemo() {
        schoolDays = nil
        isDemo = false; children = []; childID = nil; accountID = accounts.first?.id
        error = nil; selectionVersion = UUID(); clearWidgets()
    }
    func remove(_ account: SavedAccount) async {
        do {
            let updated = accounts.filter { $0.id != account.id }; try store.save(updated)
            await clients[account.id]?.forgetSession(); clients.removeValue(forKey: account.id); accounts = updated
            childrenByAccount.removeValue(forKey: account.id); otherChildrenRequested.remove(account.id)
            canteenClients.removeValue(forKey: account.id); canteenAccounts.removeValue(forKey: account.id)
            canteenSignInNeeded.remove(account.id); try? saveCanteenLink(nil, for: account.id)
            // The account's data store (its identity-provider and lunch-order sign-ins) goes with it.
            removeUnusedWebStores()
            clearWidgets()
            // That account's children's morning alerts go with it.
            await ReminderAlerts.removeAll(childKeyPrefix: account.id.uuidString + "-")
            unreadItems.remove(accountPrefix: account.id.uuidString + "/"); saveReadState()
            UpdateNotifier.shared.forget(except: Set(updated.map(\.id)))
            if accountID == account.id {
                accountID = updated.first?.id; children = []; childID = nil; selectionVersion = UUID()
            }
        } catch { self.error = error.localizedDescription }
    }
    func loadChildren() async {
        guard !isDemo, let client else { return }
        let selected = accountID; isLoading = true; error = nil
        if let school = account?.school { Task { await loadSchoolName(school) } }
        defer { if selected == accountID { isLoading = false } }
        do {
            let loaded = try await client.children()
            guard selected == accountID, !Task.isCancelled, !isDemo else { return }
            children = loaded; if let selected { childrenByAccount[selected] = loaded }
            if let preferred = preferredChildID, loaded.contains(where: { $0.id == preferred }) {
                if childID != preferred { childID = preferred; selectionVersion = UUID() }
            } else if !loaded.contains(where: { $0.id == childID }) { childID = loaded.first?.id; selectionVersion = UUID() }
            preferredChildID = nil
        } catch {
            guard selected == accountID, !Task.isCancelled, !isDemo else { return }
            self.error = error.localizedDescription
        }
    }
    // MARK: Child switcher

    /// Each saved account's children, as its school last listed them. Held in memory only: child names aren't saved
    /// on the device, so other schools' children are asked for each time the app starts.
    @Published private var childrenByAccount: [UUID: [Child]] = [:]
    private var otherChildrenRequested: Set<UUID> = []
    /// An account's children, when its school has listed them this session.
    func knownChildren(of account: UUID) -> [Child]? { account == accountID && !children.isEmpty ? children : childrenByAccount[account] }
    /// The school's public name, when it's been looked up, otherwise its web address.
    func schoolName(of account: SavedAccount) -> String {
        schoolNames[account.school.url.absoluteString] ?? account.school.url.host ?? account.school.url.absoluteString
    }
    /// Asks every other saved account's school for its children (and its public name), once per launch, so the child
    /// switcher can offer them. An account whose school doesn't answer (offline, expired sign-in) is retried next time.
    func loadOtherAccountsChildren() async {
        for account in accounts where account.id != accountID && !otherChildrenRequested.contains(account.id) {
            guard let client = clients[account.id] else { continue }
            otherChildrenRequested.insert(account.id)
            Task { await loadSchoolName(account.school) }
            if let loaded = try? await client.children() { childrenByAccount[account.id] = loaded }
            else { otherChildrenRequested.remove(account.id) }
        }
    }
    /// A child in the switcher, with the saved account it's reached through (nil in the demo).
    struct ChildChoice: Identifiable, Hashable {
        let accountID: UUID?
        let child: Child
        var id: String { "\(accountID?.uuidString ?? "demo")-\(child.id)" }
    }
    /// One school in the switcher: its children, or, until its school has listed them, just the account to switch to.
    struct SwitcherSchool: Identifiable {
        let id: String
        let name: String
        let account: UUID?
        let children: [ChildChoice]
    }
    /// Every child across the saved accounts, grouped by school in the accounts' order. Two parent logins at the same
    /// school share a group, and a child both can see appears once (through the current account when it's one of them).
    var switcherSchools: [SwitcherSchool] {
        if isDemo { return [SwitcherSchool(id: "demo", name: schoolName, account: nil, children: children.map { ChildChoice(accountID: nil, child: $0) })] }
        var order: [String] = []; var byURL: [String: [SavedAccount]] = [:]
        for account in accounts {
            let url = account.school.url.absoluteString
            if byURL[url] == nil { order.append(url) }
            byURL[url, default: []].append(account)
        }
        return order.map { url in
            let schoolAccounts = byURL[url]!.sorted { a, _ in a.id == accountID }
            var seen: Set<String> = []; var choices: [ChildChoice] = []
            for account in schoolAccounts {
                for child in (account.id == accountID ? children : childrenByAccount[account.id] ?? []) where seen.insert(child.id).inserted {
                    choices.append(ChildChoice(accountID: account.id, child: child))
                }
            }
            let first = schoolAccounts[0]
            return SwitcherSchool(id: url, name: schoolNames[url] ?? first.school.url.host ?? url, account: first.id, children: choices)
        }
    }
    /// Only worth showing when there's a choice: more than one child, or more than one school.
    var showsChildSwitcher: Bool {
        let schools = switcherSchools
        return schools.count > 1 || schools.reduce(0) { $0 + $1.children.count } > 1
    }
    func isSelected(_ choice: ChildChoice) -> Bool { choice.accountID == (isDemo ? nil : accountID) && choice.child.id == childID }
    /// Switches to a child, changing school account first when the child is reached through another one.
    func choose(_ choice: ChildChoice) {
        guard let account = choice.accountID else { selectChild(choice.child.id); return }
        open(account: account, child: choice.child.id)
    }

    private func loadSchoolName(_ school: School) async {
        guard schoolNames[school.url.absoluteString] == nil else { return }
        let publicClient = SEQTAClient(school: school, transport: ActivityTransport())
        if let name = try? await publicClient.schoolDisplayName(), !name.isEmpty {
            schoolNames[school.url.absoluteString] = name
            UserDefaults.standard.set(schoolNames, forKey: "publicSchoolNames")
        }
    }

}


struct ClassTeacher: Equatable {
    let name: String
    let email: String
}
