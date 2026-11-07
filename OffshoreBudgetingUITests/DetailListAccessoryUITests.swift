import UIKit
import XCTest

@MainActor
final class DetailListAccessoryUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testBudgetControlsStayReachableAndKeepCategorySelectionAcrossMenuChanges() {
        #if !targetEnvironment(macCatalyst)
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        if isPad { XCUIDevice.shared.orientation = .landscapeLeft }
        defer {
            if isPad { XCUIDevice.shared.orientation = .portrait }
        }
        #endif

        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingReset", "-uiTestScenarioBudgetMenus", "-uiTestCategoryDetailHistory",
            "-uiTestDetailListUncategorized",
            "-tips_seenKeys", "tip.home.v1,tip.budgets.v1,tip.budgetdetail.v1",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()

        let phoneBudgets = app.tabBars.buttons["Budgets"]
        let sidebarBudgets = app.staticTexts["Budgets"].firstMatch
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 15))
        if phoneBudgets.exists {
            phoneBudgets.tap()
        } else {
            XCTAssertTrue(sidebarBudgets.waitForExistence(timeout: 5))
            sidebarBudgets.tap()
        }
        let budget = app.staticTexts["Existing Menu Budget"].firstMatch
        XCTAssertTrue(budget.waitForExistence(timeout: 5))
        budget.tap()

        let categories = app.buttons["detailList.categories"]
        XCTAssertTrue(categories.waitForExistence(timeout: 5))
        XCTAssertEqual(categories.value as? String, "No category filter")
        app.swipeUp()
        categories.tap()

        let selectAll = app.buttons["Select All"]
        let deselectAll = app.buttons["Deselect All"]
        XCTAssertTrue(deselectAll.waitForExistence(timeout: 5))
        XCTAssertFalse(selectAll.exists)
        app.buttons["Archived Dining"].tap()
        XCTAssertTrue(selectAll.exists)
        app.buttons["Other Detail Category"].tap()
        XCTAssertTrue(selectAll.exists)
        app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(categories.value as? String, "Bills and Detail Dining")
        XCTAssertTrue(app.staticTexts["Lunch Ruby"].exists)
        XCTAssertFalse(app.staticTexts["Other Category Purchase"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Budget accessory with selected category colors"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let expenseType = app.buttons["detailList.expenseType"]
        expenseType.tap()
        app.buttons["Variable"].tap()
        XCTAssertEqual(expenseType.value as? String, "Variable")

        let sort = app.buttons["detailList.sort"]
        sort.tap()
        app.buttons["Oldest first"].tap()
        XCTAssertEqual(sort.value as? String, "Oldest first")
        XCTAssertEqual(categories.value as? String, "Bills and Detail Dining")

        categories.tap()
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5))
        selectAll.tap()
        XCTAssertTrue(deselectAll.waitForExistence(timeout: 5))
        XCTAssertFalse(selectAll.exists)
        app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue((categories.value as? String)?.contains("Other Detail Category") == true)
        XCTAssertFalse(app.staticTexts["Uncategorized Purchase"].exists)

        categories.tap()
        XCTAssertTrue(deselectAll.waitForExistence(timeout: 5))
        deselectAll.tap()
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5))
        XCTAssertFalse(deselectAll.exists)
        app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(categories.value as? String, "No categories selected")
        XCTAssertTrue(app.staticTexts["No categories selected"].exists)
        XCTAssertFalse(app.staticTexts["Lunch Ruby"].exists)
        XCTAssertFalse(app.staticTexts["Other Category Purchase"].exists)
        XCTAssertFalse(app.staticTexts["Uncategorized Purchase"].exists)
    }

    func testCardAndReconciliationHaveTheirOwnCategoryAndSortControls() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingReset", "-uiTestScenarioBudgetMenus", "-uiTestCategoryDetailHistory",
            "-uiTestDetailListReconciliation", "-tips_seenKeys", "tip.home.v1,tip.cards.v1,tip.carddetail.v1",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 15))
        let accounts = app.tabBars.buttons["Accounts"]
        try XCTSkipUnless(accounts.exists, "This test uses the phone Accounts navigation.")
        accounts.tap()

        app.buttons["accounts.destination.cards"].tap()
        let card = app.staticTexts["Ruby Card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        let categories = app.buttons["detailList.categories"]
        XCTAssertTrue(categories.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["detailList.expenseType"].exists)
        XCTAssertTrue(app.buttons["detailList.sort"].exists)
        categories.tap()
        app.buttons["Deselect All"].tap()
        let dining = app.buttons["Detail Dining"]
        XCTAssertTrue(dining.waitForExistence(timeout: 5))
        dining.tap()
        app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(categories.value as? String, "Detail Dining")

        app.navigationBars["Ruby Card"].buttons["Cards"].tap()
        app.navigationBars["Cards"].buttons["Accounts"].tap()
        app.buttons["accounts.destination.sharedBalances"].tap()
        let account = app.staticTexts["Shared Lunch"].firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        account.tap()
        XCTAssertTrue(categories.waitForExistence(timeout: 5))
        XCTAssertEqual(categories.value as? String, "No category filter")
        XCTAssertFalse(app.buttons["detailList.expenseType"].exists)
        categories.tap()
        app.buttons["Deselect All"].tap()
        XCTAssertTrue(dining.waitForExistence(timeout: 5))
        dining.tap()
        app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(categories.value as? String, "Detail Dining")

        let sort = app.buttons["detailList.sort"]
        sort.tap()
        app.buttons["Highest amount first"].tap()
        XCTAssertEqual(sort.value as? String, "Highest amount first")
    }
}
