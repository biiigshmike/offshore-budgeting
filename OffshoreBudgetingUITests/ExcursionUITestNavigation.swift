import XCTest

@MainActor
enum ExcursionUITestNavigation {
    static func openSettings(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons["Settings"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15), "Expected the main tab interface before opening Settings")
        // Launch restoration can replace the root immediately after tabs appear.
        // Retry the navigation action, never scroll a different screen.
        for _ in 0..<3 {
            tab.tap()
            if app.navigationBars["Settings"].waitForExistence(timeout: 3) { return }
            if tab.isSelected {
                let back = app.navigationBars.buttons["Settings"]
                if back.exists && back.isHittable { back.tap() }
                if app.navigationBars["Settings"].waitForExistence(timeout: 3) { return }
            }
        }
        XCTFail("Navigation did not reach Settings: \(app.debugDescription.prefix(2500))")
    }

    static func openExcursion(_ app: XCUIApplication) {
        if app.navigationBars["Excursion Mode"].exists { return }
        openSettings(app)
        let row = app.buttons["settings_excursionMode"]
        reveal(row, in: app)
        row.tap()
        XCTAssertTrue(app.navigationBars["Excursion Mode"].waitForExistence(timeout: 5))
    }

    static func allowNotificationsAndOpenExcursion(_ app: XCUIApplication) -> XCUIApplication {
        openSettings(app)
        let notifications = app.buttons["settings_notifications"]
        reveal(notifications, in: app)
        notifications.tap()
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 5))
        let setup = app.buttons["Set Up Reminders"]
        if setup.waitForExistence(timeout: 2) {
            reveal(setup, in: app)
            setup.tap()
            XCTAssertTrue(app.buttons["reminderSetupContinue"].waitForExistence(timeout: 5))
            app.buttons["reminderSetupContinue"].tap()
        } else {
            // Existing choices hide the setup button. Enabling the master switch
            // uses the normal permission flow without discarding those choices.
            let master = app.switches["scheduledRemindersEnabled"]
            reveal(master, in: app)
            if master.value as? String != "1" {
                master.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            }
        }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Reminders are on"].waitForExistence(timeout: 5),
                      "Notification permission/setup did not complete; inspect the Notifications screen")
        // Excursion uses its own notifications. Leave daily/income/preset
        // scheduling off so unrelated reminders cannot interrupt route assertions.
        let master = app.switches["scheduledRemindersEnabled"]
        reveal(master, in: app)
        if master.value as? String == "1" {
            master.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        app.navigationBars["Notifications"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        openExcursion(app)
        return springboard
    }

    static func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5), "Expected a settings list before scrolling")
        for direction in [true, false] {
            for _ in 0..<10 {
                if element.exists && element.isHittable { return }
                if direction { list.swipeUp() } else { list.swipeDown() }
            }
        }
        XCTFail("Control not reachable on the current screen: \(element)\n\(app.debugDescription.prefix(2500))")
    }
}
