import XCTest

@MainActor
final class HelpTopicPagerUITests: XCTestCase {
    func testPagerStaysSeparateFromTabsAndKeepsTopicAcrossRotation() throws {
        continueAfterFailure = false
        let device = XCUIDevice.shared
        device.orientation = .portrait
        defer { device.orientation = .portrait }

        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingReset", "-uiTestScenarioWorkspaceProgress",
            "-tips_seenKeys", "tip.home.v1,tip.budgets.v1,tip.cards.v1,tip.income.v1,tip.budgetdetail.v1",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()

        let settingsTab = app.tabBars.buttons["Settings"]
        try XCTSkipUnless(settingsTab.waitForExistence(timeout: 10), "This test uses the iPhone tab layout.")
        settingsTab.tap()
        for title in ["settings_help", "Introduction", "Planned Expenses"] {
            let row = app.buttons[title].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.tap()
        }

        let back = app.buttons["helpPagerBack"]
        let next = app.buttons["helpPagerNext"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertTrue(next.isHittable)
        XCTAssertFalse(app.tabBars.buttons["helpPagerNext"].exists)
        attachScreenshot("Help portrait footer")

        device.orientation = .landscapeLeft
        XCTAssertTrue(app.navigationBars["Planned Expenses"].exists)
        XCTAssertTrue(settingsTab.exists)
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertTrue(back.isHittable)
        XCTAssertFalse(app.tabBars.buttons["helpPagerNext"].exists)
        attachScreenshot("Help landscape footer")
        next.tap()
        XCTAssertTrue(app.navigationBars["Variable Expenses"].waitForExistence(timeout: 5))

        device.orientation = .portrait
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Variable Expenses"].exists)
        back.tap()
        XCTAssertTrue(app.navigationBars["Planned Expenses"].waitForExistence(timeout: 5))
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
