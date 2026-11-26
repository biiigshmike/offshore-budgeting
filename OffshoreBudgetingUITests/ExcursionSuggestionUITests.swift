import XCTest

@MainActor
final class ExcursionSuggestionUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    override func tearDownWithError() throws {
        if let testRun, testRun.failureCount > 0 {
            let app = XCUIApplication()
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Excursion suggestion navigation failure"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    func testChoosingMerchantOpensEditableQuickAdd() {
        let app = launch(mode: "multiple")
        XCTAssertTrue(app.navigationBars["Nearby Places"].waitForExistence(timeout: 10))
        app.buttons["Nearby Store B"].tap()
        assertExpenseForm(app, description: "Nearby Store B")
        let description = app.textFields["Description"]
        description.tap()
        description.typeText(" corrected")
        XCTAssertTrue((description.value as? String)?.contains("corrected") == true)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Add Expense"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Nearby Places"].exists)
    }

    func testOtherOpensUnprefilledQuickAdd() {
        let app = launch(mode: "multiple")
        XCTAssertTrue(app.buttons["Other"].waitForExistence(timeout: 10))
        app.buttons["Other"].tap()
        XCTAssertTrue(app.navigationBars["Add Expense"].waitForExistence(timeout: 5))
        let description = app.textFields["Description"]
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        XCTAssertFalse((description.value as? String)?.contains("Nearby Store") == true)
        description.tap()
        description.typeText("A different place")
        XCTAssertEqual(description.value as? String, "A different place")
        app.buttons["Cancel"].tap()
    }

    func testWrongWorkspaceRequiresExplicitSwitch() {
        let app = launch(mode: "wrongWorkspace")
        let change = app.buttons["Switch to Other Workspace"]
        XCTAssertTrue(change.waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Add Expense"].exists)
        XCTAssertFalse(app.buttons["Nearby Store A"].exists)
        change.tap()
        XCTAssertTrue(app.navigationBars["Nearby Places"].waitForExistence(timeout: 10))
        app.buttons["Nearby Store A"].tap()
        assertExpenseForm(app, description: "Nearby Store A")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Other Workspace Card")).firstMatch.exists)
        app.buttons["Cancel"].tap()
    }

    func testDeletedWorkspaceCannotOpenExpenseForm() {
        let app = launch(mode: "deletedWorkspace")
        XCTAssertTrue(app.staticTexts["Workspace Unavailable"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Add Expense"].exists)
        XCTAssertFalse(app.buttons["Nearby Store A"].exists)
        XCTAssertFalse(app.buttons["Save"].exists)
        app.buttons["Cancel"].tap()
    }

    func testLegacySingleMerchantStillOpensQuickAdd() {
        let app = launch(mode: "legacy")
        assertExpenseForm(app, description: "Legacy Merchant")
        app.buttons["Cancel"].tap()
    }

    private func launch(mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingReset", "-uiTestScenarioWorkspaceProgress",
            "-uiTestExcursionRoute", mode,
            "-debug_tabFlickerDiagnosticsEnabled", "YES",
            "-debug_tabFlickerVerboseEventsEnabled", "YES",
            "-tips_seenKeys", "tip.home.v1,tip.budgets.v1,tip.cards.v1,tip.income.v1,tip.budgetdetail.v1",
            "-tips_resetToken", "0", "-tips_seen_lastResetToken", "0",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        return app
    }

    private func assertExpenseForm(_ app: XCUIApplication, description expected: String) {
        XCTAssertTrue(app.navigationBars["Add Expense"].waitForExistence(timeout: 10))
        let description = app.textFields["Description"]
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        XCTAssertEqual(description.value as? String, expected)
        XCTAssertFalse(app.buttons["Save"].isEnabled)
    }
}
