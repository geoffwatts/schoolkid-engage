import Foundation
import SwiftUI
import SEQTAKit
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
    private var clients: [UUID: SEQTAClient] = [:]
    private let store = KeychainAccountStore()
    @Published private var schoolNames: [String: String] = UserDefaults.standard.dictionary(forKey: "publicSchoolNames") as? [String: String] ?? [:]
    var account: SavedAccount? { accounts.first { $0.id == accountID } }
    var child: Child? { children.first { $0.id == childID } }
    var client: SEQTAClient? { accountID.flatMap { clients[$0] } }
    var schoolName: String { isDemo ? "Banksia College" : account.flatMap { schoolNames[$0.school.url.absoluteString] } ?? "School" }
    var identityHeader: String { child.map { "\($0.name) (\(schoolName))" } ?? schoolName }

    init() {
        do {
            accounts = try store.load()
            clients = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, SEQTAClient(account: $0, transport: ActivityTransport(expiry: SessionExpiryRelay(model: self, accountID: $0.id)))) })
            accountID = accounts.first?.id
        } catch { self.error = error.localizedDescription }
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

    func connect(school: School, sessionID: String) async throws {
        let relay = SessionExpiryRelay(model: self)
        let client = SEQTAClient(school: school, transport: ActivityTransport(expiry: relay))
        let saved = try await client.connect(sessionID: sessionID)
        relay.accountID = saved.id
        try saveAccount(saved, client: client)
    }

    private func saveAccount(_ saved: SavedAccount, client: SEQTAClient) throws {
        let duplicates = accounts.filter { $0.school == saved.school && $0.personID == saved.personID }
        let updated = accounts.filter { existing in !duplicates.contains { $0.id == existing.id } } + [saved]
        try store.save(updated)
        accounts = updated
        for old in duplicates { clients.removeValue(forKey: old.id) }
        clients[saved.id] = client
        selectAccount(saved.id)
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
    /// The example everyone starts with, switched off until the reader turns it on.
    static let exampleReminder = ReminderRule(note: "PE uniform", isEnabled: false, kinds: [LessonKind.sport.key])
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
    private func reminderNotes(for lessons: [WidgetSnapshot.Lesson]) -> [String: [ReminderNote]] {
        Reminders.notes(rules: reminderRules, lessons: lessons.map { ($0.subject, WidgetSnapshot.dayKey($0.start)) }, kind: LessonKind.key(for:))
    }
    /// Re-reads the rules into the current snapshot without fetching the timetable again.
    private func applyReminders() {
        guard var snapshot = schoolDays else { return }
        snapshot.dayReminders = reminderNotes(for: snapshot.lessons)
        schoolDays = snapshot
        snapshot.save()
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
    func selectChild(_ id: String) { childID = id; selectionVersion = UUID() }
    func startDemo() {
        isDemo = true; accountID = nil
        children = [Child(id: "101", name: "Alex Morgan"), Child(id: "102", name: "Sam Morgan")]
        childID = children.first?.id; error = nil; selectionVersion = UUID()
    }
    func endDemo() {
        isDemo = false; children = []; childID = nil; accountID = accounts.first?.id
        error = nil; selectionVersion = UUID(); clearWidgets()
    }
    func remove(_ account: SavedAccount) async {
        do {
            let updated = accounts.filter { $0.id != account.id }; try store.save(updated)
            await clients[account.id]?.forgetSession(); clients.removeValue(forKey: account.id); accounts = updated
            clearWidgets()
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
            children = loaded
            if let preferred = preferredChildID, loaded.contains(where: { $0.id == preferred }) {
                if childID != preferred { childID = preferred; selectionVersion = UUID() }
            } else if !loaded.contains(where: { $0.id == childID }) { childID = loaded.first?.id; selectionVersion = UUID() }
            preferredChildID = nil
        } catch {
            guard selected == accountID, !Task.isCancelled, !isDemo else { return }
            self.error = error.localizedDescription
        }
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
