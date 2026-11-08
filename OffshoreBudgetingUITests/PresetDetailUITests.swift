import XCTest

@MainActor
final class PresetDetailUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testPresetRowOpensDetailAndSavedEditRefreshesTitle() {
        let app = launchPresets()
        let internet = presetRow(in: app)
        reveal(internet, in: app)
        XCTAssertTrue(internet.label.contains("60.00"))
        XCTAssertTrue(internet.label.contains("Assigned Budgets"))
        attachScreenshot(app, named: "Native preset navigation rows")
        internet.tap()

        XCTAssertTrue(app.navigationBars["Internet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Ruby Card")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Bills")).firstMatch.exists)
        XCTAssertTrue(app.buttons["dateRange.editor"].exists)
        assertSubtitle(monthlyHistoryRangeText(), title: "Internet", in: app)
        XCTAssertFalse(app.buttons["Last 12 Months"].exists)
        XCTAssertFalse(app.buttons["All Time"].exists)
        attachScreenshot(app, named: "Preset detail summary and trends")

        app.buttons["presetDetail.edit"].tap()
        XCTAssertTrue(app.navigationBars["Edit Preset"].waitForExistence(timeout: 5))
        let name = app.textFields["Expense Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        let oldName = name.value as? String ?? ""
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldName.count))
        name.typeText("Internet Updated")
        app.navigationBars["Edit Preset"].buttons["Save"].tap()

        XCTAssertTrue(app.navigationBars["Edit Preset"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Internet Updated"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dateRange.editor"].exists)

        // The manual editor retains the currently displayed range when applied unchanged.
        app.buttons["dateRange.editor"].tap()
        XCTAssertTrue(app.navigationBars["Date Range"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("dateRange.start", in: app).exists)
        XCTAssertTrue(element("dateRange.end", in: app).exists)
        app.buttons["dateRange.done"].tap()
        XCTAssertTrue(app.navigationBars["Date Range"].waitForNonExistence(timeout: 5))
        assertSubtitle(monthlyHistoryRangeText(), title: "Internet Updated", in: app)
    }

    func testLargestAccessibilityTextKeepsPresetNavigationAndEditingReachable() {
        let app = launchPresets(extraArguments: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            "-AppleInterfaceStyle", "Dark"
        ])
        let internet = presetRow(in: app)
        reveal(internet, in: app)
        XCTAssertTrue(internet.label.contains("60.00"))
        XCTAssertTrue(internet.label.contains("Assigned Budgets"))
        attachScreenshot(app, named: "Preset rows at largest accessibility text size")
        internet.tap()
        XCTAssertTrue(app.navigationBars["Internet"].waitForExistence(timeout: 5))
        attachScreenshot(app, named: "Preset detail at largest accessibility text size")

        let edit = app.buttons["presetDetail.edit"]
        XCTAssertTrue(edit.isHittable)
        edit.tap()
        XCTAssertTrue(app.navigationBars["Edit Preset"].waitForExistence(timeout: 5))
        let cancel = app.navigationBars["Edit Preset"].buttons["Cancel"]
        XCTAssertTrue(cancel.isHittable)
        cancel.tap()
        XCTAssertTrue(app.navigationBars["Edit Preset"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Internet"].exists)
    }

    func testHomeTileOpensPresetWithRecordedHistoryAndOccurrenceEditor() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingReset", "-uiTestScenarioBudgetMenus", "-uiTestPresetDetailHistory",
            "-tips_seenKeys", "tip.home.v1,tip.preset.v1,tip.budgets.v1,tip.budgetdetail.v1",
            "-general_defaultBudgetingPeriod", "monthly", "-general_currencyCode", "USD",
            "-general_hideFuturePlannedExpenses", "NO",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 20))
        app.buttons["dateRange.quickRanges"].tap()
        let nextMonth = app.buttons["Next Month"]
        reveal(nextMonth, in: app)
        nextMonth.tap()
        let homeDateRange = monthRangeText(offset: 1)

        // The fixture has an unrecorded Rent occurrence on the first day of next month.
        let tile = app.descendants(matching: .any).matching(identifier: "home.nextPlannedExpense").firstMatch
        reveal(tile, in: app)
        XCTAssertTrue(tile.label.contains("Rent"))
        XCTAssertTrue(tile.label.contains("Not recorded"))
        XCTAssertTrue(tile.label.contains(homeDateRange))
        attachScreenshot(app, named: "Calmer themed Next Planned Expense tile")
        tile.tap()
        XCTAssertTrue(app.navigationBars["Rent"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Presets"].exists)
        // Detail uses its historical default, independently of Home's next-month selection.
        assertSubtitle(monthlyHistoryRangeText(), title: "Rent", in: app)
        let initialAverage = element("presetDetail.averageEffective", in: app)
        reveal(initialAverage, in: app)
        XCTAssertTrue((initialAverage.label + " " + (initialAverage.value as? String ?? "")).contains("800.00"))
        XCTAssertFalse(app.staticTexts["No Results Yet"].exists)
        let initialCounts = element("presetDetail.planCounts", in: app)
        XCTAssertTrue(initialCounts.label.contains("Higher: 1"))
        XCTAssertTrue(initialCounts.label.contains("As Expected: 2"))
        XCTAssertTrue(initialCounts.label.contains("Lower: 1"))
        attachScreenshot(app, named: "Historical results available immediately on opening")

        app.buttons["dateRange.quickRanges"].tap()
        let lastMonth = app.buttons["Last Month"]
        reveal(lastMonth, in: app)
        lastMonth.tap()
        let detailDateRange = monthRangeText(offset: -1)
        assertSubtitle(detailDateRange, title: "Rent", in: app)

        scrollToSummary(in: app)
        let trends = app.staticTexts["Planned vs. Effective"]
        reveal(trends, in: app)
        attachScreenshot(app, named: "Preset recorded history chart")
        let average = element("presetDetail.averageEffective", in: app)
        reveal(average, in: app)
        XCTAssertTrue((average.label + " " + (average.value as? String ?? "")).contains("800.00"))
        XCTAssertTrue(element("presetDetail.totalVariance", in: app).exists)
        XCTAssertTrue(element("presetDetail.planCounts", in: app).exists)
        XCTAssertFalse(app.staticTexts["Monthly Values"].exists)
        attachScreenshot(app, named: "Compact preset results")
        let occurrence = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "presetDetail.history.")
        ).firstMatch
        reveal(occurrence, in: app)
        XCTAssertTrue(occurrence.label.contains("Rent History -1"))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Rent History -2")).firstMatch.exists,
                       "A manually selected quick range must not be extended to include older history.")
        attachScreenshot(app, named: "Preset occurrence history")
        occurrence.tap()
        XCTAssertTrue(app.navigationBars["Edit Planned Expense"].waitForExistence(timeout: 5))
        app.navigationBars["Edit Planned Expense"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Edit Planned Expense"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Rent"].exists)
        assertSubtitle(detailDateRange, title: "Rent", in: app)
        app.navigationBars["Rent"].buttons["Home"].tap()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))
        let returnedTile = element("home.nextPlannedExpense", in: app)
        reveal(returnedTile, in: app)
        XCTAssertTrue(returnedTile.label.contains(homeDateRange))
    }

    func testLinkedBudgetsStartCollapsedExpandAndShowZeroForUnassignedPreset() {
        let app = launchPresets()
        let internet = presetRow(in: app)
        reveal(internet, in: app)
        internet.tap()
        XCTAssertTrue(app.navigationBars["Internet"].waitForExistence(timeout: 5))
        let disclosure = element("presetDetail.linkedBudgets", in: app)
        reveal(disclosure, in: app)
        XCTAssertTrue((disclosure.label + " " + (disclosure.value as? String ?? "")).contains("1"))
        let budget = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Existing Menu Budget")
        ).firstMatch
        XCTAssertFalse(budget.exists)
        disclosure.tap()
        XCTAssertTrue(budget.waitForExistence(timeout: 5))
        reveal(budget, in: app)
        attachScreenshot(app, named: "Expanded linked budgets")
        budget.tap()
        XCTAssertTrue(app.navigationBars["Existing Menu Budget"].waitForExistence(timeout: 5))
        app.navigationBars["Existing Menu Budget"].buttons["Internet"].tap()
        XCTAssertTrue(app.navigationBars["Internet"].waitForExistence(timeout: 5))
        app.navigationBars["Internet"].buttons["Presets"].tap()
        XCTAssertTrue(app.navigationBars["Presets"].waitForExistence(timeout: 5))

        let rent = presetRow(named: "Rent", in: app)
        reveal(rent, in: app)
        rent.tap()
        XCTAssertTrue(app.navigationBars["Rent"].waitForExistence(timeout: 5))
        let emptyDisclosure = element("presetDetail.linkedBudgets", in: app)
        reveal(emptyDisclosure, in: app)
        XCTAssertTrue((emptyDisclosure.label + " " + (emptyDisclosure.value as? String ?? "")).contains("0"))
        XCTAssertFalse(budget.exists)
        emptyDisclosure.tap()
        XCTAssertTrue(app.staticTexts["No linked budgets"].waitForExistence(timeout: 5))
        attachScreenshot(app, named: "Preset with no linked budgets")
    }

    func testManagePresetsDailyDefaultShowsThirtyDaysOfHistory() {
        let app = launchPresets(defaultPeriod: "daily")
        let internet = presetRow(in: app)
        reveal(internet, in: app)
        internet.tap()
        XCTAssertTrue(app.navigationBars["Internet"].waitForExistence(timeout: 5))
        let today = Calendar.current.startOfDay(for: .now)
        let start = Calendar.current.date(byAdding: .day, value: -29, to: today)!
        assertSubtitle(rangeText(start: start, end: today), title: "Internet", in: app)
        XCTAssertFalse(app.buttons["Last 12 Months"].exists)
        XCTAssertFalse(app.buttons["All Time"].exists)
    }

    func testChartsRenderForDailyWeeklyQuarterlyAndYearlyHistory() {
        for period in ["daily", "weekly", "quarterly", "yearly"] {
            let app = launchPresets(defaultPeriod: period, extraArguments: ["-uiTestPresetDetailHistory"])
            let rent = presetRow(named: "Rent", in: app)
            reveal(rent, in: app)
            rent.tap()
            XCTAssertTrue(app.navigationBars["Rent"].waitForExistence(timeout: 5))

            if period == "daily" {
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: .now)
                let baseline = calendar.date(byAdding: .day, value: -29, to: today)!
                let monthStart = calendar.dateInterval(of: .month, for: today)!.start
                let latestOccurrence = calendar.date(byAdding: .month, value: -1, to: monthStart)!
                // If the thirty-day baseline is empty, query initialization extends back to
                // the latest historical occurrence; it never jumps to the future fixture.
                let expected = rangeText(start: min(baseline, latestOccurrence), end: today)
                let subtitle = app.navigationBars["Rent"].descendants(matching: .any).matching(
                    NSPredicate(format: "label CONTAINS %@", expected)
                ).firstMatch
                XCTAssertTrue(subtitle.waitForExistence(timeout: 5),
                              "Daily history should include the latest historical occurrence after its query loads.")
            }

            let chart = element("presetDetail.trendChart", in: app)
            reveal(chart, in: app)
            XCTAssertTrue(chart.exists, "The \(period) chart should render historical data.")
            XCTAssertFalse(app.staticTexts["No Results Yet"].exists)
            attachScreenshot(app, named: "Preset trend chart grouped \(period)")
            let average = element("presetDetail.averageEffective", in: app)
            reveal(average, in: app)
            XCTAssertTrue(average.isHittable)
            XCTAssertTrue(element("presetDetail.totalVariance", in: app).exists)
            XCTAssertTrue(element("presetDetail.planCounts", in: app).exists)
            app.terminate()
        }
    }

    func testManualDateRangeChangesEndDateWithoutExtendingHistory() {
        let app = launchPresets()
        let internet = presetRow(in: app)
        reveal(internet, in: app)
        internet.tap()
        XCTAssertTrue(app.navigationBars["Internet"].waitForExistence(timeout: 5))
        assertSubtitle(monthlyHistoryRangeText(), title: "Internet", in: app)
        app.buttons["dateRange.editor"].tap()
        XCTAssertTrue(app.navigationBars["Date Range"].waitForExistence(timeout: 5))
        element("dateRange.end", in: app).tap()

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        if !calendar.isDate(yesterday, equalTo: today, toGranularity: .month) {
            let previousMonth = app.buttons.matching(NSPredicate(
                format: "label CONTAINS[c] %@ OR identifier CONTAINS[c] %@", "Previous Month", "PreviousMonth"
            )).firstMatch
            XCTAssertTrue(previousMonth.waitForExistence(timeout: 5))
            previousMonth.tap()
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE, MMMM d"
        let day = app.buttons[formatter.string(from: yesterday)]
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        day.tap()
        // The popup blocks background accessibility hit testing. Tap beside its
        // anchor using the visible label's frame, outside the calendar itself.
        app.staticTexts["End Date"].coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).tap()
        let done = app.buttons["dateRange.done"]
        XCTAssertTrue(done.isHittable)
        done.tap()
        XCTAssertTrue(app.navigationBars["Date Range"].waitForNonExistence(timeout: 5))
        let expected = rangeText(start: monthlyHistoryStart(), end: yesterday)
        assertSubtitle(expected, title: "Internet", in: app)
        attachScreenshot(app, named: "Manually selected history end date remains exact")

        // Reopening and applying unchanged must not replace the selection with a default range.
        app.buttons["dateRange.editor"].tap()
        XCTAssertTrue(app.navigationBars["Date Range"].waitForExistence(timeout: 5))
        app.buttons["dateRange.done"].tap()
        XCTAssertTrue(app.navigationBars["Date Range"].waitForNonExistence(timeout: 5))
        assertSubtitle(expected, title: "Internet", in: app)
    }

    private func launchPresets(defaultPeriod: String = "monthly", extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingReset", "-uiTestScenarioBudgetMenus",
            "-tips_seenKeys", "tip.home.v1,tip.preset.v1,tip.budgets.v1,tip.budgetdetail.v1",
            "-general_defaultBudgetingPeriod", defaultPeriod, "-general_currencyCode", "USD",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ] + extraArguments
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 15))
        openSettings(in: app)
        let manage = app.buttons["Manage Presets"]
        reveal(manage, in: app)
        manage.tap()
        XCTAssertTrue(app.navigationBars["Presets"].waitForExistence(timeout: 5))
        return app
    }

    private func presetRow(named title: String = "Internet", in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func monthlyHistoryStart() -> Date {
        let calendar = Calendar.current
        let monthStart = calendar.dateInterval(of: .month, for: .now)!.start
        return calendar.date(byAdding: .month, value: -11, to: monthStart)!
    }

    private func monthlyHistoryRangeText() -> String {
        rangeText(start: monthlyHistoryStart(), end: .now)
    }

    private func monthRangeText(offset: Int = 0) -> String {
        let calendar = Calendar.current
        let month = calendar.date(byAdding: .month, value: offset, to: .now)!
        let interval = calendar.dateInterval(of: .month, for: month)!
        let end = calendar.date(byAdding: .day, value: -1, to: interval.end)!
        return rangeText(start: interval.start, end: end)
    }

    private func rangeText(start: Date, end: Date) -> String {
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted).locale(Locale(identifier: "en_US"))
        return "\(start.formatted(style)) – \(end.formatted(style))"
    }

    private func assertSubtitle(_ range: String, title: String, in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars[title].descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", range)
        ).firstMatch.exists, "The navigation subtitle should show \(range).")
    }

    private func openSettings(in app: XCUIApplication) {
        let tab = app.tabBars.buttons["Settings"]
        if tab.exists {
            tab.tap()
        } else if app.buttons["Settings"].firstMatch.isHittable {
            app.buttons["Settings"].firstMatch.tap()
        } else {
            let settings = app.staticTexts["Settings"].firstMatch
            if !settings.isHittable {
                let sidebar = app.buttons.matching(
                    NSPredicate(format: "label CONTAINS[c] %@", "sidebar")
                ).firstMatch
                if sidebar.exists { sidebar.tap() }
            }
            let sidebarList = app.collectionViews.firstMatch.exists
                ? app.collectionViews.firstMatch : app.tables.firstMatch
            var selected = false
            for _ in 0..<8 {
                let button = app.buttons["Settings"].firstMatch
                if button.isHittable {
                    button.tap()
                    selected = true
                    break
                }
                if settings.isHittable {
                    settings.tap()
                    selected = true
                    break
                }
                XCTAssertTrue(sidebarList.exists)
                sidebarList.swipeUp()
            }
            XCTAssertTrue(selected, "Settings should be reachable in the sidebar.")
        }
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
    }

    private func scrollToSummary(in app: XCUIApplication) {
        let summary = app.staticTexts["Preset"]
        for _ in 0..<8 {
            if summary.isHittable { return }
            app.swipeDown()
        }
        XCTAssertTrue(summary.isHittable)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
