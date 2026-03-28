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

        let nextStepTitle = app.staticTexts["Privacy, iCloud, and Notifications"].firstMatch
        XCTAssertTrue(nextStepTitle.waitForExistence(timeout: 5))
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

        let createdWorkspace = app.buttons["Personal"].firstMatch
        XCTAssertTrue(createdWorkspace.waitForExistence(timeout: 5))

        app.buttons["Next"].tap()

        let nextStepTitle = app.staticTexts["Privacy, iCloud, and Notifications"].firstMatch
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

        let slowLoadingTitle = app.staticTexts["Still Checking iCloud"].firstMatch
        XCTAssertTrue(slowLoadingTitle.waitForExistence(timeout: 10))

        let emptyStateTitle = app.staticTexts["No iCloud Workspaces Found"].firstMatch
        XCTAssertFalse(emptyStateTitle.exists)

        let delayedWorkspace = app.buttons["Delayed iCloud Workspace"].firstMatch
        XCTAssertTrue(delayedWorkspace.waitForExistence(timeout: 5))
        XCTAssertFalse(emptyStateTitle.exists)
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

        app.buttons["Add Workspace"].tap()

        let workspaceNameField = app.textFields["Name"].firstMatch
        XCTAssertTrue(workspaceNameField.waitForExistence(timeout: 5))
        workspaceNameField.tap()
        workspaceNameField.typeText("Personal")
        app.buttons["Save"].tap()

        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Privacy and Notifications"].firstMatch.waitForExistence(timeout: 5))

        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Gestures & Editing"].firstMatch.waitForExistence(timeout: 5))

        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Categories"].firstMatch.waitForExistence(timeout: 5))

        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Cards"].firstMatch.waitForExistence(timeout: 5))

        app.buttons["Add Card"].tap()

        let cardNameField = app.textFields["Name"].firstMatch
        XCTAssertTrue(cardNameField.waitForExistence(timeout: 5))
        cardNameField.tap()
        cardNameField.typeText("Checking")
        app.buttons["Save"].tap()

        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Presets"].firstMatch.waitForExistence(timeout: 5))

        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Income"].firstMatch.waitForExistence(timeout: 5))

        app.buttons["Next"].tap()
        XCTAssertTrue(app.staticTexts["Budgets"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No budgets yet."].firstMatch.exists)

        app.buttons["Next"].tap()
        XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Done"].tap()

        let budgetsTab = app.tabBars.buttons["Budgets"].firstMatch
        XCTAssertTrue(budgetsTab.waitForExistence(timeout: 5))
        budgetsTab.tap()

        let emptyBudgetsTitle = app.staticTexts["No Budgets Yet"].firstMatch
        XCTAssertTrue(emptyBudgetsTitle.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["March 2026"].firstMatch.exists)
    }

    // MARK: - Helpers

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
