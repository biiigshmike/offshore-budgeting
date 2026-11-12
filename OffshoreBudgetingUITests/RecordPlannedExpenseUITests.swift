import XCTest

@MainActor
final class RecordPlannedExpenseUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingReset", "-uiTestScenarioBudgetMenus", "-uiTestRecordAsPlanned",
            "-tips_seenKeys", "tip.home.v1,tip.budgets.v1,tip.budgetdetail.v1,tip.cards.v1,tip.carddetail.v1,tip.categories.v1",
            "-general_defaultBudgetingPeriod", "monthly", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 15))
        return app
    }

    private func recordAndVerify(in app: XCUIApplication, scrollPastHeader: Bool = false) {
        let row = app.descendants(matching: .any).matching(NSPredicate(
            format: "label BEGINSWITH %@", "Record Test Bill"
        )).firstMatch
        for _ in 0..<6 {
            if row.exists, row.isHittable { break }
            let list = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.tables.firstMatch
            if list.exists { list.swipeUp() } else { app.swipeUp() }
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        // Card headers can leave a hittable row partly covered by the bottom controls.
        if scrollPastHeader {
            let list = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.tables.firstMatch
            if list.exists { list.swipeUp() }
        }
        row.swipeRight()
        let record = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "plannedExpense.recordAsPlanned."
        )).firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Edit"].exists)
        XCTAssertTrue(app.buttons["Edit Preset"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "As Planned swipe actions"
        attachment.lifetime = .keepAlways
        add(attachment)
        record.tap()
        XCTAssertFalse(record.waitForExistence(timeout: 1))

        row.swipeRight()
        XCTAssertFalse(record.exists)
        app.buttons.matching(NSPredicate(
            format: "label == %@ AND identifier != %@", "Edit", "home.editWidgets"
        )).firstMatch.tap()
        let actual = app.textFields["Actual Amount (optional)"]
        XCTAssertTrue(actual.waitForExistence(timeout: 5))
        XCTAssertEqual(actual.value as? String, "60.00")
    }

    private func openDestination(_ title: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[title]
        if tab.exists {
            tab.tap()
            return
        }
        let button = app.buttons[title].firstMatch
        let text = app.staticTexts[title].firstMatch
        if button.exists, button.isHittable {
            button.tap()
        } else if text.exists, text.isHittable {
            text.tap()
        } else {
            let sidebar = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "sidebar")).firstMatch
            if sidebar.exists { sidebar.tap() }
            XCTAssertTrue(text.waitForExistence(timeout: 5))
            text.tap()
        }
    }

    func testBudgetDetail() {
        let app = launch()
        openDestination("Budgets", in: app)
        let budget = app.staticTexts["Existing Menu Budget"].firstMatch
        XCTAssertTrue(budget.waitForExistence(timeout: 5))
        budget.tap()
        recordAndVerify(in: app)
    }

    func testCardDetail() {
        let app = launch()
        openDestination("Accounts", in: app)
        app.buttons["accounts.destination.cards"].tap()
        let card = app.staticTexts["Ruby Card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        recordAndVerify(in: app, scrollPastHeader: true)
    }

    func testCategoryDetail() {
        let app = launch()
        openDestination("Settings", in: app)
        let manage = app.buttons["Manage Categories"]
        for _ in 0..<6 {
            if manage.exists, manage.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(manage.waitForExistence(timeout: 5))
        manage.tap()
        let category = app.staticTexts["Bills"].firstMatch
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        category.tap()
        recordAndVerify(in: app)
    }

    func testReviewTodayUpdatesSummary() {
        let app = launch()
        app.buttons["home.reviewToday"].tap()
        XCTAssertTrue(app.navigationBars["Review Today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Still Planned"].exists)
        recordAndVerify(in: app)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Today’s Activity"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Still Planned"].exists)
    }
}
