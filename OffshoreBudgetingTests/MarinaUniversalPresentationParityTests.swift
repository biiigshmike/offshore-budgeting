import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaUniversalPresentationParityTests {
    @Test func merchantVariableSpendPresentationMatchesLegacyFacts() {
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
        let legacy = fixture.harness.runLegacy(request: request, context: fixture.context())
        let presented = fixture.presentedResult(request: request, context: fixture.context())

        expectMoneyParity(
            fixture.harness.legacyMoneyFact(from: legacy),
            fixture.harness.legacyMoneyFact(from: presented),
            scenario: "Merchant variable spend presentation"
        )
    }

    @Test func categoryVariableSpendPresentationMatchesLegacyFacts() {
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
        let legacy = fixture.harness.runLegacy(request: request, context: context)
        let presented = fixture.presentedResult(request: request, context: context)

        expectMoneyParity(
            fixture.harness.legacyMoneyFact(from: legacy),
            fixture.harness.legacyMoneyFact(from: presented),
            scenario: "Category variable spend presentation"
        )
    }

    @Test func cardVariableSpendPresentationMatchesLegacyFacts() {
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
        let legacy = fixture.harness.runLegacy(request: request, context: fixture.context())
        let presented = fixture.presentedResult(request: request, context: fixture.context())

        expectMoneyParity(
            fixture.harness.legacyMoneyFact(from: legacy),
            fixture.harness.legacyMoneyFact(from: presented),
            scenario: "Card variable spend presentation"
        )
    }

    @Test func plannedExpenseSumPresentationMatchesLegacyFacts() {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .plannedExpense,
            operation: .sum,
            measure: .budgetImpact,
            dateRangeToken: .currentMonth,
            expenseScope: .planned
        )
        let legacy = fixture.harness.runLegacy(request: request, context: fixture.context())
        let presented = fixture.presentedResult(request: request, context: fixture.context())

        expectMoneyParity(
            fixture.harness.legacyMoneyFact(from: legacy),
            fixture.harness.legacyMoneyFact(from: presented),
            scenario: "Planned expense sum presentation"
        )
    }

    @Test func latestVariableExpensePresentationMatchesLegacyFacts() {
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
        let presented = fixture.presentedResult(request: request, context: fixture.context())

        expectRowParity(
            fixture.harness.legacyRowsFact(from: legacy),
            fixture.harness.legacyRowsFact(from: presented),
            scenario: "Latest variable expense presentation"
        )
    }

    @Test func biggestVariableExpenseRowsPresentationMatchesLegacyFacts() {
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
        let presented = fixture.presentedResult(request: request, context: fixture.context())

        expectRowParity(
            fixture.harness.legacyRowsFact(from: legacy),
            fixture.harness.legacyRowsFact(from: presented),
            scenario: "Biggest variable expense rows presentation"
        )
    }

    @Test func nextPlannedExpensePresentationMatchesLegacyFacts() {
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
        let presented = fixture.presentedResult(request: request, context: fixture.context())

        expectRowParity(
            fixture.harness.legacyRowsFact(from: legacy),
            fixture.harness.legacyRowsFact(from: presented),
            scenario: "Next planned expense presentation"
        )
    }

    @Test func incomeTotalPresentationMatchesLegacyFacts() {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .income,
            operation: .sum,
            measure: .incomeAmount,
            dateRangeToken: .currentPeriod,
            incomeState: .all
        )
        let context = fixture.context(ambientDateRange: fixture.currentPeriod)
        let legacy = fixture.harness.runLegacy(request: request, context: context)
        let presented = fixture.presentedResult(request: request, context: context)

        expectMoneyParity(
            fixture.harness.legacyMoneyFact(from: legacy),
            fixture.harness.legacyMoneyFact(from: presented),
            scenario: "Income total presentation"
        )
    }

    @Test func savingsTotalPresentationMatchesLegacyFacts() {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .savingsAccount,
            operation: .sum,
            measure: .savingsTotal,
            dateRangeToken: .allTime,
            targetName: "Savings Account"
        )
        let legacy = fixture.harness.runLegacy(request: request, context: fixture.context())
        let presented = fixture.presentedResult(request: request, context: fixture.context())

        expectMoneyParity(
            fixture.harness.legacyMoneyFact(from: legacy),
            fixture.harness.legacyMoneyFact(from: presented),
            scenario: "Savings total presentation"
        )
    }

    @Test func reconciliationBalancePresentationMatchesLegacyFacts() {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .reconciliationAccount,
            operation: .sum,
            measure: .reconciliationBalance,
            dateRangeToken: .allTime,
            targetName: "Alejandro"
        )
        let legacy = fixture.harness.runLegacy(request: request, context: fixture.context())
        let presented = fixture.presentedResult(request: request, context: fixture.context())

        expectMoneyParity(
            fixture.harness.legacyMoneyFact(from: legacy),
            fixture.harness.legacyMoneyFact(from: presented),
            scenario: "Reconciliation balance presentation"
        )
    }

    @Test func remainingRoomPresentationMatchesLegacyTypedRowFact() {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .budget,
            operation: .forecast,
            measure: .remainingRoom,
            dateRangeToken: .currentMonth
        )
        let legacy = fixture.harness.runLegacy(request: request, context: fixture.context())
        let presented = fixture.presentedResult(request: request, context: fixture.context())

        expectMoneyParity(
            fixture.harness.legacyMoneyFact(from: legacy, selection: .first),
            fixture.harness.legacyMoneyFact(from: presented),
            scenario: "Remaining room presentation"
        )
    }

    @Test func safeDailySpendPresentationMatchesLegacyTypedRowFact() {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .budget,
            operation: .forecast,
            measure: .safeDailySpend,
            dateRangeToken: .currentMonth
        )
        let legacy = fixture.harness.runLegacy(request: request, context: fixture.context())
        let presented = fixture.presentedResult(request: request, context: fixture.context())

        expectMoneyParity(
            fixture.harness.legacyMoneyFact(from: legacy, selection: .last),
            fixture.harness.legacyMoneyFact(from: presented),
            scenario: "Safe daily spend presentation"
        )
    }

    @Test func budgetBurnRatePresentationMatchesLegacyFormulaRows() throws {
        try expectFormulaPresentationParity(
            request: semanticRequest(
                entity: .budget,
                operation: .average,
                measure: .burnRate,
                dateRangeToken: .currentMonth
            ),
            rowTitle: "Average per day"
        )
    }

    @Test func budgetProjectedSpendPresentationMatchesLegacyFormulaRows() throws {
        try expectFormulaPresentationParity(
            request: semanticRequest(
                entity: .budget,
                operation: .forecast,
                measure: .projectedSpend,
                dateRangeToken: .currentMonth
            ),
            rowTitle: "Projected total"
        )
    }

    @Test func budgetPaceDifferencePresentationMatchesLegacyFormulaRows() throws {
        try expectFormulaPresentationParity(
            request: semanticRequest(
                entity: .budget,
                operation: .compare,
                measure: .paceDifference,
                dateRangeToken: .currentMonth,
                shape: .comparison
            ),
            rowTitle: "Pace difference"
        )
    }

    @Test func budgetCoverageRatioPresentationMatchesLegacyFormulaRows() throws {
        try expectFormulaPresentationParity(
            request: semanticRequest(
                entity: .budget,
                operation: .forecast,
                measure: .coverageRatio,
                dateRangeToken: .currentMonth
            ),
            rowTitle: "Coverage percent"
        )
    }

    @Test func incomeCoverageRatioPresentationMatchesLegacyFormulaRows() throws {
        try expectFormulaPresentationParity(
            request: semanticRequest(
                entity: .income,
                operation: .share,
                measure: .coverageRatio,
                dateRangeToken: .currentMonth
            ),
            rowTitle: "Coverage percent"
        )
    }

    @Test func categoryAvailabilityPresentationMatchesLegacyFormulaRows() {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .category,
            operation: .forecast,
            measure: .categoryAvailability,
            dateRangeToken: .currentMonth
        )
        let legacy = fixture.harness.runLegacy(request: request, context: fixture.context())
        let presented = fixture.presentedResult(request: request, context: fixture.context())

        #expect(presented.kind == legacy.kind)
        #expect(presented.title == legacy.title)
        #expect(presented.primaryValue == legacy.primaryValue)
        #expect(presented.rows.first(where: { $0.title == "Over" })?.value == legacy.rows.first(where: { $0.title == "Over" })?.value)
        #expect(presented.rows.first(where: { $0.title == "Near" })?.value == legacy.rows.first(where: { $0.title == "Near" })?.value)
        #expect(presented.rows.first(where: { $0.title == "Categories" })?.value == legacy.rows.first(where: { $0.title == "Categories" })?.value)
        expectNoDebugText(in: presented)
    }

    @Test func categoryConcentrationPresentationMatchesLegacyFormulaRows() throws {
        try expectFormulaPresentationParity(
            request: semanticRequest(
                entity: .category,
                operation: .share,
                measure: .concentration,
                dateRangeToken: .currentMonth
            ),
            rowTitle: "Concentration"
        )
    }

    @Test func recurringBurdenPresentationMatchesLegacyFormulaRows() throws {
        try expectFormulaPresentationParity(
            request: semanticRequest(
                entity: .preset,
                operation: .sum,
                measure: .recurringBurden,
                dateRangeToken: .currentMonth
            ),
            rowTitle: "Recurring burden"
        )
    }

    @Test func forecastSavingsPresentationMatchesLegacyFormulaRows() {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .savingsAccount,
            operation: .forecast,
            measure: .savingsTotal,
            dateRangeToken: .currentMonth
        )
        let legacy = fixture.harness.runLegacy(request: request, context: fixture.context())
        let presented = fixture.presentedResult(request: request, context: fixture.context())

        #expect(presented.kind == legacy.kind)
        #expect(presented.title == legacy.title)
        #expect(presented.primaryValue == legacy.primaryValue)
        #expect(presented.rows.first(where: { $0.title == "Projected savings" })?.value == legacy.rows.first(where: { $0.title == "Projected savings" })?.value)
        #expect(presented.rows.first(where: { $0.title == "Actual savings" })?.value == legacy.rows.first(where: { $0.title == "Actual savings" })?.value)
        #expect(presented.rows.first(where: { $0.title == "Gap to projected" })?.value == legacy.rows.first(where: { $0.title == "Gap to projected" })?.value)
        #expect(presented.rows.first(where: { $0.title == "Status" })?.value == legacy.rows.first(where: { $0.title == "Status" })?.value)
        expectNoDebugText(in: presented)
    }

    @Test func unifiedCategoryGroupPresentationKeepsUniversalShape() {
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
        let presented = fixture.presentedResult(request: request, context: fixture.context())
        let rows = presented.rows.sorted { $0.title < $1.title }

        #expect(presented.kind == .list)
        #expect(rows.map(\.title) == ["Electronics", "Groceries", "Uncategorized"])
        #expect(rows.map(\.amount) == [575, 38, 1_200])
    }

    @Test func incomeBySourcePresentationMatchesManualFixtureMath() {
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
        let presented = fixture.presentedResult(request: request, context: fixture.context(ambientDateRange: fixture.currentPeriod))
        let rows = presented.rows.sorted { $0.title < $1.title }

        #expect(presented.kind == .list)
        #expect(presented.title == "Income by Source")
        #expect(rows.map(\.title) == ["Freelance", "Paycheck"])
        #expect(rows.map(\.amount) == [650, 2_000])
        expectNoDebugText(in: presented)
    }

    @Test func unifiedCardGroupPresentationMatchesManualFixtureMathAndUnassignedRows() {
        let fixture = makeCardGroupFixture()
        let request = semanticRequest(
            entity: .variableExpense,
            operation: .group,
            measure: .budgetImpact,
            dimensions: [.card],
            dateRangeToken: .currentMonth,
            expenseScope: .unified,
            shape: .list
        )
        let presented = fixture.presentedResult(request: request, context: fixture.context())
        let rows = presented.rows.sorted { $0.title < $1.title }

        #expect(presented.kind == .list)
        #expect(presented.title == "Spending by Card")
        #expect(rows.map(\.title) == ["Apple Card", "Chase Card", "Unassigned"])
        #expect(rows.map(\.amount) == [200, 30, 107])
        expectNoDebugText(in: presented)
    }

    private func expectFormulaPresentationParity(
        request: MarinaSemanticRequest,
        rowTitle: String
    ) throws {
        let fixture = makeFixture()
        let legacy = fixture.harness.runLegacy(request: request, context: fixture.context())
        let presented = fixture.presentedResult(request: request, context: fixture.context())

        #expect(presented.kind == legacy.kind)
        #expect(presented.title == legacy.title)
        #expect(presented.primaryValue == legacy.primaryValue)
        #expect(presented.rows.first(where: { $0.title == rowTitle })?.amount == legacy.rows.first(where: { $0.title == rowTitle })?.amount)
        expectNoDebugText(in: presented)
    }

    private func makeFixture() -> MarinaUniversalPresentationParityFixture {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let appleCard = Card(name: "Apple Card", theme: "ruby", effect: "plastic", workspace: workspace)
        let chaseCard = Card(name: "Chase Card", theme: "sky", effect: "matte", workspace: workspace)
        let groceries = Offshore.Category(name: "Groceries", hexColor: "#22C55E", workspace: workspace)
        let electronics = Offshore.Category(name: "Electronics", hexColor: "#0EA5E9", workspace: workspace)
        let budget = Budget(name: "June", startDate: date(2026, 6, 1), endDate: date(2026, 6, 30), workspace: workspace)
        let phonePreset = Preset(title: "Phone", plannedAmount: 80, workspace: workspace, defaultCard: appleCard, defaultCategory: electronics)

        let appleStoreJune = VariableExpense(descriptionText: "Apple Store", amount: 120, transactionDate: date(2026, 6, 5), workspace: workspace, card: appleCard, category: electronics)
        let appleMarketJune = VariableExpense(descriptionText: "Apple Market", amount: 18, transactionDate: date(2026, 6, 20), workspace: workspace, card: appleCard, category: groceries)
        let appleStoreMay = VariableExpense(descriptionText: "Apple Store", amount: 90, transactionDate: date(2026, 5, 15), workspace: workspace, card: appleCard, category: electronics)
        let krogerMay = VariableExpense(descriptionText: "Kroger", amount: 64, transactionDate: date(2026, 5, 10), workspace: workspace, card: chaseCard, category: groceries)
        let traderJoesMay = VariableExpense(descriptionText: "Trader Joe's", amount: 52, transactionDate: date(2026, 5, 20), workspace: workspace, card: chaseCard, category: groceries)
        let krogerJune = VariableExpense(descriptionText: "Kroger", amount: 30, transactionDate: date(2026, 6, 10), workspace: workspace, card: chaseCard, category: groceries)
        let bestBuyJune = VariableExpense(descriptionText: "Best Buy", amount: 300, transactionDate: date(2026, 6, 12), workspace: workspace, card: chaseCard, category: electronics)
        let coffeeJuly = VariableExpense(descriptionText: "Coffee Stand", amount: 9, transactionDate: date(2026, 7, 1), workspace: workspace, card: appleCard, category: nil)

        let oldPlan = PlannedExpense(title: "Old Plan", plannedAmount: 45, expenseDate: date(2026, 5, 3), workspace: workspace, card: chaseCard, category: groceries, sourceBudgetID: budget.id)
        let phoneBill = PlannedExpense(title: "Phone Bill", plannedAmount: 80, expenseDate: date(2026, 6, 16), workspace: workspace, card: appleCard, category: electronics, sourcePresetID: phonePreset.id, sourceBudgetID: budget.id)
        let internetBill = PlannedExpense(title: "Internet Bill", plannedAmount: 100, actualAmount: 75, expenseDate: date(2026, 6, 18), workspace: workspace, card: appleCard, category: electronics, sourceBudgetID: budget.id)
        let rent = PlannedExpense(title: "Rent", plannedAmount: 1_200, expenseDate: date(2026, 6, 25), workspace: workspace, card: chaseCard, category: nil, sourceBudgetID: budget.id)

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

        return MarinaUniversalPresentationParityFixture(
            snapshot: snapshot,
            currentPeriod: HomeQueryDateRange(startDate: date(2026, 6, 10), endDate: date(2026, 6, 20)),
            now: date(2026, 6, 15),
            calendar: calendar
        )
    }

    private func makeCardGroupFixture() -> MarinaUniversalPresentationParityFixture {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let appleCard = Card(name: "Apple Card", theme: "ruby", effect: "plastic", workspace: workspace)
        let chaseCard = Card(name: "Chase Card", theme: "sky", effect: "matte", workspace: workspace)
        let budget = Budget(name: "June", startDate: date(2026, 6, 1), endDate: date(2026, 6, 30), workspace: workspace)
        let plannedExpenses = [
            PlannedExpense(title: "Phone Bill", plannedAmount: 80, expenseDate: date(2026, 6, 16), workspace: workspace, card: appleCard, sourceBudgetID: budget.id),
            PlannedExpense(title: "Cash Plan", plannedAmount: 100, expenseDate: date(2026, 6, 20), workspace: workspace, card: nil, sourceBudgetID: budget.id),
            PlannedExpense(title: "Old Cash Plan", plannedAmount: 50, expenseDate: date(2026, 5, 20), workspace: workspace, card: nil, sourceBudgetID: budget.id)
        ]
        let variableExpenses = [
            VariableExpense(descriptionText: "Apple Store", amount: 120, transactionDate: date(2026, 6, 5), workspace: workspace, card: appleCard),
            VariableExpense(descriptionText: "Kroger", amount: 30, transactionDate: date(2026, 6, 10), workspace: workspace, card: chaseCard),
            VariableExpense(descriptionText: "Cash Coffee", amount: 7, transactionDate: date(2026, 6, 11), workspace: workspace, card: nil),
            VariableExpense(descriptionText: "Future Cash", amount: 9, transactionDate: date(2026, 7, 1), workspace: workspace, card: nil)
        ]
        let snapshot = MarinaWorkspaceSnapshot(
            workspace: workspace,
            budgets: [budget],
            cards: [appleCard, chaseCard],
            categories: [],
            presets: [],
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            homePlannedExpenses: plannedExpenses,
            homeCalculationPlannedExpenses: plannedExpenses,
            homeCalculationVariableExpenses: variableExpenses,
            reconciliationAccounts: [],
            expenseAllocations: [],
            allocationSettlements: [],
            savingsAccounts: [],
            savingsEntries: [],
            incomes: []
        )

        return MarinaUniversalPresentationParityFixture(
            snapshot: snapshot,
            currentPeriod: HomeQueryDateRange(startDate: date(2026, 6, 1), endDate: date(2026, 6, 30)),
            now: date(2026, 6, 15),
            calendar: calendar
        )
    }

    private func expectNoDebugText(in result: MarinaExecutionResult) {
        let forbidden = ["Universal routing", "Diagnostics", "Scenario=", "usedUniversal", "fallbackReason"]
        let visibleValues = [
            result.title,
            result.subtitle,
            result.primaryValue,
            result.explanation
        ].compactMap { $0 } + result.rows.flatMap { [$0.title, $0.value] }

        for value in visibleValues {
            for token in forbidden {
                #expect(value.contains(token) == false)
            }
        }
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
        DateComponents(calendar: calendar, timeZone: TimeZone(secondsFromGMT: 0), year: year, month: month, day: day).date!
    }
}

@MainActor
private struct MarinaUniversalPresentationParityFixture {
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

    func presentedResult(
        request: MarinaSemanticRequest,
        context: MarinaUniversalPlanningContext
    ) -> MarinaExecutionResult {
        let formulaRegistry = MarinaFormulaRegistry(now: context.now, calendar: context.calendar)
        let bridge = MarinaSemanticUniversalPlanBridge(formulaRegistry: formulaRegistry)
        let runner = MarinaUniversalQueryRunner(formulaRegistry: formulaRegistry)
        let presenter = MarinaUniversalResultPresenter()

        switch bridge.makePlan(from: request, planningContext: context) {
        case let .plan(plan):
            let universalResult = runner.runFormulaAware(plan: plan, snapshot: snapshot)
            return presenter.presentationResult(
                for: universalResult,
                plan: plan,
                context: MarinaUniversalPresentationContext(
                    dateRange: plan.dateRange,
                    comparisonDateRange: plan.comparisonDateRange,
                    now: context.now,
                    calendar: context.calendar
                )
            )
        case let .unsupported(reason):
            return presenter.presentationResult(
                for: MarinaUniversalQueryResult.unsupported(reason),
                plan: MarinaUniversalQueryPlan(entity: request.entity, operation: request.operation, measure: request.measure),
                context: MarinaUniversalPresentationContext(
                    now: context.now,
                    calendar: context.calendar
                )
            )
        }
    }
}
