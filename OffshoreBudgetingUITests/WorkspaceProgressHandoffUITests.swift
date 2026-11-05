import XCTest

@MainActor
final class WorkspaceProgressHandoffUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testOnboardingDoneOpensProgressAndNestedFormsReturnUntilSkip() throws {
        let app = makeApp(extraArguments: ["-uiTestProgressFinishOnboarding"])
        app.launch()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        done.tap()

        assertHandoff(in: app)
        assertProgress(80, completed: 4, in: app)
        openAndCloseHelpGuide(in: app)
        assertHandoff(in: app)
        assertProgress(80, completed: 4, in: app)
        attachScreenshot("Onboarding hands off to Workspace Progress", app: app)
        let guidance = app.staticTexts["You can return to Workspace Progress in Settings."]
        reveal(guidance, in: app)

        let addIncome = app.buttons["workspaceProgressAdd_income"]
        reveal(addIncome, in: app)
        addIncome.tap()
        XCTAssertTrue(app.navigationBars["Add Income"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        assertHandoff(in: app)
        assertProgress(80, completed: 4, in: app)

        reveal(addIncome, in: app)
        addIncome.tap()
        XCTAssertTrue(app.navigationBars["Add Income"].waitForExistence(timeout: 5))
        let source = app.textFields["Source"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap()
        source.typeText("Handoff paycheck")
        let amount = app.textFields["Amount"]
        amount.tap()
        amount.typeText("2500")
        app.buttons["Save"].tap()

        assertHandoff(in: app)
        assertProgress(100, completed: 5, in: app)
        let completion = element("workspaceProgressComplete", in: app)
        reveal(completion, in: app)
        attachScreenshot("Completed progress remains open", app: app)
        app.buttons["workspaceProgressSkip"].tap()
        assertHome(in: app)

        openSettings(app)
        let progressRow = element("settingsWorkspaceProgress", in: app)
        XCTAssertTrue(progressRow.waitForExistence(timeout: 5))
        progressRow.tap()
        XCTAssertTrue(app.navigationBars["Workspace Progress"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["workspaceProgressSkip"].exists)
        XCTAssertFalse(app.buttons["Open Help Guide"].exists)
        XCTAssertFalse(guidance.exists)
        assertProgress(100, completed: 5, in: app)
    }

    func testCompletedWorkspaceGoesDirectlyHome() throws {
        let app = makeApp(extraArguments: ["-uiTestProgressHandoff", "-uiTestProgressComplete"])
        app.launch()
        assertHome(in: app)
        XCTAssertFalse(app.buttons["workspaceProgressSkip"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.navigationBars["Workspace Progress"].exists)
    }

    func testHandoffHelpGuideAtLargestAccessibilityTextSize() {
        let app = makeApp(extraArguments: [
            "-uiTestProgressHandoff",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        app.launch()

        assertHandoff(in: app)
        let link = app.buttons["Open Help Guide"]
        reveal(link, in: app)
        XCTAssertGreaterThanOrEqual(link.frame.height, 44)
        attachScreenshot("Workspace Progress help link at largest text size", app: app)
        link.tap()
        let help = app.navigationBars["Help"]
        XCTAssertTrue(help.waitForExistence(timeout: 5))
        help.buttons["Done"].tap()
        assertHandoff(in: app)
    }

    func testDelayedWorkspaceArrivalPreservesRequestedWorkspace() throws {
        let app = makeApp(extraArguments: ["-uiTestProgressDelayedWorkspace"])
        app.launch()
        assertHandoff(in: app)
        assertProgress(80, completed: 4, in: app)
        let summary = element("workspaceProgressSummary", in: app)
        XCTAssertTrue(summary.label.contains("Progress Workspace"))
        XCTAssertFalse(summary.label.contains("Other Workspace"))
        attachScreenshot("Delayed discovery keeps requested workspace", app: app)

        app.buttons["workspaceProgressSkip"].tap()
        assertHome(in: app)
        openSettings(app)
        let progressRow = element("settingsWorkspaceProgress", in: app)
        XCTAssertTrue(progressRow.waitForExistence(timeout: 5))
        progressRow.tap()
        XCTAssertTrue(app.navigationBars["Workspace Progress"].waitForExistence(timeout: 5))
        assertProgress(80, completed: 4, in: app)
        XCTAssertTrue(summary.label.contains("Progress Workspace"))
    }

    func testInteractiveDismissalDoesNotReopenOnRelaunch() throws {
        let app = makeApp(extraArguments: ["-uiTestProgressHandoff"])
        app.launch()
        assertHandoff(in: app)
        let header = app.navigationBars["Workspace Progress"]
        header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        assertHome(in: app)

        app.terminate()
        app.launchArguments.removeAll { $0 == "-uiTestingReset" }
        app.launchArguments.append("-uiTestPreserveScenarioData")
        app.launch()
        assertHome(in: app)
        XCTAssertFalse(app.buttons["workspaceProgressSkip"].waitForExistence(timeout: 2))
    }

    func testReleaseNotesAndHomeTipsWaitForHandoffDismissal() throws {
        let app = makeApp(extraArguments: ["-uiTestProgressHandoff", "-uiTestProgressPendingPrompts"], pendingTips: true)
        app.launch()
        assertHandoff(in: app)
        let releaseTitle = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "What’s New in ")).firstMatch
        XCTAssertFalse(releaseTitle.exists)
        XCTAssertFalse(app.staticTexts["Dashboard"].exists)
        XCTAssertFalse(app.navigationBars["Review Expenses"].exists)
        attachScreenshot("Progress precedes automatic prompts", app: app)

        app.buttons["workspaceProgressSkip"].tap()
        XCTAssertTrue(releaseTitle.waitForExistence(timeout: 10))
        app.buttons["Continue"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Dashboard"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Review Expenses"].exists)
        let helpButton = app.buttons["Open Help Guide"]
        let continueButton = app.buttons["Continue"].firstMatch
        XCTAssertTrue(helpButton.isHittable)
        XCTAssertLessThanOrEqual(helpButton.frame.maxY, continueButton.frame.minY)
        openAndCloseHelpGuide(in: app)
        XCTAssertTrue(helpButton.isHittable)
        XCTAssertTrue(app.staticTexts["Dashboard"].exists)
        app.buttons["Continue"].firstMatch.tap()
        let review = app.navigationBars["Review Expenses"]
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        let reviewedExpense = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Handoff review expense")).firstMatch
        XCTAssertTrue(reviewedExpense.waitForExistence(timeout: 5))
        app.buttons["Skip"].tap()
        XCTAssertTrue(review.waitForNonExistence(timeout: 5))
        assertHome(in: app)
        XCTAssertFalse(helpButton.exists)
    }

    func testSwipingHomeTipDoesNotReopenItWhenPresentationBecomesIdle() throws {
        let app = makeApp(extraArguments: ["-uiTestProgressHandoff", "-uiTestProgressPendingPrompts"], pendingTips: true)
        app.launch()
        assertHandoff(in: app)
        app.buttons["workspaceProgressSkip"].tap()
        let releaseTitle = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "What’s New in ")).firstMatch
        XCTAssertTrue(releaseTitle.waitForExistence(timeout: 10))
        app.buttons["Continue"].firstMatch.tap()
        let dashboard = app.staticTexts["Dashboard"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 10))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        XCTAssertTrue(app.navigationBars["Review Expenses"].waitForExistence(timeout: 10))
        app.buttons["Skip"].tap()
        assertHome(in: app)
        XCTAssertFalse(dashboard.waitForExistence(timeout: 2))
    }

    func testSkippingExistingCloudOnboardingUsesCompletionEligibility() throws {
        for completed in [false, true] {
            let app = makeApp(extraArguments: ["-uiTestProgressSkipOnboarding"] + (completed ? ["-uiTestProgressComplete"] : []))
            app.launch()
            let skip = app.alerts["Existing iCloud Data Detected"].buttons["Skip Onboarding"]
            XCTAssertTrue(skip.waitForExistence(timeout: 10))
            skip.tap()
            if completed {
                assertHome(in: app)
                XCTAssertFalse(app.buttons["workspaceProgressSkip"].waitForExistence(timeout: 2))
            } else {
                assertHandoff(in: app)
                app.buttons["workspaceProgressSkip"].tap()
                assertHome(in: app)
            }
            app.terminate()
        }
    }

    private func makeApp(extraArguments: [String], pendingTips: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingReset", "-uiTestScenarioWorkspaceProgress",
            "-tips_seenKeys", pendingTips ? "" : "tip.home.v1,tip.budgets.v1,tip.cards.v1,tip.income.v1,tip.budgetdetail.v1",
            "-tips_resetToken", "0", "-tips_seen_lastResetToken", "0",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ] + extraArguments
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func assertHandoff(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["workspaceProgressSkip"].waitForExistence(timeout: 15))
        let navigationBar = app.navigationBars["Workspace Progress"]
        XCTAssertTrue(navigationBar.exists)
        let skip = navigationBar.buttons["workspaceProgressSkip"]
        XCTAssertTrue(skip.exists)
        XCTAssertEqual(skip.label, "Skip")
    }

    private func assertHome(in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["workspaceProgressSkip"].exists)
        XCTAssertFalse(app.navigationBars["Settings"].exists)
    }

    private func assertProgress(_ percent: Int, completed: Int, in app: XCUIApplication) {
        let summary = element("workspaceProgressSummary", in: app)
        for _ in 0..<10 {
            if summary.exists && summary.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        let expected = NSPredicate(format: "value CONTAINS %@", "\(percent) percent, \(completed) of 5 completed")
        expectation(for: expected, evaluatedWith: summary)
        waitForExpectations(timeout: 5)
    }

    private func openSettings(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons["Settings"]
        if tab.waitForExistence(timeout: 2) {
            tab.tap()
        } else {
            let settings = app.staticTexts["Settings"].firstMatch
            if !settings.exists || !settings.isHittable {
                let sidebar = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "sidebar")).firstMatch
                if sidebar.exists { sidebar.tap() }
            }
            XCTAssertTrue(settings.waitForExistence(timeout: 5))
            settings.tap()
        }
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    private func openAndCloseHelpGuide(in app: XCUIApplication) {
        let link = app.buttons["Open Help Guide"]
        reveal(link, in: app)
        link.tap()
        let help = app.navigationBars["Help"]
        XCTAssertTrue(help.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Getting Started"].exists)
        attachScreenshot("Help Guide opened", app: app)
        let introduction = app.descendants(matching: .any).matching(identifier: "Introduction").firstMatch
        XCTAssertTrue(introduction.waitForExistence(timeout: 5))
        help.buttons["Done"].tap()
        XCTAssertTrue(help.waitForNonExistence(timeout: 5))
    }

    private func attachScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
