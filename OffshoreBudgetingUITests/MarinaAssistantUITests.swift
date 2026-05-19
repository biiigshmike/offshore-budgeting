import XCTest

@MainActor
final class MarinaAssistantUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testMarinaAppSurfaceSequentialRegressionPrompts_realUISession() throws {
        let app = XCUIApplication()
        let driver = MarinaUITestDriver(app: app, testCase: self)
        let reporter = MarinaAppSurfaceReporter()

        driver.launchHarness()

        for prompt in Self.sequentialSmokePrompts {
            let report = driver.runPrompt(prompt.text, expectation: prompt.expectation, timeout: 6)
            reporter.record(report)
        }

        reporter.attach(to: self)
        let failures = reporter.failures
        if failures.isEmpty == false {
            let summary = failures
                .prefix(8)
                .map { "\($0.prompt) [\($0.result.category.rawValue)]: \($0.result.reason)" }
                .joined(separator: "\n")
            XCTFail("Marina app-surface matrix found \(failures.count) failures:\n\(summary)")
        }
    }

    func testMarinaAppSurfacePromptMatrix_coversAllSwiftDataModelsInOneSession() throws {
        guard ProcessInfo.processInfo.environment["MARINA_RUN_EXHAUSTIVE_MATRIX"] == "1" else {
            throw XCTSkip(Self.exhaustiveMatrixSkipMessage)
        }

        let app = XCUIApplication()
        let driver = MarinaUITestDriver(app: app, testCase: self)
        let reporter = MarinaAppSurfaceReporter()

        driver.launchHarness()

        for prompt in Self.promptMatrix {
            let report = driver.runPrompt(prompt.text, expectation: prompt.expectation, timeout: 8)
            reporter.record(report)
        }

        reporter.attach(to: self)
        let failures = reporter.failures
        if failures.isEmpty == false {
            let summary = failures
                .prefix(12)
                .map { "\($0.prompt) [\($0.result.category.rawValue)]: \($0.result.reason)" }
                .joined(separator: "\n")
            XCTFail("Marina app-surface exhaustive matrix found \(failures.count) failures:\n\(summary)")
        }
    }

    private static let exhaustiveMatrixSkipMessage = """
    Exhaustive all-model Marina matrix is opt-in. Run with MARINA_RUN_EXHAUSTIVE_MATRIX=1 in the test environment, for example:
    MARINA_RUN_EXHAUSTIVE_MATRIX=1 xcodebuild -scheme OffshoreBudgeting -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:OffshoreBudgetingUITests/MarinaAssistantUITests/testMarinaAppSurfacePromptMatrix_coversAllSwiftDataModelsInOneSession test
    """

    func testMarinaAppSurfaceAppleClarification_resumesWithoutLegacyFallback() throws {
        let app = XCUIApplication()
        let driver = MarinaUITestDriver(app: app, testCase: self)
        let reporter = MarinaAppSurfaceReporter()

        driver.launchHarness()

        let ambiguityReport = driver.runPrompt(
            "What did I spend at Apple?",
            expectation: MarinaPromptExpectation(model: "VariableExpense", outcome: .clarification, responseShape: .clarification)
        )
        reporter.record(ambiguityReport)
        XCTAssertTrue(ambiguityReport.result.passed, ambiguityReport.result.reason)
        XCTAssertFalse(
            ambiguityReport.clarificationChips.isEmpty,
            "Expected Apple ambiguity to surface clarification chips."
        )

        let resumedTrace = driver.tapFirstClarificationChipAndWaitForResume(timeout: 15)
        XCTAssertEqual(
            resumedTrace?.turnClassification,
            "clarificationAnswer",
            "Expected a clarificationAnswer trace after tapping a chip. latestTrace=\(String(describing: driver.latestTrace())) chips=\(driver.clarificationChipTitles())"
        )
        XCTAssertNotEqual(resumedTrace?.selectedRoute, "shared_fallback")
        XCTAssertNotEqual(resumedTrace?.sharedPipelinePath, "legacy")

        reporter.attach(to: self)
    }

    func testMarinaAppSurfaceTypedClarificationReply_resumesWithoutLegacyFallback() throws {
        let app = XCUIApplication()
        let driver = MarinaUITestDriver(app: app, testCase: self)
        let reporter = MarinaAppSurfaceReporter()

        driver.launchHarness()

        let ambiguityReport = driver.runPrompt(
            "Show Groceries.",
            expectation: MarinaPromptExpectation(model: "Category", outcome: .clarification, responseShape: .clarification)
        )
        reporter.record(ambiguityReport)
        XCTAssertTrue(ambiguityReport.result.passed, ambiguityReport.result.reason)
        XCTAssertFalse(ambiguityReport.clarificationChips.isEmpty, "Expected Groceries ambiguity to surface clarification chips.")

        let resumedTrace = driver.typeClarificationReplyAndWaitForResume("category", timeout: 15)
        XCTAssertEqual(resumedTrace?.turnClassification, "clarificationAnswer")
        XCTAssertNotEqual(resumedTrace?.selectedRoute, "shared_fallback")
        XCTAssertNotEqual(resumedTrace?.sharedPipelinePath, "legacy")

        reporter.attach(to: self)
    }

    func testMarinaAppSurfaceExactChipTitleTypedReply_resumesWithoutLegacyFallback() throws {
        let app = XCUIApplication()
        let driver = MarinaUITestDriver(app: app, testCase: self)
        let reporter = MarinaAppSurfaceReporter()

        driver.launchHarness()

        let ambiguityReport = driver.runPrompt(
            "Tell me about Apple",
            expectation: MarinaPromptExpectation(model: "VariableExpense", outcome: .clarification, responseShape: .clarification)
        )
        reporter.record(ambiguityReport)
        XCTAssertTrue(ambiguityReport.result.passed, ambiguityReport.result.reason)
        guard let chipTitle = ambiguityReport.clarificationChips.first else {
            XCTFail("Expected Apple ambiguity to surface clarification chips.")
            return
        }

        let resumedTrace = driver.typeClarificationReplyAndWaitForResume(chipTitle, timeout: 15)
        XCTAssertEqual(resumedTrace?.turnClassification, "clarificationAnswer")
        XCTAssertNotEqual(resumedTrace?.selectedRoute, "shared_fallback")
        XCTAssertNotEqual(resumedTrace?.sharedPipelinePath, "legacy")

        reporter.attach(to: self)
    }

    func testMarinaAppSurfaceFollowUpCompareToLastMonth_anchorsTopCategory() throws {
        let app = XCUIApplication()
        let driver = MarinaUITestDriver(app: app, testCase: self)
        let reporter = MarinaAppSurfaceReporter()
        defer { reporter.attach(to: self) }

        driver.launchHarness()

        let rankedReport = driver.runPrompt(
            "Where did my money go this month?",
            expectation: MarinaPromptExpectation(model: "Category", outcome: .handled, responseShape: .rankedList)
        )
        reporter.record(rankedReport)
        XCTAssertTrue(rankedReport.result.passed, rankedReport.result.reason)
        guard let topCategory = rankedReport.visibleAnswer.topRowTitle else {
            XCTFail("Expected a top category row in the ranked answer. answer=\(rankedReport.visibleAnswer.text)")
            return
        }

        let comparisonReport = driver.runPrompt(
            "Compare to last month",
            expectation: MarinaPromptExpectation(model: "Category", outcome: .handled, responseShape: .comparison, requiredVisibleText: [topCategory])
        )
        reporter.record(comparisonReport)
        XCTAssertTrue(comparisonReport.result.passed, comparisonReport.result.reason)
        XCTAssertEqual(comparisonReport.turnClassification, "followUp")
        XCTAssertEqual(comparisonReport.priorContextUsed, true)
    }

    func testMarinaAppSurfaceStep5PhraseCapabilityBatches_renderDataBackedAnswers() throws {
        let app = XCUIApplication()
        let driver = MarinaUITestDriver(app: app, testCase: self)
        let reporter = MarinaAppSurfaceReporter()
        defer { reporter.attach(to: self) }

        driver.launchHarness()

        let prompts = [
            ModelPrompt(
                model: "BudgetCardLink",
                text: "Which cards are in May Budget?",
                shape: .relationshipList,
                requiredVisibleText: ["Apple Card", "Backup Card"],
                forbiddenVisibleText: ["Budget Summary", "Variable spend", "Planned spend"]
            ),
            ModelPrompt(
                model: "SavingsAccount",
                text: "How much have I saved?",
                shape: .summaryCard,
                requiredVisibleText: ["Savings"]
            ),
            ModelPrompt(
                model: "AllocationAccount",
                text: "What is my Roommate balance?",
                shape: .summaryCard,
                requiredVisibleText: ["Roommate"]
            ),
            ModelPrompt(
                model: "ExpenseAllocation",
                text: "Show allocations this month",
                shape: .rankedList,
                requiredVisibleText: ["Allocations"]
            )
        ]

        for prompt in prompts {
            let report = driver.runPrompt(prompt.text, expectation: prompt.expectation, timeout: 8)
            reporter.record(report)
            XCTAssertTrue(report.result.passed, report.result.reason)
            XCTAssertNotEqual(report.selectedRoute, "shared_fallback")
            XCTAssertNotEqual(report.trace?.sharedPipelinePath, "legacy")
        }
    }

    func testMarinaAppSurfaceStep5MutationPrompt_doesNotExecuteSharedReadApproximation() throws {
        let app = XCUIApplication()
        let driver = MarinaUITestDriver(app: app, testCase: self)
        let reporter = MarinaAppSurfaceReporter()
        defer { reporter.attach(to: self) }

        driver.launchHarness()

        let mutationReport = driver.runCommandOrUnsupportedPrompt(
            "create settlement with Roommate for $20",
            expectation: MarinaPromptExpectation(
                model: "AllocationSettlement",
                outcome: .typedUnsupported,
                responseShape: .unsupported
            ),
            timeout: 8
        )
        reporter.record(mutationReport)
        XCTAssertTrue(mutationReport.result.passed, mutationReport.result.reason)
        XCTAssertNotEqual(mutationReport.executorRoute?.localizedCaseInsensitiveContains("shared balances"), true)
        XCTAssertNotEqual(mutationReport.executorRoute?.localizedCaseInsensitiveContains("settlementRows"), true)

        let balanceReport = driver.runPrompt(
            "What is my Roommate balance?",
            expectation: MarinaPromptExpectation(
                model: "AllocationAccount",
                outcome: .handled,
                responseShape: .summaryCard,
                requiredVisibleText: ["Roommate"]
            ),
            timeout: 8
        )
        reporter.record(balanceReport)
        XCTAssertTrue(balanceReport.result.passed, balanceReport.result.reason)
    }

    func testMarinaFoundationModelToggle_isAvailableWithoutRuntimeLaunchArguments() throws {
        let app = XCUIApplication()
        let driver = MarinaUITestDriver(app: app, testCase: self)

        driver.launchHarness()

        let toggle = driver.foundationModelToggle()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Expected the Marina Foundation Model toggle to be visible.")
        XCTAssertEqual(toggle.value as? String, "Off")

        toggle.tap()
        XCTAssertTrue(
            ["On", "On, unavailable"].contains(toggle.value as? String),
            "Expected the Foundation Model toggle to report an enabled preference after tapping."
        )
    }

    private static let sequentialSmokePrompts: [ModelPrompt] = [
        ModelPrompt(model: "Workspace", text: "What workspace am I in?", shape: .summaryCard),
        ModelPrompt(model: "Budget", text: "What is my active budget?", shape: .summaryCard),
        ModelPrompt(model: "BudgetCategoryLimit", text: "Show my Groceries budget limit", shape: .summaryCard),
        ModelPrompt(model: "Card", text: "What did I spend on Apple Card this month?", shape: .scalarCurrency),
        ModelPrompt(
            model: "BudgetCardLink",
            text: "Which cards are linked to May Budget?",
            shape: .relationshipList,
            requiredVisibleText: ["Apple Card", "Backup Card"],
            forbiddenVisibleText: ["Budget Summary", "Variable spend", "Planned spend"]
        ),
        ModelPrompt(model: "Income", text: "What is my actual income this month?")
    ]

    private static let promptMatrix: [ModelPrompt] = [
        ModelPrompt(model: "Workspace", text: "What workspace am I in?", shape: .summaryCard),
        ModelPrompt(model: "Workspace", text: "Show my workspace summary", shape: .summaryCard),
        ModelPrompt(model: "Workspace", text: "Do I have any other workspaces?", requestShape: .objectInventoryList),
        ModelPrompt(model: "Budget", text: "What is my active budget?", shape: .summaryCard),
        ModelPrompt(model: "Budget", text: "Show May Budget", shape: .summaryCard),
        ModelPrompt(model: "Budget", text: "What budgets do I have this month?", requestShape: .objectInventoryList),
        ModelPrompt(model: "Budget", text: "List all my budgets", requestShape: .objectInventoryList, shape: .relationshipList),
        ModelPrompt(model: "BudgetCategoryLimit", text: "How much do I have left in Groceries?", shape: .summaryCard),
        ModelPrompt(model: "BudgetCategoryLimit", text: "Show my Groceries budget limit", shape: .summaryCard),
        ModelPrompt(model: "BudgetCategoryLimit", text: "Which categories are over budget?", shape: .rankedList),
        ModelPrompt(model: "Card", text: "What did I spend on Apple Card this month?", shape: .scalarCurrency),
        ModelPrompt(model: "Card", text: "Show my card balances", shape: .rankedList),
        ModelPrompt(model: "Card", text: "List expenses on Backup Card", shape: .rankedList),
        ModelPrompt(model: "Card", text: "Show all my cards", requestShape: .objectInventoryList, shape: .relationshipList, requiredVisibleText: ["Apple Card"]),
        ModelPrompt(model: "Card", text: "List all of my cards", requestShape: .objectInventoryList, shape: .relationshipList, requiredVisibleText: ["Apple Card"]),
        ModelPrompt(model: "Card", text: "What cards do I have?", requestShape: .objectInventoryList, shape: .relationshipList, requiredVisibleText: ["Apple Card"]),
        ModelPrompt(
            model: "BudgetCardLink",
            text: "Which cards are linked to May Budget?",
            shape: .relationshipList,
            requiredVisibleText: ["Apple Card", "Backup Card"],
            forbiddenVisibleText: ["Budget Summary", "Variable spend", "Planned spend"]
        ),
        ModelPrompt(
            model: "BudgetCardLink",
            text: "Is Apple Card included in this budget?",
            shape: .membershipStatus,
            requiredVisibleText: ["Included", "Apple Card"],
            forbiddenVisibleText: ["Budget Summary", "Variable spend", "Planned spend"]
        ),
        ModelPrompt(
            model: "BudgetPresetLink",
            text: "Which presets are linked to May Budget?",
            shape: .relationshipList,
            requiredVisibleText: ["Rent"],
            forbiddenVisibleText: ["Budget Summary", "Variable spend", "Planned spend"]
        ),
        ModelPrompt(
            model: "BudgetPresetLink",
            text: "Is Rent included in this budget?",
            shape: .membershipStatus,
            requiredVisibleText: ["Included", "Rent"],
            forbiddenVisibleText: ["Budget Summary", "Variable spend", "Planned spend"]
        ),
        ModelPrompt(model: "Category", text: "What did I spend on Groceries this month?"),
        ModelPrompt(model: "Category", text: "Show category spending this month"),
        ModelPrompt(model: "Category", text: "List expenses in Dining this week"),
        ModelPrompt(model: "Category", text: "List all my categories", requestShape: .objectInventoryList, shape: .relationshipList),
        ModelPrompt(model: "Preset", text: "Show my Rent preset"),
        ModelPrompt(model: "Preset", text: "What presets do I have?", requestShape: .objectInventoryList, shape: .relationshipList),
        ModelPrompt(model: "Preset", text: "Do I have presets due soon?"),
        ModelPrompt(model: "PlannedExpense", text: "What planned expenses are due this month?"),
        ModelPrompt(model: "PlannedExpense", text: "Show Rent planned expense"),
        ModelPrompt(model: "PlannedExpense", text: "What planned expenses are still unrecorded?"),
        ModelPrompt(model: "VariableExpense", text: "List expenses this week"),
        ModelPrompt(model: "VariableExpense", text: "Show my last 10 expenses"),
        ModelPrompt(model: "VariableExpense", text: "List my cannabis purchases"),
        ModelPrompt(model: "VariableExpense", text: "Spend at merchant \"NUG\" last 90 days"),
        ModelPrompt(model: "VariableExpense", text: "What did I spend this month?"),
        ModelPrompt(model: "AllocationAccount", text: "Show my Roommate reconciliation account"),
        ModelPrompt(model: "AllocationAccount", text: "What is my Roommate balance?", shape: .summaryCard),
        ModelPrompt(model: "AllocationAccount", text: "List reconciliation accounts", requestShape: .objectInventoryList, shape: .relationshipList),
        ModelPrompt(model: "ExpenseAllocation", text: "Which expenses are split with Roommate?"),
        ModelPrompt(model: "ExpenseAllocation", text: "Show allocations this month"),
        ModelPrompt(model: "ExpenseAllocation", text: "How much spending was allocated away?"),
        ModelPrompt(model: "AllocationSettlement", text: "Show Roommate settlements"),
        ModelPrompt(model: "AllocationSettlement", text: "What settlements happened this month?"),
        ModelPrompt(model: "AllocationSettlement", text: "When did Roommate last pay me back?"),
        ModelPrompt(model: "SavingsAccount", text: "Show my Emergency Fund"),
        ModelPrompt(model: "SavingsAccount", text: "How much do I have in savings?"),
        ModelPrompt(model: "SavingsAccount", text: "Show savings account details"),
        ModelPrompt(model: "SavingsAccount", text: "Show all my savings accounts", requestShape: .objectInventoryList, shape: .relationshipList),
        ModelPrompt(model: "SavingsLedgerEntry", text: "Show savings activity this month"),
        ModelPrompt(model: "SavingsLedgerEntry", text: "What savings adjustments happened this month?"),
        ModelPrompt(model: "SavingsLedgerEntry", text: "When was my last savings transfer?"),
        ModelPrompt(model: "ImportMerchantRule", text: "What import rule do I have for Whole Foods?"),
        ModelPrompt(model: "ImportMerchantRule", text: "Show learned merchant rules", requestShape: .objectInventoryList, shape: .relationshipList),
        ModelPrompt(model: "ImportMerchantRule", text: "What category does Whole Foods import as?"),
        ModelPrompt(model: "AssistantAliasRule", text: "What does food mean?"),
        ModelPrompt(model: "AssistantAliasRule", text: "Show my Marina aliases", requestShape: .objectInventoryList, shape: .relationshipList),
        ModelPrompt(model: "AssistantAliasRule", text: "Use food spending this month"),
        ModelPrompt(model: "IncomeSeries", text: "Show recurring income", requestShape: .objectInventoryList, shape: .relationshipList),
        ModelPrompt(model: "IncomeSeries", text: "What income repeats monthly?", requestShape: .objectInventoryList, shape: .relationshipList),
        ModelPrompt(model: "IncomeSeries", text: "Show my Salary income series"),
        ModelPrompt(model: "Income", text: "What is my actual income this month?"),
        ModelPrompt(model: "Income", text: "What is my income so far this month?"),
        ModelPrompt(model: "Income", text: "What planned income do I have this month?"),
        ModelPrompt(model: "Marina", text: "spend groceries Mar 2026 vs Mar 2025"),
        ModelPrompt(model: "Marina", text: "average groceries per week last quarter"),
        ModelPrompt(model: "Marina", text: "total spend card Amex Platinum in Q1 2026"),
        ModelPrompt(model: "Marina", text: "income from \"Acme Dental\" Jan-Mar 2026"),
        ModelPrompt(model: "Marina", text: "top 5 categories by spend last 30 days"),
        ModelPrompt(model: "Marina", text: "percent of spending that was groceries in April"),
        ModelPrompt(model: "Marina", text: "largest transaction this month"),
        ModelPrompt(model: "Marina", text: "median variable expense last year"),
        ModelPrompt(model: "Marina", text: "planned vs actual dining May 2026"),
        ModelPrompt(model: "Marina", text: "savings: actual vs target YTD"),
        ModelPrompt(model: "Marina", text: "total refunds last month"),
        ModelPrompt(model: "Marina", text: "spend at merchant \"Amazon\" last 90 days"),
        ModelPrompt(model: "Marina", text: "spend at merchants containing \"amazon\" last 90 days"),
        ModelPrompt(model: "Marina", text: "uncategorized spend this week"),
        ModelPrompt(model: "Marina", text: "average daily spend in March 2026"),
        ModelPrompt(model: "Marina", text: "rolling 7-day spend ending Apr 15, 2026"),
        ModelPrompt(model: "Marina", text: "card \"Visa - Blue\" share of spend in 2025"),
        ModelPrompt(model: "Marina", text: "income seasonality: Mar 2026 vs Mar 2025"),
        ModelPrompt(model: "Marina", text: "category groceries day-of-week average (last 12 weeks)"),
        ModelPrompt(model: "Marina", text: "budget \"Travel 2026\" remaining this month"),
        ModelPrompt(model: "Marina", text: "top merchants by count this quarter"),
        ModelPrompt(model: "Marina", text: "transactions over $250 in February"),
        ModelPrompt(model: "Marina", text: "first purchase of \"Litter Robot\" ever"),
        ModelPrompt(model: "Marina", text: "time to next planned expense for budget \"Home\""),
        ModelPrompt(model: "Marina", text: "workspace \"Personal\" total spend YTD vs \"Business\""),
        ModelPrompt(model: "Marina", text: "category \"Utilities\" month-over-month change (Apr -> May 2026)"),
        ModelPrompt(model: "Marina", text: "net cash flow last pay period"),
        ModelPrompt(model: "Marina", text: "average tip percentage dining last 60 days"),
        ModelPrompt(model: "Marina", text: "spend in \"Q2 2026 to date\" vs \"same days Q2 2025\""),
        ModelPrompt(model: "Marina", text: "number of transactions with note containing \"reconcile\""),
        ModelPrompt(model: "Marina", text: "card \"Cash\" vs \"Visa - Blue\" refunds YTD"),
        ModelPrompt(model: "Marina", text: "average planned expense slip (actual - planned) last quarter"),
        ModelPrompt(model: "Marina", text: "categories with zero spend last month"),
        ModelPrompt(model: "Marina", text: "top 3 categories by variance (planned vs actual) this month"),
        ModelPrompt(model: "Marina", text: "recurring merchants detected in May 2026"),
        ModelPrompt(model: "Marina", text: "total spend \"last weekend\""),
        ModelPrompt(model: "Marina", text: "budget \"Groceries Weekly\" over/under for week of May 11, 2026"),
        ModelPrompt(model: "Marina", text: "savings ledger entries between Apr 1-15, 2026"),
        ModelPrompt(model: "Marina", text: "forecast: average weekly spend next 4 weeks (baseline = last 8)")
    ]
}

private struct ModelPrompt {
    let model: String
    let text: String
    let outcome: MarinaPromptExpectation.Outcome
    let requestShape: MarinaPromptExpectation.RequestShape?
    let shape: MarinaPromptExpectation.ResponseShape?
    let requiredVisibleText: [String]
    let forbiddenVisibleText: [String]

    init(
        model: String,
        text: String,
        outcome: MarinaPromptExpectation.Outcome = .handled,
        requestShape: MarinaPromptExpectation.RequestShape? = nil,
        shape: MarinaPromptExpectation.ResponseShape? = nil,
        requiredVisibleText: [String] = [],
        forbiddenVisibleText: [String] = []
    ) {
        self.model = model
        self.text = text
        self.outcome = outcome
        self.requestShape = requestShape
        self.shape = shape
        self.requiredVisibleText = requiredVisibleText
        self.forbiddenVisibleText = forbiddenVisibleText
    }

    var expectation: MarinaPromptExpectation {
        MarinaPromptExpectation(
            model: model,
            outcome: outcome,
            requestShape: requestShape,
            responseShape: shape,
            requiredVisibleText: requiredVisibleText,
            forbiddenVisibleText: forbiddenVisibleText
        )
    }
}
