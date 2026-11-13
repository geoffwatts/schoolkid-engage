import XCTest

final class ReaderUITests: XCTestCase {
    func testFlatLayoutAndFullWidthPDF() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Today is Day'")).firstMatch.waitForExistence(timeout: 5), "Header should show today's cycle day")
        app.staticTexts["Reading journal feedback"].tap()
        capture("Flat assessment")
        let page = app.descendants(matching: .any)["assessment-pdf-page-0"]
        for _ in 0..<10 {
            if page.exists && page.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(page.exists)
        // Full width of the content area: the whole screen on a phone; on iPhone Duo, up to the floating tab rail
        // (the list runs underneath the rail, but content must stop at its edge rather than hide behind it).
        let contentEdge = app.tabBars.firstMatch.exists ? app.frame.maxX : min(app.frame.maxX, tab("Updates", in: app).frame.minX)
        XCTAssertEqual(page.frame.minX, app.frame.minX, accuracy: 2, "Inline PDFs start at the screen edge")
        XCTAssertLessThanOrEqual(page.frame.maxX, contentEdge + 1, "Inline PDFs never sit under the tab rail")
        XCTAssertGreaterThan(page.frame.maxX, contentEdge - 40, "Inline PDFs fill the content width")
        capture("Full width inline PDF")
        tab("Timetable", in: app).tap()
        XCTAssertTrue(app.buttons["Next week"].waitForExistence(timeout: 5), "Timetable should open in week view")
        capture("Timetable week")
        let piano = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Piano'")).firstMatch
        XCTAssertTrue(piano.waitForExistence(timeout: 5) && piano.isHittable, "Overlapping lessons should stay tappable")
        piano.tap()
        XCTAssertTrue(app.navigationBars["Piano"].waitForExistence(timeout: 5))
        capture("Overlapping lesson details")
        app.buttons["Done"].tap()
        app.buttons["Day"].tap()
        XCTAssertTrue(app.staticTexts["English"].waitForExistence(timeout: 5))
        capture("Flat timetable")
        openReports(app)
        app.staticTexts["Student progress report"].tap()
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        capture("Full bleed report")
    }

    func testLunchOrderFromBalance() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let headerBalance = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Lunch balance $18.50'")).firstMatch
        XCTAssertTrue(headerBalance.waitForExistence(timeout: 5), "Header should show the lunch balance")
        tab("Lunch", in: app).tap()
        XCTAssertTrue(app.staticTexts["lunch-balance-amount"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["lunch-balance-amount"].label, "$18.50")
        XCTAssertTrue(app.staticTexts["No lunch ordered yet."].exists)
        capture("Lunch home")
        app.buttons["lunch-top-up"].tap()
        XCTAssertTrue(app.staticTexts["Top up on the canteen’s page"].waitForExistence(timeout: 5), "Top up opens the canteen's page")
        app.buttons["Done"].tap()
        app.buttons["lunch-new-order"].tap()
        let firstDay = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'lunch-day-'")).firstMatch
        XCTAssertTrue(firstDay.waitForExistence(timeout: 5))
        capture("Lunch choose day")
        firstDay.tap()
        XCTAssertTrue(app.buttons["Add Veggie pie"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["lunch-review"].isEnabled, "Nothing to review until something is chosen")
        app.buttons["Add Veggie pie"].tap()
        // Keep the item above the fixed Review bar before tapping it.
        let juice = app.buttons["Add Apple juice"]
        for _ in 0..<4 where !juice.isHittable || juice.frame.maxY >= app.buttons["lunch-review"].frame.minY - 20 { app.swipeUp() }
        juice.tap()
        capture("Lunch day menu")
        app.buttons["lunch-review"].tap()
        let pay = app.buttons["lunch-pay"]
        XCTAssertTrue(pay.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["$9.00"].exists, "Pie and juice total")
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: pay)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed, "Pay once the canteen has checked the order")
        XCTAssertTrue(pay.label.contains("$18.50 available"), "The pay button shows the balance")
        capture("Lunch review")
        app.buttons["lunch-pay-card"].tap()
        XCTAssertTrue(app.staticTexts["Top up on the canteen’s page"].waitForExistence(timeout: 5), "Pay by card opens the canteen's top-up page, even when the balance covers the order")
        app.buttons["Done"].tap()
        XCTAssertTrue(pay.waitForExistence(timeout: 5))
        pay.tap()
        XCTAssertTrue(app.descendants(matching: .any)["lunch-ordered"].waitForExistence(timeout: 5))
        capture("Lunch ordered")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["lunch-balance-amount"].waitForExistence(timeout: 5))
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == '$9.50'"), object: app.staticTexts["lunch-balance-amount"])
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 5), .completed, "Balance drops by the order total")
        XCTAssertFalse(app.staticTexts["No lunch ordered yet."].exists, "The new order shows under Upcoming")
        capture("Lunch home after ordering")
        // The same order again is offered on the next day.
        app.buttons["lunch-new-order"].tap()
        let days = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'lunch-day-'"))
        XCTAssertTrue(days.element(boundBy: 1).waitForExistence(timeout: 5))
        days.element(boundBy: 1).tap()
        XCTAssertTrue(app.buttons["lunch-repeat"].waitForExistence(timeout: 5))
        capture("Lunch repeat offered")
    }

    func testAttachmentStackJumpsToFiles() throws {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        app.staticTexts["Reading journal feedback"].tap()
        let stack = app.buttons["assessment-attachment-stack"]
        XCTAssertTrue(stack.waitForExistence(timeout: 5), "Assessments with media show a pile beside the title")
        XCTAssertGreaterThan(stack.frame.midX, app.frame.midX, "The pile sits on the right")
        let header = app.staticTexts["Photos & Documents"]
        stack.tap()
        let deadline = Date().addingTimeInterval(3)
        while !(header.exists && header.isHittable) && Date() < deadline { usleep(100_000) }
        XCTAssertTrue(header.exists && header.isHittable, "Tapping the pile scrolls down to the files")
        XCTAssertLessThan(header.frame.minY, app.frame.midY, "The files section lands near the top")
    }

    func testInlineWordDocumentScrollsWithThePage() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        app.staticTexts["Reading journal feedback"].tap()
        let preview = app.descendants(matching: .any)["Preview of Essay feedback.docx"]
        for _ in 0..<12 {
            if preview.exists && preview.frame.minY < app.frame.midY { break }
            app.swipeUp()
        }
        XCTAssertTrue(preview.exists)
        capture("Inline Word document")
        // The Word file is the last thing on the page, so drag down from inside the preview: the page must move.
        let before = preview.frame.minY
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: preview.frame.midX, dy: max(before, 200) + 120))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 300)))
        XCTAssertGreaterThan(preview.frame.minY, before + 50, "The inline Word preview should not capture scrolling")
        app.buttons["Open Essay feedback.docx full size"].tap()
        XCTAssertTrue(app.navigationBars["Essay feedback.docx"].waitForExistence(timeout: 5))
        capture("Full screen Word document")
    }

    func testRotatingAPhotoKeepsItsPlace() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        app.staticTexts["Reading journal feedback"].tap()
        let rotate = app.buttons["Rotate Annotated work photo clockwise"]
        for _ in 0..<10 {
            if rotate.exists && rotate.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(rotate.isHittable)
        for angle in [90, 180, 270, 0] {
            let before = rotate.frame.minY
            rotate.tap()
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "\(angle) degrees"), object: rotate)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
            // The photo's own controls should stay where the reader's finger is, not jump with the page.
            XCTAssertEqual(rotate.frame.minY, before, accuracy: 4, "Rotating to \(angle)° moved the photo's controls")
            capture("After rotating to \(angle)")
        }
    }

    func testAssessmentListStatusAndTeacher() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        tab("Assessments", in: app).tap()
        let any = app.descendants(matching: .any)
        if app.buttons["Upcoming"].exists { app.buttons["Upcoming"].tap() }
        XCTAssertTrue(app.staticTexts["Overdue"].waitForExistence(timeout: 5), "An unmarked overdue assessment shows the Overdue pill")
        capture("Upcoming with overdue")
        app.buttons["Results"].tap()
        XCTAssertTrue(app.staticTexts["Book talk"].waitForExistence(timeout: 5))
        // Feedback without a mark gets the icon; a marked assessment shows only its mark.
        XCTAssertEqual(any.matching(NSPredicate(format: "label == 'Feedback available'")).count, 1)
        capture("Results with feedback")
        app.staticTexts["Reading journal"].tap()
        XCTAssertTrue(any.matching(NSPredicate(format: "label CONTAINS 'Ms Rivera'")).firstMatch.waitForExistence(timeout: 5), "The assessment names its class teacher")
        capture("Assessment teacher")
    }

    func testExpiredSessionOffersSignInAgain() {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--simulate-expired-session"]; app.launch()
        XCTAssertTrue(app.staticTexts["Your school sign-in has expired."].waitForExistence(timeout: 5))
        capture("Expired session banner")
        app.buttons["Sign in again"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Connect school"].waitForExistence(timeout: 5))
    }

    func testIPadShowsListAndDetailSideBySide() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad layout") }
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        app.buttons["Assessments"].firstMatch.tap()
        app.buttons["Results"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Reading journal"].waitForExistence(timeout: 5))
        app.staticTexts["Reading journal"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["OVERVIEW"].waitForExistence(timeout: 5) || app.staticTexts["Overview"].waitForExistence(timeout: 1), "The detail opens")
        XCTAssertTrue(app.staticTexts["Book talk"].isHittable, "The list stays visible beside the detail")
        capture("iPad assessments")
    }

    func testWidgetLinkOpensTimetable() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.staticTexts["Reading journal feedback"].waitForExistence(timeout: 10))
        app.open(URL(string: "schoolkidengage://timetable")!)
        XCTAssertTrue(app.buttons["Next week"].waitForExistence(timeout: 5), "The widget's link opens the timetable")
    }

    /// Runs Apple's accessibility audit on each main screen and lists every issue found.
    func testAccessibilityAudit() throws {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        var issues: [String] = [], blocking: [String] = []
        // Contrast, clipping and Dynamic Type results are logged but don't fail the run: they include deliberate
        // truncation (the header, overview previews), the five-column week grid, and pixel-sampling false positives
        // (tinted table cells, subject icons). Labels, hit targets, traits and reachability must be clean.
        let advisory: XCUIAccessibilityAuditType = [.contrast, .textClipped, .dynamicType]
        func audit(_ screen: String) throws {
            try app.performAccessibilityAudit { issue in
                let element = issue.element.map { "\($0.elementType.rawValue) '\($0.label)'" } ?? "screen"
                let line = "[\(screen)] \(issue.auditType.rawValue) \(issue.compactDescription) — \(element)"
                issues.append(line)
                if advisory.intersection(issue.auditType).isEmpty { blocking.append(line) }
                return true
            }
        }
        XCTAssertTrue(app.staticTexts["Reading journal feedback"].waitForExistence(timeout: 10))
        try audit("Updates")
        app.staticTexts["Reading journal feedback"].tap()
        XCTAssertTrue(app.buttons["Share assessment"].waitForExistence(timeout: 5))
        try audit("Assessment detail")
        goBack(in: app)
        tab("Assessments", in: app).tap()
        try audit("Assessments results")
        app.buttons["Upcoming"].firstMatch.tap()
        try audit("Assessments upcoming")
        tab("Timetable", in: app).tap()
        XCTAssertTrue(app.buttons["Next week"].waitForExistence(timeout: 5))
        try audit("Timetable week")
        app.buttons["Day"].firstMatch.tap()
        try audit("Timetable day")
        openReports(app)
        try audit("Reports")
        app.buttons["school-news"].tap()
        try audit("News")
        print("A11Y-AUDIT-BEGIN\n" + issues.joined(separator: "\n") + "\nA11Y-AUDIT-END (\(issues.count) issues)")
        XCTAssertTrue(blocking.isEmpty, "Accessibility problems:\n" + blocking.joined(separator: "\n"))
    }

    /// App Store screenshots from the demo. Runs only when asked: `TEST_RUNNER_APPSTORE_SCREENSHOTS=1 xcodebuild test …`.
    func testAppStoreScreenshots() throws {
        guard ProcessInfo.processInfo.environment["APPSTORE_SCREENSHOTS"] == "1" else { throw XCTSkip("App Store screenshots only on request") }
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        func shot(_ name: String) { sleep(1); capture("AppStore-" + name) }
        XCTAssertTrue(app.staticTexts["Reading journal feedback"].waitForExistence(timeout: 10))
        // On iPad, show the split view with the first update open rather than an empty detail pane.
        if pad { app.staticTexts["Reading journal feedback"].tap(); XCTAssertTrue(app.buttons["Share assessment"].waitForExistence(timeout: 5)) }
        shot("01-updates")
        tab("Assessments", in: app).tap()
        app.buttons["Results"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Fractions in action"].waitForExistence(timeout: 5))
        if pad { app.staticTexts["Reading journal"].firstMatch.tap(); XCTAssertTrue(app.buttons["Share assessment"].waitForExistence(timeout: 5)); shot("02-results-with-detail") }
        else {
            shot("02-results")
            app.staticTexts["Reading journal"].firstMatch.tap()
            XCTAssertTrue(app.buttons["Share assessment"].waitForExistence(timeout: 5))
            shot("03-assessment")
            // A measured scroll that lands on the Feedback heading and its table.
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)))
            shot("04-feedback")
            goBack(in: app)
        }
        app.buttons["Upcoming"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Overdue"].waitForExistence(timeout: 5))
        // On iPad the detail pane would still show the result opened above, which doesn't match this list.
        if !pad { shot("05-upcoming") }
        tab("Timetable", in: app).tap()
        XCTAssertTrue(app.buttons["Next week"].waitForExistence(timeout: 5))
        shot("06-timetable-week")
        app.buttons["Day"].firstMatch.tap()
        shot("07-timetable-day")
        app.buttons["school-news"].tap()
        XCTAssertTrue(app.staticTexts["A week of curiosity"].waitForExistence(timeout: 10))
        app.staticTexts["A week of curiosity"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'School office'")).firstMatch.waitForExistence(timeout: 5))
        shot("08-news")
    }

    func testFeedbackTableWrapsAtLargeTextSize() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.staticTexts["Reading journal feedback"].tap()
        let description = "Clear evidence supports the main idea, with relevant examples explained throughout the response."
        scrollTo(description, app: app)
        let cell = app.staticTexts[description]
        XCTAssertTrue(cell.exists)
        XCTAssertGreaterThan(cell.frame.height, 100, "Long feedback should wrap onto multiple lines at accessibility text sizes")
        capture("Feedback table at accessibility text size")
    }

    func testAssessmentSubjectFilterSurvivesDetailNavigation() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        tab("Assessments", in: app).tap()
        let filter = app.buttons["assessment-subject-filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        filter.tap()
        app.buttons["English · 2026"].tap()
        XCTAssertTrue(app.staticTexts["Reading journal"].waitForExistence(timeout: 5))
        app.staticTexts["Reading journal"].tap()
        XCTAssertTrue(app.buttons["Share assessment"].waitForExistence(timeout: 5))
        goBack(in: app)
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Reading journal"].waitForExistence(timeout: 5))
        XCTAssertTrue(filter.label.contains("English") || (filter.value as? String)?.contains("English") == true)

        app.buttons["Select child: Alex Morgan"].tap()
        app.buttons["Sam Morgan"].tap()
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        XCTAssertTrue(filter.label.contains("All") || (filter.value as? String)?.contains("All") == true)
    }

    func testDemoReadingAndChildSwitching() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Reading journal feedback"].waitForExistence(timeout: 10))
        app.staticTexts["Reading journal feedback"].tap()
        scrollTo("Criterion", app: app)
        // News is in the list's top bar, not the detail's.
        goBack(in: app)
        app.buttons["school-news"].tap()
        XCTAssertTrue(app.staticTexts["A week of curiosity"].waitForExistence(timeout: 15))
        capture("News")
        app.staticTexts["A week of curiosity"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'School office'")).firstMatch.waitForExistence(timeout: 5))
        capture("News detail")
        goBack(in: app)
        app.buttons["Done"].tap()
        tab("Assessments", in: app).tap()
        XCTAssertTrue(app.staticTexts["Reading journal"].waitForExistence(timeout: 5))
        app.buttons["Upcoming"].tap()
        XCTAssertTrue(app.staticTexts["Persuasive writing"].waitForExistence(timeout: 5))
        capture("Assessments")
        app.buttons["Select child: Alex Morgan"].tap()
        app.buttons["Sam Morgan"].tap()
        // Selection resets detail navigation and preserves the active reading tab.
        app.buttons["Upcoming"].tap()
        XCTAssertTrue(app.staticTexts["Exploring ecosystems"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Persuasive writing"].exists)
        capture("Second child")
        app.buttons["Results"].tap()
        XCTAssertTrue(app.staticTexts["Reading journal"].waitForExistence(timeout: 5))
        app.staticTexts["Reading journal"].tap()
        scrollTo("Annotated work photo", app: app)
        XCTAssertTrue(app.staticTexts["Annotated work photo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Share Annotated work photo"].waitForExistence(timeout: 5))
        verifyRotation("Rotate Annotated work photo clockwise", app: app)
        capture("Assessment photo")
        scrollTo("Marked assessment.pdf", app: app)
        XCTAssertTrue(app.buttons["Share Marked assessment.pdf"].waitForExistence(timeout: 5))
        verifyRotation("Rotate Marked assessment.pdf clockwise", app: app)
        capture("Assessment PDF")
        capture("Assessment detail")
        tab("Timetable", in: app).tap()
        XCTAssertTrue(app.navigationBars["Timetable"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Next week"].exists)
        app.buttons["Day"].tap()
        XCTAssertTrue(app.buttons["Next day"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Previous day"].exists)
        XCTAssertTrue(app.staticTexts["English"].waitForExistence(timeout: 5))
        capture("Timetable")
        openReports(app)
        XCTAssertTrue(app.staticTexts["Student progress report"].waitForExistence(timeout: 5))
        capture("Reports")
        app.staticTexts["Student progress report"].tap()
        XCTAssertFalse(app.staticTexts["Couldn’t open report"].waitForExistence(timeout: 2))
        capture("PDF report")
    }
    func testAssessmentShareOpensPrintDialog() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        app.staticTexts["Reading journal feedback"].tap()
        XCTAssertTrue(app.buttons["Share assessment"].waitForExistence(timeout: 10))
        app.buttons["Share assessment"].tap()
        XCTAssertTrue(app.staticTexts["Printer"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["print"].exists || app.buttons["Print"].exists)
        capture("Assessment print preview")
        if app.buttons["Close"].exists { app.buttons["Close"].tap() } else if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
    }

    /// A reminder chip in the header opens that reminder's settings.
    func testReminderChipOpensItsRule() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        // Make a reminder for English, which the demo timetable has every school day.
        XCTAssertTrue(app.buttons["Switch school account"].waitForExistence(timeout: 10))
        app.buttons["Switch school account"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reminders for'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Add a reminder"].waitForExistence(timeout: 5))
        app.buttons["Add a reminder"].tap()
        let note = app.textFields.firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap(); note.typeText("Bring hat")
        app.buttons["Choose lessons"].tap()
        // Search the picker, then tap the lesson by its exact name (the Updates list behind the sheet has
        // "English, …" rows too).
        let search = app.searchFields["Search lessons"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("English")
        let english = app.buttons["English"]
        XCTAssertTrue(english.waitForExistence(timeout: 10))
        english.tap()
        XCTAssertTrue(english.isSelected, "English is ticked")
        // The back button hides while searching; close the search first.
        let pickerBar = app.navigationBars["Choose lessons"], back = pickerBar.buttons["BackButton"]
        if !back.exists { pickerBar.buttons.matching(NSPredicate(format: "label IN {'Cancel', 'Close'}")).firstMatch.tap() }
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        app.buttons["Save"].tap()
        // Back from Reminders to Accounts, whose Done closes the sheet.
        XCTAssertTrue(app.buttons["Add a reminder"].waitForExistence(timeout: 5))
        app.navigationBars.matching(NSPredicate(format: "identifier BEGINSWITH 'Reminders for'")).firstMatch.buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        // Its chip is in the header; tapping it opens Settings on that reminder's editor.
        let chip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reminder' AND label ENDSWITH 'Bring hat'")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        chip.tap()
        XCTAssertTrue(app.navigationBars["Bring hat"].waitForExistence(timeout: 5), "The reminder's editor opens")
        XCTAssertEqual(app.textFields.firstMatch.value as? String, "Bring hat")
        // The timetable's week shows it under each day with English.
        app.buttons["Cancel"].tap()
        app.navigationBars.matching(NSPredicate(format: "identifier BEGINSWITH 'Reminders for'")).firstMatch.buttons["BackButton"].tap()
        app.buttons["Done"].tap()
        tab("Timetable", in: app).tap()
        let weekChip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reminder for' AND label ENDSWITH ': Bring hat'")).firstMatch
        XCTAssertTrue(weekChip.waitForExistence(timeout: 10), "Each day with English shows the reminder in the week view")
        // Each day's heading names its cycle day.
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Show' AND label CONTAINS ', Day '")).firstMatch.exists)
        capture("Timetable week with reminders")
    }

    /// The week view names each day's place in the cycle: Days 1–5 then 6–10 at a fortnightly school, and a cycle of
    /// another length (here eight days) running on across weeks without Week A/B.
    func testWeekHeadingsShowCycleDays() {
        for (length, name) in [(10, "fortnight"), (8, "eight-day")] {
            let app = XCUIApplication()
            app.launchArguments = ["--demo"] + (length == 10 ? [] : ["--demo-cycle-length=\(length)"])
            app.launch()
            tab("Timetable", in: app).tap()
            XCTAssertTrue(app.buttons["Next week"].waitForExistence(timeout: 10))
            let heading = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Show' AND label CONTAINS ', Day '"))
            XCTAssertTrue(heading.firstMatch.waitForExistence(timeout: 10))
            capture("Week view, \(name) cycle, this week")
            app.buttons["Next week"].tap()
            XCTAssertTrue(heading.firstMatch.waitForExistence(timeout: 10))
            capture("Week view, \(name) cycle, next week")
            app.terminate()
        }
    }

    /// Results sort by mark and filter by kind; hiding marks leaves only the speech bubble in the list (and drops the
    /// mark orders, which would give them away), while the assessment itself still shows its mark.
    func testAssessmentSortFilterAndHiddenMarks() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        tab("Assessments", in: app).tap()
        XCTAssertTrue(app.staticTexts["Reading journal"].waitForExistence(timeout: 10))
        // Highest mark first: Physics' 94% leads.
        app.buttons["Sort and filter"].tap()
        app.buttons["Highest mark"].tap()
        let titles = ["Forces and motion investigation", "Reading journal", "Still life drawing", "Fractions in action", "Ancient civilisations poster"]
        let ys = titles.map { app.staticTexts[$0].frame.minY }
        XCTAssertEqual(ys, ys.sorted(), "94%, 90%, A- (88%), 84%, 76%")
        // Feedback only: Book talk (feedback, no mark) stays; Ancient civilisations poster (no feedback) goes.
        app.buttons["Sort and filter"].tap()
        app.buttons["With feedback"].tap()
        XCTAssertTrue(app.staticTexts["Book talk"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Ancient civilisations poster"].exists)
        capture("Assessments sorted and filtered")
        app.buttons["Sort and filter"].tap()
        app.buttons["Reset to default"].tap()
        XCTAssertTrue(app.staticTexts["Ancient civilisations poster"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["94%"].exists)
        // Hide marks in Settings.
        app.buttons["Switch school account"].tap()
        let hide = app.switches["Hide marks in lists"]
        XCTAssertTrue(hide.waitForExistence(timeout: 5))
        // Tap the switch itself (the right-hand end of the row); the label alone doesn't toggle it.
        if (hide.value as? String) != "1" { hide.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }
        XCTAssertEqual(hide.value as? String, "1")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Reading journal"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["94%"].exists, "No marks in the list")
        XCTAssertFalse(app.staticTexts["B+"].exists)
        XCTAssertGreaterThan(app.images.matching(NSPredicate(format: "label == 'Result released'")).count, 0)
        app.buttons["Sort and filter"].tap()
        XCTAssertFalse(app.buttons["Highest mark"].exists, "Ordering by mark would give marks away")
        app.buttons["Newest first"].tap()
        capture("Assessments with marks hidden")
        // The assessment itself still shows its mark.
        app.staticTexts["Forces and motion investigation"].tap()
        // (Every demo assessment opens the same sample marks, 90%.)
        XCTAssertTrue(app.staticTexts["90%"].waitForExistence(timeout: 5), "Marks still show on the assessment")
    }

    func testLunchLoadingShowsNoControls() {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--slow-lunch"]; app.launch()
        tab("Lunch", in: app).tap()
        let loading = app.descendants(matching: .any)["lunch-loading"]
        XCTAssertTrue(loading.waitForExistence(timeout: 5), "A loading indicator while My Student Account answers")
        XCTAssertEqual(loading.label, "Loading lunch")
        XCTAssertFalse(app.buttons["lunch-new-order"].exists, "Nothing to act on while loading")
        XCTAssertFalse(app.buttons["lunch-top-up"].exists)
        XCTAssertFalse(app.staticTexts["No lunch ordered yet."].exists, "No conclusions before the orders have loaded")
        capture("Lunch loading")
        XCTAssertTrue(app.staticTexts["lunch-balance-amount"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["lunch-new-order"].isEnabled)
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: loading)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
    }

    func testCompactLunchHistory() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        tab("Lunch", in: app).tap()
        let all = app.buttons["All past orders"]
        XCTAssertTrue(all.waitForExistence(timeout: 10))
        let rows = app.staticTexts.matching(NSPredicate(format: "label == 'Order #2040' OR label == 'Order #2039' OR label == 'Order #2038'"))
        XCTAssertEqual(rows.count, 3)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Order #2037'")).firstMatch.exists)
        let upcoming = app.staticTexts.matching(NSPredicate(format: "label == 'UPCOMING' OR label == 'Upcoming'")).firstMatch
        XCTAssertLessThan(upcoming.frame.minY - app.buttons["lunch-new-order"].frame.maxY, 30)
        let activity = app.buttons["lunch-account-activity"]
        XCTAssertTrue(activity.exists)
        // Top up and Activity are a matching pair stacked beside the balance, above New order.
        let topUp = app.buttons["lunch-top-up"], amount = app.staticTexts["lunch-balance-amount"]
        XCTAssertEqual(activity.frame.width, topUp.frame.width, accuracy: 1)
        XCTAssertEqual(activity.frame.height, topUp.frame.height, accuracy: 1)
        XCTAssertEqual(activity.frame.minX, topUp.frame.minX, accuracy: 1)
        XCTAssertGreaterThan(activity.frame.minY, topUp.frame.maxY)
        XCTAssertGreaterThan(topUp.frame.minX, amount.frame.maxX)
        XCTAssertLessThan(activity.frame.maxY, app.buttons["lunch-new-order"].frame.minY)
        capture("Compact lunch home")
        activity.tap()
        XCTAssertTrue(app.navigationBars["Account activity"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        all.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Order #2037'")).firstMatch.waitForExistence(timeout: 5))
    }

    func testWidgetLunchBalanceLayouts() {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--test-widget-layout"]; app.launch()
        let balances = app.staticTexts.matching(NSPredicate(format: "label == 'Lunch balance $18.50'"))
        XCTAssertTrue(balances.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(balances.count, 2, "Small and wider widgets show the balance")
        capture("Widget lunch balances")
        app.switches["widget-msa-connected"].tap()
        XCTAssertEqual(balances.count, 0, "No balance when MSA is disconnected")
        capture("Widgets without MSA")
    }

    func testNewsAndReportUnreadCounts() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let news = app.buttons["school-news"]
        XCTAssertTrue(news.waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["News"].exists)
        let fourUnread = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '4 unread'"), object: news)
        XCTAssertEqual(XCTWaiter.wait(for: [fourUnread], timeout: 10), .completed)
        news.tap()
        XCTAssertTrue(app.staticTexts["A week of curiosity"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.images["Unread"].exists, "Listing notices doesn't mark them read")
        let today = Date().formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "en_AU")))
        XCTAssertTrue(app.staticTexts["School office · \(today)"].exists, "Each notice shows the day it's listed under")
        app.staticTexts["A week of curiosity"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'School office'")).firstMatch.waitForExistence(timeout: 5))
        goBack(in: app)
        app.buttons["Done"].tap()
        XCTAssertEqual(news.value as? String, "3 unread", "Opening a notice marks it read")
        openReports(app)
        XCTAssertTrue(app.segmentedControls.buttons["reports-pane"].label.contains("2"))
        app.staticTexts["Student progress report"].tap()
        XCTAssertTrue(app.navigationBars["Student progress report"].waitForExistence(timeout: 5))
        let pdf = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'PDF'"))
        _ = pdf.firstMatch.waitForExistence(timeout: 2)
        goBack(in: app)
        let reports = app.segmentedControls.buttons["reports-pane"]
        XCTAssertTrue(reports.waitForExistence(timeout: 5))
        XCTAssertTrue(reports.label.contains("1"), "Only the opened report is read")
        app.buttons["Select child: Alex Morgan"].tap(); app.buttons["Sam Morgan"].tap()
        openReports(app)
        XCTAssertTrue(app.segmentedControls.buttons["reports-pane"].label.contains("2"), "The other child's reports remain unread")
        XCTAssertEqual(app.buttons["school-news"].value as? String, "3 unread", "News read state is shared by children on the same account")
        capture("Report and news unread badges")
    }

    func testCanteenSignInLoadsFromBareHost() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--test-canteen-sign-in"]
        app.launch()
        let address = app.textFields["msa.yourschool.edu.au"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        // A neutral host: this checks a bare host opens in the sign-in browser, without contacting any real school.
        address.tap(); address.typeText("example.com")
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["example.com"].waitForExistence(timeout: 30), "The browser opens on the portal's host")
        let progress = app.activityIndicators["canteen-login-progress"]
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: progress)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 35), .completed, "Browser loading changes must reach the screen")
        // example.com answers /wp/Profile/Accounts without a portal session, so connecting stops with an explanation.
        XCTAssertTrue(app.staticTexts["canteen-login-error"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["canteen-login-error"].label.contains("My Student Account"))
        XCTAssertTrue(app.webViews.firstMatch.exists)
        capture("MSA sign-in browser")
        app.buttons["Change address"].tap()
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        XCTAssertEqual(address.value as? String, "example.com")
        // No credentials are entered and no lunch account is linked by this test.
    }

    func testSchoolSignInEntry() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Connect your school"].tap()
        let portal = app.textFields["https://engage.yourschool.edu.au"]
        // A neutral address: this checks the sign-in browser opens and loads, without contacting any real school.
        portal.tap(); portal.typeText("https://example.com")
        XCTAssertEqual(portal.value as? String, "https://example.com")
        capture("Connect school")
        app.buttons["Continue to school sign-in"].tap()
        XCTAssertTrue(app.buttons["Continue to reader"].waitForExistence(timeout: 10))
        let progress = app.activityIndicators["school-login-progress"]
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: progress)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 30), .completed)
        XCTAssertFalse(app.staticTexts["school-login-error"].exists)
        capture("School sign-in browser")
        // No school credentials are supplied by the test.
    }

    private func verifyRotation(_ label: String, app: XCUIApplication) {
        let button = app.buttons[label]
        for angle in [90, 180, 270, 0] {
            button.tap()
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "\(angle) degrees"), object: button)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        }
    }
    /// Reports are the third segment of Assessments.
    private func openReports(_ app: XCUIApplication) {
        tab("Assessments", in: app).tap()
        let segment = app.segmentedControls.buttons["reports-pane"].firstMatch
        // The tab may still show an assessment opened earlier; back out to the list.
        for _ in 0..<3 where !segment.waitForExistence(timeout: 2) { goBack(in: app) }
        XCTAssertTrue(segment.waitForExistence(timeout: 5)); segment.tap()
    }
    /// Back out of a pushed screen: the back button where there is one, otherwise the edge swipe.
    private func goBack(in app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists && back.isHittable { back.tap(); return }
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        edge.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
    }
    /// A tab, whether iOS shows tabs as a bottom bar (iPhone), a top bar (iPad) or a side rail (iPhone Duo).
    private func tab(_ name: String, in app: XCUIApplication) -> XCUIElement {
        let inBar = app.tabBars.buttons[name]
        return inBar.exists ? inBar : app.buttons.matching(identifier: name).firstMatch.exists
            ? app.buttons.matching(identifier: name).firstMatch : app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch
    }
    private func scrollTo(_ text: String, app: XCUIApplication) {
        for _ in 0..<5 {
            if app.staticTexts[text].exists { return }
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts[text].exists)
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
