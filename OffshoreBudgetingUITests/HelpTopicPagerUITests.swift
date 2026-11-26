import XCTest

@MainActor
final class HelpTopicPagerUITests: XCTestCase {
    func testExplanationRemainsReadableWhenSelectingScreenshotsAndClosingFullscreen() throws {
        let app = try launchHelp()
        openTopic("Customization", in: "Home", app: app)

        let explanation = app.staticTexts["helpSectionBody.home-customization-edit-home"]
        XCTAssertTrue(explanation.waitForExistence(timeout: 5))
        let fullExplanation = explanation.label
        XCTAssertTrue(fullExplanation.hasPrefix("Home customization lets you decide"))
        XCTAssertTrue(fullExplanation.hasSuffix("A layout that matches your routine helps you catch problems earlier."))

        let firstImage = app.buttons["helpMedia.home-customization-edit-home-1"]
        let secondImage = app.buttons["helpMedia.home-customization-edit-home-2"]
        reveal(secondImage, app: app)
        XCTAssertLessThan(explanation.frame.minY, firstImage.frame.minY)
        secondImage.tap()

        let caption = app.staticTexts["helpMediaCaption.home-customization-edit-home"]
        XCTAssertTrue(caption.label.hasPrefix("This step shows you how to reorder widgets"))
        XCTAssertEqual(explanation.label, fullExplanation)

        secondImage.tap()
        let fullscreenCaption = app.staticTexts["Drag widgets into the order that supports your fastest daily review."]
        XCTAssertTrue(fullscreenCaption.waitForExistence(timeout: 5))
        app.buttons["Close"].tap()
        XCTAssertTrue(secondImage.waitForExistence(timeout: 5))
        XCTAssertEqual(explanation.label, fullExplanation)

        for _ in 0..<6 where !explanation.isHittable {
            app.swipeDown()
        }
        XCTAssertTrue(explanation.isHittable)
        attachScreenshot("Help explanation and screenshots")
    }

    func testSearchOpensMatchingSectionAndPagerReturnsToTop() throws {
        let app = try launchHelp()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Filter Expenses")
        app.keyboards.buttons["Search"].tap()

        let result = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Budget Details")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        reveal(result, app: app)
        result.tap()
        let openTopic = app.buttons["helpOpenTopic.budgets-budget-details"]
        XCTAssertTrue(openTopic.waitForExistence(timeout: 5))
        reveal(openTopic, app: app)
        openTopic.tap()

        XCTAssertTrue(app.navigationBars["Budget Details"].waitForExistence(timeout: 5))
        let matchedHeading = app.staticTexts["helpSectionHeading.budgets-details-filter-expenses"]
        XCTAssertTrue(matchedHeading.waitForExistence(timeout: 5))
        XCTAssertTrue(matchedHeading.isHittable)
        XCTAssertFalse(app.staticTexts["helpSectionHeading.budgets-details-add-expense"].isHittable)
        XCTAssertTrue(app.staticTexts["helpSectionBody.budgets-details-filter-expenses"].label.hasPrefix("Filtering lets you isolate"))
        attachScreenshot("Help search matching section")

        app.buttons["helpPagerNext"].tap()
        XCTAssertTrue(app.navigationBars["Category Goals"].waitForExistence(timeout: 5))
        app.buttons["helpPagerBack"].tap()
        XCTAssertTrue(app.navigationBars["Budget Details"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["helpSectionHeading.budgets-details-add-expense"].isHittable)
    }

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

    private func launchHelp() throws -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
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
        let help = app.buttons["settings_help"].firstMatch
        XCTAssertTrue(help.waitForExistence(timeout: 5))
        help.tap()
        return app
    }

    private func openTopic(_ title: String, in destination: String, app: XCUIApplication) {
        for label in [destination, title] {
            let row = app.collectionViews.buttons[label].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.tap()
        }
    }

    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<6 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
}
