import XCTest

@MainActor
final class HomeSavingsNavigationUITests: XCTestCase {
    private func makeIncomeOverviewApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestScenarioIncomeOverview",
            "-didCompleteOnboarding", "YES", "-onboarding_didChooseDataSource", "YES",
            "-didSeedDefaultWorkspaces", "YES", "-privacy_requireBiometrics", "NO",
            "-general_defaultBudgetingPeriod", "weekly", "-general_reviewUncategorizedExpensesOnOpen", "NO",
            "-general_excludeFuturePlannedExpensesFromCalculations", "NO",
            "-general_currencyCode", "USD", "-general_confirmBeforeDeleting", "YES",
            "-view.budgets.mode", "list",
            "-releaseLogs_seenReleaseIDs", "2.5.3-28",
            "-tips_seenKeys", "tip.home.v1,tip.cards.v1,tip.income.v1,tip.budgets.v1,tip.budgetdetail.v1",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        return app
    }

    func testAddingActualIncomePreservesTheSeparateRecurringPlanAndSavingsOutlook() throws {
        continueAfterFailure = false
        let app = makeIncomeOverviewApp()
        app.launch()

        let outlook = app.buttons["Savings Outlook"].firstMatch
        XCTAssertTrue(outlook.waitForExistence(timeout: 15))
        XCTAssertTrue((outlook.value as? String ?? "").contains("Projected Savings $500"))

        app.tabBars.buttons["Income"].tap()
        addIncome(source: "Payroll", amount: "1430", isPlanned: false, in: app)
        assertAmounts("$1,500.00", "$1,430.00", in: app)
        XCTAssertFalse(app.staticTexts["Received"].exists)
        XCTAssertFalse(app.staticTexts["Linked to Planned"].exists)

        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(outlook.waitForExistence(timeout: 5))
        let updatedOutlook = outlook.value as? String ?? ""
        XCTAssertTrue(updatedOutlook.contains("Projected Savings $500"))
        XCTAssertTrue(updatedOutlook.contains("Actual Savings $385"))
        outlook.tap()
        app.buttons["How is this calculated?"].tap()
        let calculation = app.navigationBars["How is this calculated?"]
        XCTAssertTrue(calculation.waitForExistence(timeout: 5))
        reveal(app.staticTexts["$500.00"].firstMatch, in: app)
        reveal(app.staticTexts["$385.00"].firstMatch, in: app)
        calculation.buttons["Close"].tap()
        app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()

        let homeIncome = app.buttons.matching(NSPredicate(format: "label == %@ AND value BEGINSWITH %@",
                                                         "Income", "Planned Income")).firstMatch
        reveal(homeIncome, in: app)
        let incomeSummary = try XCTUnwrap(homeIncome.value as? String)
        XCTAssertTrue(incomeSummary.contains("Planned Income $1,500.00"))
        XCTAssertTrue(incomeSummary.contains("Actual Income $1,430.00"))
        homeIncome.tap()
        assertAmounts("$1,430.00", "$1,500.00", in: app)

        app.tabBars.buttons["Budgets"].tap()
        let budget = app.staticTexts["Paycheck Test Budget"].firstMatch
        reveal(budget, in: app)
        budget.tap()
        XCTAssertTrue(app.navigationBars["Paycheck Test Budget"].waitForExistence(timeout: 5))
        for label in ["Planned Income, $1,500.00", "Actual Income, $1,430.00",
                      "Projected Savings, $500.00", "Actual Savings, $385.00"] {
            let metric = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
            reveal(metric, in: app)
        }
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "$2,930")).firstMatch.exists)

        app.tabBars.buttons["Income"].tap()
        let search = app.searchFields.firstMatch
        reveal(search, in: app)
        search.tap()
        search.typeText("Payroll")
        XCTAssertTrue(app.staticTexts["Search Results"].waitForExistence(timeout: 5))
        let actual = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@",
                                                       "Payroll", "Actual")).firstMatch
        reveal(actual, in: app)
        XCTAssertTrue(actual.label.contains("$1,430.00"))
        XCTAssertFalse(app.staticTexts["Linked to Planned"].exists)
        let actualEditBar = app.navigationBars["Edit Income"]
        actual.tap()
        XCTAssertTrue(actualEditBar.waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls.buttons["Actual"].isSelected)
        XCTAssertTrue(app.staticTexts["Repeat"].exists)
        let source = app.textFields["Source"]
        source.tap()
        source.typeText(" Deposit")
        let cancel = actualEditBar.buttons["Cancel"]
        let save = actualEditBar.buttons["Save"]
        XCTAssertTrue(cancel.exists)
        XCTAssertTrue(save.exists)
        XCTAssertLessThan(cancel.frame.midX, save.frame.midX)
        save.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@",
                                                       "Payroll Deposit", "Actual")).firstMatch.waitForExistence(timeout: 5))


        let plan = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@",
                                                     "Payroll, Planned", "$1,500.00")).firstMatch
        reveal(plan, in: app)
        plan.tap()
        let editor = app.navigationBars["Edit Income"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls.buttons["Planned"].isSelected)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Weekly")).firstMatch.exists)
        editor.buttons["Save"].tap()
        let applyChanges = app.alerts["Apply changes to…"]
        XCTAssertTrue(applyChanges.waitForExistence(timeout: 5))
        applyChanges.buttons["Just This Income"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
    }

    func testAddingPlannedIncomeUsesNormalEditorAndSwipeActions() {
        continueAfterFailure = false
        let app = makeIncomeOverviewApp()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Income"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Income"].tap()
        addIncome(source: "Independent Plan", amount: "250", isPlanned: true, in: app)

        let plan = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@",
                                                     "Independent Plan", "Planned")).firstMatch
        app.swipeUp()
        reveal(plan, in: app)
        XCTAssertFalse(app.staticTexts["Received"].exists)
        openEditorBySwipingRight(on: plan, in: app)
        XCTAssertTrue(app.segmentedControls.buttons["Planned"].isSelected)
        XCTAssertTrue(app.staticTexts["Repeat"].exists)
        app.navigationBars["Edit Income"].buttons["Cancel"].tap()
        plan.swipeLeft()
        let confirmation = app.alerts["Delete?"]
        if !confirmation.exists {
            let delete = app.buttons["Delete"].firstMatch
            if delete.exists {
                delete.tap()
            }
        }
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["Cancel"].tap()
        XCTAssertTrue(plan.exists)
    }

    func testWhatIfIncomeCanBeEditedAndResetFromBothGestures() {
        continueAfterFailure = false
        let app = makeIncomeOverviewApp()
        app.launch()

        let tile = app.buttons["What If?"].firstMatch
        reveal(tile, in: app)
        tile.tap()
        XCTAssertTrue(app.navigationBars["What If?"].waitForExistence(timeout: 5))

        let row = app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@ AND value BEGINSWITH %@", "Income", "Planned"
        )).firstMatch
        app.collectionViews.firstMatch.swipeUp()
        reveal(row, in: app)
        let baseline = row.value as? String
        let plannedField = row.textFields.firstMatch
        XCTAssertTrue(plannedField.isHittable)
        plannedField.tap()
        plannedField.typeText("123")
        XCTAssertTrue((row.value as? String ?? "").contains("123"))
        app.swipeDown()
        reveal(row, in: app)

        row.coordinate(withNormalizedOffset: CGVector(dx: 0.24, dy: 0.2)).press(forDuration: 1)
        let reset = app.buttons["Reset"].firstMatch
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        reset.tap()
        XCTAssertTrue(reset.waitForNonExistence(timeout: 5))
        XCTAssertEqual(row.value as? String, baseline)

        plannedField.tap()
        plannedField.typeText("456")
        XCTAssertTrue((row.value as? String ?? "").contains("456"))
        app.swipeDown()
        reveal(row, in: app)

        let trailing = row.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.20))
        let leading = row.coordinate(withNormalizedOffset: CGVector(dx: 0.20, dy: 0.20))
        trailing.press(forDuration: 0.05, thenDragTo: leading)
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        reset.tap()
        XCTAssertTrue(reset.waitForNonExistence(timeout: 5))
        XCTAssertEqual(row.value as? String, baseline)
    }

    func testSavingsOutlookExplanationsStackAtAccessibilityTextSize() throws {
        let app = makeIncomeOverviewApp()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let outlook = app.buttons["Savings Outlook"].firstMatch
        XCTAssertTrue(outlook.waitForExistence(timeout: 15))
        reveal(outlook, in: app)
        let actualCopy = "Includes planned expenses you haven't marked yet."
        let actualCopyPredicate = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", actualCopy, actualCopy)
        XCTAssertFalse(app.descendants(matching: .any).matching(actualCopyPredicate).firstMatch.exists)
        outlook.tap()

        let projectedCopy = "Expected income minus your share of planned expenses."
        let projected = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", projectedCopy)).firstMatch
        let actual = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Actual Savings,")).firstMatch
        XCTAssertTrue(projected.waitForExistence(timeout: 5))
        XCTAssertTrue(actual.exists)
        XCTAssertEqual(actual.label.components(separatedBy: ", ").dropFirst(2), [actualCopy])
        XCTAssertEqual(projected.frame.minX, actual.frame.minX, accuracy: 1)
        XCTAssertGreaterThan(actual.frame.minY, projected.frame.maxY)
        XCTAssertLessThanOrEqual(actual.frame.maxX, app.frame.maxX)
        try app.performAccessibilityAudit(for: .textClipped) { issue in
            let label = issue.element?.label ?? ""
            return !label.contains(projectedCopy) && !label.contains(actualCopy)
        }

        let helpButton = app.buttons["How is this calculated?"]
        reveal(helpButton, in: app)
        helpButton.tap()
        XCTAssertTrue(app.navigationBars["How is this calculated?"].waitForExistence(timeout: 5))
        for text in [
            "Actual Income",
            "Planned expenses counted here",
            "Variable expenses counted here",
            "Changes you’ve entered",
            "For each planned expense, an actual amount entered above zero takes the place of the planned amount. Otherwise, the planned amount still counts."
        ] {
            let label = NSPredicate(format: "label == %@", text)
            reveal(app.staticTexts.matching(label).firstMatch, in: app)
        }
        app.terminate()
    }

    private func addIncome(source: String, amount: String, isPlanned: Bool, in app: XCUIApplication) {
        app.buttons["income.addMenu"].tap()
        app.buttons["Add Income"].firstMatch.tap()
        let editor = app.navigationBars["Add Income"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let type = app.segmentedControls.buttons[isPlanned ? "Planned" : "Actual"]
        type.tap()
        XCTAssertTrue(type.isSelected)
        let sourceField = app.textFields["Source"]
        sourceField.tap()
        sourceField.typeText(source)
        let amountField = app.textFields["Amount"]
        amountField.tap()
        amountField.typeText(amount)
        editor.buttons["Save"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
    }

    private func openEditorBySwipingRight(on row: XCUIElement, in app: XCUIApplication) {
        row.swipeRight()
        XCTAssertFalse(app.buttons["Record Income"].exists)
        XCTAssertFalse(app.buttons["Use Existing"].exists)
        let edit = app.buttons["Edit"].firstMatch
        if edit.exists {
            edit.tap()
        }
        XCTAssertTrue(app.navigationBars["Edit Income"].waitForExistence(timeout: 5))
    }

    func testSavingsAccountBackReturnsToOutlookOnHome() {
        continueAfterFailure = false
        let app = makeIncomeOverviewApp()
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 15))
        let outlook = app.buttons["Savings Outlook"].firstMatch
        reveal(outlook, in: app)
        outlook.tap()

        let openSavings = app.buttons["Open Offshore Savings"].firstMatch
        reveal(openSavings, in: app)
        openSavings.tap()
        let savingsBar = app.navigationBars["Savings"]
        XCTAssertTrue(savingsBar.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add Savings Entry"].exists)
        savingsBar.buttons.element(boundBy: 0).tap()

        XCTAssertTrue(openSavings.waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Home"].isSelected)
        XCTAssertFalse(savingsBar.exists)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    private func assertAmounts(_ first: String, _ second: String, in app: XCUIApplication) {
        for amount in [first, second] {
            let label = NSPredicate(format: "label CONTAINS %@", amount)
            let match = app.staticTexts.matching(label).firstMatch
            reveal(match, in: app)
        }
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "$2,930")).firstMatch.exists)
    }
}
