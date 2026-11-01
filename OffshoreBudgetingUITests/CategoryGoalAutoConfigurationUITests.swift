import XCTest

@MainActor
final class CategoryGoalAutoConfigurationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingReset", "-uiTestScenarioBudgetMenus", "-uiTestCategoryGoalHistory",
            "-tips_seenKeys", "tip.home.v1,tip.budgets.v1,tip.cards.v1,tip.income.v1,tip.budgetdetail.v1,tip.categories.v1",
            "-general_defaultBudgetingPeriod", "monthly", "-general_currencyCode", "USD",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 15))
        return app
    }

    private func openNewGoals(in app: XCUIApplication) {
        app.tabBars.buttons["Budgets"].tap()
        app.buttons["Add Budget"].tap()
        XCTAssertTrue(app.navigationBars["Add Budget"].waitForExistence(timeout: 5))
        app.buttons["budget.cards"].tap()
        app.buttons["Select All"].tap()
        app.navigationBars["Add Budget"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["budget.presets"].tap()
        app.buttons["Select All"].tap()
        app.navigationBars["Add Budget"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["budget.categoryGoals"].tap()
        XCTAssertTrue(app.navigationBars["Category Goals"].waitForExistence(timeout: 5))
    }

    private func toggleAutoConfigure(in app: XCUIApplication) {
        let toggle = app.switches["categoryGoals.autoConfigure"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }

    func testSuggestionsExplainHistoryRestoreAndSaveAsDrafts() throws {
        let app = launchApp()
        openNewGoals(in: app)
        XCTAssertEqual(app.switches["categoryGoals.autoConfigure"].value as? String, "0")
        toggleAutoConfigure(in: app)
        app.staticTexts["Bills"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Bills"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["Minimum"].value as? String, "860.00")
        XCTAssertEqual(app.textFields["Maximum"].value as? String, "1,400.00")
        let disclosure = app.buttons["categoryGoals.historyDisclosure"]
        if !disclosure.isHittable { app.swipeUp() }
        disclosure.tap()
        XCTAssertTrue(app.staticTexts["History 1"].waitForExistence(timeout: 3))
        if !app.staticTexts["History 3"].exists { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["History 3"].exists)
        let history = XCTAttachment(screenshot: app.screenshot())
        history.name = "Category maximum history reference"
        history.lifetime = .keepAlways
        add(history)
        app.navigationBars["Bills"].buttons["Category Goals"].tap()
        toggleAutoConfigure(in: app)
        app.staticTexts["Bills"].firstMatch.tap()
        XCTAssertEqual(app.textFields["Minimum"].value as? String, "Minimum")
        XCTAssertEqual(app.textFields["Maximum"].value as? String, "Maximum")
        app.navigationBars["Bills"].buttons["Category Goals"].tap()
        toggleAutoConfigure(in: app)
        app.staticTexts["New Category"].firstMatch.tap()
        XCTAssertEqual(app.textFields["Maximum"].value as? String, "Maximum")
        app.navigationBars["New Category"].buttons["Category Goals"].tap()
        app.navigationBars["Category Goals"].buttons["Cancel"].tap()
        app.buttons["budget.categoryGoals"].tap()
        app.staticTexts["Bills"].firstMatch.tap()
        XCTAssertEqual(app.textFields["Maximum"].value as? String, "Maximum")
        app.navigationBars["Bills"].buttons["Category Goals"].tap()
        toggleAutoConfigure(in: app)
        app.buttons["Done"].tap()
        let savedBudgetName = try XCTUnwrap(app.textFields["budget.name"].value as? String)
        app.navigationBars["Add Budget"].buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Add Budget"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Budgets"].waitForExistence(timeout: 5))
        // Reopen the newly saved budget and verify that the draft became a saved goal.
        let savedBudget = app.staticTexts[savedBudgetName].firstMatch
        XCTAssertTrue(savedBudget.waitForExistence(timeout: 5))
        savedBudget.tap()
        let goals = app.buttons["Goals"]
        for _ in 0..<3 {
            if goals.isHittable { break }
            app.swipeUp()
        }
        goals.tap()
        app.staticTexts["Bills"].firstMatch.tap()
        XCTAssertEqual(app.textFields["Maximum"].value as? String, "1,400.00")
    }

    func testWorkspaceSettingsChangeNewSuggestionsAndCanDisableMaximums() throws {
        let app = launchApp()
        app.tabBars.buttons["Settings"].tap()
        let categories = app.buttons["Manage Categories"]
        if !categories.isHittable { app.swipeUp() }
        categories.tap()
        app.buttons["categories.autoConfigureGoals"].tap()
        XCTAssertTrue(app.navigationBars["Auto-Configure Goals"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["categoryGoals.settings.suggestMaximums"].value as? String, "1")
        let cushion = app.steppers["categoryGoals.settings.cushionPercent"]
        cushion.buttons["categoryGoals.settings.cushionPercent-Increment"].tap()
        XCTAssertTrue(cushion.buttons["categoryGoals.settings.cushionPercent-Increment"].label.contains("5%"))
        app.navigationBars["Auto-Configure Goals"].buttons.element(boundBy: 0).tap()
        app.buttons["categories.autoConfigureGoals"].tap()
        XCTAssertTrue(cushion.buttons["categoryGoals.settings.cushionPercent-Increment"].label.contains("5%"))
        openNewGoals(in: app)
        toggleAutoConfigure(in: app)
        app.staticTexts["Bills"].firstMatch.tap()
        XCTAssertEqual(app.textFields["Maximum"].value as? String, "1,470.00")
        app.navigationBars["Bills"].buttons["Category Goals"].tap()
        app.navigationBars["Category Goals"].buttons["Cancel"].tap()
        app.navigationBars["Add Budget"].buttons["Cancel"].tap()
        app.tabBars.buttons["Settings"].tap()
        let toggle = app.switches["categoryGoals.settings.suggestMaximums"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        openNewGoals(in: app)
        toggleAutoConfigure(in: app)
        app.staticTexts["Bills"].firstMatch.tap()
        XCTAssertEqual(app.textFields["Minimum"].value as? String, "860.00")
        XCTAssertEqual(app.textFields["Maximum"].value as? String, "Maximum")
    }
}
