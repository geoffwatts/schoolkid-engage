import Foundation

// Reading My Student Account's JSON and HTML into the canteen models, and writing orders the way its client does.

extension CanteenMenu {
    /// A menu from `order/getmenu`.
    public init(msaJSON json: JSONValue) throws {
        let menu = json["menu"]
        guard let id = Self.int(menu["id"]) else { throw CanteenError.schema("menu without an ID") }
        self.id = id
        name = menu["name"].string.map(Self.tidy) ?? "Menu"
        description = menu["description"].string.map(Self.tidy).flatMap { $0.isEmpty ? nil : $0 }
        isStandard = Self.int(menu["type"]) == 0
        let cutOffText = menu["cutOff"].string
        timeZone = cutOffText.flatMap(Self.offset) ?? TimeZone(identifier: "Australia/Perth")!
        cutOff = cutOffText.flatMap(Self.moment)
        firstDay = cutOffText.flatMap(CanteenDay.init(iso:))
        cutOffDays = Self.int(menu["cutOffDays"]) ?? 0
        advancedOrderLimit = Self.int(menu["advancedOrderLimit"]) ?? 0
        let days = ["daySun", "dayMon", "dayTue", "dayWed", "dayThu", "dayFri", "daySat"]
        weekdays = Set(days.enumerated().compactMap { menu[$0.element].bool == true ? $0.offset + 1 : nil })
        menuStart = menu["menuStart"].string.flatMap(CanteenDay.init(iso:))
        menuEnd = menu["menuEnd"].string.flatMap(CanteenDay.init(iso:))
        specificDates = Set((menu["specificDates"].array ?? []).compactMap { $0.string.flatMap(CanteenDay.init(iso:)) })
        excludedDates = Set((menu["excludedDates"].array ?? []).compactMap { $0.string.flatMap(CanteenDay.init(iso:)) })
        allowsCardPayment = menu["disableCCPayment"].bool != true
        balance = Self.money(json["accountBalance"]) ?? 0
        options = (json["menuOptions"].array ?? []).compactMap { option in
            Self.int(option["id"]).map { Option(id: $0, name: option["name"].string.map(Self.tidy) ?? "Order", surcharge: Self.money(option["surcharge"]) ?? 0) }
        }
        groups = (json["menuGroups"].array ?? []).compactMap { group in
            guard let groupID = Self.int(group["id"]) else { return nil }
            let items: [Item] = (group["items"].array ?? []).compactMap { item in
                guard let itemID = Self.int(item["id"]), let price = Self.money(item["price"]) else { return nil }
                let diminish = item["diminish"].bool == true
                return Item(id: itemID, groupID: groupID, name: item["name"].string.map(Self.tidy) ?? "Item",
                            description: item["description"].string.map(Self.tidy).flatMap { $0.isEmpty ? nil : $0 },
                            price: price, availability: Self.int(item["availability"]) ?? 0,
                            isStockItem: Self.int(item["itemType"]) == 2, stockOnHand: Self.int(item["stockOnHand"]) ?? 0,
                            allowBackorder: item["allowBackorder"].bool ?? true,
                            diminishQuantity: diminish ? Self.int(item["diminishQty"]) ?? 0 : nil,
                            dailySalesLimit: Self.int(item["dailySalesLimit"]) ?? -1, dailyPurchaseLimit: Self.int(item["dailyPurchaseLimit"]) ?? -1,
                            takesNote: item["enableNote"].bool == true, hasModifiers: item["enableModifiers"].bool == true)
            }
            return Group(id: groupID, name: group["name"].string.map(Self.tidy) ?? "Menu", items: items)
        }
    }

    static func int(_ value: JSONValue) -> Int? {
        if case .number(let n) = value { return Int(n) }
        if case .string(let s) = value { return Int(s) }
        return nil
    }
    static func money(_ value: JSONValue) -> Decimal? {
        switch value {
        case .number(let n): return Decimal(string: String(format: "%.2f", n), locale: Locale(identifier: "en_US_POSIX"))
        case .string(let s): return MSAPages.money(s)
        default: return nil
        }
    }
    static func tidy(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    /// The fixed offset a portal time is written in, such as `+08:00`.
    static func offset(_ text: String) -> TimeZone? {
        guard let match = text.range(of: #"[+-]\d{2}:\d{2}$"#, options: .regularExpression) else { return nil }
        let part = text[match]; let sign = part.first == "-" ? -1 : 1
        let numbers = part.dropFirst().split(separator: ":").compactMap { Int($0) }
        guard numbers.count == 2 else { return nil }
        return TimeZone(secondsFromGMT: sign * (numbers[0] * 3600 + numbers[1] * 60))
    }
    static func moment(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }
}

extension CanteenRemaining {
    /// A day's remaining quantities, from `order/getmenuitemsbydate`.
    static func list(_ json: JSONValue) -> [CanteenRemaining] {
        (json.array ?? []).compactMap { entry in
            guard let group = CanteenMenu.int(entry["groupId"]), let item = CanteenMenu.int(entry["itemId"]),
                  let available = CanteenMenu.int(entry["availableSalesQty"]) else { return nil }
            return CanteenRemaining(groupID: group, itemID: item, available: available)
        }
    }
}

extension CanteenOrder {
    /// The body MSA's `order/verify` and `order/save` take, shaped exactly as the portal's client builds it (item and group
    /// IDs as strings, the date unpadded).
    public func msaBody(account: Int, menu: Int) -> JSONValue {
        let items: [JSONValue] = lines.filter { $0.quantity > 0 }.map { line in
            .object(["Id": .string(line.id), "ItemId": .string(String(line.itemID)), "GroupId": .string(String(line.groupID)),
                     "Qty": .number(Double(line.quantity)), "Note": .string(line.note), "Modifiers": .array([])])
        }
        let order: JSONValue = .object([
            "Id": .string(id), "OptionId": .number(Double(option?.id ?? 0)), "OrderDate": .string(day.orderDate),
            "Surcharge": .number(NSDecimalNumber(decimal: option?.surcharge ?? 0).doubleValue), "Items": .array(items)
        ])
        return .object(["CardId": .number(Double(account)), "MenuId": .number(Double(menu)), "Orders": .array([order])])
    }

    /// MSA's verdict on an order before it's paid for: problems it found (an item sold out, a day closed), if any.
    public func msaProblems(in verification: JSONValue) -> [String] {
        var problems: [String] = []
        for entry in verification.array ?? [] where entry["verified"].bool == false {
            if let message = entry["message"].string, !message.isEmpty { problems.append(message) }
            for item in entry["items"].array ?? [] {
                guard let message = item["message"].string, !message.isEmpty else { continue }
                let name = lines.first { $0.id == item["id"].string }?.name
                problems.append(name.map { "\($0): \(message)" } ?? message)
            }
            if problems.isEmpty { problems.append("This order can't be placed.") }
        }
        return problems
    }
}

/// The portal's server-rendered pages.
enum MSAPages {
    static func money(_ text: String) -> Decimal? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
        let negative = cleaned.hasPrefix("-") || cleaned.hasPrefix("(")
        cleaned = cleaned.filter { $0.isNumber || $0 == "." }
        guard !cleaned.isEmpty, let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return negative ? -value : value
    }

    // MARK: HTML pages

    static func accounts(html: String) -> [CanteenAccount] {
        let pattern = #"<h2>\s*([^<]+?)\s*</h2>\s*<h4>\s*\(\s*<a[^>]*href="[^"]*/Account/View/(\d+)"[^>]*>([^<]*)</a>\s*\)\s*</h4>"#
        let matches = HTMLText.matches(pattern, in: html)
        return matches.enumerated().compactMap { index, match in
            guard let id = Int(match.groups[1]) else { return nil }
            let end = index + 1 < matches.count ? matches[index + 1].range.lowerBound : html.endIndex
            let panel = String(html[match.range.upperBound..<end])
            let balance = HTMLText.matches(#"Account Balance.*?<h4[^>]*>\s*([^<]+?)\s*</h4>"#, in: panel).first.flatMap { money($0.groups[0]) }
            return CanteenAccount(id: id, name: HTMLText.decode(match.groups[0]), reference: HTMLText.decode(match.groups[2]),
                                  balance: balance ?? 0, canOrder: panel.contains("/Account/Order/\(id)\""),
                                  canRecharge: panel.contains("/Account/Recharge/\(id)\""))
        }
    }

    static func menus(html: String, account: Int) -> [CanteenMenuSummary] {
        var menus: [CanteenMenuSummary] = []
        for match in HTMLText.matches(#"panel-title[^>]*>\s*<strong>([^<]*)</strong>.*?href="[^"]*/Order/(\d+)/(\d+)""#, in: html)
        where Int(match.groups[1]) == account {
            guard let id = Int(match.groups[2]), !menus.contains(where: { $0.id == id }) else { continue }
            menus.append(CanteenMenuSummary(id: id, name: CanteenMenu.tidy(HTMLText.decode(match.groups[0]))))
        }
        return menus
    }

    /// Times on the page are the school's local time; `timeZone` is the school's (the device's, unless known otherwise).
    static func transactions(html: String, timeZone: TimeZone = .current) -> [CanteenTransaction] {
        guard let body = HTMLText.matches(#"<tbody>(.*?)</tbody>"#, in: html).first?.groups[0] else { return [] }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd/MM/yyyy - hh:mm a"; formatter.timeZone = timeZone
        return HTMLText.matches(#"<tr>(.*?)</tr>"#, in: body).enumerated().compactMap { index, row in
            let cells = HTMLText.matches(#"<td[^>]*>(.*?)</td>"#, in: row.groups[0]).map(\.groups[0])
            guard cells.count >= 5 else { return nil }
            let dateText = HTMLText.plain(cells[0])
            guard let date = formatter.date(from: dateText) else { return nil }
            let descriptionHTML = cells[1]
            let firstBreak = descriptionHTML.range(of: "<div")?.lowerBound ?? descriptionHTML.endIndex
            let description = CanteenMenu.tidy(HTMLText.plain(String(descriptionHTML[..<firstBreak])))
            let items = HTMLText.matches(#"<em[^>]*>(.*?)</em>"#, in: descriptionHTML).map { CanteenMenu.tidy(HTMLText.plain($0.groups[0])) }.filter { !$0.isEmpty }
            let kind: CanteenTransaction.Kind
            if let order = HTMLText.matches(#"Ref#:\s*(\d+)(?:.*?for\s+(\d{2}/\d{2}/\d{4}))?"#, in: description).first {
                kind = .order(number: order.groups[0], forDay: CanteenDay(slashed: order.groups[1]))
            } else if description.lowercased().hasPrefix("purchase") {
                // "Purchase/Refund/Deposit": a sale (or refund) at the canteen counter.
                kind = .purchase
            } else if description.localizedCaseInsensitiveContains("deposit") {
                kind = .deposit
            } else if description.localizedCaseInsensitiveContains("fee") {
                kind = .fee
            } else { kind = .other }
            return CanteenTransaction(id: index, date: date, description: description, kind: kind, items: items,
                                      credit: money(HTMLText.plain(cells[2])), debit: money(HTMLText.plain(cells[3])),
                                      balance: money(HTMLText.plain(cells[4])))
        }
    }

    static func orderHistory(html: String) -> [CanteenPastOrder] {
        let panels = html.components(separatedBy: #"<div class="panel panel-primary">"#).dropFirst()
        return panels.compactMap { panel in
            guard let heading = HTMLText.matches(#"panel-heading[^>]*>\s*<strong>(.*?)</strong>"#, in: panel).first else { return nil }
            let parts = HTMLText.plain(heading.groups[0]).split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2, let day = CanteenDay(slashed: parts[1]) else { return nil }
            let number = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "# "))
            let rows = HTMLText.matches(#"<tr>\s*<td class="text-left">(.*?)</td>\s*<td[^>]*>(.*?)</td>\s*<td[^>]*>(.*?)</td>\s*</tr>"#, in: panel)
            let lines: [CanteenPastOrder.Line] = rows.map { row in
                let cell = row.groups[0]
                let name = cell.range(of: "<br").map { String(cell[..<$0.lowerBound]) } ?? cell
                let note = HTMLText.matches(#"<em[^>]*>(.*?)</em>"#, in: cell).first.map { CanteenMenu.tidy(HTMLText.plain($0.groups[0])) }
                return CanteenPastOrder.Line(name: CanteenMenu.tidy(HTMLText.plain(name)), note: note?.isEmpty == false ? note : nil,
                                             quantity: Int(HTMLText.plain(row.groups[1])) ?? 1, price: money(HTMLText.plain(row.groups[2])) ?? 0)
            }
            let total = HTMLText.matches(#"TOTAL</strong>\s*</div>\s*<div[^>]*>\s*<strong>([^<]*)</strong>"#, in: panel).first.flatMap { money($0.groups[0]) }
            return CanteenPastOrder(number: number, day: day, lines: lines, total: total ?? lines.reduce(0) { $0 + $1.price * Decimal($1.quantity) })
        }
    }
}
