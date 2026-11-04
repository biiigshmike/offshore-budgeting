import XCTest

@MainActor
final class ExcursionLocationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testStartAutomaticallyRequestsAlwaysAndKeepingWhileUsingStartsLimitedMode() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingReset", "-uiTestScenarioWorkspaceProgress",
            "-tips_seenKeys", "tip.home.v1,tip.budgets.v1,tip.cards.v1,tip.income.v1,tip.budgetdetail.v1",
            "-tips_resetToken", "0", "-tips_seen_lastResetToken", "0",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Settings"].tap()
        let notifications = app.buttons["Notifications"].firstMatch
        reveal(notifications, app: app)
        notifications.tap()
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 5))

        // Notification consent is a pre-existing prerequisite for Excursion Mode.
        app.buttons["Set Up Reminders"].tap()
        app.buttons["reminderSetupContinue"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowNotifications = springboard.alerts.buttons["Allow"]
        if allowNotifications.waitForExistence(timeout: 5) { allowNotifications.tap() }
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 5))

        let start = app.buttons["Start Excursion Mode"]
        reveal(start, app: app)
        start.coordinate(withNormalizedOffset: CGVector(dx: 0.23, dy: 0.5)).tap()
        let duration = app.descendants(matching: .any)["1 hour"].firstMatch
        XCTAssertTrue(duration.waitForExistence(timeout: 5))
        duration.tap()
        let setup = app.alerts["Get nearby reminders while you’re out"]
        XCTAssertTrue(setup.waitForExistence(timeout: 5))
        setup.buttons["Cancel"].tap()
        XCTAssertTrue(start.exists)
        XCTAssertFalse(springboard.alerts.buttons["Allow While Using App"].exists)

        start.coordinate(withNormalizedOffset: CGVector(dx: 0.23, dy: 0.5)).tap()
        duration.tap()
        setup.buttons["Continue"].tap()
        let whileUsing = springboard.alerts.buttons["Allow While Using App"]
        XCTAssertTrue(whileUsing.waitForExistence(timeout: 5))
        whileUsing.tap()
        let keepWhileUsing = springboard.alerts.buttons["Keep Only While Using"]
        XCTAssertTrue(keepWhileUsing.waitForExistence(timeout: 8))
        keepWhileUsing.tap()

        let stop = app.buttons["Stop Excursion Mode"]
        reveal(stop, app: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "Works while Offshore is open."
        )).firstMatch.exists)

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        reveal(stop, app: app)
        stop.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
    }

    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            let form = app.collectionViews.firstMatch
            if form.exists { form.swipeUp() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }
}
