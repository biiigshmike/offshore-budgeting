import Foundation

@MainActor
struct MarinaWorkspaceAggregationExecutor {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func execute(
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date = Date()
    ) -> MarinaWorkspaceAggregationExecutionResult {
        switch (plan.operation, plan.measure, plan.grouping?.dimension) {
        case (.sum, .income, .incomeSource):
            return .handled(incomeBySource(plan: plan, provider: provider, now: now))
        case (.sum, .income, nil):
            return .handled(incomeSummary(plan: plan, provider: provider, now: now))
        case (.listRows, .income, nil), (.listRows, .income, .incomeSource):
            return .handled(incomeRows(plan: plan, provider: provider, now: now))
        case (.rank, .income, .incomeSource):
            return .handled(topIncomeSources(plan: plan, provider: provider, now: now))
        case (.compare, .income, nil), (.compare, .income, .incomeSource):
            return .handled(incomeComparison(plan: plan, provider: provider, now: now))
        case (.rank, .presetAmount, .transaction), (.listRows, .presetAmount, .transaction):
            return .handled(upcomingPlannedExpenses(plan: plan, provider: provider, now: now))
        case (.rank, .presetAmount, .preset):
            return .handled(highestCostPresets(plan: plan, provider: provider))
        case (.sum, .presetAmount, .category), (.rank, .presetAmount, .category):
            return .handled(plannedExpensesByCategory(plan: plan, provider: provider, now: now))
        case (.sum, .presetAmount, .card), (.rank, .presetAmount, .card):
            return .handled(plannedExpensesByCard(plan: plan, provider: provider, now: now))
        case (.rank, .savingsMovement, .savingsLedgerEntry), (.listRows, .savingsMovement, .savingsLedgerEntry):
            return .handled(largestSavingsMovements(plan: plan, provider: provider, now: now))
        case (.lookupDetails, .reconciliationBalance, nil),
             (.lookupDetails, .reconciliationBalance, .allocationAccount):
            return .handled(sharedBalances(plan: plan, provider: provider))
        case (.rank, .reconciliationBalance, .allocationAccount),
             (.sum, .reconciliationBalance, .allocationAccount),
             (.listRows, .reconciliationBalance, .allocationAccount):
            return .handled(sharedBalances(plan: plan, provider: provider))
        default:
            return .unsupported
        }
    }

    // MARK: - Income

    private func incomeSummary(
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date
    ) -> MarinaWorkspaceAggregationCard {
        let range = plan.dateRange ?? monthRange(containing: now)
        let incomes = sourceScopedIncomes(plan: plan, provider: provider, range: range)
        let actual = incomes.filter { $0.isPlanned == false }.reduce(0.0) { $0 + $1.amount }
        let planned = incomes.filter(\.isPlanned).reduce(0.0) { $0 + $1.amount }
        let topSource = totalsByIncomeSource(incomes.filter { $0.isPlanned == false }).first
        let primaryValue: String
        switch plan.incomeStatusScope {
        case .planned:
            primaryValue = currency(planned)
        case .actual, .all, nil:
            primaryValue = currency(actual)
        }

        return MarinaWorkspaceAggregationCard(
            title: incomeSummaryTitle(for: plan),
            subtitle: rangeLabel(range),
            primaryValue: primaryValue,
            rows: compactRows([
                .init(label: "Actual income", value: currency(actual), amount: actual, sortValue: actual),
                .init(label: "Planned income", value: currency(planned), amount: planned, sortValue: planned),
                .init(label: "Gap vs planned", value: delta(actual - planned), amount: actual - planned, sortValue: actual - planned),
                topSource.map { .init(label: "Top source", value: "\($0.source) (\(currency($0.total)))", amount: $0.total, sortValue: $0.total) }
            ]),
            traceSummary: "workspaceAggregation=incomeSummary,resultCount=\(incomes.count),incomeStatus=\(plan.incomeStatusScope?.rawValue ?? "all")"
        )
    }

    private func incomeRows(
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date
    ) -> MarinaWorkspaceAggregationCard {
        let range = plan.dateRange ?? monthRange(containing: now)
        let incomes = filteredIncomes(plan: plan, provider: provider, range: range)
            .sorted { lhs, rhs in
                if lhs.date == rhs.date { return lhs.source.localizedCaseInsensitiveCompare(rhs.source) == .orderedAscending }
                return lhs.date > rhs.date
            }
            .prefix(limit(for: plan))
        let total = incomes.reduce(0.0) { $0 + $1.amount }
        return MarinaWorkspaceAggregationCard(
            title: incomeRowsTitle(for: plan.incomeStatusScope),
            subtitle: rangeLabel(range),
            primaryValue: currency(total),
            rows: incomes.map { income in
                MarinaWorkspaceAggregationCard.Row(
                    label: income.source,
                    value: "\(income.isPlanned ? "Planned income" : "Actual income") • \(shortDate(income.date)) • \(currency(income.amount))",
                    amount: income.amount,
                    date: income.date,
                    objectType: .income,
                    sourceID: income.id,
                    sortValue: income.amount
                )
            },
            traceSummary: "workspaceAggregation=incomeRows,resultCount=\(incomes.count),incomeStatus=\(plan.incomeStatusScope?.rawValue ?? "all")"
        )
    }

    private func topIncomeSources(
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date
    ) -> MarinaWorkspaceAggregationCard {
        let range = plan.dateRange ?? monthRange(containing: now)
        let actual = provider.fetchAllIncomes().filter {
            $0.isPlanned == false && $0.date >= range.startDate && $0.date <= range.endDate
        }
        let sources = Array(totalsByIncomeSource(actual).prefix(limit(for: plan)))
        let total = sources.reduce(0.0) { $0 + $1.total }

        return MarinaWorkspaceAggregationCard(
            title: "Top Income Sources",
            subtitle: rangeLabel(range),
            primaryValue: sources.first.map { currency($0.total) },
            rows: sources.map {
                .init(label: $0.source, value: currency($0.total), amount: $0.total, sortValue: $0.total)
            },
            traceSummary: "workspaceAggregation=topIncomeSources,resultCount=\(sources.count),total=\(total)"
        )
    }

    private func incomeBySource(
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date
    ) -> MarinaWorkspaceAggregationCard {
        let range = plan.dateRange ?? monthRange(containing: now)
        let actual = provider.fetchAllIncomes().filter {
            $0.isPlanned == false && $0.date >= range.startDate && $0.date <= range.endDate
        }
        let sources = Array(totalsByIncomeSource(actual).prefix(limit(for: plan)))
        let total = sources.reduce(0.0) { $0 + $1.total }

        return MarinaWorkspaceAggregationCard(
            title: "Income by Source",
            subtitle: rangeLabel(range),
            primaryValue: currency(total),
            rows: sources.map {
                .init(label: $0.source, value: currency($0.total), amount: $0.total, sortValue: $0.total)
            },
            traceSummary: "workspaceAggregation=incomeBySource,resultCount=\(sources.count),total=\(total)"
        )
    }

    private func incomeComparison(
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date
    ) -> MarinaWorkspaceAggregationCard {
        let ranges = comparisonRanges(for: plan, now: now)
        let incomes = provider.fetchAllIncomes().filter { $0.isPlanned == false }
        let current = incomeTotal(incomes, in: ranges.current)
        let previous = incomeTotal(incomes, in: ranges.previous)
        let change = current - previous

        return MarinaWorkspaceAggregationCard(
            title: "Income Comparison",
            subtitle: "\(rangeLabel(ranges.current)) vs \(rangeLabel(ranges.previous))",
            primaryValue: currency(current),
            rows: [
                .init(label: "Current period", value: currency(current), amount: current, sortValue: current),
                .init(label: "Previous period", value: currency(previous), amount: previous, sortValue: previous),
                .init(label: "Change", value: delta(change), amount: change, sortValue: change)
            ],
            traceSummary: "workspaceAggregation=incomeComparison,current=\(current),previous=\(previous)"
        )
    }

    // MARK: - Planned Expenses

    private func upcomingPlannedExpenses(
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date
    ) -> MarinaWorkspaceAggregationCard {
        let range = plan.dateRange ?? nextDaysRange(from: now, days: 30)
        let newestFirst = plan.operation == .listRows || plan.ranking?.direction == .newest
        let rows = provider.fetchAllPlannedExpenses()
            .filter { $0.expenseDate >= range.startDate && $0.expenseDate <= range.endDate }
            .sorted { lhs, rhs in
                if newestFirst {
                    if lhs.expenseDate == rhs.expenseDate { return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending }
                    return lhs.expenseDate < rhs.expenseDate
                }
                let lhsAmount = lhs.effectiveAmount()
                let rhsAmount = rhs.effectiveAmount()
                if lhsAmount == rhsAmount { return lhs.expenseDate < rhs.expenseDate }
                return lhsAmount > rhsAmount
            }
            .prefix(limit(for: plan))
            .map { expense in
                MarinaWorkspaceAggregationCard.Row(
                    label: expense.title,
                    value: "\(currency(expense.effectiveAmount())) • \(shortDate(expense.expenseDate))",
                    amount: expense.effectiveAmount(),
                    date: expense.expenseDate,
                    objectType: .plannedExpense,
                    sourceID: expense.id,
                    sortValue: expense.effectiveAmount()
                )
            }

        return MarinaWorkspaceAggregationCard(
            title: newestFirst ? "Planned Expenses Due" : "Upcoming Bills",
            subtitle: rangeLabel(range),
            primaryValue: rows.first?.value,
            rows: Array(rows),
            traceSummary: "workspaceAggregation=upcomingPlannedExpenses,resultCount=\(rows.count)"
        )
    }

    private func plannedExpensesByCategory(
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date
    ) -> MarinaWorkspaceAggregationCard {
        groupedPlannedExpenses(
            title: "Planned Expenses by Category",
            plan: plan,
            provider: provider,
            now: now,
            key: { $0.category?.name ?? "Uncategorized" },
            traceName: "plannedExpensesByCategory"
        )
    }

    private func highestCostPresets(
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider
    ) -> MarinaWorkspaceAggregationCard {
        let rows = provider.fetchAllPresets()
            .filter { $0.isArchived == false && $0.plannedAmount > 0 }
            .sorted { lhs, rhs in
                if lhs.plannedAmount == rhs.plannedAmount {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhs.plannedAmount > rhs.plannedAmount
            }
            .prefix(limit(for: plan))
            .map { preset in
                MarinaWorkspaceAggregationCard.Row(
                    label: preset.title,
                    value: currency(preset.plannedAmount),
                    amount: preset.plannedAmount,
                    objectType: .preset,
                    sourceID: preset.id,
                    sortValue: preset.plannedAmount
                )
            }

        return MarinaWorkspaceAggregationCard(
            title: "Highest Preset Costs",
            subtitle: "Active presets",
            primaryValue: rows.first?.value,
            rows: Array(rows),
            traceSummary: "workspaceAggregation=highestCostPresets,resultCount=\(rows.count)"
        )
    }

    private func plannedExpensesByCard(
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date
    ) -> MarinaWorkspaceAggregationCard {
        groupedPlannedExpenses(
            title: "Planned Expenses by Card",
            plan: plan,
            provider: provider,
            now: now,
            key: { $0.card?.name ?? "No Card" },
            traceName: "plannedExpensesByCard"
        )
    }

    private func groupedPlannedExpenses(
        title: String,
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date,
        key: (PlannedExpense) -> String,
        traceName: String
    ) -> MarinaWorkspaceAggregationCard {
        let range = plan.dateRange ?? monthRange(containing: now)
        var totals: [String: Double] = [:]
        for expense in provider.fetchAllPlannedExpenses() where expense.expenseDate >= range.startDate && expense.expenseDate <= range.endDate {
            totals[key(expense), default: 0] += expense.effectiveAmount()
        }

        let rows = totals
            .map { (label: $0.key, total: $0.value) }
            .sorted { $0.total > $1.total }
            .prefix(limit(for: plan))
            .map { MarinaWorkspaceAggregationCard.Row(label: $0.label, value: currency($0.total), amount: $0.total, sortValue: $0.total) }

        return MarinaWorkspaceAggregationCard(
            title: title,
            subtitle: rangeLabel(range),
            primaryValue: rows.first?.value,
            rows: Array(rows),
            traceSummary: "workspaceAggregation=\(traceName),resultCount=\(rows.count)"
        )
    }

    // MARK: - Savings and Reconciliation

    private func largestSavingsMovements(
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date
    ) -> MarinaWorkspaceAggregationCard {
        let activityList = plan.operation == .listRows || plan.ranking?.direction == .newest
        let range = plan.dateRange
        let rows = provider.fetchAllSavingsLedgerEntries()
            .filter { entry in
                guard let range else { return true }
                return entry.date >= range.startDate && entry.date <= range.endDate
            }
            .sorted { lhs, rhs in
                if activityList {
                    if lhs.date == rhs.date { return lhs.note.localizedCaseInsensitiveCompare(rhs.note) == .orderedAscending }
                    return lhs.date > rhs.date
                }
                return abs(lhs.amount) > abs(rhs.amount)
            }
            .prefix(limit(for: plan))
            .map { entry in
                MarinaWorkspaceAggregationCard.Row(
                    label: entry.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? entry.kindRaw : entry.note,
                    value: "\(currency(entry.amount)) • \(shortDate(entry.date))",
                    amount: entry.amount,
                    date: entry.date,
                    objectType: .savingsLedgerEntry,
                    sourceID: entry.id,
                    sortValue: abs(entry.amount)
                )
            }

        return MarinaWorkspaceAggregationCard(
            title: activityList ? "Savings Activity" : "Largest Savings Movements",
            subtitle: range.map(rangeLabel) ?? "Recent activity",
            primaryValue: rows.first?.value,
            rows: Array(rows),
            traceSummary: "workspaceAggregation=largestSavingsMovements,resultCount=\(rows.count)"
        )
    }

    private func sharedBalances(
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider
    ) -> MarinaWorkspaceAggregationCard {
        let accountTargets = plan.targets.filter { $0.entityType == .allocationAccount }
        let rows = provider.fetchAllAllocationAccounts()
            .filter { $0.isArchived == false }
            .filter { account in
                accountTargets.isEmpty
                    || accountTargets.contains { $0.sourceID == account.id || $0.displayName.localizedCaseInsensitiveCompare(account.name) == .orderedSame }
            }
            .map { account in
                (account: account, balance: AllocationLedgerService.balance(for: account))
            }
            .sorted { $0.balance > $1.balance }
            .prefix(limit(for: plan))
            .map { item in
                MarinaWorkspaceAggregationCard.Row(
                    label: item.account.name,
                    value: currency(item.balance),
                    amount: item.balance,
                    objectType: .reconciliationAccount,
                    sourceID: item.account.id,
                    sortValue: item.balance
                )
            }

        return MarinaWorkspaceAggregationCard(
            title: accountTargets.count == 1 ? "\(accountTargets[0].displayName) Balance" : "Shared Balances",
            subtitle: accountTargets.count == 1 ? "Shared Balances" : "Reconciliation accounts",
            primaryValue: rows.first?.value,
            rows: Array(rows),
            traceSummary: "workspaceAggregation=sharedBalances,resultCount=\(rows.count)"
        )
    }

    // MARK: - Helpers

    private func totalsByIncomeSource(_ incomes: [Income]) -> [(source: String, total: Double)] {
        Dictionary(grouping: incomes, by: \.source)
            .map { (source: $0.key, total: $0.value.reduce(0.0) { $0 + $1.amount }) }
            .sorted { lhs, rhs in
                if lhs.total == rhs.total {
                    return lhs.source.localizedCaseInsensitiveCompare(rhs.source) == .orderedAscending
                }
                return lhs.total > rhs.total
            }
    }

    private func filteredIncomes(
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        range: HomeQueryDateRange
    ) -> [Income] {
        provider.fetchAllIncomes()
            .filter { $0.date >= range.startDate && $0.date <= range.endDate }
            .filter { income in
                matchesIncomeStatus(income, scope: plan.incomeStatusScope)
            }
            .filter { matchesIncomeSource($0, plan: plan) }
    }

    private func sourceScopedIncomes(
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        range: HomeQueryDateRange
    ) -> [Income] {
        provider.fetchAllIncomes()
            .filter { $0.date >= range.startDate && $0.date <= range.endDate }
            .filter { matchesIncomeSource($0, plan: plan) }
    }

    private func matchesIncomeStatus(_ income: Income, scope: MarinaIncomeStatusScope?) -> Bool {
        switch scope {
        case .actual:
            return income.isPlanned == false
        case .planned:
            return income.isPlanned
        case .all, nil:
            return true
        }
    }

    private func matchesIncomeSource(_ income: Income, plan: MarinaAggregationPlan) -> Bool {
        let sourceTargets = plan.targets.filter { $0.entityType == .incomeSource }
        guard sourceTargets.isEmpty == false else { return true }
        return sourceTargets.contains { target in
            income.source.localizedCaseInsensitiveCompare(target.displayName) == .orderedSame
                || income.source.localizedCaseInsensitiveContains(target.displayName)
        }
    }

    private func incomeSummaryTitle(for plan: MarinaAggregationPlan) -> String {
        if plan.routeIntent?.kind == .incomePlannedVsActual || plan.responseShape == .comparison {
            return "Planned vs Actual Income"
        }
        switch plan.incomeStatusScope {
        case .actual:
            return "Actual Income"
        case .planned:
            return "Planned Income"
        case .all, nil:
            return "Income Summary"
        }
    }

    private func incomeRowsTitle(for scope: MarinaIncomeStatusScope?) -> String {
        switch scope {
        case .actual:
            return "Actual Income Entries"
        case .planned:
            return "Planned Income Entries"
        case .all, nil:
            return "Income Entries"
        }
    }

    private func incomeTotal(_ incomes: [Income], in range: HomeQueryDateRange) -> Double {
        incomes
            .filter { $0.date >= range.startDate && $0.date <= range.endDate }
            .reduce(0.0) { $0 + $1.amount }
    }

    private func comparisonRanges(
        for plan: MarinaAggregationPlan,
        now: Date
    ) -> (current: HomeQueryDateRange, previous: HomeQueryDateRange) {
        if let current = plan.dateRange, let previous = plan.comparisonDateRange {
            return (current, previous)
        }
        let current = plan.dateRange ?? monthRange(containing: now)
        return (current, previousMonthRange(before: current.startDate))
    }

    private func compactRows(_ rows: [MarinaWorkspaceAggregationCard.Row?]) -> [MarinaWorkspaceAggregationCard.Row] {
        rows.compactMap { $0 }
    }

    private func limit(for plan: MarinaAggregationPlan) -> Int {
        min(10, max(1, plan.limit ?? plan.ranking?.limit ?? 5))
    }

    private func monthRange(containing date: Date) -> HomeQueryDateRange {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? start
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func previousMonthRange(before date: Date) -> HomeQueryDateRange {
        let current = monthRange(containing: date)
        let previousStart = calendar.date(byAdding: .month, value: -1, to: current.startDate) ?? current.startDate
        let previousEnd = calendar.date(byAdding: DateComponents(second: -1), to: current.startDate) ?? current.startDate
        return HomeQueryDateRange(startDate: previousStart, endDate: previousEnd)
    }

    private func nextDaysRange(from date: Date, days: Int) -> HomeQueryDateRange {
        let start = calendar.startOfDay(for: date)
        let endStart = calendar.date(byAdding: .day, value: days, to: start) ?? start
        let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: endStart) ?? endStart
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func rangeLabel(_ range: HomeQueryDateRange) -> String {
        "\(shortDate(range.startDate)) - \(shortDate(range.endDate))"
    }

    private func shortDate(_ date: Date) -> String {
        AppDateFormat.shortDate(date)
    }

    private func currency(_ value: Double) -> String {
        CurrencyFormatter.string(from: value)
    }

    private func delta(_ value: Double) -> String {
        if value > 0 { return "Up \(currency(value))" }
        if value < 0 { return "Down \(currency(abs(value)))" }
        return "No change"
    }
}
