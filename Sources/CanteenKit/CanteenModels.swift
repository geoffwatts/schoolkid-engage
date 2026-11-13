import Foundation

// Lunch orders and student balances, independent of the canteen provider. Providers (My Student Account, in MSA/)
// read their portal into these models and implement `CanteenService`.

public enum CanteenError: Error, LocalizedError, Equatable {
    case invalidPortalURL, signInRequired, server(Int), schema(String), rejected(String), insufficientFunds
    public var errorDescription: String? {
        switch self {
        case .invalidPortalURL: return "Enter the HTTPS address of your school's My Student Account site."
        case .signInRequired: return "Your lunch-order sign-in has expired. Sign in again."
        case .server(let status): return "The lunch-order site returned status \(status)."
        case .schema(let detail): return "The lunch-order site's response isn't supported yet: \(detail)."
        case .rejected(let message): return message
        case .insufficientFunds: return "There isn't enough money in this account. Top it up first."
        }
    }
}

/// A day in the school's own calendar, independent of the device's time zone.
public struct CanteenDay: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int, month: Int, day: Int
    public init(year: Int, month: Int, day: Int) { self.year = year; self.month = month; self.day = day }
    /// Reads the leading `yyyy-MM-dd` of a portal date such as `2026-12-04T00:00:00` or `2026-11-13T09:00:00+08:00`.
    public init?(iso text: String) {
        let parts = text.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }
    /// Reads `dd/MM/yyyy`, as the portal's HTML pages write dates.
    public init?(slashed text: String) {
        let parts = text.trimmingCharacters(in: .whitespaces).prefix(10).split(separator: "/").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[2], month: parts[1], day: parts[0])
    }
    public init(_ date: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }
    private static var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private var utcDate: Date { Self.utc.date(from: DateComponents(year: year, month: month, day: day))! }
    /// 1 = Sunday … 7 = Saturday, as `Calendar` numbers weekdays.
    public var weekday: Int { Self.utc.component(.weekday, from: utcDate) }
    public func adding(days: Int) -> CanteenDay { CanteenDay(Self.utc.date(byAdding: .day, value: days, to: utcDate)!, timeZone: TimeZone(identifier: "UTC")!) }
    /// Midnight at the start of this day in the given time zone.
    public func start(in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
    /// For display with a date formatter: noon on this day in the device's calendar, so no time zone shifts the day.
    public var displayDate: Date { Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))! }
    /// `dd/MM/yyyy`, as the portal's per-day availability request takes it.
    public var slashed: String { String(format: "%02d/%02d/%04d", day, month, year) }
    /// `yyyy-M-d` without padding, exactly as the portal's own client sends an order date.
    public var orderDate: String { "\(year)-\(month)-\(day)" }
    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }
    public static func < (a: CanteenDay, b: CanteenDay) -> Bool { (a.year, a.month, a.day) < (b.year, b.month, b.day) }
}

/// One student's account, from the portal's account list.
public struct CanteenAccount: Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let reference: String
    public let balance: Decimal
    public let canOrder: Bool
    public let canRecharge: Bool
    public init(id: Int, name: String, reference: String, balance: Decimal, canOrder: Bool, canRecharge: Bool) {
        self.id = id; self.name = name; self.reference = reference; self.balance = balance; self.canOrder = canOrder; self.canRecharge = canRecharge
    }
    /// Whether this is the named child: names compared without case, accents or extra spaces.
    public func matches(childName: String) -> Bool { Self.normalised(name) == Self.normalised(childName) }
    static func normalised(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { $0.isWhitespace || $0 == "," }).sorted().joined(separator: " ")
    }
}

/// A menu that can be ordered from, as listed on an account's ordering page.
public struct CanteenMenuSummary: Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public init(id: Int, name: String) { self.id = id; self.name = name }
}

/// A menu with its ordering rules, items and the account's balance.
public struct CanteenMenu: Sendable {
    public struct Option: Identifiable, Hashable, Sendable {
        public let id: Int, name: String, surcharge: Decimal
    }
    public struct Item: Identifiable, Hashable, Sendable {
        public let id: Int
        public let groupID: Int
        public let name: String
        public let description: String?
        public let price: Decimal
        /// Weekdays the item is sold, as the portal's bit mask: Mon 1, Tue 2, Wed 4, Thu 8, Fri 16, Sat 32, Sun 64; 0 is every day.
        public let availability: Int
        let isStockItem: Bool
        let stockOnHand: Int
        let allowBackorder: Bool
        let diminishQuantity: Int?
        /// Remaining sales for the day (-1 unlimited); replaced by the per-day figure once that's loaded.
        public var dailySalesLimit: Int
        let dailyPurchaseLimit: Int
        public let takesNote: Bool
        /// Items with modifiers (choices such as a sauce) need a screen this app doesn't offer yet.
        public let hasModifiers: Bool
        public func isSold(on day: CanteenDay) -> Bool {
            guard availability != 0 else { return true }
            let bit = [1: 64, 2: 1, 3: 2, 4: 4, 5: 8, 6: 16, 7: 32][day.weekday]!
            return availability & bit != 0
        }
        /// The most that can be ordered, following the portal's own limits; nil for no limit.
        public var maximumQuantity: Int? {
            var limits: [Int] = []
            if isStockItem && !allowBackorder { limits.append(stockOnHand) }
            if let diminishQuantity { limits.append(diminishQuantity) }
            if dailySalesLimit >= 0 { limits.append(dailySalesLimit) }
            if dailyPurchaseLimit >= 0 { limits.append(dailyPurchaseLimit) }
            return limits.min().map { max(0, $0) }
        }
        public var isSoldOut: Bool { maximumQuantity == 0 }
    }
    public struct Group: Identifiable, Hashable, Sendable {
        public let id: Int, name: String
        public var items: [Item]
    }
    public let id: Int
    public let name: String
    public let description: String?
    /// A standard menu is ordered for a date; others (rare) have no date.
    public let isStandard: Bool
    /// The deadline for the earliest day that can still be ordered, in the school's time.
    public let cutOff: Date?
    public let cutOffDays: Int
    public let advancedOrderLimit: Int
    public let weekdays: Set<Int>
    public let firstDay: CanteenDay?
    public let menuStart: CanteenDay?, menuEnd: CanteenDay?
    public let specificDates: Set<CanteenDay>, excludedDates: Set<CanteenDay>
    public let timeZone: TimeZone
    public let options: [Option]
    public var groups: [Group]
    public let balance: Decimal
    public let allowsCardPayment: Bool

    /// The days this menu can still be ordered for, earliest first, following the portal's date picker: from the
    /// cut-off day up to the advance-order limit (or the menu's end), on the menu's weekdays, skipping excluded dates.
    public func orderableDays(now: Date = Date(), searchingDays: Int = 21) -> [CanteenDay] {
        guard isStandard else { return [] }
        let today = CanteenDay(now, timeZone: timeZone)
        var first = firstDay ?? today
        if let menuStart, menuStart > first { first = menuStart }
        var last: CanteenDay?
        if advancedOrderLimit > 0 { last = (firstDay ?? today).adding(days: advancedOrderLimit) }
        if let menuEnd { last = last.map { min($0, menuEnd) } ?? menuEnd }
        var days: [CanteenDay] = []
        var day = first
        for _ in 0..<searchingDays {
            if let last, day > last { break }
            if day >= today, isOpen(on: day), deadline(for: day).map({ $0 > now }) ?? true { days.append(day) }
            day = day.adding(days: 1)
        }
        return days
    }
    func isOpen(on day: CanteenDay) -> Bool {
        if !specificDates.isEmpty { return specificDates.contains(day) && !excludedDates.contains(day) }
        return weekdays.contains(day.weekday) && !excludedDates.contains(day)
    }
    /// When orders for a day close: the cut-off time of day, `cutOffDays` before the day.
    public func deadline(for day: CanteenDay) -> Date? {
        guard let cutOff else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let time = calendar.dateComponents([.hour, .minute, .second], from: cutOff)
        let start = day.adding(days: -cutOffDays).start(in: timeZone)
        return calendar.date(byAdding: time, to: start)
    }
    /// The groups and items sold on a day, without empty groups.
    public func groups(on day: CanteenDay) -> [Group] {
        groups.map { group in Group(id: group.id, name: group.name, items: group.items.filter { $0.isSold(on: day) }) }
            .filter { !$0.items.isEmpty }
    }
    /// Applies a day's remaining quantities (`order/getmenuitemsbydate`) to the items' daily limits.
    public mutating func apply(remaining: [CanteenRemaining]) {
        for entry in remaining {
            guard let g = groups.firstIndex(where: { $0.id == entry.groupID }),
                  let i = groups[g].items.firstIndex(where: { $0.id == entry.itemID }) else { continue }
            groups[g].items[i].dailySalesLimit = entry.available
        }
    }
    public func item(group: Int, id: Int) -> Item? { groups.first { $0.id == group }?.items.first { $0.id == id } }
}

/// How many of an item can still be sold on a day.
public struct CanteenRemaining: Hashable, Sendable {
    public let groupID: Int, itemID: Int, available: Int
    public init(groupID: Int, itemID: Int, available: Int) { self.groupID = groupID; self.itemID = itemID; self.available = available }
}

/// One day's order: one date and sitting, with its items. A portal may take several dates at once; this app orders a
/// single day at a time.
public struct CanteenOrder: Sendable, Equatable {
    public struct Line: Identifiable, Sendable, Equatable {
        public let id: String
        public let groupID: Int, itemID: Int
        public var name: String
        public var price: Decimal
        public var quantity: Int
        public var note: String
        public init(groupID: Int, itemID: Int, name: String, price: Decimal, quantity: Int, note: String = "") {
            id = UUID().uuidString.lowercased(); self.groupID = groupID; self.itemID = itemID
            self.name = name; self.price = price; self.quantity = quantity; self.note = note
        }
        public var total: Decimal { price * Decimal(quantity) }
    }
    public let id: String
    public let day: CanteenDay
    public var option: CanteenMenu.Option?
    public var lines: [Line]
    public init(day: CanteenDay, option: CanteenMenu.Option?, lines: [Line] = []) {
        id = UUID().uuidString.lowercased(); self.day = day; self.option = option; self.lines = lines
    }
    public var total: Decimal { lines.reduce(option?.surcharge ?? 0) { $0 + $1.total } }
    public var isEmpty: Bool { !lines.contains { $0.quantity > 0 } }
}

/// A line of an account's transaction history.
public struct CanteenTransaction: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable { case order(number: String, forDay: CanteenDay?), deposit, fee, purchase, other }
    public let id: Int
    public let date: Date
    public let description: String
    public let kind: Kind
    public let items: [String]
    public let credit: Decimal?, debit: Decimal?, balance: Decimal?
    public init(id: Int, date: Date, description: String, kind: Kind, items: [String], credit: Decimal?, debit: Decimal?, balance: Decimal?) {
        self.id = id; self.date = date; self.description = description; self.kind = kind; self.items = items
        self.credit = credit; self.debit = debit; self.balance = balance
    }
    /// Signed: positive for money in.
    public var amount: Decimal { (credit ?? 0) - (debit ?? 0) }
}

/// An order from the account's order history.
public struct CanteenPastOrder: Identifiable, Hashable, Sendable {
    public struct Line: Hashable, Sendable {
        public let name: String, note: String?, quantity: Int, price: Decimal
        public init(name: String, note: String?, quantity: Int, price: Decimal) { self.name = name; self.note = note; self.quantity = quantity; self.price = price }
    }
    public let number: String
    public let day: CanteenDay
    public let lines: [Line]
    public let total: Decimal
    public init(number: String, day: CanteenDay, lines: [Line], total: Decimal) { self.number = number; self.day = day; self.lines = lines; self.total = total }
    public var id: String { number }
}
