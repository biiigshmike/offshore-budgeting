import XCTest

@MainActor
final class WorkspaceProgressHandoffUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testOnboardingDoneOpensProgressAndNestedFormsReturnUntilSkip() throws {
        let app = makeApp(extraArguments: ["-uiTestProgressFinishOnboarding"])
        app.launch()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        done.tap()

        assertHandoff(in: app)
        assertProgress(80, completed: 4, in: app)
        openAndCloseHelpGuide(in: app)
        assertHandoff(in: app)
        assertProgress(80, completed: 4, in: app)
        attachScreenshot("Onboarding hands off to Workspace Progress", app: app)
        let guidance = app.staticTexts["You can return to Workspace Progress in Settings."]
        reveal(guidance, in: app)

        let addIncome = app.buttons["workspaceProgressStep_income"]
        reveal(addIncome, in: app)
        addIncome.tap()
        XCTAssertTrue(app.navigationBars["Add Income"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        assertHandoff(in: app)
        assertProgress(80, completed: 4, in: app)

        reveal(addIncome, in: app)
        addIncome.tap()
        XCTAssertTrue(app.navigationBars["Add Income"].waitForExistence(timeout: 5))
        let source = app.textFields["Source"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap()
        source.typeText("Handoff paycheck")
        let amount = app.textFields["Amount"]
        amount.tap()
        amount.typeText("2500")
        app.buttons["Save"].tap()

        assertHandoff(in: app, completed: true)
        assertProgress(100, completed: 5, in: app)
        let completion = element("workspaceProgressComplete", in: app)
        reveal(completion, in: app)
        attachScreenshot("Completed progress remains open", app: app)
        app.buttons["workspaceProgressSkip"].tap()
        assertHome(in: app)

        openSettings(app)
        let progressRow = element("settingsWorkspaceProgress", in: app)
        XCTAssertTrue(progressRow.waitForExistence(timeout: 5))
        progressRow.tap()
        XCTAssertTrue(app.navigationBars["Workspace Progress"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["workspaceProgressSkip"].exists)
        XCTAssertFalse(app.buttons["Open Help Guide"].exists)
        XCTAssertFalse(guidance.exists)
        assertProgress(100, completed: 5, in: app)
    }

    func testFreshHandoffPlacesHelpAfterChecklist() {
        let app = makeApp(extraArguments: ["-uiTestProgressHandoff", "-uiTestProgressCardOnly"])
        app.launch()
        assertHandoff(in: app)
        assertProgress(20, completed: 1, in: app)
        XCTAssertFalse(app.staticTexts["Next Steps"].exists)
        let budget = app.buttons["workspaceProgressStep_budget"]
        reveal(budget, in: app)
        let help = app.buttons["Open Help Guide"]
        reveal(help, in: app)
        XCTAssertLessThanOrEqual(budget.frame.maxY, help.frame.minY)
        openAndCloseHelpGuide(in: app)
        assertHandoff(in: app)
        assertProgress(20, completed: 1, in: app)
    }

    func testFirstSetupBudgetOpensFromHomeTipsAndKeepsHiddenExpensesInTotals() {
        let app = launchWithFirstBudgetSetup(arguments: [
            "-uiTestProgressBudgetExpenses",
            "-general_defaultBudgetingPeriod", "yearly",
            "-general_hideFutureVariableExpenses", "NO",
            "-general_excludeFutureVariableExpensesFromCalculations", "NO"
        ])
        openFirstBudgetForm(in: app)
        let budgetName = app.textFields["budget.name"].value as? String ?? ""
        app.navigationBars["Add Budget"].buttons["Save"].tap()
        addMatchingRentPreset(in: app)
        finishSetupAndWaitForTips(in: app)

        let viewBudget = app.buttons["homeTips.viewBudget"]
        XCTAssertEqual(viewBudget.label, "View My Budget")
        viewBudget.tap()
        XCTAssertTrue(app.buttons["Budget Actions"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.navigationBars[budgetName].exists)
        XCTAssertFalse(app.staticTexts["Dashboard"].exists)
        XCTAssertFalse(app.navigationBars["Budgets"].exists)

        reveal(app.staticTexts["Grocery entry"], in: app)
        let futureExpense = app.staticTexts["Future grocery entry"]
        reveal(futureExpense, in: app)
        let total = app.staticTexts["All Expenses • $64.00"]
        XCTAssertTrue(total.exists)
        app.buttons["Expense Display"].tap()
        app.buttons["Variable Expense Display"].tap()
        app.buttons["Hide Future Variable Expenses"].tap()
        XCTAssertTrue(futureExpense.waitForNonExistence(timeout: 5))
        XCTAssertTrue(total.exists)
    }

    func testSetupTipsDoneAndSwipeLeaveHome() {
        for useDone in [true, false] {
            let app = launchWithFirstBudgetSetup()
            openFirstBudgetForm(in: app)
            app.navigationBars["Add Budget"].buttons["Save"].tap()
            finishSetupAndWaitForTips(in: app)
            XCTAssertTrue(app.buttons["homeTips.viewBudget"].exists)
            if useDone {
                app.buttons["Done"].tap()
            } else {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
                    .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
            }
            XCTAssertTrue(app.staticTexts["Dashboard"].waitForNonExistence(timeout: 5))
            assertHome(in: app)
            XCTAssertFalse(app.buttons["Budget Actions"].exists)
            app.terminate()
        }
    }

    func testSetupTipsOpensFirstBudgetFromRepeatPreview() {
        let app = launchWithFirstBudgetSetup()
        openFirstBudgetForm(in: app)
        let repeatPicker = app.buttons["budget.repeat"]
        reveal(repeatPicker, in: app)
        repeatPicker.tap()
        app.buttons["Monthly"].tap()
        let firstBudget = app.textFields["budget.name"].value as? String ?? ""
        XCTAssertFalse(firstBudget.isEmpty)
        app.navigationBars["Add Budget"].buttons["Preview"].tap()
        XCTAssertTrue(app.navigationBars["Preview"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["2 budgets"].exists)
        let previewTexts = app.staticTexts.allElementsBoundByIndex.map(\.label)
        let section = previewTexts.firstIndex(of: "Budgets to Create")
        XCTAssertNotNil(section)
        guard let section, section + 1 < previewTexts.count else { return }
        XCTAssertTrue(previewTexts[section + 1].hasPrefix(firstBudget))
        app.buttons["budget.confirmBatch"].tap()
        finishSetupAndWaitForTips(in: app)
        let viewBudget = app.buttons["homeTips.viewBudget"]
        XCTAssertEqual(viewBudget.label, "View My Budget")
        viewBudget.tap()
        XCTAssertTrue(app.buttons["Budget Actions"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.navigationBars[firstBudget].exists)
    }

    func testSetupTipsHasNoShortcutAfterCancelOrOnUpdate() {
        let fresh = launchWithFirstBudgetSetup()
        openFirstBudgetForm(in: fresh)
        fresh.navigationBars["Add Budget"].buttons["Cancel"].tap()
        finishSetupAndWaitForTips(in: fresh)
        XCTAssertFalse(fresh.buttons["homeTips.viewBudget"].exists)
        fresh.buttons["Done"].tap()
        assertHome(in: fresh)
        fresh.terminate()

        let existing = makeApp(extraArguments: [
            "-uiTestProgressHandoff", "-uiTestProgressCardOnly", "-uiTestProgressPendingPrompts"
        ], pendingTips: true)
        existing.launch()
        assertHandoff(in: existing)
        openFirstBudgetForm(in: existing)
        existing.navigationBars["Add Budget"].buttons["Save"].tap()
        existing.buttons["workspaceProgressSkip"].tap()
        let releaseTitle = existing.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "What’s New in ")).firstMatch
        XCTAssertTrue(releaseTitle.waitForExistence(timeout: 10))
        existing.buttons["Continue"].firstMatch.tap()
        XCTAssertTrue(existing.staticTexts["Dashboard"].waitForExistence(timeout: 10))
        XCTAssertFalse(existing.buttons["homeTips.viewBudget"].exists)
        existing.buttons["Done"].tap()
        assertHome(in: existing)
    }

    func testFreshHandoffSavesRemainingStepsAndChangesSkipToDone() {
        let app = makeApp(extraArguments: ["-uiTestProgressHandoff", "-uiTestProgressCardOnly"])
        app.launch()
        assertHandoff(in: app)
        assertProgress(20, completed: 1, in: app)

        for (index, step) in ["category", "preset", "income", "budget"].enumerated() {
            let row = app.buttons["workspaceProgressStep_\(step)"]
            reveal(row, in: app)
            row.tap()
            switch step {
            case "category":
                XCTAssertTrue(app.navigationBars["Add Category"].waitForExistence(timeout: 5))
                app.textFields["Name"].tap()
                app.textFields["Name"].typeText("Household")
            case "preset":
                XCTAssertTrue(app.navigationBars["Add Preset"].waitForExistence(timeout: 5))
                let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Choose a Card")).firstMatch
                card.tap()
                app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "First Card")).firstMatch.tap()
                app.textFields["Expense Name"].tap()
                app.textFields["Expense Name"].typeText("Internet")
                app.textFields["Planned Amount"].tap()
                app.textFields["Planned Amount"].typeText("60")
            case "income":
                XCTAssertTrue(app.navigationBars["Add Income"].waitForExistence(timeout: 5))
                app.textFields["Source"].tap()
                app.textFields["Source"].typeText("Paycheck")
                app.textFields["Amount"].tap()
                app.textFields["Amount"].typeText("2500")
            default:
                XCTAssertTrue(app.navigationBars["Add Budget"].waitForExistence(timeout: 5))
                let name = app.textFields["budget.name"]
                name.tap()
                name.typeText("First Budget")
            }
            let save = app.navigationBars.buttons["Save"]
            XCTAssertTrue(save.isEnabled)
            save.tap()
            if step == "preset" {
                let confirmation = app.navigationBars["Preset Saved"]
                XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
                confirmation.buttons["Done"].tap()
            }
            assertHandoff(in: app, completed: step == "budget")
            assertProgress((index + 2) * 20, completed: index + 2, in: app)
            XCTAssertFalse(app.buttons["workspaceProgressStep_\(step)"].exists)
        }

        for step in ["card", "category", "preset", "income", "budget"] {
            XCTAssertFalse(app.buttons["workspaceProgressStep_\(step)"].exists)
        }
        let completion = element("workspaceProgressComplete", in: app)
        reveal(completion, in: app)
        attachScreenshot("Five-of-five checklist with Done", app: app)
        app.buttons["workspaceProgressSkip"].tap()
        assertHome(in: app)
    }

    func testArabicChecklistLocalizesStatusAndOpensIncome() {
        let app = makeApp(extraArguments: ["-uiTestProgressHandoff", "-uiTestProgressCardOnly"])
        app.launchArguments = app.launchArguments.map {
            $0 == "(en)" ? "(ar)" : ($0 == "en_US" ? "ar_SA" : $0)
        }
        app.launch()
        XCTAssertTrue(app.buttons["workspaceProgressSkip"].waitForExistence(timeout: 15))
        let income = app.buttons["workspaceProgressStep_income"]
        reveal(income, in: app)
        XCTAssertTrue(income.label.contains("غير مكتمل"))
        XCTAssertGreaterThanOrEqual(income.frame.height, 44)
        attachScreenshot("Arabic right-to-left checklist", app: app)
        income.tap()
        XCTAssertTrue(app.navigationBars["أضف الدخل"].waitForExistence(timeout: 5))
        app.buttons["يلغي"].tap()
        XCTAssertTrue(app.buttons["workspaceProgressSkip"].waitForExistence(timeout: 5))
        reveal(income, in: app)
        XCTAssertTrue(income.label.contains("غير مكتمل"))
    }

    func testCompletedWorkspaceGoesDirectlyHome() throws {
        let app = makeApp(extraArguments: ["-uiTestProgressHandoff", "-uiTestProgressComplete"])
        app.launch()
        assertHome(in: app)
        XCTAssertFalse(app.buttons["workspaceProgressSkip"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.navigationBars["Workspace Progress"].exists)
    }

    func testHandoffHelpGuideAtLargestAccessibilityTextSize() {
        let app = makeApp(extraArguments: [
            "-uiTestProgressHandoff",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        app.launch()

        assertHandoff(in: app)
        let link = app.buttons["Open Help Guide"]
        reveal(link, in: app)
        XCTAssertGreaterThanOrEqual(link.frame.height, 44)
        attachScreenshot("Workspace Progress help link at largest text size", app: app)
        link.tap()
        let help = app.navigationBars["Help"]
        XCTAssertTrue(help.waitForExistence(timeout: 5))
        help.buttons["Done"].tap()
        assertHandoff(in: app)
    }

    func testDelayedWorkspaceArrivalPreservesRequestedWorkspace() throws {
        let app = makeApp(extraArguments: ["-uiTestProgressDelayedWorkspace"])
        app.launch()
        assertHandoff(in: app)
        assertProgress(80, completed: 4, in: app)
        let summary = element("workspaceProgressSummary", in: app)
        XCTAssertTrue(summary.label.contains("Progress Workspace"))
        XCTAssertFalse(summary.label.contains("Other Workspace"))
        attachScreenshot("Delayed discovery keeps requested workspace", app: app)

        app.buttons["workspaceProgressSkip"].tap()
        assertHome(in: app)
        openSettings(app)
        let progressRow = element("settingsWorkspaceProgress", in: app)
        XCTAssertTrue(progressRow.waitForExistence(timeout: 5))
        progressRow.tap()
        XCTAssertTrue(app.navigationBars["Workspace Progress"].waitForExistence(timeout: 5))
        assertProgress(80, completed: 4, in: app)
        XCTAssertTrue(summary.label.contains("Progress Workspace"))
    }

    func testInteractiveDismissalDoesNotReopenOnRelaunch() throws {
        let app = makeApp(extraArguments: ["-uiTestProgressHandoff"])
        app.launch()
        assertHandoff(in: app)
        let header = app.navigationBars["Workspace Progress"]
        header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        assertHome(in: app)

        app.terminate()
        app.launchArguments.removeAll { $0 == "-uiTestingReset" }
        app.launchArguments.append("-uiTestPreserveScenarioData")
        app.launch()
        assertHome(in: app)
        XCTAssertFalse(app.buttons["workspaceProgressSkip"].waitForExistence(timeout: 2))
    }

    func testReleaseNotesAndHomeTipsWaitForHandoffDismissal() throws {
        let app = makeApp(extraArguments: ["-uiTestProgressHandoff", "-uiTestProgressPendingPrompts"], pendingTips: true)
        app.launch()
        assertHandoff(in: app)
        let releaseTitle = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "What’s New in ")).firstMatch
        XCTAssertFalse(releaseTitle.exists)
        XCTAssertFalse(app.staticTexts["Dashboard"].exists)
        XCTAssertFalse(app.navigationBars["Review Expenses"].exists)
        attachScreenshot("Progress precedes automatic prompts", app: app)

        app.buttons["workspaceProgressSkip"].tap()
        XCTAssertTrue(releaseTitle.waitForExistence(timeout: 10))
        app.buttons["Continue"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Dashboard"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.navigationBars["Review Expenses"].exists)
        let helpButton = app.buttons["Open Help Guide"]
        let continueButton = app.buttons["Done"].firstMatch
        XCTAssertTrue(helpButton.isHittable)
        XCTAssertLessThanOrEqual(helpButton.frame.maxY, continueButton.frame.minY)
        openAndCloseHelpGuide(in: app)
        XCTAssertTrue(helpButton.isHittable)
        XCTAssertTrue(app.staticTexts["Dashboard"].exists)
        continueButton.tap()
        let review = app.navigationBars["Review Expenses"]
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        let reviewedExpense = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Handoff review expense")).firstMatch
        XCTAssertTrue(reviewedExpense.waitForExistence(timeout: 5))
        app.buttons["Skip"].tap()
        XCTAssertTrue(review.waitForNonExistence(timeout: 5))
        assertHome(in: app)
        XCTAssertFalse(helpButton.exists)
    }

    func testSwipingHomeTipDoesNotReopenItWhenPresentationBecomesIdle() throws {
        let app = makeApp(extraArguments: ["-uiTestProgressHandoff", "-uiTestProgressPendingPrompts"], pendingTips: true)
        app.launch()
        assertHandoff(in: app)
        app.buttons["workspaceProgressSkip"].tap()
        let releaseTitle = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "What’s New in ")).firstMatch
        XCTAssertTrue(releaseTitle.waitForExistence(timeout: 10))
        app.buttons["Continue"].firstMatch.tap()
        let dashboard = app.staticTexts["Dashboard"]
        XCTAssertTrue(dashboard.waitForExistence(timeout: 10))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        XCTAssertTrue(app.navigationBars["Review Expenses"].waitForExistence(timeout: 10))
        app.buttons["Skip"].tap()
        assertHome(in: app)
        XCTAssertFalse(dashboard.waitForExistence(timeout: 2))
    }

    func testSkippingExistingCloudOnboardingUsesCompletionEligibility() throws {
        for completed in [false, true] {
            let app = makeApp(extraArguments: ["-uiTestProgressSkipOnboarding"] + (completed ? ["-uiTestProgressComplete"] : []))
            app.launch()
            let skip = app.alerts["Existing iCloud Data Detected"].buttons["Skip Onboarding"]
            XCTAssertTrue(skip.waitForExistence(timeout: 10))
            skip.tap()
            if completed {
                assertHome(in: app)
                XCTAssertFalse(app.buttons["workspaceProgressSkip"].waitForExistence(timeout: 2))
            } else {
                assertHandoff(in: app)
                app.buttons["workspaceProgressSkip"].tap()
                assertHome(in: app)
            }
            app.terminate()
        }
    }

    private func launchWithFirstBudgetSetup(arguments: [String] = []) -> XCUIApplication {
        let app = makeApp(extraArguments: [
            "-uiTestProgressFinishOnboarding", "-uiTestProgressCardOnly"
        ] + arguments, pendingTips: true)
        app.launch()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        done.tap()
        assertHandoff(in: app)
        return app
    }

    private func openFirstBudgetForm(in app: XCUIApplication) {
        let step = app.buttons["workspaceProgressStep_budget"]
        reveal(step, in: app)
        step.tap()
        XCTAssertTrue(app.navigationBars["Add Budget"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["budget.cards"].label.contains("First Card"))
    }

    private func addMatchingRentPreset(in app: XCUIApplication) {
        let step = app.buttons["workspaceProgressStep_preset"]
        reveal(step, in: app)
        step.tap()
        XCTAssertTrue(app.navigationBars["Add Preset"].waitForExistence(timeout: 5))
        app.buttons["Choose a Card"].tap()
        app.buttons["First Card"].tap()
        app.textFields["Expense Name"].tap()
        app.textFields["Expense Name"].typeText("Rent")
        app.textFields["Planned Amount"].tap()
        app.textFields["Planned Amount"].typeText("1200")
        app.navigationBars["Add Preset"].buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Preset Saved"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["applySavedPreset"].label, "Add to Budget")
        app.buttons["Not Now"].tap()
    }

    private func finishSetupAndWaitForTips(in app: XCUIApplication) {
        let finish = app.buttons["workspaceProgressSkip"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()
        XCTAssertTrue(app.staticTexts["Dashboard"].waitForExistence(timeout: 10))
    }

    private func makeApp(extraArguments: [String], pendingTips: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingReset", "-uiTestScenarioWorkspaceProgress",
            "-tips_seenKeys", pendingTips ? "tip.budgetdetail.v1" : "tip.home.v1,tip.budgets.v1,tip.cards.v1,tip.income.v2,tip.budgetdetail.v1",
            "-tips_resetToken", "0", "-tips_seen_lastResetToken", "0",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ] + extraArguments
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func assertHandoff(in app: XCUIApplication, completed: Bool = false) {
        XCTAssertTrue(app.buttons["workspaceProgressSkip"].waitForExistence(timeout: 15))
        let navigationBar = app.navigationBars["Workspace Progress"]
        XCTAssertTrue(navigationBar.exists)
        let skip = navigationBar.buttons["workspaceProgressSkip"]
        XCTAssertTrue(skip.exists)
        XCTAssertEqual(skip.label, completed ? "Done" : "Skip")
    }

    private func assertHome(in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["workspaceProgressSkip"].exists)
        XCTAssertFalse(app.navigationBars["Settings"].exists)
    }

    private func assertProgress(_ percent: Int, completed: Int, in app: XCUIApplication) {
        let summary = element("workspaceProgressSummary", in: app)
        for _ in 0..<10 {
            if summary.exists && summary.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        let expected = NSPredicate(format: "value CONTAINS %@", "\(percent) percent, \(completed) of 5 completed")
        expectation(for: expected, evaluatedWith: summary)
        waitForExpectations(timeout: 5)
    }

    private func openSettings(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons["Settings"]
        if tab.waitForExistence(timeout: 2) {
            tab.tap()
        } else {
            let settings = app.staticTexts["Settings"].firstMatch
            if !settings.exists || !settings.isHittable {
                let sidebar = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "sidebar")).firstMatch
                if sidebar.exists { sidebar.tap() }
            }
            XCTAssertTrue(settings.waitForExistence(timeout: 5))
            settings.tap()
        }
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }

    private func openAndCloseHelpGuide(in app: XCUIApplication) {
        let link = app.buttons["Open Help Guide"]
        reveal(link, in: app)
        link.tap()
        let help = app.navigationBars["Help"]
        XCTAssertTrue(help.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Getting Started"].exists)
        attachScreenshot("Help Guide opened", app: app)
        let introduction = app.descendants(matching: .any).matching(identifier: "Introduction").firstMatch
        XCTAssertTrue(introduction.waitForExistence(timeout: 5))
        help.buttons["Done"].tap()
        XCTAssertTrue(help.waitForNonExistence(timeout: 5))
    }

    private func attachScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
