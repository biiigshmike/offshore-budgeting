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
        case (.rank, .presetAmount, .preset), (.listRows, .presetAmount, .preset):
            return .handled(presetTemplateRows(plan: plan, provider: provider))
        case (.sum, .presetAmount, .preset):
            return .handled(plannedExpensesByPreset(plan: plan, provider: provider, now: now))
        case (.sum, .presetAmount, .category), (.rank, .presetAmount, .category):
            return .handled(plannedExpensesByCategory(plan: plan, provider: provider, now: now))
        case (.sum, .presetAmount, .card), (.rank, .presetAmount, .card):
            return .handled(plannedExpensesByCard(plan: plan, provider: provider, now: now))
        case (.lookupDetails, .spend, nil) where hasCardBalanceTarget(plan):
            return .handled(cardBalance(plan: plan, provider: provider, now: now))
        case (.lookupDetails, .spend, .card) where hasCardBalanceTarget(plan):
            return .handled(cardBalance(plan: plan, provider: provider, now: now))
        case (.lookupDetails, .savings, nil):
            return .handled(savingsBalance(plan: plan, provider: provider))
        case (.rank, .savingsMovement, .savingsLedgerEntry), (.listRows, .savingsMovement, .savingsLedgerEntry):
            return .handled(largestSavingsMovements(plan: plan, provider: provider, now: now))
        case (.lookupDetails, .reconciliationBalance, nil),
             (.lookupDetails, .reconciliationBalance, .allocationAccount):
            return .handled(sharedBalances(plan: plan, provider: provider, now: now))
        case (.rank, .reconciliationBalance, .allocationAccount),
             (.sum, .reconciliationBalance, .allocationAccount),
             (.listRows, .reconciliationBalance, .allocationAccount):
            return .handled(sharedBalances(plan: plan, provider: provider, now: now))
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
        let presetTitlesByID = Dictionary(uniqueKeysWithValues: provider.fetchAllPresets().map { ($0.id, $0.title) })
        let rows = provider.fetchAllPlannedExpenses()
            .filter { $0.expenseDate >= range.startDate && $0.expenseDate <= range.endDate }
            .filter { plannedExpense($0, matches: plan.targets, presetTitlesByID: presetTitlesByID) }
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
                let presetSuffix = expense.sourcePresetID
                    .flatMap { presetTitlesByID[$0] }
                    .flatMap { $0 == expense.title ? nil : " • preset \($0)" } ?? ""
                return MarinaWorkspaceAggregationCard.Row(
                    label: expense.title,
                    value: "\(currency(expense.effectiveAmount())) • \(shortDate(expense.expenseDate))\(presetSuffix)",
                    amount: expense.effectiveAmount(),
                    date: expense.expenseDate,
                    objectType: .plannedExpense,
                    sourceID: expense.id,
                    sortValue: expense.effectiveAmount()
                )
            }

        return MarinaWorkspaceAggregationCard(
            title: newestFirst ? "Planned Expenses Due" : "Upcoming Bills",
            subtitle: rows.isEmpty
                ? "No planned expenses are due in \(rangeLabel(range)). Ask Marina to show active presets if you want the templates instead."
                : rangeLabel(range),
            primaryValue: rows.first?.value,
            rows: Array(rows),
            traceSummary: "workspaceAggregation=upcomingPlannedExpenses,resultCount=\(rows.count)"
        )
    }

    private func plannedExpense(
        _ expense: PlannedExpense,
        matches targets: [MarinaResolvedAggregationTarget],
        presetTitlesByID: [UUID: String]
    ) -> Bool {
        let filters = targets.filter { target in
            switch target.role {
            case .filter, .primaryTarget:
                return true
            case .comparisonTarget, .simulationInput, .simulationOutput, .excludeFilter, .groupingDimension:
                return false
            }
        }
        guard filters.isEmpty == false else { return true }
        return filters.allSatisfy { target in
            switch target.entityType {
            case .category:
                return expense.category?.id == target.sourceID
                    || normalized(expense.category?.name ?? "") == normalized(target.displayName)
            case .card:
                return expense.card?.id == target.sourceID
                    || normalized(expense.card?.name ?? "") == normalized(target.displayName)
            case .preset:
                return expense.sourcePresetID == target.sourceID
                    || expense.sourcePresetID.flatMap { presetTitlesByID[$0] }.map { normalized($0) == normalized(target.displayName) } == true
                    || normalized(expense.title) == normalized(target.displayName)
            case .expense, .transaction:
                return expense.id == target.sourceID || normalized(expense.title).contains(normalized(target.displayName))
            case .merchant, .budget, .incomeSource, .allocationAccount, .savingsAccount, .workspace:
                return true
            }
        }
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

    private func presetTemplateRows(
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider
    ) -> MarinaWorkspaceAggregationCard {
        let listRows = plan.operation == .listRows || plan.ranking?.direction == .newest
        let rows = provider.fetchAllPresets()
            .filter { $0.isArchived == false && $0.plannedAmount > 0 }
            .sorted { lhs, rhs in
                if listRows {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
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
            title: listRows ? "Preset Templates" : "Highest Preset Costs",
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

    private func plannedExpensesByPreset(
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date
    ) -> MarinaWorkspaceAggregationCard {
        let presetTitlesByID = Dictionary(uniqueKeysWithValues: provider.fetchAllPresets().map { ($0.id, $0.title) })
        return groupedPlannedExpenses(
            title: "Planned Expenses by Preset",
            plan: plan,
            provider: provider,
            now: now,
            key: { expense in
                if let sourcePresetID = expense.sourcePresetID,
                   let presetTitle = presetTitlesByID[sourcePresetID] {
                    return presetTitle
                }
                return expense.title
            },
            traceName: "plannedExpensesByPreset"
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

    private func cardBalance(
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date
    ) -> MarinaWorkspaceAggregationCard {
        let range = plan.dateRange ?? monthRange(containing: now)
        let cardTargets = plan.targets.filter { $0.entityType == .card }
        let cards = provider.fetchAllCards()
            .filter { card in
                cardTargets.isEmpty
                    || cardTargets.contains { targetMatchesCard($0, card: card) }
            }
        let plannedExpenses = provider.fetchAllPlannedExpenses()
        let variableExpenses = provider.fetchAllVariableExpenses()
        let totals = cards.map { card in
            let planned = plannedExpenses
                .filter { contains($0.expenseDate, in: range) && expenseCardMatches($0.card, card: card) }
                .reduce(0.0) { $0 + $1.effectiveAmount() }
            let variable = variableExpenses
                .filter { contains($0.transactionDate, in: range) && expenseCardMatches($0.card, card: card) }
                .reduce(0.0) { $0 + $1.ledgerSignedAmount() }
            return (card: card, planned: planned, variable: variable, total: planned + variable)
        }
        .sorted { lhs, rhs in
            if lhs.total == rhs.total {
                return lhs.card.name.localizedCaseInsensitiveCompare(rhs.card.name) == .orderedAscending
            }
            return lhs.total > rhs.total
        }
        .prefix(limit(for: plan))

        if cardTargets.count == 1, let item = totals.first {
            return MarinaWorkspaceAggregationCard(
                title: "\(cardTargets[0].displayName) Balance",
                subtitle: rangeLabel(range),
                primaryValue: currency(item.total),
                rows: [
                    .init(label: "Variable ledger activity", value: currency(item.variable), amount: item.variable, objectType: .card, sourceID: item.card.id, sortValue: item.variable),
                    .init(label: "Planned card rows", value: currency(item.planned), amount: item.planned, objectType: .card, sourceID: item.card.id, sortValue: item.planned),
                    .init(label: "Current-period card spend", value: currency(item.total), amount: item.total, objectType: .card, sourceID: item.card.id, sortValue: item.total)
                ],
                traceSummary: "workspaceAggregation=cardBalance,resultCount=1,total=\(item.total)"
            )
        }

        let rows = totals.map { item in
            MarinaWorkspaceAggregationCard.Row(
                label: item.card.name,
                value: currency(item.total),
                amount: item.total,
                objectType: .card,
                sourceID: item.card.id,
                sortValue: item.total
            )
        }
        return MarinaWorkspaceAggregationCard(
            title: "Card Balances",
            subtitle: rangeLabel(range),
            primaryValue: rows.first?.value,
            rows: Array(rows),
            traceSummary: "workspaceAggregation=cardBalance,resultCount=\(rows.count)"
        )
    }

    private func savingsBalance(
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider
    ) -> MarinaWorkspaceAggregationCard {
        let accountTargets = plan.targets.filter { $0.entityType == .savingsAccount }
        let rows = provider.fetchAllSavingsAccounts()
            .filter { account in
                accountTargets.isEmpty
                    || accountTargets.contains { $0.sourceID == account.id || normalized($0.displayName) == normalized(account.name) }
            }
            .sorted { lhs, rhs in
                if lhs.total == rhs.total {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.total > rhs.total
            }
            .prefix(limit(for: plan))
            .map { account in
                MarinaWorkspaceAggregationCard.Row(
                    label: account.name,
                    value: currency(account.total),
                    amount: account.total,
                    objectType: .savingsAccount,
                    sourceID: account.id,
                    sortValue: account.total
                )
            }

        return MarinaWorkspaceAggregationCard(
            title: accountTargets.count == 1 ? "\(accountTargets[0].displayName) Balance" : "Savings Balances",
            subtitle: "Stored savings total",
            primaryValue: rows.first?.value,
            rows: Array(rows),
            traceSummary: "workspaceAggregation=savingsBalance,resultCount=\(rows.count)"
        )
    }

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
        provider: MarinaDataProvider,
        now: Date
    ) -> MarinaWorkspaceAggregationCard {
        let range = plan.dateRange ?? monthRange(containing: now)
        let accountTargets = plan.targets.filter { $0.entityType == .allocationAccount }
        let allocations = provider.fetchAllExpenseAllocations()
        let settlements = provider.fetchAllAllocationSettlements()
        let rows = provider.fetchAllAllocationAccounts()
            .filter { $0.isArchived == false }
            .filter { account in
                accountTargets.isEmpty
                    || accountTargets.contains { $0.sourceID == account.id || $0.displayName.localizedCaseInsensitiveCompare(account.name) == .orderedSame }
            }
            .map { account in
                (
                    account: account,
                    balance: reconciliationBalance(
                        account: account,
                        allocations: allocations,
                        settlements: settlements,
                        range: range
                    )
                )
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
            subtitle: rangeLabel(range),
            primaryValue: rows.first?.value,
            rows: Array(rows),
            traceSummary: "workspaceAggregation=sharedBalances,resultCount=\(rows.count),dateRange=\(rangeLabel(range))"
        )
    }

    private func reconciliationBalance(
        account: AllocationAccount,
        allocations: [ExpenseAllocation],
        settlements: [AllocationSettlement],
        range: HomeQueryDateRange
    ) -> Double {
        let allocationTotal = allocations
            .filter { $0.account?.id == account.id }
            .filter { allocation in
                guard let date = allocation.expense?.transactionDate ?? allocation.plannedExpense?.expenseDate else {
                    return false
                }
                return contains(date, in: range)
            }
            .reduce(0.0) { $0 + max(0, $1.allocatedAmount) }
        let settlementTotal = settlements
            .filter { $0.account?.id == account.id && contains($0.date, in: range) }
            .reduce(0.0) { $0 + $1.amount }
        return allocationTotal + settlementTotal
    }

    private func hasCardBalanceTarget(_ plan: MarinaAggregationPlan) -> Bool {
        plan.routeIntent?.requestedDetail == .balance
            && plan.targets.contains { $0.entityType == .card }
    }

    private func targetMatchesCard(_ target: MarinaResolvedAggregationTarget, card: Card) -> Bool {
        target.sourceID == card.id || normalized(target.displayName) == normalized(card.name)
    }

    private func expenseCardMatches(_ expenseCard: Card?, card: Card) -> Bool {
        expenseCard?.id == card.id || normalized(expenseCard?.name ?? "") == normalized(card.name)
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

    private func contains(_ date: Date, in range: HomeQueryDateRange) -> Bool {
        date >= range.startDate && date <= range.endDate
    }

    private func shortDate(_ date: Date) -> String {
        AppDateFormat.shortDate(date)
    }

    private func currency(_ value: Double) -> String {
        CurrencyFormatter.string(from: value)
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s&]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func delta(_ value: Double) -> String {
        if value > 0 { return "Up \(currency(value))" }
        if value < 0 { return "Down \(currency(abs(value)))" }
        return "No change"
    }
}
