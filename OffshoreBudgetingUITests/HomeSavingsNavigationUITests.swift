import XCTest

@MainActor
final class HomeSavingsNavigationUITests: XCTestCase {
    func testSavingsAccountBackReturnsToOutlookOnHome() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingReset", "-uiTestScenarioBudgetMenus",
            "-tips_seenKeys", "tip.home.v1,tip.cards.v1,tip.income.v1",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 15))
        let outlook = app.buttons["Savings Outlook"].firstMatch
        reveal(outlook, in: app)
        outlook.tap()

        let openSavings = app.buttons["Open Offshore Savings"].firstMatch
        reveal(openSavings, in: app)
        openSavings.tap()
        XCTAssertTrue(app.navigationBars["Savings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add Savings Entry"].exists)
        app.navigationBars["Savings"].buttons.element(boundBy: 0).tap()

        XCTAssertTrue(openSavings.waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Home"].isSelected)
        XCTAssertFalse(app.navigationBars["Savings"].exists)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
}
