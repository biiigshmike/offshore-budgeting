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
        #expect(registry.supports(measure: .burnRate, surface: .semantic(.budget), operation: .average))
        #expect(registry.supports(measure: .projectedSpend, surface: .semantic(.budget), operation: .forecast))
        #expect(registry.supports(measure: .paceDifference, surface: .semantic(.budget), operation: .compare))
        #expect(registry.supports(measure: .coverageRatio, surface: .semantic(.budget), operation: .forecast))
        #expect(registry.supports(measure: .coverageRatio, surface: .semantic(.income), operation: .share))
        #expect(registry.supports(measure: .incomeAmount, surface: .semantic(.income), operation: .share))
        #expect(registry.supports(measure: .categoryAvailability, surface: .semantic(.category), operation: .forecast))
        #expect(registry.supports(measure: .categoryAvailability, surface: .semantic(.category), operation: .list))
        #expect(registry.supports(measure: .concentration, surface: .semantic(.category), operation: .share))
        #expect(registry.supports(measure: .recurringBurden, surface: .semantic(.preset), operation: .sum))
        #expect(registry.supports(measure: .savingsTotal, surface: .semantic(.savingsAccount), operation: .forecast))
        #expect(registry.supports(measure: .remainingRoom, surface: .semantic(.budget), operation: .whatIf))
        #expect(registry.supports(measure: .projectedSavings, surface: .semantic(.budget), operation: .whatIf))

        #expect(registry.supports(measure: .concentration, surface: .semantic(.category), operation: .forecast) == false)
        #expect(registry.supports(measure: .recurringBurden, surface: .semantic(.preset), operation: .forecast) == false)
        #expect(registry.supports(measure: .savingsTotal, surface: .semantic(.savingsAccount), operation: .share) == false)
        #expect(registry.supports(measure: .burnRate, surface: .semantic(.budget), operation: .forecast) == false)
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

    @Test func budgetPaceFormulasDelegateToBudgetFormulaCalculator() throws {
        let fixture = makeFixture()
        let registry = MarinaFormulaRegistry(now: date(2026, 6, 15), calendar: calendar)
        let range = HomeQueryDateRange(startDate: date(2026, 6, 1), endDate: date(2026, 6, 30))

        let burnRate = requireMetric(registry.evaluate(
            request: formulaRequest(
                surface: .semantic(.budget),
                operation: .average,
                measure: .burnRate,
                dateRange: range
            ),
            snapshot: fixture.snapshot
        ))
        #expect(burnRate.value == .money(250.0 / 15.0))
        #expect(burnRate.source == .marinaBudgetFormulaCalculator)
        #expect(detailValue(.spentSoFar, in: burnRate) == .money(250))
        #expect(detailValue(.elapsedDays, in: burnRate) == .integer(15))

        let projectedSpend = requireMetric(registry.evaluate(
            request: formulaRequest(
                surface: .semantic(.budget),
                operation: .forecast,
                measure: .projectedSpend,
                dateRange: range
            ),
            snapshot: fixture.snapshot
        ))
        #expect(projectedSpend.value == .money(450))
        #expect(projectedSpend.source == .safeSpendTodayCalculator)
        #expect(detailValue(.actualSpendSoFar, in: projectedSpend) == .money(250))
        #expect(detailValue(.plannedSpendingRemaining, in: projectedSpend) == .money(200))
        #expect(detailValue(.projectedSpend, in: projectedSpend) == .money(450))
        #expect(detailValue(.averagePerDay, in: projectedSpend) == nil)
        #expect(detailValue(.projectedTotal, in: projectedSpend) == nil)

        let paceDifference = requireMetric(registry.evaluate(
            request: formulaRequest(
                surface: .semantic(.budget),
                operation: .compare,
                measure: .paceDifference,
                dateRange: range
            ),
            snapshot: fixture.snapshot
        ))
        #expect(paceDifference.value == .money(100))
        #expect(detailValue(.expectedByNow, in: paceDifference) == .money(150))
        #expect(detailValue(.paceDifference, in: paceDifference) == .money(100))

        let budgetCoverage = requireMetric(registry.evaluate(
            request: formulaRequest(
                surface: .semantic(.budget),
                operation: .forecast,
                measure: .coverageRatio,
                dateRange: range
            ),
            snapshot: fixture.snapshot
        ))
        #expect(budgetCoverage.value == .number(1_000.0 / 300.0))
        #expect(detailValue(.income, in: budgetCoverage) == .money(1_000))
        #expect(detailValue(.plannedExpenses, in: budgetCoverage) == .money(300))

        let incomeCoverage = requireMetric(registry.evaluate(
            request: formulaRequest(
                surface: .semantic(.income),
                operation: .share,
                measure: .coverageRatio,
                dateRange: range
            ),
            snapshot: fixture.snapshot
        ))
        #expect(incomeCoverage.value == .number(1_000.0 / 300.0))
        #expect(detailValue(.difference, in: incomeCoverage) == .money(700))
    }

    @Test func incomeProgressMatchesActualToPlannedHomeSemantics() {
        let fixture = makeFixture()
        let registry = MarinaFormulaRegistry(now: date(2026, 6, 15), calendar: calendar)
        let range = HomeQueryDateRange(startDate: date(2026, 6, 1), endDate: date(2026, 6, 30))

        let metric = requireMetric(registry.evaluate(
            request: formulaRequest(
                surface: .semantic(.income),
                operation: .share,
                measure: .incomeAmount,
                dateRange: range
            ),
            snapshot: fixture.snapshot
        ))

        #expect(metric.value == .number(2))
        #expect(metric.source == .homeQueryEngine)
        #expect(metric.evidenceRows.map(\.displayName).sorted() == ["Bonus", "Paycheck"])
        #expect(metric.presentationRows.map(\.title) == ["Actual", "Planned", "Progress"])
        #expect(metric.presentationRows[0].primaryValue == .money(1_000))
        #expect(metric.presentationRows[1].primaryValue == .money(500))
        #expect(metric.presentationRows[2].primaryValue == .number(2))
        #expect(metric.presentationRows[2].primaryStyle == .percent)
    }

    @Test func incomeProgressWithoutPlannedIncomeUsesEmptyMetricAndDashRow() {
        let fixture = makeFixture(includePlannedIncome: false)
        let registry = MarinaFormulaRegistry(now: date(2026, 6, 15), calendar: calendar)

        let metric = requireMetric(registry.evaluate(
            request: formulaRequest(
                surface: .semantic(.income),
                operation: .share,
                measure: .incomeAmount,
                dateRange: HomeQueryDateRange(startDate: date(2026, 6, 1), endDate: date(2026, 6, 30))
            ),
            snapshot: fixture.snapshot
        ))

        #expect(metric.value == .empty)
        #expect(metric.presentationRows[1].primaryValue == .money(0))
        #expect(metric.presentationRows[2].primaryValue == .text("-"))
    }

    @Test func budgetWhatIfFormulasApplyTypedAdditionalSpend() {
        let fixture = makeFixture()
        let registry = MarinaFormulaRegistry(now: date(2026, 6, 15), calendar: calendar)
        let range = HomeQueryDateRange(startDate: date(2026, 6, 1), endDate: date(2026, 6, 30))

        let remainingRoom = requireMetric(registry.evaluate(
            request: formulaRequest(
                surface: .semantic(.budget),
                operation: .whatIf,
                measure: .remainingRoom,
                dateRange: range,
                whatIfAmount: 50
            ),
            snapshot: fixture.snapshot
        ))
        let projectedSavings = requireMetric(registry.evaluate(
            request: formulaRequest(
                surface: .semantic(.budget),
                operation: .whatIf,
                measure: .projectedSavings,
                dateRange: range,
                whatIfAmount: 200
            ),
            snapshot: fixture.snapshot
        ))

        #expect(remainingRoom.value == .money(1_000))
        #expect(remainingRoom.presentationRows.count == 2)
        #expect(projectedSavings.presentationRows.count == 2)
        #expect(detailValue(.difference, in: projectedSavings) == .money(-200))
    }

    @Test func categoryFormulasDelegateToDeterministicCategoryServices() throws {
        let fixture = makeCategoryFormulaFixture()
        let registry = MarinaFormulaRegistry(now: date(2026, 6, 15), calendar: calendar)
        let range = HomeQueryDateRange(startDate: date(2026, 6, 1), endDate: date(2026, 6, 30))

        let availability = requireMetric(registry.evaluate(
            request: formulaRequest(
                surface: .semantic(.category),
                operation: .forecast,
                measure: .categoryAvailability,
                dateRange: range
            ),
            snapshot: fixture.snapshot
        ))
        let availabilityResult = HomeCategoryLimitsAggregator.build(
            budgets: fixture.snapshot.budgets,
            categories: fixture.snapshot.categories,
            plannedExpenses: fixture.snapshot.homeCalculationPlannedExpenses,
            variableExpenses: fixture.snapshot.homeCalculationVariableExpenses,
            rangeStart: range.startDate,
            rangeEnd: range.endDate,
            calendar: calendar
        )

        #expect(availability.value == .integer(availabilityResult.metrics.count))
        #expect(availability.source == .homeCategoryLimitsAggregator)
        #expect(detailValue(.activeBudget, in: availability) == .text("June"))
        #expect(detailValue(.overCount, in: availability) == .integer(availabilityResult.overCount))
        #expect(detailValue(.nearCount, in: availability) == .integer(availabilityResult.nearCount))
        #expect(detailValue(.categoryCount, in: availability) == .integer(availabilityResult.metrics.count))

        let overList = registry.evaluate(
            request: formulaRequest(
                surface: .semantic(.category),
                operation: .list,
                measure: .categoryAvailability,
                dateRange: range,
                categoryAvailabilityFilter: .over
            ),
            snapshot: fixture.snapshot
        )
        guard case let .rows(overRows) = overList else {
            Issue.record("Expected category availability over-limit rows, got \(overList).")
            throw FormulaTestFailure()
        }
        #expect(overRows.map(\.displayName) == ["Groceries"])
        #expect(overRows.first?.fields[.amount] == .money(150))
        #expect(overRows.first?.fields[.plannedAmount] == .money(100))
        #expect(overRows.first?.fields[.actualAmount] == .money(-50))

        let concentration = requireMetric(registry.evaluate(
            request: formulaRequest(
                surface: .semantic(.category),
                operation: .share,
                measure: .concentration,
                dateRange: range
            ),
            snapshot: fixture.snapshot
        ))
        let categoryMetrics = HomeCategoryMetricsCalculator.calculate(
            categories: fixture.snapshot.categories,
            plannedExpenses: fixture.snapshot.homeCalculationPlannedExpenses,
            variableExpenses: fixture.snapshot.homeCalculationVariableExpenses,
            rangeStart: range.startDate,
            rangeEnd: range.endDate
        )
        let selected = try #require(categoryMetrics.metrics.first)
        let expectedConcentration = try #require(MarinaBudgetFormulaCalculator.concentration(
            partTotal: selected.totalSpent,
            wholeTotal: categoryMetrics.totalSpent
        ))

        #expect(concentration.value == .number(expectedConcentration))
        #expect(concentration.source == .homeCategoryMetricsCalculator)
        #expect(detailValue(.category, in: concentration) == .text(selected.categoryName))
        #expect(detailValue(.categorySpend, in: concentration) == .money(selected.totalSpent))
        #expect(detailValue(.totalSpend, in: concentration) == .money(categoryMetrics.totalSpent))
        #expect(detailValue(.concentration, in: concentration) == .number(expectedConcentration))
    }

    @Test func remainingFormulaShapesDelegateToDeterministicCalculators() throws {
        let fixture = makeRemainingFormulaFixture()
        let registry = MarinaFormulaRegistry(now: date(2026, 6, 15), calendar: calendar)
        let range = HomeQueryDateRange(startDate: date(2026, 6, 1), endDate: date(2026, 6, 30))

        let recurringBurden = requireMetric(registry.evaluate(
            request: formulaRequest(
                surface: .semantic(.preset),
                operation: .sum,
                measure: .recurringBurden,
                dateRange: range
            ),
            snapshot: fixture.snapshot
        ))
        let recurringTotal = MarinaBudgetFormulaCalculator.plannedExpenseTotal(
            snapshot: fixture.snapshot,
            range: range,
            recurringOnly: true
        )
        let plannedExpenseTotal = MarinaBudgetFormulaCalculator.plannedExpenseTotal(
            snapshot: fixture.snapshot,
            range: range
        )
        let expectedBurden = try #require(MarinaBudgetFormulaCalculator.recurringBurden(
            recurringTotal: recurringTotal,
            plannedExpenseTotal: plannedExpenseTotal
        ))

        #expect(recurringBurden.value == .number(expectedBurden))
        #expect(recurringBurden.source == .marinaBudgetFormulaCalculator)
        #expect(detailValue(.recurringTotal, in: recurringBurden) == .money(recurringTotal))
        #expect(detailValue(.plannedExpenses, in: recurringBurden) == .money(plannedExpenseTotal))
        #expect(detailValue(.recurringBurden, in: recurringBurden) == .number(expectedBurden))

        let forecastSavings = requireMetric(registry.evaluate(
            request: formulaRequest(
                surface: .semantic(.savingsAccount),
                operation: .forecast,
                measure: .savingsTotal,
                dateRange: range
            ),
            snapshot: fixture.snapshot
        ))
        let summary = MarinaSavingsForecastCalculator.calculate(
            range: range,
            incomes: fixture.snapshot.incomes,
            plannedExpenses: fixture.snapshot.homeCalculationPlannedExpenses,
            variableExpenses: fixture.snapshot.homeCalculationVariableExpenses,
            savingsEntries: fixture.snapshot.savingsEntries
        )

        #expect(forecastSavings.value == .money(summary.projectedSavings))
        #expect(forecastSavings.source == .marinaSavingsForecastCalculator)
        #expect(detailValue(.projectedSavings, in: forecastSavings) == .money(summary.projectedSavings))
        #expect(detailValue(.actualSavings, in: forecastSavings) == .money(summary.actualSavings))
        #expect(detailValue(.gapToProjected, in: forecastSavings) == .money(summary.gapToProjected))
        #expect(detailValue(.forecastStatus, in: forecastSavings) == .text(summary.statusLine))
    }

    @Test func supportedFormulaMissingRequiredContextReturnsTypedUnsupported() {
        let fixture = makeFixture()
        let registry = MarinaFormulaRegistry(now: date(2026, 6, 15), calendar: calendar)

        #expect(registry.evaluate(
            request: formulaRequest(surface: .semantic(.budget), operation: .forecast, measure: .safeDailySpend),
            snapshot: fixture.snapshot
        ) == .unsupported(.missingDateField))
        #expect(registry.evaluate(
            request: formulaRequest(surface: .semantic(.budget), operation: .average, measure: .burnRate),
            snapshot: fixture.snapshot
        ) == .unsupported(.missingDateField))
        #expect(registry.evaluate(
            request: formulaRequest(surface: .semantic(.category), operation: .forecast, measure: .categoryAvailability),
            snapshot: fixture.snapshot
        ) == .unsupported(.missingDateField))
        #expect(registry.evaluate(
            request: formulaRequest(surface: .semantic(.category), operation: .share, measure: .concentration),
            snapshot: fixture.snapshot
        ) == .unsupported(.missingDateField))
        #expect(registry.evaluate(
            request: formulaRequest(surface: .semantic(.preset), operation: .sum, measure: .recurringBurden),
            snapshot: fixture.snapshot
        ) == .unsupported(.missingDateField))
        #expect(registry.evaluate(
            request: formulaRequest(surface: .semantic(.savingsAccount), operation: .forecast, measure: .savingsTotal),
            snapshot: fixture.snapshot
        ) == .unsupported(.missingDateField))
    }

    @Test func categoryFormulaInvalidDataReturnsTypedUnsupported() {
        let fixture = makeFixture()
        let registry = MarinaFormulaRegistry(now: date(2026, 6, 15), calendar: calendar)
        let range = HomeQueryDateRange(startDate: date(2026, 7, 1), endDate: date(2026, 7, 31))
        let noBudgetSnapshot = MarinaWorkspaceSnapshot(
            workspace: fixture.snapshot.workspace,
            budgets: [],
            cards: fixture.snapshot.cards,
            categories: fixture.snapshot.categories,
            presets: fixture.snapshot.presets,
            plannedExpenses: fixture.snapshot.plannedExpenses,
            variableExpenses: fixture.snapshot.variableExpenses,
            homePlannedExpenses: fixture.snapshot.homePlannedExpenses,
            homeCalculationPlannedExpenses: fixture.snapshot.homeCalculationPlannedExpenses,
            homeCalculationVariableExpenses: fixture.snapshot.homeCalculationVariableExpenses,
            reconciliationAccounts: fixture.snapshot.reconciliationAccounts,
            expenseAllocations: fixture.snapshot.expenseAllocations,
            allocationSettlements: fixture.snapshot.allocationSettlements,
            savingsAccounts: fixture.snapshot.savingsAccounts,
            savingsEntries: fixture.snapshot.savingsEntries,
            incomes: fixture.snapshot.incomes
        )

        #expect(registry.evaluate(
            request: formulaRequest(
                surface: .semantic(.category),
                operation: .forecast,
                measure: .categoryAvailability,
                dateRange: range
            ),
            snapshot: noBudgetSnapshot
        ) == .unsupported(.unsupportedCombination))

        #expect(registry.evaluate(
            request: formulaRequest(
                surface: .semantic(.category),
                operation: .share,
                measure: .concentration,
                dateRange: range
            ),
            snapshot: noBudgetSnapshot
        ) == .unsupported(.unsupportedCombination))
    }

    @Test func remainingFormulaInvalidDataReturnsTypedUnsupported() {
        let fixture = makeFixture()
        let registry = MarinaFormulaRegistry(now: date(2026, 6, 15), calendar: calendar)
        let range = HomeQueryDateRange(startDate: date(2026, 7, 1), endDate: date(2026, 7, 31))
        let emptySnapshot = MarinaWorkspaceSnapshot(
            workspace: fixture.snapshot.workspace,
            budgets: fixture.snapshot.budgets,
            cards: fixture.snapshot.cards,
            categories: fixture.snapshot.categories,
            presets: fixture.snapshot.presets,
            plannedExpenses: [],
            variableExpenses: [],
            homePlannedExpenses: [],
            homeCalculationPlannedExpenses: [],
            homeCalculationVariableExpenses: [],
            reconciliationAccounts: fixture.snapshot.reconciliationAccounts,
            expenseAllocations: [],
            allocationSettlements: [],
            savingsAccounts: fixture.snapshot.savingsAccounts,
            savingsEntries: [],
            incomes: []
        )

        #expect(registry.evaluate(
            request: formulaRequest(
                surface: .semantic(.preset),
                operation: .sum,
                measure: .recurringBurden,
                dateRange: range
            ),
            snapshot: emptySnapshot
        ) == .unsupported(.unsupportedCombination))

        #expect(registry.evaluate(
            request: formulaRequest(
                surface: .semantic(.savingsAccount),
                operation: .forecast,
                measure: .savingsTotal,
                dateRange: range
            ),
            snapshot: emptySnapshot
        ) == .unsupported(.unsupportedCombination))
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
        _ = registry.evaluate(
            request: formulaRequest(
                surface: .semantic(.budget),
                operation: .forecast,
                measure: .projectedSpend,
                dateRange: HomeQueryDateRange(startDate: date(2026, 6, 1), endDate: date(2026, 6, 30))
            ),
            snapshot: fixture.snapshot
        )
        _ = registry.evaluate(
            request: formulaRequest(
                surface: .semantic(.category),
                operation: .share,
                measure: .concentration,
                dateRange: HomeQueryDateRange(startDate: date(2026, 6, 1), endDate: date(2026, 6, 30))
            ),
            snapshot: fixture.snapshot
        )
        _ = registry.evaluate(
            request: formulaRequest(
                surface: .semantic(.preset),
                operation: .sum,
                measure: .recurringBurden,
                dateRange: HomeQueryDateRange(startDate: date(2026, 6, 1), endDate: date(2026, 6, 30))
            ),
            snapshot: fixture.snapshot
        )
        _ = registry.evaluate(
            request: formulaRequest(
                surface: .semantic(.savingsAccount),
                operation: .forecast,
                measure: .savingsTotal,
                dateRange: HomeQueryDateRange(startDate: date(2026, 6, 1), endDate: date(2026, 6, 30))
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
        filters: [MarinaRowFilter] = [],
        categoryAvailabilityFilter: MarinaCategoryAvailabilityFilter? = nil,
        whatIfAmount: Double? = nil
    ) -> MarinaFormulaRequest {
        MarinaFormulaRequest(
            surface: surface,
            projection: .records,
            operation: operation,
            measure: measure,
            dateRange: dateRange,
            comparisonDateRange: nil,
            filters: filters,
            search: nil,
            groupBy: nil,
            offset: 0,
            limit: nil,
            whatIfAmount: whatIfAmount,
            categoryAvailabilityFilter: categoryAvailabilityFilter
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

    private func detailValue(
        _ component: MarinaFormulaMetricComponent,
        in metric: MarinaFormulaMetric
    ) -> MarinaValue? {
        metric.details.first { $0.component == component }?.value
    }

    private func numericValue(_ value: MarinaValue?) -> Double? {
        switch value {
        case let .money(value)?:
            return value
        case let .number(value)?:
            return value
        case let .integer(value)?:
            return Double(value)
        case .text, .date, .boolean, .colorHex, .empty, nil:
            return nil
        }
    }

    private func makeFixture(includePlannedIncome: Bool = true) -> FormulaFixture {
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
            incomes: includePlannedIncome ? [incomeActual, incomePlanned] : [incomeActual]
        )

        return FormulaFixture(snapshot: snapshot, emergency: emergency, roommate: roommate)
    }

    private func makeCategoryFormulaFixture() -> FormulaFixture {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let budget = Budget(name: "June", startDate: date(2026, 6, 1), endDate: date(2026, 6, 30), workspace: workspace)
        let card = Card(name: "Apple Card", theme: "ruby", effect: "plastic", workspace: workspace)
        let groceries = Offshore.Category(name: "Groceries", hexColor: "#22C55E", workspace: workspace)
        let bills = Offshore.Category(name: "Bills", hexColor: "#0EA5E9", workspace: workspace)
        let groceriesLimit = BudgetCategoryLimit(minAmount: 0, maxAmount: 100, budget: budget, category: groceries)
        let billsLimit = BudgetCategoryLimit(minAmount: 0, maxAmount: 500, budget: budget, category: bills)
        budget.categoryLimits = [groceriesLimit, billsLimit]

        let emergency = SavingsAccount(name: "Emergency Fund", total: 300, createdAt: date(2026, 1, 1), updatedAt: date(2026, 6, 1), workspace: workspace)
        let roommate = AllocationAccount(name: "Roommate", hexColor: "#14B8A6", workspace: workspace)
        let rent = PlannedExpense(title: "Rent", plannedAmount: 450, expenseDate: date(2026, 6, 10), workspace: workspace, card: card, category: bills)
        let groceriesRun = VariableExpense(descriptionText: "Groceries", amount: 150, transactionDate: date(2026, 6, 14), workspace: workspace, card: card, category: groceries)

        let snapshot = MarinaWorkspaceSnapshot(
            workspace: workspace,
            budgets: [budget],
            cards: [card],
            categories: [groceries, bills],
            presets: [],
            plannedExpenses: [rent],
            variableExpenses: [groceriesRun],
            homePlannedExpenses: [rent],
            homeCalculationPlannedExpenses: [rent],
            homeCalculationVariableExpenses: [groceriesRun],
            reconciliationAccounts: [roommate],
            expenseAllocations: [],
            allocationSettlements: [],
            savingsAccounts: [emergency],
            savingsEntries: [],
            incomes: []
        )

        return FormulaFixture(snapshot: snapshot, emergency: emergency, roommate: roommate)
    }

    private func makeRemainingFormulaFixture() -> FormulaFixture {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let budget = Budget(name: "June", startDate: date(2026, 6, 1), endDate: date(2026, 6, 30), workspace: workspace)
        let card = Card(name: "Apple Card", theme: "ruby", effect: "plastic", workspace: workspace)
        let category = Offshore.Category(name: "General", hexColor: "#22C55E", workspace: workspace)
        let phonePreset = Preset(title: "Phone", plannedAmount: 80, workspace: workspace, defaultCard: card, defaultCategory: category)

        let emergency = SavingsAccount(name: "Emergency Fund", total: 300, createdAt: date(2026, 1, 1), updatedAt: date(2026, 6, 1), workspace: workspace)
        let roommate = AllocationAccount(name: "Roommate", hexColor: "#14B8A6", workspace: workspace)
        let phoneBill = PlannedExpense(
            title: "Phone Bill",
            plannedAmount: 80,
            expenseDate: date(2026, 6, 16),
            workspace: workspace,
            card: card,
            category: category,
            sourcePresetID: phonePreset.id,
            sourceBudgetID: budget.id
        )
        let rent = PlannedExpense(
            title: "Rent",
            plannedAmount: 120,
            expenseDate: date(2026, 6, 25),
            workspace: workspace,
            card: card,
            category: category,
            sourceBudgetID: budget.id
        )
        let variableExpense = VariableExpense(descriptionText: "Groceries", amount: 100, transactionDate: date(2026, 6, 14), workspace: workspace, card: card, category: category)
        let actualIncome = Income(source: "Paycheck", amount: 900, date: date(2026, 6, 1), isPlanned: false, workspace: workspace)
        let plannedIncome = Income(source: "Expected Paycheck", amount: 1_000, date: date(2026, 6, 20), isPlanned: true, workspace: workspace)
        let savingsAdjustment = SavingsLedgerEntry(
            date: date(2026, 6, 15),
            amount: 25,
            note: "Manual savings",
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
            workspace: workspace,
            account: emergency
        )

        let snapshot = MarinaWorkspaceSnapshot(
            workspace: workspace,
            budgets: [budget],
            cards: [card],
            categories: [category],
            presets: [phonePreset],
            plannedExpenses: [phoneBill, rent],
            variableExpenses: [variableExpense],
            homePlannedExpenses: [phoneBill, rent],
            homeCalculationPlannedExpenses: [phoneBill, rent],
            homeCalculationVariableExpenses: [variableExpense],
            reconciliationAccounts: [roommate],
            expenseAllocations: [],
            allocationSettlements: [],
            savingsAccounts: [emergency],
            savingsEntries: [savingsAdjustment],
            incomes: [actualIncome, plannedIncome]
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

private struct FormulaTestFailure: Error {}
