import XCTest

@MainActor
final class ReminderSetupUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func makeApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingReset", "-uiTestScenarioWorkspaceProgress",
            "-tips_seenKeys", "tip.home.v1,tip.budgets.v1,tip.cards.v1,tip.income.v1,tip.budgetdetail.v1",
            "-tips_resetToken", "0", "-tips_seen_lastResetToken", "0",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ] + extraArguments
        return app
    }

    private func openNotifications(_ app: XCUIApplication) {
        let settings = app.tabBars.buttons["Settings"]
        if settings.waitForExistence(timeout: 5) {
            settings.tap()
        } else {
            let row = app.staticTexts["Settings"].firstMatch
            if !row.exists || !row.isHittable {
                let sidebar = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "sidebar")).firstMatch
                if sidebar.exists { sidebar.tap() }
            }
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.tap()
        }
        let notifications = app.buttons["Notifications"].firstMatch
        for _ in 0..<5 {
            if notifications.exists && notifications.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(notifications.waitForExistence(timeout: 5))
        notifications.tap()
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 5))
    }

    private func assertChoices(_ value: String, app: XCUIApplication) {
        for id in ["reminderSetupDaily", "reminderSetupIncome", "reminderSetupPreset"] {
            let toggle = app.switches[id]
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            XCTAssertEqual(toggle.value as? String, value)
        }
    }

    private func tapSwitch(_ toggle: XCUIElement) {
        // SwiftUI exposes the full row as the switch's accessibility frame. Tap its control.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    }

    private func turnOff(_ toggle: XCUIElement) {
        tapSwitch(toggle)
        expectation(for: NSPredicate(format: "value == %@", "0"), evaluatedWith: toggle)
        waitForExpectations(timeout: 3)
    }

    func testAllowEnablesSelectedRemindersAndSurvivesRelaunch() {
        let app = makeApp()
        app.launch()
        openNotifications(app)
        app.buttons["Set Up Reminders"].tap()
        assertChoices("1", app: app)
        app.buttons["reminderSetupContinue"].tap()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["scheduledRemindersEnabled"].value as? String, "1")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "Reminders are on"
        )).firstMatch.exists)
        app.terminate()
        app.launchArguments.removeAll { $0 == "-uiTestingReset" }
        app.launchArguments.append("-uiTestPreserveScenarioData")
        app.launch()
        openNotifications(app)
        XCTAssertEqual(app.switches["scheduledRemindersEnabled"].value as? String, "1")
    }

    func testMasterOpensSetupAndCancelDoesNotSaveDraft() {
        let app = makeApp()
        app.launch()
        openNotifications(app)
        let master = app.switches["scheduledRemindersEnabled"]
        XCTAssertEqual(master.value as? String, "0")
        tapSwitch(master)
        XCTAssertTrue(app.navigationBars["Set Up Reminders"].waitForExistence(timeout: 5))
        assertChoices("1", app: app)
        turnOff(app.switches["reminderSetupDaily"])
        app.buttons["Cancel"].tap()
        XCTAssertTrue(master.waitForExistence(timeout: 5))
        XCTAssertEqual(master.value as? String, "0")
        app.buttons["Set Up Reminders"].tap()
        assertChoices("1", app: app)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Reminder setup with explicit default choices"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAllOffSavesWithoutPermissionAndSurvivesRelaunch() {
        let app = makeApp()
        app.launch()
        openNotifications(app)
        app.buttons["Set Up Reminders"].tap()
        assertChoices("1", app: app)
        for id in ["reminderSetupDaily", "reminderSetupIncome", "reminderSetupPreset"] {
            turnOff(app.switches[id])
        }
        app.buttons["reminderSetupContinue"].tap()
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["scheduledRemindersEnabled"].value as? String, "0")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "Choose which reminders you’d like to receive."
        )).firstMatch.exists)
        XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists)
        app.terminate()
        app.launchArguments.removeAll { $0 == "-uiTestingReset" }
        app.launchArguments.append("-uiTestPreserveScenarioData")
        app.launch()
        openNotifications(app)
        app.buttons["Set Up Reminders"].tap()
        assertChoices("0", app: app)
    }

    func testOnboardingSetupIsOptionalAtAccessibilityTextSize() {
        let app = makeApp(extraArguments: [
            "-uiTestProgressFinishOnboarding",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        app.launch()
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 10))
        for _ in 0..<3 { app.buttons["Back"].tap() }
        let setup = app.buttons["Set Up Reminders"]
        for _ in 0..<6 {
            if setup.exists && setup.isHittable { break }
            let form = app.collectionViews.firstMatch
            if form.exists { form.swipeUp() } else { app.swipeUp() }
        }
        XCTAssertTrue(setup.waitForExistence(timeout: 5), String(app.debugDescription.prefix(20000)))
        setup.tap()
        XCTAssertTrue(app.buttons["reminderSetupContinue"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["reminderSetupContinue"].isHittable)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Reminder setup at accessibility text size"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 5))
        app.buttons["Next"].tap()
        let categoriesTitle: XCUIElement
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            categoriesTitle = app.navigationBars["Categories"].firstMatch
        } else {
            categoriesTitle = app.staticTexts["Categories"].firstMatch
        }
        XCTAssertTrue(categoriesTitle.waitForExistence(timeout: 5))
    }
}
