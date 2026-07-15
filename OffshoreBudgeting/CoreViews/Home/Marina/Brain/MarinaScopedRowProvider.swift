import Foundation

struct MarinaScopedRowProvider {
    let adapterRegistry: MarinaEntityAdapterRegistry

    init(adapterRegistry: MarinaEntityAdapterRegistry = MarinaEntityAdapterRegistry()) {
        self.adapterRegistry = adapterRegistry
    }

    func rows(
        for plan: MarinaUniversalQueryPlan,
        from snapshot: MarinaWorkspaceSnapshot
    ) -> [MarinaQueryableRow]? {
        guard resolvedWorkspaceIsValid(for: plan, snapshot: snapshot),
              resolvedBudgetScopeIsValid(for: plan, snapshot: snapshot) else {
            return []
        }

        return switch (plan.surface, plan.projection) {
        case (_, .records):
            recordRows(for: plan, snapshot: snapshot)
        case (.savingsLedgerEntries, .activity):
            rows(
                MarinaSavingsLedgerEntryAdapter().rows(from: snapshot),
                matching: plan.resolvedTarget,
                relationship: .savingsAccount
            )
        case (.reconciliationLedgerEntries, .activity):
            rows(
                MarinaReconciliationLedgerEntryAdapter().rows(from: snapshot),
                matching: plan.resolvedTarget,
                relationship: .reconciliationAccount
            )
        case (.semantic(.preset), .linkedBudgets):
            linkedBudgetRows(target: plan.resolvedTarget, snapshot: snapshot)
        case (.semantic(.incomeSeries), .occurrences):
            occurrenceRows(target: plan.resolvedTarget, snapshot: snapshot)
        case (.semantic(.budget), .summary),
             (.semantic(.budget), .linkedCards),
             (.semantic(.budget), .linkedPresets),
             (.semantic(.budget), .income),
             (.semantic(.budget), .expenses):
            budgetRows(for: plan, snapshot: snapshot)
        case (_, .summary),
             (_, .income),
             (_, .expenses),
             (_, .linkedCards),
             (_, .linkedPresets),
             (_, .linkedBudgets),
             (_, .activity),
             (_, .occurrences):
            nil
        }
    }

    private func recordRows(
        for plan: MarinaUniversalQueryPlan,
        snapshot: MarinaWorkspaceSnapshot
    ) -> [MarinaQueryableRow]? {
        guard case .budget? = plan.resolvedScope else {
            return adapterRegistry.rows(for: plan.surface, from: snapshot)
        }
        guard let budget = resolvedBudget(for: plan, snapshot: snapshot),
              let lens = budgetLens(for: budget, plan: plan, snapshot: snapshot) else {
            return []
        }

        switch plan.surface {
        case .semantic(.income):
            return relatedRows(
                adapterRegistry.adapter(for: .income)?.rows(from: snapshot) ?? [],
                ids: Set(lens.incomesInBudget.map(\.id))
            )
        case .semantic(.plannedExpense):
            return relatedRows(
                adapterRegistry.adapter(for: .plannedExpense)?.calculationRows(from: snapshot) ?? [],
                ids: Set(lens.plannedExpensesInBudget.map(\.id))
            )
        case .semantic(.variableExpense):
            return relatedRows(
                adapterRegistry.adapter(for: .variableExpense)?.calculationRows(from: snapshot) ?? [],
                ids: Set(lens.variableExpensesInBudget.map(\.id))
            )
        case .unifiedExpenses:
            let variableIDs = Set(lens.variableExpensesInBudget.map(\.id))
            let plannedIDs = Set(lens.plannedExpensesInBudget.map(\.id))
            let variableRows = adapterRegistry.adapter(for: .variableExpense)?.calculationRows(from: snapshot) ?? []
            let plannedRows = adapterRegistry.adapter(for: .plannedExpense)?.calculationRows(from: snapshot) ?? []
            return relatedRows(variableRows, ids: variableIDs) + relatedRows(plannedRows, ids: plannedIDs)
        case .semantic(_),
             .savingsLedgerEntries,
             .reconciliationLedgerEntries:
            return adapterRegistry.rows(for: plan.surface, from: snapshot)
        }
    }

    private func resolvedWorkspaceIsValid(
        for plan: MarinaUniversalQueryPlan,
        snapshot: MarinaWorkspaceSnapshot
    ) -> Bool {
        let workspace = snapshot.workspace
        if case let .workspace(workspaceID)? = plan.resolvedScope,
           workspaceID != workspace.id {
            return false
        }

        for reference in [plan.resolvedTarget, plan.resolvedComparisonTarget].compactMap({ $0 })
        where reference.entity == .workspace {
            if let id = reference.id {
                guard id == workspace.id else { return false }
            } else {
                guard workspace.name.localizedCaseInsensitiveCompare(reference.displayName) == .orderedSame else {
                    return false
                }
            }
        }
        return true
    }

    private func resolvedBudgetScopeIsValid(
        for plan: MarinaUniversalQueryPlan,
        snapshot: MarinaWorkspaceSnapshot
    ) -> Bool {
        guard case let .budget(budgetID)? = plan.resolvedScope else { return true }
        return snapshot.budgets.contains { budget in
            budget.id == budgetID && budget.workspace?.id == snapshot.workspace.id
        }
    }

    private func budgetRows(
        for plan: MarinaUniversalQueryPlan,
        snapshot: MarinaWorkspaceSnapshot
    ) -> [MarinaQueryableRow] {
        guard let budget = resolvedBudget(for: plan, snapshot: snapshot),
              let lens = budgetLens(for: budget, plan: plan, snapshot: snapshot) else {
            return []
        }

        switch plan.projection {
        case .summary:
            return [budgetSummaryRow(lens: lens)]
        case .linkedCards:
            return relatedRows(
                adapterRegistry.adapter(for: .card)?.rows(from: snapshot) ?? [],
                ids: Set(lens.linkedCards.map(\.id))
            )
        case .linkedPresets:
            return relatedRows(
                adapterRegistry.adapter(for: .preset)?.rows(from: snapshot) ?? [],
                ids: Set(lens.linkedPresets.map(\.id))
            )
        case .income:
            return relatedRows(
                adapterRegistry.adapter(for: .income)?.rows(from: snapshot) ?? [],
                ids: Set(lens.incomesInBudget.map(\.id))
            )
        case .expenses:
            let variableIDs = Set(lens.variableExpensesInBudget.map(\.id))
            let plannedIDs = Set(lens.plannedExpensesInBudget.map(\.id))
            let variableRows = adapterRegistry.adapter(for: .variableExpense)?.calculationRows(from: snapshot) ?? []
            let plannedRows = adapterRegistry.adapter(for: .plannedExpense)?.calculationRows(from: snapshot) ?? []
            return relatedRows(variableRows, ids: variableIDs) + relatedRows(plannedRows, ids: plannedIDs)
        case .records,
             .linkedBudgets,
             .activity,
             .occurrences:
            return []
        }
    }

    private func resolvedBudget(
        for plan: MarinaUniversalQueryPlan,
        snapshot: MarinaWorkspaceSnapshot
    ) -> Budget? {
        let workspaceID = snapshot.workspace.id
        if case let .workspace(scopeWorkspaceID)? = plan.resolvedScope,
           scopeWorkspaceID != workspaceID {
            return nil
        }

        let scopedBudgetID: UUID?
        if case let .budget(id)? = plan.resolvedScope {
            scopedBudgetID = id
        } else {
            scopedBudgetID = nil
        }
        let target = plan.resolvedTarget?.entity == .budget ? plan.resolvedTarget : nil
        if let scopedBudgetID,
           let targetID = target?.id,
           targetID != scopedBudgetID {
            return nil
        }

        let eligibleBudgets = snapshot.budgets.filter { $0.workspace?.id == workspaceID }
        if let budgetID = scopedBudgetID ?? target?.id {
            return eligibleBudgets.first { $0.id == budgetID }
        }
        if let target {
            let matches = eligibleBudgets.filter {
                $0.name.localizedCaseInsensitiveCompare(target.displayName) == .orderedSame
            }
            return matches.count == 1 ? matches[0] : nil
        }
        if let dateRange = plan.dateRange {
            return BudgetRangeOverlap.pickActiveBudget(
                from: eligibleBudgets,
                for: DateRange(start: dateRange.startDate, end: dateRange.endDate)
            )
        }
        return eligibleBudgets.count == 1 ? eligibleBudgets[0] : nil
    }

    private func budgetLens(
        for budget: Budget,
        plan: MarinaUniversalQueryPlan,
        snapshot: MarinaWorkspaceSnapshot
    ) -> BudgetLensService.Lens? {
        let requestedDateRange: DateRange?
        switch plan.dateRangeSource {
        case .defaulted:
            requestedDateRange = nil
        case .explicit, .conversationContext:
            requestedDateRange = plan.dateRange.map {
                DateRange(start: $0.startDate, end: $0.endDate)
            }
        }
        let outcome = BudgetLensService.makeLens(
            workspace: snapshot.workspace,
            budget: budget,
            budgetCardLinks: snapshot.budgets.flatMap { $0.cardLinks ?? [] },
            budgetPresetLinks: snapshot.budgets.flatMap { $0.presetLinks ?? [] },
            budgetCategoryLimits: snapshot.budgets.flatMap { $0.categoryLimits ?? [] },
            workspaceCategories: snapshot.categories,
            workspaceIncomes: snapshot.incomes,
            workspacePlannedExpenses: snapshot.homeCalculationPlannedExpenses,
            workspaceVariableExpenses: snapshot.homeCalculationVariableExpenses,
            workspaceSavingsEntries: snapshot.savingsEntries,
            requestedDateRange: requestedDateRange,
            futureCalculationPolicy: BudgetLensService.FutureCalculationPolicy(
                excludeFuturePlannedExpenses: false,
                excludeFutureVariableExpenses: false,
                now: .now
            )
        )
        return outcome.resolvedLens
    }

    private func budgetSummaryRow(lens: BudgetLensService.Lens) -> MarinaQueryableRow {
        let budget = lens.budget
        let totals = lens.totals
        return MarinaQueryableRow(
            id: budget.id,
            entity: .budget,
            displayName: budget.name.isEmpty ? budget.id.uuidString : budget.name,
            fields: [
                .id: .text(budget.id.uuidString),
                .name: .text(budget.name),
                .startDate: .date(lens.dateRange.start),
                .endDate: .date(lens.dateRange.end),
                .budgetImpact: .money(totals.unifiedExpenseTotal),
                .projectedBudgetImpact: .money(totals.plannedExpenseProjectedTotal),
                .plannedIncomeTotal: .money(totals.plannedIncomeTotal),
                .actualIncomeTotal: .money(totals.actualIncomeTotal),
                .plannedExpenseProjectedTotal: .money(totals.plannedExpenseProjectedTotal),
                .plannedExpenseActualTotal: .money(totals.plannedExpenseActualTotal),
                .plannedExpenseEffectiveTotal: .money(totals.plannedExpenseEffectiveTotal),
                .variableExpenseTotal: .money(totals.variableExpenseTotal),
                .unifiedExpenseTotal: .money(totals.unifiedExpenseTotal),
                .maximumSavings: .money(totals.maxSavings),
                .projectedSavings: .money(totals.projectedSavings),
                .actualSavings: .money(totals.actualSavings)
            ],
            relationships: [
                .workspace: MarinaResolvedRelationship(
                    key: .workspace,
                    targetEntity: .workspace,
                    targetID: lens.workspace.id,
                    displayName: lens.workspace.name
                )
            ]
        )
    }

    private func relatedRows(
        _ rows: [MarinaQueryableRow],
        ids: Set<UUID>
    ) -> [MarinaQueryableRow] {
        rows.filter { ids.contains($0.id) }
    }

    private func linkedBudgetRows(
        target: MarinaResolvedEntityReference?,
        snapshot: MarinaWorkspaceSnapshot
    ) -> [MarinaQueryableRow] {
        guard target == nil || target?.entity == .preset,
              let presetRows = adapterRegistry.adapter(for: .preset)?.rows(from: snapshot),
              let budgetRows = adapterRegistry.adapter(for: .budget)?.rows(from: snapshot) else {
            return []
        }

        let matchingPresets = presetRows.filter { matches($0, target: target) }
        let budgetIDs = Set(
            matchingPresets
                .flatMap { $0.relationshipCollections[.budget] ?? [] }
                .compactMap(\.targetID)
        )
        return budgetRows.filter { budgetIDs.contains($0.id) }
    }

    private func occurrenceRows(
        target: MarinaResolvedEntityReference?,
        snapshot: MarinaWorkspaceSnapshot
    ) -> [MarinaQueryableRow] {
        guard target == nil || target?.entity == .incomeSeries,
              let rows = adapterRegistry.adapter(for: .income)?.rows(from: snapshot) else {
            return []
        }
        guard let target else {
            return rows.filter { $0.relationships[.incomeSeries] != nil }
        }
        return rows.filter { row in
            relationship(row.relationships[.incomeSeries], matches: target)
        }
    }

    private func rows(
        _ rows: [MarinaQueryableRow],
        matching target: MarinaResolvedEntityReference?,
        relationship key: MarinaRelationshipKey
    ) -> [MarinaQueryableRow] {
        guard let target else { return rows }
        return rows.filter { row in
            relationship(row.relationships[key], matches: target)
        }
    }

    private func matches(
        _ row: MarinaQueryableRow,
        target: MarinaResolvedEntityReference?
    ) -> Bool {
        guard let target else { return true }
        guard row.entity == target.entity else { return false }
        if let id = target.id {
            return row.id == id
        }
        return row.displayName.localizedCaseInsensitiveCompare(target.displayName) == .orderedSame
    }

    private func relationship(
        _ relationship: MarinaResolvedRelationship?,
        matches target: MarinaResolvedEntityReference
    ) -> Bool {
        guard let relationship else { return false }
        guard relationship.targetEntity == target.entity else { return false }
        if let id = target.id {
            return relationship.targetID == id
        }
        return relationship.displayName?.localizedCaseInsensitiveCompare(target.displayName) == .orderedSame
    }
}
