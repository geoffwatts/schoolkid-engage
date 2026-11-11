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
        tab("Reports", in: app).tap()
        app.staticTexts["Student progress report"].tap()
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        capture("Full bleed report")
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
        tab("Reports", in: app).tap()
        try audit("Reports")
        tab("News", in: app).tap()
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
        tab("News", in: app).tap()
        XCTAssertTrue(app.staticTexts["A week of curiosity"].waitForExistence(timeout: 10))
        app.staticTexts["A week of curiosity"].tap()
        XCTAssertTrue(app.staticTexts["School office"].waitForExistence(timeout: 5))
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
        tab("News", in: app).tap()
        XCTAssertTrue(app.staticTexts["A week of curiosity"].waitForExistence(timeout: 15))
        capture("News")
        app.staticTexts["A week of curiosity"].tap()
        XCTAssertTrue(app.staticTexts["School office"].waitForExistence(timeout: 5))
        capture("News detail")
        goBack(in: app)
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
        tab("Reports", in: app).tap()
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
