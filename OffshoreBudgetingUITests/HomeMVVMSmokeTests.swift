import XCTest

/// Runs against the DEBUG screenshot container, which explicitly disables CloudKit.
/// Never run these reset-seed scenarios against a production build or a user's store.
final class HomeMVVMSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testHomeQuickRangeAndTabReturn() throws {
        let app = launchSeededHome()
        let apply = app.buttons["Apply date range"].firstMatch
        XCTAssertTrue(apply.waitForExistence(timeout: 10))
        XCTAssertFalse(apply.isEnabled)

        tap(app.buttons["Quick ranges"].firstMatch)
        tap(app.buttons["Today"].firstMatch)
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        // Quick ranges apply immediately, leaving no unapplied draft.
        let applied = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == false"), object: apply
        )
        XCTAssertEqual(XCTWaiter.wait(for: [applied], timeout: 5), .completed)

        tap(app.tabBars.buttons["Budgets"].firstMatch)
        XCTAssertTrue(app.navigationBars["Budgets"].waitForExistence(timeout: 5))
        tap(app.tabBars.buttons["Home"].firstMatch)
        XCTAssertTrue(app.buttons["Quick ranges"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Widgets"].firstMatch.exists)
    }

    @MainActor
    func testPinRemovalPersistsAcrossTabReturnAndCanBeRestored() throws {
        let app = launchSeededHome()
        tap(app.buttons["Edit"].firstMatch)
        XCTAssertTrue(app.navigationBars["Edit Dashboard"].waitForExistence(timeout: 5))
        tap(app.navigationBars["Edit Dashboard"].buttons["Edit"].firstMatch)

        // Income is the first seeded pin. Use the edit-mode removal control.
        // SwiftUI combines its edit-mode removal affordance into the title label.
        let incomeRow = app.cells.containing(.staticText, identifier: "Remove, Income").firstMatch
        XCTAssertTrue(incomeRow.waitForExistence(timeout: 5))
        tap(incomeRow.images["minus.circle.fill"].firstMatch)
        tap(app.collectionViews.buttons["Delete"].firstMatch)
        let availableIncome = app.collectionViews.buttons["Income"].firstMatch
        reveal(availableIncome, in: app)
        XCTAssertTrue(availableIncome.waitForExistence(timeout: 5))

        closePinEditor(app)
        tap(app.tabBars.buttons["Budgets"].firstMatch)
        tap(app.tabBars.buttons["Home"].firstMatch)
        tap(app.buttons["Edit"].firstMatch)
        XCTAssertTrue(app.navigationBars["Edit Dashboard"].waitForExistence(timeout: 5))
        let restoredAvailableIncome = app.collectionViews.buttons["Income"].firstMatch
        reveal(restoredAvailableIncome, in: app)
        XCTAssertTrue(restoredAvailableIncome.waitForExistence(timeout: 5))

        tap(app.navigationBars["Edit Dashboard"].buttons["Edit"].firstMatch)
        tap(restoredAvailableIncome)
        let removedFromAvailable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: restoredAvailableIncome
        )
        XCTAssertEqual(XCTWaiter.wait(for: [removedFromAvailable], timeout: 5), .completed)
        tap(app.buttons["Done"].firstMatch)
        closePinEditor(app)
        XCTAssertTrue(app.buttons["Quick ranges"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testWorkspaceSwitchAndReturnKeepsHomeAvailable() throws {
        let app = launchSeededHome()
        tap(app.tabBars.buttons["Settings"].firstMatch)
        tap(app.buttons["Workspaces"].firstMatch)
        tap(app.buttons["Manage Workspaces"].firstMatch)
        XCTAssertTrue(app.navigationBars["Workspaces"].waitForExistence(timeout: 5))
        tap(app.buttons["Workspace Actions"].firstMatch)
        tap(app.buttons["Add Workspace"].firstMatch)
        // Screenshot mode prefills this name; use it as the isolated second workspace.
        XCTAssertTrue(app.textFields["Name"].firstMatch.waitForExistence(timeout: 5))
        tap(app.buttons["Save"].firstMatch)
        tap(app.buttons["Close"].firstMatch)

        tap(app.buttons["Workspaces"].firstMatch)
        tap(app.buttons["Personal Snapshot"].firstMatch)
        tap(app.tabBars.buttons["Home"].firstMatch)
        XCTAssertTrue(app.buttons["Quick ranges"].waitForExistence(timeout: 5))

        tap(app.tabBars.buttons["Settings"].firstMatch)
        tap(app.buttons["Workspaces"].firstMatch)
        tap(app.buttons["Personal"].firstMatch)
        tap(app.tabBars.buttons["Home"].firstMatch)
        XCTAssertTrue(app.buttons["Quick ranges"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Widgets"].firstMatch.exists)
    }

    @MainActor
    private func launchSeededHome() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode", "-resetSeed", "-didCompleteOnboarding", "YES",
            "-icloud_useCloud", "NO", "-tips_resetToken", "0",
            "-tips_seen_lastResetToken", "0",
            "-tips_seenKeys", "tip.home.v1,tip.budgets.v1",
            "-releaseLogs_seenReleaseIDs", "2.4.1-22,2.4-21",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Home"].firstMatch.waitForExistence(timeout: 15))
        tap(app.tabBars.buttons["Home"].firstMatch)
        XCTAssertTrue(app.buttons["Quick ranges"].firstMatch.waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func closePinEditor(_ app: XCUIApplication) {
        tap(app.navigationBars["Edit Dashboard"].buttons["xmark"].firstMatch)
    }

    @MainActor
    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Missing element: \(element)")
        element.tap()
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.collectionViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "Could not scroll to \(element)")
    }
}
