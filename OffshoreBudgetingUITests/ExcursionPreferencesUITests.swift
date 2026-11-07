import XCTest

@MainActor
final class ExcursionPreferencesUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testExcursionControlsAtLargestDynamicTypeSize() {
        let app = launch(additionalArguments: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        openExcursionMode(app)

        XCTAssertEqual(app.staticTexts["excursionStatus"].label, "Inactive")
        XCTAssertFalse(app.segmentedControls.firstMatch.exists)
        let durationChoices = app.descendants(matching: .any)
        reveal(durationChoices["1 hour"].firstMatch, in: app)
        reveal(durationChoices["4 hours"].firstMatch, in: app)
        reveal(app.buttons["Start Excursion Mode"], in: app)
        reveal(app.buttons["excursionPreferences"], in: app)
    }

    func testLegacyThemePreferencePreservesNativeBack() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingReset", "-uiTestScenarioWorkspaceProgress",
                               "-appearance_theme", "heather",
                               "-tips_seenKeys", "tip.home.v1,tip.budgets.v1,tip.cards.v1,tip.income.v1,tip.budgetdetail.v1",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        openPreferences(app)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Default navigation with legacy theme preference"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.navigationBars["Excursion Preferences"].buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["excursionPreferences"].waitForExistence(timeout: 5))
    }

    func testSidebarIgnoresLegacyThemePreference() throws {
        try verifyNativeSidebar(theme: "heather")
    }

    func testSidebarDefaultRendering() throws {
        try verifyNativeSidebar(theme: "offshore-default")
    }

    private func verifyNativeSidebar(theme: String) throws {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        #endif
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingReset", "-uiTestScenarioWorkspaceProgress",
                               "-appearance_theme", theme,
                               "-tips_seenKeys", "tip.home.v1,tip.budgets.v1,tip.cards.v1,tip.income.v1,tip.budgetdetail.v1",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        try XCTSkipIf(app.tabBars.firstMatch.exists, "Sidebar rendering requires iPad or Mac Catalyst.")
        XCTAssertFalse(app.buttons["navigation.sidebarToggle"].exists)
        let sidebar = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "sidebar")).firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 10))
        if !app.staticTexts["Quick Links"].isHittable { sidebar.tap() }
        XCTAssertTrue(app.staticTexts["Quick Links"].isHittable)
        XCTAssertLessThan(sidebar.frame.midX, app.windows.firstMatch.frame.midX)
        let visibleToggles = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "sidebar")).allElementsBoundByIndex.filter(\.isHittable)
        XCTAssertEqual(visibleToggles.count, 1)
        attachScreenshot("Native sidebar expanded - \(theme)")
        sidebar.tap()
        XCTAssertFalse(app.staticTexts["Quick Links"].isHittable)
        attachScreenshot("Native sidebar collapsed - \(theme)")
        sidebar.tap()
        XCTAssertTrue(app.staticTexts["Quick Links"].isHittable)
        app.staticTexts["Settings"].firstMatch.tap()
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        sidebar.tap()
        XCTAssertFalse(app.staticTexts["Quick Links"].isHittable)
        sidebar.tap()
        XCTAssertTrue(app.staticTexts["Quick Links"].isHittable)
    }

    private func attachScreenshot(_ name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
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
        let readOnlyAirport = app.staticTexts["excursionCategory_MKPOICategoryAirport"]
        XCTAssertTrue(app.buttons["excursionEditCategories"].exists)
        XCTAssertFalse(app.buttons["excursionDeselectAllCategories"].exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label == %@", "Airport")).firstMatch.exists)
        readOnlyAirport.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(readOnlyAirport.value as? String, "Not selected")
        app.buttons["excursionEditCategories"].tap()
        app.buttons["excursionDeselectAllCategories"].tap()
        XCTAssertFalse(app.buttons["excursionSaveCategories"].isEnabled)

        app.staticTexts["Airport"].tap()
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("Amusement")
        XCTAssertFalse(app.staticTexts["Airport"].exists)
        app.staticTexts["Amusement Park"].tap()
        search.buttons["Clear text"].tap()
        let closeSearch = app.navigationBars["Categories"].buttons["Close"]
        if closeSearch.exists { closeSearch.tap() }
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
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label == %@", "Airport")).firstMatch.exists)
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
        airport.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(airport.value as? String, "Selected")
        app.navigationBars["Categories"].buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["excursionAllCategories"].label.contains("2 selected"))
        app.buttons["excursionAllCategories"].tap()
        XCTAssertEqual(airport.value as? String, "Selected")
        XCTAssertEqual(amusementPark.value as? String, "Selected")

        app.buttons["excursionEditCategories"].tap()
        app.buttons["excursionDeselectAllCategories"].tap()
        let terminal = app.staticTexts["Airport Terminal"].firstMatch
        let nextCategory = terminal.exists ? terminal : amusementPark
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let selectionColumnX: CGFloat = 40
        let start = origin.withOffset(CGVector(dx: selectionColumnX, dy: airport.frame.midY))
        let end = origin.withOffset(CGVector(dx: selectionColumnX, dy: nextCategory.frame.midY))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.05)
        XCTAssertEqual(airport.value as? String, "Selected")
        XCTAssertEqual(nextCategory.value as? String, "Selected")
    }

    func testLegacyThemePreferencePreservesCategoryEditing() {
        let app = launch(theme: "heather")
        openPreferences(app)
        app.buttons["excursionAllCategories"].tap()
        attachScreenshot("Default categories with legacy theme preference read-only")
        app.buttons["excursionEditCategories"].tap()
        attachScreenshot("Default categories with legacy theme preference editing")
        app.buttons["excursionCancelCategories"].tap()
        XCTAssertTrue(app.buttons["excursionEditCategories"].exists)
    }

    private func launch(theme: String = "offshore-default", additionalArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingReset", "-uiTestScenarioWorkspaceProgress",
            "-appearance_theme", theme,
            "-tips_seenKeys", "tip.home.v1,tip.budgets.v1,tip.cards.v1,tip.income.v1,tip.budgetdetail.v1",
            "-tips_resetToken", "0", "-tips_seen_lastResetToken", "0",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ] + additionalArguments
        app.launch()
        return app
    }

    private func openPreferences(_ app: XCUIApplication) {
        openExcursionMode(app)
        let preferences = app.buttons["excursionPreferences"]
        reveal(preferences, in: app)
        preferences.tap()
        XCTAssertTrue(app.navigationBars["Excursion Preferences"].waitForExistence(timeout: 5))
    }

    private func openExcursionMode(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Settings"].tap()
        let excursion = app.buttons["settings_excursionMode"]
        reveal(excursion, in: app)
        excursion.tap()
        XCTAssertTrue(app.navigationBars["Excursion Mode"].waitForExistence(timeout: 5))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, String(app.debugDescription.prefix(5_000)))
    }
}
