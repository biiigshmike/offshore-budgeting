import XCTest

@MainActor
final class CategoryDetailUITests: XCTestCase {
    private let diningID = "C1000000-0000-0000-0000-000000000001"
    private let archivedID = "C1000000-0000-0000-0000-000000000002"
    private let otherID = "C1000000-0000-0000-0000-000000000003"
    private let lunchID = "variable-D1000000-0000-0000-0000-000000000001"
    private let coffeeID = "variable-D1000000-0000-0000-0000-000000000002"
    private let supperID = "variable-D1000000-0000-0000-0000-000000000003"
    private let previousID = "variable-D1000000-0000-0000-0000-000000000004"

    override func setUpWithError() throws { continueAfterFailure = false }

    private func launchCategories(currencyCode: String = "USD", extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingReset", "-uiTestScenarioBudgetMenus", "-uiTestCategoryDetailHistory",
            "-tips_seenKeys", "tip.home.v1,tip.categories.v1,tip.cards.v1,tip.carddetail.v1",
            "-general_defaultBudgetingPeriod", "monthly", "-general_currencyCode", currencyCode,
            "-general_confirmBeforeDeleting", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ] + extraArguments
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 15))
        openSettings(in: app)
        let manage = app.buttons["Manage Categories"]
        reveal(manage, in: app)
        manage.tap()
        XCTAssertTrue(app.navigationBars["Categories"].waitForExistence(timeout: 5))
        return app
    }

    private func openSettings(in app: XCUIApplication) {
        let tab = app.tabBars.buttons["Settings"]
        if tab.exists {
            tab.tap()
        } else if app.buttons["Settings"].firstMatch.exists && app.buttons["Settings"].firstMatch.isHittable {
            app.buttons["Settings"].firstMatch.tap()
        } else {
            let sidebarSettings = app.staticTexts["Settings"].firstMatch
            if !sidebarSettings.exists || !sidebarSettings.isHittable {
                let sidebar = app.buttons.matching(
                    NSPredicate(format: "label CONTAINS[c] %@", "sidebar")
                ).firstMatch
                if sidebar.exists { sidebar.tap() }
            }
            let expandedSidebar = XCTAttachment(screenshot: app.screenshot())
            expandedSidebar.name = "Expanded sidebar before opening Settings"
            expandedSidebar.lifetime = .keepAlways
            add(expandedSidebar)
            // Large accessibility text can put Settings below the sidebar's lazy rows.
            // Scroll the sidebar list instead of the separate Home detail column.
            let sidebarList = app.collectionViews.firstMatch.exists
                ? app.collectionViews.firstMatch : app.tables.firstMatch
            var selectedSettings = false
            for _ in 0..<8 {
                let settingsButton = app.buttons["Settings"].firstMatch
                if settingsButton.exists, settingsButton.isHittable {
                    settingsButton.tap()
                    selectedSettings = true
                    break
                }
                if sidebarSettings.exists, sidebarSettings.isHittable {
                    sidebarSettings.tap()
                    selectedSettings = true
                    break
                }
                XCTAssertTrue(sidebarList.exists, "The expanded sidebar should expose its scrollable list.")
                sidebarList.swipeUp()
            }
            XCTAssertTrue(selectedSettings, "Settings should be reachable by scrolling the expanded sidebar.")
        }
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
    }

    private func row(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    private func openDining(in app: XCUIApplication) {
        let category = row("categories.row.\(diningID)", in: app)
        reveal(category, in: app)
        category.tap()
        XCTAssertTrue(app.navigationBars["Detail Dining"].waitForExistence(timeout: 5))
    }

    private func chooseQuickRange(_ title: String, in app: XCUIApplication) {
        app.buttons["dateRange.quickRanges"].tap()
        let choice = app.buttons[title]
        reveal(choice, in: app)
        choice.tap()
    }

    private func clearAndDismissSearch(in app: XCUIApplication) {
        let clear = app.buttons["Clear text"]
        if clear.exists { clear.tap() }
        let close = app.buttons["Close"]
        if close.exists {
            close.tap()
        } else {
            app.buttons["Cancel"].tap()
        }
    }

    func testCurrentMonthShowsBothCardsAndScopeTotals() {
        let app = launchCategories()
        openDining(in: app)
        let total = row("categoryDetail.total", in: app)
        XCTAssertTrue((total.value as? String)?.contains("70.00") == true)
        let scope = app.buttons["detailList.expenseType"]
        scope.tap()
        app.buttons["Variable"].tap()
        XCTAssertTrue((total.value as? String)?.contains("30.00") == true)

        let lunch = row("categoryDetail.expense.\(lunchID)", in: app)
        reveal(lunch, in: app)
        XCTAssertTrue(lunch.label.contains("Lunch Ruby"))
        XCTAssertTrue(lunch.label.contains("Ruby Card"))
        let coffee = row("categoryDetail.expense.\(coffeeID)", in: app)
        reveal(coffee, in: app)
        XCTAssertTrue(coffee.label.contains("Coffee Ocean"))
        XCTAssertTrue(coffee.label.contains("Ocean Card"))
        XCTAssertFalse(app.staticTexts["Other Category Purchase"].exists)
        XCTAssertFalse(row("categoryDetail.expense.\(previousID)", in: app).exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Category expenses across cards"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testSearchAndDateRangeReachHistoricalExpenses() {
        let app = launchCategories()
        openDining(in: app)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Previous Month Dining")
        let previous = row("categoryDetail.expense.\(previousID)", in: app)
        XCTAssertFalse(previous.exists)
        clearAndDismissSearch(in: app)
        chooseQuickRange("Last Month", in: app)
        search.tap()
        search.typeText("Previous Month Dining")
        reveal(previous, in: app)
        XCTAssertTrue(previous.label.contains("Previous Month Dining"))
        XCTAssertFalse(row("categoryDetail.expense.\(lunchID)", in: app).exists)
        clearAndDismissSearch(in: app)
        chooseQuickRange("Current Month", in: app)
        XCTAssertTrue(previous.waitForNonExistence(timeout: 5))
        let lunch = row("categoryDetail.expense.\(lunchID)", in: app)
        reveal(lunch, in: app)
        XCTAssertTrue(lunch.label.contains("Lunch Ruby"))
    }

    func testAccessibilityTextSizeKeepsSearchTotalsAndExpenseEditingReachable() {
        let app = launchCategories(extraArguments: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        openDining(in: app)
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        let total = row("categoryDetail.total", in: app)
        XCTAssertTrue(total.exists)
        XCTAssertTrue((total.value as? String)?.contains("70.00") == true)
        let overview = XCTAttachment(screenshot: app.screenshot())
        overview.name = "Category detail at largest accessibility text size"
        overview.lifetime = .keepAlways
        add(overview)

        let lunch = row("categoryDetail.expense.\(lunchID)", in: app)
        reveal(lunch, in: app)
        XCTAssertTrue(lunch.label.contains("Lunch Ruby"))
        XCTAssertTrue(lunch.label.contains("Ruby Card"))
        let expense = XCTAttachment(screenshot: app.screenshot())
        expense.name = "Category expense card label at largest accessibility text size"
        expense.lifetime = .keepAlways
        add(expense)
        lunch.tap()
        XCTAssertTrue(app.navigationBars["Edit Expense"].waitForExistence(timeout: 5))
        let cancel = app.navigationBars["Edit Expense"].buttons["Cancel"]
        XCTAssertTrue(cancel.isHittable)
        cancel.tap()
        XCTAssertTrue(app.navigationBars["Edit Expense"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Detail Dining"].exists)
    }

    func testFloatingSortMenuSupportsEveryDirectionAtLargestTextSize() {
        let app = launchCategories(currencyCode: "EUR", extraArguments: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        openDining(in: app)
        XCTAssertTrue((row("categoryDetail.total", in: app).value as? String)?.contains("€") == true)

        let sort = app.buttons["detailList.sort"]
        let scope = app.buttons["detailList.expenseType"]
        for control in [sort, scope] {
            XCTAssertTrue(control.isHittable)
            XCTAssertGreaterThanOrEqual(control.frame.width, 44)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44)
        }
        XCTAssertFalse(app.buttons["detailList.categories"].exists)
        XCTAssertEqual(sort.value as? String, "Newest first")

        for title in ["Oldest first", "Name A–Z", "Name Z–A",
                      "Lowest amount first", "Highest amount first", "Newest first"] {
            sort.tap()
            app.buttons[title].tap()
            XCTAssertEqual(sort.value as? String, title)
        }

        let scrollStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
        let scrollEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.40))
        scrollStart.press(forDuration: 0.05, thenDragTo: scrollEnd)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Floating expense sort with euros at largest accessibility text size"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testExpenseEditsRefreshWithoutResettingScopeOrDates() {
        let app = launchCategories()
        openDining(in: app)
        chooseQuickRange("Current Year", in: app)
        let datesBeforeEdit = app.buttons["dateRange.editor"].value as? String
        let scope = app.buttons["detailList.expenseType"]
        scope.tap()
        app.buttons["Variable"].tap()
        let lunch = row("categoryDetail.expense.\(lunchID)", in: app)
        reveal(lunch, in: app)
        lunch.tap()
        XCTAssertTrue(app.navigationBars["Edit Expense"].waitForExistence(timeout: 5))
        let description = app.textFields["Description"]
        description.tap()
        let existing = description.value as? String ?? ""
        description.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        description.typeText("Edited Ruby Lunch")
        app.navigationBars["Edit Expense"].buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Edit Expense"].waitForNonExistence(timeout: 5))
        let afterEdit = XCTAttachment(screenshot: app.screenshot())
        afterEdit.name = "Category detail after editing preserves variable scope"
        afterEdit.lifetime = .keepAlways
        add(afterEdit)
        XCTAssertEqual(scope.value as? String, "Variable")
        XCTAssertEqual(app.buttons["dateRange.editor"].value as? String, datesBeforeEdit)
        XCTAssertTrue(lunch.waitForExistence(timeout: 5))
        XCTAssertTrue(lunch.label.contains("Edited Ruby Lunch"))

        lunch.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(app.alerts["Delete Expense?"].waitForExistence(timeout: 3))
        app.alerts["Delete Expense?"].buttons["Delete"].tap()
        XCTAssertTrue(lunch.waitForNonExistence(timeout: 5))
    }

    func testCategorySwipesAndArchivedHistoryRemainAvailable() {
        let app = launchCategories()
        let dining = row("categories.row.\(diningID)", in: app)
        reveal(dining, in: app)
        dining.swipeRight()
        app.buttons["Edit"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Edit Category"].waitForExistence(timeout: 5))
        app.navigationBars["Edit Category"].buttons["Cancel"].tap()
        dining.swipeRight()
        app.buttons["Archive"].firstMatch.tap()
        reveal(dining, in: app)
        dining.tap()
        XCTAssertTrue(app.navigationBars["Detail Dining"].waitForExistence(timeout: 5))
        app.navigationBars["Detail Dining"].buttons["Categories"].tap()
        reveal(dining, in: app)
        dining.swipeRight()
        app.buttons["Unarchive"].firstMatch.tap()

        let archived = row("categories.row.\(archivedID)", in: app)
        reveal(archived, in: app)
        archived.tap()
        XCTAssertTrue(app.navigationBars["Archived Dining"].waitForExistence(timeout: 5))
        let supper = row("categoryDetail.expense.\(supperID)", in: app)
        reveal(supper, in: app)
        XCTAssertTrue(supper.label.contains("Archived Supper"))
        app.navigationBars["Archived Dining"].buttons["Categories"].tap()

        let other = row("categories.row.\(otherID)", in: app)
        reveal(other, in: app)
        other.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(app.alerts["Delete?"].waitForExistence(timeout: 3))
        app.alerts["Delete?"].buttons["Cancel"].tap()
        XCTAssertTrue(other.exists)
    }
}
