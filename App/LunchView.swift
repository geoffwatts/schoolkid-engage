import SwiftUI
import LMSKit
import CanteenKit

extension Decimal {
    /// Dollars as the portal shows them: "$7.50".
    var dollars: String { formatted(.currency(code: "AUD").locale(Locale(identifier: "en_AU"))) }
}

extension CanteenDay {
    /// Short dates throughout Lunch ("Tue, 10 Nov 26"): abbreviated weekday and month, two-digit year.
    var title: String {
        let date = displayDate.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits).locale(Locale(identifier: "en_AU")))
        let calendar = Calendar.current
        if calendar.isDateInToday(displayDate) { return "Today · \(date)" }
        if calendar.isDateInTomorrow(displayDate) { return "Tomorrow · \(date)" }
        return longTitle
    }
    var longTitle: String { Self.short(displayDate) }
    /// "Tue, 10 Nov 26", in the en-AU format.
    static func short(_ date: Date, timeZone: TimeZone = .current) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated).year(.twoDigits).locale(Locale(identifier: "en_AU"))
        style.timeZone = timeZone
        return date.formatted(style)
    }
}

/// Lunch's action colour: a deep teal that keeps white text, and text on white, readable (the app's bright teal tint
/// is too light for either).
enum LunchStyle {
    /// Fill for prominent buttons, with white text, in both appearances.
    static let fill = Color(red: 0.0, green: 0.42, blue: 0.47)
    /// Menu group headings: black or white, bolder than the system's muted section headers.
    static let heading = Color(UIColor { $0.userInterfaceStyle == .dark ? .white : .black })
    /// Text and icons: deep teal on light backgrounds, a lighter teal on dark ones.
    static let text = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.39, green: 0.82, blue: 0.87, alpha: 1) : UIColor(red: 0.0, green: 0.42, blue: 0.47, alpha: 1) })
}

/// A full-width button: prominent (white on deep teal) or secondary (grey, primary text). The label stretches, so the
/// button fills the width and its content sits in the middle.
struct LunchButton<Label: View>: View {
    var prominent = true
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    var body: some View {
        let content = Button(action: action) { label().frame(maxWidth: .infinity).foregroundStyle(prominent ? Color.white : .primary) }
            .controlSize(.large)
        if prominent { content.buttonStyle(.borderedProminent).tint(LunchStyle.fill) }
        else { content.buttonStyle(.bordered).tint(.secondary) }
    }
}

/// A section footer in Lunch's plain lists, small and grey like the rest of the app's notes.
struct LunchNote: View {
    let text: String
    var body: some View { Text(text).font(.footnote).foregroundStyle(.secondary).listRowSeparator(.hidden) }
}

/// The header's lunch balance; tapping it opens the Lunch tab.
struct LunchBalanceBadge: View {
    @EnvironmentObject private var model: AppModel
    let balance: Decimal
    var body: some View {
        Button { model.lunchOpenRequest = UUID() } label: {
            Text(balance.dollars).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
        }.buttonStyle(.plain)
            .accessibilityLabel("Lunch balance \(balance.dollars)").accessibilityHint("Opens lunch orders")
            .accessibilityIdentifier("lunch-balance")
    }
}

/// Lunch's loading indicator. My Student Account can take a while, so it keeps the wait light.
struct LunchLoadingIndicator: View {
    static let messages = [
        "Warming the pie warmer…", "Buttering the bread…", "Counting Michelin stars…", "Reviewing gastronomy…",
        "Peeling the mandarins…", "Toasting the sangas…", "Asking about sausage rolls…", "Slicing the banana bread…",
        "Reading the specials board…", "Polishing the lunchboxes…", "Tasting the gravy…"
    ]
    var body: some View {
        RotatingLoadingIndicator(messages: Self.messages, accessibilityLabel: "Loading lunch").accessibilityIdentifier("lunch-loading")
    }
}

/// The Lunch screen's shape while it first loads: grey bars where the text will be and greyed controls. Nothing in
/// it can be tapped, and VoiceOver skips it (the loading indicator speaks for it).
private struct LunchSkeleton: View {
    var body: some View {
        Group {
            Section {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Balance").font(.subheadline)
                        Text("$00.00").font(.largeTitle.weight(.bold))
                    }
                    Spacer(minLength: 0)
                    VStack(spacing: 8) { pill("Top up"); pill("Activity") }.frame(width: 136)
                }.padding(.top, 6).listRowSeparator(.hidden)
                VStack(alignment: .leading, spacing: 12) {
                    Capsule().fill(Color.secondary.opacity(0.16)).frame(height: 50)
                    Text("Upcoming").font(.footnote.weight(.semibold))
                }
                .listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 0, trailing: 16))
                row
            }
            Section { ForEach(0..<3, id: \.self) { _ in row } } header: { Text("Past orders") }
        }
        .redacted(reason: .placeholder).foregroundStyle(.secondary)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
    private func pill(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(Color.secondary.opacity(0.16), in: Capsule())
    }
    private var row: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack { Text("Wed, 12 Nov 26").font(.headline); Spacer(); Text("$9.50") }
            Text("Chicken wrap, Apple juice").font(.subheadline)
            Text("Order #2040").font(.caption)
        }.padding(.vertical, 2)
    }
}

private enum LunchRoute: Hashable { case chooseDay, order(CanteenDay), review, pastOrders }

/// Lunch: the child's balance, the days open for ordering, orders already placed, and recent account activity.
struct LunchView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var showAccounts: Bool
    @State private var path: [LunchRoute] = []
    @State private var menus: [CanteenMenuSummary] = []
    @State private var menuID: Int?
    @State private var menu: CanteenMenu?
    @State private var orders: [CanteenPastOrder] = []
    @State private var transactions: [CanteenTransaction] = []
    @State private var loading = false
    @State private var loadingMenu = false
    @State private var menuRequest = UUID()
    @State private var error: String?
    @State private var loadedKey: String?
    @State private var showTopUp = false
    @State private var showActivity = false
    @State private var showSignIn = false
    /// The order being built, carried from the day's menu to its review.
    @State private var draft: CanteenOrder?
    private var key: String { "\(model.accountID?.uuidString ?? "demo")-\(model.lunchAccount?.id ?? 0)" }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if model.lunchSignInNeeded {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.fill").foregroundStyle(.orange).accessibilityHidden(true)
                            Text("Your lunch-order sign-in has expired.").font(.subheadline)
                            Spacer(minLength: 8)
                            Button("Sign in again") { showSignIn = true }.font(.subheadline.weight(.semibold)).buttonStyle(.borderless)
                        }
                    }
                }
                // Nothing to act on until the whole screen has loaded (the menu, orders and activity), so a half-loaded
                // screen never offers New order or says "No lunch ordered yet". A refresh keeps what's showing.
                if let account = model.lunchAccount, loadedKey == key {
                    let today = CanteenDay(Date(), timeZone: menu?.timeZone ?? .current)
                    let upcoming = orders.filter { $0.day >= today }.sorted { $0.day < $1.day }
                    let past = orders.filter { $0.day < today }.sorted { $0.day > $1.day }
                    Section {
                        // The balance with what explains it: topping it up, and what it's been spent on (orders and
                        // the canteen counter).
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Balance").font(.subheadline).foregroundStyle(.secondary)
                                Text(account.balance.dollars).font(.largeTitle.weight(.bold)).monospacedDigit()
                                    .lineLimit(1).minimumScaleFactor(0.6)
                                    .accessibilityIdentifier("lunch-balance-amount")
                            }
                            Spacer(minLength: 0)
                            // Beside the balance rather than under it: vertical space is what a phone lacks.
                            if account.canRecharge || !transactions.isEmpty {
                                VStack(spacing: 8) {
                                    if account.canRecharge {
                                        balanceAction("Top up", symbol: "creditcard") { showTopUp = true }
                                            .accessibilityIdentifier("lunch-top-up")
                                    }
                                    if !transactions.isEmpty {
                                        balanceAction("Activity", symbol: "list.bullet") { showActivity = true }
                                            .accessibilityLabel("Account activity")
                                            .accessibilityIdentifier("lunch-account-activity")
                                    }
                                }.frame(width: 136)
                            }
                        }.padding(.top, 6).listRowSeparator(.hidden)
                        VStack(alignment: .leading, spacing: 12) {
                            LunchButton { path.append(.chooseDay) } label: { Label("New order", systemImage: "plus").fontWeight(.semibold) }
                                .disabled(menu == nil || loading || loadingMenu).accessibilityIdentifier("lunch-new-order")
                            Text("Upcoming").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                                .textCase(.uppercase).accessibilityAddTraits(.isHeader)
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 0, trailing: 16))
                        if upcoming.isEmpty { Text("No lunch ordered yet.").foregroundStyle(.secondary) }
                        ForEach(upcoming) { PastOrderRow(order: $0) }
                    }
                    if !past.isEmpty {
                        Section("Past orders") {
                            ForEach(past.prefix(3)) { PastOrderRow(order: $0) }
                            if past.count > 3 { NavigationLink("All past orders", value: LunchRoute.pastOrders) }
                        }
                    }
                } else if let child = model.child {
                    if error != nil {
                        // The error row below says what went wrong and offers to try again.
                    } else if showingSkeleton {
                        LunchSkeleton()
                    } else {
                        ContentUnavailableView("No lunch account for \(child.name)", systemImage: "fork.knife",
                                               description: Text("My Student Account doesn’t list an account with this child’s name."))
                    }
                } else { ChildPlaceholder() }
                if let error { ErrorRow(message: error) { await load() } }
            }
            .listStyle(.plain)
            // Over content that's already showing (a refresh, or another menu); a first load shows the row above.
            .overlay { if showingSkeleton || ((loading || loadingMenu) && loadedKey == key) { LunchLoadingIndicator() } }
            .navigationTitle("Lunch")
            .modifier(SchoolToolbar(showAccounts: $showAccounts))
            .navigationDestination(for: LunchRoute.self) { route in
                switch route {
                case .chooseDay:
                    List {
                        if menus.count > 1 {
                            Section { Picker("Menu", selection: $menuID) { ForEach(menus) { Text($0.name).tag(Optional($0.id)) } } }
                        }
                        orderSection.disabled(loading || loadingMenu)
                    }.listStyle(.plain).navigationTitle("New order").navigationBarTitleDisplayMode(.inline)
                        .overlay { if loading || loadingMenu { LunchLoadingIndicator() } }
                case .pastOrders:
                    let today = CanteenDay(Date(), timeZone: menu?.timeZone ?? .current)
                    List(orders.filter { $0.day < today }.sorted { $0.day > $1.day }) { PastOrderRow(order: $0) }.listStyle(.plain).navigationTitle("Past orders")
                case .order(let day):
                    if let menu, let account = model.lunchAccount {
                        // The most recent earlier order, whatever order the portal lists them in.
                        let lastOrder = orders.filter { $0.day < day }.max { $0.day < $1.day }
                        LunchOrderView(menu: menu, account: account, day: day, lastOrder: lastOrder, draft: $draft) {
                            path.append(.review)
                        }
                    }
                case .review:
                    if let menu, let account = model.lunchAccount, let draft {
                        LunchReviewView(menu: menu, account: account, order: draft) {
                            path = []; Task { await load(refreshing: true) }
                        }
                    }
                }
            }
            .task(id: key) { if loadedKey != key { await load() } }
            .onChange(of: menuID) { _, id in if let id, id != menu?.id { Task { await loadMenu(id) } } }
            .refreshable { await load(refreshing: true) }
            .sheet(isPresented: $showActivity) {
                NavigationStack {
                    List(transactions) { TransactionRow(transaction: $0) }
                        .listStyle(.plain).navigationTitle("Account activity").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showActivity = false } } }
                }
            }
            .sheet(isPresented: $showTopUp) {
                if let account = model.lunchAccount {
                    CanteenPageView(title: "Top up", url: model.canteenLink?.portal.rechargePage(account: account.id))
                }
            }
            .sheet(isPresented: $showSignIn, onDismiss: { Task { await load(refreshing: true) } }) {
                CanteenSignInView(portal: model.canteenLink?.portal)
            }
        }
    }

    @ViewBuilder private var orderSection: some View {
        Section {
            if let menu {
                let days = menu.orderableDays()
                if days.isEmpty {
                    Text("No days are open for ordering right now.").foregroundStyle(.secondary)
                }
                ForEach(days, id: \.self) { day in
                    let existing = orders.filter { $0.day == day }
                    NavigationLink(value: LunchRoute.order(day)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(day.title).font(.headline)
                            if !existing.isEmpty {
                                Label("Already ordered: \(existing.flatMap(\.lines).map(\.name).joined(separator: ", "))", systemImage: "checkmark.circle.fill")
                                    .font(.subheadline).foregroundStyle(LunchStyle.text).lineLimit(2)
                            } else if let deadline = menu.deadline(for: day) {
                                Text("Order by \(deadlineText(deadline))").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 2)
                    }.accessibilityIdentifier("lunch-day-\(day)")
                }
            } else if loading {
                ProgressView().frame(maxWidth: .infinity)
            }
        } header: { Text("Which day? · \(menu?.name ?? "Menu")") } footer: {
            if let description = menu?.description { LunchNote(text: description) }
        }
    }
    /// Top up and Activity: an identical pair of teal capsules, stacked beside the balance.
    private func balanceAction(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.subheadline.weight(.semibold)).foregroundStyle(LunchStyle.text)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.regular).tint(LunchStyle.text)
    }

    /// The first load: the screen's shape, greyed, until there's something real to act on.
    private var showingSkeleton: Bool {
        guard model.child != nil, error == nil, !(model.lunchAccount != nil && loadedKey == key) else { return false }
        return !model.lunchAccountsLoaded || loading || model.lunchAccount != nil
    }

    private func deadlineText(_ deadline: Date) -> String {
        let zone = menu?.timeZone ?? .current
        var time = Date.FormatStyle.dateTime.hour().minute().locale(Locale(identifier: "en_AU"))
        time.timeZone = zone
        return "\(CanteenDay.short(deadline, timeZone: zone)), \(deadline.formatted(time))"
    }

    private func load(refreshing: Bool = false) async {
        guard let service = model.canteenService else { return }
        loading = true; error = nil; defer { loading = false }
        if refreshing || !model.lunchAccountsLoaded { await model.refreshLunch() }
        guard let account = model.lunchAccount else { loadedKey = key; return }
        do {
            menus = try await model.withCanteenRenewal { try await service.menus(account: account.id) }
            let chosen = menus.first { $0.id == menuID } ?? menus.first
            menuID = chosen?.id
            if let chosen { await loadMenu(chosen.id) } else { menu = nil }
            async let history = model.withCanteenRenewal { try await service.orderHistory(account: account.id) }
            async let activity = model.withCanteenRenewal { try await service.transactions(account: account.id) }
            orders = try await history; transactions = try await activity
            loadedKey = key
        } catch is CancellationError {
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func loadMenu(_ id: Int) async {
        guard let service = model.canteenService, let account = model.lunchAccount else { return }
        let request = UUID(), selection = key
        menuRequest = request; loadingMenu = true
        defer { if menuRequest == request { loadingMenu = false } }
        do {
            let loaded = try await model.withCanteenRenewal { try await service.menu(account: account.id, menu: id) }
            guard request == menuRequest, selection == key, menuID == id, !Task.isCancelled else { return }
            menu = loaded
        } catch { if !Task.isCancelled, request == menuRequest { self.error = error.localizedDescription } }
    }
}

/// One day's menu: choose items and quantities, then review.
private struct LunchOrderView: View {
    @EnvironmentObject private var model: AppModel
    let account: CanteenAccount
    let day: CanteenDay
    let lastOrder: CanteenPastOrder?
    @Binding var draft: CanteenOrder?
    let review: () -> Void
    @State private var menu: CanteenMenu
    @State private var order: CanteenOrder
    @State private var loadingAvailability = true
    init(menu: CanteenMenu, account: CanteenAccount, day: CanteenDay, lastOrder: CanteenPastOrder?, draft: Binding<CanteenOrder?>, review: @escaping () -> Void) {
        self.account = account; self.day = day; self.lastOrder = lastOrder; _draft = draft; self.review = review
        _menu = State(initialValue: menu)
        let carried = draft.wrappedValue.flatMap { $0.day == day ? $0 : nil }
        _order = State(initialValue: carried ?? CanteenOrder(day: day, option: menu.options.first))
    }
    private var groups: [CanteenMenu.Group] { menu.groups(on: day) }
    /// The previous order's items, when every one of them is on today's menu.
    private var repeatable: [(CanteenMenu.Item, CanteenPastOrder.Line)]? {
        guard let lastOrder, order.isEmpty else { return nil }
        let items = groups.flatMap(\.items)
        let matched = lastOrder.lines.compactMap { line in
            items.first { CanteenMenu.tidyName($0.name) == CanteenMenu.tidyName(line.name) && !$0.isSoldOut && !$0.hasModifiers }.map { ($0, line) }
        }
        return matched.count == lastOrder.lines.count && !matched.isEmpty ? matched : nil
    }
    var body: some View {
        List {
            if menu.options.count > 1 {
                Section {
                    Picker("Sitting", selection: Binding(get: { order.option?.id }, set: { id in order.option = menu.options.first { $0.id == id } })) {
                        ForEach(menu.options) { option in
                            Text(option.surcharge > 0 ? "\(option.name) (+\(option.surcharge.dollars))" : option.name).tag(Optional(option.id))
                        }
                    }
                }
            }
            if let repeatable {
                Section {
                    Button {
                        order.lines = repeatable.map { item, line in
                            CanteenOrder.Line(groupID: item.groupID, itemID: item.id, name: item.name, price: item.price,
                                              quantity: min(line.quantity, item.maximumQuantity ?? line.quantity), note: item.takesNote ? line.note ?? "" : "")
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Label("Same as last time", systemImage: "arrow.clockwise")
                            Text(repeatable.map { "\($0.1.quantity > 1 ? "\($0.1.quantity) × " : "")\($0.0.name)" }.joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.accessibilityIdentifier("lunch-repeat")
                }
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.items) { item in ItemRow(item: item, order: $order) }
                } header: {
                    // A real section header, so it stays pinned while its items scroll; styled bold and black/white
                    // rather than the system's muted grey.
                    Text(group.name).font(.headline.weight(.bold)).foregroundStyle(LunchStyle.heading).textCase(nil)
                        .padding(.vertical, 4).accessibilityAddTraits(.isHeader)
                }
            }
        }
        .listStyle(.plain)
        .disabled(loadingAvailability)
        .navigationTitle(day.longTitle).navigationBarTitleDisplayMode(.inline)
        .overlay {
            if loadingAvailability {
                ProgressView("Checking availability…").padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("lunch-availability-loading")
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(order.total.dollars).font(.headline).monospacedDigit()
                    Text("\(account.balance.dollars) available").font(.caption).foregroundStyle(order.total > account.balance ? .red : .secondary)
                }
                Spacer()
                Button { draft = order; review() } label: { Text("Review order").fontWeight(.semibold) }
                    .buttonStyle(.borderedProminent).tint(LunchStyle.fill).controlSize(.large)
                    .disabled(order.isEmpty || loadingAvailability).accessibilityIdentifier("lunch-review")
            }.padding().background(.bar)
        }
        .task {
            loadingAvailability = true
            defer { loadingAvailability = false }
            guard let service = model.canteenService,
                  let remaining = try? await model.withCanteenRenewal({ try await service.remaining(account: account.id, menu: menu.id, day: day) }) else { return }
            menu.apply(remaining: remaining)
        }
    }
}

private struct ItemRow: View {
    let item: CanteenMenu.Item
    @Binding var order: CanteenOrder
    private var index: Int? { order.lines.firstIndex { $0.itemID == item.id && $0.groupID == item.groupID } }
    private var quantity: Int { index.map { order.lines[$0].quantity } ?? 0 }
    private var limit: Int { min(item.maximumQuantity ?? 9, 9) }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                    if let description = item.description, description != item.name {
                        Text(description).font(.caption).foregroundStyle(.secondary)
                    }
                    if item.hasModifiers {
                        Text("Has options – order this on the website").font(.caption).foregroundStyle(.orange)
                    } else if item.isSoldOut {
                        Text("Sold out").font(.caption).foregroundStyle(.red)
                    } else if let max = item.maximumQuantity, max <= 5 {
                        Text("\(max) left").font(.caption).foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 8)
                Text(item.price.dollars).monospacedDigit().foregroundStyle(.secondary)
                if !item.hasModifiers && !item.isSoldOut {
                    HStack(spacing: 4) {
                        if quantity > 0 {
                            Button { change(-1) } label: { Image(systemName: "minus.circle.fill") }
                                .accessibilityLabel("Remove one \(item.name)")
                            Text("\(quantity)").monospacedDigit().frame(minWidth: 16)
                        }
                        Button { change(1) } label: { Image(systemName: "plus.circle.fill") }
                            .disabled(quantity >= limit).accessibilityLabel("Add \(item.name)")
                    }.font(.title2).buttonStyle(.borderless).foregroundStyle(LunchStyle.text)
                }
            }
            if quantity > 0, item.takesNote, let index {
                TextField("Note for the canteen", text: $order.lines[index].note).font(.subheadline).textFieldStyle(.roundedBorder)
            }
        }.padding(.vertical, 2)
            .accessibilityElement(children: .contain)
    }
    private func change(_ by: Int) {
        if let index {
            order.lines[index].quantity = max(0, min(limit, order.lines[index].quantity + by))
            if order.lines[index].quantity == 0 { order.lines.remove(at: index) }
        } else if by > 0 {
            order.lines.append(CanteenOrder.Line(groupID: item.groupID, itemID: item.id, name: item.name, price: item.price, quantity: 1))
        }
    }
}

/// The portal checks the order, then it's paid from the account balance.
private struct LunchReviewView: View {
    @EnvironmentObject private var model: AppModel
    let menu: CanteenMenu
    let account: CanteenAccount
    let order: CanteenOrder
    let done: () -> Void
    @State private var checking = true
    @State private var problems: [String] = []
    @State private var paying = false
    @State private var error: String?
    @State private var orderNumbers: [String]?
    @State private var payingByCard = false
    /// The balance as last read, so a card top-up made from here shows straight away.
    private var balance: Decimal { model.lunchAccount.flatMap { $0.id == account.id ? $0.balance : nil } ?? account.balance }
    private var affordable: Bool { order.total <= balance }
    /// What a card needs to add: the shortfall, or the whole order when the balance already covers it (some parents
    /// would rather pay each order by card).
    private var cardAmount: Decimal { affordable ? order.total : order.total - balance }
    private var offersCard: Bool { account.canRecharge && menu.allowsCardPayment }
    var body: some View {
        List {
            if let orderNumbers {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(LunchStyle.text)
                        Text("Lunch ordered").font(.title2.weight(.semibold))
                        Text("\(order.day.longTitle) · Order \(orderNumbers.map { "#\($0)" }.joined(separator: ", "))")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity).padding(.vertical, 20)
                        .accessibilityElement(children: .combine).accessibilityIdentifier("lunch-ordered")
                }
                Section { LunchButton(action: done) { Text("Done").fontWeight(.semibold) }.listRowSeparator(.hidden) }
            } else {
                Section {
                    ForEach(order.lines.filter { $0.quantity > 0 }) { line in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.quantity > 1 ? "\(line.quantity) × \(line.name)" : line.name)
                                if !line.note.isEmpty { Text(line.note).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Text(line.total.dollars).monospacedDigit()
                        }
                    }
                    if let option = order.option, option.surcharge > 0 {
                        LabeledContent("\(option.name) surcharge", value: option.surcharge.dollars)
                    }
                    HStack { Text("Total").fontWeight(.semibold); Spacer(); Text(order.total.dollars).monospacedDigit().fontWeight(.semibold) }
                } header: { Text([order.day.longTitle, menu.options.count > 1 ? order.option?.name : nil].compactMap { $0 }.joined(separator: " · ")) }
                Section {
                    HStack { Text("Balance"); Spacer(); Text(balance.dollars).monospacedDigit() }.foregroundStyle(.secondary)
                    HStack { Text("After this order"); Spacer(); Text((balance - order.total).dollars).monospacedDigit() }
                        .foregroundStyle(affordable ? Color.primary : .red)
                } footer: {
                    if !affordable { LunchNote(text: "There isn’t enough in the account. Pay by card to top up \(cardAmount.dollars); the order will be waiting here.") }
                }
                if checking {
                    Section { HStack { ProgressView(); Text("Checking with the canteen…").foregroundStyle(.secondary) } }
                }
                if !problems.isEmpty || error != nil {
                    Section {
                        ForEach(problems + [error].compactMap { $0 }, id: \.self) { Label($0, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                    }
                }
                if offersCard {
                    Section {} footer: {
                        LunchNote(text: "Paying by card opens My Student Account’s own page, where your card details go straight to the canteen. Top up the amount shown, tap Done, then pay from the balance. The canteen may add a card fee.")
                    }
                }
            }
        }
        .listStyle(.plain)
        .safeAreaInset(edge: .bottom) {
            if orderNumbers == nil {
                VStack(spacing: 10) {
                    LunchButton { Task { await pay() } } label: {
                        if paying { ProgressView().tint(.white) } else {
                            VStack(spacing: 1) {
                                Text("Pay \(order.total.dollars) from balance").fontWeight(.semibold)
                                Text("\(balance.dollars) available").font(.caption)
                            }
                        }
                    }
                        .disabled(!affordable || checking || paying || !problems.isEmpty).accessibilityIdentifier("lunch-pay")
                    if offersCard {
                        LunchButton(prominent: false) { payingByCard = true } label: {
                            VStack(spacing: 1) {
                                Label("Pay by card", systemImage: "creditcard").fontWeight(.semibold)
                                Text("Tops up \(cardAmount.dollars) on the canteen’s page").font(.caption)
                            }
                        }
                            .disabled(checking || paying || !problems.isEmpty).accessibilityIdentifier("lunch-pay-card")
                    }
                }.padding().background(.bar)
            }
        }
        .navigationTitle(orderNumbers == nil ? "Review" : "Ordered").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(orderNumbers != nil || paying)
        .task { await verify() }
        .sheet(isPresented: $payingByCard) {
            CanteenPageView(title: "Pay by card", url: model.canteenLink?.portal.rechargePage(account: account.id),
                            note: "Top up \(cardAmount.dollars), then tap Done to finish your order.")
        }
    }
    private func verify() async {
        guard let service = model.canteenService else { return }
        checking = true; error = nil; defer { checking = false }
        do { problems = try await model.withCanteenRenewal { try await service.verify(order, account: account.id, menu: menu.id) } }
        catch { self.error = error.localizedDescription }
    }
    private func pay() async {
        guard let service = model.canteenService, !paying else { return }
        paying = true; error = nil; defer { paying = false }
        do {
            orderNumbers = try await model.withCanteenRenewal(retry: false) { try await service.place(order, account: account.id, menu: menu.id) }
            await model.refreshLunch()
        } catch {
            self.error = "\(error.localizedDescription) Check Upcoming on the Lunch screen before trying again."
        }
    }
}

private struct PastOrderRow: View {
    let order: CanteenPastOrder
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(order.day.title).font(.headline)
                Spacer()
                Text(order.total.dollars).monospacedDigit().foregroundStyle(.secondary)
            }
            Text(order.lines.map { ($0.quantity > 1 ? "\($0.quantity) × " : "") + $0.name + ($0.note.map { " (\($0))" } ?? "") }.joined(separator: ", "))
                .font(.subheadline).foregroundStyle(.secondary)
            Text("Order #\(order.number)").font(.caption).foregroundStyle(.tertiary)
        }.padding(.vertical, 2).accessibilityElement(children: .combine)
    }
}

private struct TransactionRow: View {
    let transaction: CanteenTransaction
    private var title: String {
        switch transaction.kind {
        case .order(_, let day): return day.map { "Lunch for \($0.title)" } ?? "Lunch order"
        case .deposit: return "Top up"
        case .fee: return "Card fee"
        case .purchase: return "Canteen counter"
        case .other: return transaction.description
        }
    }
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if !transaction.items.isEmpty {
                    Text(transaction.items.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Text(transaction.date.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits).hour().minute().locale(Locale(identifier: "en_AU")))).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            Text((transaction.amount > 0 ? "+" : "") + transaction.amount.dollars).monospacedDigit()
                .foregroundStyle(transaction.amount > 0 ? LunchStyle.text : .primary)
        }.accessibilityElement(children: .combine)
    }
}

extension CanteenMenu {
    /// Item names compared loosely: the portal's history and menu differ in case and spacing.
    static func tidyName(_ name: String) -> String {
        name.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
