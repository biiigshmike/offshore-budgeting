import Foundation

struct MarinaUniversalPresentationContext: Equatable, Sendable {
    let dateRange: HomeQueryDateRange?
    let comparisonDateRange: HomeQueryDateRange?
    let semanticRequest: MarinaSemanticRequest?
    let now: Date
    let calendar: Calendar

    init(
        dateRange: HomeQueryDateRange? = nil,
        comparisonDateRange: HomeQueryDateRange? = nil,
        semanticRequest: MarinaSemanticRequest? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.dateRange = dateRange
        self.comparisonDateRange = comparisonDateRange
        self.semanticRequest = semanticRequest
        self.now = now
        self.calendar = calendar
    }
}

struct MarinaUniversalPresentationResult: Equatable {
    let executionResult: MarinaExecutionResult
    let unsupportedReason: MarinaCapabilityFailureReason?

    init(
        executionResult: MarinaExecutionResult,
        unsupportedReason: MarinaCapabilityFailureReason? = nil
    ) {
        self.executionResult = executionResult
        self.unsupportedReason = unsupportedReason
    }
}

struct MarinaUniversalResultPresenter {
    func presentationResult(
        for universalResult: MarinaUniversalQueryResult,
        plan: MarinaUniversalQueryPlan,
        context: MarinaUniversalPresentationContext
    ) -> MarinaExecutionResult {
        presentedResult(
            for: universalResult,
            plan: plan,
            context: context
        )
        .executionResult
    }

    func presentedResult(
        for universalResult: MarinaUniversalQueryResult,
        plan: MarinaUniversalQueryPlan,
        context: MarinaUniversalPresentationContext
    ) -> MarinaUniversalPresentationResult {
        switch universalResult {
        case let .metric(metric):
            return .init(executionResult: metricResult(metric, plan: plan, context: context))
        case let .rows(rows):
            return .init(executionResult: rowsResult(rows, plan: plan, context: context))
        case let .rowsPage(page):
            return .init(executionResult: rowsPageResult(page, plan: plan, context: context))
        case let .groups(groups):
            return .init(executionResult: groupsResult(groups, plan: plan, context: context))
        case let .unsupported(reason):
            return unsupportedResult(reason)
        }
    }

    func presentationResult(
        for formulaResult: MarinaFormulaResult,
        plan: MarinaUniversalQueryPlan,
        context: MarinaUniversalPresentationContext
    ) -> MarinaExecutionResult {
        presentedResult(
            for: formulaResult,
            plan: plan,
            context: context
        )
        .executionResult
    }

    func presentedResult(
        for formulaResult: MarinaFormulaResult,
        plan: MarinaUniversalQueryPlan,
        context: MarinaUniversalPresentationContext
    ) -> MarinaUniversalPresentationResult {
        switch formulaResult {
        case let .metric(metric):
            return .init(
                executionResult: metricResult(
                    MarinaUniversalMetricResult(
                        value: metric.value,
                        evidenceRows: metric.evidenceRows,
                        details: metric.details,
                        presentationRows: metric.presentationRows
                    ),
                    plan: plan,
                    context: context
                )
            )
        case let .rows(rows):
            return .init(executionResult: rowsResult(rows, plan: plan, context: context))
        case let .groups(groups):
            return .init(executionResult: formulaGroupsResult(groups, plan: plan, context: context))
        case let .unsupported(reason):
            return unsupportedResult(reason)
        }
    }

    private func metricResult(
        _ metric: MarinaUniversalMetricResult,
        plan: MarinaUniversalQueryPlan,
        context: MarinaUniversalPresentationContext
    ) -> MarinaExecutionResult {
        let value = formattedMetricValue(metric.value, measure: plan.measure, details: metric.details)
        let presentationRows = metric.presentationRows.map { presentationRow in
            HomeAnswerRow(
                title: presentationRow.title,
                value: formattedPresentationRowValue(presentationRow),
                amount: presentationRow.amount
            )
        }
        let detailRows = metric.details.map { detail in
            HomeAnswerRow(
                title: title(for: detail.component),
                value: formattedDetailValue(detail),
                amount: numericValue(detail.value)
            )
        }
        let rows = presentationRows + (presentationRows.isEmpty && detailRows.isEmpty ? [
            HomeAnswerRow(
                title: "Value",
                value: value,
                amount: numericValue(metric.value)
            )
        ] : detailRows) + metric.evidenceRows.map { row in
            homeAnswerRow(from: row, plan: plan, role: .evidence)
        }

        return MarinaExecutionResult(
            kind: kind(for: plan),
            title: title(for: plan, context: context),
            subtitle: subtitle(for: context),
            primaryValue: value,
            rows: rows
        )
    }

    private func rowsResult(
        _ rows: [MarinaQueryableRow],
        plan: MarinaUniversalQueryPlan,
        context: MarinaUniversalPresentationContext
    ) -> MarinaExecutionResult {
        guard rows.isEmpty == false else {
            return emptyResult(plan: plan, context: context)
        }

        return MarinaExecutionResult(
            kind: .list,
            title: title(for: plan, context: context),
            subtitle: subtitle(for: context),
            rows: rows.map { homeAnswerRow(from: $0, plan: plan, role: .result) }
        )
    }

    private func rowsPageResult(
        _ page: MarinaUniversalRowsPage,
        plan: MarinaUniversalQueryPlan,
        context: MarinaUniversalPresentationContext
    ) -> MarinaExecutionResult {
        guard page.rows.isEmpty == false else {
            return emptyResult(plan: plan, context: context)
        }

        return MarinaExecutionResult(
            kind: .list,
            title: title(for: plan, context: context),
            subtitle: listSubtitle(for: page, plan: plan, context: context),
            primaryValue: page.fullTotalAmount.map(CurrencyFormatter.string(from:)),
            rows: page.rows.map { homeAnswerRow(from: $0, plan: plan, role: .result) },
            displayedRowCount: page.rows.count,
            totalRowCount: page.totalRowCount,
            fullTotalAmount: page.fullTotalAmount
        )
    }

    private func groupsResult(
        _ groups: [MarinaUniversalGroupResult],
        plan: MarinaUniversalQueryPlan,
        context: MarinaUniversalPresentationContext
    ) -> MarinaExecutionResult {
        guard groups.isEmpty == false else {
            return emptyResult(plan: plan, context: context)
        }

        return MarinaExecutionResult(
            kind: .list,
            title: title(for: plan, context: context),
            subtitle: subtitle(for: context),
            rows: groups.map { group in
                groupRow(
                    displayName: group.group.displayName,
                    aggregate: group.aggregate,
                    count: group.group.rows.count
                )
            }
        )
    }

    private func formulaGroupsResult(
        _ groups: [MarinaFormulaGroup],
        plan: MarinaUniversalQueryPlan,
        context: MarinaUniversalPresentationContext
    ) -> MarinaExecutionResult {
        guard groups.isEmpty == false else {
            return emptyResult(plan: plan, context: context)
        }

        return MarinaExecutionResult(
            kind: .list,
            title: title(for: plan, context: context),
            subtitle: subtitle(for: context),
            rows: groups.map { group in
                groupRow(
                    displayName: group.displayName,
                    aggregate: group.value,
                    count: group.evidenceRows.count
                )
            }
        )
    }

    private func unsupportedResult(
        _ reason: MarinaCapabilityFailureReason
    ) -> MarinaUniversalPresentationResult {
        MarinaUniversalPresentationResult(
            executionResult: MarinaExecutionResult(
                kind: .message,
                title: "I can't answer that yet",
                subtitle: "That universal result is not supported for presentation yet."
            ),
            unsupportedReason: reason
        )
    }

    private func emptyResult(
        plan: MarinaUniversalQueryPlan,
        context: MarinaUniversalPresentationContext
    ) -> MarinaExecutionResult {
        MarinaExecutionResult(
            kind: .message,
            title: emptyTitle(for: plan, context: context),
            subtitle: genericEmptySubtitle(for: plan, context: context)
        )
    }

    private func homeAnswerRow(
        from row: MarinaQueryableRow,
        plan: MarinaUniversalQueryPlan,
        role: HomeAnswerRowRole
    ) -> HomeAnswerRow {
        let selectedValue = preferredDisplayValue(for: row, plan: plan)
        return HomeAnswerRow(
            title: row.displayName,
            value: formattedValue(selectedValue),
            sourceID: row.id,
            objectType: objectType(for: row.entity),
            amount: amount(for: row, plan: plan),
            date: date(for: row),
            role: role
        )
    }

    private func groupRow(
        displayName: String,
        aggregate: MarinaValue?,
        count: Int
    ) -> HomeAnswerRow {
        guard let aggregate else {
            return HomeAnswerRow(title: displayName, value: "\(count)")
        }

        return HomeAnswerRow(
            title: displayName,
            value: formattedValue(aggregate),
            amount: numericValue(aggregate)
        )
    }

    private func title(
        for plan: MarinaUniversalQueryPlan,
        context: MarinaUniversalPresentationContext
    ) -> String {
        if isExpenseList(plan),
           let target = displayTarget(in: context) {
            return "\(target) Expenses"
        }

        if let groupBy = plan.groupBy {
            switch groupBy {
            case .relationship(.category):
                return "Spending by Category"
            case .relationship(.card):
                return "Spending by Card"
            case .relationship(.incomeSource):
                return "Income by Source"
            case .field, .relationship:
                break
            }
        }

        switch plan.measure {
        case .savingsTotal:
            if plan.operation == .forecast {
                return "Forecast Savings"
            }
            return "Savings Total"
        case .reconciliationBalance:
            return "Reconciliation Balance"
        case .remainingRoom:
            return "Remaining Room"
        case .burnRate:
            return "Budget Pace"
        case .projectedSpend:
            return "Projected Spend"
        case .safeDailySpend:
            return "Safe Daily Spend"
        case .paceDifference:
            return "Pace Difference"
        case .coverageRatio:
            switch plan.entity {
            case .income:
                return "Income Coverage"
            case .budget:
                return "Budget Coverage"
            case .workspace, .card, .plannedExpense, .variableExpense, .reconciliationAccount, .savingsAccount, .category, .preset:
                return "Coverage Ratio"
            }
        case .categoryAvailability:
            return "Category Availability"
        case .concentration:
            return "Category Spend Share"
        case .recurringBurden:
            return "Recurring Burden"
        case .incomeAmount:
            return "Income"
        case .budgetImpact:
            switch plan.operation {
            case .average:
                return "Average Spending"
            case .sum:
                return "Spending"
            case .list, .last, .next:
                return "Results"
            case .count:
                return "Count"
            case .group, .compare, .share, .forecast, .whatIf:
                break
            }
        case .amount,
             .plannedAmount,
             .actualAmount,
             .effectiveAmount,
             .color,
             .name,
             nil:
            break
        }

        switch plan.operation {
        case .count:
            return "Count"
        case .average:
            return "Average"
        case .list, .last, .next:
            return "Results"
        case .group:
            return "Grouped Results"
        case .sum:
            return "Total"
        case .compare, .share, .forecast, .whatIf:
            return "Results"
        }
    }

    private func subtitle(for context: MarinaUniversalPresentationContext) -> String? {
        if let label = dateLabel(for: context, capitalization: .title) {
            return label
        }
        guard let dateRange = context.dateRange else {
            return nil
        }
        return "\(shortDate(dateRange.startDate)) - \(shortDate(dateRange.endDate))"
    }

    private func listSubtitle(
        for page: MarinaUniversalRowsPage,
        plan: MarinaUniversalQueryPlan,
        context: MarinaUniversalPresentationContext
    ) -> String? {
        guard page.totalRowCount > page.rows.count else {
            return subtitle(for: context)
        }

        let noun = expenseNoun(for: context)
        let date = dateLabel(for: context, capitalization: .sentence).map { " from \($0)" } ?? ""
        return "Showing \(page.rows.count) of \(page.totalRowCount) \(noun)\(date)."
    }

    private func emptyTitle(
        for plan: MarinaUniversalQueryPlan,
        context: MarinaUniversalPresentationContext
    ) -> String {
        guard isExpenseList(plan),
              let target = displayTarget(in: context) else {
            return "No results found."
        }

        let date = emptyDatePhrase(for: context).map { " \($0)" } ?? ""
        return "I didn't find any \(target) expenses\(date)."
    }

    private func genericEmptySubtitle(
        for plan: MarinaUniversalQueryPlan,
        context: MarinaUniversalPresentationContext
    ) -> String? {
        guard isExpenseList(plan),
              displayTarget(in: context) != nil else {
            return subtitle(for: context)
        }
        return nil
    }

    private func isExpenseList(_ plan: MarinaUniversalQueryPlan) -> Bool {
        guard plan.operation == .list else { return false }
        switch plan.surface {
        case .unifiedExpenses,
             .semantic(.variableExpense),
             .semantic(.plannedExpense):
            return true
        case .semantic,
             .savingsLedgerEntries,
             .reconciliationLedgerEntries:
            return false
        }
    }

    private func displayTarget(in context: MarinaUniversalPresentationContext) -> String? {
        trimmed(context.semanticRequest?.targetDisplayName)
            ?? trimmed(context.semanticRequest?.targetName)
            ?? trimmed(context.semanticRequest?.textQuery)
    }

    private func expenseNoun(for context: MarinaUniversalPresentationContext) -> String {
        guard let target = displayTarget(in: context) else {
            return "expenses"
        }
        return "\(target) expenses"
    }

    private enum DateLabelCapitalization {
        case title
        case sentence
    }

    private func dateLabel(
        for context: MarinaUniversalPresentationContext,
        capitalization: DateLabelCapitalization
    ) -> String? {
        guard let token = context.semanticRequest?.dateRangeToken else {
            return nil
        }

        let label: String?
        switch token {
        case .currentPeriod:
            label = "this budgeting period"
        case .previousMonth:
            label = "last month"
        case .currentMonth:
            label = "this month"
        case .previousPeriod:
            label = "last budgeting period"
        case .nextSevenDays:
            label = "the next seven days"
        case .allTime:
            label = "all time"
        }

        guard let label else { return nil }
        switch capitalization {
        case .title:
            return label.prefix(1).uppercased() + String(label.dropFirst())
        case .sentence:
            return label
        }
    }

    private func emptyDatePhrase(for context: MarinaUniversalPresentationContext) -> String? {
        guard let token = context.semanticRequest?.dateRangeToken else {
            return nil
        }

        switch token {
        case .currentPeriod:
            return "in this budgeting period"
        case .previousPeriod:
            return "in last budgeting period"
        case .currentMonth:
            return "this month"
        case .previousMonth:
            return "last month"
        case .nextSevenDays:
            return "in the next seven days"
        case .allTime:
            return "all time"
        }
    }

    private func trimmed(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false else {
            return nil
        }
        return trimmed
    }

    private func preferredDisplayValue(
        for row: MarinaQueryableRow,
        plan: MarinaUniversalQueryPlan
    ) -> MarinaValue {
        let fields = preferredFields(for: row.entity, measure: plan.measure)
        for field in fields {
            if let value = row.fields[field] {
                return value
            }
        }
        return .text(row.displayName)
    }

    private func preferredFields(
        for entity: MarinaSemanticEntity,
        measure: MarinaSemanticMeasure?
    ) -> [MarinaFieldKey] {
        var fields: [MarinaFieldKey] = []
        if let measureField = field(for: measure) {
            fields.append(measureField)
        }

        switch entity {
        case .variableExpense, .plannedExpense:
            fields.append(contentsOf: [.budgetImpact, .amount, .effectiveAmount, .plannedAmount, .actualAmount])
        case .income:
            fields.append(contentsOf: [.incomeAmount, .amount, .date, .source])
        case .workspace, .budget, .card, .reconciliationAccount, .savingsAccount, .category:
            fields.append(contentsOf: [.name, .title, .color, .date, .startDate])
        case .preset:
            fields.append(contentsOf: [.title, .name, .plannedAmount, .date])
        }

        return fields.uniqued()
    }

    private func field(for measure: MarinaSemanticMeasure?) -> MarinaFieldKey? {
        switch measure {
        case .amount:
            return .amount
        case .plannedAmount:
            return .plannedAmount
        case .actualAmount:
            return .actualAmount
        case .effectiveAmount:
            return .effectiveAmount
        case .budgetImpact:
            return .budgetImpact
        case .incomeAmount:
            return .incomeAmount
        case .name:
            return .name
        case .color:
            return .color
        case .savingsTotal,
             .reconciliationBalance,
             .categoryAvailability,
             .remainingRoom,
             .burnRate,
             .projectedSpend,
             .safeDailySpend,
             .paceDifference,
             .coverageRatio,
             .recurringBurden,
             .concentration,
             nil:
            return nil
        }
    }

    private func amount(
        for row: MarinaQueryableRow,
        plan: MarinaUniversalQueryPlan
    ) -> Double? {
        for field in preferredFields(for: row.entity, measure: plan.measure) {
            if let value = numericValue(row.fields[field]),
               amountFields.contains(field) {
                return value
            }
        }
        return nil
    }

    private var amountFields: Set<MarinaFieldKey> {
        [.amount, .plannedAmount, .actualAmount, .effectiveAmount, .budgetImpact, .incomeAmount]
    }

    private func date(for row: MarinaQueryableRow) -> Date? {
        for field in [MarinaFieldKey.date, .transactionDate, .expenseDate, .createdAt, .startDate] {
            if case let .date(date)? = row.fields[field] {
                return date
            }
        }
        return nil
    }

    private func objectType(for entity: MarinaSemanticEntity) -> MarinaLookupObjectType {
        switch entity {
        case .workspace:
            return .workspace
        case .budget:
            return .budget
        case .card:
            return .card
        case .plannedExpense:
            return .plannedExpense
        case .variableExpense:
            return .variableExpense
        case .reconciliationAccount:
            return .reconciliationAccount
        case .savingsAccount:
            return .savingsAccount
        case .income:
            return .income
        case .category:
            return .category
        case .preset:
            return .preset
        }
    }

    private func formattedValue(_ value: MarinaValue) -> String {
        switch value {
        case let .text(value):
            return value
        case let .money(value):
            return CurrencyFormatter.string(from: value)
        case let .number(value):
            return decimal(value)
        case let .integer(value):
            return "\(value)"
        case let .date(value):
            return shortDate(value)
        case let .boolean(value):
            return value ? "Yes" : "No"
        case let .colorHex(value):
            return value
        case .empty:
            return "No value"
        }
    }

    private func formattedMetricValue(
        _ value: MarinaValue,
        measure: MarinaSemanticMeasure?,
        details: [MarinaFormulaMetricDetail] = []
    ) -> String {
        switch measure {
        case .coverageRatio:
            return formattedValue(value, style: .percent)
        case .categoryAvailability:
            guard let overCount = integerDetail(.overCount, in: details),
                  let nearCount = integerDetail(.nearCount, in: details) else {
                return formattedValue(value)
            }
            return "\(AppNumberFormat.integer(overCount)) over, \(AppNumberFormat.integer(nearCount)) near"
        case .paceDifference:
            return formattedValue(value, style: .deltaMoney)
        case .concentration:
            return formattedValue(value, style: .percent)
        case .recurringBurden:
            return formattedValue(value, style: .percent)
        case .amount,
             .plannedAmount,
             .actualAmount,
             .effectiveAmount,
             .budgetImpact,
             .savingsTotal,
             .incomeAmount,
             .reconciliationBalance,
             .remainingRoom,
             .burnRate,
             .projectedSpend,
             .safeDailySpend,
             .color,
             .name,
             nil:
            return formattedValue(value)
        }
    }

    private func formattedDetailValue(_ detail: MarinaFormulaMetricDetail) -> String {
        formattedValue(detail.value, style: detail.style)
    }

    private func formattedPresentationRowValue(_ row: MarinaFormulaPresentationRow) -> String {
        let primary = formattedValue(row.primaryValue, style: row.primaryStyle)
        guard let secondaryValue = row.secondaryValue else {
            return primary
        }
        return "\(primary) - \(formattedValue(secondaryValue, style: row.secondaryStyle))"
    }

    private func formattedValue(_ value: MarinaValue, style: MarinaFormulaValueStyle) -> String {
        switch style {
        case .automatic:
            return formattedValue(value)
        case .money:
            return CurrencyFormatter.string(from: numericValue(value) ?? 0)
        case .integer:
            if case let .integer(value) = value {
                return "\(value)"
            }
            return (numericValue(value) ?? 0).formatted(.number.precision(.fractionLength(0)))
        case .percent:
            return (numericValue(value) ?? 0).formatted(.percent.precision(.fractionLength(1)))
        case .deltaMoney:
            return deltaSummary(numericValue(value) ?? 0)
        }
    }

    private func kind(for plan: MarinaUniversalQueryPlan) -> HomeAnswerKind {
        switch plan.measure {
        case .paceDifference:
            return .comparison
        case .amount,
             .plannedAmount,
             .actualAmount,
             .effectiveAmount,
             .budgetImpact,
             .savingsTotal,
             .incomeAmount,
             .reconciliationBalance,
             .categoryAvailability,
             .remainingRoom,
             .burnRate,
             .projectedSpend,
             .safeDailySpend,
             .coverageRatio,
             .recurringBurden,
             .concentration,
             .color,
             .name,
             nil:
            return .metric
        }
    }

    private func title(for component: MarinaFormulaMetricComponent) -> String {
        switch component {
        case .spentSoFar:
            return "Spent so far"
        case .elapsedDays:
            return "Elapsed days"
        case .averagePerDay:
            return "Average per day"
        case .projectedTotal:
            return "Projected total"
        case .expectedByNow:
            return "Expected by now"
        case .paceDifference:
            return "Pace difference"
        case .income:
            return "Income"
        case .plannedExpenses:
            return "Planned expenses"
        case .coveragePercent:
            return "Coverage percent"
        case .difference:
            return "Difference"
        case .activeBudget:
            return "Budget"
        case .overCount:
            return "Over"
        case .nearCount:
            return "Near"
        case .categoryCount:
            return "Categories"
        case .category:
            return "Category"
        case .categorySpend:
            return "Category spend"
        case .totalSpend:
            return "Total spend"
        case .concentration:
            return "Concentration"
        case .recurringTotal:
            return "Recurring total"
        case .recurringBurden:
            return "Recurring burden"
        case .projectedSavings:
            return "Projected savings"
        case .actualSavings:
            return "Actual savings"
        case .gapToProjected:
            return "Gap to projected"
        case .forecastStatus:
            return "Status"
        }
    }

    private func integerDetail(
        _ component: MarinaFormulaMetricComponent,
        in details: [MarinaFormulaMetricDetail]
    ) -> Int? {
        guard let value = details.first(where: { $0.component == component })?.value else {
            return nil
        }

        switch value {
        case let .integer(value):
            return value
        case let .number(value):
            return Int(value)
        case let .money(value):
            return Int(value)
        case .text, .date, .boolean, .colorHex, .empty:
            return nil
        }
    }

    private func deltaSummary(_ delta: Double) -> String {
        if delta > 0 {
            return "Up \(CurrencyFormatter.string(from: delta))"
        }

        if delta < 0 {
            return "Down \(CurrencyFormatter.string(from: abs(delta)))"
        }

        return "No change"
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

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
