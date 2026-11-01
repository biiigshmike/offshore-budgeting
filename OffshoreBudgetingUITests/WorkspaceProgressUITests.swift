import XCTest

@MainActor
final class WorkspaceProgressUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

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

        let addIncome = app.buttons["workspaceProgressAdd_income"]
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
        XCTAssertFalse(app.buttons["workspaceProgressAdd_income"].exists)
        let hideGuidance = element("workspaceProgressHideGuidance", in: app)
        reveal(hideGuidance, in: app)
        attachScreenshot("Workspace setup complete", app: app)
        goBack(from: "Workspace Progress", to: "Settings", in: app)
        XCTAssertTrue(element("settingsWorkspaceProgress", in: app).waitForExistence(timeout: 5))
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

        let addPreset = app.buttons["workspaceProgressAdd_preset"]
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
            "-tips_seenKeys", "tip.home.v1,tip.budgets.v1,tip.cards.v1,tip.income.v1,tip.budgetdetail.v1",
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
        XCTAssertTrue(element.exists && element.isHittable)
    }

    private func attachScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
