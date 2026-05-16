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
        ModelPrompt(model: "Workspace", text: "Do I have any other workspaces?", shape: .summaryCard),
        ModelPrompt(model: "Budget", text: "What is my active budget?", shape: .summaryCard),
        ModelPrompt(model: "Budget", text: "Show May Budget", shape: .summaryCard),
        ModelPrompt(model: "Budget", text: "What budgets do I have this month?", shape: .summaryCard),
        ModelPrompt(model: "BudgetCategoryLimit", text: "How much do I have left in Groceries?", shape: .summaryCard),
        ModelPrompt(model: "BudgetCategoryLimit", text: "Show my Groceries budget limit", shape: .summaryCard),
        ModelPrompt(model: "BudgetCategoryLimit", text: "Which categories are over budget?", shape: .rankedList),
        ModelPrompt(model: "Card", text: "What did I spend on Apple Card this month?", shape: .scalarCurrency),
        ModelPrompt(model: "Card", text: "Show my card balances", shape: .rankedList),
        ModelPrompt(model: "Card", text: "List expenses on Backup Card", shape: .rankedList),
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
        ModelPrompt(model: "Preset", text: "Show my Rent preset"),
        ModelPrompt(model: "Preset", text: "What presets do I have?"),
        ModelPrompt(model: "Preset", text: "Do I have presets due soon?"),
        ModelPrompt(model: "PlannedExpense", text: "What planned expenses are due this month?"),
        ModelPrompt(model: "PlannedExpense", text: "Show Rent planned expense"),
        ModelPrompt(model: "PlannedExpense", text: "What planned expenses are still unrecorded?"),
        ModelPrompt(model: "VariableExpense", text: "List expenses this week"),
        ModelPrompt(model: "VariableExpense", text: "Show my last 10 expenses"),
        ModelPrompt(model: "VariableExpense", text: "What did I spend this month?"),
        ModelPrompt(model: "AllocationAccount", text: "Show my Roommate reconciliation account"),
        ModelPrompt(model: "AllocationAccount", text: "What is my Roommate balance?"),
        ModelPrompt(model: "AllocationAccount", text: "List reconciliation accounts"),
        ModelPrompt(model: "ExpenseAllocation", text: "Which expenses are split with Roommate?"),
        ModelPrompt(model: "ExpenseAllocation", text: "Show allocations this month"),
        ModelPrompt(model: "ExpenseAllocation", text: "How much spending was allocated away?"),
        ModelPrompt(model: "AllocationSettlement", text: "Show Roommate settlements"),
        ModelPrompt(model: "AllocationSettlement", text: "What settlements happened this month?"),
        ModelPrompt(model: "AllocationSettlement", text: "When did Roommate last pay me back?"),
        ModelPrompt(model: "SavingsAccount", text: "Show my Emergency Fund"),
        ModelPrompt(model: "SavingsAccount", text: "How much do I have in savings?"),
        ModelPrompt(model: "SavingsAccount", text: "Show savings account details"),
        ModelPrompt(model: "SavingsLedgerEntry", text: "Show savings activity this month"),
        ModelPrompt(model: "SavingsLedgerEntry", text: "What savings adjustments happened this month?"),
        ModelPrompt(model: "SavingsLedgerEntry", text: "When was my last savings transfer?"),
        ModelPrompt(model: "ImportMerchantRule", text: "What import rule do I have for Whole Foods?"),
        ModelPrompt(model: "ImportMerchantRule", text: "Show learned merchant rules"),
        ModelPrompt(model: "ImportMerchantRule", text: "What category does Whole Foods import as?"),
        ModelPrompt(model: "AssistantAliasRule", text: "What does food mean?"),
        ModelPrompt(model: "AssistantAliasRule", text: "Show my Marina aliases"),
        ModelPrompt(model: "AssistantAliasRule", text: "Use food spending this month"),
        ModelPrompt(model: "IncomeSeries", text: "Show recurring income"),
        ModelPrompt(model: "IncomeSeries", text: "What income repeats monthly?"),
        ModelPrompt(model: "IncomeSeries", text: "Show my Salary income series"),
        ModelPrompt(model: "Income", text: "What is my actual income this month?"),
        ModelPrompt(model: "Income", text: "What is my income so far this month?"),
        ModelPrompt(model: "Income", text: "What planned income do I have this month?")
    ]
}

private struct ModelPrompt {
    let model: String
    let text: String
    let outcome: MarinaPromptExpectation.Outcome
    let shape: MarinaPromptExpectation.ResponseShape?
    let requiredVisibleText: [String]
    let forbiddenVisibleText: [String]

    init(
        model: String,
        text: String,
        outcome: MarinaPromptExpectation.Outcome = .handled,
        shape: MarinaPromptExpectation.ResponseShape? = nil,
        requiredVisibleText: [String] = [],
        forbiddenVisibleText: [String] = []
    ) {
        self.model = model
        self.text = text
        self.outcome = outcome
        self.shape = shape
        self.requiredVisibleText = requiredVisibleText
        self.forbiddenVisibleText = forbiddenVisibleText
    }

    var expectation: MarinaPromptExpectation {
        MarinaPromptExpectation(
            model: model,
            outcome: outcome,
            responseShape: shape,
            requiredVisibleText: requiredVisibleText,
            forbiddenVisibleText: forbiddenVisibleText
        )
    }
}
