import XCTest

@MainActor
final class BudgetFormMenusUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func menuItem(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    private func dismissMenu(_ app: XCUIApplication, formTitle: String) {
        app.navigationBars[formTitle].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func exerciseMenus(_ app: XCUIApplication, formTitle: String) {
        app.buttons["budget.cards"].tap()
        app.buttons["Select All"].tap()
        XCTAssertTrue(app.buttons["Clear All"].waitForExistence(timeout: 3))
        app.buttons["Clear All"].tap()
        XCTAssertTrue(menuItem("Ocean Card", in: app).waitForExistence(timeout: 5))
        menuItem("Ocean Card", in: app).tap()
        XCTAssertTrue(menuItem("Ruby Card", in: app).waitForExistence(timeout: 3))
        menuItem("Ruby Card", in: app).tap()
        // A second action must be possible without reopening the menu.
        XCTAssertTrue(app.buttons["Clear All"].waitForExistence(timeout: 3))
        app.buttons["Clear All"].tap()
        XCTAssertTrue(app.buttons["Select All"].waitForExistence(timeout: 3))
        app.buttons["Select All"].tap()
        XCTAssertTrue(app.buttons["Clear All"].waitForExistence(timeout: 3))
        let cards = XCTAttachment(screenshot: app.screenshot())
        cards.name = "Budget cards menu with artwork"
        cards.lifetime = .keepAlways
        add(cards)
        dismissMenu(app, formTitle: formTitle)

        app.buttons["budget.presets"].tap()
        app.buttons["Select All"].tap()
        XCTAssertTrue(app.buttons["Clear All"].waitForExistence(timeout: 3))
        app.buttons["Clear All"].tap()
        let rent = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Rent")).firstMatch
        XCTAssertTrue(rent.waitForExistence(timeout: 5))
        XCTAssertFalse(rent.label.contains("$"))
        rent.tap()
        let internet = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Internet")).firstMatch
        XCTAssertTrue(internet.waitForExistence(timeout: 3))
        XCTAssertFalse(internet.label.contains("$"))
        internet.tap()
        XCTAssertTrue(app.buttons["Clear All"].waitForExistence(timeout: 3))
        app.buttons["Clear All"].tap()
        XCTAssertTrue(app.buttons["Select All"].waitForExistence(timeout: 3))
        app.buttons["Select All"].tap()
        XCTAssertTrue(app.buttons["Clear All"].waitForExistence(timeout: 3))
        let presets = XCTAttachment(screenshot: app.screenshot())
        presets.name = "Budget presets menu with schedule details"
        presets.lifetime = .keepAlways
        add(presets)
        dismissMenu(app, formTitle: formTitle)
    }

    func testAddAndEditBudgetMenusStayOpenAndCancelDiscardsEdits() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingReset", "-uiTestScenarioBudgetMenus",
            "-tips_seenKeys", "tip.home.v1,tip.budgets.v1,tip.cards.v1,tip.income.v1,tip.budgetdetail.v1",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Budgets"].tap()
        app.buttons["Add Budget"].tap()
        XCTAssertTrue(app.navigationBars["Add Budget"].waitForExistence(timeout: 5))
        exerciseMenus(app, formTitle: "Add Budget")
        app.buttons["budget.categoryGoals"].tap()
        XCTAssertTrue(app.navigationBars["Category Goals"].waitForExistence(timeout: 5))
        let autoConfigure = app.switches["categoryGoals.autoConfigure"]
        XCTAssertTrue(autoConfigure.waitForExistence(timeout: 5))
        autoConfigure.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        app.staticTexts["Bills"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Bills"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["categoryGoals.usePlannedMinimum"].exists)
        XCTAssertFalse(app.buttons["categoryGoals.clearPlannedMinimum"].exists)
        XCTAssertEqual(app.textFields["Minimum"].value as? String, "860.00")
        let goals = XCTAttachment(screenshot: app.screenshot())
        goals.name = "Preset-based minimum during budget creation"
        goals.lifetime = .keepAlways
        add(goals)
        app.navigationBars["Bills"].buttons["Category Goals"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Add Budget"].waitForExistence(timeout: 5))
        // Saving uses the existing creation flow, including selections and the goal draft.
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Budgets"].waitForExistence(timeout: 5))

        app.staticTexts["Existing Menu Budget"].firstMatch.tap()
        app.buttons["Budget Actions"].tap()
        app.buttons["Edit Budget"].tap()
        XCTAssertTrue(app.navigationBars["Edit Budget"].waitForExistence(timeout: 5))
        exerciseMenus(app, formTitle: "Edit Budget")
        app.buttons["Cancel"].tap()
        app.buttons["Budget Actions"].tap()
        app.buttons["Edit Budget"].tap()
        XCTAssertTrue(app.navigationBars["Edit Budget"].waitForExistence(timeout: 5))
        app.buttons["budget.cards"].tap()
        XCTAssertTrue(app.buttons["Select All"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Clear All"].exists)
        dismissMenu(app, formTitle: "Edit Budget")
        app.buttons["budget.presets"].tap()
        XCTAssertTrue(app.buttons["Select All"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Clear All"].exists)
        dismissMenu(app, formTitle: "Edit Budget")
        app.buttons["Cancel"].tap()
    }
}
