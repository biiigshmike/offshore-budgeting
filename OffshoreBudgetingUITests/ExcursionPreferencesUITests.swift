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

    func testGroupsAndSearchShareSelectionAndPreventEmptyCustomMode() {
        let app = launch()
        openPreferences(app)
        app.buttons["excursionGroup_food-drink"].tap()
        app.buttons["excursionGroup_shopping"].tap()
        app.buttons["excursionGroup_fuel-charging"].tap()
        XCTAssertFalse(app.buttons["excursionGroup_groceries"].isEnabled)
        app.buttons["excursionAllCategories"].tap()
        XCTAssertTrue(app.navigationBars["All Categories"].waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Grocery")
        let grocery = app.buttons.matching(NSPredicate(format: "label == %@", "Grocery Stores")).firstMatch
        XCTAssertTrue(grocery.waitForExistence(timeout: 5))
        XCTAssertFalse(grocery.isEnabled)
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
        app.navigationBars["All Categories"].buttons.firstMatch.tap()
        let uncategorized = app.switches["excursionIncludeUncategorized"]
        reveal(uncategorized, in: app)
        uncategorized.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(uncategorized.value as? String, "1")
        XCTAssertTrue(app.buttons["excursionGroup_food-drink"].exists)
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
        XCTAssertTrue(app.buttons["excursionGroup_food-drink"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["excursionGroup_food-drink"].value as? String, "Selected")
    }

    func testIndividualCategoryUpdatesGroupPartialState() {
        let app = launch()
        openPreferences(app)
        app.buttons["excursionAllCategories"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Restaurant")
        let restaurant = app.buttons.matching(NSPredicate(format: "label == %@", "Restaurant")).firstMatch
        XCTAssertTrue(restaurant.waitForExistence(timeout: 5))
        restaurant.tap()
        // Active search replaces the back button with Close on recent iOS.
        let closeSearch = app.navigationBars["All Categories"].buttons["Close"]
        if closeSearch.exists { closeSearch.tap() }
        app.navigationBars["All Categories"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Excursion Preferences"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["excursionGroup_food-drink"].value as? String, "Partially selected")
        app.buttons["excursionGroup_food-drink"].tap()
        XCTAssertEqual(app.buttons["excursionGroup_food-drink"].value as? String, "Selected")
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
