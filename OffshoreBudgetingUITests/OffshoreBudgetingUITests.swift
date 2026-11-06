//
//  OffshoreBudgetingUITests.swift
//  OffshoreBudgetingUITests
//
//  Created by Michael Brown on 1/20/26.
//

import XCTest

final class OffshoreBudgetingUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testOnboarding_iCloudExistingWorkspace_canSelectAndAdvance() throws {
        let app = makeAppForUITesting(
            scenario: "-uiTestScenarioICloudHasExistingWorkspace"
        )
        app.launch()

        app.buttons["Get Started"].tap()
        app.buttons["iCloud"].tap()

        let existingWorkspace = app.buttons["Existing iCloud Workspace"].firstMatch
        XCTAssertTrue(existingWorkspace.waitForExistence(timeout: 5))
        existingWorkspace.tap()

        app.buttons["Next"].tap()

        let nextStepTitle = privacyStepTitle(in: app, usesICloud: true)
        XCTAssertTrue(nextStepTitle.waitForExistence(timeout: 5))
    }

    @MainActor
    func testOnboarding_reselectingICloud_preservesWorkspaceAndCanAdvance() throws {
        let app = makeAppForUITesting(scenario: "-uiTestScenarioICloudHasExistingWorkspace")
        app.launch()

        app.buttons["Get Started"].tap()
        app.buttons["iCloud"].tap()
        XCTAssertTrue(app.buttons["Existing iCloud Workspace"].firstMatch.waitForExistence(timeout: 5))

        app.buttons["Add Workspace"].tap()
        let nameField = app.textFields["Name"].firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Retained Workspace")
        app.buttons["Save"].tap()

        let retainedWorkspace = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Retained Workspace")
        ).firstMatch
        XCTAssertTrue(retainedWorkspace.waitForExistence(timeout: 5))

        app.buttons["Back"].tap()
        XCTAssertTrue(app.staticTexts["onboarding.storageHeading"].waitForExistence(timeout: 5))
        app.buttons["iCloud"].tap()

        XCTAssertTrue(retainedWorkspace.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Existing iCloud Workspace"].firstMatch.exists)
        app.buttons["Next"].tap()
        XCTAssertTrue(privacyStepTitle(in: app, usesICloud: true).waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testOnboarding_iCloudTimeout_thenAddWorkspace_canAdvance() throws {
        let app = makeAppForUITesting(
            scenario: "-uiTestScenarioICloudEmpty"
        )
        app.launch()

        app.buttons["Get Started"].tap()
        app.buttons["iCloud"].tap()

        let slowLoadingTitle = app.staticTexts["Still Checking iCloud"].firstMatch
        XCTAssertTrue(slowLoadingTitle.waitForExistence(timeout: 10))

        app.buttons["Add Workspace"].tap()

        let nameField = app.textFields["Name"].firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Personal")

        app.buttons["Save"].tap()

        let createdWorkspace = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Personal")).firstMatch
        XCTAssertTrue(createdWorkspace.waitForExistence(timeout: 5))

        app.buttons["Next"].tap()

        let nextStepTitle = privacyStepTitle(in: app, usesICloud: true)
        XCTAssertTrue(nextStepTitle.waitForExistence(timeout: 5))
    }

    @MainActor
    func testOnboarding_iCloudDelayedWorkspace_keepsLoadingUntilWorkspaceArrives() throws {
        let app = makeAppForUITesting(
            scenario: "-uiTestScenarioICloudDelayedWorkspace"
        )
        app.launch()

        app.buttons["Get Started"].tap()
        app.buttons["iCloud"].tap()

        let loadingTitle = app.staticTexts["Setting Up iCloud Sync"].firstMatch
        XCTAssertTrue(loadingTitle.waitForExistence(timeout: 3))

        let emptyStateTitle = app.staticTexts["No iCloud Workspaces Found"].firstMatch
        XCTAssertFalse(emptyStateTitle.exists)

        let delayedWorkspace = app.buttons["Delayed iCloud Workspace"].firstMatch
        XCTAssertTrue(delayedWorkspace.waitForExistence(timeout: 15))
        XCTAssertFalse(emptyStateTitle.exists)
        XCTAssertFalse(app.staticTexts["Personal"].exists)
        XCTAssertFalse(app.staticTexts["Work"].exists)
    }

    @MainActor
    func testOnboarding_localFlow_doesNotCreateStarterBudget() throws {
        let app = makeAppForUITesting(
            scenario: "-uiTestScenarioICloudEmpty"
        )
        app.launch()

        app.buttons["Get Started"].tap()
        let onDeviceButton = app.buttons["On Device"].firstMatch
        XCTAssertTrue(onDeviceButton.waitForExistence(timeout: 5))
        onDeviceButton.tap()

        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Personal")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Work")).firstMatch.exists)
        XCTAssertFalse(app.buttons["Start with Personal"].exists)
        XCTAssertFalse(app.staticTexts["No Workspaces Yet"].exists)

        app.buttons["Next"].tap()
        XCTAssertTrue(privacyStepTitle(in: app, usesICloud: false).waitForExistence(timeout: 5))

        app.buttons["Next"].tap()
        XCTAssertTrue(onboardingStepTitle("Categories", in: app).waitForExistence(timeout: 5))

        app.buttons["Next"].tap()
        XCTAssertTrue(onboardingStepTitle("Cards", in: app).waitForExistence(timeout: 5))
        app.buttons["Next"].tap()
        XCTAssertTrue(app.alerts["Card Required"].waitForExistence(timeout: 5))
        app.alerts["Card Required"].buttons["OK"].tap()

        app.buttons["Add Card"].tap()

        let cardNameField = app.textFields["Apple Card"].firstMatch
        XCTAssertTrue(cardNameField.waitForExistence(timeout: 5))
        cardNameField.tap()
        cardNameField.typeText("Checking")
        app.buttons["Save"].tap()

        app.buttons["Next"].tap()
        XCTAssertTrue(onboardingStepTitle("Presets", in: app).waitForExistence(timeout: 5))

        XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Back"].tap()
        XCTAssertTrue(onboardingStepTitle("Cards", in: app).waitForExistence(timeout: 5))
        app.buttons["Next"].tap()
        XCTAssertTrue(onboardingStepTitle("Presets", in: app).waitForExistence(timeout: 5))
        app.buttons["Done"].tap()

        let budgetsTab = app.tabBars.buttons["Budgets"].firstMatch
        XCTAssertTrue(budgetsTab.waitForExistence(timeout: 5))
        budgetsTab.tap()

        let emptyBudgetsTitle = app.staticTexts["No Budgets Yet"].firstMatch
        XCTAssertTrue(emptyBudgetsTitle.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["March 2026"].firstMatch.exists)
    }

    // MARK: - Helpers

    @MainActor
    func testOnboarding_storageHeadingAndRealDefaultWorkspaces() throws {
        let app = makeAppForUITesting(scenario: "-uiTestScenarioICloudEmpty")
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["Get Started"].tap()
        let heading = app.staticTexts["onboarding.storageHeading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertEqual(heading.label, "Where should Offshore save your data?")
        let storageScreenshot = XCTAttachment(screenshot: app.screenshot())
        storageScreenshot.name = "Storage heading on small iPhone"
        storageScreenshot.lifetime = .keepAlways
        add(storageScreenshot)
        app.buttons["On Device"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Personal")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Work")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["No Workspaces Yet"].exists)
        XCTAssertFalse(app.buttons["Start with Personal"].exists)
        let workspaceScreenshot = XCTAttachment(screenshot: app.screenshot())
        workspaceScreenshot.name = "Real default workspaces"
        workspaceScreenshot.lifetime = .keepAlways
        add(workspaceScreenshot)
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Work")).firstMatch.tap()
        app.buttons["Next"].tap()
        app.buttons["Back"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Personal")).count, 1)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label != %@", "Work", "Add Workspace")).count, 1)
    }

    private func onboardingStepTitle(_ title: String, in app: XCUIApplication) -> XCUIElement {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            return app.navigationBars[title].firstMatch
        }
        return app.staticTexts[title].firstMatch
    }

    private func privacyStepTitle(in app: XCUIApplication, usesICloud: Bool) -> XCUIElement {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            return app.navigationBars["Privacy"].firstMatch
        }
        let title = usesICloud ? "Privacy, iCloud, and Notifications" : "Privacy and Notifications"
        return app.staticTexts[title].firstMatch
    }

    private func makeAppForUITesting(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting",
            "-uiTestingReset",
            "-uiTestingForceICloudAvailable",
            "-uiTestingUseLocalCloudStore",
            scenario
        ]
        return app
    }
}
