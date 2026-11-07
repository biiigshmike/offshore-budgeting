import XCTest

@MainActor
final class CategoryGoalSavingsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testFullBudgetScenarioStaysStableWhileFilteringExpenses() throws {
        let app = launchBudget()
        editBillsMaximum("100", in: app)
        let scenario = showScenario(in: app)
        let fullBudgetLabel = scenario.label
        attachScreenshot("Savings at goal maximums on a compact phone", in: app)

        // Selecting Bills hides expenses in the other seeded categories, but must not
        // change the full-budget scenario.
        let categories = app.buttons["detailList.categories"]
        categories.tap()
        app.buttons["Deselect All"].tap()
        let bills = app.buttons["Bills"]
        XCTAssertTrue(bills.waitForExistence(timeout: 5))
        bills.tap()
        let dismissMenu = app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        dismissMenu.tap()
        XCTAssertEqual(showScenario(in: app).label, fullBudgetLabel)

        categories.tap()
        XCTAssertTrue(bills.waitForExistence(timeout: 5))
        bills.tap()
        dismissMenu.tap()
        app.buttons["detailList.expenseType"].tap()
        app.buttons["Variable"].tap()
        XCTAssertEqual(showScenario(in: app).label, fullBudgetLabel)

        let search = app.searchFields.firstMatch
        revealAbove(search, in: app)
        search.tap()
        let query = "No matching expense for this scenario"
        search.typeText(query + XCUIKeyboardKey.return.rawValue)
        XCTAssertEqual(search.value as? String, query)
        XCTAssertEqual(showScenario(in: app).label, fullBudgetLabel)
    }

    func testGoalEditsZeroMaximumAndRemovingTheFinalMaximumRefreshImmediately() throws {
        let app = launchBudget()
        editBillsMaximum("100", in: app)
        let originalLabel = showScenario(in: app).label

        editBillsMaximum("300", in: app)
        let changed = showScenario(in: app)
        let updated = NSPredicate(format: "label != %@", originalLabel)
        expectation(for: updated, evaluatedWith: changed)
        waitForExpectations(timeout: 5)

        // A zero maximum is still a real goal and must keep the scenario visible.
        editBillsMaximum("0", in: app)
        XCTAssertTrue(showScenario(in: app).exists)

        editBillsMaximum("", in: app)
        revealAbove(app.staticTexts["Savings Outlook"].firstMatch, in: app)
        XCTAssertTrue(scenarioRow(in: app).waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[scenarioFootnote].exists)
    }

    func testLargestAccessibilityTextKeepsEstimateAndExplanationReachable() throws {
        let app = launchBudget(extraArguments: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        editBillsMaximum("100", in: app)
        let scenario = showScenario(in: app)
        XCTAssertTrue(scenario.isHittable)
        XCTAssertGreaterThanOrEqual(scenario.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(scenario.frame.maxX, app.frame.maxX + 1)
        XCTAssertTrue(app.buttons["detailList.categories"].isHittable)
        app.buttons["detailList.expenseType"].tap()
        let combined = app.buttons["Combined"]
        XCTAssertTrue(combined.waitForExistence(timeout: 5))
        combined.tap()
        app.buttons["detailList.sort"].tap()
        let newest = app.buttons["Newest first"]
        XCTAssertTrue(newest.waitForExistence(timeout: 5))
        newest.tap()
        attachScreenshot("Savings at goal maximums at largest accessibility text size", in: app)

        let footnote = app.staticTexts[scenarioFootnote]
        revealBelow(footnote, in: app)
        XCTAssertTrue(footnote.isHittable)
        XCTAssertLessThanOrEqual(footnote.frame.maxX, app.frame.maxX + 1)
        attachScreenshot("Full-budget scenario explanation at largest accessibility text size", in: app)
    }

    private let scenarioFootnote = "Full-budget estimate if you use your remaining category allowances. Spending already above a maximum is included."

    private func launchBudget(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingReset", "-uiTestScenarioBudgetMenus", "-uiTestCategoryDetailHistory",
            "-tips_seenKeys", "tip.home.v1,tip.budgets.v1,tip.cards.v1,tip.income.v1,tip.budgetdetail.v1,tip.categories.v1",
            "-general_currencyCode", "USD", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ] + extraArguments
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Budgets"].tap()
        let budget = app.staticTexts["Existing Menu Budget"].firstMatch
        XCTAssertTrue(budget.waitForExistence(timeout: 5))
        budget.tap()
        XCTAssertTrue(app.navigationBars["Existing Menu Budget"].waitForExistence(timeout: 5))
        return app
    }

    private func editBillsMaximum(_ amount: String, in app: XCUIApplication) {
        let budgetActions = app.buttons["Budget Actions"]
        let categoryGoals = app.buttons["Category Goals"].firstMatch
        if !budgetActions.isHittable {
            app.navigationBars["Existing Menu Budget"].buttons["More"].tap()
        }
        if !categoryGoals.exists {
            budgetActions.tap()
        }
        XCTAssertTrue(categoryGoals.waitForExistence(timeout: 5))
        categoryGoals.tap()
        XCTAssertTrue(app.navigationBars["Category Goals"].waitForExistence(timeout: 5))
        let bills = app.staticTexts["Bills"].firstMatch
        revealBelow(bills, in: app)
        bills.tap()
        XCTAssertTrue(app.navigationBars["Bills"].waitForExistence(timeout: 5))
        let maximum = app.textFields["Maximum"]
        revealBelow(maximum, in: app)
        maximum.tap()
        let current = maximum.value as? String ?? ""
        let text = current == maximum.placeholderValue ? "" : current
        maximum.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count) + amount)
        app.navigationBars["Bills"].buttons["Category Goals"].tap()
        app.navigationBars["Category Goals"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Category Goals"].waitForNonExistence(timeout: 5))
    }

    private func scenarioRow(in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "label BEGINSWITH %@", "Savings at Goal Maximums")
        let text = app.staticTexts.matching(predicate).firstMatch
        return text.exists ? text : app.otherElements.matching(predicate).firstMatch
    }

    @discardableResult
    private func showScenario(in app: XCUIApplication) -> XCUIElement {
        // The goals menu opens above the list, so the overview may be below the fold.
        for _ in 0..<10 {
            let row = scenarioRow(in: app)
            if row.exists && row.isHittable { return row }
            app.swipeUp()
        }
        let row = scenarioRow(in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.isHittable)
        return row
    }

    private func revealBelow(_ element: XCUIElement, in app: XCUIApplication) {
        let bottom = app.frame.maxY - 24
        for _ in 0..<12 {
            if element.exists && element.isHittable && element.frame.midY < bottom { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    private func revealAbove(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            app.swipeDown()
        }
        XCTAssertTrue(element.isHittable)
    }

    private func attachScreenshot(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
