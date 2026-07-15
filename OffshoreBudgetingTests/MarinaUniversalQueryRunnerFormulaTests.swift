import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaUniversalQueryRunnerFormulaTests {
    @Test func rowBackedMeasuresStillWorkThroughFormulaAwareRunner() {
        let fixture = makeFixture()
        let runner = formulaRunner()

        let metric = requireMetric(runner.runFormulaAware(
            plan: MarinaUniversalQueryPlan(
                entity: .variableExpense,
                operation: .sum,
                measure: .budgetImpact
            ),
            snapshot: fixture.snapshot
        ))

        #expect(metric.value == .money(150))
        #expect(metric.evidenceRows.map(\.displayName) == ["Groceries"])
    }

    @Test func formulaBackedSavingsTotalRoutesThroughRegistry() {
        let fixture = makeFixture()
        let runner = formulaRunner()

        let metric = requireMetric(runner.runFormulaAware(
            plan: MarinaUniversalQueryPlan(
                entity: .savingsAccount,
                operation: .sum,
                measure: .savingsTotal,
                filters: [nameFilter("Emergency Fund")]
            ),
            snapshot: fixture.snapshot
        ))

        #expect(metric.value == .money(300))
        #expect(metric.evidenceRows.map(\.displayName) == ["Emergency Fund"])
    }

    @Test func formulaBackedSafeDailySpendRoutesThroughRegistry() {
        let fixture = makeFixture()
        let runner = formulaRunner()
        let range = HomeQueryDateRange(startDate: date(2026, 6, 1), endDate: date(2026, 6, 30))
        let plan = MarinaUniversalQueryPlan(
            entity: .budget,
            operation: .forecast,
            measure: .safeDailySpend,
            dateRange: range
        )

        let metric = requireMetric(runner.runFormulaAware(
            plan: plan,
            snapshot: fixture.snapshot
        ))
        let expected = SafeSpendTodayCalculator.calculate(
            budgetingPeriod: .monthly,
            rangeStart: range.startDate,
            rangeEnd: range.endDate,
            budgets: fixture.snapshot.budgets,
            categories: fixture.snapshot.categories,
            incomes: fixture.snapshot.incomes,
            plannedExpenses: fixture.snapshot.homeCalculationPlannedExpenses,
            variableExpenses: fixture.snapshot.homeCalculationVariableExpenses,
            savingsEntries: fixture.snapshot.savingsEntries,
            now: date(2026, 6, 15),
            calendar: calendar
        )

        #expect(metric.value == .money(expected.safeToSpendToday))
        #expect(metric.evidenceRows.map(\.displayName) == ["June"])
        #expect(metric.details.map(\.component).contains(.period))
        #expect(metric.details.map(\.component).contains(.remainingDays))
        #expect(metric.details.map(\.component).contains(.plannedSpending))
        #expect(metric.details.map(\.component).contains(.plannedSpendingRemaining))
        #expect(metric.details.map(\.component).contains(.actualSpendSoFar))
        #expect(metric.details.map(\.component).contains(.periodRemainingRoom))
        #expect(metric.details.map(\.component).contains(.safePerDay))
        #expect(metric.details.map(\.component).contains(.clampedToZero))
    }

    @Test func formulaBackedIncomeProgressRoutesThroughRegistry() {
        let fixture = makeFixture()
        let runner = formulaRunner()
        let metric = requireMetric(runner.runFormulaAware(
            plan: MarinaUniversalQueryPlan(
                entity: .income,
                operation: .share,
                measure: .incomeAmount,
                dateRange: HomeQueryDateRange(startDate: date(2026, 6, 1), endDate: date(2026, 6, 30))
            ),
            snapshot: fixture.snapshot
        ))

        #expect(metric.value == .number(2))
        #expect(metric.evidenceRows.map(\.displayName).sorted() == ["Bonus", "Paycheck"])
        #expect(metric.presentationRows.map(\.title) == ["Actual", "Planned", "Progress"])
    }

    @Test func safeDailySpendPresentationExplainsZeroClamp() {
        let fixture = makeFixture(extraVariableExpenseAmount: 5_000)
        let runner = formulaRunner()
        let presenter = MarinaUniversalResultPresenter()
        let range = HomeQueryDateRange(startDate: date(2026, 6, 1), endDate: date(2026, 6, 30))
        let plan = MarinaUniversalQueryPlan(
            entity: .budget,
            operation: .forecast,
            measure: .safeDailySpend,
            dateRange: range
        )
        let result = runner.runFormulaAware(plan: plan, snapshot: fixture.snapshot)
        let presented = presenter.presentationResult(
            for: result,
            plan: plan,
            context: MarinaUniversalPresentationContext(
                dateRange: range,
                semanticRequest: MarinaSemanticRequest(
                    entity: .budget,
                    operation: .forecast,
                    measure: .safeDailySpend,
                    dateRangeToken: .currentMonth,
                    expectedAnswerShape: .metric
                ),
                now: date(2026, 6, 15),
                calendar: calendar
            )
        )

        #expect(presented.title == "Safe Daily Spend")
        #expect(presented.primaryValue == CurrencyFormatter.string(from: 0))
        #expect(presented.rows.map(\.title) == [
            "Period",
            "Remaining days",
            "Planned spending remaining",
            "Actual spend so far",
            "Remaining room",
            "Safe per day"
        ])
        #expect(presented.rows.first(where: { $0.title == "Remaining days" })?.amount == 16)
        #expect(presented.rows.first(where: { $0.title == "Planned spending remaining" })?.amount == 200)
        #expect(presented.rows.first(where: { $0.title == "Actual spend so far" }) != nil)
        #expect(presented.rows.first(where: { $0.title == "Remaining room" })?.amount == 0)
        #expect(presented.rows.first(where: { $0.title == "Safe per day" })?.amount == 0)
        #expect(presented.rows.contains { $0.title == "Planned spending" } == false)
        #expect(presented.rows.contains { $0.title == "Clamped to zero" } == false)
        #expect(presented.explanation == "Your safe daily spend is $0.00 because there is no remaining room left in this budgeting period.")
    }

    @Test func budgetPaceFormulaMeasuresRouteThroughRegistry() {
        let fixture = makeFixture()
        let runner = formulaRunner()
        let range = HomeQueryDateRange(startDate: date(2026, 6, 1), endDate: date(2026, 6, 30))

        let burnRate = requireMetric(runner.runFormulaAware(
            plan: MarinaUniversalQueryPlan(
                entity: .budget,
                operation: .average,
                measure: .burnRate,
                dateRange: range
            ),
            snapshot: fixture.snapshot
        ))
        #expect(burnRate.value == .money(250.0 / 15.0))
        #expect(burnRate.details.map(\.component) == [.spentSoFar, .elapsedDays, .averagePerDay])

        let projectedSpend = requireMetric(runner.runFormulaAware(
            plan: MarinaUniversalQueryPlan(
                entity: .budget,
                operation: .forecast,
                measure: .projectedSpend,
                dateRange: range
            ),
            snapshot: fixture.snapshot
        ))
        let safeSpendSummary = SafeSpendTodayCalculator.calculate(
            budgetingPeriod: .monthly,
            rangeStart: range.startDate,
            rangeEnd: range.endDate,
            budgets: fixture.snapshot.budgets,
            categories: fixture.snapshot.categories,
            incomes: fixture.snapshot.incomes,
            plannedExpenses: fixture.snapshot.homeCalculationPlannedExpenses,
            variableExpenses: fixture.snapshot.homeCalculationVariableExpenses,
            savingsEntries: fixture.snapshot.savingsEntries,
            now: date(2026, 6, 15),
            calendar: calendar
        )
        let expectedProjectedSpend = safeSpendSummary.actualSpendSoFar + safeSpendSummary.plannedSpendingRemaining
        #expect(abs((numericValue(projectedSpend.value) ?? 0) - expectedProjectedSpend) < 0.0001)

        let paceDifference = requireMetric(runner.runFormulaAware(
            plan: MarinaUniversalQueryPlan(
                entity: .budget,
                operation: .compare,
                measure: .paceDifference,
                dateRange: range
            ),
            snapshot: fixture.snapshot
        ))
        #expect(paceDifference.value == .money(100))

        let budgetCoverage = requireMetric(runner.runFormulaAware(
            plan: MarinaUniversalQueryPlan(
                entity: .budget,
                operation: .forecast,
                measure: .coverageRatio,
                dateRange: range
            ),
            snapshot: fixture.snapshot
        ))
        #expect(budgetCoverage.value == .number(1_000.0 / 300.0))

        let incomeCoverage = requireMetric(runner.runFormulaAware(
            plan: MarinaUniversalQueryPlan(
                entity: .income,
                operation: .share,
                measure: .coverageRatio,
                dateRange: range
            ),
            snapshot: fixture.snapshot
        ))
        #expect(incomeCoverage.value == .number(1_000.0 / 300.0))
        #expect(incomeCoverage.details.map(\.component) == [.income, .plannedExpenses, .coveragePercent, .difference])
    }

    @Test func categoryFormulaMeasuresRouteThroughRegistry() {
        let fixture = makeFixture()
        let runner = formulaRunner()
        let range = HomeQueryDateRange(startDate: date(2026, 6, 1), endDate: date(2026, 6, 30))

        let availability = requireMetric(runner.runFormulaAware(
            plan: MarinaUniversalQueryPlan(
                entity: .category,
                operation: .forecast,
                measure: .categoryAvailability,
                dateRange: range
            ),
            snapshot: fixture.snapshot
        ))
        #expect(availability.value == .integer(1))
        #expect(availability.details.map(\.component) == [.activeBudget, .overCount, .nearCount, .categoryCount])

        let concentration = requireMetric(runner.runFormulaAware(
            plan: MarinaUniversalQueryPlan(
                entity: .category,
                operation: .share,
                measure: .concentration,
                dateRange: range
            ),
            snapshot: fixture.snapshot
        ))
        #expect(concentration.value == .number(1))
        #expect(concentration.details.map(\.component) == [.category, .categorySpend, .totalSpend, .concentration])
    }

    @Test func remainingFormulaMeasuresRouteThroughRegistry() throws {
        let fixture = makeFixture()
        let runner = formulaRunner()
        let range = HomeQueryDateRange(startDate: date(2026, 6, 1), endDate: date(2026, 6, 30))

        let recurringBurden = requireMetric(runner.runFormulaAware(
            plan: MarinaUniversalQueryPlan(
                entity: .preset,
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
        #expect(recurringBurden.details.map(\.component) == [.recurringTotal, .plannedExpenses, .recurringBurden])

        let forecastSavings = requireMetric(runner.runFormulaAware(
            plan: MarinaUniversalQueryPlan(
                entity: .savingsAccount,
                operation: .forecast,
                measure: .savingsTotal,
                dateRange: range
            ),
            snapshot: fixture.snapshot
        ))
        #expect(forecastSavings.value == .money(200))
        #expect(forecastSavings.details.map(\.component) == [.projectedSavings, .actualSavings, .gapToProjected, .forecastStatus])
    }

    @Test func formulaMissingDateContextReturnsTypedUnsupported() {
        let fixture = makeFixture()
        let runner = formulaRunner()

        #expect(runner.runFormulaAware(
            plan: MarinaUniversalQueryPlan(
                entity: .budget,
                operation: .average,
                measure: .burnRate
            ),
            snapshot: fixture.snapshot
        ) == .unsupported(.missingDateField))

        #expect(runner.runFormulaAware(
            plan: MarinaUniversalQueryPlan(
                entity: .category,
                operation: .forecast,
                measure: .categoryAvailability
            ),
            snapshot: fixture.snapshot
        ) == .unsupported(.missingDateField))

        #expect(runner.runFormulaAware(
            plan: MarinaUniversalQueryPlan(
                entity: .preset,
                operation: .sum,
                measure: .recurringBurden
            ),
            snapshot: fixture.snapshot
        ) == .unsupported(.missingDateField))

        #expect(runner.runFormulaAware(
            plan: MarinaUniversalQueryPlan(
                entity: .savingsAccount,
                operation: .forecast,
                measure: .savingsTotal
            ),
            snapshot: fixture.snapshot
        ) == .unsupported(.missingDateField))
    }

    @Test func unsupportedFormulaMeasureReturnsTypedUnsupported() {
        let fixture = makeFixture()
        let runner = formulaRunner()

        #expect(runner.runFormulaAware(
            plan: MarinaUniversalQueryPlan(entity: .category, operation: .sum, measure: .categoryAvailability),
            snapshot: fixture.snapshot
        ) == .unsupported(.measureNotAvailable))

        #expect(runner.runFormulaAware(
            plan: MarinaUniversalQueryPlan(entity: .preset, operation: .sum, measure: .savingsTotal),
            snapshot: fixture.snapshot
        ) == .unsupported(.measureNotAvailable))

        #expect(runner.runFormulaAware(
            plan: MarinaUniversalQueryPlan(entity: .preset, operation: .forecast, measure: .recurringBurden),
            snapshot: fixture.snapshot
        ) == .unsupported(.operationNotSupported))
    }

    @Test func formulaBackedRequestsDoNotBypassCatalogValidation() {
        let fixture = makeFixture()
        let runner = formulaRunner()

        #expect(runner.runFormulaAware(
            plan: MarinaUniversalQueryPlan(
                entity: .savingsAccount,
                operation: .sum,
                measure: .savingsTotal,
                search: MarinaRowSearchClause(fields: [.amount], query: "300"),
                filters: [nameFilter("Emergency Fund")]
            ),
            snapshot: fixture.snapshot
        ) == .unsupported(.fieldNotSearchable))
    }

    @Test func defaultRunnerStillTreatsFormulaMeasuresAsDeferred() {
        let fixture = makeFixture()
        let runner = MarinaUniversalQueryRunner()

        #expect(runner.run(
            plan: MarinaUniversalQueryPlan(entity: .savingsAccount, operation: .list, measure: .savingsTotal),
            snapshot: fixture.snapshot
        ) == .unsupported(.measureNotAvailable))
    }

    private func formulaRunner() -> MarinaUniversalQueryRunner {
        MarinaUniversalQueryRunner(
            formulaRegistry: MarinaFormulaRegistry(now: date(2026, 6, 15), calendar: calendar)
        )
    }

    private func nameFilter(_ name: String) -> MarinaRowFilter {
        MarinaRowFilter(target: .field(.name), operation: .equals, value: .text(name))
    }

    private func requireMetric(_ result: MarinaUniversalQueryResult) -> MarinaUniversalMetricResult {
        guard case let .metric(metric) = result else {
            Issue.record("Expected universal metric, got \(result).")
            return MarinaUniversalMetricResult(value: .empty, evidenceRows: [])
        }
        return metric
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

    private func makeFixture(extraVariableExpenseAmount: Double? = nil) -> FormulaRunnerFixture {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let budget = Budget(name: "June", startDate: date(2026, 6, 1), endDate: date(2026, 6, 30), workspace: workspace)
        let card = Card(name: "Apple Card", theme: "ruby", effect: "plastic", workspace: workspace)
        let category = Offshore.Category(name: "General", hexColor: "#22C55E", workspace: workspace)
        let emergency = SavingsAccount(name: "Emergency Fund", total: 300, createdAt: date(2026, 1, 1), updatedAt: date(2026, 6, 1), workspace: workspace)
        let internetPreset = Preset(title: "Internet", plannedAmount: 200, workspace: workspace, defaultCard: card, defaultCategory: category)
        let variableExpense = VariableExpense(descriptionText: "Groceries", amount: 150, transactionDate: date(2026, 6, 14), workspace: workspace, card: card, category: category)
        let extraVariableExpense = extraVariableExpenseAmount.map {
            VariableExpense(descriptionText: "Large adjustment", amount: $0, transactionDate: date(2026, 6, 15), workspace: workspace, card: card, category: category)
        }
        let incomeActual = Income(source: "Paycheck", amount: 1_000, date: date(2026, 6, 1), isPlanned: false, workspace: workspace)
        let incomePlanned = Income(source: "Bonus", amount: 500, date: date(2026, 6, 20), isPlanned: true, workspace: workspace)
        let consumedPlanned = PlannedExpense(title: "Rent", plannedAmount: 100, expenseDate: date(2026, 6, 10), workspace: workspace, card: card, category: category)
        let remainingPlanned = PlannedExpense(title: "Internet", plannedAmount: 200, expenseDate: date(2026, 6, 20), workspace: workspace, card: card, category: category, sourcePresetID: internetPreset.id)
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
            presets: [internetPreset],
            plannedExpenses: [consumedPlanned, remainingPlanned],
            variableExpenses: [variableExpense] + [extraVariableExpense].compactMap { $0 },
            homePlannedExpenses: [consumedPlanned, remainingPlanned],
            homeCalculationPlannedExpenses: [consumedPlanned, remainingPlanned],
            homeCalculationVariableExpenses: [variableExpense] + [extraVariableExpense].compactMap { $0 },
            reconciliationAccounts: [],
            expenseAllocations: [],
            allocationSettlements: [],
            savingsAccounts: [emergency],
            savingsEntries: [savingsAdjustment],
            incomes: [incomeActual, incomePlanned]
        )

        return FormulaRunnerFixture(snapshot: snapshot)
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

private struct FormulaRunnerFixture {
    let snapshot: MarinaWorkspaceSnapshot
}
