import XCTest

@MainActor
final class ExcursionLocationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testStartAutomaticallyRequestsAlwaysAndKeepingWhileUsingStartsLimitedMode() {
        let (app, springboard) = openExcursionWithNotificationConsent()

        let status = app.staticTexts["excursionStatus"]
        XCTAssertEqual(status.label, "Inactive")
        let start = app.buttons["Start Excursion Mode"]
        reveal(start, app: app)
        let durations = app.segmentedControls.firstMatch
        XCTAssertTrue(durations.buttons["1 hour"].isSelected)
        let duration = durations.buttons["2 hours"]
        duration.tap()
        XCTAssertTrue(duration.isSelected)
        start.tap()
        let setup = app.alerts["Get nearby reminders while you’re out"]
        XCTAssertTrue(setup.waitForExistence(timeout: 5))
        setup.buttons["Cancel"].tap()
        XCTAssertTrue(start.exists)
        XCTAssertFalse(springboard.alerts.buttons["Allow While Using App"].exists)

        start.tap()
        setup.buttons["Continue"].tap()
        let whileUsing = springboard.alerts.buttons["Allow While Using App"]
        XCTAssertTrue(whileUsing.waitForExistence(timeout: 5))
        whileUsing.tap()
        let keepWhileUsing = springboard.alerts.buttons["Keep Only While Using"]
        XCTAssertTrue(keepWhileUsing.waitForExistence(timeout: 8))
        keepWhileUsing.tap()

        let stop = app.buttons["Stop Excursion Mode"]
        XCTAssertTrue(stop.waitForExistence(timeout: 8))
        XCTAssertEqual(status.label, "Active")
        XCTAssertFalse(start.exists)
        reveal(stop, app: app)
        let locationStatus = app.staticTexts["excursionLocationStatus"]
        reveal(locationStatus, app: app)
        XCTAssertEqual(locationStatus.label, "Works while Offshore is open.")

        #if os(macOS) || targetEnvironment(macCatalyst)
        XCUIApplication(bundleIdentifier: "com.apple.finder").activate()
        #else
        XCUIDevice.shared.press(.home)
        #endif
        app.activate()
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        reveal(stop, app: app)
        stop.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, "Inactive")
    }

    #if DEBUG
    func testBackgroundReminderFooterAndSessionExpiry() {
        let (app, springboard) = openExcursionWithNotificationConsent()
        let start = app.buttons["Start Excursion Mode"]
        reveal(start, app: app)
        app.segmentedControls.firstMatch.buttons["1 minute"].tap()
        start.tap()

        app.alerts["Get nearby reminders while you’re out"].buttons["Continue"].tap()
        let whileUsing = springboard.alerts.buttons["Allow While Using App"]
        XCTAssertTrue(whileUsing.waitForExistence(timeout: 5))
        whileUsing.tap()
        let always = springboard.alerts.buttons["Change to Always Allow"]
        XCTAssertTrue(always.waitForExistence(timeout: 8))
        always.tap()

        XCTAssertTrue(app.buttons["Stop Excursion Mode"].waitForExistence(timeout: 8))
        let locationStatus = app.staticTexts["excursionLocationStatus"]
        reveal(locationStatus, app: app)
        XCTAssertEqual(locationStatus.label, "Nearby reminders can work with Offshore closed.")

        XCTAssertTrue(start.waitForExistence(timeout: 70))
        XCTAssertEqual(app.staticTexts["excursionStatus"].label, "Inactive")
    }
    #endif

    private func openExcursionWithNotificationConsent() -> (XCUIApplication, XCUIApplication) {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingReset", "-uiTestScenarioWorkspaceProgress",
            "-tips_seenKeys", "tip.home.v1,tip.budgets.v1,tip.cards.v1,tip.income.v1,tip.budgetdetail.v1",
            "-tips_resetToken", "0", "-tips_seen_lastResetToken", "0",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.resetAuthorizationStatus(for: .location)
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Settings"].tap()
        let notifications = app.buttons["Notifications"].firstMatch
        reveal(notifications, app: app)
        notifications.tap()
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 5))

        // Excursion Mode requires system notification consent.
        app.buttons["Set Up Reminders"].tap()
        app.buttons["reminderSetupContinue"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowNotifications = springboard.alerts.buttons["Allow"]
        if allowNotifications.waitForExistence(timeout: 5) { allowNotifications.tap() }
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 5))
        app.navigationBars["Notifications"].buttons.firstMatch.tap()

        let excursion = app.buttons["settings_excursionMode"]
        reveal(excursion, app: app)
        excursion.tap()
        XCTAssertTrue(app.navigationBars["Excursion Mode"].waitForExistence(timeout: 5))
        return (app, springboard)
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
