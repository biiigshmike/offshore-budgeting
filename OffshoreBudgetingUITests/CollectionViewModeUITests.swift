import UIKit
import XCTest

@MainActor
final class CollectionViewModeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAllFiveCollectionsSwitchLayoutsAndKeepDetailNavigation() throws {
        let app = launchApp()
        try XCTSkipUnless(app.tabBars.buttons["Accounts"].exists,
                          "This smoke test uses the phone tab and Accounts navigation.")

        app.tabBars.buttons["Budgets"].tap()
        assertBothLayouts(in: app, collectionTitle: "Budgets", detailTitle: "Existing Menu Budget") {
            app.staticTexts["Existing Menu Budget"].firstMatch
        }

        app.tabBars.buttons["Accounts"].tap()
        app.buttons["accounts.destination.cards"].tap()
        assertBothLayouts(in: app, collectionTitle: "Cards", detailTitle: "Ruby Card") {
            app.staticTexts["Ruby Card"].firstMatch
        }
        app.navigationBars["Cards"].buttons["Accounts"].tap()
        app.buttons["accounts.destination.sharedBalances"].tap()
        assertBothLayouts(in: app, collectionTitle: "Reconciliations", detailTitle: "Shared Lunch") {
            app.staticTexts["Shared Lunch"].firstMatch
        }
        app.navigationBars["Reconciliations"].buttons["Accounts"].tap()
        app.buttons["accounts.destination.savings"].tap()
        XCTAssertTrue(app.staticTexts["savings.runningTotal"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["collection.viewMenu"].exists,
                       "Savings should retain its existing toolbar without collection layout controls.")

        app.tabBars.buttons["Settings"].tap()
        openManagement("Manage Categories", title: "Categories", in: app)
        assertBothLayouts(in: app, collectionTitle: "Categories", detailTitle: "Detail Dining") {
            app.descendants(matching: .any)
                .matching(identifier: "categories.row.C1000000-0000-0000-0000-000000000001").firstMatch
        }
        XCTAssertTrue(app.buttons["categories.autoConfigureGoals"].exists)
        XCTAssertTrue(app.staticTexts["Archived"].exists)
        app.navigationBars["Categories"].buttons["Settings"].tap()
        openManagement("Manage Presets", title: "Presets", in: app)
        assertBothLayouts(in: app, collectionTitle: "Presets", detailTitle: "Internet") {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Internet")).firstMatch
        }
    }

    func testLayoutPreferenceSurvivesRelaunchWithoutOverridingLaunchDefaults() throws {
        let app = launchApp()
        try XCTSkipUnless(app.tabBars.buttons["Accounts"].exists,
                          "This persistence test uses the phone navigation.")
        app.tabBars.buttons["Budgets"].tap()
        chooseLayout("Gallery", in: app)
        app.terminate()
        // The fixture reseeds financial data, but layout preferences are app-level defaults.
        // Do not pass -view.budgets.mode: argument-domain values would mask persisted writes.
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Budgets"].tap()
        let menu = app.buttons["collection.viewMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertEqual(menu.label, "View, Gallery")
        chooseLayout("List", in: app)
    }

    func testDarkAccessibilitySizeKeepsGalleriesAndNativeListsReachable() throws {
        let previousAppearance = XCUIDevice.shared.appearance
        XCUIDevice.shared.appearance = .dark
        defer { XCUIDevice.shared.appearance = previousAppearance }
        let app = launchApp(extraArguments: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        try XCTSkipUnless(app.tabBars.buttons["Accounts"].exists,
                          "This accessibility smoke test uses phone navigation.")

        app.tabBars.buttons["Budgets"].tap()
        assertAccessibleLayout("Gallery", in: app, collectionTitle: "Budgets",
                               detailTitle: "Existing Menu Budget") {
            app.staticTexts["Existing Menu Budget"].firstMatch
        }

        app.tabBars.buttons["Accounts"].tap()
        app.buttons["accounts.destination.cards"].tap()
        assertAccessibleLayout("List", in: app, collectionTitle: "Cards", detailTitle: "Ruby Card") {
            app.staticTexts["Ruby Card"].firstMatch
        }
        app.navigationBars["Cards"].buttons["Accounts"].tap()
        let reconciliations = app.buttons["accounts.destination.sharedBalances"]
        reveal(reconciliations, in: app)
        reconciliations.tap()
        assertAccessibleLayout("List", in: app, collectionTitle: "Reconciliations", detailTitle: "Shared Lunch") {
            app.staticTexts["Shared Lunch"].firstMatch
        }

        app.tabBars.buttons["Settings"].tap()
        openManagement("Manage Categories", title: "Categories", in: app)
        assertAccessibleLayout("Gallery", in: app, collectionTitle: "Categories", detailTitle: "Detail Dining") {
            app.descendants(matching: .any)
                .matching(identifier: "categories.row.C1000000-0000-0000-0000-000000000001").firstMatch
        }
    }

    func testTabletGalleryUsesMultipleColumnsAndKeepsNavigation() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad,
                          "This wide-layout test requires an existing iPad simulator.")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launchApp()
        let settingsButton = app.buttons["Settings"].firstMatch
        let settingsText = app.staticTexts["Settings"].firstMatch
        if !settingsButton.isHittable && !settingsText.isHittable {
            let sidebar = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "sidebar")).firstMatch
            if sidebar.exists { sidebar.tap() }
        }
        if settingsButton.exists && settingsButton.isHittable {
            settingsButton.tap()
        } else {
            XCTAssertTrue(settingsText.waitForExistence(timeout: 5))
            settingsText.tap()
        }
        openManagement("Manage Categories", title: "Categories", in: app)
        chooseLayout("Gallery", in: app)
        let dining = app.descendants(matching: .any)
            .matching(identifier: "categories.row.C1000000-0000-0000-0000-000000000001").firstMatch
        let other = app.descendants(matching: .any)
            .matching(identifier: "categories.row.C1000000-0000-0000-0000-000000000003").firstMatch
        XCTAssertTrue(dining.waitForExistence(timeout: 5))
        XCTAssertTrue(other.waitForExistence(timeout: 5))
        XCTAssertEqual(dining.frame.minY, other.frame.minY, accuracy: 2,
                       "The wide gallery should place categories on the same grid row.")
        XCTAssertGreaterThan(abs(dining.frame.minX - other.frame.minX), 20)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Categories — Gallery, wide iPad"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        dining.tap()
        XCTAssertTrue(app.navigationBars["Detail Dining"].waitForExistence(timeout: 5))
    }

    func testCompactGalleriesPlaceAdjacentItemsOnPortraitPhone() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone,
                          "Compact gallery adjacency is checked on a portrait phone.")
        XCUIDevice.shared.orientation = .portrait
        let app = launchApp(extraArguments: compactGalleryArguments)
        assertCompactGalleryGeometry(in: app, singleColumn: false)
    }

    func testCompactGalleriesUseOneColumnAtAccessibilitySizes() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone,
                          "This accessibility gallery check uses phone navigation.")
        XCUIDevice.shared.orientation = .portrait
        let app = launchApp(extraArguments: compactGalleryArguments + [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        assertCompactGalleryGeometry(in: app, singleColumn: true)
    }

    func testCardListMiniatureUpdatesAfterEditingThemeAndEffect() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone,
                          "This native card-list edit check uses phone navigation.")
        let app = launchApp()
        app.tabBars.buttons["Accounts"].tap()
        app.buttons["accounts.destination.cards"].tap()
        chooseLayout("List", in: app)
        let originalRow = app.buttons["Ruby Card"]
        XCTAssertTrue(originalRow.waitForExistence(timeout: 5))
        XCTAssertEqual(originalRow.label, "Ruby Card")
        let before = originalRow.screenshot()
        let beforeAttachment = XCTAttachment(screenshot: before)
        beforeAttachment.name = "Ruby Card list miniature — before editing"
        beforeAttachment.lifetime = .keepAlways
        add(beforeAttachment)

        originalRow.press(forDuration: 1)
        let edit = app.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(app.navigationBars["Edit Card"].waitForExistence(timeout: 5))
        let name = app.textFields["Credit Card, Checking, or Cash"]
        XCTAssertEqual(name.value as? String, "Ruby Card")
        let glass = app.buttons["Glass"]
        reveal(glass, in: app)
        glass.tap()
        let aqua = app.buttons["Aqua"]
        reveal(aqua, in: app)
        aqua.tap()
        app.navigationBars["Edit Card"].buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Edit Card"].waitForNonExistence(timeout: 5))

        let updatedRow = app.buttons["Ruby Card"]
        XCTAssertTrue(updatedRow.waitForExistence(timeout: 5))
        XCTAssertEqual(updatedRow.label, "Ruby Card", "Editing appearance must preserve the full card name.")
        let after = updatedRow.screenshot()
        let afterAttachment = XCTAttachment(screenshot: after)
        afterAttachment.name = "Ruby Card list miniature — Aqua and Glass after saving"
        afterAttachment.lifetime = .keepAlways
        add(afterAttachment)
        XCTAssertNotEqual(before.pngRepresentation, after.pngRepresentation,
                          "The native list row artwork should refresh after editing its theme and effect.")

        updatedRow.swipeRight()
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "Native list swipe editing should remain available.")
        edit.tap()
        XCTAssertTrue(app.navigationBars["Edit Card"].waitForExistence(timeout: 5))
        app.navigationBars["Edit Card"].buttons["Cancel"].tap()
    }

    private var compactGalleryArguments: [String] {
        ["-uiTestCompactGalleries", "-sort.categories.mode", "az", "-sort.presets.mode", "az"]
    }

    private func assertCompactGalleryGeometry(in app: XCUIApplication, singleColumn: Bool) {
        app.tabBars.buttons["Budgets"].tap()
        chooseLayout("Gallery", in: app)
        assertGalleryPair(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Existing Menu Budget")).firstMatch,
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Compact Gallery Budget")).firstMatch,
            singleColumn: singleColumn, title: "Budgets", in: app
        )

        app.tabBars.buttons["Settings"].tap()
        openManagement("Manage Categories", title: "Categories", in: app)
        chooseLayout("Gallery", in: app)
        assertGalleryPair(
            app.buttons.matching(NSPredicate(format: "label == %@", "Bills")).firstMatch,
            app.descendants(matching: .any)
                .matching(identifier: "categories.row.C1000000-0000-0000-0000-000000000001").firstMatch,
            singleColumn: singleColumn, title: "Categories", in: app
        )
        app.navigationBars["Categories"].buttons["Settings"].tap()
        openManagement("Manage Presets", title: "Presets", in: app)
        chooseLayout("Gallery", in: app)
        assertGalleryPair(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Internet")).firstMatch,
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Rent")).firstMatch,
            singleColumn: singleColumn, title: "Presets", in: app
        )
    }

    private func assertGalleryPair(
        _ first: XCUIElement,
        _ second: XCUIElement,
        singleColumn: Bool,
        title: String,
        in app: XCUIApplication
    ) {
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        reveal(first, in: app)
        reveal(second, in: app)
        if singleColumn {
            XCTAssertEqual(first.frame.minX, second.frame.minX, accuracy: 2,
                           "\(title) must use one column at accessibility text sizes.")
            XCTAssertGreaterThan(abs(first.frame.minY - second.frame.minY), 20)
        } else {
            XCTAssertEqual(first.frame.minY, second.frame.minY, accuracy: 2,
                           "\(title) should show adjacent tiles in a portrait phone gallery.")
            XCTAssertGreaterThan(abs(first.frame.minX - second.frame.minX), 20)
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "\(title) — compact gallery, \(singleColumn ? "accessibility one column" : "portrait adjacent tiles")"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func assertAccessibleLayout(
        _ layout: String,
        in app: XCUIApplication,
        collectionTitle: String,
        detailTitle: String,
        row: () -> XCUIElement
    ) {
        XCTAssertTrue(app.navigationBars[collectionTitle].waitForExistence(timeout: 5))
        chooseLayout(layout, in: app)
        let destination = row()
        reveal(destination, in: app)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "\(collectionTitle) — \(layout), Dark, accessibility XXXL"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        destination.tap()
        XCTAssertTrue(app.navigationBars[detailTitle].waitForExistence(timeout: 5))
        app.navigationBars[detailTitle].buttons[collectionTitle].tap()
        XCTAssertEqual(app.buttons["collection.viewMenu"].label, "View, \(layout)")
    }

    private func launchApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingReset", "-uiTestScenarioBudgetMenus",
            "-uiTestCategoryDetailHistory", "-uiTestDetailListReconciliation",
            "-tips_seenKeys", "tip.home.v1,tip.budgets.v1,tip.budgetdetail.v1,tip.cards.v1,tip.carddetail.v1,tip.categories.v1,tip.preset.v1",
            "-general_defaultBudgetingPeriod", "monthly", "-general_currencyCode", "USD",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ] + extraArguments
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 15))
        return app
    }

    private func assertBothLayouts(
        in app: XCUIApplication,
        collectionTitle: String,
        detailTitle: String,
        row: () -> XCUIElement
    ) {
        XCTAssertTrue(app.navigationBars[collectionTitle].waitForExistence(timeout: 5))
        for layout in ["Gallery", "List"] {
            chooseLayout(layout, in: app)
            let destination = row()
            reveal(destination, in: app)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(collectionTitle) — \(layout)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            destination.tap()
            XCTAssertTrue(app.navigationBars[detailTitle].waitForExistence(timeout: 5),
                          "\(collectionTitle) should open details from \(layout).")
            app.navigationBars[detailTitle].buttons[collectionTitle].tap()
            XCTAssertTrue(app.navigationBars[collectionTitle].waitForExistence(timeout: 5))
            XCTAssertEqual(app.buttons["collection.viewMenu"].label, "View, \(layout)")
        }
    }

    private func chooseLayout(_ title: String, in app: XCUIApplication) {
        let menu = app.buttons["collection.viewMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertTrue(menu.isHittable)
        menu.tap()
        let option = app.buttons[title]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
        XCTAssertEqual(menu.label, "View, \(title)")
    }

    private func openManagement(_ label: String, title: String, in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let management = app.buttons[label]
        reveal(management, in: app)
        management.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
}
