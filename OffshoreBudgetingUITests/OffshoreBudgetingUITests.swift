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

        let emptyStateTitle = app.staticTexts["No iCloud Workspaces Found"].firstMatch
        XCTAssertTrue(emptyStateTitle.waitForExistence(timeout: 10))

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
