import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaUniversalRoutingHarnessTests {
    @Test func disabledPolicyReturnsDisabledFallback() throws {
        let fixture = makeFixture()
        let request = merchantSpendRequest()
        let result = fixture.harness(policy: .disabled).attemptUniversalResult(
            request: request,
            plan: fixture.plan(for: request),
            snapshot: fixture.snapshot,
            context: fixture.context()
        )
        let fallback = try requireFallback(result)

        #expect(fallback.reason == .disabled)
        #expect(fallback.diagnostics.usedUniversal == false)
        #expect(fallback.diagnostics.fallbackReason == .disabled)
    }

    @Test func nonAllowlistedRequestReturnsNotAllowlistedFallback() throws {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .savingsAccount,
            operation: .forecast,
            measure: .savingsTotal,
            dateRangeToken: .allTime
        )
        let result = fixture.harness().attemptUniversalResult(
            request: request,
            plan: fixture.plan(for: request),
            snapshot: fixture.snapshot,
            context: fixture.context()
        )
        let fallback = try requireFallback(result)

        #expect(fallback.reason == .notAllowlisted)
        #expect(fallback.diagnostics.usedUniversal == false)
    }

    @Test func allowlistedMerchantSpendReturnsUniversalResult() throws {
        let fixture = makeFixture()
        let request = merchantSpendRequest()
        let universal = try fixture.requireUniversalAttempt(for: request)

        #expect(universal.result.kind == .metric)
        try expectFirstAmount(universal.result, equals: 138)
        #expect(universal.diagnostics.usedUniversal)
        #expect(universal.diagnostics.fallbackReason == nil)
    }

    @Test func allowlistedCategorySpendReturnsUniversalResult() throws {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.category],
            targetName: "Groceries",
            expenseScope: .variable
        )
        let universal = try fixture.requireUniversalAttempt(for: request)

        #expect(universal.result.kind == .metric)
        try expectFirstAmount(universal.result, equals: 38)
    }

    @Test func allowlistedIncomeTotalReturnsUniversalResult() throws {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .income,
            operation: .sum,
            measure: .incomeAmount,
            incomeState: .all
        )
        let universal = try fixture.requireUniversalAttempt(for: request)

        #expect(universal.result.kind == .metric)
        try expectFirstAmount(universal.result, equals: 4_750)
    }

    @Test func allowlistedIncomeBySourceReturnsUniversalResult() throws {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .income,
            operation: .group,
            measure: .incomeAmount,
            dimensions: [.incomeSource],
            incomeState: .all,
            shape: .list
        )
        let universal = try fixture.requireUniversalAttempt(for: request)
        let rows = universal.result.rows.sorted { $0.title < $1.title }

        #expect(universal.result.kind == .list)
        #expect(universal.diagnostics.scenario == .incomeBySource)
        #expect(rows.map(\.title) == ["Freelance", "Paycheck"])
        #expect(rows.map(\.amount) == [650, 4_100])
    }

    @Test func allowlistedUnifiedExpenseCardGroupsReturnUniversalResult() throws {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .variableExpense,
            operation: .group,
            measure: .budgetImpact,
            dimensions: [.card],
            expenseScope: .unified,
            shape: .list
        )
        let universal = try fixture.requireUniversalAttempt(for: request)
        let rows = universal.result.rows.sorted { $0.title < $1.title }

        #expect(universal.result.kind == .list)
        #expect(universal.diagnostics.scenario == .unifiedExpenseCardGroups)
        #expect(rows.map(\.title) == ["Apple Card", "Chase Card"])
        #expect(rows.map(\.amount) == [218, 1_520])
    }

    @Test func rowBackedVariableExpenseListSearchSortAndLimitReturnsUniversalResult() throws {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .variableExpense,
            operation: .list,
            measure: .budgetImpact,
            textQuery: "Apple",
            resultLimit: 1,
            sort: .amountDescending,
            expenseScope: .variable,
            shape: .list
        )
        let universal = try fixture.requireUniversalAttempt(for: request)

        #expect(universal.result.kind == .list)
        #expect(universal.diagnostics.scenario == .rowBackedQuery)
        #expect(universal.result.rows.map(\.title) == ["Apple Store"])
        #expect(universal.result.rows.map(\.amount) == [120])
    }

    @Test func rowBackedVariableExpenseCountAndAverageReturnUniversalResults() throws {
        let fixture = makeFixture()
        let countRequest = semanticRequest(
            entity: .variableExpense,
            operation: .count,
            expenseScope: .variable
        )
        let averageRequest = semanticRequest(
            entity: .variableExpense,
            operation: .average,
            measure: .budgetImpact,
            expenseScope: .variable
        )
        let count = try fixture.requireUniversalAttempt(for: countRequest)
        let average = try fixture.requireUniversalAttempt(for: averageRequest)

        #expect(count.diagnostics.scenario == .rowBackedQuery)
        #expect(average.diagnostics.scenario == .rowBackedQuery)
        try expectFirstAmount(count.result, equals: 4)
        try expectFirstAmount(average.result, equals: 114.5)
    }

    @Test func rowBackedPlannedExpenseRelationshipFiltersAndLastReturnUniversalResults() throws {
        let fixture = makeFixture()
        let listRequest = semanticRequest(
            entity: .plannedExpense,
            operation: .list,
            dimensions: [.card],
            targetName: "Apple Card",
            expenseScope: .planned,
            shape: .list
        )
        let lastRequest = semanticRequest(
            entity: .plannedExpense,
            operation: .last,
            measure: .effectiveAmount,
            expenseScope: .planned,
            shape: .metric
        )
        let list = try fixture.requireUniversalAttempt(for: listRequest)
        let last = try fixture.requireUniversalAttempt(for: lastRequest)

        #expect(list.diagnostics.scenario == .rowBackedQuery)
        #expect(list.result.rows.map(\.title) == ["Phone Bill"])
        #expect(last.diagnostics.scenario == .rowBackedQuery)
        #expect(last.result.rows.map(\.title) == ["Rent"])
    }

    @Test func rowBackedUnifiedAllTimeGroupAndCountReturnUniversalResults() throws {
        let fixture = makeFixture()
        let groupRequest = semanticRequest(
            entity: .variableExpense,
            operation: .group,
            measure: .budgetImpact,
            dimensions: [.card],
            dateRangeToken: .allTime,
            expenseScope: .unified,
            shape: .list
        )
        let countRequest = semanticRequest(
            entity: .plannedExpense,
            operation: .count,
            dateRangeToken: .allTime,
            expenseScope: .unified
        )
        let groups = try fixture.requireUniversalAttempt(for: groupRequest)
        let count = try fixture.requireUniversalAttempt(for: countRequest)

        #expect(groups.diagnostics.scenario == .rowBackedQuery)
        #expect(groups.result.rows.sorted { $0.title < $1.title }.map(\.amount) == [218, 1_520])
        #expect(count.diagnostics.scenario == .rowBackedQuery)
        try expectFirstAmount(count.result, equals: 6)
    }

    @Test func rowBackedIncomeStateCategoryCardAndPresetShapesReturnUniversalResults() throws {
        let fixture = makeFixture()
        let plannedIncome = try fixture.requireUniversalAttempt(for: semanticRequest(
            entity: .income,
            operation: .sum,
            measure: .incomeAmount,
            incomeState: .planned
        ))
        let categories = try fixture.requireUniversalAttempt(for: semanticRequest(
            entity: .category,
            operation: .list,
            shape: .list
        ))
        let cards = try fixture.requireUniversalAttempt(for: semanticRequest(
            entity: .card,
            operation: .count
        ))
        let presetSum = try fixture.requireUniversalAttempt(for: semanticRequest(
            entity: .preset,
            operation: .sum,
            measure: .plannedAmount
        ))

        #expect(plannedIncome.diagnostics.scenario == .rowBackedQuery)
        try expectFirstAmount(plannedIncome.result, equals: 2_100)
        #expect(categories.diagnostics.scenario == .rowBackedQuery)
        #expect(categories.result.rows.map(\.title).sorted() == ["Electronics", "Groceries"])
        #expect(cards.diagnostics.scenario == .rowBackedQuery)
        try expectFirstAmount(cards.result, equals: 2)
        #expect(presetSum.diagnostics.scenario == .rowBackedQuery)
        try expectFirstAmount(presetSum.result, equals: 80)
    }

    @Test func allowlistedSavingsTotalWithExplicitAccountReturnsUniversalResult() throws {
        let fixture = makeFixture()
        let request = savingsTotalRequest(targetName: "Savings Account")
        let universal = try fixture.requireUniversalAttempt(for: request)

        #expect(universal.result.kind == .metric)
        try expectFirstAmount(universal.result, equals: 1_000)
    }

    @Test func savingsTotalWithoutExplicitAccountFallsBack() throws {
        let fixture = makeFixture()
        let request = savingsTotalRequest(targetName: nil)
        let result = fixture.harness().attemptUniversalResult(
            request: request,
            plan: fixture.plan(for: request),
            snapshot: fixture.snapshot,
            context: fixture.context()
        )
        let fallback = try requireFallback(result)

        #expect(fallback.reason == .notAllowlisted)
        #expect(fallback.diagnostics.fallbackReason == .notAllowlisted)
    }

    @Test func allowlistedReconciliationBalanceWithExplicitAccountReturnsUniversalResult() throws {
        let fixture = makeFixture()
        let request = reconciliationBalanceRequest(targetName: "Alejandro")
        let universal = try fixture.requireUniversalAttempt(for: request)

        #expect(universal.result.kind == .metric)
        try expectFirstAmount(universal.result, equals: 6)
    }

    @Test func allowlistedBudgetBurnRateReturnsUniversalResult() throws {
        let fixture = makeFixture()
        let request = semanticRequest(entity: .budget, operation: .average, measure: .burnRate)
        let universal = try fixture.requireUniversalAttempt(for: request)

        #expect(universal.result.kind == .metric)
        #expect(universal.result.title == "Burn Rate")
        #expect(universal.diagnostics.scenario == .budgetBurnRate)
        try expectRowAmount(universal.result, title: "Average per day", equals: 440.0 / 15.0)
    }

    @Test func allowlistedBudgetProjectedSpendReturnsUniversalResult() throws {
        let fixture = makeFixture()
        let request = semanticRequest(entity: .budget, operation: .forecast, measure: .projectedSpend)
        let universal = try fixture.requireUniversalAttempt(for: request)

        #expect(universal.result.kind == .metric)
        #expect(universal.result.title == "Projected Spend")
        #expect(universal.diagnostics.scenario == .budgetProjectedSpend)
        try expectRowAmount(universal.result, title: "Projected total", equals: 880)
    }

    @Test func allowlistedBudgetPaceDifferenceReturnsUniversalResult() throws {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .budget,
            operation: .compare,
            measure: .paceDifference,
            shape: .comparison
        )
        let universal = try fixture.requireUniversalAttempt(for: request)

        #expect(universal.result.kind == .comparison)
        #expect(universal.result.title == "Pace Difference")
        #expect(universal.diagnostics.scenario == .budgetPaceDifference)
        try expectRowAmount(universal.result, title: "Pace difference", equals: -200)
    }

    @Test func allowlistedCoverageRatiosReturnUniversalResults() throws {
        let fixture = makeFixture()
        let budgetRequest = semanticRequest(entity: .budget, operation: .forecast, measure: .coverageRatio)
        let incomeRequest = semanticRequest(entity: .income, operation: .share, measure: .coverageRatio)
        let budgetUniversal = try fixture.requireUniversalAttempt(for: budgetRequest)
        let incomeUniversal = try fixture.requireUniversalAttempt(for: incomeRequest)

        #expect(budgetUniversal.result.title == "Budget Coverage")
        #expect(incomeUniversal.result.title == "Income Coverage")
        #expect(budgetUniversal.diagnostics.scenario == .budgetCoverageRatio)
        #expect(incomeUniversal.diagnostics.scenario == .incomeCoverageRatio)
        try expectRowAmount(budgetUniversal.result, title: "Coverage percent", equals: 2_650.0 / 1_280.0)
        try expectRowAmount(incomeUniversal.result, title: "Coverage percent", equals: 2_650.0 / 1_280.0)
    }

    @Test func allowlistedCategoryFormulasReturnUniversalResults() throws {
        let fixture = makeFixture()
        let availabilityRequest = semanticRequest(entity: .category, operation: .forecast, measure: .categoryAvailability)
        let concentrationRequest = semanticRequest(entity: .category, operation: .share, measure: .concentration)
        let availability = try fixture.requireUniversalAttempt(for: availabilityRequest)
        let concentration = try fixture.requireUniversalAttempt(for: concentrationRequest)

        #expect(availability.result.kind == .metric)
        #expect(availability.result.title == "Category Availability")
        #expect(availability.result.primaryValue == "0 over, 0 near")
        #expect(availability.diagnostics.scenario == .categoryAvailability)
        try expectRowAmount(availability.result, title: "Categories", equals: 2)

        #expect(concentration.result.kind == .metric)
        #expect(concentration.result.title == "Budget Concentration")
        #expect(concentration.diagnostics.scenario == .categoryConcentration)
        try expectRowAmount(concentration.result, title: "Concentration", equals: 1_200.0 / 1_738.0)
    }

    @Test func allowlistedRemainingFormulaShapesReturnUniversalResults() throws {
        let fixture = makeFixture()
        let recurringRequest = semanticRequest(entity: .preset, operation: .sum, measure: .recurringBurden)
        let forecastRequest = semanticRequest(entity: .savingsAccount, operation: .forecast, measure: .savingsTotal)
        let recurring = try fixture.requireUniversalAttempt(for: recurringRequest)
        let forecast = try fixture.requireUniversalAttempt(for: forecastRequest)

        #expect(recurring.result.kind == .metric)
        #expect(recurring.result.title == "Recurring Burden")
        #expect(recurring.diagnostics.scenario == .presetRecurringBurden)
        try expectRowAmount(recurring.result, title: "Recurring burden", equals: 80.0 / 1_280.0)

        #expect(forecast.result.kind == .metric)
        #expect(forecast.result.title == "Forecast Savings")
        #expect(forecast.diagnostics.scenario == .forecastSavings)
        try expectRowAmount(forecast.result, title: "Projected savings", equals: 820)
    }

    @Test func reconciliationBalanceWithoutExplicitAccountFallsBack() throws {
        let fixture = makeFixture()
        let request = reconciliationBalanceRequest(targetName: nil)
        let result = fixture.harness().attemptUniversalResult(
            request: request,
            plan: fixture.plan(for: request),
            snapshot: fixture.snapshot,
            context: fixture.context()
        )
        let fallback = try requireFallback(result)

        #expect(fallback.reason == .notAllowlisted)
        #expect(fallback.diagnostics.fallbackReason == .notAllowlisted)
    }

    @Test func universalBridgeUnsupportedResultFallsBack() throws {
        let fixture = makeFixture()
        let request = savingsTotalRequest(targetName: "Savings Account")
        let result = fixture.harness(bridgeUsesFormulaRegistry: false, runnerUsesFormulaRegistry: true)
            .attemptUniversalResult(
                request: request,
                plan: fixture.plan(for: request),
                snapshot: fixture.snapshot,
                context: fixture.context()
            )
        let fallback = try requireFallback(result)

        #expect(fallback.reason == .unsupportedBridge)
        #expect(fallback.diagnostics.notes.contains { $0.contains("Bridge unsupported") })
    }

    @Test func universalRunnerUnsupportedResultFallsBack() throws {
        let fixture = makeFixture()
        let request = savingsTotalRequest(targetName: "Savings Account")
        let result = fixture.harness(bridgeUsesFormulaRegistry: true, runnerUsesFormulaRegistry: false)
            .attemptUniversalResult(
                request: request,
                plan: fixture.plan(for: request),
                snapshot: fixture.snapshot,
                context: fixture.context()
            )
        let fallback = try requireFallback(result)

        #expect(fallback.reason == .unsupportedRunner)
        #expect(fallback.diagnostics.notes.contains { $0.contains("Runner unsupported") })
    }

    @Test func presentationSucceedsForAllowlistedUniversalResult() throws {
        let fixture = makeFixture()
        let request = merchantSpendRequest()
        let universal = try fixture.requireUniversalAttempt(for: request)

        #expect(universal.result.title.isEmpty == false)
        #expect(universal.result.primaryValue != nil)
        #expect(universal.result.rows.isEmpty == false)
    }

    @Test func diagnosticsIncludeUniversalUsageAndFallbackReason() throws {
        let fixture = makeFixture()
        let universal = try fixture.requireUniversalAttempt(for: merchantSpendRequest())
        let fallbackResult = fixture.harness(policy: .disabled).attemptUniversalResult(
            request: merchantSpendRequest(),
            plan: fixture.plan(for: merchantSpendRequest()),
            snapshot: fixture.snapshot,
            context: fixture.context()
        )
        let fallback = try requireFallback(fallbackResult)

        #expect(universal.diagnostics.requestEntity == .variableExpense)
        #expect(universal.diagnostics.operation == .sum)
        #expect(universal.diagnostics.measure == .budgetImpact)
        #expect(universal.diagnostics.usedUniversal)
        #expect(universal.diagnostics.notes.contains("Universal routing succeeded."))
        #expect(fallback.diagnostics.usedUniversal == false)
        #expect(fallback.diagnostics.fallbackReason == .disabled)
    }

    private func makeFixture() -> MarinaUniversalRoutingHarnessFixture {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let appleCard = Card(name: "Apple Card", theme: "ruby", effect: "plastic", workspace: workspace)
        let chaseCard = Card(name: "Chase Card", theme: "sky", effect: "matte", workspace: workspace)
        let groceries = Offshore.Category(name: "Groceries", hexColor: "#22C55E", workspace: workspace)
        let electronics = Offshore.Category(name: "Electronics", hexColor: "#0EA5E9", workspace: workspace)
        let budget = Budget(name: "June", startDate: date(2026, 6, 1), endDate: date(2026, 6, 30), workspace: workspace)
        let phonePreset = Preset(title: "Phone", plannedAmount: 80, workspace: workspace, defaultCard: appleCard, defaultCategory: electronics)

        let appleStoreJune = VariableExpense(descriptionText: "Apple Store", amount: 120, transactionDate: date(2026, 6, 5), workspace: workspace, card: appleCard, category: electronics)
        let appleMarketJune = VariableExpense(descriptionText: "Apple Market", amount: 18, transactionDate: date(2026, 6, 20), workspace: workspace, card: appleCard, category: groceries)
        let krogerJune = VariableExpense(descriptionText: "Kroger", amount: 30, transactionDate: date(2026, 6, 10), workspace: workspace, card: chaseCard, category: groceries)
        let bestBuyJune = VariableExpense(descriptionText: "Best Buy", amount: 300, transactionDate: date(2026, 6, 12), workspace: workspace, card: chaseCard, category: electronics)

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

        let savings = SavingsAccount(name: "Savings Account", total: 1_000, workspace: workspace)
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

        let variableExpenses = [appleStoreJune, appleMarketJune, krogerJune, bestBuyJune]
        let plannedExpenses = [phoneBill, rent]
        let incomes = [actualPaycheck, freelance, plannedPaycheck]
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
            savingsEntries: [],
            incomes: incomes
        )

        return MarinaUniversalRoutingHarnessFixture(
            snapshot: snapshot,
            now: date(2026, 6, 15),
            calendar: calendar
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

    private func savingsTotalRequest(targetName: String?) -> MarinaSemanticRequest {
        semanticRequest(
            entity: .savingsAccount,
            operation: .sum,
            measure: .savingsTotal,
            dateRangeToken: .allTime,
            targetName: targetName
        )
    }

    private func reconciliationBalanceRequest(targetName: String?) -> MarinaSemanticRequest {
        semanticRequest(
            entity: .reconciliationAccount,
            operation: .sum,
            measure: .reconciliationBalance,
            dateRangeToken: .allTime,
            targetName: targetName
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

    private func requireFallback(
        _ result: MarinaUniversalRoutingResult
    ) throws -> (reason: MarinaUniversalFallbackReason, diagnostics: MarinaUniversalRoutingDiagnostics) {
        guard case let .fallback(reason, diagnostics) = result else {
            Issue.record("Expected fallback, got \(result).")
            throw TestFailure()
        }
        return (reason, diagnostics)
    }

    private func expectFirstAmount(
        _ result: MarinaExecutionResult,
        equals expectedAmount: Double,
        accuracy: Double = 0.01
    ) throws {
        let amount = try #require(result.rows.first?.amount)
        #expect(abs(amount - expectedAmount) <= accuracy, "Expected \(expectedAmount), got \(amount).")
    }

    private func expectRowAmount(
        _ result: MarinaExecutionResult,
        title: String,
        equals expectedAmount: Double,
        accuracy: Double = 0.01
    ) throws {
        let amount = try #require(result.rows.first(where: { $0.title == title })?.amount)
        #expect(abs(amount - expectedAmount) <= accuracy, "Expected \(expectedAmount), got \(amount).")
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
private struct MarinaUniversalRoutingHarnessFixture {
    let snapshot: MarinaWorkspaceSnapshot
    let now: Date
    let calendar: Calendar

    func context() -> MarinaUniversalPlanningContext {
        MarinaUniversalPlanningContext(
            defaultBudgetingPeriod: .monthly,
            now: now,
            calendar: calendar
        )
    }

    func plan(for request: MarinaSemanticRequest) -> MarinaQueryPlan {
        MarinaQueryPlanner(calendar: calendar).plan(
            request: request,
            ambientDateRange: context().ambientDateRange,
            defaultBudgetingPeriod: context().defaultBudgetingPeriod,
            now: context().now
        )
    }

    func harness(
        policy: MarinaUniversalRoutingPolicy = .internalParityProven,
        bridgeUsesFormulaRegistry: Bool = true,
        runnerUsesFormulaRegistry: Bool = true
    ) -> MarinaUniversalRoutingHarness {
        let bridgeFormulaRegistry: MarinaFormulaRegistry? = bridgeUsesFormulaRegistry
            ? MarinaFormulaRegistry(now: now, calendar: calendar)
            : nil
        let runnerFormulaRegistry: MarinaFormulaRegistry? = runnerUsesFormulaRegistry
            ? MarinaFormulaRegistry(now: now, calendar: calendar)
            : nil

        return MarinaUniversalRoutingHarness(
            bridge: MarinaSemanticUniversalPlanBridge(formulaRegistry: bridgeFormulaRegistry),
            runner: MarinaUniversalQueryRunner(formulaRegistry: runnerFormulaRegistry),
            presenter: MarinaUniversalResultPresenter(),
            policy: policy
        )
    }

    func requireUniversalAttempt(
        for request: MarinaSemanticRequest
    ) throws -> (result: MarinaExecutionResult, diagnostics: MarinaUniversalRoutingDiagnostics) {
        let attempt = harness().attemptUniversalResult(
            request: request,
            plan: plan(for: request),
            snapshot: snapshot,
            context: context()
        )
        guard case let .universal(result, diagnostics) = attempt else {
            Issue.record("Expected universal result, got \(attempt).")
            throw TestFailure()
        }
        return (result, diagnostics)
    }
}

private struct TestFailure: Error {}
