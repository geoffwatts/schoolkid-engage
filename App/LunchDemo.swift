import Foundation
import CanteenKit

/// A pretend lunch-order portal for the demo: two children, a week's menu, and orders that are "placed" in memory.
actor DemoCanteen: CanteenService {
    private var balances: [Int: Decimal] = [1: Decimal(string: "18.50")!, 2: Decimal(string: "6.00")!]
    private var placed: [Int: [CanteenPastOrder]] = [:]
    private var nextNumber = 2041

    func accounts() async throws -> [CanteenAccount] {
        [CanteenAccount(id: 1, name: "Alex Morgan", reference: "1000000000011", balance: balances[1]!, canOrder: true, canRecharge: true),
         CanteenAccount(id: 2, name: "Sam Morgan", reference: "1000000000012", balance: balances[2]!, canOrder: true, canRecharge: true)]
    }
    func menus(account: Int) async throws -> [CanteenMenuSummary] { [CanteenMenuSummary(id: 1, name: "Term 4 Menu")] }
    func menu(account: Int, menu: Int) async throws -> CanteenMenu {
        try CanteenMenu(msaJSON: JSONDecoder().decode(JSONValue.self, from: Data(Self.menuJSON(balance: balances[account] ?? 0).utf8)))
    }
    func remaining(account: Int, menu: Int, day: CanteenDay) async throws -> [CanteenRemaining] {
        [CanteenRemaining(groupID: 1, itemID: 13, available: 3)]
    }
    func verify(_ order: CanteenOrder, account: Int, menu: Int) async throws -> [String] { [] }
    func place(_ order: CanteenOrder, account: Int, menu: Int) async throws -> [String] {
        guard (balances[account] ?? 0) >= order.total else { throw CanteenError.insufficientFunds }
        try await Task.sleep(for: .milliseconds(600))
        balances[account, default: 0] -= order.total
        nextNumber += 1
        let lines = order.lines.filter { $0.quantity > 0 }.map {
            CanteenPastOrder.Line(name: $0.name, note: $0.note.isEmpty ? nil : $0.note, quantity: $0.quantity, price: $0.price)
        }
        placed[account, default: []].insert(CanteenPastOrder(number: String(nextNumber), day: order.day, lines: lines, total: order.total), at: 0)
        return [String(nextNumber)]
    }
    func transactions(account: Int) async throws -> [CanteenTransaction] {
        let now = Date()
        let mine = placed[account] ?? []
        var balance = balances[account] ?? 0
        var list: [CanteenTransaction] = mine.enumerated().map { index, order in
            defer { balance += order.total }
            return CanteenTransaction(id: 100 + index, date: now, description: "Online Order Ref#: \(order.number)", kind: .order(number: order.number, forDay: order.day),
                                      items: order.lines.map { "\($0.quantity) x \($0.name)" }, credit: nil, debit: order.total, balance: balance)
        }
        list += [
            CanteenTransaction(id: 1, date: now.addingTimeInterval(-3 * 86_400), description: "Online Order Ref#: 2040", kind: .order(number: "2040", forDay: nil),
                               items: ["1 x Chicken wrap", "1 x Apple juice"], credit: nil, debit: Decimal(string: "9.50"), balance: balance),
            CanteenTransaction(id: 2, date: now.addingTimeInterval(-3 * 86_400 - 60), description: "Online Deposit", kind: .deposit,
                               items: [], credit: 20, debit: nil, balance: balance + Decimal(string: "9.50")!),
            CanteenTransaction(id: 3, date: now.addingTimeInterval(-6 * 86_400), description: "Purchase/Refund/Deposit", kind: .purchase,
                               items: ["1 x Fruit cup"], credit: nil, debit: 3, balance: balance + Decimal(string: "-10.50")!)
        ]
        return list
    }
    func orderHistory(account: Int) async throws -> [CanteenPastOrder] {
        let history = (0..<5).map { index in
            CanteenPastOrder(number: String(2040 - index),
                             day: CanteenDay(Date().addingTimeInterval(Double(-3 - index) * 86_400), timeZone: .current),
                             lines: [.init(name: "Chicken wrap", note: nil, quantity: 1, price: 6),
                                     .init(name: "Apple juice", note: nil, quantity: 1, price: Decimal(string: "3.50")!)],
                             total: Decimal(string: "9.50")!)
        }
        return (placed[account] ?? []) + history
    }

    /// A menu whose first orderable day is the next weekday (today, before 9 am).
    private static func menuJSON(balance: Decimal) -> String {
        let zone = TimeZone.current
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        var day = Date()
        if calendar.component(.hour, from: day) >= 9 { day = calendar.date(byAdding: .day, value: 1, to: day)! }
        while [1, 7].contains(calendar.component(.weekday, from: day)) { day = calendar.date(byAdding: .day, value: 1, to: day)! }
        let first = CanteenDay(day, timeZone: zone)
        let offset = zone.secondsFromGMT(for: day), sign = offset < 0 ? "-" : "+"
        let cutOff = "\(first)T09:00:00\(sign)\(String(format: "%02d:%02d", abs(offset) / 3600, abs(offset) % 3600 / 60))"
        func item(_ id: Int, _ name: String, _ description: String?, _ price: Double, days: Int = 0, note: Bool = false) -> String {
            #"{"id":\#(id),"name":"\#(name)","description":\#(description.map { "\"\($0)\"" } ?? "null"),"availability":\#(days),"dailySalesLimit":-1,"dailyPurchaseLimit":-1,"diminish":false,"diminishQty":0,"itemType":1,"stockOnHand":0,"allowBackorder":true,"price":\#(price),"enableNote":\#(note),"enableModifiers":false}"#
        }
        let hot = [item(11, "Veggie pie", "Flaky pastry, seasonal vegetables", 5.5), item(12, "Chicken wrap", "Grilled chicken, lettuce, mayo", 6, note: true),
                   item(13, "Pasta bake", "Tomato and cheese, made on site", 7, days: 1 | 4), item(14, "Fish and chips", "Oven-baked, lemon wedge", 7, days: 16),
                   item(15, "Sushi pack", "Five pieces, gluten free", 8, days: 2 | 8)]
        let snacks = [item(21, "Fruit cup", nil, 3), item(22, "Banana bread", "Baked this morning", 4), item(23, "Cookie", nil, 1)]
        let drinks = [item(31, "Water 600ml", nil, 2.5), item(32, "Apple juice", "250 ml", 3.5), item(33, "Chocolate milk", "300 ml", 3.5)]
        return """
        {"allowedPayments":3,"allowFavourites":false,"accountBalance":\(balance),
         "menu":{"id":1,"type":0,"name":"Term 4 Menu","description":"Order by 9 am on the day.","cutOff":"\(cutOff)","cutOffDays":0,
           "advancedOrderLimit":6,"dayMon":true,"dayTue":true,"dayWed":true,"dayThu":true,"dayFri":true,"daySat":false,"daySun":false,
           "menuStart":null,"menuEnd":null,"discount":0,"disableCCPayment":false,"specificDates":[],"excludedDates":[]},
         "menuOptions":[{"id":1,"name":"Lunch","surcharge":0}],
         "menuGroups":[{"id":1,"name":"Hot food","items":[\(hot.joined(separator: ","))]},
                       {"id":2,"name":"Snacks","items":[\(snacks.joined(separator: ","))]},
                       {"id":3,"name":"Drinks","items":[\(drinks.joined(separator: ","))]}]}
        """
    }
}
