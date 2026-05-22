import Foundation

enum MarinaMetricFormulaExecutionResult {
    case handled(MarinaWorkspaceAggregationCard, amountBasis: MarinaFinancialAmountBasis, route: MarinaSemanticExecutionRoute)
    case blocked(HomeAnswer, MarinaTypedUnsupportedResponse)
    case notHandled
}

@MainActor
struct MarinaMetricFormulaExecutor {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func execute(
        contract: MarinaMetricContract,
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        semanticResolved: MarinaResolvedSemanticQuery?,
        context: MarinaTurnContext
    ) -> MarinaMetricFormulaExecutionResult {
        switch contract.id {
        case .safeSpendRemaining:
            return safeSpendRemaining(contract: contract, candidate: candidate, context: context)
        case .spendingIncreaseDrivers:
            return spendingIncreaseDrivers(contract: contract, context: context)
        case .categoryOverPace:
            return categoryOverPace(contract: contract, context: context)
        case .upcomingExpensesBeforeNextIncome:
            return upcomingExpensesBeforeNextIncome(contract: contract, candidate: candidate, context: context)
        case .plannedVsActualSpend:
            return plannedVsActualSpend(contract: contract, context: context)
        case .unrecordedPlannedExpenses:
            return unrecordedPlannedExpenses(contract: contract, context: context)
        case .unusualMerchantSpend:
            return unusualMerchantSpend(contract: contract, context: context)
        case .subscriptionSpend:
            return subscriptionSpend(contract: contract, candidate: candidate, context: context)
        case .reconciliationOwedThisMonth:
            return reconciliationOwedThisMonth(contract: contract, candidate: candidate, resolved: resolved, semanticResolved: semanticResolved, context: context)
        case .trueOwnedSpend:
            return trueOwnedSpend(contract: contract, context: context)
        case .cardOverspendingDriver:
            return cardOverspendingDriver(contract: contract, candidate: candidate, context: context)
        case .categoryCutImpact:
            return categoryCutImpact(contract: contract, candidate: candidate, context: context)
        case .skipCategoryScenario:
            return skipCategoryScenario(contract: contract, candidate: candidate, resolved: resolved, semanticResolved: semanticResolved, context: context)
        case .savingsTrackVsLastMonth:
            return savingsTrackVsLastMonth(contract: contract, context: context)
        case .incomeBySource:
            return incomeBySource(contract: contract, context: context)
        case .budgetSharedLinks:
            return budgetSharedLinks(contract: contract, context: context)
        case .categorizationReview:
            return categorizationReview(contract: contract, context: context)
        case .sinceLastCheckIn:
            return sinceLastCheckIn(contract: contract, candidate: candidate, context: context)
        case .allocatedCategorySpend, .recurringExpenseIncrease, .incomeActualVsExpected:
            return .notHandled
        default:
            return .notHandled
        }
    }

    // MARK: - Batch 1

    private func safeSpendRemaining(
        contract: MarinaMetricContract,
        candidate: MarinaQueryPlanCandidate,
        context: MarinaTurnContext
    ) -> MarinaMetricFormulaExecutionResult {
        guard let workspace = context.provider.fetchWorkspace() else {
            return setupRequired(contract: contract, candidate: candidate, message: "Marina needs the selected workspace before it can calculate safe spend.")
        }
        let summary = SafeSpendTodayCalculator.calculate(
            workspace: workspace,
            budgetingPeriod: .monthly,
            now: context.now,
            calendar: calendar
        )
        let card = MarinaWorkspaceAggregationCard(
            title: "Safe Spend Remaining",
            subtitle: rangeLabel(summary.rangeStart, summary.rangeEnd),
            primaryValue: currency(summary.periodRemainingRoom),
            rows: [
                row("Rest of month", "\(shortDate(summary.rangeStart))-\(shortDate(summary.rangeEnd))"),
                row("Days left", "\(summary.daysLeftInPeriod)"),
                row("Per-day reference", currency(summary.safeToSpendToday)),
                row("Formula", "income received + expected income - owned expenses - remaining planned expenses + savings adjustments")
            ],
            traceSummary: "metricFormula=\(contract.id.rawValue),remaining=\(summary.periodRemainingRoom)"
        )
        return .handled(card, amountBasis: .budgetImpact, route: .aggregate)
    }

    private func plannedVsActualSpend(
        contract: MarinaMetricContract,
        context: MarinaTurnContext
    ) -> MarinaMetricFormulaExecutionResult {
        let range = currentMonthRange(containing: context.now)
        let plannedRows = context.provider.fetchAllPlannedExpenses().filter { contains($0.expenseDate, in: range) }
        let variableRows = context.provider.fetchAllVariableExpenses().filter { contains($0.transactionDate, in: range) }
        let plannedTotal = plannedRows.reduce(0.0) { $0 + SavingsMathService.plannedProjectedBudgetImpactAmount(for: $1) }
        let recordedPlannedActual = plannedRows
            .filter { $0.actualAmount > 0 }
            .reduce(0.0) { $0 + SavingsMathService.plannedBudgetImpactAmount(for: $1) }
        let variableActual = variableRows.reduce(0.0) { $0 + SavingsMathService.variableBudgetImpactAmount(for: $1) }
        let actualTotal = recordedPlannedActual + variableActual
        let gap = actualTotal - plannedTotal
        let card = MarinaWorkspaceAggregationCard(
            title: "Planned vs Actual Spend",
            subtitle: rangeLabel(range),
            primaryValue: delta(gap),
            rows: [
                row("Planned spend", currency(plannedTotal), amount: plannedTotal),
                row("Recorded planned actual", currency(recordedPlannedActual), amount: recordedPlannedActual),
                row("Variable actual spend", currency(variableActual), amount: variableActual),
                row("Actual spend total", currency(actualTotal), amount: actualTotal),
                row("Gap", delta(gap), amount: gap)
            ],
            traceSummary: "metricFormula=\(contract.id.rawValue),planned=\(plannedTotal),actual=\(actualTotal)"
        )
        return .handled(card, amountBasis: .budgetImpact, route: .comparison)
    }

    private func unrecordedPlannedExpenses(
        contract: MarinaMetricContract,
        context: MarinaTurnContext
    ) -> MarinaMetricFormulaExecutionResult {
        let range = currentMonthRange(containing: context.now)
        let rows = context.provider.fetchAllPlannedExpenses()
            .filter { contains($0.expenseDate, in: range) && $0.actualAmount <= 0 }
            .sorted { $0.expenseDate < $1.expenseDate }
            .map { expense in
                row(
                    expense.title,
                    "\(currency(expense.plannedAmount)) planned on \(shortDate(expense.expenseDate))",
                    amount: expense.plannedAmount,
                    date: expense.expenseDate,
                    objectType: .plannedExpense,
                    sourceID: expense.id
                )
            }
        let card = MarinaWorkspaceAggregationCard(
            title: "Unrecorded Planned Expenses",
            subtitle: rangeLabel(range),
            primaryValue: rows.isEmpty ? "None" : "\(rows.count)",
            rows: rows,
            traceSummary: "metricFormula=\(contract.id.rawValue),rows=\(rows.count)"
        )
        return .handled(card, amountBasis: .budgetImpact, route: .list)
    }

    private func trueOwnedSpend(
        contract: MarinaMetricContract,
        context: MarinaTurnContext
    ) -> MarinaMetricFormulaExecutionResult {
        let range = currentMonthRange(containing: context.now)
        let variable = context.provider.fetchAllVariableExpenses().filter { contains($0.transactionDate, in: range) }
        let planned = context.provider.fetchAllPlannedExpenses().filter { contains($0.expenseDate, in: range) }
        let variableOwned = variable.reduce(0.0) { $0 + SavingsMathService.variableBudgetImpactAmount(for: $1) }
        let plannedOwned = planned.reduce(0.0) { $0 + SavingsMathService.plannedBudgetImpactAmount(for: $1) }
        let gross = variable.reduce(0.0) { $0 + SavingsMathService.variableGrossAmount(for: $1) }
            + planned.reduce(0.0) { $0 + SavingsMathService.grossEffectiveAmount(for: $1) }
        let ledger = variable.reduce(0.0) { $0 + $1.ledgerSignedAmount() }
            + planned.reduce(0.0) { $0 + $1.effectiveAmount() }
        let total = variableOwned + plannedOwned
        let card = MarinaWorkspaceAggregationCard(
            title: "True Owned Spend",
            subtitle: rangeLabel(range),
            primaryValue: currency(total),
            rows: [
                row("Variable owned spend", currency(variableOwned), amount: variableOwned),
                row("Planned owned spend", currency(plannedOwned), amount: plannedOwned),
                row("Gross comparison", currency(gross), amount: gross),
                row("Ledger comparison", currency(ledger), amount: ledger)
            ],
            traceSummary: "metricFormula=\(contract.id.rawValue),owned=\(total),gross=\(gross),ledger=\(ledger)"
        )
        return .handled(card, amountBasis: .budgetImpact, route: .aggregate)
    }

    // MARK: - Batch 2

    private func spendingIncreaseDrivers(
        contract: MarinaMetricContract,
        context: MarinaTurnContext
    ) -> MarinaMetricFormulaExecutionResult {
        let ranges = currentAndPreviousMatchingMonthRanges(now: context.now)
        let current = spendByCategory(range: ranges.current, provider: context.provider, includeUnrecordedPlanned: false)
        let previous = spendByCategory(range: ranges.previous, provider: context.provider, includeUnrecordedPlanned: false)
        let drivers: [(name: String, current: Double, previous: Double, delta: Double)] = Set(current.keys).union(previous.keys)
            .map { name in
                let currentAmount: Double = current[name] ?? 0
                let previousAmount: Double = previous[name] ?? 0
                let deltaAmount: Double = currentAmount - previousAmount
                return (name: name, current: currentAmount, previous: previousAmount, delta: deltaAmount)
            }
        let rows = drivers
            .filter { $0.3 > 0 }
            .sorted { lhs, rhs in lhs.delta == rhs.delta ? lhs.name < rhs.name : lhs.delta > rhs.delta }
            .prefix(8)
            .map { item in
                row(item.name, "\(delta(item.delta)) • current \(currency(item.current)) vs previous \(currency(item.previous))", amount: item.delta)
            }
        let totalDelta = current.values.reduce(0, +) - previous.values.reduce(0, +)
        let card = MarinaWorkspaceAggregationCard(
            title: "Spending Increase Drivers",
            subtitle: "\(rangeLabel(ranges.current)) vs \(rangeLabel(ranges.previous))",
            primaryValue: delta(totalDelta),
            rows: Array(rows),
            traceSummary: "metricFormula=\(contract.id.rawValue),delta=\(totalDelta),rows=\(rows.count)"
        )
        return .handled(card, amountBasis: .budgetImpact, route: .groupedRanked)
    }

    private func categoryOverPace(
        contract: MarinaMetricContract,
        context: MarinaTurnContext
    ) -> MarinaMetricFormulaExecutionResult {
        let range = activeBudgetRange(provider: context.provider, now: context.now) ?? currentMonthRange(containing: context.now)
        let activeBudget = activeBudget(provider: context.provider, now: context.now, range: range)
        let limits = activeBudget?.categoryLimits ?? []
        let toDate = HomeQueryDateRange(startDate: range.startDate, endDate: min(endOfDay(context.now), range.endDate))
        let elapsed = max(1, daysInclusive(from: range.startDate, to: toDate.endDate))
        let totalDays = max(elapsed, daysInclusive(from: range.startDate, to: range.endDate))
        let pace = min(1.0, Double(elapsed) / Double(totalDays))
        let spend = spendByCategory(range: toDate, provider: context.provider, includeUnrecordedPlanned: false)
        let rows = limits.compactMap { limit -> MarinaWorkspaceAggregationCard.Row? in
            guard let maxAmount = limit.maxAmount, maxAmount > 0, let category = limit.category else { return nil }
            let actual = spend[category.name] ?? 0
            let expected = maxAmount * pace
            let over = actual - expected
            guard over > 0 else { return nil }
            let projected = actual / max(pace, 0.01)
            return row(
                category.name,
                "\(currency(actual)) to date • projected \(currency(projected)) vs max \(currency(maxAmount))",
                amount: over,
                objectType: .category,
                sourceID: category.id
            )
        }
        .sorted { ($0.amount ?? 0) > ($1.amount ?? 0) }
        let card = MarinaWorkspaceAggregationCard(
            title: "Categories Over Pace",
            subtitle: "\(elapsed) of \(totalDays) days elapsed",
            primaryValue: rows.first?.label ?? "None",
            rows: rows,
            traceSummary: "metricFormula=\(contract.id.rawValue),rows=\(rows.count)"
        )
        return .handled(card, amountBasis: .budgetImpact, route: .groupedRanked)
    }

    private func cardOverspendingDriver(
        contract: MarinaMetricContract,
        candidate: MarinaQueryPlanCandidate,
        context: MarinaTurnContext
    ) -> MarinaMetricFormulaExecutionResult {
        let range = currentMonthRange(containing: context.now)
        let plannedByCard = Dictionary(grouping: context.provider.fetchAllPlannedExpenses().filter { contains($0.expenseDate, in: range) }) { expense in
            expense.card?.id
        }
        let baselines = plannedByCard.compactMapValues { expenses -> Double in
            expenses.reduce(0.0) { $0 + max(0, $1.plannedAmount) }
        }
        guard baselines.values.reduce(0, +) > 0 else {
            return setupRequired(contract: contract, candidate: candidate, message: "Marina needs planned expenses by card before it can call card spend overspending.")
        }
        let actualByCard = actualSpendByCard(range: range, provider: context.provider, includeUnrecordedPlanned: false)
        let rows = context.provider.fetchAllCards().compactMap { card -> MarinaWorkspaceAggregationCard.Row? in
            let baseline = baselines[card.id] ?? 0
            let actual = actualByCard[card.id] ?? 0
            let over = actual - baseline
            guard over > 0 else { return nil }
            return row(card.name, "\(delta(over)) • actual \(currency(actual)) vs planned \(currency(baseline))", amount: over, objectType: .card, sourceID: card.id)
        }
        .sorted { ($0.amount ?? 0) > ($1.amount ?? 0) }
        let card = MarinaWorkspaceAggregationCard(
            title: "Card Overspending Drivers",
            subtitle: rangeLabel(range),
            primaryValue: rows.first?.label ?? "None",
            rows: rows,
            traceSummary: "metricFormula=\(contract.id.rawValue),rows=\(rows.count)"
        )
        return .handled(card, amountBasis: .budgetImpact, route: .groupedRanked)
    }

    private func categoryCutImpact(
        contract: MarinaMetricContract,
        candidate: MarinaQueryPlanCandidate,
        context: MarinaTurnContext
    ) -> MarinaMetricFormulaExecutionResult {
        let percentValue = percentage(in: candidate.rawPrompt) ?? 20
        let fraction = max(0, percentValue) / 100
        let range = currentMonthRange(containing: context.now)
        let rows = spendByCategory(range: range, provider: context.provider)
            .map { name, amount in row(name, "\(currency(amount * fraction)) saved from \(currency(amount)) at \(Int(percentValue))%", amount: amount * fraction) }
            .filter { ($0.amount ?? 0) > 0 }
            .sorted { ($0.amount ?? 0) > ($1.amount ?? 0) }
        let card = MarinaWorkspaceAggregationCard(
            title: "Category Cut Impact",
            subtitle: rangeLabel(range),
            primaryValue: rows.first?.value,
            rows: rows,
            traceSummary: "metricFormula=\(contract.id.rawValue),percent=\(percentValue),rows=\(rows.count)"
        )
        return .handled(card, amountBasis: .budgetImpact, route: .scenario)
    }

    // MARK: - Batch 3

    private func upcomingExpensesBeforeNextIncome(
        contract: MarinaMetricContract,
        candidate: MarinaQueryPlanCandidate,
        context: MarinaTurnContext
    ) -> MarinaMetricFormulaExecutionResult {
        let now = context.now
        guard let nextIncome = context.provider.fetchAllIncomes().filter({ $0.date >= now }).sorted(by: { $0.date < $1.date }).first else {
            return setupRequired(contract: contract, candidate: candidate, message: "Marina needs an upcoming planned or actual income row to define the window.")
        }
        let range = HomeQueryDateRange(startDate: now, endDate: nextIncome.date)
        let rows = context.provider.fetchAllPlannedExpenses()
            .filter { $0.expenseDate >= now && $0.expenseDate < nextIncome.date }
            .sorted { $0.expenseDate < $1.expenseDate }
            .map { expense in
                row(expense.title, "\(currency(SavingsMathService.plannedProjectedBudgetImpactAmount(for: expense))) on \(shortDate(expense.expenseDate))", amount: SavingsMathService.plannedProjectedBudgetImpactAmount(for: expense), date: expense.expenseDate, objectType: .plannedExpense, sourceID: expense.id)
            }
        let card = MarinaWorkspaceAggregationCard(
            title: "Upcoming Expenses Before Next Income",
            subtitle: "Before \(nextIncome.source) on \(shortDate(nextIncome.date))",
            primaryValue: rows.isEmpty ? "None" : currency(rows.reduce(0.0) { $0 + ($1.amount ?? 0) }),
            rows: rows,
            traceSummary: "metricFormula=\(contract.id.rawValue),range=\(rangeLabel(range)),rows=\(rows.count)"
        )
        return .handled(card, amountBasis: .budgetImpact, route: .list)
    }

    private func unusualMerchantSpend(
        contract: MarinaMetricContract,
        context: MarinaTurnContext
    ) -> MarinaMetricFormulaExecutionResult {
        let current = currentMonthRange(containing: context.now)
        let baseline = previousCompletedMonthsRange(before: context.now, months: 3)
        let currentTotals = variableSpendByMerchant(range: current, provider: context.provider)
        let baselineTotals = variableSpendByMerchant(range: baseline, provider: context.provider)
        let rows = currentTotals.compactMap { key, currentAmount -> MarinaWorkspaceAggregationCard.Row? in
            let baselineAverage = (baselineTotals[key] ?? 0) / 3
            let deltaAmount = currentAmount - baselineAverage
            guard currentAmount >= 50, deltaAmount >= 25, currentAmount >= baselineAverage * 1.5 else { return nil }
            return row(displayMerchant(key), "\(delta(deltaAmount)) • current \(currency(currentAmount)) vs baseline \(currency(baselineAverage))", amount: deltaAmount)
        }
        .sorted { ($0.amount ?? 0) > ($1.amount ?? 0) }
        let card = MarinaWorkspaceAggregationCard(
            title: "Unusual Merchant Spend",
            subtitle: "\(rangeLabel(current)) vs prior 3-month average",
            primaryValue: rows.first?.label ?? "None",
            rows: rows,
            traceSummary: "metricFormula=\(contract.id.rawValue),rows=\(rows.count)"
        )
        return .handled(card, amountBasis: .budgetImpact, route: .groupedRanked)
    }

    private func subscriptionSpend(
        contract: MarinaMetricContract,
        candidate: MarinaQueryPlanCandidate,
        context: MarinaTurnContext
    ) -> MarinaMetricFormulaExecutionResult {
        let range = quarterRange(containing: context.now)
        let subscriptionCategoryIDs = Set(context.provider.fetchAllCategories()
            .filter { normalized($0.name).contains("subscription") }
            .map(\.id))
        let subscriptionPresetIDs = Set(context.provider.fetchAllPresets()
            .filter { normalized($0.title).contains("subscription") }
            .map(\.id))
        let hasIdentity = subscriptionCategoryIDs.isEmpty == false || subscriptionPresetIDs.isEmpty == false
        guard hasIdentity else {
            return setupRequired(contract: contract, candidate: candidate, message: "Marina needs a Subscriptions category, subscription preset, or explicit merchant set before it can total subscriptions safely.")
        }
        let variable = context.provider.fetchAllVariableExpenses().filter { expense in
            contains(expense.transactionDate, in: range)
                && (expense.category.map { subscriptionCategoryIDs.contains($0.id) } == true
                    || normalized(expense.descriptionText).contains("subscription"))
        }
        let planned = context.provider.fetchAllPlannedExpenses().filter { expense in
            contains(expense.expenseDate, in: range)
                && (expense.category.map { subscriptionCategoryIDs.contains($0.id) } == true
                    || expense.sourcePresetID.map { subscriptionPresetIDs.contains($0) } == true
                    || normalized(expense.title).contains("subscription"))
        }
        let variableTotal = variable.reduce(0.0) { $0 + SavingsMathService.variableBudgetImpactAmount(for: $1) }
        let plannedTotal = planned.reduce(0.0) { $0 + SavingsMathService.plannedBudgetImpactAmount(for: $1) }
        let card = MarinaWorkspaceAggregationCard(
            title: "Subscription Spend",
            subtitle: rangeLabel(range),
            primaryValue: currency(variableTotal + plannedTotal),
            rows: [
                row("Variable subscription spend", currency(variableTotal), amount: variableTotal),
                row("Planned subscription spend", currency(plannedTotal), amount: plannedTotal)
            ],
            traceSummary: "metricFormula=\(contract.id.rawValue),total=\(variableTotal + plannedTotal)"
        )
        return .handled(card, amountBasis: .budgetImpact, route: .aggregate)
    }

    private func skipCategoryScenario(
        contract: MarinaMetricContract,
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        semanticResolved: MarinaResolvedSemanticQuery?,
        context: MarinaTurnContext
    ) -> MarinaMetricFormulaExecutionResult {
        let target = categoryOrMerchantTarget(candidate: candidate, resolved: resolved, semanticResolved: semanticResolved, provider: context.provider)
            ?? fallbackRestaurantsTarget(provider: context.provider)
        guard let target else {
            return setupRequired(contract: contract, candidate: candidate, message: "Marina needs a category or merchant target, such as Restaurants or Dining, before it can simulate a skip.")
        }
        let range = currentMonthRange(containing: context.now)
        let toDate = HomeQueryDateRange(startDate: range.startDate, endDate: min(endOfDay(context.now), range.endDate))
        let totalToDate = totalOwnedSpend(range: toDate, provider: context.provider)
        let targetToDate = totalOwnedSpend(range: toDate, provider: context.provider) { row in
            matches(row: row, target: target)
        }
        let elapsed = max(1, daysInclusive(from: range.startDate, to: toDate.endDate))
        let daysRemaining = max(0, daysInclusive(from: startOfTomorrow(after: context.now), to: range.endDate))
        let projectedWithoutSkip = totalToDate + (totalToDate / Double(elapsed) * Double(daysRemaining))
        let avoidable = min(targetToDate / Double(elapsed) * 14, projectedWithoutSkip)
        let projectedWithSkip = max(0, projectedWithoutSkip - avoidable)
        let card = MarinaWorkspaceAggregationCard(
            title: "Skip \(target.displayName) Scenario",
            subtitle: "Two-week skip projected into \(rangeLabel(range))",
            primaryValue: currency(projectedWithSkip),
            rows: [
                row("Projected without skip", currency(projectedWithoutSkip), amount: projectedWithoutSkip),
                row("Estimated avoided spend", currency(avoidable), amount: avoidable),
                row("Projected with skip", currency(projectedWithSkip), amount: projectedWithSkip)
            ],
            traceSummary: "metricFormula=\(contract.id.rawValue),target=\(target.displayName),avoided=\(avoidable)"
        )
        return .handled(card, amountBasis: .budgetImpact, route: .scenario)
    }

    private func savingsTrackVsLastMonth(
        contract: MarinaMetricContract,
        context: MarinaTurnContext
    ) -> MarinaMetricFormulaExecutionResult {
        let ranges = currentAndPreviousFullMonthRanges(now: context.now)
        let currentProjected = projectedSavings(range: ranges.current, now: context.now, provider: context.provider)
        let lastActual = actualSavings(range: ranges.previous, provider: context.provider)
        let diff = currentProjected - lastActual
        let card = MarinaWorkspaceAggregationCard(
            title: "Savings Track vs Last Month",
            subtitle: "\(rangeLabel(ranges.current)) vs \(rangeLabel(ranges.previous))",
            primaryValue: diff >= 0 ? "On track" : "Behind",
            rows: [
                row("Projected savings", currency(currentProjected), amount: currentProjected),
                row("Last month actual savings", currency(lastActual), amount: lastActual),
                row("Difference", delta(diff), amount: diff)
            ],
            traceSummary: "metricFormula=\(contract.id.rawValue),difference=\(diff)"
        )
        return .handled(card, amountBasis: .budgetImpact, route: .comparison)
    }

    // MARK: - Batch 4

    private func incomeBySource(
        contract: MarinaMetricContract,
        context: MarinaTurnContext
    ) -> MarinaMetricFormulaExecutionResult {
        let plan = MarinaAggregationPlan(
            status: .executable,
            operation: .sum,
            measure: .income,
            grouping: MarinaGroupingCandidate(dimension: .incomeSource, rawText: "source"),
            limit: 10,
            incomeStatusScope: .actual,
            responseShape: contract.responseShape
        )
        switch MarinaWorkspaceAggregationExecutor(calendar: calendar).execute(
            plan: plan,
            provider: context.provider,
            now: context.now
        ) {
        case .handled(let card):
            return .handled(card, amountBasis: .actualIncome, route: .groupedRanked)
        case .unsupported:
            return .notHandled
        }
    }

    private func reconciliationOwedThisMonth(
        contract: MarinaMetricContract,
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        semanticResolved: MarinaResolvedSemanticQuery?,
        context: MarinaTurnContext
    ) -> MarinaMetricFormulaExecutionResult {
        guard let account = allocationAccount(candidate: candidate, resolved: resolved, semanticResolved: semanticResolved, provider: context.provider) else {
            return setupRequired(contract: contract, candidate: candidate, message: "Marina needs the reconciliation account before it can calculate what is owed.")
        }
        let range = currentMonthRange(containing: context.now)
        let allocations = context.provider.fetchAllExpenseAllocations().filter { allocation in
            allocation.account?.id == account.id && contains(linkedDate(for: allocation) ?? allocation.createdAt, in: range)
        }
        let settlements = context.provider.fetchAllAllocationSettlements().filter { settlement in
            settlement.account?.id == account.id && contains(settlement.date, in: range)
        }
        let allocatedTotal = allocations.reduce(0.0) { $0 + max(0, $1.allocatedAmount) }
        let settlementTotal = settlements.reduce(0.0) { $0 + $1.amount }
        let owed = allocatedTotal + settlementTotal
        let card = MarinaWorkspaceAggregationCard(
            title: "\(account.name) Owed This Month",
            subtitle: rangeLabel(range),
            primaryValue: currency(owed),
            rows: [
                row("Allocated share", currency(allocatedTotal), amount: allocatedTotal),
                row("Signed settlements", currency(settlementTotal), amount: settlementTotal),
                row("Net owed", currency(owed), amount: owed)
            ],
            traceSummary: "metricFormula=\(contract.id.rawValue),account=\(account.name),owed=\(owed)"
        )
        return .handled(card, amountBasis: .reconciliationBalance, route: .aggregate)
    }

    private func budgetSharedLinks(
        contract: MarinaMetricContract,
        context: MarinaTurnContext
    ) -> MarinaMetricFormulaExecutionResult {
        var rows: [MarinaWorkspaceAggregationCard.Row] = []
        let budgets = context.provider.fetchAllBudgets()
        let cardGroups = Dictionary(grouping: budgets.flatMap { budget in
            (budget.cardLinks ?? []).compactMap { link in link.card.map { (object: $0.name, budget: budget.name, id: $0.id, type: "Card") } }
        }) { $0.id }
        for group in cardGroups.values where group.count > 1 {
            let first = group[0]
            rows.append(row("\(first.type): \(first.object)", group.map(\.budget).sorted().joined(separator: ", "), objectType: .card, sourceID: first.id))
        }
        let presetGroups = Dictionary(grouping: budgets.flatMap { budget in
            (budget.presetLinks ?? []).compactMap { link in link.preset.map { (object: $0.title, budget: budget.name, id: $0.id, type: "Preset") } }
        }) { $0.id }
        for group in presetGroups.values where group.count > 1 {
            let first = group[0]
            rows.append(row("\(first.type): \(first.object)", group.map(\.budget).sorted().joined(separator: ", "), objectType: .preset, sourceID: first.id))
        }
        let sortedRows = rows.sorted { $0.label < $1.label }
        let card = MarinaWorkspaceAggregationCard(
            title: "Shared Budget Links",
            subtitle: "Cards and presets linked to more than one budget",
            primaryValue: sortedRows.isEmpty ? "None" : "\(sortedRows.count)",
            rows: sortedRows,
            traceSummary: "metricFormula=\(contract.id.rawValue),rows=\(sortedRows.count)"
        )
        return .handled(card, amountBasis: .homeSpend, route: .list)
    }

    private func categorizationReview(
        contract: MarinaMetricContract,
        context: MarinaTurnContext
    ) -> MarinaMetricFormulaExecutionResult {
        let range = currentMonthRange(containing: context.now)
        let rules = Dictionary(uniqueKeysWithValues: context.provider.fetchAllImportMerchantRules().map { ($0.merchantKey, $0) })
        let matcher = ImportMerchantRuleMatcher(rulesByKey: rules)
        var rows: [MarinaWorkspaceAggregationCard.Row] = []
        for expense in context.provider.fetchAllVariableExpenses() where contains(expense.transactionDate, in: range) {
            if expense.category == nil {
                rows.append(row(expense.descriptionText, "\(currency(SavingsMathService.variableBudgetImpactAmount(for: expense))) • Uncategorized", amount: SavingsMathService.variableBudgetImpactAmount(for: expense), date: expense.transactionDate, objectType: .variableExpense, sourceID: expense.id))
                continue
            }
            if let match = matcher.match(for: MerchantNormalizer.normalizeKey(expense.descriptionText)),
               let preferred = match.rule.preferredCategory,
               preferred.id != expense.category?.id {
                rows.append(row(expense.descriptionText, "\(expense.category?.name ?? "Uncategorized") -> \(preferred.name)", date: expense.transactionDate, objectType: .variableExpense, sourceID: expense.id))
            }
        }
        for expense in context.provider.fetchAllPlannedExpenses() where contains(expense.expenseDate, in: range) && expense.category == nil {
            rows.append(row(expense.title, "\(currency(SavingsMathService.plannedProjectedBudgetImpactAmount(for: expense))) • Uncategorized planned", amount: SavingsMathService.plannedProjectedBudgetImpactAmount(for: expense), date: expense.expenseDate, objectType: .plannedExpense, sourceID: expense.id))
        }
        let sortedRows = rows.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        let card = MarinaWorkspaceAggregationCard(
            title: "Categorization Review",
            subtitle: rangeLabel(range),
            primaryValue: sortedRows.isEmpty ? "None" : "\(sortedRows.count)",
            rows: sortedRows,
            traceSummary: "metricFormula=\(contract.id.rawValue),rows=\(sortedRows.count)"
        )
        return .handled(card, amountBasis: .budgetImpact, route: .list)
    }

    private func sinceLastCheckIn(
        contract: MarinaMetricContract,
        candidate: MarinaQueryPlanCandidate,
        context: MarinaTurnContext
    ) -> MarinaMetricFormulaExecutionResult {
        let store = MarinaConversationStore()
        guard let since = store.loadLastCheckIn(workspaceID: context.provider.workspaceID) else {
            return setupRequired(contract: contract, candidate: candidate, message: "Marina has no saved check-in snapshot for this workspace yet. Start a check-in first, then this metric can compare later changes.")
        }
        let range = HomeQueryDateRange(startDate: since, endDate: context.now)
        var rows: [MarinaWorkspaceAggregationCard.Row] = []
        rows += context.provider.fetchAllVariableExpenses().filter { $0.transactionDate > since }.map {
            row($0.descriptionText, "\(currency(SavingsMathService.variableBudgetImpactAmount(for: $0))) • variable expense", amount: SavingsMathService.variableBudgetImpactAmount(for: $0), date: $0.transactionDate, objectType: .variableExpense, sourceID: $0.id)
        }
        rows += context.provider.fetchAllPlannedExpenses().filter { $0.expenseDate > since }.map {
            row($0.title, "\(currency(SavingsMathService.plannedBudgetImpactAmount(for: $0))) • planned expense", amount: SavingsMathService.plannedBudgetImpactAmount(for: $0), date: $0.expenseDate, objectType: .plannedExpense, sourceID: $0.id)
        }
        rows += context.provider.fetchAllIncomes().filter { $0.date > since }.map {
            row($0.source, "\(currency($0.amount)) • \($0.isPlanned ? "expected income" : "received income")", amount: $0.amount, date: $0.date, objectType: .income, sourceID: $0.id)
        }
        rows += context.provider.fetchAllSavingsLedgerEntries().filter { $0.date > since }.map {
            row($0.note, "\(currency($0.amount)) • savings ledger", amount: $0.amount, date: $0.date, objectType: .savingsLedgerEntry, sourceID: $0.id)
        }
        rows += context.provider.fetchAllExpenseAllocations().filter { $0.updatedAt > since || $0.createdAt > since }.map {
            row($0.account?.name ?? "Allocation", "\(currency($0.allocatedAmount)) • allocation", amount: $0.allocatedAmount, date: $0.updatedAt, objectType: .expenseAllocation, sourceID: $0.id)
        }
        rows += context.provider.fetchAllAllocationSettlements().filter { $0.date > since }.map {
            row($0.note, "\(currency($0.amount)) • settlement", amount: $0.amount, date: $0.date, objectType: .reconciliationItem, sourceID: $0.id)
        }
        let sortedRows = rows.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        let card = MarinaWorkspaceAggregationCard(
            title: "Changed Since Last Check-In",
            subtitle: rangeLabel(range),
            primaryValue: sortedRows.isEmpty ? "Nothing new" : "\(sortedRows.count)",
            rows: Array(sortedRows.prefix(12)),
            traceSummary: "metricFormula=\(contract.id.rawValue),rows=\(sortedRows.count)"
        )
        return .handled(card, amountBasis: .budgetImpact, route: .list)
    }

    // MARK: - Shared Calculations

    private struct SpendRow {
        let amount: Double
        let date: Date
        let categoryName: String
        let cardID: UUID?
        let cardName: String
        let merchantKey: String
    }

    private struct Target {
        let entityType: MarinaCandidateEntityTypeHint
        let displayName: String
        let sourceID: UUID?
    }

    private func spendingRows(
        range: HomeQueryDateRange,
        provider: MarinaDataProvider,
        includeUnrecordedPlanned: Bool = true
    ) -> [SpendRow] {
        let variable = provider.fetchAllVariableExpenses().filter { contains($0.transactionDate, in: range) }.map { expense in
            SpendRow(
                amount: SavingsMathService.variableBudgetImpactAmount(for: expense),
                date: expense.transactionDate,
                categoryName: expense.category?.name ?? "Uncategorized",
                cardID: expense.card?.id,
                cardName: expense.card?.name ?? "No Card",
                merchantKey: MerchantNormalizer.normalizeKey(expense.descriptionText)
            )
        }
        let planned = provider.fetchAllPlannedExpenses()
            .filter { contains($0.expenseDate, in: range) && (includeUnrecordedPlanned || $0.actualAmount > 0) }
            .map { expense in
            SpendRow(
                amount: SavingsMathService.plannedBudgetImpactAmount(for: expense),
                date: expense.expenseDate,
                categoryName: expense.category?.name ?? "Uncategorized",
                cardID: expense.card?.id,
                cardName: expense.card?.name ?? "No Card",
                merchantKey: MerchantNormalizer.normalizeKey(expense.title)
            )
        }
        return variable + planned
    }

    private func spendByCategory(
        range: HomeQueryDateRange,
        provider: MarinaDataProvider,
        includeUnrecordedPlanned: Bool = true
    ) -> [String: Double] {
        spendingRows(
            range: range,
            provider: provider,
            includeUnrecordedPlanned: includeUnrecordedPlanned
        ).reduce(into: [:]) { totals, row in
            totals[row.categoryName, default: 0] += row.amount
        }
    }

    private func actualSpendByCard(
        range: HomeQueryDateRange,
        provider: MarinaDataProvider,
        includeUnrecordedPlanned: Bool = true
    ) -> [UUID: Double] {
        spendingRows(
            range: range,
            provider: provider,
            includeUnrecordedPlanned: includeUnrecordedPlanned
        ).reduce(into: [:]) { totals, row in
            if let cardID = row.cardID {
                totals[cardID, default: 0] += row.amount
            }
        }
    }

    private func variableSpendByMerchant(range: HomeQueryDateRange, provider: MarinaDataProvider) -> [String: Double] {
        provider.fetchAllVariableExpenses()
            .filter { contains($0.transactionDate, in: range) }
            .reduce(into: [:]) { totals, expense in
                let key = MerchantNormalizer.normalizeKey(expense.descriptionText)
                guard key.isEmpty == false else { return }
                totals[key, default: 0] += SavingsMathService.variableBudgetImpactAmount(for: expense)
            }
    }

    private func totalOwnedSpend(
        range: HomeQueryDateRange,
        provider: MarinaDataProvider,
        matching predicate: (SpendRow) -> Bool = { _ in true }
    ) -> Double {
        spendingRows(range: range, provider: provider)
            .filter(predicate)
            .reduce(0.0) { $0 + $1.amount }
    }

    private func projectedSavings(range: HomeQueryDateRange, now: Date, provider: MarinaDataProvider) -> Double {
        let toDateEnd = min(endOfDay(now), range.endDate)
        let remaining = HomeQueryDateRange(startDate: calendar.startOfDay(for: now), endDate: range.endDate)
        let actualIncome = provider.fetchAllIncomes().filter { $0.isPlanned == false && contains($0.date, in: HomeQueryDateRange(startDate: range.startDate, endDate: toDateEnd)) }.reduce(0.0) { $0 + $1.amount }
        let plannedIncome = provider.fetchAllIncomes().filter { $0.isPlanned && contains($0.date, in: remaining) }.reduce(0.0) { $0 + $1.amount }
        let variable = provider.fetchAllVariableExpenses().filter { contains($0.transactionDate, in: HomeQueryDateRange(startDate: range.startDate, endDate: toDateEnd)) }.reduce(0.0) { $0 + SavingsMathService.variableBudgetImpactAmount(for: $1) }
        let plannedPast = provider.fetchAllPlannedExpenses().filter { $0.expenseDate < calendar.startOfDay(for: now) && contains($0.expenseDate, in: range) }.reduce(0.0) { $0 + SavingsMathService.plannedBudgetImpactAmount(for: $1) }
        let plannedRemaining = provider.fetchAllPlannedExpenses().filter { contains($0.expenseDate, in: remaining) }.reduce(0.0) { $0 + SavingsMathService.plannedProjectedBudgetImpactAmount(for: $1) }
        let savingsAdjustments = SavingsMathService.actualSavingsAdjustmentTotal(from: provider.fetchAllSavingsLedgerEntries(), startDate: range.startDate, endDate: toDateEnd)
        return actualIncome + plannedIncome - variable - plannedPast - plannedRemaining + savingsAdjustments
    }

    private func actualSavings(range: HomeQueryDateRange, provider: MarinaDataProvider) -> Double {
        let income = provider.fetchAllIncomes().filter { $0.isPlanned == false && contains($0.date, in: range) }.reduce(0.0) { $0 + $1.amount }
        let variable = provider.fetchAllVariableExpenses().filter { contains($0.transactionDate, in: range) }.reduce(0.0) { $0 + SavingsMathService.variableBudgetImpactAmount(for: $1) }
        let planned = provider.fetchAllPlannedExpenses().filter { contains($0.expenseDate, in: range) }.reduce(0.0) { $0 + SavingsMathService.plannedBudgetImpactAmount(for: $1) }
        let savingsAdjustments = SavingsMathService.actualSavingsAdjustmentTotal(from: provider.fetchAllSavingsLedgerEntries(), startDate: range.startDate, endDate: range.endDate)
        return income - variable - planned + savingsAdjustments
    }

    // MARK: - Target Resolution Helpers

    private func allocationAccount(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        semanticResolved: MarinaResolvedSemanticQuery?,
        provider: MarinaDataProvider
    ) -> AllocationAccount? {
        let targetNames = resolved.resolvedTargets.filter { $0.entityType == .allocationAccount }.map(\.displayName)
            + (semanticResolved?.resolvedFilters.filter { $0.entityType == .allocationAccount }.map(\.displayName) ?? [])
        let prompt = normalized(candidate.rawPrompt)
        return provider.fetchAllAllocationAccounts().first { account in
            targetNames.contains { normalized($0) == normalized(account.name) }
                || prompt.contains(normalized(account.name))
        }
    }

    private func categoryOrMerchantTarget(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        semanticResolved: MarinaResolvedSemanticQuery?,
        provider: MarinaDataProvider
    ) -> Target? {
        let targets = resolved.resolvedTargets.map { Target(entityType: $0.entityType, displayName: $0.displayName, sourceID: $0.sourceID) }
            + (semanticResolved?.resolvedFilters.map { Target(entityType: $0.entityType, displayName: $0.displayName, sourceID: $0.sourceID) } ?? [])
        if let target = targets.first(where: { $0.entityType == .category || $0.entityType == .merchant }) {
            return target
        }
        let prompt = normalized(candidate.rawPrompt)
        if let category = provider.fetchAllCategories().first(where: { prompt.contains(normalized($0.name)) }) {
            return Target(entityType: .category, displayName: category.name, sourceID: category.id)
        }
        return nil
    }

    private func fallbackRestaurantsTarget(provider: MarinaDataProvider) -> Target? {
        if let category = provider.fetchAllCategories().first(where: {
            let name = normalized($0.name)
            return name.contains("restaurant") || name.contains("dining")
        }) {
            return Target(entityType: .category, displayName: category.name, sourceID: category.id)
        }
        return Target(entityType: .merchant, displayName: "restaurants", sourceID: nil)
    }

    private func matches(row: SpendRow, target: Target) -> Bool {
        switch target.entityType {
        case .category:
            if let sourceID = target.sourceID {
                return false == sourceID.uuidString.isEmpty && normalized(row.categoryName) == normalized(target.displayName)
            }
            return normalized(row.categoryName).contains(normalized(target.displayName))
        case .merchant:
            return normalized(row.merchantKey).contains(normalized(target.displayName))
                || normalized(target.displayName).contains(normalized(row.merchantKey))
        default:
            return false
        }
    }

    private func activeBudget(provider: MarinaDataProvider, now: Date, range: HomeQueryDateRange) -> Budget? {
        provider.fetchAllBudgets().first { $0.startDate <= now && $0.endDate >= now }
            ?? provider.fetchAllBudgets().first { $0.startDate <= range.endDate && $0.endDate >= range.startDate }
    }

    private func activeBudgetRange(provider: MarinaDataProvider, now: Date) -> HomeQueryDateRange? {
        guard let budget = provider.fetchAllBudgets().first(where: { $0.startDate <= now && $0.endDate >= now }) else {
            return nil
        }
        return HomeQueryDateRange(startDate: budget.startDate, endDate: endOfDay(budget.endDate))
    }

    private func linkedDate(for allocation: ExpenseAllocation) -> Date? {
        allocation.expense?.transactionDate ?? allocation.plannedExpense?.expenseDate
    }

    // MARK: - Dates

    private func currentMonthRange(containing date: Date) -> HomeQueryDateRange {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? calendar.startOfDay(for: date)
        let next = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return HomeQueryDateRange(startDate: start, endDate: calendar.date(byAdding: .second, value: -1, to: next) ?? next)
    }

    private func quarterRange(containing date: Date) -> HomeQueryDateRange {
        let components = calendar.dateComponents([.year, .month], from: date)
        let month = components.month ?? 1
        let quarterStartMonth = ((month - 1) / 3) * 3 + 1
        let start = calendar.date(from: DateComponents(year: components.year, month: quarterStartMonth, day: 1)) ?? calendar.startOfDay(for: date)
        let next = calendar.date(byAdding: .month, value: 3, to: start) ?? start
        return HomeQueryDateRange(startDate: start, endDate: calendar.date(byAdding: .second, value: -1, to: next) ?? next)
    }

    private func previousCompletedMonthsRange(before date: Date, months: Int) -> HomeQueryDateRange {
        let currentStart = currentMonthRange(containing: date).startDate
        let start = calendar.date(byAdding: .month, value: -max(1, months), to: currentStart) ?? currentStart
        let end = calendar.date(byAdding: .second, value: -1, to: currentStart) ?? currentStart
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func currentAndPreviousMatchingMonthRanges(now: Date) -> (current: HomeQueryDateRange, previous: HomeQueryDateRange) {
        let currentFull = currentMonthRange(containing: now)
        let current = HomeQueryDateRange(startDate: currentFull.startDate, endDate: endOfDay(now))
        let dayOffset = max(0, calendar.dateComponents([.day], from: currentFull.startDate, to: calendar.startOfDay(for: now)).day ?? 0)
        let previousStart = calendar.date(byAdding: .month, value: -1, to: currentFull.startDate) ?? currentFull.startDate
        let previousEndDay = calendar.date(byAdding: .day, value: dayOffset, to: previousStart) ?? previousStart
        return (current, HomeQueryDateRange(startDate: previousStart, endDate: endOfDay(previousEndDay)))
    }

    private func currentAndPreviousFullMonthRanges(now: Date) -> (current: HomeQueryDateRange, previous: HomeQueryDateRange) {
        let current = currentMonthRange(containing: now)
        let previousStart = calendar.date(byAdding: .month, value: -1, to: current.startDate) ?? current.startDate
        let previousNext = current.startDate
        let previousEnd = calendar.date(byAdding: .second, value: -1, to: previousNext) ?? previousNext
        return (current, HomeQueryDateRange(startDate: previousStart, endDate: previousEnd))
    }

    private func contains(_ date: Date, in range: HomeQueryDateRange) -> Bool {
        date >= range.startDate && date <= range.endDate
    }

    private func endOfDay(_ date: Date) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }

    private func startOfTomorrow(after date: Date) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
    }

    private func daysInclusive(from start: Date, to end: Date) -> Int {
        guard end >= start else { return 0 }
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        return (calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0) + 1
    }

    // MARK: - Formatting

    private func row(
        _ label: String,
        _ value: String,
        amount: Double? = nil,
        date: Date? = nil,
        objectType: MarinaLookupObjectType? = nil,
        sourceID: UUID? = nil
    ) -> MarinaWorkspaceAggregationCard.Row {
        MarinaWorkspaceAggregationCard.Row(label: label, value: value, amount: amount, date: date, objectType: objectType, sourceID: sourceID, sortValue: amount)
    }

    private func rangeLabel(_ range: HomeQueryDateRange) -> String {
        rangeLabel(range.startDate, range.endDate)
    }

    private func rangeLabel(_ start: Date, _ end: Date) -> String {
        "\(shortDate(start))-\(shortDate(end))"
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

    private func displayMerchant(_ key: String) -> String {
        MerchantNormalizer.displayName(key)
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s%]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func percentage(in value: String) -> Double? {
        guard let range = value.range(of: #"\d+(?:\.\d+)?\s*%"#, options: .regularExpression) else { return nil }
        return Double(value[range].replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func setupRequired(
        contract: MarinaMetricContract,
        candidate: MarinaQueryPlanCandidate,
        message: String
    ) -> MarinaMetricFormulaExecutionResult {
        let answer = HomeAnswer(
            queryID: UUID(),
            kind: .message,
            userPrompt: candidate.rawPrompt,
            title: "Marina needs one setup step",
            subtitle: contract.formulaName,
            primaryValue: "setup required",
            rows: [
                HomeAnswerRow(title: "Metric contract", value: contract.id.rawValue),
                HomeAnswerRow(title: "Amount basis", value: contract.amountBasisDescription),
                HomeAnswerRow(title: "Source rows", value: contract.sourceModels.joined(separator: ", ")),
                HomeAnswerRow(title: "Required setup", value: message),
                HomeAnswerRow(title: "Refused substitution", value: contract.neverSilentlySubstituteRules.first ?? "No unsafe substitute is allowed.")
            ]
        )
        let unsupported = MarinaTypedUnsupportedResponse(
            kind: .unsupportedCombination,
            message: message,
            candidate: candidate
        )
        return .blocked(answer, unsupported)
    }
}
