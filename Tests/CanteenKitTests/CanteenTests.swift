import XCTest
@testable import CanteenKit

/// Fictional fixtures shaped like the portal's pages and API responses.
private enum Fixture {
    static let accounts = """
    <nav><form action="/wp/Profile/SignOut" method="post"><input name="__RequestVerificationToken" type="hidden" value="x" /></form></nav>
    <div class="panel-body">
      <div class="row"><div class="col-sm-9">
        <h2>Alex Morgan</h2>
        <h4>(<a title="Reference Number" href="/wp/Account/View/501">1234567890123</a>)</h4>
      </div><div class="col-sm-3">
        <h5 class="text-right text-uppercase"><strong>Account Balance</strong></h5>
        <h4 class="text-right text-primary">$25.00</h4>
      </div></div>
      <ul><li><a href="/wp/Account/Recharge/501">RECHARGE</a></li><li><a href="/wp/Account/Order/501">ONLINE ORDERS</a></li></ul>
    </div>
    <div class="panel-body">
      <div class="row"><div class="col-sm-9">
        <h2>Sam  O&#x27;Neil</h2>
        <h4>(<a title="Reference Number" href="/wp/Account/View/502">1234567890124</a>)</h4>
      </div><div class="col-sm-3">
        <h5 class="text-right text-uppercase"><strong>Account Balance</strong></h5>
        <h4 class="text-right text-primary">$1,204.50</h4>
      </div></div>
      <ul><li><a href="/wp/Account/History/502">HISTORY</a></li></ul>
    </div>
    """
    static let orderPage = """
    <ul class="nav nav-tabs"><li class="active"><a>New Order</a></li></ul>
    <div class="panel panel-primary"><div class="panel-heading clearfix">
      <h4 class="panel-title pull-left"><strong>Term 4  Menu</strong></h4></div>
      <div class="panel-body"><p> For junior school students only. </p></div>
      <div class="panel-body bg-info"><a class="btn btn-default pull-right" href="/wp/Order/501/17">Begin Order</a></div>
    </div>
    """
    static let menu = """
    {"allowedPayments":3,"allowFavourites":false,"accountBalance":25,
     "menu":{"id":17,"type":0,"name":"Term 4  Menu","description":" Junior school ","cutOff":"2026-11-13T09:00:00+08:00",
       "cutOffDays":0,"advancedOrderLimit":4,"dayMon":true,"dayTue":true,"dayWed":true,"dayThu":true,"dayFri":true,
       "daySat":false,"daySun":false,"menuStart":null,"menuEnd":null,"discount":0,"disableCCPayment":false,
       "specificDates":[],"excludedDates":["2026-11-17T00:00:00"]},
     "menuOptions":[{"id":11,"name":"Lunch","surcharge":0}],
     "menuGroups":[
       {"id":118,"name":"Hot Food","items":[
         {"id":1,"name":"Veggie pie","description":"Every day","availability":0,"dailySalesLimit":-1,"dailyPurchaseLimit":-1,
          "diminish":false,"diminishQty":0,"itemType":1,"stockOnHand":0,"allowBackorder":true,"price":5.5,"enableNote":false,"enableModifiers":false},
         {"id":2,"name":"Mon- Fried rice","description":null,"availability":1,"dailySalesLimit":-1,"dailyPurchaseLimit":-1,
          "diminish":false,"diminishQty":0,"itemType":1,"stockOnHand":0,"allowBackorder":true,"price":7,"enableNote":false,"enableModifiers":false},
         {"id":3,"name":"Fish and chips","description":"Fridays","availability":16,"dailySalesLimit":-1,"dailyPurchaseLimit":2,
          "diminish":false,"diminishQty":0,"itemType":1,"stockOnHand":0,"allowBackorder":true,"price":7,"enableNote":true,"enableModifiers":false}]},
       {"id":119,"name":"Drinks","items":[
         {"id":4,"name":"Water 600ml","description":"","availability":0,"dailySalesLimit":-1,"dailyPurchaseLimit":-1,
          "diminish":false,"diminishQty":0,"itemType":2,"stockOnHand":0,"allowBackorder":false,"price":1.8,"enableNote":false,"enableModifiers":false}]}]}
    """
    static let history = """
    <table class="table"><thead><tr><th>Date</th><th>Description</th><th>Credit</th><th>Debit</th><th>Balance</th></tr></thead>
    <tbody>
      <tr><td>06/11/2026 - 07:04 AM</td><td>
          Online Order Ref#: 1001 - (Lunch for 06/11/2026)
          <div><em class="small col-sm-12">1 x Veggie pie</em></div>
          <div><em class="small col-sm-12">1 x Water 600ml</em></div>
        </td><td class="text-right"></td><td class="text-right">
    $7.30                                                    </td><td class="text-right text-primary">$25.00</td></tr>
      <tr><td>06/11/2026 - 07:04 AM</td><td>
          Online Deposit (REF0001)
        </td><td class="text-right">
    $7.30                                                    </td><td class="text-right"></td><td class="text-right text-primary">$32.30</td></tr>
      <tr><td>25/09/2026 - 01:09 PM</td><td>
          WP Transaction Fee
        </td><td class="text-right"></td><td class="text-right">
    $1.15                                                    </td><td class="text-right text-primary">$25.00</td></tr>
      <tr><td>17/08/2026 - 01:09 PM</td><td>
          Purchase/Refund/Deposit
          <div><em class="small col-sm-12">1 x Biscuit</em></div>
        </td><td class="text-right"></td><td class="text-right">
    $2.00                                                    </td><td class="text-right text-primary">$26.15</td></tr>
    </tbody></table>
    """
    static let orderHistory = """
    <div class="row"><div class="col-sm-12">
      <div class="panel panel-primary">
        <div class="panel-heading"><strong>#1002&nbsp;&nbsp;:&nbsp;&nbsp;13/11/2026&nbsp;&nbsp;:&nbsp;&nbsp;Term 4  Menu&nbsp;</strong></div>
        <div class="table-responsive"><table class="table table-condensed small">
          <thead><tr><th class="col-sm-10 text-left">Description</th><th>Qty</th><th>Price</th></tr></thead>
          <tbody>
            <tr>
              <td class="text-left">Fish &amp; chips<br /><em class="text-info">No salt</em></td>
              <td class="text-center">1</td>
              <td class="text-right">$7.00</td>
            </tr>
            <tr>
              <td class="text-left">Water 600ml <br /><em class="text-info"></em></td>
              <td class="text-center">2</td>
              <td class="text-right">$1.80</td>
            </tr>
          </tbody></table></div>
        <div class="panel-footer">
          <div class="row"><div class="col-sm-10 text-right"><strong>TAX</strong></div><div class="col-sm-2 text-right"><strong>$0.96</strong></div></div>
          <div class="row"><div class="col-sm-10 text-right"><strong>TOTAL</strong></div><div class="col-sm-2 text-right"><strong>$10.60</strong></div></div>
        </div>
      </div>
      <div class="panel panel-primary">
        <div class="panel-heading"><strong>#1001&nbsp;&nbsp;:&nbsp;&nbsp;06/11/2026&nbsp;&nbsp;:&nbsp;&nbsp;DELETED MENU&nbsp;</strong></div>
        <div class="table-responsive"><table><tbody>
          <tr><td class="text-left">Veggie pie<br /><em class="text-info"></em></td><td class="text-center">1</td><td class="text-right">$5.50</td></tr>
        </tbody></table></div>
        <div class="panel-footer"><div class="row"><div class="col-sm-10 text-right"><strong>TOTAL</strong></div><div class="col-sm-2 text-right"><strong>$5.50</strong></div></div></div>
      </div>
    </div></div>
    """
}

private actor PortalTransport: HTTPTransport {
    struct Reply: Sendable { var body: String; var status: Int = 200; var headers: [String: String] = [:] }
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []
    init(_ replies: [Reply]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw CanteenError.schema("unexpected request") }
        let reply = replies.removeFirst()
        return (Data(reply.body.utf8), HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers)!)
    }
}

final class CanteenTests: XCTestCase {
    private let perth = TimeZone(secondsFromGMT: 8 * 3600)!
    private func link() throws -> MSALink {
        MSALink(portal: try MSAPortal("https://canteen.example/wp/Profile/Accounts"), cookies: [".AspNetCore.Cookies": "session-a"])
    }
    private func menu() throws -> CanteenMenu { try CanteenMenu(msaJSON: JSONDecoder().decode(JSONValue.self, from: Data(Fixture.menu.utf8))) }
    private func moment(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    func testPortalIsCutBackToItsBaseFromAnyPastedPage() throws {
        XCTAssertEqual(try MSAPortal("https://Canteen.example/wp/Profile/Accounts").base.absoluteString, "https://canteen.example/wp/")
        XCTAssertEqual(try MSAPortal("canteen.example/wp/order/getmenu/?id=1&menuid=2").base.absoluteString, "https://canteen.example/wp/")
        XCTAssertEqual(try MSAPortal("https://secure.canteen.example/Profile/SignIn").base.absoluteString, "https://secure.canteen.example/")
        XCTAssertEqual(try MSAPortal("https://canteen.example/wp").path, "/wp/")
        for bad in ["http://canteen.example/wp/", "https://user:pass@canteen.example/wp/", ""] {
            XCTAssertThrowsError(try MSAPortal(bad), bad)
        }
        let portal = try MSAPortal("https://canteen.example/wp/")
        XCTAssertTrue(portal.isSignedInPage(URL(string: "https://canteen.example/wp/Profile/Accounts")))
        XCTAssertFalse(portal.isSignedInPage(URL(string: "https://canteen.example/wp/Profile/Authenticate?ReturnUrl=x")))
        XCTAssertFalse(portal.isSignedInPage(URL(string: "https://login.microsoftonline.com/tenant/wsfed")))
    }

    func testBareMSAHostOpensTheStandardAccountsPage() throws {
        for input in ["msa.banksia.example.edu.au", "https://msa.banksia.example.edu.au", " https://msa.banksia.example.edu.au/ ",
                      "https://msa.banksia.example.edu.au/wp/Profile/Accounts"] {
            let portal = try MSAPortal(input)
            XCTAssertEqual(portal.base.absoluteString, "https://msa.banksia.example.edu.au/wp/", input)
            XCTAssertEqual(portal.accountsPage.absoluteString, "https://msa.banksia.example.edu.au/wp/Profile/Accounts", input)
        }
        // Explicit deployments outside /wp/ still keep their supplied path.
        XCTAssertEqual(try MSAPortal("https://canteen.example/portal/Profile/Accounts").path, "/portal/")
        XCTAssertEqual(try MSAPortal("https://canteen.example/Profile/Accounts").path, "/")
    }

    func testKeepsOnlyThePortalsOwnCookies() throws {
        let portal = try MSAPortal("https://canteen.example/wp/")
        func cookie(_ name: String, domain: String = "canteen.example", path: String = "/wp", expires: Date? = nil) -> HTTPCookie {
            var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: "v-\(name)", .domain: domain, .path: path]
            if let expires { properties[.expires] = expires }
            return HTTPCookie(properties: properties)!
        }
        let kept = MSALink.portalCookies([
            cookie(".AspNetCore.Cookies"), cookie("ARRAffinity", path: "/"),
            cookie(".AspNetCore.Correlation.abc", path: "/wp/signin-adfs"), cookie("ESTSAUTH", domain: ".login.microsoftonline.com", path: "/"),
            cookie("old", expires: Date(timeIntervalSinceNow: -60)), cookie("elsewhere", path: "/other")
        ], portal: portal)
        XCTAssertEqual(kept, [".AspNetCore.Cookies": "v-.AspNetCore.Cookies", "ARRAffinity": "v-ARRAffinity"])
    }

    func testAccountListAndMenusAreReadFromThePages() {
        let accounts = MSAPages.accounts(html: Fixture.accounts)
        XCTAssertEqual(accounts.map(\.id), [501, 502])
        XCTAssertEqual(accounts[0].name, "Alex Morgan"); XCTAssertEqual(accounts[0].reference, "1234567890123")
        XCTAssertEqual(accounts[0].balance, Decimal(string: "25.00")); XCTAssertTrue(accounts[0].canOrder && accounts[0].canRecharge)
        XCTAssertEqual(accounts[1].balance, Decimal(string: "1204.50")); XCTAssertFalse(accounts[1].canOrder)
        XCTAssertTrue(accounts[1].matches(childName: "sam o'neil")); XCTAssertTrue(accounts[0].matches(childName: "Morgan, Alex"))
        XCTAssertFalse(accounts[0].matches(childName: "Alex Morgana"))
        XCTAssertEqual(MSAPages.menus(html: Fixture.orderPage, account: 501), [CanteenMenuSummary(id: 17, name: "Term 4 Menu")])
        XCTAssertEqual(MSAPages.menus(html: Fixture.orderPage, account: 502), [])
    }

    func testMenuRulesFollowThePortalsDatePicker() throws {
        let menu = try menu()
        XCTAssertEqual(menu.name, "Term 4 Menu"); XCTAssertEqual(menu.balance, 25); XCTAssertEqual(menu.options.first?.name, "Lunch")
        XCTAssertEqual(menu.timeZone.secondsFromGMT(), 8 * 3600)
        // Thursday evening in Perth: Friday is the first day, the limit runs four days on, and Tuesday is excluded.
        let thursdayEvening = moment("2026-11-12T13:00:00Z")
        XCTAssertEqual(menu.orderableDays(now: thursdayEvening).map(\.description), ["2026-11-13", "2026-11-16"])
        XCTAssertEqual(menu.deadline(for: CanteenDay(year: 2026, month: 11, day: 16)), moment("2026-11-16T01:00:00Z"))
        // After Friday's 9 am cut-off, Friday is gone.
        XCTAssertEqual(menu.orderableDays(now: moment("2026-11-13T01:30:00Z")).map(\.description), ["2026-11-16"])
    }

    func testItemsAreFilteredByWeekdayAndLimited() throws {
        var menu = try menu()
        let friday = CanteenDay(year: 2026, month: 11, day: 13), monday = CanteenDay(year: 2026, month: 11, day: 16)
        XCTAssertEqual(friday.weekday, 6)
        XCTAssertEqual(menu.groups(on: friday).flatMap(\.items).map(\.id), [1, 3, 4])
        XCTAssertEqual(menu.groups(on: monday).flatMap(\.items).map(\.id), [1, 2, 4])
        XCTAssertEqual(menu.item(group: 118, id: 1)?.maximumQuantity, nil)
        XCTAssertEqual(menu.item(group: 118, id: 3)?.maximumQuantity, 2)
        XCTAssertEqual(menu.item(group: 119, id: 4)?.isSoldOut, true, "a stock item with none on hand and no backorder")
        XCTAssertEqual(menu.item(group: 119, id: 4)?.price, Decimal(string: "1.80"))
        menu.apply(remaining: [CanteenRemaining(groupID: 118, itemID: 1, available: 0)])
        XCTAssertEqual(menu.item(group: 118, id: 1)?.isSoldOut, true)
    }

    func testOrderBodyMatchesThePortalsClient() throws {
        let day = CanteenDay(year: 2026, month: 11, day: 6)
        var order = CanteenOrder(day: day, option: CanteenMenu.Option(id: 11, name: "Lunch", surcharge: 0))
        order.lines = [CanteenOrder.Line(groupID: 118, itemID: 3, name: "Fish and chips", price: 7, quantity: 1, note: "No salt"),
                       CanteenOrder.Line(groupID: 119, itemID: 4, name: "Water", price: Decimal(string: "1.8")!, quantity: 0)]
        XCTAssertEqual(order.total, 7)
        let body = order.msaBody(account: 501, menu: 17)
        XCTAssertEqual(body["CardId"], .number(501)); XCTAssertEqual(body["MenuId"], .number(17))
        let placed = try XCTUnwrap(body["Orders"].array?.first)
        XCTAssertEqual(placed["OrderDate"], .string("2026-11-6")); XCTAssertEqual(placed["OptionId"], .number(11))
        XCTAssertEqual(placed["Id"].string, order.id)
        let items = try XCTUnwrap(placed["Items"].array)
        XCTAssertEqual(items.count, 1, "lines with no quantity are left out")
        XCTAssertEqual(items[0]["ItemId"], .string("3")); XCTAssertEqual(items[0]["GroupId"], .string("118"))
        XCTAssertEqual(items[0]["Qty"], .number(1)); XCTAssertEqual(items[0]["Note"], .string("No salt"))
        // Verification messages are reported against the line's name.
        let verdict: JSONValue = .array([.object(["id": .string(order.id), "verified": .bool(false), "message": .null,
                                                   "items": .array([.object(["id": .string(order.lines[0].id), "message": .string("Sold out")])])])])
        XCTAssertEqual(order.msaProblems(in: verdict), ["Fish and chips: Sold out"])
        XCTAssertEqual(order.msaProblems(in: .array([.object(["id": .string(order.id), "verified": .bool(true)])])), [])
    }

    func testTransactionsAndOrderHistoryAreReadFromThePages() throws {
        let transactions = MSAPages.transactions(html: Fixture.history, timeZone: perth)
        XCTAssertEqual(transactions.count, 4)
        XCTAssertEqual(transactions[0].kind, .order(number: "1001", forDay: CanteenDay(year: 2026, month: 11, day: 6)))
        XCTAssertEqual(transactions[0].items, ["1 x Veggie pie", "1 x Water 600ml"])
        XCTAssertEqual(transactions[0].amount, Decimal(string: "-7.30")); XCTAssertEqual(transactions[0].balance, 25)
        XCTAssertEqual(transactions[0].date, moment("2026-11-05T23:04:00Z"))
        XCTAssertEqual(transactions[1].kind, .deposit); XCTAssertEqual(transactions[1].amount, Decimal(string: "7.30"))
        XCTAssertEqual(transactions[2].kind, .fee)
        XCTAssertEqual(transactions[3].kind, .purchase); XCTAssertEqual(transactions[3].date, moment("2026-08-17T05:09:00Z"))

        let orders = MSAPages.orderHistory(html: Fixture.orderHistory)
        XCTAssertEqual(orders.map(\.number), ["1002", "1001"])
        XCTAssertEqual(orders[0].day, CanteenDay(year: 2026, month: 11, day: 13))
        XCTAssertEqual(orders[0].lines, [.init(name: "Fish & chips", note: "No salt", quantity: 1, price: 7),
                                         .init(name: "Water 600ml", note: nil, quantity: 2, price: Decimal(string: "1.80")!)])
        XCTAssertEqual(orders[0].total, Decimal(string: "10.60")); XCTAssertEqual(orders[1].total, Decimal(string: "5.50"))
    }

    func testClientSendsCookiesOnlyToThePortalAndKeepsRefreshedOnes() async throws {
        let transport = PortalTransport([
            .init(body: Fixture.accounts, headers: ["Set-Cookie": ".AspNetCore.Cookies=session-b; path=/wp; secure; httponly"]),
            .init(body: Fixture.menu)
        ])
        let client = MSAClient(link: try link(), transport: transport)
        let accounts = try await client.accounts()
        XCTAssertEqual(accounts.count, 2)
        let menu = try await client.menu(account: 501, menu: 17)
        XCTAssertEqual(menu.id, 17)
        let requests = await transport.requests
        XCTAssertEqual(requests[0].url?.absoluteString, "https://canteen.example/wp/Profile/Accounts")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Cookie"), ".AspNetCore.Cookies=session-a")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Cookie"), ".AspNetCore.Cookies=session-b")
        let menuURL = try XCTUnwrap(requests[1].url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        XCTAssertEqual(menuURL.path, "/wp/order/getmenu/")
        XCTAssertEqual(menuURL.queryItems?.first { $0.name == "id" }?.value, "501")
        XCTAssertNotNil(menuURL.queryItems?.first { $0.name == "noCache" })
        let version = await client.cookieVersion
        XCTAssertEqual(version, 1)
    }

    func testExpiredSessionsAndRefusalsAreReported() async throws {
        let transport = PortalTransport([
            .init(body: "", status: 302, headers: ["Location": "https://canteen.example/wp/Profile/Authenticate?ReturnUrl=%2Fwp%2F"]),
            .init(body: "<html>Sign in</html>"),
            .init(body: "\"The cut off time for this order has passed\"", status: 400)
        ])
        let client = MSAClient(link: try link(), transport: transport)
        do { _ = try await client.accounts(); XCTFail("expected sign-in") } catch { XCTAssertEqual(error as? CanteenError, .signInRequired) }
        do { _ = try await client.menu(account: 501, menu: 17); XCTFail("expected sign-in") } catch { XCTAssertEqual(error as? CanteenError, .signInRequired) }
        let order = CanteenOrder(day: CanteenDay(year: 2026, month: 11, day: 13), option: nil,
                                 lines: [CanteenOrder.Line(groupID: 118, itemID: 1, name: "Veggie pie", price: 5, quantity: 1)])
        do { _ = try await client.verify(order, account: 501, menu: 17); XCTFail("expected a refusal") }
        catch { XCTAssertEqual(error as? CanteenError, .rejected("The cut off time for this order has passed")) }
    }

    func testPlacingChecksTheSessionThenSavesOnce() async throws {
        let transport = PortalTransport([
            .init(body: "{}"),
            .init(body: #"{"orderReceipts":[{"id":"x","orderNumber":1003}]}"#)
        ])
        let client = MSAClient(link: try link(), transport: transport)
        let order = CanteenOrder(day: CanteenDay(year: 2026, month: 11, day: 13), option: nil,
                                 lines: [CanteenOrder.Line(groupID: 118, itemID: 1, name: "Veggie pie", price: 5, quantity: 1)])
        let numbers = try await client.place(order, account: 501, menu: 17)
        XCTAssertEqual(numbers, ["1003"])
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.path } }, ["/wp/status/", "/wp/order/save/"])
        XCTAssertEqual(requests[1].httpMethod, "POST")
        let sent = try JSONDecoder().decode(JSONValue.self, from: try XCTUnwrap(requests[1].httpBody))
        XCTAssertEqual(sent["Orders"].array?.first?["OptionId"], .number(0))
    }

    func testLinksMoveOutOfAccountJSONFromOlderBuilds() throws {
        // Builds 19–20 saved the link inside each account; accounts without one are skipped.
        let old = #"""
        [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","school":"https://school.example","name":"P","username":"p","personID":"7","sessionID":"s",
          "canteen":{"portal":"https://canteen.example/wp/","cookies":{".AspNetCore.Cookies":"session-a"}}},
         {"id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","school":"https://school.example","name":"Q","username":"q","personID":"8","sessionID":"t"}]
        """#
        let links = CanteenLinkStore.legacyLinks(fromAccountsJSON: Data(old.utf8))
        XCTAssertEqual(links, [UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!: .myStudentAccount(try link())])
        XCTAssertEqual(CanteenLinkStore.legacyLinks(fromAccountsJSON: Data("not json".utf8)), [:])
    }

    func testConnectionsRoundTrip() throws {
        let connection = CanteenConnection.myStudentAccount(try link())
        XCTAssertEqual(try JSONDecoder().decode(CanteenConnection.self, from: JSONEncoder().encode(connection)), connection)
        XCTAssertEqual(connection.msa, try link())
    }

    func testEscapedEntitiesDecodeOnce() {
        XCTAssertEqual(HTMLText.decode("Fish &amp; chips"), "Fish & chips")
        XCTAssertEqual(HTMLText.decode("a &amp;lt; b"), "a &lt; b")
        XCTAssertEqual(HTMLText.decode("caf&#233; &#x27;x&#x27;"), "café 'x'")
    }
}
