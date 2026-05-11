import Foundation

enum MarinaComposableWorkspaceQueryExecutionResult: Equatable {
    case handled(MarinaWorkspaceAggregationCard)
    case unsupported
}

struct MarinaComposableWorkspaceQuery: Codable, Equatable, Sendable {
    enum Dataset: String, Codable, Equatable, Sendable {
        case spending
        case allocations
        case simulation
    }

    enum Sort: String, Codable, Equatable, Sendable {
        case newest
        case largest
        case deltaDescending
        case groupedTotalDescending
    }

    let dataset: Dataset
    let measure: MarinaCandidateMeasure
    let includeFilters: [Filter]
    let excludeFilters: [Filter]
    let grouping: MarinaGroupingDimensionCandidate?
    let sort: Sort
    let dateRange: HomeQueryDateRange?
    let comparisonDateRange: HomeQueryDateRange?
    let limit: Int

    struct Filter: Codable, Equatable, Sendable {
        let entityType: MarinaCandidateEntityTypeHint
        let displayName: String
        let sourceID: UUID?
    }
}

@MainActor
struct MarinaComposableWorkspaceQueryExecutor {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func execute(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date = Date()
    ) -> MarinaComposableWorkspaceQueryExecutionResult {
        if plan.operation == .simulate {
            return simulate(candidate: candidate, resolved: resolved, plan: plan, provider: provider, now: now)
        }

        if hasAllocationAccountTarget(plan) {
            return allocatedSpend(resolved: resolved, plan: plan, provider: provider, now: now)
        }

        switch (plan.operation, plan.measure, plan.grouping?.dimension) {
        case (.rank, .spend, .card):
            return .handled(cardBudgetImpactRanking(plan: plan, provider: provider, now: now))
        case (.sum, .spend, _):
            guard hasExclusionCue(candidate.rawPrompt) else { return .unsupported }
            return .handled(filteredSpend(candidate: candidate, resolved: resolved, plan: plan, provider: provider, now: now))
        case (.rank, .transactionAmount, .transaction), (.listRows, .transactionAmount, .transaction):
            guard plan.operation == .listRows || plan.ranking?.direction == .newest else { return .unsupported }
            return .handled(recentFilteredTransactions(resolved: resolved, plan: plan, provider: provider, now: now))
        case (.average, .spend, .week), (.average, .spend, .month):
            return .handled(targetedPeriodicAverage(resolved: resolved, plan: plan, provider: provider, now: now))
        case (.compare, .spend, .category), (.compare, .spend, .transaction):
            guard plan.ranking != nil else { return .unsupported }
            return .handled(categoryDeltaDrivers(plan: plan, provider: provider, now: now))
        default:
            return .unsupported
        }
    }

    // MARK: - Cards

    private func cardBudgetImpactRanking(
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date
    ) -> MarinaWorkspaceAggregationCard {
        let range = plan.dateRange ?? monthRange(containing: now)
        var totals: [String: (amount: Double, id: UUID?)] = [:]

        for expense in provider.fetchAllVariableExpenses() where contains(expense.transactionDate, in: range) {
            let name = expense.card?.name ?? "No Card"
            let id = expense.card?.id
            totals[name, default: (0, id)].amount += SavingsMathService.variableBudgetImpactAmount(for: expense)
            totals[name]?.id = id
        }

        for expense in provider.fetchAllPlannedExpenses() where contains(expense.expenseDate, in: range) {
            let name = expense.card?.name ?? "No Card"
            let id = expense.card?.id
            totals[name, default: (0, id)].amount += SavingsMathService.plannedBudgetImpactAmount(for: expense)
            totals[name]?.id = id
        }

        let rows = totals
            .map { (name: $0.key, amount: $0.value.amount, id: $0.value.id) }
            .filter { $0.amount != 0 }
            .sorted { $0.amount > $1.amount }
            .prefix(limit(for: plan))
            .map {
                MarinaWorkspaceAggregationCard.Row(
                    label: $0.name,
                    value: currency($0.amount),
                    amount: $0.amount,
                    objectType: .card,
                    sourceID: $0.id,
                    sortValue: $0.amount
                )
            }

        return MarinaWorkspaceAggregationCard(
            title: "Cards by Budget Impact",
            subtitle: rangeLabel(range),
            primaryValue: rows.first?.value,
            rows: Array(rows),
            traceSummary: "composableWorkspace=cardBudgetImpactRanking,resultCount=\(rows.count)"
        )
    }

    // MARK: - Filters and Lists

    private func filteredSpend(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date
    ) -> MarinaWorkspaceAggregationCard {
        let range = plan.dateRange ?? monthRange(containing: now)
        let excludedNames = exclusionNames(from: candidate.rawPrompt)
        let explicitExcludeFilters = resolved.resolvedTargets.filter { $0.role == .excludeFilter }
        let includeFilters = resolved.resolvedTargets.filter {
            $0.role != .excludeFilter && excludedNames.contains(normalized($0.displayName)) == false
        }
        let excludeFilters = explicitExcludeFilters.isEmpty
            ? resolved.resolvedTargets.filter { excludedNames.contains(normalized($0.displayName)) }
            : explicitExcludeFilters
        let rows = spendingRows(provider: provider, range: range)
            .filter { row in includeFilters.allSatisfy { matches(row: row, target: $0) } }
            .filter { row in excludeFilters.contains(where: { matches(row: row, target: $0) }) == false }
        let total = rows.reduce(0.0) { $0 + $1.amount }

        return MarinaWorkspaceAggregationCard(
            title: "Filtered Spending",
            subtitle: filterSummary(include: includeFilters, exclude: excludeFilters, range: range),
            primaryValue: currency(total),
            rows: Array(rows.sorted { $0.date > $1.date }.prefix(limit(for: plan))).map(displayRow),
            traceSummary: "composableWorkspace=filteredSpend,resultCount=\(rows.count),total=\(total)"
        )
    }

    private func recentFilteredTransactions(
        resolved: MarinaResolvedQueryCandidate,
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date
    ) -> MarinaWorkspaceAggregationCard {
        let range = plan.dateRange ?? lookbackRange(from: now, months: 12)
        let filters = resolved.resolvedTargets.filter { $0.role != .excludeFilter }
        let rows = spendingRows(provider: provider, range: range)
            .filter { row in filters.isEmpty || filters.allSatisfy { matches(row: row, target: $0) } }
            .sorted { $0.date > $1.date }
        let shown = Array(rows.prefix(limit(for: plan)))
        let total = shown.reduce(0.0) { $0 + $1.amount }

        return MarinaWorkspaceAggregationCard(
            title: "Recent Purchases",
            subtitle: filterSummary(include: filters, exclude: [], range: range),
            primaryValue: currency(total),
            rows: shown.map(displayRow),
            traceSummary: "composableWorkspace=recentFilteredTransactions,resultCount=\(shown.count),total=\(total)"
        )
    }

    private func targetedPeriodicAverage(
        resolved: MarinaResolvedQueryCandidate,
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date
    ) -> MarinaWorkspaceAggregationCard {
        let range = plan.dateRange ?? lookbackRange(from: now, months: 3)
        let filters = resolved.resolvedTargets
        let rows = spendingRows(provider: provider, range: range)
            .filter { row in filters.isEmpty || filters.allSatisfy { matches(row: row, target: $0) } }
        let buckets = bucketRanges(in: range, dimension: plan.grouping?.dimension ?? .week)
        let totals = buckets.map { bucket in
            rows.filter { contains($0.date, in: bucket.range) }.reduce(0.0) { $0 + $1.amount }
        }
        let average = totals.isEmpty ? 0 : totals.reduce(0, +) / Double(totals.count)
        let cardRows = zip(buckets, totals).map { bucket, total in
            MarinaWorkspaceAggregationCard.Row(
                label: bucket.label,
                value: currency(total),
                amount: total,
                date: bucket.range.startDate,
                sortValue: total
            )
        }

        return MarinaWorkspaceAggregationCard(
            title: "Average \(periodLabel(plan.grouping?.dimension ?? .week)) Spending",
            subtitle: filterSummary(include: filters, exclude: [], range: range),
            primaryValue: currency(average),
            rows: cardRows,
            traceSummary: "composableWorkspace=targetedPeriodicAverage,buckets=\(buckets.count),average=\(average)"
        )
    }

    // MARK: - Deltas

    private func categoryDeltaDrivers(
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date
    ) -> MarinaWorkspaceAggregationCard {
        let ranges = comparisonRanges(for: plan, now: now)
        let currentRows = spendingRows(provider: provider, range: ranges.current)
        let previousRows = spendingRows(provider: provider, range: ranges.previous)
        let currentTotals = groupedTotals(currentRows, by: \.categoryName)
        let previousTotals = groupedTotals(previousRows, by: \.categoryName)
        let labels = Set(currentTotals.keys).union(previousTotals.keys)

        let rows = labels
            .map { label in
                (label: label, current: currentTotals[label, default: 0], previous: previousTotals[label, default: 0])
            }
            .map { item in
                (label: item.label, delta: item.current - item.previous, current: item.current, previous: item.previous)
            }
            .filter { $0.delta > 0 }
            .sorted { $0.delta > $1.delta }
            .prefix(limit(for: plan))
            .map { item in
                let renderedDelta = delta(item.delta)
                let renderedCurrent = currency(item.current)
                return MarinaWorkspaceAggregationCard.Row(
                    label: item.label,
                    value: "\(renderedDelta) • now \(renderedCurrent)",
                    amount: item.delta,
                    sortValue: item.delta
                )
            }

        return MarinaWorkspaceAggregationCard(
            title: "Spending Increase Drivers",
            subtitle: "\(rangeLabel(ranges.current)) vs \(rangeLabel(ranges.previous))",
            primaryValue: rows.first?.value,
            rows: Array(rows),
            traceSummary: "composableWorkspace=categoryDeltaDrivers,resultCount=\(rows.count)"
        )
    }

    // MARK: - Reconciliation

    private func allocatedSpend(
        resolved: MarinaResolvedQueryCandidate,
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date
    ) -> MarinaComposableWorkspaceQueryExecutionResult {
        let range = plan.dateRange ?? monthRange(containing: now)
        guard let account = resolved.resolvedTargets.first(where: { $0.entityType == .allocationAccount }) else {
            return .unsupported
        }
        let otherFilters = resolved.resolvedTargets.filter { $0.entityType != .allocationAccount }
        let allocations = provider.fetchAllExpenseAllocations().filter { allocation in
            allocation.account?.id == account.sourceID
        }
        let matched = allocations.compactMap { allocation -> SpendingRow? in
            if let expense = allocation.expense, contains(expense.transactionDate, in: range) {
                return row(for: expense, amount: max(0, allocation.allocatedAmount))
            }
            if let expense = allocation.plannedExpense, contains(expense.expenseDate, in: range) {
                return row(for: expense, amount: max(0, allocation.allocatedAmount))
            }
            return nil
        }
        .filter { row in otherFilters.isEmpty || otherFilters.allSatisfy { matches(row: row, target: $0) } }
        let total = matched.reduce(0.0) { $0 + $1.amount }

        return .handled(
            MarinaWorkspaceAggregationCard(
                title: "\(account.displayName) Allocated Spend",
                subtitle: filterSummary(include: otherFilters, exclude: [], range: range),
                primaryValue: currency(total),
                rows: Array(matched.sorted { $0.date > $1.date }.prefix(limit(for: plan))).map(displayRow),
                traceSummary: "composableWorkspace=allocatedSpend,resultCount=\(matched.count),total=\(total)"
            )
        )
    }

    // MARK: - Simulation

    private func simulate(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date
    ) -> MarinaComposableWorkspaceQueryExecutionResult {
        guard let amount = firstCurrencyAmount(in: candidate.rawPrompt),
              let input = resolved.resolvedTargets.first(where: { $0.role == .simulationInput || $0.entityType == .category }) else {
            return .unsupported
        }

        let range = plan.dateRange ?? monthRange(containing: now)
        let rows = spendingRows(provider: provider, range: range)
        let totalBefore = rows.reduce(0.0) { $0 + $1.amount }
        let categoryBefore = rows.filter { matches(row: $0, target: input) }.reduce(0.0) { $0 + $1.amount }
        let budget = activeBudget(provider: provider, now: now, range: range)
        let plannedIncome = provider.fetchAllIncomes()
            .filter { $0.isPlanned && contains($0.date, in: range) }
            .reduce(0.0) { $0 + $1.amount }
        let budgetLimit = categoryLimit(for: input, budget: budget)
        let categoryAfter = categoryBefore + amount
        let totalAfter = totalBefore + amount

        var answerRows: [MarinaWorkspaceAggregationCard.Row] = [
            .init(label: "Category after", value: currency(categoryAfter), amount: categoryAfter, sortValue: categoryAfter),
            .init(label: "Workspace spend after", value: currency(totalAfter), amount: totalAfter, sortValue: totalAfter)
        ]
        if plannedIncome > 0 {
            answerRows.append(.init(label: "Remaining vs planned income", value: currency(plannedIncome - totalAfter), amount: plannedIncome - totalAfter, sortValue: plannedIncome - totalAfter))
        }
        if let budgetLimit, let maxAmount = budgetLimit.maxAmount {
            answerRows.append(.init(label: "Category limit", value: "\(currency(maxAmount)) (\(categoryAfter > maxAmount ? "over" : "under"))", amount: maxAmount, sortValue: maxAmount))
        }

        return .handled(
            MarinaWorkspaceAggregationCard(
                title: "What-If Budget Impact",
                subtitle: "Add \(currency(amount)) to \(input.displayName)",
                primaryValue: currency(totalAfter - totalBefore),
                rows: answerRows,
                traceSummary: "composableWorkspace=simulation,amount=\(amount),target=\(input.displayName)"
            )
        )
    }

    // MARK: - Rows

    private struct SpendingRow {
        let title: String
        let amount: Double
        let date: Date
        let cardID: UUID?
        let cardName: String?
        let categoryID: UUID?
        let categoryName: String
        let objectType: MarinaLookupObjectType
        let sourceID: UUID
    }

    private func spendingRows(provider: MarinaDataProvider, range: HomeQueryDateRange) -> [SpendingRow] {
        let variable = provider.fetchAllVariableExpenses()
            .filter { contains($0.transactionDate, in: range) }
            .map { row(for: $0, amount: SavingsMathService.variableBudgetImpactAmount(for: $0)) }
        let planned = provider.fetchAllPlannedExpenses()
            .filter { contains($0.expenseDate, in: range) }
            .map { row(for: $0, amount: SavingsMathService.plannedBudgetImpactAmount(for: $0)) }
        return variable + planned
    }

    private func row(for expense: VariableExpense, amount: Double) -> SpendingRow {
        SpendingRow(
            title: expense.descriptionText,
            amount: amount,
            date: expense.transactionDate,
            cardID: expense.card?.id,
            cardName: expense.card?.name,
            categoryID: expense.category?.id,
            categoryName: expense.category?.name ?? "Uncategorized",
            objectType: .variableExpense,
            sourceID: expense.id
        )
    }

    private func row(for expense: PlannedExpense, amount: Double) -> SpendingRow {
        SpendingRow(
            title: expense.title,
            amount: amount,
            date: expense.expenseDate,
            cardID: expense.card?.id,
            cardName: expense.card?.name,
            categoryID: expense.category?.id,
            categoryName: expense.category?.name ?? "Uncategorized",
            objectType: .plannedExpense,
            sourceID: expense.id
        )
    }

    private func displayRow(_ row: SpendingRow) -> MarinaWorkspaceAggregationCard.Row {
        MarinaWorkspaceAggregationCard.Row(
            label: row.title,
            value: [currency(row.amount), shortDate(row.date), row.cardName, row.categoryName]
                .compactMap { $0 }
                .joined(separator: " • "),
            amount: row.amount,
            date: row.date,
            objectType: row.objectType,
            sourceID: row.sourceID,
            sortValue: row.amount
        )
    }

    private func matches(row: SpendingRow, target: MarinaResolvedEntityMention) -> Bool {
        switch target.entityType {
        case .card:
            return row.cardID == target.sourceID || normalized(row.cardName ?? "") == normalized(target.displayName)
        case .category:
            return row.categoryID == target.sourceID || normalized(row.categoryName) == normalized(target.displayName)
        case .merchant, .expense, .transaction:
            return normalized(row.title).contains(normalized(target.displayName))
        case .allocationAccount, .budget, .preset, .incomeSource, .savingsAccount, .workspace:
            return false
        }
    }

    // MARK: - Helpers

    private func hasAllocationAccountTarget(_ plan: MarinaAggregationPlan) -> Bool {
        plan.targets.contains { $0.entityType == .allocationAccount }
    }

    private func hasExclusionCue(_ prompt: String) -> Bool {
        normalized(prompt).contains(" outside of ")
    }

    private func exclusionNames(from prompt: String) -> Set<String> {
        let text = normalized(prompt)
        guard let range = text.range(of: " outside of ") else { return [] }
        return [String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    private func filterSummary(
        include: [MarinaResolvedEntityMention],
        exclude: [MarinaResolvedEntityMention],
        range: HomeQueryDateRange
    ) -> String {
        var parts: [String] = [rangeLabel(range)]
        if include.isEmpty == false {
            parts.append("Including \(include.map(\.displayName).joined(separator: ", "))")
        }
        if exclude.isEmpty == false {
            parts.append("Excluding \(exclude.map(\.displayName).joined(separator: ", "))")
        }
        return parts.joined(separator: " • ")
    }

    private func groupedTotals(_ rows: [SpendingRow], by keyPath: KeyPath<SpendingRow, String>) -> [String: Double] {
        var totals: [String: Double] = [:]
        for row in rows {
            totals[row[keyPath: keyPath], default: 0] += row.amount
        }
        return totals
    }

    private func bucketRanges(
        in range: HomeQueryDateRange,
        dimension: MarinaGroupingDimensionCandidate
    ) -> [(label: String, range: HomeQueryDateRange)] {
        let component: Calendar.Component = dimension == .month ? .month : .weekOfYear
        var buckets: [(String, HomeQueryDateRange)] = []
        var cursor = calendar.startOfDay(for: range.startDate)
        while cursor <= range.endDate {
            let interval = calendar.dateInterval(of: component, for: cursor)
            let start = max(interval?.start ?? cursor, range.startDate)
            let rawEnd = interval?.end.addingTimeInterval(-1) ?? cursor
            let end = min(rawEnd, range.endDate)
            buckets.append((shortDate(start), HomeQueryDateRange(startDate: start, endDate: end)))
            cursor = calendar.date(byAdding: component, value: 1, to: cursor) ?? range.endDate.addingTimeInterval(1)
        }
        return buckets
    }

    private func comparisonRanges(
        for plan: MarinaAggregationPlan,
        now: Date
    ) -> (current: HomeQueryDateRange, previous: HomeQueryDateRange) {
        if let current = plan.dateRange, let previous = plan.comparisonDateRange {
            return (current, previous)
        }
        let current = plan.dateRange ?? monthRange(containing: now)
        let previousStart = calendar.date(byAdding: .month, value: -1, to: current.startDate) ?? current.startDate
        let previousEnd = calendar.date(byAdding: .day, value: -1, to: current.startDate) ?? previousStart
        return (current, HomeQueryDateRange(startDate: previousStart, endDate: previousEnd))
    }

    private func monthRange(containing date: Date) -> HomeQueryDateRange {
        let interval = calendar.dateInterval(of: .month, for: date)
        let start = interval?.start ?? date
        let end = (interval?.end ?? date).addingTimeInterval(-1)
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func lookbackRange(from date: Date, months: Int) -> HomeQueryDateRange {
        let end = date
        let start = calendar.date(byAdding: .month, value: -months, to: date) ?? date
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func activeBudget(provider: MarinaDataProvider, now: Date, range: HomeQueryDateRange) -> Budget? {
        provider.fetchAllBudgets().first { $0.startDate <= now && $0.endDate >= now }
            ?? provider.fetchAllBudgets().first { $0.startDate <= range.endDate && $0.endDate >= range.startDate }
    }

    private func categoryLimit(for target: MarinaResolvedEntityMention, budget: Budget?) -> BudgetCategoryLimit? {
        budget?.categoryLimits?.first { limit in
            limit.category?.id == target.sourceID || normalized(limit.category?.name ?? "") == normalized(target.displayName)
        }
    }

    private func firstCurrencyAmount(in prompt: String) -> Double? {
        let pattern = #"(?i)(?:\$|usd\s*)?([0-9]+(?:\.[0-9]{1,2})?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: prompt, range: NSRange(prompt.startIndex..., in: prompt)),
              let range = Range(match.range(at: 1), in: prompt) else {
            return nil
        }
        return Double(prompt[range])
    }

    private func contains(_ date: Date, in range: HomeQueryDateRange) -> Bool {
        date >= range.startDate && date <= range.endDate
    }

    private func currency(_ amount: Double) -> String {
        CurrencyFormatter.string(from: amount)
    }

    private func delta(_ amount: Double) -> String {
        let label = amount >= 0 ? "Up" : "Down"
        return "\(label) \(currency(abs(amount)))"
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func rangeLabel(_ range: HomeQueryDateRange) -> String {
        "\(shortDate(range.startDate))-\(shortDate(range.endDate))"
    }

    private func periodLabel(_ dimension: MarinaGroupingDimensionCandidate) -> String {
        dimension == .month ? "Monthly" : "Weekly"
    }

    private func limit(for plan: MarinaAggregationPlan) -> Int {
        min(max(plan.limit ?? plan.ranking?.limit ?? 5, 1), 10)
    }

    private func normalized(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s&]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
