import Foundation
import SwiftData
import Testing
@testable import Offshore

@Suite(.serialized)
@MainActor
struct MarinaBrainUniversalRoutingIntegrationTests {
    @Test func disabledUniversalRoutingMatchesDirectLegacyExecutorForSelectedScenarios() async throws {
        let fixture = try makeFixture()
        let brain = MarinaBrain(
            universalRoutingPolicyProvider: { .disabled }
        )
        let requests = [
            merchantSpendRequest(),
            categorySpendRequest(),
            incomeTotalRequest(),
            nextPlannedExpenseRequest(),
            safeDailySpendRequest()
        ]

        for request in requests {
            let answer = await brainAnswer(for: request, using: brain, fixture: fixture)
            let expected = try directLegacyResult(for: request, fixture: fixture)

            try expect(answer, matches: expected)
        }
    }

    @Test func enabledUniversalRoutingCanReturnUniversalForAllowlistedResolvedRequest() async throws {
        let fixture = try makeFixture()
        let brain = MarinaBrain(
            universalRoutingPolicyProvider: { .internalParityProven }
        )

        let answer = await brainAnswer(for: merchantSpendRequest(), using: brain, fixture: fixture)

        #expect(answer.kind == .metric)
        #expect(answer.title == "Spending")
        #expect(answer.rows.first?.title == "Value")
        #expect(answer.explanation?.contains("Universal routing") != true)
        #expect(answer.explanation?.contains("Scenario=") != true)
    }

    @Test func enabledUniversalRoutingFallsBackForNonAllowlistedResolvedRequest() async throws {
        let fixture = try makeFixture()
        let brain = MarinaBrain(
            universalRoutingPolicyProvider: { .internalParityProven }
        )
        let request = burnRateRequest()
        let answer = await brainAnswer(for: request, using: brain, fixture: fixture)
        let expected = try directLegacyResult(for: request, fixture: fixture)

        try expect(answer, matches: expected)
        #expect(answer.explanation?.contains("notAllowlisted") != true)
        #expect(answer.explanation?.contains("Universal routing") != true)
    }

    private func brainAnswer(
        for request: MarinaSemanticRequest,
        using brain: MarinaBrain,
        fixture: Fixture
    ) async -> HomeAnswer {
        let seed = await brain.answerSeed(
            resolvedRequest: request,
            prompt: "Resolved request",
            workspace: fixture.workspace,
            modelContext: fixture.context,
            ambientDateRange: fixture.currentRange,
            homeContext: MarinaPanelHomeContext(dateRange: fixture.currentRange),
            defaultBudgetingPeriod: .monthly,
            now: fixture.now
        )
        return seed.answer
    }

    private func directLegacyResult(
        for request: MarinaSemanticRequest,
        fixture: Fixture
    ) throws -> MarinaExecutionResult {
        let snapshot = try MarinaWorkspaceSnapshotProvider().snapshot(
            for: fixture.workspace,
            modelContext: fixture.context,
            homeContext: MarinaPanelHomeContext(dateRange: fixture.currentRange),
            now: fixture.now
        )
        let interpreted = MarinaInterpretedSemanticRequest(
            request: request,
            confidence: .high,
            source: .ruleBased,
            diagnosticNotes: ["Resolved from Marina clarification choice."]
        )
        let validated = MarinaSemanticRequestValidator().validate(
            interpreted: interpreted,
            snapshot: snapshot
        )
        let plan = MarinaQueryPlanner().plan(
            request: validated.request,
            ambientDateRange: fixture.currentRange,
            defaultBudgetingPeriod: .monthly,
            now: fixture.now,
            clarificationChoices: validated.clarificationChoices
        )
        return MarinaQueryExecutor().execute(plan: plan, snapshot: snapshot)
    }

    private func expect(_ answer: HomeAnswer, matches result: MarinaExecutionResult) throws {
        #expect(answer.kind == result.kind)
        #expect(answer.title == result.title)
        #expect(answer.subtitle == result.subtitle)
        #expect(answer.primaryValue == result.primaryValue)
        #expect(answer.attachment == result.attachment)
        #expect(answer.rows.count == result.rows.count)

        for (actual, expected) in zip(answer.rows, result.rows) {
            #expect(actual.title == expected.title)
            #expect(actual.value == expected.value)
            #expect(actual.sourceID == expected.sourceID)
            #expect(actual.objectType == expected.objectType)
            #expect(actual.amount == expected.amount)
            #expect(actual.date == expected.date)
            #expect(actual.role == expected.role)
        }
    }

    private func makeFixture() throws -> Fixture {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let appleCard = Card(name: "Apple Card", theme: "ruby", effect: "plastic", workspace: workspace)
        let chaseCard = Card(name: "Chase", theme: "sky", effect: "matte", workspace: workspace)
        let groceries = Offshore.Category(name: "Groceries", hexColor: "#22C55E", workspace: workspace)
        let bills = Offshore.Category(name: "Bills", hexColor: "#2563EB", workspace: workspace)
        let budget = Budget(
            name: "April 2026",
            startDate: date(2026, 4, 1),
            endDate: date(2026, 4, 30),
            workspace: workspace
        )
        let appleLink = BudgetCardLink(budget: budget, card: appleCard)
        let chaseLink = BudgetCardLink(budget: budget, card: chaseCard)
        budget.cardLinks = [appleLink, chaseLink]
        let billsLimit = BudgetCategoryLimit(minAmount: 0, maxAmount: 1_500, budget: budget, category: bills)
        budget.categoryLimits = [billsLimit]

        let rent = PlannedExpense(
            title: "Rent",
            plannedAmount: 1_200,
            expenseDate: date(2026, 4, 25),
            workspace: workspace,
            card: appleCard,
            category: bills,
            sourceBudgetID: budget.id
        )
        let phone = PlannedExpense(
            title: "Phone",
            plannedAmount: 90,
            expenseDate: date(2026, 4, 26),
            workspace: workspace,
            card: appleCard,
            category: bills,
            sourceBudgetID: budget.id
        )
        let appleStore = VariableExpense(
            descriptionText: "Apple Store",
            amount: 300,
            transactionDate: date(2026, 4, 13),
            workspace: workspace,
            card: chaseCard,
            category: bills
        )
        let appleMarket = VariableExpense(
            descriptionText: "Apple Market",
            amount: 25,
            transactionDate: date(2026, 4, 14),
            workspace: workspace,
            card: appleCard,
            category: groceries
        )
        let groceryRun = VariableExpense(
            descriptionText: "Grocery Run",
            amount: 80,
            transactionDate: date(2026, 4, 10),
            workspace: workspace,
            card: appleCard,
            category: groceries
        )
        let actualPaycheck = Income(
            source: "Paycheck",
            amount: 3_000,
            date: date(2026, 4, 1),
            isPlanned: false,
            workspace: workspace,
            card: appleCard
        )
        let plannedPaycheck = Income(
            source: "Paycheck",
            amount: 3_200,
            date: date(2026, 4, 1),
            isPlanned: true,
            workspace: workspace,
            card: appleCard
        )

        context.insert(workspace)
        context.insert(appleCard)
        context.insert(chaseCard)
        context.insert(groceries)
        context.insert(bills)
        context.insert(budget)
        context.insert(appleLink)
        context.insert(chaseLink)
        context.insert(billsLimit)
        context.insert(rent)
        context.insert(phone)
        context.insert(appleStore)
        context.insert(appleMarket)
        context.insert(groceryRun)
        context.insert(actualPaycheck)
        context.insert(plannedPaycheck)
        try context.save()

        return Fixture(
            context: context,
            workspace: workspace,
            currentRange: HomeQueryDateRange(
                startDate: date(2026, 4, 1),
                endDate: date(2026, 4, 30)
            ),
            now: date(2026, 4, 20)
        )
    }

    private func merchantSpendRequest() -> MarinaSemanticRequest {
        semanticRequest(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.merchantText],
            textQuery: "Apple",
            expenseScope: .variable
        )
    }

    private func categorySpendRequest() -> MarinaSemanticRequest {
        semanticRequest(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.category],
            targetName: "Groceries",
            expenseScope: .variable
        )
    }

    private func incomeTotalRequest() -> MarinaSemanticRequest {
        semanticRequest(
            entity: .income,
            operation: .sum,
            measure: .incomeAmount,
            incomeState: .all
        )
    }

    private func nextPlannedExpenseRequest() -> MarinaSemanticRequest {
        semanticRequest(
            entity: .plannedExpense,
            operation: .next,
            measure: .effectiveAmount,
            dateRangeToken: .nextSevenDays,
            expenseScope: .planned
        )
    }

    private func safeDailySpendRequest() -> MarinaSemanticRequest {
        semanticRequest(
            entity: .budget,
            operation: .forecast,
            measure: .safeDailySpend
        )
    }

    private func burnRateRequest() -> MarinaSemanticRequest {
        semanticRequest(
            entity: .budget,
            operation: .forecast,
            measure: .burnRate
        )
    }

    private func semanticRequest(
        entity: MarinaSemanticEntity,
        operation: MarinaSemanticOperation,
        measure: MarinaSemanticMeasure? = nil,
        dimensions: [MarinaSemanticDimension] = [],
        dateRangeToken: MarinaSemanticDateRangeToken = .currentMonth,
        targetName: String? = nil,
        textQuery: String? = nil,
        expenseScope: MarinaSemanticExpenseScope? = nil,
        incomeState: MarinaSemanticIncomeState? = nil,
        shape: MarinaSemanticAnswerShape = .metric
    ) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: entity,
            operation: operation,
            measure: measure,
            dimensions: dimensions,
            dateRangeToken: dateRangeToken,
            targetName: targetName,
            textQuery: textQuery,
            expenseScope: expenseScope,
            incomeState: incomeState,
            expectedAnswerShape: shape
        )
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

private struct Fixture {
    let context: ModelContext
    let workspace: Workspace
    let currentRange: HomeQueryDateRange
    let now: Date
}
