import XCTest

@MainActor
final class HomeSavingsNavigationUITests: XCTestCase {
    private func makeReceiptApp(incomeTipSeenKey: String = "tip.income.v2") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestScenarioIncomeReceipt",
            "-didCompleteOnboarding", "YES", "-onboarding_didChooseDataSource", "YES",
            "-didSeedDefaultWorkspaces", "YES", "-privacy_requireBiometrics", "NO",
            "-general_defaultBudgetingPeriod", "weekly", "-general_reviewUncategorizedExpensesOnOpen", "NO",
            "-general_excludeFuturePlannedExpensesFromCalculations", "NO",
            "-general_currencyCode", "USD",
            "-view.budgets.mode", "list",
            "-tips_seenKeys", "tip.home.v1,tip.cards.v1,\(incomeTipSeenKey),tip.budgets.v1,tip.budgetdetail.v1",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        return app
    }

    func testReceivingPaycheckPreservesThePlanAndSavingsOutlook() throws {
        continueAfterFailure = false
        let app = makeReceiptApp()
        app.launch()

        let outlook = app.buttons["Savings Outlook"].firstMatch
        XCTAssertTrue(outlook.waitForExistence(timeout: 15))
        XCTAssertTrue((outlook.value as? String ?? "").contains("Projected Savings $500"))

        app.tabBars.buttons["Income"].tap()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        let isStartOfWeek = calendar.component(.weekday, from: .now) == calendar.firstWeekday
        app.buttons[isStartOfWeek ? "Next Day" : "Previous Day"].tap()
        app.swipeUp()

        let record = app.buttons["Record Income"].firstMatch
        let useExisting = app.buttons["Use Existing"].firstMatch
        let edit = app.buttons["Edit"].firstMatch
        let plan = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@",
                                                     "Payroll", "Planned")).firstMatch
        reveal(plan, in: app)
        XCTAssertFalse(record.exists)
        XCTAssertFalse(useExisting.exists)
        plan.tap()
        XCTAssertTrue(app.navigationBars["Edit Planned Income"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.segmentedControls.firstMatch.exists)
        app.navigationBars["Edit Planned Income"].buttons["Cancel"].tap()

        plan.swipeRight()
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        XCTAssertTrue(edit.isHittable)
        XCTAssertFalse(useExisting.exists)
        record.tap()
        let receiptBar = app.navigationBars["Record Income"]
        XCTAssertTrue(receiptBar.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your planned amount stays for comparison."].exists)
        XCTAssertFalse(app.buttons["Use Existing Income"].exists)
        XCTAssertFalse(app.staticTexts["Repeat"].exists)
        XCTAssertEqual(app.textFields["Source"].value as? String, "Payroll")
        let amount = app.textFields["Amount"]
        let prefill = try XCTUnwrap(amount.value as? String)
        XCTAssertEqual(prefill.filter(\.isNumber).prefix(4), "1500")
        receiptBar.buttons["Cancel"].tap()
        XCTAssertTrue(receiptBar.waitForNonExistence(timeout: 5))
        plan.swipeRight()
        XCTAssertTrue(record.waitForExistence(timeout: 5))

        record.tap()
        amount.tap()
        let existingAmount = try XCTUnwrap(amount.value as? String)
        amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existingAmount.count) + "1430")
        receiptBar.buttons["Save"].doubleTap()
        XCTAssertTrue(app.staticTexts["Received"].waitForExistence(timeout: 5))
        let plannedEditBar = app.navigationBars["Edit Planned Income"]
        openEditorBySwipingRight(on: plan, editor: plannedEditBar, in: app)
        plannedEditBar.buttons["Cancel"].tap()
        assertAmounts("$1,500.00", "$1,430.00", in: app)

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
        let actualEditBar = app.navigationBars["Edit Income"]
        openEditorBySwipingRight(on: actual, editor: actualEditBar, in: app)
        actualEditBar.buttons["Cancel"].tap()

        let plannedResults = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@",
                                                               "Payroll", "Planned"))
        let olderPlan = plannedResults.element(boundBy: 1)
        reveal(olderPlan, in: app)
        XCTAssertFalse(record.exists)
        olderPlan.swipeRight()
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        app.terminate()
    }

    func testWhatIfIncomeCanBeEditedAndResetFromBothGestures() {
        continueAfterFailure = false
        let app = makeReceiptApp()
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

        row.swipeLeft()
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        reset.tap()
        XCTAssertTrue(reset.waitForNonExistence(timeout: 5))
    }

    func testSavingsOutlookExplanationsStackAtAccessibilityTextSize() throws {
        let app = makeReceiptApp()
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

    func testUsingAnOlderDepositMarksThePlanReceived() {
        continueAfterFailure = false
        let app = makeReceiptApp()
        app.launchArguments.append("-uiTestIncomeReceiptHasDeposit")
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 15))
        let incomeTab = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label == %@", "calendar", "Income")).firstMatch
        XCTAssertTrue(incomeTab.waitForExistence(timeout: 5))
        incomeTab.tap()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        let isStartOfWeek = calendar.component(.weekday, from: .now) == calendar.firstWeekday
        app.buttons[isStartOfWeek ? "Next Day" : "Previous Day"].tap()
        app.swipeUp()

        let record = app.buttons["Record Income"].firstMatch
        let useExisting = app.buttons["Use Existing"].firstMatch
        let plan = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@",
                                                     "Payroll", "Planned")).firstMatch
        reveal(plan, in: app)
        XCTAssertFalse(record.exists)
        XCTAssertFalse(useExisting.exists)
        plan.tap()
        let plannedEditBar = app.navigationBars["Edit Planned Income"]
        XCTAssertTrue(plannedEditBar.waitForExistence(timeout: 5))
        assertFixedIncomeType("Planned", in: app)
        plannedEditBar.buttons["Cancel"].tap()

        plan.press(forDuration: 1)
        let menuEdit = app.buttons["Edit"]
        XCTAssertTrue(menuEdit.waitForExistence(timeout: 5))
        XCTAssertTrue(record.isHittable)
        XCTAssertTrue(useExisting.isHittable)
        XCTAssertTrue(app.buttons["Delete"].exists)
        XCTAssertFalse(plannedEditBar.exists)
        menuEdit.tap()
        XCTAssertTrue(plannedEditBar.waitForExistence(timeout: 5))
        plannedEditBar.buttons["Cancel"].tap()

        plan.swipeRight()
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        XCTAssertTrue(useExisting.isHittable)
        XCTAssertTrue(menuEdit.isHittable)
        XCTAssertLessThan(record.frame.midX, useExisting.frame.midX)
        XCTAssertLessThan(useExisting.frame.midX, menuEdit.frame.midX)
        let swipeActions = XCTAttachment(screenshot: app.screenshot())
        swipeActions.name = "Income leading swipe actions"
        swipeActions.lifetime = .keepAlways
        add(swipeActions)

        record.tap()
        let receiptBar = app.navigationBars["Record Income"]
        XCTAssertTrue(receiptBar.waitForExistence(timeout: 5))
        assertFixedIncomeType("Actual", in: app)
        app.buttons["Use Existing Income"].firstMatch.tap()
        let pickerBar = app.navigationBars["Use Existing Income"]
        XCTAssertTrue(pickerBar.waitForExistence(timeout: 5))
        pickerBar.buttons["Cancel"].tap()
        receiptBar.buttons["Cancel"].tap()

        XCTAssertTrue(receiptBar.waitForNonExistence(timeout: 5))
        plan.swipeRight()
        XCTAssertTrue(useExisting.waitForExistence(timeout: 5))
        useExisting.tap()
        XCTAssertTrue(pickerBar.waitForExistence(timeout: 5))
        let deposit = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Bank deposit")).firstMatch
        XCTAssertTrue(deposit.waitForExistence(timeout: 5), app.debugDescription)
        deposit.tap()
        let confirmation = app.alerts["Use this Actual income?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["Use Income"].tap()

        XCTAssertTrue(app.staticTexts["Received"].waitForExistence(timeout: 5))
        openEditorBySwipingRight(on: plan, editor: plannedEditBar, in: app)
        app.terminate()
    }

    func testUpdatedIncomeTipShowsOnceAfterDismissingPreviousVersion() {
        continueAfterFailure = false
        let app = makeReceiptApp(incomeTipSeenKey: "tip.income.v1")
        app.launch()

        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 15))
        tabs.buttons["Income"].tap()

        let tip = app.staticTexts["Income Row Actions"]
        XCTAssertTrue(tip.waitForExistence(timeout: 5))
        app.buttons["Continue"].tap()
        XCTAssertTrue(tip.waitForNonExistence(timeout: 5))

        tabs.buttons["Home"].tap()
        tabs.buttons["Income"].tap()
        XCTAssertFalse(tip.waitForExistence(timeout: 2))
    }

    private func openEditorBySwipingRight(on row: XCUIElement, editor: XCUIElement, in app: XCUIApplication) {
        row.swipeRight()
        XCTAssertFalse(app.buttons["Record Income"].exists)
        XCTAssertFalse(app.buttons["Use Existing"].exists)
        let edit = app.buttons["Edit"].firstMatch
        if edit.exists {
            edit.tap()
        }
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
    }

    private func assertFixedIncomeType(_ expectedType: String, in app: XCUIApplication) {
        let incomeType = app.descendants(matching: .any).matching(identifier: "fixedIncomeType").firstMatch
        XCTAssertTrue(incomeType.label.contains(expectedType))
        XCTAssertFalse(app.buttons["fixedIncomeType"].exists)
        XCTAssertFalse(app.segmentedControls.firstMatch.exists)
    }

    func testSavingsAccountBackReturnsToOutlookOnHome() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingReset", "-uiTestScenarioBudgetMenus",
            "-tips_seenKeys", "tip.home.v1,tip.cards.v1,tip.income.v2",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 15))
        let outlook = app.buttons["Savings Outlook"].firstMatch
        reveal(outlook, in: app)
        outlook.tap()

        let openSavings = app.buttons["Open Offshore Savings"].firstMatch
        reveal(openSavings, in: app)
        openSavings.tap()
        XCTAssertTrue(app.navigationBars["Offshore Savings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add Savings Entry"].exists)
        app.navigationBars["Offshore Savings"].buttons.element(boundBy: 0).tap()

        XCTAssertTrue(openSavings.waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Home"].isSelected)
        XCTAssertFalse(app.navigationBars["Offshore Savings"].exists)
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
