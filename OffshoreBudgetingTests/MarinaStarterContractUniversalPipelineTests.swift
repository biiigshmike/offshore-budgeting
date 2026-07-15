import Foundation
import SwiftData
import Testing
@testable import Offshore

@Suite(.serialized)
@MainActor
struct MarinaStarterContractUniversalPipelineTests {
    @Test func everySharedStarterContractExecutesAgainstSeededWorkspaceThroughUniversalPipeline() async throws {
        let fixture = try makeFixture()
        let cases = try starterCases()
        #expect(cases.count == 8)
        #expect(Set(cases.map(\.id)).count == 8)

        let outcomes = Dictionary(uniqueKeysWithValues: cases.map { testCase in
            (
                testCase.prompt,
                MarinaInterpretedSemanticRequest(
                    request: request(for: testCase.contract),
                    confidence: .high,
                    source: .foundationModel,
                    diagnosticNotes: ["Injected shared starter contract."]
                )
            )
        })
        let brain = MarinaBrain(interpreter: StarterCatalogInterpreter(outcomes: outcomes))

        for testCase in cases {
            let seed = await brain.answerSeed(
                prompt: testCase.prompt,
                workspace: fixture.workspace,
                modelContext: fixture.context,
                ambientDateRange: fixture.currentRange,
                homeContext: MarinaPanelHomeContext(dateRange: fixture.currentRange),
                defaultBudgetingPeriod: .monthly,
                conversationContext: .empty,
                now: fixture.now
            )
            let trace = try #require(seed.debugTrace, "Missing trace for \(testCase.id.rawValue)")
            let expectedKind: HomeAnswerKind = testCase.contract.answerShape == .list ? .list : .metric

            #expect(trace.executionRoute == .universal, "Wrong route for \(testCase.id.rawValue)")
            #expect(trace.executionSucceeded, "Execution failed for \(testCase.id.rawValue)")
            #expect(trace.validatorAccepted, "Validation failed for \(testCase.id.rawValue)")
            #expect(seed.answer.kind == expectedKind, "Wrong answer kind for \(testCase.id.rawValue)")
            #expect(seed.answer.title.isEmpty == false, "Empty answer title for \(testCase.id.rawValue)")
            #expect(seed.answer.title != "I can't answer that yet", "Terminal answer for \(testCase.id.rawValue)")
            #expect(trace.evidenceRowSummaries.isEmpty == false, "Missing seeded evidence for \(testCase.id.rawValue)")
        }
    }

    private func starterCases() throws -> [StarterCase] {
        var cases = MarinaStarterPromptCatalog.baseEntries.map {
            StarterCase(id: $0.id, prompt: $0.defaultValue, contract: $0.contract)
        }
        let cardPrompt = MarinaStarterPromptCatalog.cardSummaryEntry.defaultValue
            .replacing("%@", with: "Evaluation Card")
        let cardMatch = try #require(MarinaStarterPromptCatalog.match(
            prompt: cardPrompt,
            localeIdentifier: "en"
        ))
        cases.append(StarterCase(id: .cardSummary, prompt: cardPrompt, contract: cardMatch.contract))
        return cases
    }

    private func request(for contract: MarinaStarterPromptCatalog.Contract) -> MarinaSemanticRequest {
        let targetName: String?
        let targetKindSource: MarinaSemanticTargetKindSource
        switch contract.target {
        case .absent:
            targetName = nil
            targetKindSource = .unspecified
        case let .named(name, _, source):
            targetName = name
            targetKindSource = source
        }

        return MarinaSemanticRequest(
            entity: contract.entity,
            operation: contract.operation,
            measure: contract.measure,
            projection: contract.projection,
            dimensions: contract.dimensions,
            dateRangeToken: contract.dateRange,
            dateRangeSource: contract.dateRangeSource,
            targetName: targetName,
            targetKindSource: targetKindSource,
            resultLimit: contract.resultLimit,
            sort: contract.sort,
            expenseScope: contract.expenseScope,
            incomeState: contract.incomeState,
            categoryAvailabilityFilter: contract.categoryAvailabilityFilter,
            expectedAnswerShape: contract.answerShape
        )
    }

    private func makeFixture() throws -> Fixture {
        let schema = Schema([
            Workspace.self,
            Budget.self,
            BudgetCategoryLimit.self,
            Card.self,
            BudgetCardLink.self,
            BudgetPresetLink.self,
            Category.self,
            Preset.self,
            PlannedExpense.self,
            VariableExpense.self,
            AllocationAccount.self,
            ExpenseAllocation.self,
            AllocationSettlement.self,
            SavingsAccount.self,
            SavingsLedgerEntry.self,
            ImportMerchantRule.self,
            AssistantAliasRule.self,
            MarinaChatSession.self,
            IncomeSeries.self,
            Income.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let now = try date(2026, 4, 20)
        let range = HomeQueryDateRange(
            startDate: try date(2026, 4, 1),
            endDate: try date(2026, 4, 30)
        )
        let workspace = Workspace(name: "Evaluation Workspace", hexColor: "#3B82F6")
        let card = Card(
            name: "Evaluation Card",
            theme: "ruby",
            effect: "plastic",
            workspace: workspace
        )
        let groceries = Category(name: "Groceries", hexColor: "#22C55E", workspace: workspace)
        let dining = Category(name: "Dining", hexColor: "#F97316", workspace: workspace)
        let housing = Category(name: "Housing", hexColor: "#8B5CF6", workspace: workspace)
        let budget = Budget(
            name: "April Evaluation Budget",
            startDate: range.startDate,
            endDate: range.endDate,
            workspace: workspace
        )

        let cardLink = BudgetCardLink(budget: budget, card: card)
        let groceriesLimit = BudgetCategoryLimit(maxAmount: 300, budget: budget, category: groceries)
        let diningLimit = BudgetCategoryLimit(maxAmount: 200, budget: budget, category: dining)
        let housingLimit = BudgetCategoryLimit(maxAmount: 1_200, budget: budget, category: housing)
        let groceriesExpense = VariableExpense(
            descriptionText: "Evaluation Groceries",
            amount: 120,
            transactionDate: try date(2026, 4, 8),
            workspace: workspace,
            card: card,
            category: groceries
        )
        let diningExpense = VariableExpense(
            descriptionText: "Evaluation Dining",
            amount: 80,
            transactionDate: try date(2026, 4, 12),
            workspace: workspace,
            card: card,
            category: dining
        )
        let rent = PlannedExpense(
            title: "Evaluation Rent",
            plannedAmount: 900,
            expenseDate: try date(2026, 4, 25),
            workspace: workspace,
            card: card,
            category: housing,
            sourceBudgetID: budget.id
        )
        let plannedIncome = Income(
            source: "Evaluation Salary",
            amount: 4_000,
            date: try date(2026, 4, 1),
            isPlanned: true,
            workspace: workspace,
            card: card
        )
        let actualIncome = Income(
            source: "Evaluation Salary",
            amount: 3_200,
            date: try date(2026, 4, 5),
            isPlanned: false,
            workspace: workspace,
            card: card
        )

        context.insert(workspace)
        context.insert(card)
        context.insert(groceries)
        context.insert(dining)
        context.insert(housing)
        context.insert(budget)
        context.insert(cardLink)
        context.insert(groceriesLimit)
        context.insert(diningLimit)
        context.insert(housingLimit)
        context.insert(groceriesExpense)
        context.insert(diningExpense)
        context.insert(rent)
        context.insert(plannedIncome)
        context.insert(actualIncome)

        let savings = SavingsAccount(name: "Evaluation Savings", total: 800, workspace: workspace)
        context.insert(savings)
        context.insert(SavingsLedgerEntry(
            date: try date(2026, 4, 2),
            amount: 800,
            note: "Evaluation opening balance",
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
            workspace: workspace,
            account: savings
        ))
        try context.save()

        return Fixture(context: context, workspace: workspace, currentRange: range, now: now)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try #require(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(year: year, month: month, day: day)
            )
        )
    }
}

private struct StarterCase {
    let id: MarinaStarterPromptCatalog.ID
    let prompt: String
    let contract: MarinaStarterPromptCatalog.Contract
}

private struct Fixture {
    let context: ModelContext
    let workspace: Workspace
    let currentRange: HomeQueryDateRange
    let now: Date
}

@MainActor
private final class StarterCatalogInterpreter: MarinaModelInterpreting {
    private let outcomes: [String: MarinaInterpretedSemanticRequest]

    init(outcomes: [String: MarinaInterpretedSemanticRequest]) {
        self.outcomes = outcomes
    }

    func interpretedSemanticRequest(
        for prompt: String,
        context: MarinaBrainContext
    ) async throws -> MarinaInterpretedSemanticRequest {
        try #require(outcomes[prompt])
    }
}
