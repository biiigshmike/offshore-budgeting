import XCTest

@MainActor
final class BudgetDetailTipsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testBudgetDetailTipReappearsAfterReset() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingReset", "-uiTestScenarioBudgetMenus",
            "-tips_seenKeys", "tip.home.v1,tip.budgets.v1,tip.budgetdetail.v1",
            "-tips_resetToken", "0", "-tips_seen_lastResetToken", "0",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()

        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 15))
        tabs.buttons["Budgets"].tap()

        let budget = app.staticTexts["Existing Menu Budget"].firstMatch
        let detail = app.navigationBars["Existing Menu Budget"]
        let tip = app.staticTexts["Budget Detail Overview"]
        XCTAssertTrue(budget.waitForExistence(timeout: 5))
        budget.tap()
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertFalse(tip.waitForExistence(timeout: 2))
        detail.buttons["Budgets"].tap()

        tabs.buttons["Settings"].tap()
        let general = app.buttons["settings_general"].firstMatch
        XCTAssertTrue(general.waitForExistence(timeout: 5))
        general.tap()
        let maintenance = app.buttons["Maintenance"].firstMatch
        for _ in 0..<5 where !maintenance.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(maintenance.isHittable)
        maintenance.tap()
        let resetTips = app.buttons["Reset Tips & Hints"]
        XCTAssertTrue(resetTips.waitForExistence(timeout: 5))
        resetTips.tap()
        let confirmation = app.alerts["Reset Tips & Hints?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["Reset"].tap()
        let result = app.alerts["Tips & Hints Reset"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.buttons["OK"].tap()

        tabs.buttons["Budgets"].tap()
        let continueButton = app.buttons["Continue"].firstMatch
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        XCTAssertFalse(tip.exists)
        continueButton.tap()

        XCTAssertTrue(budget.waitForExistence(timeout: 5))
        budget.tap()
        XCTAssertTrue(tip.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open Help Guide"].exists)
        continueButton.tap()
        XCTAssertTrue(tip.waitForNonExistence(timeout: 5))

        detail.buttons["Budgets"].tap()
        XCTAssertTrue(budget.waitForExistence(timeout: 5))
        budget.tap()
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertFalse(tip.waitForExistence(timeout: 2))
    }
}
