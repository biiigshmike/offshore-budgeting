import XCTest

@MainActor
final class AccountsNavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private let destinations = [
        (id: "cards", title: "Cards"),
        (id: "sharedBalances", title: "Reconciliations"),
        (id: "savings", title: "Offshore Savings")
    ]

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingReset", "-uiTestScenarioUncategorizedReview",
            "-uiTestReviewDisabled",
            "-tips_seenKeys", "tip.home.v1,tip.budgets.v1,tip.cards.v1,tip.income.v1",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 15))
        return app
    }

    private func assertSavingsToolbar(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["dateRange.editor"].exists)
        XCTAssertTrue(app.buttons["dateRange.quickRanges"].exists)
        XCTAssertTrue(app.buttons["Sort"].exists)
        XCTAssertTrue(app.buttons["Add Savings Entry"].exists)
        let editor = app.buttons["dateRange.editor"].frame
        let quickRanges = app.buttons["dateRange.quickRanges"].frame
        let sort = app.buttons["Sort"].frame
        let add = app.buttons["Add Savings Entry"].frame
        XCTAssertLessThan(editor.midX, quickRanges.midX)
        XCTAssertLessThan(quickRanges.midX, sort.midX)
        XCTAssertLessThan(sort.midX, add.midX)
    }

    func testOverviewDestinationsSupportNativeBackAndEdgeSwipe() throws {
        let app = launchApp()
        try XCTSkipUnless(app.tabBars.buttons["Accounts"].exists, "Edge-swipe coverage uses the phone layout.")
        app.tabBars.buttons["Accounts"].tap()

        for destination in destinations {
            let link = app.buttons["accounts.destination.\(destination.id)"]
            XCTAssertTrue(link.waitForExistence(timeout: 5))
            link.tap()
            let navigationBar = app.navigationBars[destination.title]
            XCTAssertTrue(navigationBar.waitForExistence(timeout: 5))
            if destination.id == "savings" {
                assertSavingsToolbar(app)
            }
            XCTAssertFalse(app.buttons["accounts.overview.return"].exists)
            navigationBar.buttons["Accounts"].tap()
            XCTAssertTrue(link.waitForExistence(timeout: 5))
            XCTAssertTrue(link.isHittable)

            link.tap()
            XCTAssertTrue(navigationBar.waitForExistence(timeout: 5))
            let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.001, dy: 0.45))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.45))
            edge.press(forDuration: 0.05, thenDragTo: end)
            XCTAssertTrue(link.waitForExistence(timeout: 5))
            XCTAssertTrue(link.isHittable)
        }
    }

    func testSidebarDestinationsRemainDirect() throws {
        #if !targetEnvironment(macCatalyst)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        #endif
        let app = launchApp()
        try XCTSkipIf(app.tabBars.buttons["Accounts"].exists, "Sidebar coverage requires the iPad or Mac layout.")

        app.staticTexts["Accounts"].firstMatch.tap()
        let cardsLink = app.buttons["accounts.destination.cards"]
        XCTAssertTrue(cardsLink.waitForExistence(timeout: 5))
        cardsLink.tap()
        XCTAssertTrue(app.navigationBars["Cards"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["accounts.overview.return"].exists)

        for destination in destinations {
            let sidebarItem = app.staticTexts["accounts.sidebar.\(destination.id)"].firstMatch
            XCTAssertTrue(sidebarItem.waitForExistence(timeout: 5))
            sidebarItem.tap()
            XCTAssertTrue(app.navigationBars[destination.title].waitForExistence(timeout: 5))
            if destination.id == "savings" {
                assertSavingsToolbar(app)
            }
            // The sidebar handles navigation on iPad. The direct return
            // button is only used by the phone shortcut flow.
            XCTAssertFalse(app.buttons["accounts.overview.return"].exists)
            XCTAssertFalse(app.navigationBars[destination.title].buttons["Accounts"].exists)
        }

        app.staticTexts["Accounts"].firstMatch.tap()
        XCTAssertTrue(app.buttons["accounts.destination.cards"].waitForExistence(timeout: 5))
    }
}
