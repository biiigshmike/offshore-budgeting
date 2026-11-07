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
        XCTAssertEqual(categories.value as? String, "All categories")
        app.swipeUp()
        XCTAssertTrue(categories.isHittable)
        categories.tap()

        let picker = app.navigationBars["Categories"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let bills = app.staticTexts["Bills"].firstMatch
        let dining = app.staticTexts["Detail Dining"].firstMatch
        if phoneBudgets.exists {
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let selectionColumnX: CGFloat = 40
            let start = origin.withOffset(CGVector(dx: selectionColumnX, dy: bills.frame.midY))
            let end = origin.withOffset(CGVector(dx: selectionColumnX, dy: dining.frame.midY))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.05)
        } else {
            bills.tap()
            dining.tap()
        }
        picker.buttons["Done"].tap()
        XCTAssertTrue(picker.waitForNonExistence(timeout: 5))
        XCTAssertEqual(categories.value as? String, "Bills and Detail Dining")
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
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        let selectAll = app.buttons["Select All"]
        selectAll.tap()
        XCTAssertFalse(selectAll.isEnabled)
        picker.buttons["Done"].tap()
        XCTAssertTrue((categories.value as? String)?.contains("Other Detail Category") == true)

        categories.tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        app.buttons["Deselect All"].tap()
        picker.buttons["Done"].tap()
        XCTAssertEqual(categories.value as? String, "All categories")
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
        let picker = app.navigationBars["Categories"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        app.descendants(matching: .any).matching(identifier: "Detail Dining").firstMatch.tap()
        picker.buttons["Done"].tap()
        XCTAssertTrue(picker.waitForNonExistence(timeout: 5))
        XCTAssertEqual(categories.value as? String, "Detail Dining")

        app.navigationBars["Ruby Card"].buttons["Cards"].tap()
        app.navigationBars["Cards"].buttons["Accounts"].tap()
        app.buttons["accounts.destination.sharedBalances"].tap()
        let account = app.staticTexts["Shared Lunch"].firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        account.tap()
        XCTAssertTrue(categories.waitForExistence(timeout: 5))
        XCTAssertEqual(categories.value as? String, "All categories")
        XCTAssertFalse(app.buttons["detailList.expenseType"].exists)
        categories.tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        app.descendants(matching: .any).matching(identifier: "Detail Dining").firstMatch.tap()
        picker.buttons["Done"].tap()
        XCTAssertTrue(picker.waitForNonExistence(timeout: 5))
        XCTAssertEqual(categories.value as? String, "Detail Dining")

        let sort = app.buttons["detailList.sort"]
        sort.tap()
        app.buttons["Highest amount first"].tap()
        XCTAssertEqual(sort.value as? String, "Highest amount first")
    }
}
