import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct MarinaAggregationExecutorTests {
    @Test func executor_broadCategoryAndCardSpendReturnScalarResults() throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let executor = MarinaAggregationExecutor()
        let range = monthRange()

        let broad = executor.execute(try executable(MarinaAggregationPlan(operation: .sum, measure: .spend, dateRange: range)), provider: fixture.provider, now: date(2026, 5, 15))
        let category = executor.execute(try executable(MarinaAggregationPlan(operation: .sum, measure: .spend, targets: [target(.category, "Groceries")], dateRange: range)), provider: fixture.provider, now: date(2026, 5, 15))
        let card = executor.execute(try executable(MarinaAggregationPlan(operation: .sum, measure: .spend, targets: [target(.card, "Apple Card")], dateRange: range)), provider: fixture.provider, now: date(2026, 5, 15))

        assertScalar(broad, containsDigits: "600")
        assertScalar(category, containsDigits: "300")
        assertScalar(card, containsDigits: "500")
    }

    @Test func executor_incomeAverageReturnsScalarResult() throws {
        let fixture = try makeFixture()
        try fixture.seedIncomeData()
        let plan = MarinaAggregationPlan(
            operation: .average,
            measure: .income,
            dateRange: HomeQueryDateRange(startDate: date(2026, 1, 1), endDate: date(2026, 3, 31))
        )

        let result = MarinaAggregationExecutor().execute(try executable(plan), provider: fixture.provider, now: date(2026, 3, 20))

        assertScalar(result, containsDigits: "2200")
    }

    @Test func executor_comparisonPreservesPrimaryAndComparisonValues() throws {
        let fixture = try makeFixture()
        try fixture.seedComparisonData()
        let primary = HomeQueryDateRange(startDate: date(2026, 5, 1), endDate: date(2026, 5, 31))
        let comparison = HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30))
        let plan = MarinaAggregationPlan(
            operation: .compare,
            measure: .spend,
            targets: [target(.category, "Groceries")],
            dateRange: primary,
            comparisonDateRange: comparison,
            responseShape: .comparison
        )

        let result = MarinaAggregationExecutor().execute(try executable(plan), provider: fixture.provider, now: date(2026, 5, 15))

        guard case .comparison(let comparisonResult) = result else {
            Issue.record("Expected comparison result.")
            return
        }
        #expect(comparisonResult.primaryRenderedValue.filter(\.isNumber).contains("300"))
        #expect(comparisonResult.comparisonRenderedValue.filter(\.isNumber).contains("100"))
    }

    @Test func executor_rankedAndGroupedResultsPreserveRowsAndPercentages() throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let range = monthRange()
        let rankingPlan = MarinaAggregationPlan(
            operation: .rank,
            measure: .spend,
            dateRange: range,
            grouping: MarinaGroupingCandidate(dimension: .category),
            ranking: MarinaRankingCandidate(direction: .top, limit: 3),
            limit: 3,
            responseShape: .rankedList
        )
        let sharePlan = MarinaAggregationPlan(
            operation: .sum,
            measure: .categoryShare,
            dateRange: range,
            responseShape: .groupedBreakdown
        )
        let executor = MarinaAggregationExecutor()

        let ranking = executor.execute(try executable(rankingPlan), provider: fixture.provider, now: date(2026, 5, 15))
        let share = executor.execute(try executable(sharePlan), provider: fixture.provider, now: date(2026, 5, 15))

        guard case .rankedList(let ranked) = ranking else {
            Issue.record("Expected ranked list result.")
            return
        }
        #expect(ranked.rows.contains(where: { $0.label == "Groceries" }))

        guard case .groupedBreakdown(let grouped) = share else {
            Issue.record("Expected grouped breakdown result.")
            return
        }
        #expect(grouped.rows.contains(where: { $0.label == "Groceries" && $0.renderedValue.contains("%") && $0.percentage != nil }))
    }

    @Test func executor_unsupportedPlansReturnTypedUnsupported() throws {
        let fixture = try makeFixture()
        let simulation = MarinaPlanValidationOutcome.executable(
            MarinaAggregationPlan(operation: .simulate, measure: .remainingBudget)
        )
        let incomeTotal = MarinaPlanValidationOutcome.executable(
            MarinaAggregationPlan(operation: .sum, measure: .income)
        )
        let targetedAverage = MarinaPlanValidationOutcome.executable(
            MarinaAggregationPlan(operation: .average, measure: .spend, targets: [target(.category, "Groceries")])
        )
        let executor = MarinaAggregationExecutor()

        assertUnsupported(executor.execute(outcome: simulation, provider: fixture.provider))
        assertUnsupported(executor.execute(outcome: incomeTotal, provider: fixture.provider))
        assertUnsupported(executor.execute(outcome: targetedAverage, provider: fixture.provider))
    }

    private func executable(_ plan: MarinaAggregationPlan) throws -> MarinaExecutableAggregationPlan {
        switch MarinaAggregationPlanHomeQueryAdapter().executablePlan(from: plan) {
        case .success(let executable):
            return executable
        case .failure(let unsupported):
            throw TestFailure(message: unsupported.message)
        }
    }

    private func assertScalar(_ result: MarinaAggregationResult, containsDigits digits: String) {
        guard case .scalar(let scalar) = result else {
            Issue.record("Expected scalar result.")
            return
        }
        #expect((scalar.renderedValue ?? "").filter(\.isNumber).contains(digits))
    }

    private func assertUnsupported(_ result: MarinaAggregationResult) {
        guard case .unsupported = result else {
            Issue.record("Expected unsupported result.")
            return
        }
    }

    private func target(_ type: MarinaCandidateEntityTypeHint, _ name: String) -> MarinaResolvedAggregationTarget {
        MarinaResolvedAggregationTarget(role: .primaryTarget, entityType: type, displayName: name)
    }

    private func monthRange() -> HomeQueryDateRange {
        HomeQueryDateRange(startDate: date(2026, 5, 1), endDate: date(2026, 5, 31))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }

    private struct TestFailure: Error {
        let message: String
    }
}

@MainActor
struct MarinaPhase5Fixture {
    let context: ModelContext
    let workspace: Workspace
    let groceries: Offshore.Category
    let travel: Offshore.Category
    let appleCard: Card
    let backupCard: Card
    let provider: MarinaDataProvider

    func seedSpendData() throws {
        context.insert(PlannedExpense(title: "Groceries Plan", plannedAmount: 250, expenseDate: date(2026, 5, 5), workspace: workspace, card: appleCard, category: groceries))
        context.insert(VariableExpense(descriptionText: "Groceries Variable", amount: 50, transactionDate: date(2026, 5, 10), workspace: workspace, card: appleCard, category: groceries))
        context.insert(PlannedExpense(title: "Travel Plan", plannedAmount: 200, expenseDate: date(2026, 5, 7), workspace: workspace, card: appleCard, category: travel))
        context.insert(VariableExpense(descriptionText: "Travel Variable", amount: 100, transactionDate: date(2026, 5, 12), workspace: workspace, card: backupCard, category: travel))
        try context.save()
    }

    func seedComparisonData() throws {
        context.insert(PlannedExpense(title: "May Groceries", plannedAmount: 300, expenseDate: date(2026, 5, 5), workspace: workspace, card: appleCard, category: groceries))
        context.insert(PlannedExpense(title: "April Groceries", plannedAmount: 100, expenseDate: date(2026, 4, 5), workspace: workspace, card: appleCard, category: groceries))
        try context.save()
    }

    func seedIncomeData() throws {
        context.insert(Income(source: "Salary", amount: 2_000, date: date(2026, 1, 5), isPlanned: false, workspace: workspace))
        context.insert(Income(source: "Salary", amount: 2_200, date: date(2026, 2, 5), isPlanned: false, workspace: workspace))
        context.insert(Income(source: "Salary", amount: 2_400, date: date(2026, 3, 5), isPlanned: false, workspace: workspace))
        try context.save()
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }
}

@MainActor
func makeFixture() throws -> MarinaPhase5Fixture {
    let schema = Schema([
        Workspace.self,
        Budget.self,
        Card.self,
        BudgetCardLink.self,
        Offshore.Category.self,
        Preset.self,
        BudgetPresetLink.self,
        BudgetCategoryLimit.self,
        PlannedExpense.self,
        VariableExpense.self,
        AllocationAccount.self,
        ExpenseAllocation.self,
        AllocationSettlement.self,
        IncomeSeries.self,
        ImportMerchantRule.self,
        Income.self,
        SavingsAccount.self,
        SavingsLedgerEntry.self
    ])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: config)
    let context = ModelContext(container)
    let workspace = Workspace(name: "Phase 5 Workspace", hexColor: "#3B82F6")
    let groceries = Offshore.Category(name: "Groceries", hexColor: "#00AA00", workspace: workspace)
    let travel = Offshore.Category(name: "Travel", hexColor: "#0000AA", workspace: workspace)
    let appleCard = Card(name: "Apple Card", workspace: workspace)
    let backupCard = Card(name: "Backup Card", workspace: workspace)
    context.insert(workspace)
    context.insert(groceries)
    context.insert(travel)
    context.insert(appleCard)
    context.insert(backupCard)
    try context.save()

    return MarinaPhase5Fixture(
        context: context,
        workspace: workspace,
        groceries: groceries,
        travel: travel,
        appleCard: appleCard,
        backupCard: backupCard,
        provider: MarinaDataProvider(modelContext: context, workspaceID: workspace.id)
    )
}
