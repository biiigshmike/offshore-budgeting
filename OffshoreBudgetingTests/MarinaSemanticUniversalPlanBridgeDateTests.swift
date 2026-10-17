import Foundation
import Testing
@testable import Offshore

struct MarinaSemanticUniversalPlanBridgeDateTests {
    private let bridge = MarinaSemanticUniversalPlanBridge()

    @Test func currentMonthMapsToDateFiltersForVariableExpenses() throws {
        let plan = try requirePlan(bridge.makePlan(
            from: request(entity: .variableExpense, operation: .sum, measure: .budgetImpact, dateRangeToken: .currentMonth),
            planningContext: context(now: date(2026, 6, 15))
        ))

        #expect(dateFilters(in: plan) == filters(field: .transactionDate, start: date(2026, 6, 1), end: date(2026, 6, 30)))
        #expect(plan.requiresDateField)
    }

    @Test func previousMonthMapsToDateFiltersForVariableExpenses() throws {
        let plan = try requirePlan(bridge.makePlan(
            from: request(entity: .variableExpense, operation: .sum, measure: .budgetImpact, dateRangeToken: .previousMonth),
            planningContext: context(now: date(2026, 6, 15))
        ))

        #expect(dateFilters(in: plan) == filters(field: .transactionDate, start: date(2026, 5, 1), end: date(2026, 5, 31)))
    }

    @Test func currentPeriodUsesAmbientRangeWhenProvided() throws {
        let ambientRange = HomeQueryDateRange(startDate: date(2026, 4, 10), endDate: date(2026, 4, 20))
        let plan = try requirePlan(bridge.makePlan(
            from: request(entity: .variableExpense, operation: .sum, measure: .budgetImpact, dateRangeToken: .currentPeriod),
            planningContext: context(ambientDateRange: ambientRange, now: date(2026, 6, 15))
        ))

        #expect(dateFilters(in: plan) == filters(field: .transactionDate, start: date(2026, 4, 10), end: date(2026, 4, 20)))
    }

    @Test func currentPeriodFallsBackToDefaultBudgetingPeriod() throws {
        let plan = try requirePlan(bridge.makePlan(
            from: request(entity: .variableExpense, operation: .sum, measure: .budgetImpact, dateRangeToken: .currentPeriod),
            planningContext: context(defaultBudgetingPeriod: .quarterly, now: date(2026, 5, 15))
        ))

        #expect(dateFilters(in: plan) == filters(field: .transactionDate, start: date(2026, 4, 1), end: date(2026, 6, 30)))
    }

    @Test func previousPeriodMapsToPreviousEquivalentPeriod() throws {
        let ambientRange = HomeQueryDateRange(startDate: date(2026, 4, 10), endDate: date(2026, 4, 20))
        let plan = try requirePlan(bridge.makePlan(
            from: request(entity: .variableExpense, operation: .sum, measure: .budgetImpact, dateRangeToken: .previousPeriod),
            planningContext: context(ambientDateRange: ambientRange, now: date(2026, 6, 15))
        ))

        #expect(dateFilters(in: plan) == filters(field: .transactionDate, start: date(2026, 3, 30), end: date(2026, 4, 9)))
    }

    @Test func nextSevenDaysMapsToTodayThroughSixDaysAhead() throws {
        let plan = try requirePlan(bridge.makePlan(
            from: request(entity: .plannedExpense, operation: .next, measure: .effectiveAmount, dateRangeToken: .nextSevenDays),
            planningContext: context(now: date(2026, 6, 15, 14, 30, 0))
        ))

        #expect(dateFilters(in: plan) == filters(field: .expenseDate, start: date(2026, 6, 15), end: date(2026, 6, 21)))
    }

    @Test func allTimeCreatesNoDateFilters() throws {
        let plan = try requirePlan(bridge.makePlan(
            from: request(entity: .variableExpense, operation: .sum, measure: .budgetImpact, dateRangeToken: .allTime),
            planningContext: context(now: date(2026, 6, 15))
        ))

        #expect(dateFilters(in: plan).isEmpty)
        #expect(plan.requiresDateField == false)
    }

    @Test func dateBackedEntityWithoutDefaultDateFieldReturnsMissingDateField() {
        var entities = MarinaEntityCatalog.defaultEntities
        let descriptor = entities[.variableExpense]!
        entities[.variableExpense] = MarinaEntityDescriptor(
            entity: descriptor.entity,
            displayName: descriptor.displayName,
            aliases: descriptor.aliases,
            fields: descriptor.fields,
            relationships: descriptor.relationships,
            supportedOperations: descriptor.supportedOperations,
            supportedMeasures: descriptor.supportedMeasures,
            defaultDateField: nil,
            defaultAmountField: descriptor.defaultAmountField,
            defaultSearchFields: descriptor.defaultSearchFields,
            workspaceScoped: descriptor.workspaceScoped,
            isInternalOnly: descriptor.isInternalOnly
        )
        let bridge = MarinaSemanticUniversalPlanBridge(catalog: MarinaEntityCatalog(entities: entities))
        let result = bridge.makePlan(
            from: request(entity: .variableExpense, operation: .sum, measure: .budgetImpact, dateRangeToken: .currentMonth),
            planningContext: context(now: date(2026, 6, 15))
        )

        #expect(result == .unsupported(.missingDateField))
    }

    @Test func plannedExpensesUseExpenseDate() throws {
        let plan = try requirePlan(bridge.makePlan(
            from: request(entity: .plannedExpense, operation: .sum, measure: .effectiveAmount, dateRangeToken: .currentMonth),
            planningContext: context(now: date(2026, 6, 15))
        ))

        #expect(dateFilterFields(in: plan) == [.expenseDate, .expenseDate])
    }

    @Test func variableExpensesUseTransactionDate() throws {
        let plan = try requirePlan(bridge.makePlan(
            from: request(entity: .variableExpense, operation: .sum, measure: .budgetImpact, dateRangeToken: .currentMonth),
            planningContext: context(now: date(2026, 6, 15))
        ))

        #expect(dateFilterFields(in: plan) == [.transactionDate, .transactionDate])
    }

    @Test func incomeUsesDate() throws {
        let plan = try requirePlan(bridge.makePlan(
            from: request(entity: .income, operation: .sum, measure: .incomeAmount, dateRangeToken: .currentMonth),
            planningContext: context(now: date(2026, 6, 15))
        ))

        #expect(dateFilterFields(in: plan) == [.date, .date])
    }

    @Test func metadataListsDoNotApplyDateFilters() throws {
        let entities: [MarinaSemanticEntity] = [.category, .card, .budget, .preset]

        for entity in entities {
            let plan = try requirePlan(bridge.makePlan(
                from: request(entity: entity, operation: .list, dateRangeToken: .currentMonth, shape: .list),
                planningContext: context(now: date(2026, 6, 15))
            ))

            #expect(dateFilters(in: plan).isEmpty)
            #expect(plan.requiresDateField == false)
        }
    }

    private func request(
        entity: MarinaSemanticEntity,
        operation: MarinaSemanticOperation,
        measure: MarinaSemanticMeasure? = nil,
        dateRangeToken: MarinaSemanticDateRangeToken,
        shape: MarinaSemanticAnswerShape = .metric
    ) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: entity,
            operation: operation,
            measure: measure,
            dateRangeToken: dateRangeToken,
            expectedAnswerShape: shape
        )
    }

    private func context(
        ambientDateRange: HomeQueryDateRange? = nil,
        defaultBudgetingPeriod: BudgetingPeriod = .monthly,
        now: Date
    ) -> MarinaUniversalPlanningContext {
        MarinaUniversalPlanningContext(
            ambientDateRange: ambientDateRange,
            defaultBudgetingPeriod: defaultBudgetingPeriod,
            now: now,
            calendar: calendar
        )
    }

    private func filters(
        field: MarinaFieldKey,
        start: Date,
        end: Date
    ) -> [MarinaRowFilter] {
        [
            MarinaRowFilter(target: .field(field), operation: .greaterThanOrEqual, value: .date(start)),
            MarinaRowFilter(target: .field(field), operation: .lessThanOrEqual, value: .date(end))
        ]
    }

    private func dateFilters(in plan: MarinaUniversalQueryPlan) -> [MarinaRowFilter] {
        plan.filters.filter { filter in
            guard case .field = filter.target,
                  case .date = filter.value else {
                return false
            }
            return true
        }
    }

    private func dateFilterFields(in plan: MarinaUniversalQueryPlan) -> [MarinaFieldKey] {
        dateFilters(in: plan).compactMap { filter in
            if case let .field(field) = filter.target {
                return field
            }
            return nil
        }
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        date(year, month, day, 0, 0, 0)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.timeZone = TimeZone(secondsFromGMT: 0)

        return calendar.date(from: components) ?? .distantPast
    }

    private func requirePlan(
        _ result: MarinaSemanticUniversalPlanBridgeResult
    ) throws -> MarinaUniversalQueryPlan {
        guard case let .plan(plan) = result else {
            Issue.record("Expected plan result, got \(result).")
            throw BridgeDateTestError.expectedPlan
        }
        return plan
    }
}

private enum BridgeDateTestError: Error {
    case expectedPlan
}
