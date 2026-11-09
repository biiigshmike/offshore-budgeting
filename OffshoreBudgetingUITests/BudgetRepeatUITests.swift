import XCTest

@MainActor
final class BudgetRepeatUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingReset", "-uiTestScenarioBudgetMenus",
            "-tips_seenKeys", "tip.home.v1,tip.budgets.v1,tip.cards.v1,tip.income.v1,tip.budgetdetail.v1",
            "-general_defaultBudgetingPeriod", "monthly",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Budgets"].tap()
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists)
    }

    private func chooseRepeat(_ title: String, in app: XCUIApplication) {
        let repeatPicker = app.buttons["budget.repeat"]
        reveal(repeatPicker, in: app)
        repeatPicker.tap()
        let option = app.buttons[title].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 3))
        option.tap()
    }

    private func openExistingBudgetEditor(in app: XCUIApplication) {
        app.staticTexts["Existing Menu Budget"].firstMatch.tap()
        app.buttons["Budget Actions"].tap()
        app.buttons["Edit Budget"].tap()
        XCTAssertTrue(app.navigationBars["Edit Budget"].waitForExistence(timeout: 5))
    }

    func testAddDefaultsToNonePreviewsCountAndRestoresManualEndDate() throws {
        let app = launchApp()
        app.buttons["Add Budget"].tap()
        XCTAssertTrue(app.navigationBars["Add Budget"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Add Budget"].buttons["Save"].exists)
        XCTAssertFalse(app.steppers["budget.repeatCount"].exists)
        let endDateButton = app.buttons["budget.endDate"]
        XCTAssertTrue(endDateButton.exists)
        let manualEndDateLabel = endDateButton.label

        // Weekly periods avoid the fixture's exact current-month date range.
        chooseRepeat("Weekly", in: app)
        let interval = app.steppers["budget.repeatInterval"]
        reveal(interval, in: app)
        interval.buttons["budget.repeatInterval-Increment"].tap()
        let count = app.steppers["budget.repeatCount"]
        reveal(count, in: app)
        count.buttons["budget.repeatCount-Increment"].tap()
        XCTAssertTrue(endDateButton.exists, "Repeating end dates remain editable.")
        app.navigationBars["Add Budget"].buttons["Preview"].tap()
        XCTAssertTrue(app.navigationBars["Preview"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["3 budgets"].exists)
        XCTAssertTrue(app.staticTexts["0 planned expenses"].exists)
        XCTAssertTrue(app.staticTexts["Each budget is independent. Editing or deleting one will not change the others."].exists)
        app.navigationBars["Preview"].buttons["Back"].tap()

        chooseRepeat("None", in: app)
        app.swipeDown()
        XCTAssertTrue(endDateButton.waitForExistence(timeout: 3))
        XCTAssertEqual(endDateButton.label, manualEndDateLabel)
        XCTAssertTrue(app.navigationBars["Add Budget"].buttons["Save"].exists)
        app.navigationBars["Add Budget"].buttons["Cancel"].tap()
    }

    func testEditedEndDateSurvivesCycleChangesAndPreview() {
        let app = launchApp()
        app.buttons["Add Budget"].tap()
        XCTAssertTrue(app.navigationBars["Add Budget"].waitForExistence(timeout: 5))
        chooseRepeat("Weekly", in: app)
        app.swipeDown()
        let endDate = app.buttons["budget.endDate"]
        XCTAssertTrue(endDate.isHittable)
        let suggestedLabel = endDate.label
        // LabeledContent exposes the whole row as the accessibility button;
        // the date pill itself occupies the trailing side of that row.
        endDate.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["End Date"].waitForExistence(timeout: 5))
        let calendar = Calendar.current
        let month = calendar.dateInterval(of: .month, for: .now)!.start
        let chosen = calendar.date(byAdding: .day, value: 19, to: month)!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE, MMMM d"
        let day = app.buttons[formatter.string(from: chosen)]
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        day.tap()
        app.navigationBars["End Date"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Add Budget"].waitForExistence(timeout: 5))
        let chosenLabel = endDate.label
        XCTAssertNotEqual(chosenLabel, suggestedLabel)
        chooseRepeat("Quarterly", in: app)
        let interval = app.steppers["budget.repeatInterval"]
        reveal(interval, in: app)
        interval.buttons["budget.repeatInterval-Increment"].tap()
        app.swipeDown()
        XCTAssertEqual(endDate.label, chosenLabel)
        app.navigationBars["Add Budget"].buttons["Preview"].tap()
        XCTAssertTrue(app.navigationBars["Preview"].waitForExistence(timeout: 5))
        app.navigationBars["Preview"].buttons["Back"].tap()
        XCTAssertTrue(endDate.waitForExistence(timeout: 5))
        XCTAssertEqual(endDate.label, chosenLabel)
        chooseRepeat("None", in: app)
        app.swipeDown()
        XCTAssertEqual(endDate.label, chosenLabel)
        app.navigationBars["Add Budget"].buttons["Cancel"].tap()
    }

    func testExactExistingRangeBlocksRepeatingPreview() {
        let app = launchApp()
        app.buttons["Add Budget"].tap()
        XCTAssertTrue(app.navigationBars["Add Budget"].waitForExistence(timeout: 5))
        chooseRepeat("Monthly", in: app)
        app.navigationBars["Add Budget"].buttons["Preview"].tap()
        let error = app.alerts["Couldn’t Save Budget"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.staticTexts["A budget already has these exact dates. Change the starting date or number of budgets."].exists)
        error.buttons["OK"].tap()
        XCTAssertTrue(app.navigationBars["Add Budget"].exists)
        app.navigationBars["Add Budget"].buttons["Cancel"].tap()
    }

    func testFollowingPreviewSupportsAccessibilityTextSizeAndDescriptions() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingReset", "-uiTestScenarioBudgetMenus",
            "-tips_seenKeys", "tip.home.v1,tip.budgets.v1,tip.cards.v1,tip.income.v1,tip.budgetdetail.v1",
            "-general_defaultBudgetingPeriod", "monthly",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Budgets"].tap()
        openExistingBudgetEditor(in: app)
        let following = app.buttons["budget.createFollowing"]
        reveal(following, in: app)
        XCTAssertTrue(following.isEnabled)
        following.tap()
        XCTAssertTrue(app.navigationBars["Create Following Budgets"].waitForExistence(timeout: 5))
        let preview = app.navigationBars["Create Following Budgets"].buttons["Preview"]
        XCTAssertTrue(preview.isHittable)
        preview.tap()
        XCTAssertTrue(app.navigationBars["Preview"].waitForExistence(timeout: 5))
        let confirm = app.buttons["budget.confirmBatch"]
        XCTAssertTrue(confirm.isHittable, "Creation must remain reachable at the largest accessibility text size.")
        XCTAssertTrue(confirm.isEnabled)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Following budgets preview at accessibility XXXL"
        attachment.lifetime = .keepAlways
        add(attachment)
        if #available(iOS 17.0, *) {
            try app.performAccessibilityAudit(for: [.dynamicType, .sufficientElementDescription])
        }
    }

    func testFollowingBudgetsRequireSavedDraftAndCreateIndependentPeriods() {
        let app = launchApp()
        openExistingBudgetEditor(in: app)
        let following = app.buttons["budget.createFollowing"]
        reveal(following, in: app)
        XCTAssertTrue(following.isEnabled)

        // Change a selection without saving: the independent action must disable.
        app.swipeDown()
        app.buttons["budget.cards"].tap()
        app.buttons["Select All"].tap()
        app.navigationBars["Edit Budget"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        reveal(following, in: app)
        XCTAssertFalse(following.isEnabled)
        XCTAssertTrue(app.staticTexts["Save or discard your changes before creating following budgets."].exists)
        app.navigationBars["Edit Budget"].buttons["Cancel"].tap()

        app.buttons["Budget Actions"].tap()
        app.buttons["Edit Budget"].tap()
        XCTAssertTrue(app.navigationBars["Edit Budget"].waitForExistence(timeout: 5))
        reveal(following, in: app)
        XCTAssertTrue(following.isEnabled)
        following.tap()
        XCTAssertTrue(app.navigationBars["Create Following Budgets"].waitForExistence(timeout: 5))
        // The template's current month remains unchanged; only new months are created.
        app.navigationBars["Create Following Budgets"].buttons["Preview"].tap()
        XCTAssertTrue(app.navigationBars["Preview"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["2 budgets"].exists)
        XCTAssertTrue(app.staticTexts["2 planned expenses"].exists)
        XCTAssertFalse(app.staticTexts["Overlapping Existing Budgets"].exists)
        app.buttons["budget.confirmBatch"].tap()
        XCTAssertTrue(app.navigationBars["Create Following Budgets"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Edit Budget"].waitForExistence(timeout: 5))
        app.swipeDown()
        XCTAssertEqual(app.textFields["budget.name"].value as? String, "Existing Menu Budget")
        app.navigationBars["Edit Budget"].buttons["Cancel"].tap()
    }
}
