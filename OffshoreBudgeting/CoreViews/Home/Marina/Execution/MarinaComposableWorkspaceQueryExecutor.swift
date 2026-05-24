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
    private let allowsPromptRouteFallback: Bool

    init(
        calendar: Calendar = .current,
        amountBasisAdapter: MarinaAmountBasisAdapter = MarinaAmountBasisAdapter(),
        allowsPromptRouteFallback: Bool = true
    ) {
        self.calendar = calendar
        self.amountBasisAdapter = amountBasisAdapter
        self.allowsPromptRouteFallback = allowsPromptRouteFallback
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

        switch candidate.routeIntent?.kind ?? plan.routeIntent?.kind {
        case .budgetSummary?:
            if let budget = resolvedBudgetTarget(in: resolved, candidate: candidate, provider: provider, now: now) {
                return .handled(budgetLinkedSummary(budget: budget, plan: plan, provider: provider))
            }
        case .budgetInventory?:
            return .handled(budgetsOverlappingRange(prompt: candidate.rawPrompt, plan: plan, provider: provider, now: now))
        case .overBudgetCategories?:
            return .handled(overBudgetCategories(plan: plan, provider: provider, now: now, amountBasis: amountBasis))
        case .allocationRows?:
            return .handled(allocationRows(resolved: resolved, plan: plan, provider: provider, now: now))
        case .settlementRows?:
            return .handled(settlementRows(resolved: resolved, plan: plan, provider: provider, now: now))
        case .budgetMembership?:
            if let detail = (candidate.routeIntent?.requestedDetail ?? plan.routeIntent?.requestedDetail ?? candidate.semanticCommand?.requestedDetail),
               detail == .membership,
               asksForBudgetMembershipList(candidate.rawPrompt),
               let member = budgetMemberTarget(in: resolved) {
                return .handled(budgetsUsingMember(member, provider: provider))
            }
            if let budget = resolvedBudgetTarget(in: resolved, candidate: candidate, provider: provider, now: now),
               let detail = (candidate.routeIntent?.requestedDetail ?? plan.routeIntent?.requestedDetail ?? candidate.semanticCommand?.requestedDetail),
               isBudgetRelationshipDetail(detail) {
                return .handled(budgetRelationshipResponse(budget: budget, detail: detail, resolved: resolved, plan: plan, provider: provider))
            }
        case .activeBudget?:
            return .handled(activeBudgetStatus(provider: provider, now: now))
        case .budgetLinkedCards?, .budgetLinkedPresets?, .budgetCategoryLimits?:
            if let budget = resolvedBudgetTarget(in: resolved, candidate: candidate, provider: provider, now: now),
               let detail = (candidate.routeIntent?.requestedDetail ?? plan.routeIntent?.requestedDetail ?? candidate.semanticCommand?.requestedDetail),
               isBudgetRelationshipDetail(detail) {
                return .handled(budgetRelationshipResponse(budget: budget, detail: detail, resolved: resolved, plan: plan, provider: provider))
            }
        case .budgetCategoryLimit?:
            if let categoryTarget = resolved.resolvedTargets.first(where: { $0.entityType == .category }) {
                return .handled(categoryAvailability(target: categoryTarget, plan: plan, provider: provider, now: now))
            }
        case .recentTransactionRows?:
            return .handled(recentFilteredTransactions(resolved: resolved, plan: plan, provider: provider, now: now, amountBasis: amountBasis))
        case .currentWorkspace?, .databaseLookup?, .periodOverview?, .generic?, .broadSpend?, .plannedExpenseRows?, .presetTemplateRows?, .plannedExpenseByCategory?, .plannedExpenseByCard?, .plannedExpenseByPreset?, .savingsStatus?, .savingsActivity?, .savingsMovementRanking?, .incomePlannedVsActual?, .reconciliationBalance?, nil:
            break
        }

        // Compatibility only: covered Marina read routes should arrive with routeIntent.kind.
        // Tests run Step 5 routes with this disabled so prompt text cannot choose the route.
        if allowsPromptRouteFallback,
           let fallbackKind = MarinaRoutePatternRegistry.fallbackComposableKind(
               rawPrompt: candidate.rawPrompt,
               operation: plan.operation,
               measure: plan.measure,
               grouping: plan.grouping?.dimension
           ) {
            switch fallbackKind {
            case .budgetInventory:
                return .handled(budgetsOverlappingRange(prompt: candidate.rawPrompt, plan: plan, provider: provider, now: now))
            case .overBudgetCategories:
                return .handled(overBudgetCategories(plan: plan, provider: provider, now: now, amountBasis: amountBasis))
            case .allocationRows:
                return .handled(allocationRows(resolved: resolved, plan: plan, provider: provider, now: now))
            case .settlementRows:
                return .handled(settlementRows(resolved: resolved, plan: plan, provider: provider, now: now))
            case .recentTransactionRows:
                return .handled(recentFilteredTransactions(resolved: resolved, plan: plan, provider: provider, now: now, amountBasis: amountBasis))
            case .generic, .databaseLookup, .currentWorkspace, .periodOverview, .budgetSummary, .activeBudget, .budgetMembership, .budgetLinkedCards, .budgetLinkedPresets, .budgetCategoryLimits, .budgetCategoryLimit, .plannedExpenseRows, .presetTemplateRows, .plannedExpenseByCategory, .plannedExpenseByCard, .plannedExpenseByPreset, .savingsStatus, .savingsActivity, .savingsMovementRanking, .incomePlannedVsActual, .reconciliationBalance, .broadSpend:
                break
            }
        }

        if let budget = resolvedBudgetTarget(in: resolved, candidate: candidate, provider: provider, now: now),
           let detail = candidate.semanticCommand?.requestedDetail,
           isBudgetRelationshipDetail(detail) {
            return .handled(budgetRelationshipResponse(budget: budget, detail: detail, resolved: resolved, plan: plan, provider: provider))
        }

        if let budget = resolvedBudgetTarget(in: resolved, candidate: candidate, provider: provider, now: now),
           plan.measure == .spend {
            return .handled(budgetLinkedSummary(budget: budget, plan: plan, provider: provider))
        }

        if hasAllocationAccountTarget(plan), plan.measure != .reconciliationBalance {
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
            guard hasFilterTargets(resolved: resolved, plan: plan) else { return .unsupported }
            return .handled(filteredSpend(candidate: candidate, resolved: resolved, plan: plan, provider: provider, now: now, amountBasis: amountBasis))
        case (.rank, .spend, nil), (.rank, .spend, .transaction):
            guard candidate.measure == .transactionAmount || candidate.grouping?.dimension == .transaction,
                  plan.ranking?.direction == .largest || candidate.ranking?.direction == .largest else {
                return .unsupported
            }
            return .handled(recentFilteredTransactions(resolved: resolved, plan: plan, provider: provider, now: now, amountBasis: amountBasis))
        case (.rank, .transactionAmount, .transaction), (.listRows, .transactionAmount, .transaction):
            guard plan.operation == .listRows
                    || plan.ranking?.direction == .newest
                    || plan.ranking?.direction == .largest else {
                return .unsupported
            }
            return .handled(recentFilteredTransactions(resolved: resolved, plan: plan, provider: provider, now: now, amountBasis: amountBasis))
        case (.average, .spend, nil), (.average, .spend, .week), (.average, .spend, .month):
            guard plan.targets.isEmpty || hasFilterTargets(resolved: resolved, plan: plan) else { return .unsupported }
            return .handled(targetedPeriodicAverage(resolved: resolved, plan: plan, provider: provider, now: now, amountBasis: amountBasis))
        case (.compare, .spend, .category), (.compare, .spend, .transaction):
            guard plan.ranking != nil else { return .unsupported }
            return .handled(categoryDeltaDrivers(plan: plan, provider: provider, now: now, amountBasis: amountBasis))
        default:
            return .unsupported
        }
    }

    // MARK: - Budgets

    private func activeBudgetStatus(
        provider: MarinaDataProvider,
        now: Date
    ) -> MarinaWorkspaceAggregationCard {
        let matches = activeBudgets(provider: provider, now: now)

        guard matches.isEmpty == false else {
            return MarinaWorkspaceAggregationCard(
                title: "No Active Budget",
                subtitle: "No budget includes today.",
                primaryValue: "None",
                rows: [
                    .init(label: "Status", value: "No active budget includes today.")
                ],
                traceSummary: "composableWorkspace=activeBudgetStatus,result=none"
            )
        }

        guard matches.count == 1, let budget = matches.first else {
            let rows = matches.map { budget in
                MarinaWorkspaceAggregationCard.Row(
                    label: budget.name,
                    value: activeBudgetValue(budget),
                    date: budget.startDate,
                    objectType: .budget,
                    sourceID: budget.id,
                    sortValue: budget.startDate.timeIntervalSince1970
                )
            }
            return MarinaWorkspaceAggregationCard(
                title: "Multiple Active Budgets",
                subtitle: "Choose the budget Marina should use.",
                primaryValue: "\(matches.count)",
                rows: rows,
                traceSummary: "composableWorkspace=activeBudgetStatus,result=ambiguous,count=\(matches.count)"
            )
        }

        let range = HomeQueryDateRange(startDate: budget.startDate, endDate: budget.endDate)
        let linkedCards = (budget.cardLinks ?? []).compactMap { $0.card?.name }.sorted()
        let linkedPresets = (budget.presetLinks ?? []).compactMap { $0.preset?.title }.sorted()
        let categoryLimitCount = budget.categoryLimits?.count ?? 0
        return MarinaWorkspaceAggregationCard(
            title: "Active Budget",
            subtitle: rangeLabel(range),
            primaryValue: budget.name,
            rows: [
                .init(label: "Budget", value: budget.name, objectType: .budget, sourceID: budget.id),
                .init(label: "Period", value: rangeLabel(range), date: budget.startDate),
                .init(label: "Linked cards", value: linkedCards.isEmpty ? "None" : linkedCards.joined(separator: ", ")),
                .init(label: "Linked presets", value: linkedPresets.isEmpty ? "None" : linkedPresets.joined(separator: ", ")),
                .init(label: "Category limits", value: "\(categoryLimitCount)")
            ],
            traceSummary: "composableWorkspace=activeBudgetStatus,result=single,budgetID=\(budget.id.uuidString),budgetName=\(budget.name)"
        )
    }

    private func activeBudgetValue(_ budget: Budget) -> String {
        let linkedCardCount = budget.cardLinks?.count ?? 0
        let linkedPresetCount = budget.presetLinks?.count ?? 0
        return "\(rangeLabel(HomeQueryDateRange(startDate: budget.startDate, endDate: budget.endDate))) • \(linkedCardCount) card\(linkedCardCount == 1 ? "" : "s") • \(linkedPresetCount) preset\(linkedPresetCount == 1 ? "" : "s")"
    }

    private func activeBudgets(
        provider: MarinaDataProvider,
        now: Date
    ) -> [Budget] {
        let day = calendar.startOfDay(for: now)
        var seenBudgetIDs = Set<UUID>()
        var seenBudgetKeys = Set<String>()
        return provider.fetchAllBudgets()
            .filter { budget in
                budget.workspace?.id == provider.workspaceID
            }
            .filter { budget in
                seenBudgetIDs.insert(budget.id).inserted
            }
            .filter { budget in
                let key = [
                    normalized(budget.name),
                    "\(calendar.startOfDay(for: budget.startDate).timeIntervalSince1970)",
                    "\(calendar.startOfDay(for: budget.endDate).timeIntervalSince1970)"
                ].joined(separator: "|")
                return seenBudgetKeys.insert(key).inserted
            }
            .filter { budget in
                calendar.startOfDay(for: budget.startDate) <= day
                    && calendar.startOfDay(for: budget.endDate) >= day
            }
            .sorted { lhs, rhs in
                if lhs.startDate != rhs.startDate {
                    return lhs.startDate < rhs.startDate
                }
                if lhs.endDate != rhs.endDate {
                    return lhs.endDate < rhs.endDate
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func budgetsOverlappingRange(
        prompt: String,
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date
    ) -> MarinaWorkspaceAggregationCard {
        let range = plan.dateRange ?? monthRange(containing: now)
        let inventoryMode = budgetInventoryMode(prompt: prompt, plan: plan)
        let rows = provider.fetchAllBudgets()
            .filter { budget in
                switch inventoryMode {
                case .upcoming:
                    return budget.endDate >= calendar.startOfDay(for: now)
                case .all:
                    return true
                case .overlappingRange:
                    return budget.startDate <= range.endDate && budget.endDate >= range.startDate
                }
            }
            .sorted { lhs, rhs in
                if inventoryMode == .upcoming {
                    let lhsActive = lhs.startDate <= now && lhs.endDate >= now
                    let rhsActive = rhs.startDate <= now && rhs.endDate >= now
                    if lhsActive != rhsActive { return lhsActive }
                }
                if lhs.startDate == rhs.startDate { return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending }
                return lhs.startDate < rhs.startDate
            }
            .prefix(limit(for: plan))
            .map { budget in
                MarinaWorkspaceAggregationCard.Row(
                    label: budget.name,
                    value: "\(shortDate(budget.startDate))-\(shortDate(budget.endDate))",
                    date: budget.startDate,
                    objectType: .budget,
                    sourceID: budget.id,
                    sortValue: budget.startDate.timeIntervalSince1970
                )
            }

        return MarinaWorkspaceAggregationCard(
            title: inventoryMode == .upcoming ? "Upcoming Budgets" : "Budgets",
            subtitle: budgetInventorySubtitle(mode: inventoryMode, range: range),
            primaryValue: rows.first?.label,
            rows: Array(rows),
            traceSummary: "composableWorkspace=budgetInventory;route=budgetsOverlappingRange,resultCount=\(rows.count)"
        )
    }

    private enum BudgetInventoryMode: Equatable {
        case overlappingRange
        case upcoming
        case all
    }

    private func budgetInventoryMode(prompt: String, plan: MarinaAggregationPlan) -> BudgetInventoryMode {
        let normalizedPrompt = normalized(prompt)
        if normalizedPrompt.contains("upcoming") || normalizedPrompt.contains("future") {
            return .upcoming
        }
        if plan.dateRange == nil,
           normalizedPrompt.contains("all budgets")
            || normalizedPrompt == "list budgets"
            || normalizedPrompt == "show budgets"
            || normalizedPrompt == "show my budgets" {
            return .all
        }
        return .overlappingRange
    }

    private func budgetInventorySubtitle(mode: BudgetInventoryMode, range: HomeQueryDateRange) -> String {
        switch mode {
        case .upcoming:
            return "Active and future budgets"
        case .all:
            return "All budgets"
        case .overlappingRange:
            return rangeLabel(range)
        }
    }

    private func budgetLinkedSummary(
        budget: Budget,
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider
    ) -> MarinaWorkspaceAggregationCard {
        let range = HomeQueryDateRange(startDate: budget.startDate, endDate: budget.endDate)
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

    private func overBudgetCategories(
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date,
        amountBasis: MarinaFinancialAmountBasis
    ) -> MarinaWorkspaceAggregationCard {
        let range = plan.dateRange ?? monthRange(containing: now)
        let budget = activeBudget(provider: provider, now: now, range: range)
        let rows = spendingRows(provider: provider, range: range, amountBasis: amountBasis)
        let spendByCategory = groupedTotals(rows, by: \.categoryName)
        let limitRows = (budget?.categoryLimits ?? [])
            .compactMap { limit -> MarinaWorkspaceAggregationCard.Row? in
                guard let category = limit.category,
                      let maxAmount = limit.maxAmount else {
                    return nil
                }
                let spend = spendByCategory[category.name, default: 0]
                let over = spend - maxAmount
                guard over > 0 else { return nil }
                return MarinaWorkspaceAggregationCard.Row(
                    label: category.name,
                    value: "\(currency(spend)) spent • \(currency(over)) over \(currency(maxAmount))",
                    amount: over,
                    objectType: .category,
                    sourceID: category.id,
                    sortValue: over
                )
            }
            .sorted { ($0.sortValue ?? 0) > ($1.sortValue ?? 0) }
            .prefix(limit(for: plan))

        return MarinaWorkspaceAggregationCard(
            title: "Categories Over Budget",
            subtitle: budget.map { "\($0.name) • \(rangeLabel(range))" } ?? rangeLabel(range),
            primaryValue: limitRows.first?.value,
            rows: Array(limitRows),
            traceSummary: "composableWorkspace=overBudgetCategories,resultCount=\(limitRows.count)"
        )
    }

    private func budgetRelationshipResponse(
        budget: Budget,
        detail: MarinaSemanticRequestedDetail,
        resolved: MarinaResolvedQueryCandidate,
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider
    ) -> MarinaWorkspaceAggregationCard {
        switch detail {
        case .linkedCards:
            return budgetLinkedCards(budget: budget)
        case .linkedPresets:
            return budgetLinkedPresets(budget: budget)
        case .categoryLimits:
            return budgetCategoryLimits(budget: budget)
        case .membership:
            return budgetMembership(budget: budget, resolved: resolved)
        case .linkedObjects, .status:
            return budgetLinkedSummary(budget: budget, plan: plan, provider: provider)
        default:
            return budgetLinkedSummary(budget: budget, plan: plan, provider: provider)
        }
    }

    private func budgetLinkedCards(budget: Budget) -> MarinaWorkspaceAggregationCard {
        let rows = (budget.cardLinks ?? [])
            .compactMap(\.card)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map {
                MarinaWorkspaceAggregationCard.Row(
                    label: $0.name,
                    value: "Linked card",
                    objectType: .card,
                    sourceID: $0.id
                )
            }

        return MarinaWorkspaceAggregationCard(
            title: "Cards linked to \(budget.name)",
            subtitle: rows.isEmpty ? "No cards are linked to this budget." : "\(rows.count) linked card\(rows.count == 1 ? "" : "s")",
            primaryValue: rows.isEmpty ? "None" : "\(rows.count)",
            rows: rows,
            traceSummary: "composableWorkspace=budgetLinkedCards,linkedCards=\(rows.count)"
        )
    }

    private func budgetLinkedPresets(budget: Budget) -> MarinaWorkspaceAggregationCard {
        let rows = (budget.presetLinks ?? [])
            .compactMap(\.preset)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map {
                MarinaWorkspaceAggregationCard.Row(
                    label: $0.title,
                    value: currency($0.plannedAmount),
                    amount: $0.plannedAmount,
                    objectType: .preset,
                    sourceID: $0.id,
                    sortValue: $0.plannedAmount
                )
            }

        return MarinaWorkspaceAggregationCard(
            title: "Presets linked to \(budget.name)",
            subtitle: rows.isEmpty ? "No presets are linked to this budget." : "\(rows.count) linked preset\(rows.count == 1 ? "" : "s")",
            primaryValue: rows.isEmpty ? "None" : "\(rows.count)",
            rows: rows,
            traceSummary: "composableWorkspace=budgetLinkedPresets,linkedPresets=\(rows.count)"
        )
    }

    private func budgetCategoryLimits(budget: Budget) -> MarinaWorkspaceAggregationCard {
        let rows = (budget.categoryLimits ?? [])
            .compactMap { limit -> MarinaWorkspaceAggregationCard.Row? in
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
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }

        return MarinaWorkspaceAggregationCard(
            title: "Category limits for \(budget.name)",
            subtitle: rows.isEmpty ? "No category limits are set for this budget." : "\(rows.count) category limit\(rows.count == 1 ? "" : "s")",
            primaryValue: rows.isEmpty ? "None" : "\(rows.count)",
            rows: rows,
            traceSummary: "composableWorkspace=budgetCategoryLimits,categoryLimits=\(rows.count)"
        )
    }

    private func budgetMembership(
        budget: Budget,
        resolved: MarinaResolvedQueryCandidate
    ) -> MarinaWorkspaceAggregationCard {
        guard let member = resolved.resolvedTargets.first(where: { $0.entityType == .card || $0.entityType == .preset }) else {
            return MarinaWorkspaceAggregationCard(
                title: "I need one linked item",
                subtitle: "Pick a card or preset and I can check whether it belongs to this budget.",
                rows: [
                    .init(label: "Budget", value: budget.name)
                ],
                traceSummary: "composableWorkspace=budgetMembershipCheck,missingMember=true"
            )
        }

        let included: Bool
        let noun: String
        switch member.entityType {
        case .card:
            noun = "card"
            included = (budget.cardLinks ?? []).contains { link in
                link.card?.id == member.sourceID || normalized(link.card?.name ?? "") == normalized(member.displayName)
            }
        case .preset:
            noun = "preset"
            included = (budget.presetLinks ?? []).contains { link in
                link.preset?.id == member.sourceID || normalized(link.preset?.title ?? "") == normalized(member.displayName)
            }
        default:
            noun = "item"
            included = false
        }

        return MarinaWorkspaceAggregationCard(
            title: included ? "Yes, \(member.displayName) is linked" : "No, \(member.displayName) is not linked",
            subtitle: "\(budget.name) budget",
            primaryValue: included ? "Included" : "Not included",
            rows: [
                .init(label: "Budget", value: budget.name, objectType: .budget, sourceID: budget.id),
                .init(label: noun.capitalized, value: member.displayName, objectType: lookupObjectType(from: member.entityType), sourceID: member.sourceID)
            ],
            traceSummary: "composableWorkspace=budgetMembershipCheck,memberType=\(member.entityType.rawValue),included=\(included)"
        )
    }

    private func budgetsUsingMember(
        _ member: MarinaResolvedEntityMention,
        provider: MarinaDataProvider
    ) -> MarinaWorkspaceAggregationCard {
        let matchingBudgets = provider.fetchAllBudgets()
            .filter { budget in
                switch member.entityType {
                case .card:
                    return (budget.cardLinks ?? []).contains { link in
                        link.card?.id == member.sourceID || normalized(link.card?.name ?? "") == normalized(member.displayName)
                    }
                case .preset:
                    return (budget.presetLinks ?? []).contains { link in
                        link.preset?.id == member.sourceID || normalized(link.preset?.title ?? "") == normalized(member.displayName)
                    }
                default:
                    return false
                }
            }
            .sorted { $0.startDate < $1.startDate }

        let rows = matchingBudgets.map { budget in
            MarinaWorkspaceAggregationCard.Row(
                label: budget.name,
                value: rangeLabel(HomeQueryDateRange(startDate: budget.startDate, endDate: budget.endDate)),
                objectType: .budget,
                sourceID: budget.id
            )
        }

        return MarinaWorkspaceAggregationCard(
            title: "Budgets using \(member.displayName)",
            subtitle: rows.isEmpty ? "No budgets are linked to this \(member.entityType == .card ? "card" : "preset")." : "\(rows.count) budget\(rows.count == 1 ? "" : "s")",
            primaryValue: rows.isEmpty ? "None" : "\(rows.count)",
            rows: rows,
            traceSummary: "composableWorkspace=budgetMembershipList,memberType=\(member.entityType.rawValue),budgetCount=\(rows.count)"
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
        let targets = filterTargets(resolved: resolved, plan: plan)
        let explicitExcludeFilters = targets.filter { $0.role == .excludeFilter }
        let includeFilters = targets.filter {
            $0.role != .excludeFilter && excludedNames.contains(normalized($0.displayName)) == false
        }
        let excludeFilters = explicitExcludeFilters.isEmpty
            ? targets.filter { excludedNames.contains(normalized($0.displayName)) }
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
        let filters = filterTargets(resolved: resolved, plan: plan).filter { $0.role != .excludeFilter }
        let filteredRows = spendingRows(provider: provider, range: range, amountBasis: amountBasis)
            .filter { row in filters.isEmpty || filters.allSatisfy { matches(row: row, target: $0) } }
        let rows = plan.ranking?.direction == .largest
            ? filteredRows.sorted { $0.amount > $1.amount }
            : filteredRows.sorted { $0.date > $1.date }
        let shown = Array(rows.prefix(limit(for: plan)))
        let total = shown.reduce(0.0) { $0 + $1.amount }

        return MarinaWorkspaceAggregationCard(
            title: plan.ranking?.direction == .largest ? "Largest Purchases" : "Recent Purchases",
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

    private func allocationRows(
        resolved: MarinaResolvedQueryCandidate,
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date
    ) -> MarinaWorkspaceAggregationCard {
        let range = plan.dateRange ?? monthRange(containing: now)
        let accountFilters = resolved.resolvedTargets.filter { $0.entityType == .allocationAccount }
        let otherFilters = resolved.resolvedTargets.filter { $0.entityType != .allocationAccount }
        let rows = provider.fetchAllExpenseAllocations()
            .filter { allocation in
                accountFilters.isEmpty
                    || accountFilters.contains { $0.sourceID == allocation.account?.id || $0.displayName.localizedCaseInsensitiveCompare(allocation.account?.name ?? "") == .orderedSame }
            }
            .compactMap { allocation -> MarinaWorkspaceAggregationCard.Row? in
                let spendingRow: SpendingRow?
                if let expense = allocation.expense {
                    spendingRow = row(for: expense, amount: max(0, allocation.allocatedAmount))
                } else if let expense = allocation.plannedExpense {
                    spendingRow = row(for: expense, amount: max(0, allocation.allocatedAmount))
                } else {
                    spendingRow = nil
                }
                if let spendingRow {
                    guard contains(spendingRow.date, in: range) else { return nil }
                    guard otherFilters.isEmpty || otherFilters.allSatisfy({ matches(row: spendingRow, target: $0) }) else {
                        return nil
                    }
                    let accountName = allocation.account?.name ?? "Reconciliation"
                    return MarinaWorkspaceAggregationCard.Row(
                        label: spendingRow.title,
                        value: "\(currency(spendingRow.amount)) • \(accountName) • \(shortDate(spendingRow.date))",
                        amount: spendingRow.amount,
                        date: spendingRow.date,
                        objectType: .expenseAllocation,
                        sourceID: allocation.id,
                        sortValue: spendingRow.date.timeIntervalSince1970
                    )
                }

                guard otherFilters.isEmpty else { return nil }
                let linkedDate = allocation.expense?.transactionDate ?? allocation.plannedExpense?.expenseDate ?? allocation.createdAt
                guard contains(linkedDate, in: range) else { return nil }
                let title = allocation.expense?.descriptionText ?? allocation.plannedExpense?.title ?? "Allocation"
                let accountName = allocation.account?.name ?? "Reconciliation"
                return MarinaWorkspaceAggregationCard.Row(
                    label: title,
                    value: "\(currency(allocation.allocatedAmount)) • \(accountName) • \(shortDate(linkedDate))",
                    amount: allocation.allocatedAmount,
                    date: linkedDate,
                    objectType: .expenseAllocation,
                    sourceID: allocation.id,
                    sortValue: linkedDate.timeIntervalSince1970
                )
            }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            .prefix(limit(for: plan))

        return MarinaWorkspaceAggregationCard(
            title: "Allocations",
            subtitle: rangeLabel(range),
            primaryValue: rows.first?.value,
            rows: Array(rows),
            traceSummary: "composableWorkspace=allocationRows,resultCount=\(rows.count)"
        )
    }

    private func settlementRows(
        resolved: MarinaResolvedQueryCandidate,
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date
    ) -> MarinaWorkspaceAggregationCard {
        let range = plan.dateRange ?? monthRange(containing: now)
        let accountFilters = resolved.resolvedTargets.filter { $0.entityType == .allocationAccount }
        let rows = provider.fetchAllAllocationSettlements()
            .filter { settlement in
                contains(settlement.date, in: range)
                    && (accountFilters.isEmpty
                        || accountFilters.contains { $0.sourceID == settlement.account?.id || $0.displayName.localizedCaseInsensitiveCompare(settlement.account?.name ?? "") == .orderedSame })
            }
            .sorted { lhs, rhs in
                if lhs.date == rhs.date { return lhs.note.localizedCaseInsensitiveCompare(rhs.note) == .orderedAscending }
                return lhs.date > rhs.date
            }
            .prefix(limit(for: plan))
            .map { settlement in
                MarinaWorkspaceAggregationCard.Row(
                    label: settlement.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Settlement" : settlement.note,
                    value: "\(currency(settlement.amount)) • \(settlement.account?.name ?? "Reconciliation") • \(shortDate(settlement.date))",
                    amount: settlement.amount,
                    date: settlement.date,
                    objectType: .reconciliationItem,
                    sourceID: settlement.id,
                    sortValue: settlement.date.timeIntervalSince1970
                )
            }

        return MarinaWorkspaceAggregationCard(
            title: "Settlements",
            subtitle: rangeLabel(range),
            primaryValue: rows.first?.value,
            rows: Array(rows),
            traceSummary: "composableWorkspace=settlementRows,resultCount=\(rows.count)"
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
        guard let card = MarinaBudgetForecastScenarioSimulator(
            calendar: calendar,
            amountBasisAdapter: amountBasisAdapter
        ).simulate(
            candidate: candidate,
            resolved: resolved,
            plan: plan,
            provider: provider,
            now: now
        ) else {
            return .unsupported
        }
        return .handled(card)
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

    private func hasFilterTargets(
        resolved: MarinaResolvedQueryCandidate,
        plan: MarinaAggregationPlan
    ) -> Bool {
        filterTargets(resolved: resolved, plan: plan).isEmpty == false
    }

    private func filterTargets(
        resolved: MarinaResolvedQueryCandidate,
        plan: MarinaAggregationPlan
    ) -> [MarinaResolvedEntityMention] {
        if plan.targets.isEmpty == false {
            return plan.targets.map(resolvedMention)
        }
        return resolved.resolvedTargets
    }

    private func resolvedMention(from target: MarinaResolvedAggregationTarget) -> MarinaResolvedEntityMention {
        MarinaResolvedEntityMention(
            id: target.id,
            mention: MarinaUnresolvedEntityMention(
                id: target.id,
                role: mentionRole(from: target.role),
                rawText: target.displayName,
                typeHint: target.entityType,
                allowedTypeHints: [target.entityType],
                confidence: .high
            ),
            role: target.role,
            entityType: target.entityType,
            displayName: target.displayName,
            sourceID: target.sourceID
        )
    }

    private func mentionRole(from role: MarinaResolvedTargetRole) -> MarinaEntityMentionRole {
        switch role {
        case .filter:
            return .filter
        case .excludeFilter:
            return .excludeFilter
        case .primaryTarget:
            return .primaryTarget
        case .comparisonTarget:
            return .comparisonTarget
        case .groupingDimension:
            return .groupingDimension
        case .simulationInput:
            return .simulationInput
        case .simulationOutput:
            return .simulationOutput
        }
    }

    // MARK: - Helpers

    private func hasAllocationAccountTarget(_ plan: MarinaAggregationPlan) -> Bool {
        plan.targets.contains { $0.entityType == .allocationAccount }
    }

    private func asksForBudgetMembershipList(_ prompt: String) -> Bool {
        let prompt = normalized(prompt)
        guard prompt.contains("budget") else { return false }
        return prompt.contains("which budget")
            || prompt.contains("which budgets")
            || prompt.contains("what budget")
            || prompt.contains("what budgets")
            || prompt.contains("budgets use")
            || prompt.contains("budgets include")
            || prompt.contains("budgets linked")
    }

    private func budgetMemberTarget(in resolved: MarinaResolvedQueryCandidate) -> MarinaResolvedEntityMention? {
        resolved.resolvedTargets.first { target in
            target.entityType == .card || target.entityType == .preset
        }
    }

    private func resolvedBudgetTarget(
        in resolved: MarinaResolvedQueryCandidate,
        candidate: MarinaQueryPlanCandidate,
        provider: MarinaDataProvider,
        now: Date
    ) -> Budget? {
        if let target = resolved.resolvedTargets.first(where: { $0.entityType == .budget }) {
            return provider.fetchAllBudgets().first { budget in
                budget.id == target.sourceID || normalized(budget.name) == normalized(target.displayName)
            }
        }

        guard candidate.semanticCommand?.requestedDetail.map(isBudgetRelationshipDetail) == true else {
            return nil
        }

        let range = monthRange(containing: now)
        return activeBudget(provider: provider, now: now, range: range)
    }

    private func isBudgetRelationshipDetail(_ detail: MarinaSemanticRequestedDetail) -> Bool {
        switch detail {
        case .linkedObjects, .linkedCards, .linkedPresets, .categoryLimits, .membership, .status:
            return true
        default:
            return false
        }
    }

    private func lookupObjectType(from entityType: MarinaCandidateEntityTypeHint) -> MarinaLookupObjectType? {
        switch entityType {
        case .card:
            return .card
        case .preset:
            return .preset
        case .budget:
            return .budget
        case .category:
            return .category
        default:
            return nil
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
