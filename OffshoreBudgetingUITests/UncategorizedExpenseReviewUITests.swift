import XCTest

@MainActor
final class UncategorizedExpenseReviewUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func makeApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingReset", "-uiTestScenarioUncategorizedReview",
            "-tips_seenKeys", extraArguments.contains("-uiTestReviewTipsFirst") ? "" : "tip.home.v1,tip.budgets.v1,tip.cards.v1,tip.income.v1",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ] + extraArguments
        return app
    }

    private func returnFromBackground(_ app: XCUIApplication) {
        XCUIDevice.shared.press(.home)
        app.activate()
    }

    private func chooseDining(_ app: XCUIApplication) {
        let category = app.descendants(matching: .any)["expenseReview.category"].firstMatch
        for _ in 0..<4 {
            if category.exists && category.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        category.tap()
        XCTAssertFalse(app.buttons["Archived Review Category"].exists)
        app.buttons["Dining"].firstMatch.tap()
    }

    func testLaterDiscardsSelectionsAndSavePersistsCategory() throws {
        let app = makeApp()
        app.launch()
        XCTAssertTrue(app.navigationBars["Review Expenses"].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Uncategorized Expense Review"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(app.staticTexts["Review Coffee"].exists)
        XCTAssertFalse(app.staticTexts["Foreign Expense"].exists)
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        chooseDining(app)
        XCTAssertTrue(app.buttons["Save"].isEnabled)
        app.buttons["Later"].tap()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Review Expenses"].exists)

        returnFromBackground(app)
        XCTAssertTrue(app.navigationBars["Review Expenses"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        chooseDining(app)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))

        returnFromBackground(app)
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Review Expenses"].exists)
    }

    func testEnablingInSettingsWaitsForNextForeground() throws {
        let app = makeApp(extraArguments: ["-uiTestReviewDisabled"])
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Review Expenses"].exists)
        app.buttons["Settings"].firstMatch.tap()
        app.buttons["General"].firstMatch.tap()
        let toggle = app.switches["reviewUncategorizedExpensesOnOpen"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1")
        XCTAssertFalse(app.navigationBars["Review Expenses"].exists)
        returnFromBackground(app)
        XCTAssertTrue(app.navigationBars["Review Expenses"].waitForExistence(timeout: 10))
    }

    func testSwipeDismissalDiscardsSelections() throws {
        let app = makeApp()
        app.launch()
        let review = app.navigationBars["Review Expenses"]
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        chooseDining(app)
        let dragStart = review.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let dragEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        dragStart.press(forDuration: 0.1, thenDragTo: dragEnd)
        XCTAssertTrue(review.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))
        returnFromBackground(app)
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Save"].isEnabled)
    }

    func testVisibleReviewDoesNotRepeatAfterReturning() throws {
        let app = makeApp()
        app.launch()
        XCTAssertTrue(app.navigationBars["Review Expenses"].waitForExistence(timeout: 10))
        returnFromBackground(app)
        XCTAssertTrue(app.navigationBars["Review Expenses"].waitForExistence(timeout: 5))
        app.buttons["Later"].tap()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Review Expenses"].exists)
    }

    func testLaunchTipDefersReview() throws {
        let app = makeApp(extraArguments: ["-uiTestReviewTipsFirst"])
        app.launch()
        let proceed = app.buttons["Continue"].firstMatch
        XCTAssertTrue(proceed.waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Review Expenses"].exists)
        proceed.tap()
        XCTAssertTrue(app.navigationBars["Review Expenses"].waitForExistence(timeout: 10))
    }

    func testExistingAlertDefersReviewUntilDismissed() throws {
        let app = makeApp()
        app.launch()
        XCTAssertTrue(app.navigationBars["Review Expenses"].waitForExistence(timeout: 10))
        app.buttons["Later"].tap()
        app.buttons["Settings"].firstMatch.tap()
        app.buttons["General"].firstMatch.tap()
        app.swipeUp()
        let maintenance = app.buttons["Maintenance"].firstMatch
        XCTAssertTrue(maintenance.waitForExistence(timeout: 5))
        maintenance.tap()
        app.buttons["Reset Tips & Hints"].firstMatch.tap()
        let alert = app.alerts["Reset Tips & Hints?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        returnFromBackground(app)
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Review Expenses"].exists)
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Review Expenses"].waitForExistence(timeout: 10))
    }

    func testReviewSupportsAccessibilityTextSize() throws {
        let app = makeApp(extraArguments: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        app.launch()
        XCTAssertTrue(app.navigationBars["Review Expenses"].waitForExistence(timeout: 10))
        chooseDining(app)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Review at Accessibility Text Size"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        // Check the scrollable content and actions at AX5. The simulator's
        // automatic font audit flags the standard navigation-bar text sizing.
        XCTAssertTrue(app.buttons["Later"].isHittable)
        XCTAssertTrue(app.buttons["Save"].isHittable)
    }

    func testExistingFormDefersReviewUntilDismissed() throws {
        let app = makeApp()
        app.launch()
        XCTAssertTrue(app.navigationBars["Review Expenses"].waitForExistence(timeout: 10))
        app.buttons["Later"].tap()
        app.buttons["Accounts"].firstMatch.tap()
        let add = app.buttons["Add Card"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(app.navigationBars["Add Card"].waitForExistence(timeout: 5))
        returnFromBackground(app)
        XCTAssertTrue(app.navigationBars["Add Card"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Review Expenses"].exists)
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Review Expenses"].waitForExistence(timeout: 10))
    }
}
