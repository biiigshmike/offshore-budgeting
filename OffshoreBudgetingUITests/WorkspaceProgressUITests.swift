import XCTest

@MainActor
final class WorkspaceProgressUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testPresetOfferWithNoBudgetReturnsToSettingsPresets() {
        let app = makeApp(extraArguments: ["-uiTestProgressCardOnly"])
        app.launch()
        openPresets(app)
        app.buttons["Add Preset"].tap()
        savePreset(named: "Rent", in: app)

        XCTAssertTrue(app.staticTexts["You can select this preset when you create a budget."].exists)
        XCTAssertFalse(app.buttons["applySavedPreset"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Presets"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Rent"].exists)
    }

    func testWorkspaceProgressPresetOfferAppliesToOnlyBudget() {
        let app = makeApp(extraArguments: ["-uiTestProgressPresetOffer", "-uiTestProgressComplete"])
        app.launch()
        openSettings(app)
        openProgress(app)
        assertProgress(80, completed: 4, in: app)
        addPresetFromProgress(in: app)
        savePreset(named: "Rent", in: app)

        let apply = app.buttons["applySavedPreset"]
        XCTAssertEqual(apply.label, "Add to Budget")
        apply.tap()
        XCTAssertTrue(app.navigationBars["Workspace Progress"].waitForExistence(timeout: 5))
        assertProgress(100, completed: 5, in: app)
        openBudget("First Budget", in: app)
        reveal(app.staticTexts["Rent"].firstMatch, in: app)
        assertPreset("Rent", isLinked: true, in: app)
        app.navigationBars["Linked Presets"].buttons.firstMatch.tap()

        app.buttons["Add Expense"].tap()
        XCTAssertTrue(app.navigationBars["Add Expense"].waitForExistence(timeout: 5))
        let cardPicker = app.buttons["Choose a Card"]
        if cardPicker.exists {
            cardPicker.tap()
            app.buttons["First Card"].tap()
        }
        let description = app.textFields["Description"]
        description.tap()
        description.typeText("Coffee")
        let amount = app.textFields["Amount"]
        amount.tap()
        amount.typeText("5")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Add Expense"].waitForNonExistence(timeout: 5))
        reveal(app.staticTexts["Coffee"].firstMatch, in: app)
    }

    func testWorkspaceProgressNotNowKeepsTemplateAndMilestoneAfterRelaunch() {
        let app = makeApp(extraArguments: ["-uiTestProgressPresetOffer", "-uiTestProgressComplete"])
        app.launch()
        openSettings(app)
        openProgress(app)
        addPresetFromProgress(in: app)
        savePreset(named: "Rent", in: app)
        app.buttons["Not Now"].tap()
        XCTAssertTrue(app.navigationBars["Workspace Progress"].waitForExistence(timeout: 5))
        assertProgress(100, completed: 5, in: app)

        app.terminate()
        app.launchArguments.removeAll { $0 == "-uiTestingReset" }
        app.launchArguments.append("-uiTestPreserveScenarioData")
        app.launch()
        openSettings(app)
        openProgress(app)
        assertProgress(100, completed: 5, in: app)
        openBudget("First Budget", in: app)
        assertPreset("Rent", isLinked: false, in: app)
    }

    func testSettingsPresetOfferAppliesToEachSelectedBudget() {
        let app = makeApp(extraArguments: ["-uiTestProgressPresetOffer", "-uiTestProgressOverlappingPresetOffer"])
        app.launch()
        openPresets(app)
        app.buttons["Add Preset"].tap()
        savePreset(named: "Internet", in: app)
        app.buttons["Not Now"].tap()
        XCTAssertTrue(app.navigationBars["Presets"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Internet"].exists)

        app.buttons["Add Preset"].tap()
        savePreset(named: "Rent", in: app)
        let apply = app.buttons["applySavedPreset"]
        XCTAssertFalse(apply.isEnabled)
        let budgetRows = app.descendants(matching: .any).matching(identifier: "presetOfferBudget")
        let first = budgetRows.matching(NSPredicate(format: "label BEGINSWITH %@", "First Budget")).firstMatch
        let ended = budgetRows.matching(NSPredicate(format: "label BEGINSWITH %@", "Ended Budget")).firstMatch
        XCTAssertTrue(first.exists && ended.exists)
        app.buttons["Select All"].tap()
        XCTAssertEqual(apply.label, "Add to Budgets")
        app.buttons["Deselect All"].tap()
        XCTAssertFalse(apply.isEnabled)
        first.tap()
        XCTAssertEqual(apply.label, "Add to Budget")
        ended.tap()
        XCTAssertTrue(apply.isEnabled)
        XCTAssertEqual(apply.label, "Add to Budgets")
        apply.tap()
        XCTAssertTrue(app.navigationBars["Presets"].waitForExistence(timeout: 5))

        openBudget("Unselected Budget", in: app)
        assertPreset("Rent", isLinked: false, in: app)
        app.navigationBars["Linked Presets"].buttons.firstMatch.tap()
        goBack(from: "Unselected Budget", to: "Budgets", in: app)
        openBudget("First Budget", in: app)
        assertPreset("Internet", isLinked: false, in: app)
        assertPreset("Rent", isLinked: true, in: app, openSheet: false)
        app.navigationBars["Linked Presets"].buttons.firstMatch.tap()
        goBack(from: "First Budget", to: "Budgets", in: app)
        openBudget("Ended Budget", in: app)
        reveal(app.staticTexts["Rent"].firstMatch, in: app)
        assertPreset("Rent", isLinked: true, in: app)
    }

    func testIncomeCancelPreservesProgressAndSaveCompletesSetup() throws {
        let app = makeApp()
        app.launch()
        openSettings(app)
        openProgress(app)
        assertProgress(80, completed: 4, in: app)
        attachScreenshot("Workspace progress summary", app: app)
        XCTAssertFalse(element("workspaceProgressHideGuidance", in: app).exists)
        goBack(from: "Workspace Progress", to: "Settings", in: app)
        openMaintenance(app)
        XCTAssertFalse(app.switches["hideWorkspaceProgress"].exists)
        returnToSettingsFromMaintenance(app)
        openProgress(app)

        for step in ["card", "category", "preset", "income", "budget"] {
            let row = element("workspaceProgressStep_\(step)", in: app)
            reveal(row, in: app)
            XCTAssertTrue(row.label.contains(step == "income" ? "Not completed" : "Completed"))
        }
        attachScreenshot("Workspace setup checklist at 80 percent", app: app)

        let addIncome = app.buttons["workspaceProgressStep_income"]
        reveal(addIncome, in: app)
        addIncome.tap()
        XCTAssertTrue(app.navigationBars["Add Income"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Workspace Progress"].waitForExistence(timeout: 5))
        assertProgress(80, completed: 4, in: app)

        reveal(addIncome, in: app)
        addIncome.tap()
        XCTAssertTrue(app.navigationBars["Add Income"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["Planned"].tap()
        let source = app.textFields["Source"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap()
        source.typeText("First Paycheck")
        let amount = app.textFields["Amount"]
        amount.tap()
        amount.typeText("2500")
        app.buttons["Save"].tap()

        XCTAssertTrue(app.navigationBars["Workspace Progress"].waitForExistence(timeout: 5))
        assertProgress(100, completed: 5, in: app)
        let complete = element("workspaceProgressComplete", in: app)
        reveal(complete, in: app)
        XCTAssertFalse(app.buttons["workspaceProgressStep_income"].exists)
        let hideGuidance = element("workspaceProgressHideGuidance", in: app)
        reveal(hideGuidance, in: app)
        attachScreenshot("Workspace setup complete", app: app)
        goBack(from: "Workspace Progress", to: "Settings", in: app)
        XCTAssertTrue(element("settingsWorkspaceProgress", in: app).waitForExistence(timeout: 5))
    }

    func testFreshCardOnlyRowsOpenFormsAcrossTheirWidthAndCancelPreservesProgress() {
        let app = makeApp(extraArguments: ["-uiTestProgressCardOnly"])
        app.launch()
        openSettings(app)
        openProgress(app)
        assertProgress(20, completed: 1, in: app)
        XCTAssertFalse(app.buttons["workspaceProgressStep_card"].exists)
        XCTAssertFalse(app.staticTexts["Next Steps"].exists)

        for (index, step) in ["category", "preset", "income", "budget"].enumerated() {
            let row = app.buttons["workspaceProgressStep_\(step)"]
            reveal(row, in: app)
            XCTAssertTrue(row.isEnabled)
            XCTAssertGreaterThanOrEqual(row.frame.height, 44)
            // isHittable may be true for a sliver above the iPhone tab bar.
            // Bring the whole row into view before choosing an exact tap coordinate.
            let bottom = app.tabBars.firstMatch.exists
                ? app.tabBars.firstMatch.frame.minY : app.frame.maxY
            for _ in 0..<8 {
                if row.frame.maxY < bottom - 8 { break }
                app.swipeUp()
            }
            // Alternate between the title area and trailing whitespace.
            row.coordinate(withNormalizedOffset: CGVector(dx: index.isMultiple(of: 2) ? 0.2 : 0.85, dy: 0.5)).tap()
            let title = ["category": "Add Category", "preset": "Add Preset",
                         "income": "Add Income", "budget": "Add Budget"][step]!
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            if step == "income" {
                let source = app.textFields["Source"]
                source.tap()
                source.typeText("Canceled draft")
            }
            app.buttons["Cancel"].tap()
            XCTAssertTrue(app.navigationBars["Workspace Progress"].waitForExistence(timeout: 5))
            assertProgress(20, completed: 1, in: app)
            XCTAssertTrue(app.buttons["workspaceProgressStep_\(step)"].exists)
        }
        attachScreenshot("Fresh one-of-five tappable checklist", app: app)
    }

    func testHidePreferenceIsWorkspaceScopedAndSurvivesRelaunch() throws {
        let app = makeApp(extraArguments: ["-uiTestProgressComplete"])
        app.launch()
        openSettings(app)
        XCTAssertTrue(element("settingsWorkspaceProgress", in: app).waitForExistence(timeout: 5))
        openMaintenance(app)
        let hideProgress = app.switches["hideWorkspaceProgress"]
        XCTAssertTrue(hideProgress.waitForExistence(timeout: 5))
        XCTAssertEqual(hideProgress.value as? String, "0")
        hideProgress.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(hideProgress.value as? String, "1")
        attachScreenshot("Hide progress for selected workspace", app: app)
        returnToSettingsFromMaintenance(app)
        XCTAssertFalse(element("settingsWorkspaceProgress", in: app).exists)

        // Keep the same isolated store and defaults, bypassing seed/reset on this launch.
        app.terminate()
        app.launchArguments.removeAll { $0 == "-uiTestingReset" }
        app.launchArguments.append("-uiTestPreserveScenarioData")
        app.launch()
        openSettings(app)
        XCTAssertFalse(element("settingsWorkspaceProgress", in: app).exists)

        selectWorkspace("Other Workspace", in: app)
        XCTAssertTrue(element("settingsWorkspaceProgress", in: app).waitForExistence(timeout: 5))
        openProgress(app)
        assertProgress(0, completed: 0, in: app)
        goBack(from: "Workspace Progress", to: "Settings", in: app)

        selectWorkspace("Progress Workspace", in: app)
        XCTAssertFalse(element("settingsWorkspaceProgress", in: app).exists)
        openMaintenance(app)
        XCTAssertEqual(hideProgress.value as? String, "1")
        hideProgress.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(hideProgress.value as? String, "0")
        returnToSettingsFromMaintenance(app)
        XCTAssertTrue(element("settingsWorkspaceProgress", in: app).waitForExistence(timeout: 5))
        openProgress(app)
        assertProgress(100, completed: 5, in: app)
    }

    func testPresetRequiresCurrentCardAndOffersRecoveryAfterCardDeletion() throws {
        let app = makeApp(extraArguments: ["-uiTestProgressNoCard"])
        app.launch()
        openSettings(app)
        openProgress(app)
        assertProgress(60, completed: 3, in: app)

        let addPreset = app.buttons["workspaceProgressStep_preset"]
        reveal(addPreset, in: app)
        XCTAssertFalse(addPreset.isEnabled)
        let restoreCard = app.buttons["workspaceProgressRestoreCard"]
        reveal(restoreCard, in: app)
        attachScreenshot("Preset requires an existing card", app: app)
        restoreCard.tap()
        XCTAssertTrue(app.navigationBars["Add Card"].waitForExistence(timeout: 5))
        let name = app.textFields["Credit Card, Checking, or Cash"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Replacement Card")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Workspace Progress"].waitForExistence(timeout: 5))
        reveal(addPreset, in: app)
        XCTAssertTrue(addPreset.isEnabled)
        addPreset.tap()
        XCTAssertTrue(app.navigationBars["Add Preset"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        assertProgress(60, completed: 3, in: app)
    }

    private func makeApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingReset", "-uiTestScenarioWorkspaceProgress",
            "-tips_seenKeys", "tip.home.v1,tip.budgets.v1,tip.cards.v1,tip.income.v2,tip.budgetdetail.v1",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ] + extraArguments
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func openSettings(_ app: XCUIApplication) {
        if app.navigationBars["Settings"].waitForExistence(timeout: 2) { return }
        let tab = app.tabBars.buttons["Settings"]
        if tab.waitForExistence(timeout: 3) {
            tab.tap()
        } else {
            let settings = app.buttons["Settings"].firstMatch
            if settings.waitForExistence(timeout: 3), settings.isHittable {
                settings.tap()
            } else {
                let sidebar = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "sidebar")).firstMatch
                if sidebar.exists { sidebar.tap() }
                let sidebarSettings = app.staticTexts["Settings"].firstMatch
                XCTAssertTrue(sidebarSettings.waitForExistence(timeout: 5))
                sidebarSettings.tap()
            }
        }
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
    }

    private func openProgress(_ app: XCUIApplication) {
        let row = element("settingsWorkspaceProgress", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.navigationBars["Workspace Progress"].waitForExistence(timeout: 5))
    }

    private func openPresets(_ app: XCUIApplication) {
        openSettings(app)
        let presets = element("settings_managePresets", in: app)
        reveal(presets, in: app)
        presets.tap()
        XCTAssertTrue(app.navigationBars["Presets"].waitForExistence(timeout: 5))
    }

    private func addPresetFromProgress(in app: XCUIApplication) {
        let add = app.buttons["workspaceProgressStep_preset"]
        reveal(add, in: app)
        add.tap()
    }

    private func savePreset(named name: String, in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Add Preset"].waitForExistence(timeout: 5))
        app.buttons["Choose a Card"].tap()
        app.buttons["First Card"].tap()
        let title = app.textFields["Expense Name"]
        title.tap()
        title.typeText(name)
        let amount = app.textFields["Planned Amount"]
        amount.tap()
        amount.typeText("1200")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Preset Saved"].waitForExistence(timeout: 5))
    }

    private func openBudget(_ name: String, in app: XCUIApplication) {
        if !app.navigationBars["Budgets"].exists {
            app.tabBars.buttons["Budgets"].tap()
        }
        XCTAssertTrue(app.navigationBars["Budgets"].waitForExistence(timeout: 5))
        let budget = app.staticTexts[name].firstMatch
        if name == "Ended Budget", !budget.exists {
            let pastBudgets = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Past Budgets")).firstMatch
            reveal(pastBudgets, in: app)
            pastBudgets.tap()
        }
        reveal(budget, in: app)
        budget.tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
    }

    private func assertPreset(_ name: String, isLinked: Bool, in app: XCUIApplication, openSheet: Bool = true) {
        if openSheet {
            app.buttons["Budget Actions"].tap()
            app.buttons["Manage Presets"].tap()
        }
        XCTAssertTrue(app.navigationBars["Linked Presets"].waitForExistence(timeout: 5))
        let toggle = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, isLinked ? "1" : "0")
    }

    private func openMaintenance(_ app: XCUIApplication) {
        let general = element("settings_general", in: app)
        reveal(general, in: app)
        general.tap()
        XCTAssertTrue(app.navigationBars["General"].waitForExistence(timeout: 5))
        let maintenance = app.buttons["Maintenance"].firstMatch
        reveal(maintenance, in: app)
        maintenance.tap()
        XCTAssertTrue(app.navigationBars["Maintenance"].waitForExistence(timeout: 5))
    }

    private func returnToSettingsFromMaintenance(_ app: XCUIApplication) {
        goBack(from: "Maintenance", to: "General", in: app)
        goBack(from: "General", to: "Settings", in: app)
    }

    private func goBack(from title: String, to previousTitle: String, in app: XCUIApplication) {
        let namedBack = app.navigationBars[title].buttons[previousTitle]
        if namedBack.exists {
            namedBack.tap()
        } else {
            app.navigationBars[title].buttons["Back"].tap()
        }
        XCTAssertTrue(app.navigationBars[previousTitle].waitForExistence(timeout: 5))
    }

    private func selectWorkspace(_ name: String, in app: XCUIApplication) {
        let workspaces = app.navigationBars["Settings"].buttons["Workspaces"]
        XCTAssertTrue(workspaces.waitForExistence(timeout: 5))
        workspaces.tap()
        let workspace = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        XCTAssertTrue(workspace.waitForExistence(timeout: 5))
        workspace.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    private func assertProgress(_ percent: Int, completed: Int, in app: XCUIApplication) {
        let summary = element("workspaceProgressSummary", in: app)
        for _ in 0..<8 {
            if summary.exists && summary.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        let expected = NSPredicate(format: "value CONTAINS %@", "\(percent) percent, \(completed) of 5 completed")
        expectation(for: expected, evaluatedWith: summary)
        waitForExpectations(timeout: 5)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }

    private func attachScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
