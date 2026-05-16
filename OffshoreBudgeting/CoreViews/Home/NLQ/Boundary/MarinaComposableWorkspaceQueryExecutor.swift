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
    private let amountBasisAdapter: MarinaAmountBasisAdapter

    init(
        calendar: Calendar = .current,
        amountBasisAdapter: MarinaAmountBasisAdapter = MarinaAmountBasisAdapter()
    ) {
        self.calendar = calendar
        self.amountBasisAdapter = amountBasisAdapter
    }

    func execute(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date = Date(),
        amountBasis: MarinaFinancialAmountBasis? = nil
    ) -> MarinaComposableWorkspaceQueryExecutionResult {
        let amountBasis = amountBasis ?? amountBasisAdapter.basis(plan: plan, semanticQuery: nil)

        if plan.operation == .simulate {
            return simulate(candidate: candidate, resolved: resolved, plan: plan, provider: provider, now: now)
        }

        if let budget = resolvedBudgetTarget(in: resolved, provider: provider),
           plan.measure == .spend || candidate.semanticCommand?.requestedDetail == .linkedObjects {
            return .handled(budgetLinkedSummary(budget: budget, plan: plan, provider: provider))
        }

        if hasAllocationAccountTarget(plan) {
            return allocatedSpend(resolved: resolved, plan: plan, provider: provider, now: now)
        }

        switch (plan.operation, plan.measure, plan.grouping?.dimension) {
        case (.lookupDetails, .remainingBudget, _):
            guard let categoryTarget = resolved.resolvedTargets.first(where: { $0.entityType == .category }) else {
                return .unsupported
            }
            return .handled(categoryAvailability(target: categoryTarget, plan: plan, provider: provider, now: now))
        case (.rank, .spend, .card):
            return .handled(cardBudgetImpactRanking(plan: plan, provider: provider, now: now, amountBasis: amountBasis))
        case (.sum, .spend, _):
            guard resolved.resolvedTargets.isEmpty == false else { return .unsupported }
            return .handled(filteredSpend(candidate: candidate, resolved: resolved, plan: plan, provider: provider, now: now, amountBasis: amountBasis))
        case (.rank, .transactionAmount, .transaction), (.listRows, .transactionAmount, .transaction):
            guard plan.operation == .listRows || plan.ranking?.direction == .newest else { return .unsupported }
            return .handled(recentFilteredTransactions(resolved: resolved, plan: plan, provider: provider, now: now, amountBasis: amountBasis))
        case (.average, .spend, nil), (.average, .spend, .week), (.average, .spend, .month):
            guard plan.targets.isEmpty || resolved.resolvedTargets.isEmpty == false else { return .unsupported }
            return .handled(targetedPeriodicAverage(resolved: resolved, plan: plan, provider: provider, now: now, amountBasis: amountBasis))
        case (.compare, .spend, .category), (.compare, .spend, .transaction):
            guard plan.ranking != nil else { return .unsupported }
            return .handled(categoryDeltaDrivers(plan: plan, provider: provider, now: now, amountBasis: amountBasis))
        default:
            return .unsupported
        }
    }

    // MARK: - Budgets

    private func budgetLinkedSummary(
        budget: Budget,
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider
    ) -> MarinaWorkspaceAggregationCard {
        let range = plan.dateRange ?? HomeQueryDateRange(startDate: budget.startDate, endDate: budget.endDate)
        let linkedCardIDs = Set((budget.cardLinks ?? []).compactMap { $0.card?.id })
        let linkedPresetIDs = Set((budget.presetLinks ?? []).compactMap { $0.preset?.id })
        let linkedCardNames = (budget.cardLinks ?? []).compactMap { $0.card?.name }.sorted()
        let linkedPresetNames = (budget.presetLinks ?? []).compactMap { $0.preset?.title }.sorted()

        let variableSpend = provider.fetchAllVariableExpenses()
            .filter { contains($0.transactionDate, in: range) }
            .filter { expense in
                linkedCardIDs.isEmpty || expense.card.map { linkedCardIDs.contains($0.id) } == true
            }
            .reduce(0.0) { $0 + SavingsMathService.variableBudgetImpactAmount(for: $1) }

        let plannedSpend = provider.fetchAllPlannedExpenses()
            .filter { contains($0.expenseDate, in: range) }
            .filter { expense in
                expense.sourceBudgetID == budget.id
                    || expense.sourcePresetID.map { linkedPresetIDs.contains($0) } == true
                    || (linkedCardIDs.isEmpty == false && expense.card.map { linkedCardIDs.contains($0.id) } == true)
            }
            .reduce(0.0) { $0 + SavingsMathService.plannedBudgetImpactAmount(for: $1) }

        let limitRows = (budget.categoryLimits ?? []).compactMap { limit -> MarinaWorkspaceAggregationCard.Row? in
            guard let category = limit.category else { return nil }
            let parts = [
                limit.minAmount.map { "min \(currency($0))" },
                limit.maxAmount.map { "max \(currency($0))" }
            ].compactMap { $0 }
            return MarinaWorkspaceAggregationCard.Row(
                label: category.name,
                value: parts.isEmpty ? "Limit" : parts.joined(separator: " • "),
                objectType: .category,
                sourceID: category.id
            )
        }

        var rows: [MarinaWorkspaceAggregationCard.Row] = [
            .init(label: "Budget period", value: rangeLabel(range), date: range.startDate),
            .init(label: "Linked cards", value: linkedCardNames.isEmpty ? "None" : linkedCardNames.joined(separator: ", ")),
            .init(label: "Linked presets", value: linkedPresetNames.isEmpty ? "None" : linkedPresetNames.joined(separator: ", ")),
            .init(label: "Variable spend", value: currency(variableSpend), amount: variableSpend, sortValue: variableSpend),
            .init(label: "Planned spend", value: currency(plannedSpend), amount: plannedSpend, sortValue: plannedSpend)
        ]
        rows.append(contentsOf: limitRows)

        let total = variableSpend + plannedSpend
        return MarinaWorkspaceAggregationCard(
            title: "\(budget.name) Budget Summary",
            subtitle: rangeLabel(range),
            primaryValue: currency(total),
            rows: rows,
            traceSummary: "composableWorkspace=budgetLinkedSummary,linkedCards=\(linkedCardIDs.count),linkedPresets=\(linkedPresetIDs.count),total=\(total)"
        )
    }

    // MARK: - Cards

    private func cardBudgetImpactRanking(
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date,
        amountBasis: MarinaFinancialAmountBasis
    ) -> MarinaWorkspaceAggregationCard {
        let range = plan.dateRange ?? monthRange(containing: now)
        var totals: [String: (amount: Double, id: UUID?)] = [:]

        for expense in provider.fetchAllVariableExpenses() where contains(expense.transactionDate, in: range) {
            let name = expense.card?.name ?? "No Card"
            let id = expense.card?.id
            totals[name, default: (0, id)].amount += amountBasisAdapter.variableAmount(for: expense, basis: amountBasis)
            totals[name]?.id = id
        }

        for expense in provider.fetchAllPlannedExpenses() where contains(expense.expenseDate, in: range) {
            let name = expense.card?.name ?? "No Card"
            let id = expense.card?.id
            totals[name, default: (0, id)].amount += amountBasisAdapter.plannedAmount(for: expense, basis: amountBasis)
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
        now: Date,
        amountBasis: MarinaFinancialAmountBasis
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
        let rows = spendingRows(provider: provider, range: range, amountBasis: amountBasis)
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
        now: Date,
        amountBasis: MarinaFinancialAmountBasis
    ) -> MarinaWorkspaceAggregationCard {
        let range = plan.dateRange ?? lookbackRange(from: now, months: 12)
        let filters = resolved.resolvedTargets.filter { $0.role != .excludeFilter }
        let rows = spendingRows(provider: provider, range: range, amountBasis: amountBasis)
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

    private func categoryAvailability(
        target: MarinaResolvedEntityMention,
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date
    ) -> MarinaWorkspaceAggregationCard {
        let range = plan.dateRange ?? monthRange(containing: now)
        let result = HomeCategoryLimitsAggregator.build(
            budgets: provider.fetchAllBudgets(),
            categories: provider.fetchAllCategories(),
            plannedExpenses: provider.fetchAllPlannedExpenses(),
            variableExpenses: provider.fetchAllVariableExpenses(),
            rangeStart: range.startDate,
            rangeEnd: range.endDate,
            inclusionPolicy: .limitsOnly,
            calendar: calendar
        )
        let metric = result.metrics.first { metric in
            metric.categoryID == target.sourceID || normalized(metric.name) == normalized(target.displayName)
        }

        guard let metric else {
            return MarinaWorkspaceAggregationCard(
                title: "\(target.displayName) Availability",
                subtitle: rangeLabel(range),
                primaryValue: "No limit",
                rows: [
                    .init(label: "Status", value: "No category limit found"),
                    .init(label: "Budget", value: result.activeBudget?.name ?? "No active budget")
                ],
                traceSummary: "composableWorkspace=categoryAvailability,result=missingLimit,target=\(target.displayName)"
            )
        }

        let status = availabilityStatus(metric)
        let available = metric.availableRaw(for: .all)
        let budgetLimit = categoryLimit(for: target, budget: result.activeBudget)
        var rows: [MarinaWorkspaceAggregationCard.Row] = [
            .init(label: "Status", value: status),
            .init(label: "Spent", value: currency(metric.spentTotal), amount: metric.spentTotal, sortValue: metric.spentTotal),
            .init(label: "Planned", value: currency(metric.spentPlanned), amount: metric.spentPlanned, sortValue: metric.spentPlanned),
            .init(label: "Actual", value: currency(metric.spentVariable), amount: metric.spentVariable, sortValue: metric.spentVariable),
            .init(label: "Budget", value: result.activeBudget?.name ?? "No active budget")
        ]
        if let maxAmount = metric.maxAmount {
            rows.insert(.init(label: "Max", value: currency(maxAmount), amount: maxAmount, sortValue: maxAmount), at: 2)
        }
        if let minAmount = budgetLimit?.minAmount {
            rows.insert(.init(label: "Min", value: currency(minAmount), amount: minAmount, sortValue: minAmount), at: 2)
        }
        if let available {
            rows.insert(.init(label: available >= 0 ? "Remaining" : "Over", value: currency(abs(available)), amount: available, sortValue: available), at: 1)
        }

        return MarinaWorkspaceAggregationCard(
            title: "\(metric.name) Availability",
            subtitle: rangeLabel(range),
            primaryValue: available.map { currency(abs($0)) } ?? currency(metric.spentTotal),
            rows: rows,
            traceSummary: "composableWorkspace=categoryAvailability,target=\(metric.name),spent=\(metric.spentTotal),available=\(available ?? 0)"
        )
    }

    private func availabilityStatus(_ metric: CategoryAvailabilityMetric) -> String {
        guard metric.isLimited else { return "Unlimited" }
        switch metric.status(for: .all, nearThreshold: HomeCategoryLimitsAggregator.defaultNearThreshold) {
        case .over:
            return "Over"
        case .near:
            return "Near"
        case .ok:
            return "Available"
        }
    }

    private func targetedPeriodicAverage(
        resolved: MarinaResolvedQueryCandidate,
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date,
        amountBasis: MarinaFinancialAmountBasis
    ) -> MarinaWorkspaceAggregationCard {
        let range = plan.dateRange ?? lookbackRange(from: now, months: 3)
        let filters = resolved.resolvedTargets
        let rows = spendingRows(provider: provider, range: range, amountBasis: amountBasis)
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
        let resolvedEntityTypes = filters.map { $0.entityType.rawValue }.joined(separator: "+")
        let resolvedObjectIDs = filters.compactMap { $0.sourceID?.uuidString }.joined(separator: "+")
        let resolvedObjectNames = filters.map(\.displayName).joined(separator: "+")

        return MarinaWorkspaceAggregationCard(
            title: "Average \(periodLabel(plan.grouping?.dimension ?? .week)) Spending",
            subtitle: filterSummary(include: filters, exclude: [], range: range),
            primaryValue: currency(average),
            rows: cardRows,
            traceSummary: [
                "composableWorkspace=targetedPeriodicAverage",
                "targetFilterApplied=\(filters.isEmpty == false)",
                "resolvedEntityType=\(resolvedEntityTypes)",
                "resolvedObjectID=\(resolvedObjectIDs)",
                "resolvedObjectName=\(resolvedObjectNames)",
                "dateRange=\(rangeLabel(range))",
                "aggregationDenominator=\(buckets.count)",
                "aggregationRowCount=\(rows.count)",
                "aggregationSourceEntity=spendingRows",
                "responseScope=\(filters.isEmpty ? "broad" : "targeted")",
                "average=\(average)"
            ].joined(separator: ",")
        )
    }

    // MARK: - Deltas

    private func categoryDeltaDrivers(
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date,
        amountBasis: MarinaFinancialAmountBasis
    ) -> MarinaWorkspaceAggregationCard {
        let ranges = comparisonRanges(for: plan, now: now)
        let currentRows = spendingRows(provider: provider, range: ranges.current, amountBasis: amountBasis)
        let previousRows = spendingRows(provider: provider, range: ranges.previous, amountBasis: amountBasis)
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
        let rows = spendingRows(provider: provider, range: range, amountBasis: .budgetImpact)
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

    private func spendingRows(
        provider: MarinaDataProvider,
        range: HomeQueryDateRange,
        amountBasis: MarinaFinancialAmountBasis
    ) -> [SpendingRow] {
        let variable = provider.fetchAllVariableExpenses()
            .filter { contains($0.transactionDate, in: range) }
            .map { row(for: $0, amount: amountBasisAdapter.variableAmount(for: $0, basis: amountBasis)) }
        let planned = provider.fetchAllPlannedExpenses()
            .filter { contains($0.expenseDate, in: range) }
            .map { row(for: $0, amount: amountBasisAdapter.plannedAmount(for: $0, basis: amountBasis)) }
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
        case .preset:
            return normalized(row.title) == normalized(target.displayName)
                || normalized(row.title).contains(normalized(target.displayName))
        case .allocationAccount, .budget, .incomeSource, .savingsAccount, .workspace:
            return false
        }
    }

    // MARK: - Helpers

    private func hasAllocationAccountTarget(_ plan: MarinaAggregationPlan) -> Bool {
        plan.targets.contains { $0.entityType == .allocationAccount }
    }

    private func resolvedBudgetTarget(
        in resolved: MarinaResolvedQueryCandidate,
        provider: MarinaDataProvider
    ) -> Budget? {
        guard let target = resolved.resolvedTargets.first(where: { $0.entityType == .budget }) else {
            return nil
        }
        return provider.fetchAllBudgets().first { budget in
            budget.id == target.sourceID || normalized(budget.name) == normalized(target.displayName)
        }
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
