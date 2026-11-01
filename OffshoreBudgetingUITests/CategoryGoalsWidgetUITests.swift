import XCTest

@MainActor
final class CategoryGoalsWidgetUITests: XCTestCase {
    private let diningRowID = "homeCategoryGoals.category.C1000000-0000-0000-0000-000000000001"

    override func setUpWithError() throws { continueAfterFailure = false }

    func testRowEditsBudgetGoalAndCancelPreservesSavedValue() {
        let app = launchHome()
        let dining = app.buttons[diningRowID]
        reveal(dining, in: app)
        XCTAssertTrue((dining.value as? String ?? "").contains("$70.00"))
        XCTAssertFalse(app.staticTexts["Category Availability"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Goals from ")).firstMatch.exists)
        dining.tap()
        XCTAssertTrue(app.navigationBars["Detail Dining"].waitForExistence(timeout: 5))
        // Home includes both cards; the editor summarizes the budget's linked Ruby card only.
        XCTAssertTrue(app.staticTexts["$25.00"].firstMatch.exists)
        setMaximum("100", in: app)
        app.navigationBars["Detail Dining"].buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Detail Dining"].waitForNonExistence(timeout: 5))
        reveal(dining, in: app)
        let saved = NSPredicate(format: "value CONTAINS %@", "$100.00")
        expectation(for: saved, evaluatedWith: dining)
        waitForExpectations(timeout: 5)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Category Goals after saving a maximum from Home"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        dining.tap()
        XCTAssertTrue(app.navigationBars["Detail Dining"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["Maximum"].value as? String, "100.00")
        setMaximum("300", in: app)
        app.navigationBars["Detail Dining"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Detail Dining"].waitForNonExistence(timeout: 5))
        reveal(dining, in: app)
        XCTAssertTrue(saved.evaluate(with: dining))

        // The Home edit must update the same budget-scoped goal used in Budget Detail.
        app.tabBars.buttons["Budgets"].tap()
        app.staticTexts["Existing Menu Budget"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Existing Menu Budget"].waitForExistence(timeout: 5))
        let goals = app.buttons["Goals"].firstMatch
        reveal(goals, in: app)
        goals.tap()
        XCTAssertTrue(app.navigationBars["Category Goals"].waitForExistence(timeout: 5))
        app.staticTexts["Detail Dining"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Detail Dining"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["Maximum"].value as? String, "100.00")
    }

    func testLargestAccessibilityTextKeepsCategoryEditingReachable() {
        let app = launchHome(extraArguments: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        let dining = app.buttons[diningRowID]
        reveal(dining, in: app)
        XCTAssertGreaterThanOrEqual(dining.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(dining.frame.maxX, app.frame.maxX + 1)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Category Goals limit markers at largest accessibility text size"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        dining.tap()
        XCTAssertTrue(app.navigationBars["Detail Dining"].waitForExistence(timeout: 5))
        let maximum = app.textFields["Maximum"]
        reveal(maximum, in: app)
        XCTAssertTrue(maximum.isHittable)
        app.navigationBars["Detail Dining"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Detail Dining"].waitForNonExistence(timeout: 5))
    }

    private func launchHome(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingReset", "-uiTestScenarioBudgetMenus", "-uiTestCategoryDetailHistory",
            "-tips_seenKeys", "tip.home.v1,tip.budgets.v1,tip.cards.v1,tip.budgetdetail.v1,tip.categories.v1",
            "-general_defaultBudgetingPeriod", "monthly", "-general_currencyCode", "USD",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ] + extraArguments
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 15))
        pinCategoryGoals(in: app)
        return app
    }

    private func pinCategoryGoals(in app: XCUIApplication) {
        app.navigationBars["Home"].buttons["Edit"].tap()
        XCTAssertTrue(app.navigationBars["Edit"].waitForExistence(timeout: 5))
        app.navigationBars["Edit"].buttons["Edit"].tap()
        let categoryGoals = app.buttons["Category Goals"].firstMatch
        reveal(categoryGoals, in: app)
        categoryGoals.tap()
        app.navigationBars["Edit"].buttons["Done"].tap()
        // Done finishes reordering; the leading close button dismisses the editor.
        app.navigationBars["Edit"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Edit"].waitForNonExistence(timeout: 5))
    }

    private func setMaximum(_ amount: String, in app: XCUIApplication) {
        let maximum = app.textFields["Maximum"]
        reveal(maximum, in: app)
        maximum.tap()
        let current = maximum.value as? String ?? ""
        let text = current == maximum.placeholderValue ? "" : current
        maximum.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count) + amount)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<24 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
}
