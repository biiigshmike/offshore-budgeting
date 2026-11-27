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

    func testFirstBudgetCardDefaultCanBeClearedAndDoesNotChangeCopiedOrLaterBudgets() {
        let app = launchFirstBudgetForm()
        let cards = app.buttons["budget.cards"]
        let addBudget = app.navigationBars["Add Budget"]
        XCTAssertTrue(cards.label.contains("First Card"))
        cards.tap()
        app.buttons["Clear All"].tap()
        XCTAssertTrue(app.buttons["Select All"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Done"].exists)
        dismissMenu(app, formTitle: "Add Budget")
        XCTAssertTrue(app.buttons["Select All"].waitForNonExistence(timeout: 3))

        let endDate = app.buttons["budget.endDate"]
        let initialDate = endDate.label
        endDate.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        let datePicker = app.navigationBars["End Date"]
        XCTAssertTrue(datePicker.waitForExistence(timeout: 5))
        let calendar = Calendar.current
        let month = calendar.dateInterval(of: .month, for: .now)!.start
        let changedDay = calendar.date(byAdding: .day, value: 19, to: month)!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE, MMMM d"
        app.buttons[formatter.string(from: changedDay)].tap()
        datePicker.buttons["Done"].tap()
        XCTAssertNotEqual(endDate.label, initialDate)
        XCTAssertTrue(cards.label.contains("None selected"))

        app.buttons["budget.categoryGoals"].tap()
        let goals = app.navigationBars["Category Goals"]
        XCTAssertTrue(goals.waitForExistence(timeout: 5))
        goals.buttons["Done"].tap()
        XCTAssertTrue(cards.label.contains("None selected"))

        let name = app.textFields["budget.name"].value as? String ?? ""
        addBudget.buttons["Save"].tap()
        let budgets = app.navigationBars["Budgets"]
        XCTAssertTrue(budgets.waitForExistence(timeout: 5))
        app.buttons["Add Budget"].tap()
        XCTAssertTrue(addBudget.waitForExistence(timeout: 5))
        XCTAssertTrue(cards.label.contains("None selected"))
        addBudget.buttons["Cancel"].tap()

        let savedBudget = app.staticTexts[name].firstMatch
        if !savedBudget.exists {
            let pastBudgets = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Past Budgets")).firstMatch
            XCTAssertTrue(pastBudgets.waitForExistence(timeout: 5))
            pastBudgets.tap()
        }
        XCTAssertTrue(savedBudget.waitForExistence(timeout: 5))
        savedBudget.tap()
        app.buttons["Budget Actions"].tap()
        app.buttons["Edit Budget"].tap()
        let editBudget = app.navigationBars["Edit Budget"]
        XCTAssertTrue(editBudget.waitForExistence(timeout: 5))
        XCTAssertTrue(cards.label.contains("None selected"))
        let copy = app.buttons["budget.createFollowing"]
        for _ in 0..<4 where !copy.isHittable { app.swipeUp() }
        copy.tap()
        XCTAssertTrue(addBudget.waitForExistence(timeout: 5))
        let copiedCards = app.buttons.matching(identifier: "budget.cards").allElementsBoundByIndex.last(where: \.isHittable)
        XCTAssertTrue(copiedCards?.label.contains("None selected") == true)
    }

    func testEmptyCardsRowCreatesACardAndReturnsToTheBudgetDraft() {
        let app = launchFirstBudgetForm(extraArguments: ["-uiTestProgressNoCard"])
        let cards = app.buttons["budget.cards"]
        let draftName = app.textFields["budget.name"].value as? String
        XCTAssertTrue(cards.label.contains("Create Card"))
        cards.tap()

        let cardForm = app.navigationBars["Add Card"]
        XCTAssertTrue(cardForm.waitForExistence(timeout: 5))
        let name = app.textFields["Credit Card, Checking, or Cash"]
        name.tap()
        name.typeText("New Checking")
        cardForm.buttons["Save"].tap()

        XCTAssertTrue(cards.waitForExistence(timeout: 5))
        XCTAssertFalse(cards.label.contains("Create Card"))
        XCTAssertEqual(app.textFields["budget.name"].value as? String, draftName)
        cards.tap()
        XCTAssertTrue(menuItem("New Checking", in: app).waitForExistence(timeout: 5))
    }

    func testFirstBudgetWithMultipleCardsHasNoDefault() {
        let app = launchFirstBudgetForm(extraArguments: ["-uiTestProgressTwoCards"])
        let cards = app.buttons["budget.cards"]
        XCTAssertTrue(cards.label.contains("None selected"))
        XCTAssertTrue(cards.isEnabled)
    }

    private func launchFirstBudgetForm(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingReset", "-uiTestScenarioWorkspaceProgress", "-uiTestProgressCardOnly",
            "-tips_seenKeys", "tip.home.v1,tip.budgets.v1,tip.budgetdetail.v1",
            "-general_defaultBudgetingPeriod", "monthly",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ] + extraArguments
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Budgets"].tap()
        app.buttons["Add Budget"].tap()
        XCTAssertTrue(app.navigationBars["Add Budget"].waitForExistence(timeout: 5))
        return app
    }
}
