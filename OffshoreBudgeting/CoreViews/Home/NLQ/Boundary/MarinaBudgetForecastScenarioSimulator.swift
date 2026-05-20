import Foundation

@MainActor
struct MarinaBudgetForecastScenarioSimulator {
    private enum ScenarioKind: String {
        case spend
        case earn
        case save
    }

    private struct SpendingRow {
        let amount: Double
        let date: Date
        let cardID: UUID?
        let cardName: String?
        let categoryID: UUID?
        let categoryName: String
    }

    private let calendar: Calendar
    private let amountBasisAdapter: MarinaAmountBasisAdapter

    init(
        calendar: Calendar = .current,
        amountBasisAdapter: MarinaAmountBasisAdapter = MarinaAmountBasisAdapter()
    ) {
        self.calendar = calendar
        self.amountBasisAdapter = amountBasisAdapter
    }

    func simulate(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date
    ) -> MarinaWorkspaceAggregationCard? {
        guard let amount = firstCurrencyAmount(in: candidate.rawPrompt) else {
            return nil
        }

        let kind = scenarioKind(from: candidate.rawPrompt)
        let budget = selectedBudget(resolved: resolved, plan: plan, provider: provider, now: now)
        let range = selectedRange(plan: plan, budget: budget, now: now)
        let filters = scopedTargets(from: resolved.resolvedTargets, plan: plan)
        guard kind != .spend || filters.contains(where: { $0.entityType == .category || $0.entityType == .card }) else {
            return nil
        }

        let budgetCardIDs = linkedCardIDs(for: budget)
        let baseRows = spendingRows(provider: provider, range: range)
            .filter { row in budgetCardIDs.isEmpty || row.cardID.map { budgetCardIDs.contains($0) } == true }
        let scopedRows = baseRows.filter { row in filters.isEmpty || filters.allSatisfy { matches(row: row, target: $0) } }
        let spendBefore = scopedRows.reduce(0.0) { $0 + $1.amount }
        let workspaceSpendBefore = baseRows.reduce(0.0) { $0 + $1.amount }
        let plannedIncomeBefore = provider.fetchAllIncomes()
            .filter { $0.isPlanned && contains($0.date, in: range) }
            .reduce(0.0) { $0 + $1.amount }

        let signedAmount = signedScenarioAmount(amount, prompt: candidate.rawPrompt)
        let spendDelta = kind == .spend ? signedAmount : 0
        let incomeDelta = kind == .earn ? signedAmount : 0
        let savingsDelta = kind == .save ? signedAmount : 0
        let spendAfter = spendBefore + spendDelta
        let workspaceSpendAfter = workspaceSpendBefore + spendDelta
        let plannedIncomeAfter = plannedIncomeBefore + incomeDelta
        let remainingBefore = plannedIncomeBefore - workspaceSpendBefore
        let remainingAfter = plannedIncomeAfter - workspaceSpendAfter - savingsDelta
        let targetLabel = scenarioTargetLabel(filters: filters, budget: budget)

        var rows: [MarinaWorkspaceAggregationCard.Row] = [
            .init(label: "Scenario", value: scenarioLabel(kind: kind, amount: signedAmount), amount: signedAmount, sortValue: signedAmount),
            .init(label: "Scope spend before", value: currency(spendBefore), amount: spendBefore, sortValue: spendBefore),
            .init(label: "Scope spend after", value: currency(spendAfter), amount: spendAfter, sortValue: spendAfter),
            .init(label: "Workspace spend after", value: currency(workspaceSpendAfter), amount: workspaceSpendAfter, sortValue: workspaceSpendAfter),
            .init(label: "Remaining before", value: currency(remainingBefore), amount: remainingBefore, sortValue: remainingBefore),
            .init(label: "Remaining after", value: currency(remainingAfter), amount: remainingAfter, sortValue: remainingAfter)
        ]

        if kind == .earn {
            rows.append(.init(label: "Planned income after", value: currency(plannedIncomeAfter), amount: plannedIncomeAfter, sortValue: plannedIncomeAfter))
        }
        if kind == .save {
            rows.append(.init(label: "Savings scenario", value: currency(savingsDelta), amount: savingsDelta, sortValue: savingsDelta))
        }
        if let categoryTarget = filters.first(where: { $0.entityType == .category }),
           let limit = categoryLimit(for: categoryTarget, budget: budget),
           let maxAmount = limit.maxAmount {
            let categorySpendAfter = baseRows
                .filter { matches(row: $0, target: categoryTarget) }
                .reduce(0.0) { $0 + $1.amount } + spendDelta
            rows.append(
                .init(
                    label: "Category limit",
                    value: "\(currency(maxAmount)) (\(categorySpendAfter > maxAmount ? "over" : "under"))",
                    amount: maxAmount,
                    sortValue: maxAmount
                )
            )
        }

        let remainingDelta = remainingAfter - remainingBefore
        return MarinaWorkspaceAggregationCard(
            title: "What-If Budget Impact",
            subtitle: "\(targetLabel) • \(rangeLabel(range))",
            primaryValue: delta(remainingDelta),
            rows: rows,
            traceSummary: "composableWorkspace=simulation,kind=\(kind.rawValue),amount=\(signedAmount),scope=\(targetLabel),range=\(rangeLabel(range))"
        )
    }

    private func scenarioKind(from prompt: String) -> ScenarioKind {
        let text = normalized(prompt)
        let padded = " \(text) "
        if padded.contains(" earn ") || padded.contains(" income ") || padded.contains(" get paid ") || padded.contains(" receive ") || padded.contains(" make ") {
            return .earn
        }
        if padded.contains(" save ") || padded.contains(" savings ") || padded.contains(" put away ") {
            return .save
        }
        return .spend
    }

    private func selectedBudget(
        resolved: MarinaResolvedQueryCandidate,
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date
    ) -> Budget? {
        if let target = resolved.resolvedTargets.first(where: { $0.entityType == .budget })
            ?? plan.targets.first(where: { $0.entityType == .budget }).map(resolvedTarget) {
            return provider.fetchAllBudgets().first { budget in
                budget.id == target.sourceID || normalized(budget.name) == normalized(target.displayName)
            }
        }

        let range = plan.dateRange ?? monthRange(containing: now)
        return provider.fetchAllBudgets().first { $0.startDate <= now && $0.endDate >= now }
            ?? provider.fetchAllBudgets().first { $0.startDate <= range.endDate && $0.endDate >= range.startDate }
    }

    private func selectedRange(plan: MarinaAggregationPlan, budget: Budget?, now: Date) -> HomeQueryDateRange {
        if let range = plan.dateRange {
            return range
        }
        if let budget {
            return HomeQueryDateRange(startDate: budget.startDate, endDate: budget.endDate)
        }
        return monthRange(containing: now)
    }

    private func scopedTargets(
        from resolvedTargets: [MarinaResolvedEntityMention],
        plan: MarinaAggregationPlan
    ) -> [MarinaResolvedEntityMention] {
        let resolved = resolvedTargets.filter { target in
            guard isIncludedScopeRole(target.role) else { return false }
            switch target.entityType {
            case .category, .card:
                return true
            case .budget, .merchant, .expense, .transaction, .preset, .allocationAccount, .incomeSource, .savingsAccount, .workspace:
                return false
            }
        }
        if resolved.isEmpty == false {
            return resolved
        }
        return plan.targets.compactMap { target in
            guard isIncludedScopeRole(target.role) else { return nil }
            switch target.entityType {
            case .category, .card:
                return resolvedTarget(target)
            default:
                return nil
            }
        }
    }

    private func isIncludedScopeRole(_ role: MarinaResolvedTargetRole) -> Bool {
        switch role {
        case .filter, .primaryTarget, .simulationInput, .simulationOutput:
            return true
        case .excludeFilter, .comparisonTarget, .groupingDimension:
            return false
        }
    }

    private func spendingRows(provider: MarinaDataProvider, range: HomeQueryDateRange) -> [SpendingRow] {
        let variable = provider.fetchAllVariableExpenses()
            .filter { contains($0.transactionDate, in: range) }
            .map { expense in
                SpendingRow(
                    amount: amountBasisAdapter.variableAmount(for: expense, basis: .budgetImpact),
                    date: expense.transactionDate,
                    cardID: expense.card?.id,
                    cardName: expense.card?.name,
                    categoryID: expense.category?.id,
                    categoryName: expense.category?.name ?? "Uncategorized"
                )
            }
        let planned = provider.fetchAllPlannedExpenses()
            .filter { contains($0.expenseDate, in: range) }
            .map { expense in
                SpendingRow(
                    amount: amountBasisAdapter.plannedAmount(for: expense, basis: .budgetImpact),
                    date: expense.expenseDate,
                    cardID: expense.card?.id,
                    cardName: expense.card?.name,
                    categoryID: expense.category?.id,
                    categoryName: expense.category?.name ?? "Uncategorized"
                )
            }
        return variable + planned
    }

    private func matches(row: SpendingRow, target: MarinaResolvedEntityMention) -> Bool {
        switch target.entityType {
        case .card:
            return row.cardID == target.sourceID || normalized(row.cardName ?? "") == normalized(target.displayName)
        case .category:
            return row.categoryID == target.sourceID || normalized(row.categoryName) == normalized(target.displayName)
        default:
            return false
        }
    }

    private func linkedCardIDs(for budget: Budget?) -> Set<UUID> {
        Set((budget?.cardLinks ?? []).compactMap { $0.card?.id })
    }

    private func categoryLimit(for target: MarinaResolvedEntityMention, budget: Budget?) -> BudgetCategoryLimit? {
        budget?.categoryLimits?.first { limit in
            limit.category?.id == target.sourceID || normalized(limit.category?.name ?? "") == normalized(target.displayName)
        }
    }

    private func resolvedTarget(_ target: MarinaResolvedAggregationTarget) -> MarinaResolvedEntityMention {
        let mentionRole = MarinaEntityMentionRole(rawValue: target.role.rawValue) ?? .filter
        let mention = MarinaUnresolvedEntityMention(
            role: mentionRole,
            rawText: target.displayName,
            typeHint: target.entityType
        )
        return MarinaResolvedEntityMention(
            id: target.id,
            mention: mention,
            role: target.role,
            entityType: target.entityType,
            displayName: target.displayName,
            sourceID: target.sourceID
        )
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

    private func scenarioTargetLabel(filters: [MarinaResolvedEntityMention], budget: Budget?) -> String {
        var parts = filters.map(\.displayName)
        if let budget {
            parts.insert(budget.name, at: 0)
        }
        return parts.isEmpty ? "Workspace" : parts.joined(separator: " / ")
    }

    private func scenarioLabel(kind: ScenarioKind, amount: Double) -> String {
        switch kind {
        case .spend:
            return "Spend \(currency(amount))"
        case .earn:
            return "Earn \(currency(amount))"
        case .save:
            return "Save \(currency(amount))"
        }
    }

    private func signedScenarioAmount(_ amount: Double, prompt: String) -> Double {
        let text = " \(normalized(prompt)) "
        if text.contains(" less ")
            || text.contains(" lower ")
            || text.contains(" reduce ")
            || text.contains(" decrease ")
            || text.contains(" cut ") {
            return -abs(amount)
        }
        return amount
    }

    private func monthRange(containing date: Date) -> HomeQueryDateRange {
        let interval = calendar.dateInterval(of: .month, for: date)
        let start = interval?.start ?? date
        let end = (interval?.end ?? date).addingTimeInterval(-1)
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func contains(_ date: Date, in range: HomeQueryDateRange) -> Bool {
        date >= range.startDate && date <= range.endDate
    }

    private func rangeLabel(_ range: HomeQueryDateRange) -> String {
        "\(shortDate(range.startDate))-\(shortDate(range.endDate))"
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

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
