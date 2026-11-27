import XCTest

@MainActor
final class FirstRunBudgetingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCreatePresetFromFirstBudgetAfterOnboarding() {
        let app = makeApp(arguments: ["-uiTestFreshBudgetingOnboarding"])
        app.launch()

        tap(app.buttons["Get Started"], in: app)
        tap(app.buttons["On Device"], in: app)
        for title in ["Workspaces", "Privacy", "Categories"] {
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            tap(app.buttons["Next"], in: app)
        }

        XCTAssertTrue(app.navigationBars["Cards"].waitForExistence(timeout: 5))
        tap(app.buttons["Add Card"], in: app)
        let cardName = app.textFields["Credit Card, Checking, or Cash"]
        tap(cardName, in: app)
        cardName.typeText("Checking")
        tap(app.navigationBars["Add Card"].buttons["Save"], in: app)
        tap(app.buttons["Next"], in: app)
        XCTAssertTrue(app.navigationBars["Presets"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No Presets Yet"].exists)
        tap(app.buttons["Done"], in: app)
        tap(app.buttons["workspaceProgressSkip"], in: app)
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 10))

        openNewBudget(in: app)
        XCTAssertTrue(app.buttons["budget.cards"].label.contains("Checking"))
        let budgetName = nameBudget("First Run Budget", in: app)
        let presetsRow = app.buttons["budget.presets"]
        XCTAssertTrue(presetsRow.label.contains("Create Preset"))
        tap(presetsRow, in: app)
        tap(app.navigationBars["Add Preset"].buttons["Cancel"], in: app)
        XCTAssertTrue(app.navigationBars["Add Budget"].waitForExistence(timeout: 5))

        tap(app.buttons["budget.categoryGoals"], in: app)
        let createCategory = app.buttons["Create Category"]
        let categoryGoalsGuide = app.buttons["Category Goals guide"]
        XCTAssertTrue(createCategory.waitForExistence(timeout: 5))
        XCTAssertTrue(categoryGoalsGuide.exists)
        XCTAssertLessThanOrEqual(createCategory.frame.maxY, categoryGoalsGuide.frame.minY)
        XCTAssertFalse(app.switches["categoryGoals.autoConfigure"].exists)
        tap(createCategory, in: app)
        let categoryName = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "Name")).firstMatch
        tap(categoryName, in: app)
        categoryName.typeText("First Run Bills")
        tap(app.navigationBars["Add Category"].buttons["Save"], in: app)
        XCTAssertTrue(app.staticTexts["First Run Bills"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["categoryGoals.autoConfigure"].exists)
        tap(app.navigationBars["Category Goals"].buttons["Done"], in: app)
        app.swipeDown()
        XCTAssertEqual(app.textFields["budget.name"].value as? String, budgetName)
        saveAndOpenBudget(budgetName, in: app)

        tap(app.buttons["Budget Actions"], in: app)
        tap(app.buttons["Manage Presets"], in: app)
        XCTAssertTrue(app.navigationBars["Linked Presets"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No Presets"].exists)
        tap(app.buttons["Create Preset"], in: app)
        XCTAssertTrue(app.navigationBars["Add Preset"].waitForExistence(timeout: 5))
        tap(app.buttons["Choose a Card"], in: app)
        tap(app.buttons["Checking"], in: app)
        let presetName = "First Run Rent"
        let title = app.textFields["Expense Name"]
        tap(title, in: app)
        title.typeText(presetName)
        let amount = app.textFields["Planned Amount"]
        tap(amount, in: app)
        amount.typeText("90")
        tap(app.navigationBars["Add Preset"].buttons["Save"], in: app)

        XCTAssertTrue(app.navigationBars["Preset Saved"].waitForExistence(timeout: 5))
        let offers = app.descendants(matching: .any).matching(identifier: "presetOfferBudget")
        XCTAssertEqual(offers.count, 1)
        XCTAssertTrue(offers.firstMatch.label.hasPrefix(budgetName))
        let apply = app.buttons["applySavedPreset"]
        XCTAssertTrue(apply.isEnabled)
        tap(apply, in: app)

        XCTAssertTrue(app.navigationBars["Linked Presets"].waitForExistence(timeout: 5))
        let preset = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", presetName)).firstMatch
        XCTAssertTrue(preset.waitForExistence(timeout: 5))
        XCTAssertEqual(preset.value as? String, "1")
        tap(app.navigationBars["Linked Presets"].buttons.firstMatch, in: app)
        XCTAssertTrue(app.navigationBars[budgetName].waitForExistence(timeout: 5))
        let plannedExpense = app.staticTexts.matching(identifier: presetName)
        reveal(plannedExpense.firstMatch, in: app)
        XCTAssertEqual(plannedExpense.count, 1)
    }

    func testMissingCardActionsKeepTheirParentScreens() {
        let app = makeApp(arguments: ["-uiTestProgressNoCard"])
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 10))

        openSettings(in: app)
        let presets = app.descendants(matching: .any).matching(identifier: "settings_managePresets").firstMatch
        tap(presets, in: app)
        tap(app.buttons["Add Preset"], in: app)
        let presetTitle = app.textFields["Expense Name"]
        tap(presetTitle, in: app)
        presetTitle.typeText("Draft Preset")
        let createCardRow = app.buttons["preset.createCard"]
        XCTAssertTrue(createCardRow.label.contains("Create Card"))
        tap(createCardRow, in: app)
        tap(app.navigationBars["Add Card"].buttons["Cancel"], in: app)
        XCTAssertTrue(app.navigationBars["Add Preset"].waitForExistence(timeout: 5))
        XCTAssertEqual(presetTitle.value as? String, "Draft Preset")
        tap(app.navigationBars["Add Preset"].buttons["Cancel"], in: app)

        tap(app.tabBars.buttons["Budgets"], in: app)
        tap(app.staticTexts["First Budget"].firstMatch, in: app)
        tap(app.buttons["Budget Actions"], in: app)
        tap(app.buttons["Manage Cards"], in: app)
        XCTAssertTrue(app.navigationBars["Linked Cards"].waitForExistence(timeout: 5))
        tap(app.buttons["Create Card"], in: app)
        let cardName = app.textFields["Credit Card, Checking, or Cash"]
        tap(cardName, in: app)
        cardName.typeText("New Checking")
        tap(app.navigationBars["Add Card"].buttons["Save"], in: app)

        XCTAssertTrue(app.navigationBars["Linked Cards"].waitForExistence(timeout: 5))
        let newCard = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "New Checking")).firstMatch
        XCTAssertTrue(newCard.waitForExistence(timeout: 5))
        XCTAssertEqual(newCard.value as? String, "0")
    }

    func testWeeklyIntervalPersistsAndNewBudgetDatesCanBeEdited() throws {
        let app = makeApp(arguments: ["-uiTestProgressCardOnly", "-uiTestLegacyWeeklyBudgetingPeriod"])
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 10))
        openNewBudget(in: app)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let week = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: today))
        let weeklyEnd = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: week.end))
        assertBudgetDates(start: week.start, end: weeklyEnd, in: app)
        tap(app.navigationBars["Add Budget"].buttons["Cancel"], in: app)

        openGeneralSettings(in: app)
        let stepper = app.steppers["defaultBudgetingPeriod.weeklyInterval"]
        reveal(stepper, in: app)
        XCTAssertEqual(stepper.label, "Every 1 week")
        tap(stepper.buttons["defaultBudgetingPeriod.weeklyInterval-Increment"], in: app)
        XCTAssertEqual(stepper.label, "Every 2 weeks")

        app.terminate()
        app.launchArguments.removeAll { $0 == "-uiTestingReset" || $0 == "-uiTestLegacyWeeklyBudgetingPeriod" }
        app.launchArguments.append("-uiTestPreserveScenarioData")
        app.launch()
        openGeneralSettings(in: app)
        reveal(stepper, in: app)
        XCTAssertEqual(stepper.label, "Every 2 weeks")

        openNewBudget(in: app)
        let january3 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2000, month: 1, day: 3)))
        let anchor = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: january3)).start
        let daysFromAnchor = try XCTUnwrap(calendar.dateComponents([.day], from: anchor, to: today).day)
        let cycleStart = try XCTUnwrap(calendar.date(byAdding: .day, value: daysFromAnchor / 14 * 14, to: anchor))
        let cycleEnd = try XCTUnwrap(calendar.date(byAdding: .day, value: 13, to: cycleStart))
        assertBudgetDates(start: cycleStart, end: cycleEnd, in: app)

        let endDate = app.buttons["budget.endDate"]
        endDate.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        let picker = app.navigationBars["End Date"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let offset = calendar.component(.day, from: cycleEnd) == 1 ? 1 : -1
        let customEnd = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: cycleEnd))
        let dayLabel = DateFormatter()
        dayLabel.locale = Locale(identifier: "en_US")
        dayLabel.dateFormat = "EEEE, MMMM d"
        tap(app.buttons[dayLabel.string(from: customEnd)], in: app)
        tap(picker.buttons["Done"], in: app)
        assertBudgetDates(start: cycleStart, end: customEnd, in: app)

        let budgetName = try XCTUnwrap(app.textFields["budget.name"].value as? String)
        XCTAssertFalse(budgetName.isEmpty)
        saveAndOpenBudget(budgetName, in: app)
        tap(app.buttons["Budget Actions"], in: app)
        tap(app.buttons["Edit Budget"], in: app)
        XCTAssertTrue(app.navigationBars["Edit Budget"].waitForExistence(timeout: 5))
        assertBudgetDates(start: cycleStart, end: customEnd, in: app)
    }

    private func makeApp(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingReset", "-uiTestScenarioWorkspaceProgress",
            "-tips_seenKeys", "tip.home.v1,tip.budgets.v1,tip.budgetdetail.v1",
            "-tips_resetToken", "0", "-tips_seen_lastResetToken", "0",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ] + arguments
        return app
    }

    private func openSettings(in app: XCUIApplication) {
        let settingsTab = app.tabBars.buttons["Settings"]
        if settingsTab.waitForExistence(timeout: 3) {
            settingsTab.tap()
        } else {
            tap(app.buttons["Settings"].firstMatch, in: app)
        }
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    private func openGeneralSettings(in app: XCUIApplication) {
        openSettings(in: app)
        let general = app.descendants(matching: .any).matching(identifier: "settings_general").firstMatch
        tap(general, in: app)
        XCTAssertTrue(app.navigationBars["General"].waitForExistence(timeout: 5))
    }

    private func openNewBudget(in app: XCUIApplication) {
        tap(app.tabBars.buttons["Budgets"], in: app)
        tap(app.buttons["Add Budget"], in: app)
        XCTAssertTrue(app.navigationBars["Add Budget"].waitForExistence(timeout: 5))
    }

    private func nameBudget(_ name: String, in app: XCUIApplication) -> String {
        let field = app.textFields["budget.name"]
        tap(field, in: app)
        field.typeKey("a", modifierFlags: .command)
        field.typeText(name)
        XCTAssertEqual(field.value as? String, name)
        return name
    }

    private func saveAndOpenBudget(_ name: String, in app: XCUIApplication) {
        tap(app.navigationBars["Add Budget"].buttons["Save"], in: app)
        XCTAssertTrue(app.navigationBars["Budgets"].waitForExistence(timeout: 5))
        let budget = app.staticTexts[name].firstMatch
        if !budget.exists {
            let pastBudgets = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Past Budgets")).firstMatch
            if pastBudgets.exists { tap(pastBudgets, in: app) }
        }
        tap(budget, in: app)
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
    }

    private func assertBudgetDates(start: Date, end: Date, in app: XCUIApplication) {
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted).locale(Locale(identifier: "en_US"))
        XCTAssertTrue(app.buttons["budget.startDate"].label.contains(start.formatted(style)))
        XCTAssertTrue(app.buttons["budget.endDate"].label.contains(end.formatted(style)))
    }

    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        reveal(element, in: app)
        element.tap()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        if !element.exists { _ = element.waitForExistence(timeout: 1) }
        for _ in 0..<4 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(element.isHittable, element.debugDescription)
    }
}
