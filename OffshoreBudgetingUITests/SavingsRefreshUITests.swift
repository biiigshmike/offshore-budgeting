import XCTest

@MainActor
final class SavingsRefreshUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func showBalance(_ app: XCUIApplication) -> XCUIElement {
        let balance = app.staticTexts["savings.runningTotal"]
        for _ in 0..<7 {
            if balance.exists && balance.isHittable { return balance }
            app.swipeDown()
        }
        return balance
    }

    private func assertBalance(_ amount: String, in app: XCUIApplication) {
        let balance = showBalance(app)
        XCTAssertTrue(balance.waitForExistence(timeout: 5))
        let updated = NSPredicate(format: "label CONTAINS %@", amount)
        expectation(for: updated, evaluatedWith: balance)
        waitForExpectations(timeout: 5)
    }

    private func addEntry(_ amount: String, note: String, setAside: Bool = false, in app: XCUIApplication) {
        app.buttons["Add Savings Entry"].tap()
        XCTAssertTrue(app.navigationBars["Add Savings Entry"].waitForExistence(timeout: 5))
        app.textFields["Amount"].tap()
        app.textFields["Amount"].typeText(amount)
        app.textFields["Note"].tap()
        app.textFields["Note"].typeText(note)
        if setAside {
            let toggle = app.switches["Set Aside as Savings"]
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            XCTAssertEqual(toggle.value as? String, "1")
        }
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Offshore Savings"].waitForExistence(timeout: 5))
    }

    private func ledgerRow(_ note: String, in app: XCUIApplication) -> XCUIElement {
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", note)).firstMatch
        for _ in 0..<7 {
            if row.exists && row.isHittable { break }
            app.swipeUp()
        }
        return row
    }

    func testRunningTotalUpdatesAfterAddEditDeleteWithoutRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingReset", "-uiTestScenarioBudgetMenus",
            "-tips_seenKeys", "tip.home.v1,tip.budgets.v1,tip.cards.v1,tip.income.v1",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Accounts"].tap()
        app.buttons["accounts.destination.savings"].tap()
        XCTAssertTrue(app.navigationBars["Offshore Savings"].waitForExistence(timeout: 5))
        assertBalance("0.00", in: app)
        XCTAssertFalse(app.buttons["Refresh Savings"].exists)
        XCTAssertFalse(app.staticTexts["Offshore Savings is up to date."].exists)
        let guide = app.buttons["Savings guide"]
        for _ in 0..<4 {
            if guide.exists && guide.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(guide.isHittable)
        let overview = XCTAttachment(screenshot: app.screenshot())
        overview.name = "Savings guide and compact phone title"
        overview.lifetime = .keepAlways
        add(overview)

        addEntry("100", note: "Live balance entry", in: app)
        assertBalance("100.00", in: app)

        let entry = ledgerRow("Live balance entry", in: app)
        XCTAssertTrue(entry.exists)
        entry.tap()
        XCTAssertTrue(app.navigationBars["Edit Savings Entry"].waitForExistence(timeout: 5))
        let amount = app.textFields["Amount"]
        amount.tap()
        let currentText = amount.value as? String ?? ""
        amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentText.count) + "60")
        app.buttons["Save"].tap()
        assertBalance("60.00", in: app)

        addEntry("10", note: "Reserved balance entry", setAside: true, in: app)
        assertBalance("50.00", in: app)

        let reserved = ledgerRow("Reserved balance entry", in: app)
        XCTAssertTrue(reserved.exists)
        reserved.tap()
        XCTAssertTrue(app.navigationBars["Edit Savings Entry"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["Set Aside as Savings"].value as? String, "1")
        app.buttons["Save"].tap()
        assertBalance("50.00", in: app)

        ledgerRow("Reserved balance entry", in: app).swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        if app.alerts["Delete Entry?"].waitForExistence(timeout: 2) {
            app.alerts["Delete Entry?"].buttons["Delete"].tap()
        }
        assertBalance("60.00", in: app)
    }
}
