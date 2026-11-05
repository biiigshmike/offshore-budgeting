import XCTest

@MainActor
final class ExcursionPreferencesUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testNavigationThemeAndNativeBack() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingReset", "-uiTestScenarioWorkspaceProgress",
                               "-appearance_theme", "heather",
                               "-tips_seenKeys", "tip.home.v1,tip.budgets.v1,tip.cards.v1,tip.income.v1,tip.budgetdetail.v1",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        openPreferences(app)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Themed native navigation"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.navigationBars["Excursion Preferences"].buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["excursionPreferences"].waitForExistence(timeout: 5))
    }

    func testSidebarThemeRendering() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingReset", "-uiTestScenarioWorkspaceProgress",
                               "-appearance_theme", "heather",
                               "-tips_seenKeys", "tip.home.v1,tip.budgets.v1,tip.cards.v1,tip.income.v1,tip.budgetdetail.v1",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        try XCTSkipIf(app.tabBars.firstMatch.exists, "Sidebar rendering requires iPad or Mac Catalyst.")
        let sidebar = app.buttons["navigation.sidebarToggle"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 10))
        sidebar.tap()
        XCTAssertFalse(app.staticTexts["Quick Links"].isHittable)
        sidebar.tap()
        XCTAssertTrue(app.staticTexts["Quick Links"].isHittable)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Themed native sidebar"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testSelectAllUncategorizedPersistenceAndRestoreDefaults() {
        let app = launch()
        openPreferences(app)
        XCTAssertFalse(app.segmentedControls["excursionPlacesMode"].exists)
        XCTAssertFalse(app.buttons["excursionSelectAll"].exists)
        app.buttons["excursionAllCategories"].tap()
        app.buttons["excursionEditCategories"].tap()
        app.buttons["excursionDeselectAllCategories"].tap()
        XCTAssertFalse(app.buttons["excursionSaveCategories"].isEnabled)
        app.buttons["excursionCancelCategories"].tap()
        app.buttons["excursionEditCategories"].tap()
        XCTAssertTrue(app.buttons["excursionSaveCategories"].isEnabled)
        app.buttons["excursionSelectAllCategories"].tap()
        app.buttons["excursionSaveCategories"].tap()
        app.navigationBars["Categories"].buttons.firstMatch.tap()
        let uncategorized = app.switches["excursionIncludeUncategorized"]
        reveal(uncategorized, in: app)
        uncategorized.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(uncategorized.value as? String, "1")
        XCTAssertFalse(app.descendants(matching: .any)["excursionGroup_food-drink"].firstMatch.exists)
        let timing = app.descendants(matching: .any)["excursionDwellTime"].firstMatch
        timing.tap()
        app.buttons["2 minutes"].tap()
        app.terminate()
        app.launchArguments.removeAll { $0 == "-uiTestingReset" }
        app.launch()
        openPreferences(app)
        XCTAssertEqual(app.switches["excursionIncludeUncategorized"].value as? String, "1")
        let persistedTiming = app.descendants(matching: .any)["excursionDwellTime"].firstMatch
        XCTAssertTrue(persistedTiming.label.contains("2 minutes") || (persistedTiming.value as? String)?.contains("2 minutes") == true)
        let restore = app.buttons["excursionRestoreDefaults"]
        reveal(restore, in: app)
        restore.tap()
        XCTAssertEqual(app.switches["excursionIncludeUncategorized"].value as? String, "0")
        let categories = app.buttons["excursionAllCategories"]
        XCTAssertTrue(categories.exists)
        XCTAssertTrue(categories.label.contains("12 selected"))
    }

    func testNativeCategorySelectionSavesMultipleRowsAndCancelDiscardsChanges() {
        let app = launch()
        openPreferences(app)
        app.buttons["excursionAllCategories"].tap()
        let readOnlyAirport = app.staticTexts["Airport"]
        XCTAssertFalse(readOnlyAirport.isEnabled)
        readOnlyAirport.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(readOnlyAirport.value as? String, "Not selected")
        app.buttons["excursionEditCategories"].tap()
        app.buttons["excursionDeselectAllCategories"].tap()
        XCTAssertFalse(app.buttons["excursionSaveCategories"].isEnabled)

        app.staticTexts["Airport"].tap()
        app.staticTexts["Amusement Park"].tap()
        let editingScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        editingScreenshot.name = "Native categories editing"
        editingScreenshot.lifetime = .keepAlways
        add(editingScreenshot)
        XCTAssertTrue(app.buttons["excursionSaveCategories"].isEnabled)
        app.buttons["excursionSaveCategories"].tap()
        let airport = app.staticTexts.matching(NSPredicate(format: "label == %@", "Airport")).firstMatch
        let amusementPark = app.staticTexts.matching(NSPredicate(format: "label == %@", "Amusement Park")).firstMatch
        XCTAssertEqual(airport.value as? String, "Selected")
        XCTAssertEqual(amusementPark.value as? String, "Selected")
        XCTAssertFalse(airport.isEnabled)
        airport.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(airport.value as? String, "Selected")
        let savedScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        savedScreenshot.name = "Native categories saved"
        savedScreenshot.lifetime = .keepAlways
        add(savedScreenshot)

        app.buttons["excursionEditCategories"].tap()
        app.staticTexts["Airport"].tap()
        app.buttons["excursionCancelCategories"].tap()
        XCTAssertEqual(airport.value as? String, "Selected")
        XCTAssertEqual(amusementPark.value as? String, "Selected")
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingReset", "-uiTestScenarioWorkspaceProgress",
            "-tips_seenKeys", "tip.home.v1,tip.budgets.v1,tip.cards.v1,tip.income.v1,tip.budgetdetail.v1",
            "-tips_resetToken", "0", "-tips_seen_lastResetToken", "0",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        return app
    }

    private func openPreferences(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Settings"].tap()
        let notifications = app.buttons["Notifications"].firstMatch
        reveal(notifications, in: app)
        notifications.tap()
        let preferences = app.buttons["excursionPreferences"]
        reveal(preferences, in: app)
        preferences.tap()
        XCTAssertTrue(app.navigationBars["Excursion Preferences"].waitForExistence(timeout: 5))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }
}
