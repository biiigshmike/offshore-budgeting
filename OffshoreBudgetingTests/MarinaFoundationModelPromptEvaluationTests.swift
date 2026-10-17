import Foundation
import SwiftData
import Testing
@testable import Offshore

#if canImport(FoundationModels)
import FoundationModels
#endif

@Suite(.serialized)
@MainActor
struct MarinaFoundationModelPromptEvaluationTests {
    private static let optInKey = "debug_marinaRunFoundationModelEvaluation"

    @Test func foundationModelPromptEvaluation_isOptInAndSeparatedFromCI() async throws {
        guard DebugFeatureFlagResolver.isEnabled(key: Self.optInKey, fallback: false) else {
            return
        }

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            return
        }

        let model = SystemLanguageModel(useCase: .general, guardrails: .default)
        guard model.isAvailable else {
            return
        }

        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        context.insert(workspace)
        let brainContext = MarinaBrainContext(
            workspace: workspace,
            modelContext: context,
            ambientDateRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30)),
            defaultBudgetingPeriod: .monthly,
            now: date(2026, 4, 20)
        )

        let interpreter = MarinaFoundationModelsInterpreter()
        let interpreted = try await interpreter.interpretedSemanticRequest(
            for: "What is my Apple Card spend this month?",
            context: brainContext
        )

        #expect(interpreted.source == .foundationModel)
        #expect(interpreted.request.entity == .card)
        #expect(interpreted.request.operation == .sum)
        #expect(interpreted.request.measure == .budgetImpact)

        let plan = MarinaQueryPlan(
            id: UUID(),
            semanticRequest: MarinaSemanticRequest(
                entity: .card,
                operation: .sum,
                measure: .budgetImpact,
                targetName: "Apple Card",
                expectedAnswerShape: .metric
            ),
            dateRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30)),
            comparisonDateRange: nil,
            now: date(2026, 4, 20)
        )
        let insightContext = MarinaInsightContext(
            prompt: "What is my Apple Card spend this month?",
            result: MarinaExecutionResult(
                kind: .metric,
                title: "Apple Card Spend",
                subtitle: "Apr 1, 2026 - Apr 30, 2026",
                primaryValue: "$120.00",
                rows: [
                    HomeAnswerRow(title: "Planned", value: "$90.00"),
                    HomeAnswerRow(title: "Variable", value: "$30.00")
                ]
            ),
            plan: plan
        )
        let insight = await MarinaFoundationModelsInsightRuntime().generateNarration(for: insightContext)
        #expect(insight?.isEmpty == false)
        #else
        return
        #endif
    }

    private func makeContext() throws -> ModelContext {
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

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        return ModelContext(container)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
