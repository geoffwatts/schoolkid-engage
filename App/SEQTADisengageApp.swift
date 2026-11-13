import SwiftUI

@main
struct SEQTADisengageApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    init() {
        UpdateNotifier.shared.activate()
        if ProcessInfo.processInfo.arguments.contains("--demo") {
            // The launch argument is only used by UI tests; start each run from default preferences.
            UserDefaults.standard.removeObject(forKey: "timetableWeekView")
            UserDefaults.standard.removeObject(forKey: "reminderRules")
            for key in ["assessmentResultsSort", "assessmentUpcomingSort", "assessmentResultsShow", "assessmentUpcomingShow", "hideMarks"] {
                UserDefaults.standard.removeObject(forKey: key)
            }
            // The demo school's cycle length is learned afresh, so a run with another length isn't read as a fortnight.
            if var maxDays = UserDefaults.standard.dictionary(forKey: "cycleMaxDays") {
                maxDays["demo"] = nil; UserDefaults.standard.set(maxDays, forKey: "cycleMaxDays")
            }
            _model = StateObject(wrappedValue: {
            let model = AppModel(); model.startDemo()
            #if DEBUG
            // UI tests: show the expired-session banner without needing a real expired session.
            if ProcessInfo.processInfo.arguments.contains("--simulate-expired-session") { model.sessionHasExpired = true }
            #endif
            return model
        }()) }
    }
    var body: some Scene {
        WindowGroup { RootView().environmentObject(model).tint(.teal).modifier(DelayedNetworkIndicator())
            .task(id: model.accountID) {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--diagnose-shapes") { await writeDiagnosticShapes() }
                if ProcessInfo.processInfo.arguments.contains("--diagnose-timetable") { await writeDiagnosticShapes(timetableOnly: true) }
                #endif
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { UpdateNotifier.shared.scheduleRefresh() }
            if phase == .active { Task { await UpdateNotifier.shared.refreshAuthorization() } }
        }
        .backgroundTask(.appRefresh(UpdateNotifier.refreshTaskID)) { await UpdateNotifier.shared.checkForUpdates() }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var notifier = UpdateNotifier.shared
    @State private var showAccounts = false
    @State private var showSignIn = false
    #if DEBUG
    /// `--open-lunch` starts on the Lunch tab, for simulator layout checks.
    @State private var selectedTab = ProcessInfo.processInfo.arguments.contains("--open-lunch") ? 5 : 0
    #else
    @State private var selectedTab = 0
    #endif
    #if DEBUG
    @State private var testCanteenSignIn = ProcessInfo.processInfo.arguments.contains("--test-canteen-sign-in")
    #endif
    var body: some View {
        Group {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--test-widget-layout") {
                NavigationStack { WidgetLayoutPreview() }
            } else {
                reader
            }
            #else
            reader
            #endif
        }
        .task(id: model.accountID) { await model.loadChildren(); await model.loadOtherAccountsChildren() }
        .task(id: model.readingScope) { await model.refreshReadingBadges() }
        // Once per launch, after start-up: data stores left by unfinished sign-ins or removed accounts.
        .task { try? await Task.sleep(for: .seconds(3)); model.removeUnusedWebStores() }
        // The header's lunch balance, for whichever account and child are showing.
        .task(id: "\(model.accountID?.uuidString ?? "")-\(model.isDemo)-\(model.hasLunch)") { await model.refreshLunch() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.refreshLunch(); await model.refreshReadingBadges() } } }
        .onChange(of: model.lunchOpenRequest) { _, _ in showAccounts = false; selectedTab = 5 }
        .onChange(of: notifier.destination, initial: true) { _, destination in
            // A tapped update notification opens the Updates tab for its account and child.
            guard let destination else { return }
            notifier.destination = nil
            guard model.open(account: destination.accountID, child: destination.childID) else { return }
            showAccounts = false; showSignIn = false; selectedTab = 0
        }
        .onOpenURL { url in
            // schoolkidengage://timetable, from the widget: show the timetable as of now.
            guard url.scheme == "schoolkidengage", url.host == "timetable" else { return }
            showAccounts = false; showSignIn = false; selectedTab = 2; model.timetableOpenRequest = UUID()
        }
        // A reminder tapped anywhere (the header bar, the timetable) opens Settings on it.
        .onChange(of: model.reminderToOpen) { _, id in if id != nil { showAccounts = true } }
        #if DEBUG
        .sheet(isPresented: $testCanteenSignIn) { CanteenSignInView() }
        #endif
        .sheet(isPresented: $showAccounts) { AccountsView() }
        .sheet(isPresented: $showSignIn) { SignInView() }
        .sheet(isPresented: $model.reauthenticating) { SignInView(school: model.expiredSchoolURL, reuseStoreID: model.account?.webStoreID) }
    }
    @ViewBuilder private var reader: some View {
        Group {
            if model.accountID == nil && !model.isDemo {
                WelcomeView(showSignIn: $showSignIn)
            } else {
                TabView(selection: $selectedTab) {
                    ListDetailNavigation(placeholder: "Select an update", systemImage: "bell") { ActivityView().modifier(SchoolToolbar(showAccounts: $showAccounts)) }
                        .tabItem { Label("Updates", systemImage: "bell") }.tag(0)
                        // Unread updates for this account; nothing shows at zero.
                        .badge(model.accountID.flatMap { notifier.unviewed[$0] } ?? 0)
                    ListDetailNavigation(placeholder: "Select an assessment", systemImage: "checklist") { AssessmentsView().modifier(SchoolToolbar(showAccounts: $showAccounts)) }
                        .tabItem { Label("Assessments", systemImage: "checklist") }.tag(1)
                        .badge(model.unreadReportCount)
                    NavigationStack { TimetableView().modifier(SchoolToolbar(showAccounts: $showAccounts)) }
                        .tabItem { Label("Timetable", systemImage: "calendar") }.tag(2)
                    // Reports are a part of Assessments (its third segment), leaving room for Lunch.
                    if model.hasLunch {
                        LunchView(showAccounts: $showAccounts)
                            .tabItem { Label("Lunch", systemImage: "fork.knife") }.tag(5)
                    }
                }
                .id(model.selectionVersion)
            }
        }
    }

}

struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var showSignIn: Bool
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    // The app icon itself (rendered from AppIcon.icon by ictool), so the welcome matches the home screen.
                    Image("AppIconArtwork").resizable().frame(width: 80, height: 80).padding(.top, 55).accessibilityHidden(true)
                    Text("Schoolkid Engage").font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("The unofficial alternative parent app for SEQTA").font(.title3).foregroundStyle(.secondary)
                    Text("School news, assessments and reports.")
                        .foregroundStyle(.secondary).font(.title3)
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Move easily between school accounts", systemImage: "person.crop.circle.badge.checkmark")
                        Label("Keep each child in view", systemImage: "person.2")
                        Label("Your session stays on your device", systemImage: "lock.shield")
                    }.font(.subheadline)
                    Button("Connect your school") { showSignIn = true }.buttonStyle(.borderedProminent).controlSize(.large)
                    Button("Explore the demo") { model.startDemo() }
                    if let error = model.error { Text(error).foregroundStyle(.red) }
                    Text("An independent reader for SEQTA Engage. Not affiliated with SEQTA or Tes.")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: 520, alignment: .leading).padding(28)
            }.background(Color(.systemGroupedBackground))
        }
    }
}

struct SchoolToolbar: ViewModifier {
    @EnvironmentObject private var model: AppModel
    @State private var showNews = false
    @Binding var showAccounts: Bool
    /// A school's children, ticked when selected; a school that hasn't listed them yet offers itself instead.
    @ViewBuilder private func rows(for school: AppModel.SwitcherSchool) -> some View {
        if school.children.isEmpty, let account = school.account {
            Button { model.open(account: account, child: nil) } label: {
                if model.accountID == account { Label(school.name, systemImage: "checkmark") } else { Text(school.name) }
            }
        }
        ForEach(school.children) { choice in
            Button { model.choose(choice) } label: {
                if model.isSelected(choice) { Label(choice.child.name, systemImage: "checkmark") } else { Text(choice.child.name) }
            }
        }
    }
    func body(content: Content) -> some View {
        content.navigationBarTitleDisplayMode(.inline).toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showAccounts = true } label: {
                    Label(model.isDemo ? "Demo account" : model.account?.name ?? "Accounts", systemImage: "person.crop.circle")
                        .font(.subheadline)
                }.accessibilityLabel("Switch school account")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNews = true } label: {
                    Image(systemName: "newspaper")
                        .overlay(alignment: .topTrailing) {
                            if model.unreadNewsCount > 0 {
                                Text(model.unreadNewsCount > 99 ? "99+" : "\(model.unreadNewsCount)")
                                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                    .padding(.horizontal, 4).frame(minWidth: 17, minHeight: 17)
                                    .background(.red, in: Capsule()).offset(x: 9, y: -9)
                            }
                        }
                }.accessibilityLabel("News").accessibilityValue("\(model.unreadNewsCount) unread")
                    .accessibilityIdentifier("school-news")
            }
            ToolbarItem(placement: .topBarTrailing) {
                // Every child across every saved school, grouped by school; only shown when there's a choice to make.
                if model.showsChildSwitcher {
                    let schools = model.switcherSchools
                    Menu {
                        ForEach(schools) { school in
                            if schools.count > 1 { Section(school.name) { rows(for: school) } } else { rows(for: school) }
                        }
                    } label: { Image(systemName: "person.2") }
                    .accessibilityLabel("Select child: \(model.child?.name ?? "None")")
                }
            }
        }.sheet(isPresented: $showNews) {
            NavigationStack {
                NewsView(close: { showNews = false }).id(model.newsScope)
            }
        }.safeAreaInset(edge: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(model.identityHeader).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        .lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                    if let balance = model.lunchAccount?.balance { LunchBalanceBadge(balance: balance) }
                    if let cycle = model.todayCycle { CycleBadge(text: cycle) }
                }
                // One element for VoiceOver: the full child and school name (truncated on screen) and today's cycle.
                .frame(minHeight: 44)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel([model.identityHeader, model.todayCycle.map { "Today is \($0)" },
                                     model.lunchAccount.map { "Lunch balance \($0.balance.dollars)" }].compactMap { $0 }.joined(separator: ". "))
                if let schoolDays = model.schoolDays {
                    // Rolls over to the next school day once today's last lesson ends, as the widget does.
                    TimelineView(.everyMinute) { context in
                        if let reminder = schoolDays.reminderNotes(at: context.date) {
                            ReminderBar(day: reminder.day, notes: reminder.notes) { model.openReminder($0) }
                                .padding(.bottom, 4)
                        }
                    }
                }
                if model.sessionHasExpired {
                    // One clear way back in, rather than an error on every screen.
                    HStack(spacing: 10) {
                        Image(systemName: "lock.fill").foregroundStyle(.orange).accessibilityHidden(true)
                        Text("Your school sign-in has expired.").font(.subheadline)
                        Spacer(minLength: 8)
                        Button("Sign in again") { model.reauthenticating = true }
                            .font(.subheadline.weight(.semibold)).buttonStyle(.borderless)
                    }.padding(.top, 2)
                }
                if let error = model.error { Text(error).font(.caption).foregroundStyle(.red) }
                if model.isLoading { ProgressView().controlSize(.small) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.vertical, 4)
                .background(.bar)
                .task(id: "\(model.childID ?? "")-\(model.isDemo)") { model.refreshTodayCycle() }
        }
    }
}

/// A list with its detail beside it on iPad (and other regular-width layouts), or a pushed stack on iPhone.
/// The lists' existing `NavigationLink`s open in the detail column of the split view.
struct ListDetailNavigation<List: View>: View {
    let placeholder: String
    let systemImage: String
    @ViewBuilder var list: () -> List
    @Environment(\.horizontalSizeClass) private var sizeClass
    var body: some View {
        if sizeClass == .regular {
            NavigationSplitView {
                list().navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 460)
            } detail: {
                ContentUnavailableView(placeholder, systemImage: systemImage)
            }.navigationSplitViewStyle(.balanced)
        } else {
            NavigationStack { list() }
        }
    }
}
