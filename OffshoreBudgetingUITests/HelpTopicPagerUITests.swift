import XCTest

@MainActor
final class HelpTopicPagerUITests: XCTestCase {
    func testRotationMovesPagerOutOfTabBarWithoutLosingTopic() throws {
        guard #available(iOS 26.1, *) else {
            throw XCTSkip("The tab accessory requires iOS 26.1.")
        }
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

        let accessory = app.descendants(matching: .any).matching(identifier: "helpTabAccessory").firstMatch
        XCTAssertTrue(accessory.waitForExistence(timeout: 5))
        attachScreenshot("Help portrait accessory")

        device.orientation = .landscapeLeft
        XCTAssertTrue(accessory.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Planned Expenses"].exists)
        XCTAssertTrue(settingsTab.exists)
        let next = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Next")).firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        attachScreenshot("Help landscape footer")
        next.tap()
        XCTAssertTrue(app.navigationBars["Variable Expenses"].waitForExistence(timeout: 5))

        device.orientation = .portrait
        XCTAssertTrue(accessory.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Variable Expenses"].exists)
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
