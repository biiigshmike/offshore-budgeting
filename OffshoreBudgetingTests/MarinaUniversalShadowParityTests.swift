import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaUniversalShadowParityTests {
    @Test func merchantVariableSpendMatchesLegacyExecutor() {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.merchantText],
            dateRangeToken: .currentMonth,
            textQuery: "Apple",
            expenseScope: .variable
        )

        expectMoneyParity(
            fixture.harness.legacyMoneyFact(from: fixture.harness.runLegacy(request: request, context: fixture.context())),
            fixture.harness.universalMoneyFact(from: fixture.harness.runUniversal(request: request, context: fixture.context())),
            scenario: "Merchant variable spend"
        )
    }

    @Test func categoryVariableSpendMatchesLegacyExecutor() {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.category],
            dateRangeToken: .currentPeriod,
            targetName: "Groceries",
            expenseScope: .variable
        )
        let context = fixture.context(ambientDateRange: fixture.currentPeriod)

        expectMoneyParity(
            fixture.harness.legacyMoneyFact(from: fixture.harness.runLegacy(request: request, context: context)),
            fixture.harness.universalMoneyFact(from: fixture.harness.runUniversal(request: request, context: context)),
            scenario: "Category variable spend"
        )
    }

    @Test func cardVariableSpendMatchesLegacyExecutor() {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.card],
            dateRangeToken: .currentMonth,
            targetName: "Apple Card",
            expenseScope: .variable
        )

        expectMoneyParity(
            fixture.harness.legacyMoneyFact(from: fixture.harness.runLegacy(request: request, context: fixture.context())),
            fixture.harness.universalMoneyFact(from: fixture.harness.runUniversal(request: request, context: fixture.context())),
            scenario: "Card variable spend"
        )
    }

    @Test func plannedExpenseSumMatchesLegacyExecutor() {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .plannedExpense,
            operation: .sum,
            measure: .budgetImpact,
            dateRangeToken: .currentMonth,
            expenseScope: .planned
        )

        expectMoneyParity(
            fixture.harness.legacyMoneyFact(from: fixture.harness.runLegacy(request: request, context: fixture.context())),
            fixture.harness.universalMoneyFact(from: fixture.harness.runUniversal(request: request, context: fixture.context())),
            scenario: "Planned expense sum"
        )
    }

    @Test func latestVariableExpenseRowMatchesLegacyExecutor() {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .variableExpense,
            operation: .last,
            measure: .budgetImpact,
            dateRangeToken: .currentMonth,
            expenseScope: .variable,
            shape: .metric
        )
        let legacy = fixture.harness.runLegacy(request: request, context: fixture.context())
        let universal = fixture.harness.runUniversal(request: request, context: fixture.context())

        expectRowParity(
            fixture.harness.legacyRowsFact(from: legacy),
            fixture.harness.universalRowsFact(from: universal, request: request),
            scenario: "Latest variable expense row"
        )
    }

    @Test func biggestVariableExpenseRowsMatchLegacyExecutorOrdering() {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .variableExpense,
            operation: .list,
            measure: .budgetImpact,
            dateRangeToken: .currentMonth,
            resultLimit: 3,
            sort: .amountDescending,
            expenseScope: .variable,
            shape: .list
        )
        let legacy = fixture.harness.runLegacy(request: request, context: fixture.context())
        let universal = fixture.harness.runUniversal(request: request, context: fixture.context())

        expectRowParity(
            fixture.harness.legacyRowsFact(from: legacy),
            fixture.harness.universalRowsFact(from: universal, request: request),
            scenario: "Biggest variable expense rows"
        )
    }

    @Test func nextPlannedExpenseRowMatchesLegacyExecutor() {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .plannedExpense,
            operation: .next,
            measure: .effectiveAmount,
            dateRangeToken: .nextSevenDays,
            expenseScope: .planned,
            shape: .metric
        )
        let legacy = fixture.harness.runLegacy(request: request, context: fixture.context())
        let universal = fixture.harness.runUniversal(request: request, context: fixture.context())

        expectRowParity(
            fixture.harness.legacyRowsFact(from: legacy),
            fixture.harness.universalRowsFact(from: universal, request: request),
            scenario: "Next planned expense row"
        )
    }

    @Test func unifiedExpenseGroupsByCategoryMatchLegacyExecutorFacts() {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .variableExpense,
            operation: .group,
            measure: .budgetImpact,
            dimensions: [.category],
            dateRangeToken: .currentMonth,
            expenseScope: .unified,
            shape: .list
        )
        let legacy = fixture.harness.runLegacy(request: request, context: fixture.context())
        let universal = fixture.harness.runUniversal(request: request, context: fixture.context())

        expectUnorderedGroupParity(
            fixture.harness.legacyGroupsFact(from: legacy),
            fixture.harness.universalGroupsFact(from: universal),
            scenario: "Unified expense category groups"
        )
    }

    @Test func unifiedExpenseGroupsByCardMatchManualFixtureMath() {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .variableExpense,
            operation: .group,
            measure: .budgetImpact,
            dimensions: [.card],
            dateRangeToken: .currentMonth,
            expenseScope: .unified,
            shape: .list
        )
        let universal = fixture.harness.runUniversal(request: request, context: fixture.context())

        expectUnorderedGroupParity(
            .groups([
                MarinaComparableGroup(displayName: "Apple Card", amount: 293, count: nil),
                MarinaComparableGroup(displayName: "Chase Card", amount: 1_520, count: nil)
            ]),
            fixture.harness.universalGroupsFact(from: universal),
            scenario: "Unified expense card groups manual fixture"
        )
    }

    @Test func incomeBySourceMatchesManualFixtureMath() {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .income,
            operation: .group,
            measure: .incomeAmount,
            dimensions: [.incomeSource],
            dateRangeToken: .currentPeriod,
            incomeState: .all,
            shape: .list
        )
        let context = fixture.context(ambientDateRange: fixture.currentPeriod)
        let universal = fixture.harness.runUniversal(request: request, context: context)

        expectUnorderedGroupParity(
            .groups([
                MarinaComparableGroup(displayName: "Freelance", amount: 650, count: nil),
                MarinaComparableGroup(displayName: "Paycheck", amount: 2_000, count: nil)
            ]),
            fixture.harness.universalGroupsFact(from: universal),
            scenario: "Income by source manual fixture"
        )
    }

    @Test func incomeTotalMatchesLegacyExecutor() {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .income,
            operation: .sum,
            measure: .incomeAmount,
            dateRangeToken: .currentPeriod,
            incomeState: .all
        )
        let context = fixture.context(ambientDateRange: fixture.currentPeriod)

        expectMoneyParity(
            fixture.harness.legacyMoneyFact(from: fixture.harness.runLegacy(request: request, context: context)),
            fixture.harness.universalMoneyFact(from: fixture.harness.runUniversal(request: request, context: context)),
            scenario: "Income total"
        )
    }

    @Test func explicitSavingsAccountTotalMatchesLegacyExecutor() {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .savingsAccount,
            operation: .sum,
            measure: .savingsTotal,
            dateRangeToken: .allTime,
            targetName: "Savings Account"
        )

        expectMoneyParity(
            fixture.harness.legacyMoneyFact(from: fixture.harness.runLegacy(request: request, context: fixture.context())),
            fixture.harness.universalMoneyFact(from: fixture.harness.runUniversal(request: request, context: fixture.context())),
            scenario: "Explicit savings account total"
        )
    }

    @Test func explicitReconciliationBalanceMatchesLegacyExecutor() {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .reconciliationAccount,
            operation: .sum,
            measure: .reconciliationBalance,
            dateRangeToken: .allTime,
            targetName: "Alejandro"
        )

        expectMoneyParity(
            fixture.harness.legacyMoneyFact(from: fixture.harness.runLegacy(request: request, context: fixture.context())),
            fixture.harness.universalMoneyFact(from: fixture.harness.runUniversal(request: request, context: fixture.context())),
            scenario: "Explicit reconciliation balance"
        )
    }

    @Test func remainingRoomFormulaMatchesLegacyExecutorTypedRow() {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .budget,
            operation: .forecast,
            measure: .remainingRoom,
            dateRangeToken: .currentMonth
        )

        expectMoneyParity(
            fixture.harness.legacyMoneyFact(from: fixture.harness.runLegacy(request: request, context: fixture.context()), selection: .first),
            fixture.harness.universalMoneyFact(from: fixture.harness.runUniversal(request: request, context: fixture.context())),
            scenario: "Remaining room formula"
        )
    }

    @Test func safeDailySpendFormulaMatchesLegacyExecutorTypedRow() {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .budget,
            operation: .forecast,
            measure: .safeDailySpend,
            dateRangeToken: .currentMonth
        )

        expectMoneyParity(
            fixture.harness.legacyMoneyFact(from: fixture.harness.runLegacy(request: request, context: fixture.context()), selection: .last),
            fixture.harness.universalMoneyFact(from: fixture.harness.runUniversal(request: request, context: fixture.context())),
            scenario: "Safe daily spend formula"
        )
    }

    @Test func budgetBurnRateFormulaMatchesLegacyExecutorTypedRow() {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .budget,
            operation: .average,
            measure: .burnRate,
            dateRangeToken: .currentMonth
        )

        expectMoneyParity(
            fixture.harness.legacyMoneyFact(from: fixture.harness.runLegacy(request: request, context: fixture.context()), selection: .last),
            fixture.harness.universalMoneyFact(from: fixture.harness.runUniversal(request: request, context: fixture.context())),
            scenario: "Budget burn rate formula"
        )
    }

    @Test func budgetProjectedSpendFormulaMatchesLegacyExecutorTypedRow() {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .budget,
            operation: .forecast,
            measure: .projectedSpend,
            dateRangeToken: .currentMonth
        )

        expectMoneyParity(
            fixture.harness.legacyMoneyFact(from: fixture.harness.runLegacy(request: request, context: fixture.context()), selection: .last),
            fixture.harness.universalMoneyFact(from: fixture.harness.runUniversal(request: request, context: fixture.context())),
            scenario: "Budget projected spend formula"
        )
    }

    @Test func budgetPaceDifferenceFormulaMatchesLegacyExecutorTypedRow() {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .budget,
            operation: .compare,
            measure: .paceDifference,
            dateRangeToken: .currentMonth,
            shape: .comparison
        )

        expectMoneyParity(
            fixture.harness.legacyMoneyFact(from: fixture.harness.runLegacy(request: request, context: fixture.context()), selection: .last),
            fixture.harness.universalMoneyFact(from: fixture.harness.runUniversal(request: request, context: fixture.context())),
            scenario: "Budget pace difference formula"
        )
    }

    @Test func budgetCoverageRatioFormulaMatchesLegacyExecutorTypedRow() {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .budget,
            operation: .forecast,
            measure: .coverageRatio,
            dateRangeToken: .currentMonth
        )

        expectMoneyParity(
            fixture.harness.legacyMoneyFact(from: fixture.harness.runLegacy(request: request, context: fixture.context()), selection: .index(2)),
            fixture.harness.universalMoneyFact(from: fixture.harness.runUniversal(request: request, context: fixture.context())),
            scenario: "Budget coverage ratio formula"
        )
    }

    @Test func incomeCoverageRatioFormulaMatchesLegacyExecutorTypedRow() {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .income,
            operation: .share,
            measure: .coverageRatio,
            dateRangeToken: .currentMonth
        )

        expectMoneyParity(
            fixture.harness.legacyMoneyFact(from: fixture.harness.runLegacy(request: request, context: fixture.context()), selection: .index(2)),
            fixture.harness.universalMoneyFact(from: fixture.harness.runUniversal(request: request, context: fixture.context())),
            scenario: "Income coverage ratio formula"
        )
    }

    private func makeFixture() -> MarinaUniversalShadowParityFixture {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let appleCard = Card(name: "Apple Card", theme: "ruby", effect: "plastic", workspace: workspace)
        let chaseCard = Card(name: "Chase Card", theme: "sky", effect: "matte", workspace: workspace)
        let groceries = Offshore.Category(name: "Groceries", hexColor: "#22C55E", workspace: workspace)
        let electronics = Offshore.Category(name: "Electronics", hexColor: "#0EA5E9", workspace: workspace)
        let budget = Budget(name: "June", startDate: date(2026, 6, 1), endDate: date(2026, 6, 30), workspace: workspace)
        let phonePreset = Preset(title: "Phone", plannedAmount: 80, workspace: workspace, defaultCard: appleCard, defaultCategory: electronics)

        let appleStoreJune = VariableExpense(
            descriptionText: "Apple Store",
            amount: 120,
            transactionDate: date(2026, 6, 5),
            workspace: workspace,
            card: appleCard,
            category: electronics
        )
        let appleMarketJune = VariableExpense(
            descriptionText: "Apple Market",
            amount: 18,
            transactionDate: date(2026, 6, 20),
            workspace: workspace,
            card: appleCard,
            category: groceries
        )
        let appleStoreMay = VariableExpense(
            descriptionText: "Apple Store",
            amount: 90,
            transactionDate: date(2026, 5, 15),
            workspace: workspace,
            card: appleCard,
            category: electronics
        )
        let krogerMay = VariableExpense(
            descriptionText: "Kroger",
            amount: 64,
            transactionDate: date(2026, 5, 10),
            workspace: workspace,
            card: chaseCard,
            category: groceries
        )
        let traderJoesMay = VariableExpense(
            descriptionText: "Trader Joe's",
            amount: 52,
            transactionDate: date(2026, 5, 20),
            workspace: workspace,
            card: chaseCard,
            category: groceries
        )
        let krogerJune = VariableExpense(
            descriptionText: "Kroger",
            amount: 30,
            transactionDate: date(2026, 6, 10),
            workspace: workspace,
            card: chaseCard,
            category: groceries
        )
        let bestBuyJune = VariableExpense(
            descriptionText: "Best Buy",
            amount: 300,
            transactionDate: date(2026, 6, 12),
            workspace: workspace,
            card: chaseCard,
            category: electronics
        )
        let coffeeJuly = VariableExpense(
            descriptionText: "Coffee Stand",
            amount: 9,
            transactionDate: date(2026, 7, 1),
            workspace: workspace,
            card: appleCard,
            category: nil
        )

        let oldPlan = PlannedExpense(
            title: "Old Plan",
            plannedAmount: 45,
            expenseDate: date(2026, 5, 3),
            workspace: workspace,
            card: chaseCard,
            category: groceries,
            sourceBudgetID: budget.id
        )
        let phoneBill = PlannedExpense(
            title: "Phone Bill",
            plannedAmount: 80,
            expenseDate: date(2026, 6, 16),
            workspace: workspace,
            card: appleCard,
            category: electronics,
            sourcePresetID: phonePreset.id,
            sourceBudgetID: budget.id
        )
        let internetBill = PlannedExpense(
            title: "Internet Bill",
            plannedAmount: 100,
            actualAmount: 75,
            expenseDate: date(2026, 6, 18),
            workspace: workspace,
            card: appleCard,
            category: electronics,
            sourceBudgetID: budget.id
        )
        let rent = PlannedExpense(
            title: "Rent",
            plannedAmount: 1_200,
            expenseDate: date(2026, 6, 25),
            workspace: workspace,
            card: chaseCard,
            category: nil,
            sourceBudgetID: budget.id
        )

        let actualPaycheck = Income(source: "Paycheck", amount: 2_000, date: date(2026, 6, 11), isPlanned: false, workspace: workspace, card: appleCard)
        let freelance = Income(source: "Freelance", amount: 650, date: date(2026, 6, 19), isPlanned: false, workspace: workspace, card: chaseCard)
        let plannedPaycheck = Income(source: "Paycheck", amount: 2_100, date: date(2026, 6, 25), isPlanned: true, workspace: workspace, card: appleCard)
        let previousPaycheck = Income(source: "Paycheck", amount: 1_900, date: date(2026, 5, 15), isPlanned: false, workspace: workspace, card: appleCard)

        let savings = SavingsAccount(name: "Savings Account", total: 1_000, workspace: workspace)
        let savingsAdjustment = SavingsLedgerEntry(
            date: date(2026, 6, 15),
            amount: 100,
            note: "Manual savings",
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
            workspace: workspace,
            account: savings
        )

        let alejandro = AllocationAccount(name: "Alejandro", workspace: workspace)
        let krogerAllocation = ExpenseAllocation(
            allocatedAmount: 10,
            preservesGrossAmount: true,
            workspace: workspace,
            account: alejandro,
            expense: krogerJune
        )
        let settlement = AllocationSettlement(
            date: date(2026, 6, 21),
            note: "Alejandro paid back",
            amount: -4,
            workspace: workspace,
            account: alejandro
        )
        krogerJune.allocation = krogerAllocation
        alejandro.expenseAllocations = [krogerAllocation]
        alejandro.settlements = [settlement]

        let variableExpenses = [
            appleStoreJune,
            appleMarketJune,
            appleStoreMay,
            krogerMay,
            traderJoesMay,
            krogerJune,
            bestBuyJune,
            coffeeJuly
        ]
        let plannedExpenses = [oldPlan, phoneBill, internetBill, rent]
        let incomes = [actualPaycheck, freelance, plannedPaycheck, previousPaycheck]
        let snapshot = MarinaWorkspaceSnapshot(
            workspace: workspace,
            budgets: [budget],
            cards: [appleCard, chaseCard],
            categories: [groceries, electronics],
            presets: [phonePreset],
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            homePlannedExpenses: plannedExpenses,
            homeCalculationPlannedExpenses: plannedExpenses,
            homeCalculationVariableExpenses: variableExpenses,
            reconciliationAccounts: [alejandro],
            expenseAllocations: [krogerAllocation],
            allocationSettlements: [settlement],
            savingsAccounts: [savings],
            savingsEntries: [savingsAdjustment],
            incomes: incomes
        )
        let fixture = MarinaUniversalShadowParityFixture(
            snapshot: snapshot,
            currentPeriod: HomeQueryDateRange(startDate: date(2026, 6, 10), endDate: date(2026, 6, 20)),
            now: date(2026, 6, 15),
            calendar: calendar
        )
        return fixture
    }

    private func semanticRequest(
        entity: MarinaSemanticEntity,
        operation: MarinaSemanticOperation,
        measure: MarinaSemanticMeasure? = nil,
        dimensions: [MarinaSemanticDimension] = [],
        dateRangeToken: MarinaSemanticDateRangeToken,
        targetName: String? = nil,
        textQuery: String? = nil,
        resultLimit: Int? = nil,
        sort: MarinaSemanticSort? = nil,
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
            resultLimit: resultLimit,
            sort: sort,
            expenseScope: expenseScope,
            incomeState: incomeState,
            expectedAnswerShape: shape
        )
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return calendar.date(from: components) ?? .distantPast
    }
}

@MainActor
private struct MarinaUniversalShadowParityFixture {
    let snapshot: MarinaWorkspaceSnapshot
    let currentPeriod: HomeQueryDateRange
    let now: Date
    let calendar: Calendar

    var harness: MarinaShadowParityHarness {
        MarinaShadowParityHarness(snapshot: snapshot, context: context())
    }

    func context(ambientDateRange: HomeQueryDateRange? = nil) -> MarinaUniversalPlanningContext {
        MarinaUniversalPlanningContext(
            ambientDateRange: ambientDateRange,
            defaultBudgetingPeriod: .monthly,
            now: now,
            calendar: calendar
        )
    }
}
