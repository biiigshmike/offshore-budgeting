import XCTest

@MainActor
final class SpendingCalculationSheetUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testCalculationSheetsOpenAndCloseFromBothHomeDetails() {
        checkSheets(largeText: false)
    }

    func testExpandableDetailsRemainReachableWithLargestAccessibilityText() {
        checkSheets(largeText: true)
    }

    private func checkSheets(largeText: Bool, titles: [String] = ["Category Spotlight", "Spend Trends"]) {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingReset", "-uiTestScenarioBudgetMenus", "-uiTestCategoryDetailHistory",
            "-tips_seenKeys", "tip.home.v1,tip.budgets.v1,tip.cards.v1,tip.income.v1",
            "-general_defaultBudgetingPeriod", "monthly", "-general_currencyCode", "USD",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 15))
        for title in titles {
            let tile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
            reveal(tile, in: app)
            tile.tap()
            let calculation = app.buttons["How is this calculated?"].firstMatch
            reveal(calculation, in: app)
            calculation.tap()
            let sheet = app.navigationBars["How is this calculated?"]
            XCTAssertTrue(sheet.waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Dates Included"].exists)
            let effective = app.staticTexts["Planned expenses before deductions"].firstMatch
            reveal(effective, in: app)
            XCTAssertTrue(effective.isHittable)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(title) calculation steps, large text: \(largeText)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            if title == "Category Spotlight" {
                let category = app.buttons.matching(NSPredicate(
                    format: "identifier BEGINSWITH %@", "calculation.disclosure.category-"
                )).firstMatch
                reveal(category, in: app)
                let categoryTitle = app.staticTexts[category.staticTexts.firstMatch.label].firstMatch
                revealHeader(categoryTitle, in: app)
                XCTAssertTrue((category.label).contains("$"))
                XCTAssertEqual(app.staticTexts.matching(identifier: "Category Spending").count, 1)
                let explanation = app.staticTexts.matching(NSPredicate(
                    format: "label == %@",
                    "This category’s total includes Planned Expenses and Variable Expenses, minus shared expense amounts, Pay From Savings, and refunds."
                )).firstMatch
                XCTAssertFalse(explanation.exists)
                let collapsed = XCTAttachment(screenshot: app.screenshot())
                collapsed.name = "Collapsed category spending, large text: \(largeText)"
                collapsed.lifetime = .keepAlways
                add(collapsed)
                categoryTitle.tap()
                XCTAssertTrue(explanation.waitForExistence(timeout: 3))
                let expanded = XCTAttachment(screenshot: app.screenshot())
                expanded.name = "Expanded category spending, large text: \(largeText)"
                expanded.lifetime = .keepAlways
                add(expanded)
                revealHeader(categoryTitle, in: app)
                categoryTitle.tap()
                XCTAssertTrue(explanation.waitForNonExistence(timeout: 3))
            }
            if title == "Spend Trends" {
                let period = app.buttons.matching(NSPredicate(
                    format: "identifier BEGINSWITH %@", "calculation.disclosure.period-"
                )).firstMatch
                reveal(period, in: app)
                let summaryTitle = period.staticTexts.firstMatch.label
                let periodTitle = app.staticTexts[summaryTitle].firstMatch
                revealHeader(periodTitle, in: app)
                XCTAssertTrue(period.label.contains("$"))
                XCTAssertEqual(app.staticTexts.matching(identifier: "Spending Periods").count, 1)
                let reconciliation = app.staticTexts.matching(NSPredicate(format: "label == %@", "Why the chart and total can differ")).firstMatch
                XCTAssertFalse(reconciliation.exists)
                let collapsed = XCTAttachment(screenshot: app.screenshot())
                collapsed.name = "Collapsed spending periods, large text: \(largeText)"
                collapsed.lifetime = .keepAlways
                add(collapsed)
                periodTitle.tap()
                reveal(reconciliation, in: app)
                XCTAssertTrue(reconciliation.exists)
                let expanded = XCTAttachment(screenshot: app.screenshot())
                expanded.name = "Expanded spending period, large text: \(largeText)"
                expanded.lifetime = .keepAlways
                add(expanded)
                revealHeader(periodTitle, in: app)
                periodTitle.tap()
                let recollapsed = XCTAttachment(screenshot: app.screenshot())
                recollapsed.name = "Recollapsed spending period, large text: \(largeText)"
                recollapsed.lifetime = .keepAlways
                add(recollapsed)
                XCTAssertTrue(reconciliation.waitForNonExistence(timeout: 3))
            }
            let help = app.buttons["Learn more in Help"].firstMatch
            reveal(help, in: app)
            XCTAssertTrue(help.isHittable)
            sheet.buttons["Close"].tap()
            XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
            XCTAssertTrue(calculation.exists)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))
        }
    }

    private func revealHeader(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<20 {
            // Expanded details can move their header out of the visible List cells.
            // Bring it back from above before deciding which way to scroll.
            if !element.exists {
                app.swipeDown()
                continue
            }
            if element.exists {
                let top = app.navigationBars.firstMatch.frame.maxY + 12
                if element.frame.minY < top {
                    app.swipeDown()
                    continue
                }
                if element.isHittable && element.frame.maxY < app.frame.maxY - 40 { return }
            }
            app.swipeUp()
        }
        XCTFail("The full disclosure title must be visible before tapping it.")
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<35 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
}
