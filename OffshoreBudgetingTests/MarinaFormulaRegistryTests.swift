import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaFormulaRegistryTests {
    @Test func registryReportsSupportedAndUnsupportedFormulaCombinations() {
        let registry = MarinaFormulaRegistry(now: date(2026, 6, 15), calendar: calendar)

        #expect(registry.supports(measure: .savingsTotal, surface: .semantic(.savingsAccount)))
        #expect(registry.supports(measure: .reconciliationBalance, surface: .semantic(.reconciliationAccount)))
        #expect(registry.supports(measure: .remainingRoom, surface: .semantic(.budget), operation: .forecast))
        #expect(registry.supports(measure: .safeDailySpend, surface: .semantic(.budget), operation: .forecast))

        #expect(registry.supports(measure: .categoryAvailability, surface: .semantic(.category)) == false)
        #expect(registry.supports(measure: .burnRate, surface: .semantic(.budget)) == false)
        #expect(registry.supports(measure: .savingsTotal, surface: .semantic(.preset)) == false)
    }

    @Test func savingsTotalDelegatesToSavingsAccountServiceWithExplicitTarget() {
        let fixture = makeFixture()
        let registry = MarinaFormulaRegistry(now: date(2026, 6, 15), calendar: calendar)

        let result = registry.evaluate(
            request: formulaRequest(
                surface: .semantic(.savingsAccount),
                operation: .sum,
                measure: .savingsTotal,
                filters: [nameFilter("Emergency Fund")]
            ),
            snapshot: fixture.snapshot
        )

        let metric = requireMetric(result)
        #expect(metric.value == .money(300))
        #expect(metric.measure == .savingsTotal)
        #expect(metric.source == .savingsAccountService)
        #expect(metric.evidenceRows.map(\.displayName) == ["Emergency Fund"])
    }

    @Test func accountFormulaWithoutExplicitTargetReturnsTypedUnsupported() {
        let fixture = makeFixture()
        let registry = MarinaFormulaRegistry(now: date(2026, 6, 15), calendar: calendar)

        #expect(registry.evaluate(
            request: formulaRequest(surface: .semantic(.savingsAccount), operation: .sum, measure: .savingsTotal),
            snapshot: fixture.snapshot
        ) == .unsupported(.unresolvedEntity))

        #expect(registry.evaluate(
            request: formulaRequest(surface: .semantic(.reconciliationAccount), operation: .sum, measure: .reconciliationBalance),
            snapshot: fixture.snapshot
        ) == .unsupported(.unresolvedEntity))
    }

    @Test func reconciliationBalanceDelegatesToAllocationLedgerService() {
        let fixture = makeFixture()
        let registry = MarinaFormulaRegistry(now: date(2026, 6, 15), calendar: calendar)

        let allTime = requireMetric(registry.evaluate(
            request: formulaRequest(
                surface: .semantic(.reconciliationAccount),
                operation: .sum,
                measure: .reconciliationBalance,
                filters: [nameFilter("Roommate")]
            ),
            snapshot: fixture.snapshot
        ))
        let juneActivity = requireMetric(registry.evaluate(
            request: formulaRequest(
                surface: .semantic(.reconciliationAccount),
                operation: .sum,
                measure: .reconciliationBalance,
                dateRange: HomeQueryDateRange(startDate: date(2026, 6, 1), endDate: date(2026, 6, 30)),
                filters: [nameFilter("Roommate")]
            ),
            snapshot: fixture.snapshot
        ))

        #expect(allTime.value == .money(35))
        #expect(allTime.source == .allocationLedgerService)
        #expect(juneActivity.value == .money(40))
        #expect(juneActivity.source == .allocationLedgerService)
    }

    @Test func remainingRoomAndSafeDailySpendDelegateToSafeSpendCalculator() {
        let fixture = makeFixture()
        let registry = MarinaFormulaRegistry(now: date(2026, 6, 15), calendar: calendar)
        let range = HomeQueryDateRange(startDate: date(2026, 6, 1), endDate: date(2026, 6, 30))

        let remainingRoom = requireMetric(registry.evaluate(
            request: formulaRequest(
                surface: .semantic(.budget),
                operation: .forecast,
                measure: .remainingRoom,
                dateRange: range
            ),
            snapshot: fixture.snapshot
        ))
        let safeDailySpend = requireMetric(registry.evaluate(
            request: formulaRequest(
                surface: .semantic(.budget),
                operation: .forecast,
                measure: .safeDailySpend,
                dateRange: range
            ),
            snapshot: fixture.snapshot
        ))

        #expect(remainingRoom.value == .money(1_050))
        #expect(remainingRoom.source == .safeSpendTodayCalculator)
        #expect(safeDailySpend.value == .money(65.625))
        #expect(safeDailySpend.source == .safeSpendTodayCalculator)
        #expect(safeDailySpend.evidenceRows.map(\.displayName) == ["June"])
    }

    @Test func supportedFormulaMissingRequiredContextReturnsTypedUnsupported() {
        let fixture = makeFixture()
        let registry = MarinaFormulaRegistry(now: date(2026, 6, 15), calendar: calendar)

        #expect(registry.evaluate(
            request: formulaRequest(surface: .semantic(.budget), operation: .forecast, measure: .safeDailySpend),
            snapshot: fixture.snapshot
        ) == .unsupported(.missingDateField))
    }

    @Test func formulaRegistryDoesNotMutateSnapshotData() {
        let fixture = makeFixture()
        let registry = MarinaFormulaRegistry(now: date(2026, 6, 15), calendar: calendar)
        let originalSavingsTotal = fixture.emergency.total
        let originalSettlementCount = fixture.roommate.settlements?.count

        _ = registry.evaluate(
            request: formulaRequest(
                surface: .semantic(.savingsAccount),
                operation: .sum,
                measure: .savingsTotal,
                filters: [nameFilter("Emergency Fund")]
            ),
            snapshot: fixture.snapshot
        )
        _ = registry.evaluate(
            request: formulaRequest(
                surface: .semantic(.reconciliationAccount),
                operation: .sum,
                measure: .reconciliationBalance,
                filters: [nameFilter("Roommate")]
            ),
            snapshot: fixture.snapshot
        )

        #expect(fixture.emergency.total == originalSavingsTotal)
        #expect(fixture.roommate.settlements?.count == originalSettlementCount)
    }

    private func formulaRequest(
        surface: MarinaUniversalEntitySurface,
        operation: MarinaSemanticOperation,
        measure: MarinaSemanticMeasure,
        dateRange: HomeQueryDateRange? = nil,
        filters: [MarinaRowFilter] = []
    ) -> MarinaFormulaRequest {
        MarinaFormulaRequest(
            surface: surface,
            operation: operation,
            measure: measure,
            dateRange: dateRange,
            comparisonDateRange: nil,
            filters: filters,
            search: nil,
            groupBy: nil,
            limit: nil,
            whatIfAmount: nil
        )
    }

    private func nameFilter(_ name: String) -> MarinaRowFilter {
        MarinaRowFilter(target: .field(.name), operation: .equals, value: .text(name))
    }

    private func requireMetric(_ result: MarinaFormulaResult) -> MarinaFormulaMetric {
        guard case let .metric(metric) = result else {
            Issue.record("Expected formula metric, got \(result).")
            return MarinaFormulaMetric(value: .empty, evidenceRows: [], measure: .amount, source: .rowBackedFallback)
        }
        return metric
    }

    private func makeFixture() -> FormulaFixture {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let budget = Budget(name: "June", startDate: date(2026, 6, 1), endDate: date(2026, 6, 30), workspace: workspace)
        let card = Card(name: "Apple Card", theme: "ruby", effect: "plastic", workspace: workspace)
        let category = Offshore.Category(name: "General", hexColor: "#22C55E", workspace: workspace)

        let emergency = SavingsAccount(name: "Emergency Fund", total: 300, createdAt: date(2026, 1, 1), updatedAt: date(2026, 6, 1), workspace: workspace)
        let travelSavings = SavingsAccount(name: "Travel Savings", total: 200, createdAt: date(2026, 2, 1), updatedAt: date(2026, 6, 1), workspace: workspace)
        let roommate = AllocationAccount(name: "Roommate", hexColor: "#14B8A6", workspace: workspace)

        let incomeActual = Income(source: "Paycheck", amount: 1_000, date: date(2026, 6, 1), isPlanned: false, workspace: workspace)
        let incomePlanned = Income(source: "Bonus", amount: 500, date: date(2026, 6, 20), isPlanned: true, workspace: workspace)
        let consumedPlanned = PlannedExpense(title: "Rent", plannedAmount: 100, expenseDate: date(2026, 6, 10), workspace: workspace, card: card, category: category)
        let remainingPlanned = PlannedExpense(title: "Internet", plannedAmount: 200, expenseDate: date(2026, 6, 20), workspace: workspace, card: card, category: category)
        let variableExpense = VariableExpense(descriptionText: "Groceries", amount: 150, transactionDate: date(2026, 6, 14), workspace: workspace, card: card, category: category)
        let allocationExpense = VariableExpense(descriptionText: "Apple Store", amount: 90, transactionDate: date(2026, 6, 5), workspace: workspace, card: card, category: category)

        let allocation = ExpenseAllocation(allocatedAmount: 40, createdAt: date(2026, 6, 6), updatedAt: date(2026, 6, 6), workspace: workspace, account: roommate, expense: allocationExpense)
        let maySettlement = AllocationSettlement(date: date(2026, 5, 18), note: "May true-up", amount: 10, workspace: workspace, account: roommate)
        let juneSettlement = AllocationSettlement(date: date(2026, 6, 8), note: "Paid back", amount: -15, workspace: workspace, account: roommate)
        roommate.expenseAllocations = [allocation]
        roommate.settlements = [maySettlement, juneSettlement]

        let snapshot = MarinaWorkspaceSnapshot(
            workspace: workspace,
            budgets: [budget],
            cards: [card],
            categories: [category],
            presets: [],
            plannedExpenses: [consumedPlanned, remainingPlanned],
            variableExpenses: [variableExpense, allocationExpense],
            homePlannedExpenses: [consumedPlanned, remainingPlanned],
            homeCalculationPlannedExpenses: [consumedPlanned, remainingPlanned],
            homeCalculationVariableExpenses: [variableExpense],
            reconciliationAccounts: [roommate],
            expenseAllocations: [allocation],
            allocationSettlements: [maySettlement, juneSettlement],
            savingsAccounts: [emergency, travelSavings],
            savingsEntries: [],
            incomes: [incomeActual, incomePlanned]
        )

        return FormulaFixture(snapshot: snapshot, emergency: emergency, roommate: roommate)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        DateComponents(calendar: calendar, timeZone: TimeZone(secondsFromGMT: 0), year: year, month: month, day: day).date!
    }
}

private struct FormulaFixture {
    let snapshot: MarinaWorkspaceSnapshot
    let emergency: SavingsAccount
    let roommate: AllocationAccount
}
