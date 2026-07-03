import Foundation

@MainActor
struct MarinaQueryExecutor {
    private let calendar: Calendar
    private let homeEngine: HomeQueryEngine

    init(calendar: Calendar = .current) {
        self.calendar = calendar
        self.homeEngine = HomeQueryEngine(calendar: calendar)
    }

    func execute(plan: MarinaQueryPlan, snapshot: MarinaWorkspaceSnapshot) -> MarinaExecutionResult {
        if plan.semanticRequest.expectedAnswerShape == .clarification {
            return clarification(plan: plan, snapshot: snapshot)
        }

        if let reason = plan.semanticRequest.unsupportedReason {
            return unsupported(reason)
        }

        switch plan.entity {
        case .workspace:
            return workspaceResult(plan: plan, snapshot: snapshot)
        case .card:
            return cardResult(plan: plan, snapshot: snapshot)
        case .category:
            return categoryResult(plan: plan, snapshot: snapshot)
        case .preset:
            return presetResult(plan: plan, snapshot: snapshot)
        case .reconciliationAccount:
            return reconciliationResult(plan: plan, snapshot: snapshot)
        case .savingsAccount:
            return savingsResult(plan: plan, snapshot: snapshot)
        case .income:
            return incomeResult(plan: plan, snapshot: snapshot)
        case .budget:
            return budgetResult(plan: plan, snapshot: snapshot)
        case .plannedExpense, .variableExpense:
            return expenseResult(plan: plan, snapshot: snapshot)
        }
    }

    // MARK: - Workspace

    private func workspaceResult(plan: MarinaQueryPlan, snapshot: MarinaWorkspaceSnapshot) -> MarinaExecutionResult {
        if plan.measure == .color {
            return MarinaExecutionResult(
                kind: .metric,
                title: MarinaL10n.string("marina.answer.workspaceColor.title", defaultValue: "Workspace Color", comment: "Marina answer title for workspace color."),
                primaryValue: snapshot.workspace.hexColor,
                rows: [
                    HomeAnswerRow(title: MarinaL10n.common("workspace", defaultValue: "Workspace", comment: "Common label for workspace."), value: snapshot.workspace.name)
                ]
            )
        }

        return MarinaExecutionResult(
            kind: .metric,
            title: MarinaL10n.string("marina.answer.currentWorkspace.title", defaultValue: "Current Workspace", comment: "Marina answer title for the current workspace."),
            primaryValue: snapshot.workspace.name,
            rows: [
                HomeAnswerRow(title: MarinaL10n.common("color", defaultValue: "Color", comment: "Common label for color."), value: snapshot.workspace.hexColor),
                HomeAnswerRow(title: MarinaL10n.common("budgets", defaultValue: "Budgets", comment: "Common label for budgets."), value: "\(snapshot.budgets.count)"),
                HomeAnswerRow(title: MarinaL10n.common("cards", defaultValue: "Cards", comment: "Common label for cards."), value: "\(snapshot.cards.count)"),
                HomeAnswerRow(title: MarinaL10n.common("categories", defaultValue: "Categories", comment: "Common label for categories."), value: "\(snapshot.categories.count)")
            ]
        )
    }

    // MARK: - Cards

    private func cardResult(plan: MarinaQueryPlan, snapshot: MarinaWorkspaceSnapshot) -> MarinaExecutionResult {
        if plan.operation == .count {
            return MarinaExecutionResult(
                kind: .metric,
                title: MarinaL10n.common("cards", defaultValue: "Cards", comment: "Common label for cards."),
                primaryValue: "\(snapshot.cards.count)"
            )
        }

        if plan.operation == .compare {
            guard let leftName = plan.targetName,
                  let rightName = plan.comparisonTargetName else {
                return clarification(MarinaL10n.string("marina.clarification.whichCardsCompare", defaultValue: "Which two cards should I compare?", comment: "Clarification question when a card comparison is missing targets."))
            }
            guard let left = resolveCard(named: leftName, in: snapshot),
                  let right = resolveCard(named: rightName, in: snapshot) else {
                return unsupported(.unresolvedEntity)
            }
            let leftTotal = homeCardMetrics(for: left, plan: plan, snapshot: snapshot).total
            let rightTotal = homeCardMetrics(for: right, plan: plan, snapshot: snapshot).total
            return comparisonResult(
                title: MarinaL10n.string("marina.answer.cardSpendComparison.title", defaultValue: "Card Spend Comparison", comment: "Marina answer title for card spend comparison."),
                subtitle: rangeLabel(plan.dateRange),
                leftTitle: left.name,
                leftValue: leftTotal,
                rightTitle: right.name,
                rightValue: rightTotal
            )
        }

        guard let targetName = plan.targetName else {
            let grouped = snapshot.cards
                .map { (name: $0.name, value: homeCardMetrics(for: $0, plan: plan, snapshot: snapshot).total) }
                .filter { $0.value > 0 }
                .sorted { $0.value > $1.value }
            return listResult(
                title: MarinaL10n.string("marina.answer.cardSpend.title", defaultValue: "Card Spend", comment: "Marina answer title for card spend list."),
                subtitle: rangeLabel(plan.dateRange),
                rows: grouped.map { HomeAnswerRow(title: $0.name, value: currency($0.value), amount: $0.value) }
            )
        }

        guard let card = resolveCard(named: targetName, in: snapshot) else {
            return unsupported(.unresolvedEntity)
        }
        // Universal ownership note:
        // cardVariableSpend is owned by universal for the Phase 14 variableExpense + card semantic shape.
        // This broader card branch remains the legacy fallback during migration.
        let metrics = homeCardMetrics(for: card, plan: plan, snapshot: snapshot)
        return MarinaExecutionResult(
            kind: .metric,
            title: MarinaL10n.format("marina.answer.namedSpend.title", defaultValue: "%@ Spend", comment: "Marina answer title for spend on a named target.", card.name),
            subtitle: rangeLabel(plan.dateRange),
            primaryValue: currency(metrics.total),
            rows: [
                HomeAnswerRow(title: MarinaL10n.common("planned", defaultValue: "Planned", comment: "Common label for planned values."), value: currency(metrics.plannedTotal), amount: metrics.plannedTotal),
                HomeAnswerRow(title: MarinaL10n.common("variable", defaultValue: "Variable", comment: "Common label for variable values."), value: currency(metrics.variableTotal), amount: metrics.variableTotal),
                HomeAnswerRow(title: MarinaL10n.common("total", defaultValue: "Total", comment: "Common label for totals."), value: currency(metrics.total), amount: metrics.total),
                HomeAnswerRow(title: MarinaL10n.common("period", defaultValue: "Period", comment: "Common label for a date period."), value: rangeLabel(plan.dateRange))
            ]
        )
    }

    // MARK: - Categories

    private func categoryResult(plan: MarinaQueryPlan, snapshot: MarinaWorkspaceSnapshot) -> MarinaExecutionResult {
        if plan.measure == .categoryAvailability {
            if plan.operation == .list {
                return categoryAvailabilityListResult(plan: plan, snapshot: snapshot)
            }

            return executionResult(
                from: homeAnswer(
                    query: HomeQuery(intent: .categoryAvailabilitySummary, dateRange: plan.dateRange),
                    snapshot: snapshot,
                    plan: plan
                )
            )
        }

        if plan.measure == .concentration {
            return categoryConcentrationResult(plan: plan, snapshot: snapshot)
        }

        if plan.operation == .group {
            let intent: HomeQueryIntent = plan.dimensions.contains(.date) ? .spendTrendsSummary : .categorySpendShare
            return executionResult(
                from: homeAnswer(
                    query: HomeQuery(intent: intent, dateRange: plan.dateRange, resultLimit: plan.resultLimit),
                    snapshot: snapshot,
                    plan: plan
                )
            )
        }

        if plan.operation == .compare {
            guard let leftName = plan.targetName,
                  let rightName = plan.comparisonTargetName else {
                return clarification(MarinaL10n.string("marina.clarification.whichCategoriesCompare", defaultValue: "Which two categories should I compare?", comment: "Clarification question when a category comparison is missing targets."))
            }
            guard let left = resolveCategory(named: leftName, in: snapshot),
                  let right = resolveCategory(named: rightName, in: snapshot) else {
                return unsupported(.unresolvedEntity)
            }
            let rows = expenseRows(snapshot: snapshot, scope: .unified, range: plan.dateRange)
            let leftTotal = rows.filter { $0.categoryID == left.id }.reduce(0.0) { $0 + $1.budgetImpact }
            let rightTotal = rows.filter { $0.categoryID == right.id }.reduce(0.0) { $0 + $1.budgetImpact }
            return comparisonResult(
                title: MarinaL10n.string("marina.answer.categorySpendComparison.title", defaultValue: "Category Spend Comparison", comment: "Marina answer title for category spend comparison."),
                subtitle: rangeLabel(plan.dateRange),
                leftTitle: left.name,
                leftValue: leftTotal,
                rightTitle: right.name,
                rightValue: rightTotal
            )
        }

        guard let targetName = plan.targetName,
              let category = resolveCategory(named: targetName, in: snapshot) else {
            return unsupported(.unresolvedEntity)
        }
        let rows = expenseRows(snapshot: snapshot, scope: .unified, range: plan.dateRange)
            .filter { $0.categoryID == category.id }
        if plan.operation == .count {
            return MarinaExecutionResult(
                kind: .metric,
                title: MarinaL10n.format("marina.answer.namedCount.title", defaultValue: "%@ Count", comment: "Marina answer title for a count on a named target.", category.name),
                subtitle: rangeLabel(plan.dateRange),
                primaryValue: "\(rows.count)",
                rows: [HomeAnswerRow(title: MarinaL10n.common("rows", defaultValue: "Rows", comment: "Common label for rows."), value: "\(rows.count)")]
            )
        }
        let total = rows
            .reduce(0.0) { $0 + $1.budgetImpact }
        let primaryValue = plan.operation == .average && rows.isEmpty == false ? total / Double(rows.count) : total
        // Universal ownership note:
        // categoryVariableSpend is owned by universal for the Phase 14 variableExpense + category semantic shape.
        // This broader category branch remains the legacy fallback during migration.
        return MarinaExecutionResult(
            kind: .metric,
            title: plan.operation == .average
                ? MarinaL10n.format("marina.answer.namedAverage.title", defaultValue: "%@ Average", comment: "Marina answer title for an average on a named target.", category.name)
                : MarinaL10n.format("marina.answer.namedSpend.title", defaultValue: "%@ Spend", comment: "Marina answer title for spend on a named target.", category.name),
            subtitle: rangeLabel(plan.dateRange),
            primaryValue: currency(primaryValue),
            rows: [
                HomeAnswerRow(title: plan.operation == .average ? MarinaL10n.common("average", defaultValue: "Average", comment: "Common label for averages.") : MarinaL10n.common("total", defaultValue: "Total", comment: "Common label for totals."), value: currency(primaryValue), amount: primaryValue)
            ]
        )
    }

    // MARK: - Presets

    private func presetResult(plan: MarinaQueryPlan, snapshot: MarinaWorkspaceSnapshot) -> MarinaExecutionResult {
        if plan.measure == .recurringBurden {
            return recurringBurdenResult(plan: plan, snapshot: snapshot)
        }

        if let targetName = plan.targetName,
           let preset = resolvePreset(named: targetName, in: snapshot),
           plan.operation != .next {
            return MarinaExecutionResult(
                kind: .metric,
                title: MarinaL10n.format("marina.answer.namedPreset.title", defaultValue: "%@ Preset", comment: "Marina answer title for a named preset.", preset.title),
                subtitle: preset.isArchived ? MarinaL10n.common("archived", defaultValue: "Archived", comment: "Common label for archived records.") : nil,
                primaryValue: currency(preset.plannedAmount),
                rows: [
                    HomeAnswerRow(title: MarinaL10n.string("marina.answer.row.plannedAmount", defaultValue: "Planned amount", comment: "Row label for planned amount."), value: currency(preset.plannedAmount), sourceID: preset.id, objectType: .preset, amount: preset.plannedAmount),
                    HomeAnswerRow(title: MarinaL10n.string("marina.answer.row.defaultCard", defaultValue: "Default card", comment: "Row label for a preset default card."), value: preset.defaultCard?.name ?? MarinaL10n.common("none", defaultValue: "None", comment: "Common option for no selection.")),
                    HomeAnswerRow(title: MarinaL10n.string("marina.answer.row.defaultCategory", defaultValue: "Default category", comment: "Row label for a preset default category."), value: preset.defaultCategory?.name ?? MarinaL10n.common("uncategorized", defaultValue: "Uncategorized", comment: "Common label for uncategorized expenses."))
                ]
            )
        }

        if plan.operation == .next {
            let planned = snapshot.homePlannedExpenses
                .filter { $0.sourcePresetID != nil }
                .filter { contains($0.expenseDate, in: plan.dateRange) && $0.expenseDate >= calendar.startOfDay(for: plan.now) }
                .sorted { $0.expenseDate < $1.expenseDate }
            guard let next = planned.first else {
                return MarinaExecutionResult(
                    kind: .message,
                    title: MarinaL10n.string("marina.answer.nextPreset.title", defaultValue: "Next Preset", comment: "Marina answer title for next preset."),
                    subtitle: MarinaL10n.string("marina.answer.nextPreset.empty", defaultValue: "No preset-generated planned expenses are due in this period.", comment: "Empty state when no preset-generated planned expenses are due.")
                )
            }
            let presetName = snapshot.presets.first(where: { $0.id == next.sourcePresetID })?.title ?? next.title
            return MarinaExecutionResult(
                kind: .metric,
                title: MarinaL10n.string("marina.answer.nextPresetDue.title", defaultValue: "Next Preset Due", comment: "Marina answer title for the next preset due."),
                subtitle: rangeLabel(plan.dateRange),
                primaryValue: presetName,
                rows: [
                    HomeAnswerRow(title: MarinaL10n.common("amount", defaultValue: "Amount", comment: "Common label for money amount."), value: currency(next.effectiveAmount()), amount: next.effectiveAmount()),
                    HomeAnswerRow(title: MarinaL10n.common("date", defaultValue: "Date", comment: "Common label for a date field."), value: shortDate(next.expenseDate), date: next.expenseDate)
                ]
            )
        }

        if plan.operation == .group, plan.dimensions.contains(.category) {
            let groups = Dictionary(grouping: snapshot.presets) { preset in
                preset.defaultCategory?.name ?? MarinaL10n.common("uncategorized", defaultValue: "Uncategorized", comment: "Common label for uncategorized expenses.")
            }
            let rows = groups
                .map { (name: $0.key, count: $0.value.count) }
                .sorted { $0.count > $1.count }
                .prefix(plan.resultLimit)
                .map { HomeAnswerRow(title: $0.name, value: "\($0.count)") }
            return listResult(
                title: MarinaL10n.string("marina.answer.presetCategories.title", defaultValue: "Preset Categories", comment: "Marina answer title for preset categories."),
                subtitle: MarinaL10n.string("marina.answer.byAssignedDefaultCategory", defaultValue: "By assigned default category", comment: "Subtitle describing preset category grouping."),
                rows: rows
            )
        }

        if plan.measure == .actualAmount {
            let rows = snapshot.plannedExpenses
                .filter { $0.actualAmount > 0 && $0.sourcePresetID != nil && contains($0.expenseDate, in: plan.dateRange) }
                .sorted { $0.expenseDate > $1.expenseDate }
                .prefix(plan.resultLimit)
                .map { expense in
                    HomeAnswerRow(
                        title: expense.title,
                        value: MarinaL10n.format("marina.answer.amountDate.valueFormat", defaultValue: "%@ • %@", comment: "Row value with amount and date.", currency(expense.actualAmount), shortDate(expense.expenseDate)),
                        amount: expense.actualAmount,
                        date: expense.expenseDate
                    )
                }
            return listResult(title: MarinaL10n.string("marina.answer.actualizedPresets.title", defaultValue: "Actualized Presets", comment: "Marina answer title for actualized presets."), subtitle: rangeLabel(plan.dateRange), rows: rows)
        }

        if plan.dimensions.contains(.category), let categoryName = plan.targetName {
            guard let category = resolveCategory(named: categoryName, in: snapshot) else {
                return unsupported(.unresolvedEntity)
            }
            let rows = snapshot.presets
                .filter { $0.isArchived == false && $0.defaultCategory?.id == category.id }
                .sorted { $0.plannedAmount > $1.plannedAmount }
                .prefix(plan.resultLimit)
                .map { HomeAnswerRow(title: $0.title, value: currency($0.plannedAmount), sourceID: $0.id, objectType: .preset, amount: $0.plannedAmount) }
            return listResult(
                title: MarinaL10n.format("marina.answer.namedPresets.title", defaultValue: "%@ Presets", comment: "Marina answer title for presets in a named category.", category.name),
                subtitle: MarinaL10n.string("marina.answer.byAssignedDefaultCategory", defaultValue: "By assigned default category", comment: "Subtitle describing preset category grouping."),
                rows: rows
            )
        }

        let rows = snapshot.presets
            .filter { $0.isArchived == false }
            .sorted { $0.plannedAmount > $1.plannedAmount }
            .prefix(plan.resultLimit)
            .map { HomeAnswerRow(title: $0.title, value: currency($0.plannedAmount), sourceID: $0.id, objectType: .preset, amount: $0.plannedAmount) }
        return listResult(title: MarinaL10n.common("presets", defaultValue: "Presets", comment: "Common label for presets."), rows: rows)
    }

    // MARK: - Reconciliation

    private func reconciliationResult(plan: MarinaQueryPlan, snapshot: MarinaWorkspaceSnapshot) -> MarinaExecutionResult {
        guard let targetName = plan.targetName,
              let account = resolveReconciliationAccount(named: targetName, in: snapshot) else {
            return unsupported(.unresolvedEntity)
        }

        if plan.dimensions.contains(.category), let categoryName = plan.semanticRequest.textQuery,
           let category = resolveCategory(named: categoryName, in: snapshot) {
            let total = expenseRows(snapshot: snapshot, scope: .unified, range: plan.dateRange)
                .filter { $0.reconciliationAccountID == account.id && $0.categoryID == category.id }
                .reduce(0.0) { $0 + $1.reconciliationAmount }
            return MarinaExecutionResult(
                kind: .metric,
                title: MarinaL10n.format("marina.answer.reconciliationCategory.title", defaultValue: "%@ %@ Reconciliation", comment: "Marina answer title for reconciliation account/category result.", account.name, category.name),
                subtitle: rangeLabel(plan.dateRange),
                primaryValue: currency(total),
                rows: [
                    HomeAnswerRow(title: MarinaL10n.string("marina.answer.row.allocatedSpend", defaultValue: "Allocated spend", comment: "Row label for allocated spend."), value: currency(total), amount: total)
                ]
            )
        }

        // Universal ownership note:
        // reconciliationBalanceExplicitAccount is parity-proven through universal.
        // Keep this branch as the legacy fallback until universal routing is promoted beyond debug.
        let total = reconciliationBalance(for: account, range: plan.dateRange)
        return MarinaExecutionResult(
            kind: .metric,
            title: MarinaL10n.format("marina.answer.namedBalance.title", defaultValue: "%@ Balance", comment: "Marina answer title for a named balance.", account.name),
            subtitle: plan.dateRange == nil ? MarinaL10n.string("marina.answer.reconciliation.allHistorySubtitle", defaultValue: "Current outstanding balance across all history", comment: "Subtitle for all-time reconciliation balance.") : rangeLabel(plan.dateRange),
            primaryValue: currency(total),
            rows: [
                HomeAnswerRow(title: MarinaL10n.common("balance", defaultValue: "Balance", comment: "Common label for balance."), value: currency(total), amount: total)
            ]
        )
    }

    // MARK: - Savings

    private func savingsResult(plan: MarinaQueryPlan, snapshot: MarinaWorkspaceSnapshot) -> MarinaExecutionResult {
        if plan.operation == .forecast {
            return executionResult(
                from: homeAnswer(
                    query: HomeQuery(intent: .forecastSavings, dateRange: plan.dateRange),
                    snapshot: snapshot,
                    plan: plan
                )
            )
        }

        let account = plan.targetName.flatMap { resolveSavingsAccount(named: $0, in: snapshot) } ?? snapshot.savingsAccounts.first

        if plan.dateRange == nil {
            // Universal ownership note:
            // savingsTotalExplicitAccount is parity-proven through universal.
            // Keep this branch as the legacy fallback until universal routing is promoted beyond debug.
            let total = account?.total ?? snapshot.savingsEntries.reduce(0.0) { $0 + $1.amount }
            return MarinaExecutionResult(
                kind: .metric,
                title: MarinaL10n.format("marina.answer.namedBalance.title", defaultValue: "%@ Balance", comment: "Marina answer title for a named balance.", account?.name ?? MarinaL10n.common("savings", defaultValue: "Savings", comment: "Common label for savings.")),
                primaryValue: currency(total),
                rows: [
                    HomeAnswerRow(title: account?.name ?? MarinaL10n.string("marina.answer.savingsAccount.fallback", defaultValue: "Savings Account", comment: "Fallback savings account row label."), value: currency(total), amount: total)
                ]
            )
        }

        return executionResult(
            from: homeAnswer(
                query: HomeQuery(intent: .savingsStatus, dateRange: plan.dateRange),
                snapshot: snapshot,
                plan: plan
            )
        )
    }

    // MARK: - Income

    private func incomeResult(plan: MarinaQueryPlan, snapshot: MarinaWorkspaceSnapshot) -> MarinaExecutionResult {
        if plan.measure == .coverageRatio {
            return coverageRatioResult(title: MarinaL10n.string("marina.answer.incomeCoverage.title", defaultValue: "Income Coverage", comment: "Marina answer title for income coverage."), plan: plan, snapshot: snapshot)
        }

        if plan.operation == .share {
            return executionResult(
                from: homeAnswer(
                    query: HomeQuery(intent: .incomeProgressSummary, dateRange: plan.dateRange),
                    snapshot: snapshot,
                    plan: plan
                )
            )
        }

        if plan.operation == .compare {
            let current = incomeTotal(snapshot.incomes, range: plan.dateRange, state: plan.semanticRequest.incomeState ?? .actual, source: plan.targetName)
            let previous = incomeTotal(snapshot.incomes, range: plan.comparisonDateRange, state: plan.semanticRequest.incomeState ?? .actual, source: plan.targetName)
            return comparisonResult(
                title: MarinaL10n.string("marina.answer.incomeComparison.title", defaultValue: "Income Comparison", comment: "Marina answer title for income comparison."),
                subtitle: rangeLabel(plan.dateRange),
                leftTitle: MarinaL10n.string("marina.answer.row.currentPeriod", defaultValue: "Current period", comment: "Row label for current period."),
                leftValue: current,
                rightTitle: MarinaL10n.string("marina.answer.row.previousPeriod", defaultValue: "Previous period", comment: "Row label for previous period."),
                rightValue: previous
            )
        }

        if plan.operation == .list {
            let rows = sortedIncomes(
                snapshot.incomes
                    .filter { contains($0.date, in: plan.dateRange) }
                    .filter { income in
                        switch plan.semanticRequest.incomeState ?? .all {
                        case .planned:
                            return income.isPlanned
                        case .actual:
                            return income.isPlanned == false
                        case .all:
                            return true
                        }
                    }
                    .filter { income in
                        guard let source = plan.targetName else { return true }
                        return normalize(income.source) == normalize(source)
                    },
                sort: plan.semanticRequest.sort
            )
            .prefix(plan.resultLimit)
            .map { income in
                HomeAnswerRow(
                    title: income.source,
                    value: MarinaL10n.format("marina.answer.incomeList.valueFormat", defaultValue: "%@ • %@ • %@", comment: "Income row value with amount, date, and planned/actual state.", currency(income.amount), shortDate(income.date), income.isPlanned ? MarinaL10n.common("planned", defaultValue: "Planned", comment: "Common label for planned values.") : MarinaL10n.common("actual", defaultValue: "Actual", comment: "Common label for actual values.")),
                    sourceID: income.id,
                    objectType: .income,
                    amount: income.amount,
                    date: income.date
                )
            }
            return listResult(title: MarinaL10n.common("income", defaultValue: "Income", comment: "Common label for income."), subtitle: rangeLabel(plan.dateRange), rows: rows)
        }

        // Universal ownership note:
        // incomeTotal and incomeBySource are universal-owned for exact Phase 14/17 semantic shapes.
        // Source-filtered totals, narrowed income states, and other shaped income variants remain legacy-owned for now.
        let total = incomeTotal(snapshot.incomes, range: plan.dateRange, state: plan.semanticRequest.incomeState ?? .all, source: plan.targetName)
        return MarinaExecutionResult(
            kind: .metric,
            title: incomeTitle(state: plan.semanticRequest.incomeState ?? .all, source: plan.targetName),
            subtitle: rangeLabel(plan.dateRange),
            primaryValue: currency(total),
            rows: [
                HomeAnswerRow(title: MarinaL10n.common("total", defaultValue: "Total", comment: "Common label for totals."), value: currency(total), amount: total)
            ]
        )
    }

    // MARK: - Budgets

    private func budgetResult(plan: MarinaQueryPlan, snapshot: MarinaWorkspaceSnapshot) -> MarinaExecutionResult {
        let targetBudgetRange = plan.targetName
            .flatMap { resolveBudget(named: $0, in: snapshot) }
            .map { HomeQueryDateRange(startDate: $0.startDate, endDate: $0.endDate) }
        let formulaRange = targetBudgetRange ?? resolvedRange(for: plan)

        if let formulaResult = budgetFormulaResult(plan: plan, snapshot: snapshot, range: formulaRange) {
            return formulaResult
        }

        if plan.operation == .whatIf {
            let amount = max(0, plan.semanticRequest.whatIfAmount ?? 0)
            guard amount > 0 else {
                return clarification(MarinaL10n.string("marina.clarification.whatIfAmount", defaultValue: "What amount should I use for the what-if?", comment: "Clarification question for missing what-if amount."))
            }
            if plan.measure == .remainingRoom {
                let current = safeSpendSummary(snapshot: snapshot, plan: plan)
                let scenario = safeSpendSummary(
                    snapshot: snapshot,
                    plan: plan,
                    virtualSpendAmount: amount,
                    virtualSpendCategoryID: matchingCategoryID(for: plan.targetName, snapshot: snapshot)
                )

                return MarinaExecutionResult(
                    kind: .comparison,
                    title: MarinaL10n.common("whatIf", defaultValue: "What If", comment: "Common label for what-if scenarios."),
                    subtitle: rangeLabel(plan.dateRange),
                    primaryValue: currency(scenario.safeToSpendToday),
                    rows: [
                        HomeAnswerRow(title: MarinaL10n.string("marina.answer.row.currentSafeSpendToday", defaultValue: "Current safe spend today", comment: "Row label for current safe spend today."), value: currency(current.safeToSpendToday), amount: current.safeToSpendToday),
                        HomeAnswerRow(title: MarinaL10n.string("marina.answer.row.virtualSpend", defaultValue: "Virtual spend", comment: "Row label for virtual spend."), value: "-\(currency(amount))", amount: -amount),
                        HomeAnswerRow(title: MarinaL10n.string("marina.answer.row.safeSpendAfter", defaultValue: "Safe spend after", comment: "Row label for safe spend after what-if."), value: currency(scenario.safeToSpendToday), amount: scenario.safeToSpendToday),
                        HomeAnswerRow(title: MarinaL10n.string("marina.answer.row.periodRoomAfter", defaultValue: "Period room after", comment: "Row label for period room after what-if."), value: currency(scenario.periodRemainingRoom), amount: scenario.periodRemainingRoom),
                        HomeAnswerRow(title: MarinaL10n.common("status", defaultValue: "Status", comment: "Common label for status."), value: scenario.periodRemainingRoom > 0 ? MarinaL10n.string("marina.answer.status.stillAboveZero", defaultValue: "Still above zero", comment: "Status for a what-if result still above zero.") : MarinaL10n.string("marina.answer.status.wouldGoToZero", defaultValue: "Would go to zero", comment: "Status for a what-if result going to zero."))
                    ]
                )
            }
            let baseline = plan.measure == .savingsTotal
                ? projectedSavings(snapshot: snapshot, range: plan.dateRange)
                : budgetRoom(snapshot: snapshot, range: plan.dateRange)
            let scenario = baseline - amount
            return MarinaExecutionResult(
                kind: .comparison,
                title: MarinaL10n.common("whatIf", defaultValue: "What If", comment: "Common label for what-if scenarios."),
                subtitle: rangeLabel(plan.dateRange),
                primaryValue: currency(scenario),
                rows: [
                    HomeAnswerRow(title: MarinaL10n.string("marina.answer.row.currentRoom", defaultValue: "Current room", comment: "Row label for current room before a what-if."), value: currency(baseline), amount: baseline),
                    HomeAnswerRow(title: MarinaL10n.string("marina.answer.row.virtualSpend", defaultValue: "Virtual spend", comment: "Row label for virtual spend."), value: "-\(currency(amount))", amount: -amount),
                    HomeAnswerRow(title: MarinaL10n.string("marina.answer.row.afterWhatIf", defaultValue: "After what-if", comment: "Row label for after a what-if."), value: currency(scenario), amount: scenario),
                    HomeAnswerRow(title: MarinaL10n.common("status", defaultValue: "Status", comment: "Common label for status."), value: scenario >= 0 ? MarinaL10n.string("marina.answer.status.stillAboveZero", defaultValue: "Still above zero", comment: "Status for a what-if result still above zero.") : MarinaL10n.string("marina.answer.status.wouldGoBelowZero", defaultValue: "Would go below zero", comment: "Status for a what-if result below zero."))
                ]
            )
        }

        if plan.operation == .compare {
            let currentRange = targetBudgetRange ?? plan.dateRange
            let current = totalSpend(snapshot: snapshot, range: currentRange)
            let previous = totalSpend(snapshot: snapshot, range: plan.comparisonDateRange)
            return comparisonResult(
                title: MarinaL10n.string("marina.answer.budgetPeriodComparison.title", defaultValue: "Budget Period Comparison", comment: "Marina answer title for budget period comparison."),
                subtitle: rangeLabel(currentRange),
                leftTitle: MarinaL10n.string("marina.answer.row.currentSpend", defaultValue: "Current spend", comment: "Row label for current spend."),
                leftValue: current,
                rightTitle: MarinaL10n.string("marina.answer.row.previousSpend", defaultValue: "Previous spend", comment: "Row label for previous spend."),
                rightValue: previous
            )
        }

        // Universal ownership note:
        // budgetRemainingRoom is parity-proven through universal for forecast + remainingRoom requests.
        // This HomeQuery branch remains the legacy fallback during migration.
        return executionResult(
            from: homeAnswer(
                query: HomeQuery(intent: plan.measure == .remainingRoom ? .safeSpendToday : .periodOverview, dateRange: targetBudgetRange ?? plan.dateRange),
                snapshot: snapshot,
                plan: plan
            )
        )
    }

    // MARK: - Formula answers

    private func budgetFormulaResult(
        plan: MarinaQueryPlan,
        snapshot: MarinaWorkspaceSnapshot,
        range: HomeQueryDateRange
    ) -> MarinaExecutionResult? {
        guard let measure = plan.measure else { return nil }
        let inputs = MarinaBudgetFormulaCalculator.inputs(
            snapshot: snapshot,
            range: range,
            now: plan.now,
            calendar: calendar
        )
        let progress = inputs.progress
        let actualSpend = inputs.actualSpendToDate
        let plannedSpend = inputs.plannedSpend

        switch measure {
        case .burnRate:
            guard let burnRate = MarinaBudgetFormulaCalculator.burnRate(actualSpend: actualSpend, elapsedDays: progress.elapsedDays) else {
                return noFormulaResult(title: MarinaL10n.string("marina.answer.burnRate.title", defaultValue: "Budget Pace", comment: "Marina answer title for budget pace."))
            }
            return MarinaExecutionResult(
                kind: .metric,
                title: MarinaL10n.string("marina.answer.burnRate.title", defaultValue: "Budget Pace", comment: "Marina answer title for budget pace."),
                subtitle: rangeLabel(range),
                primaryValue: currency(burnRate),
                rows: [
                    HomeAnswerRow(title: MarinaL10n.string("marina.answer.row.spentSoFar", defaultValue: "Spent so far", comment: "Row label for spend to date."), value: currency(actualSpend), amount: actualSpend),
                    HomeAnswerRow(title: MarinaL10n.string("marina.answer.row.elapsedDays", defaultValue: "Elapsed days", comment: "Row label for elapsed day count."), value: "\(progress.elapsedDays)", amount: Double(progress.elapsedDays)),
                    HomeAnswerRow(title: MarinaL10n.string("marina.answer.row.averagePerDay", defaultValue: "Average per day", comment: "Row label for average spend per day."), value: currency(burnRate), amount: burnRate)
                ]
            )
        case .projectedSpend:
            let summary = safeSpendSummary(snapshot: snapshot, plan: plan, rangeOverride: range)
            let projectedSpend = summary.actualSpendSoFar + summary.plannedSpendingRemaining
            return MarinaExecutionResult(
                kind: .metric,
                title: MarinaL10n.string("marina.answer.projectedSpend.title", defaultValue: "Projected Spend", comment: "Marina answer title for projected spend."),
                subtitle: rangeLabel(range),
                primaryValue: currency(projectedSpend),
                rows: [
                    HomeAnswerRow(title: MarinaL10n.string("marina.answer.row.actualSpendSoFar", defaultValue: "Actual spend so far", comment: "Row label for actual spend to date."), value: currency(summary.actualSpendSoFar), amount: summary.actualSpendSoFar),
                    HomeAnswerRow(title: MarinaL10n.string("marina.answer.row.plannedSpendingRemaining", defaultValue: "Planned spending remaining", comment: "Row label for remaining planned spending."), value: currency(summary.plannedSpendingRemaining), amount: summary.plannedSpendingRemaining),
                    HomeAnswerRow(title: MarinaL10n.string("marina.answer.row.projectedSpend", defaultValue: "Projected spend", comment: "Row label for budget-aware projected spend."), value: currency(projectedSpend), amount: projectedSpend)
                ]
            )
        case .safeDailySpend:
            // Universal ownership note:
            // safeDailySpend is parity-proven through universal.
            // Keep this formula branch as the legacy fallback until universal routing is promoted beyond debug.
            let summary = safeSpendSummary(snapshot: snapshot, plan: plan, rangeOverride: range)
            guard let safeDailySpend = MarinaBudgetFormulaCalculator.safeDailySpend(
                remainingRoom: summary.periodRemainingRoom,
                remainingDays: summary.daysLeftInPeriod
            ) else {
                return noFormulaResult(title: MarinaL10n.string("marina.answer.safeDailySpend.title", defaultValue: "Safe Daily Spend", comment: "Marina answer title for safe daily spend."))
            }
            return MarinaExecutionResult(
                kind: .metric,
                title: MarinaL10n.string("marina.answer.safeDailySpend.title", defaultValue: "Safe Daily Spend", comment: "Marina answer title for safe daily spend."),
                subtitle: rangeLabel(range),
                primaryValue: currency(safeDailySpend),
                rows: [
                    HomeAnswerRow(title: MarinaL10n.string("marina.answer.row.remainingRoom", defaultValue: "Remaining room", comment: "Row label for remaining budget room."), value: currency(summary.periodRemainingRoom), amount: summary.periodRemainingRoom),
                    HomeAnswerRow(title: MarinaL10n.string("marina.answer.row.remainingDays", defaultValue: "Remaining days", comment: "Row label for remaining days."), value: "\(summary.daysLeftInPeriod)", amount: Double(summary.daysLeftInPeriod)),
                    HomeAnswerRow(title: MarinaL10n.string("marina.answer.row.safePerDay", defaultValue: "Safe per day", comment: "Row label for safe daily spend."), value: currency(safeDailySpend), amount: safeDailySpend)
                ]
            )
        case .paceDifference:
            guard let paceDifference = MarinaBudgetFormulaCalculator.paceDifference(
                actualSpend: actualSpend,
                plannedSpend: plannedSpend,
                elapsedPercent: progress.elapsedPercent
            ) else {
                return noFormulaResult(title: MarinaL10n.string("marina.answer.paceDifference.title", defaultValue: "Pace Difference", comment: "Marina answer title for spend pace difference."))
            }
            let expectedByNow = plannedSpend * progress.elapsedPercent
            return MarinaExecutionResult(
                kind: .comparison,
                title: MarinaL10n.string("marina.answer.paceDifference.title", defaultValue: "Pace Difference", comment: "Marina answer title for spend pace difference."),
                subtitle: rangeLabel(range),
                primaryValue: deltaSummary(paceDifference),
                rows: [
                    HomeAnswerRow(title: MarinaL10n.string("marina.answer.row.spentSoFar", defaultValue: "Spent so far", comment: "Row label for spend to date."), value: currency(actualSpend), amount: actualSpend),
                    HomeAnswerRow(title: MarinaL10n.string("marina.answer.row.expectedByNow", defaultValue: "Expected by now", comment: "Row label for expected spend by now."), value: currency(expectedByNow), amount: expectedByNow),
                    HomeAnswerRow(title: MarinaL10n.string("marina.answer.row.paceDifference", defaultValue: "Pace difference", comment: "Row label for spend pace difference."), value: deltaSummary(paceDifference), amount: paceDifference)
                ]
            )
        case .coverageRatio:
            return coverageRatioResult(
                title: MarinaL10n.string("marina.answer.budgetCoverage.title", defaultValue: "Budget Coverage", comment: "Marina answer title for budget coverage."),
                plan: plan,
                snapshot: snapshot,
                range: range
            )
        case .amount, .plannedAmount, .actualAmount, .effectiveAmount, .budgetImpact, .savingsTotal, .incomeAmount, .reconciliationBalance, .categoryAvailability, .remainingRoom, .recurringBurden, .concentration, .color, .name:
            return nil
        }
    }

    private func coverageRatioResult(
        title: String,
        plan: MarinaQueryPlan,
        snapshot: MarinaWorkspaceSnapshot,
        range: HomeQueryDateRange? = nil
    ) -> MarinaExecutionResult {
        let targetRange = range ?? plan.dateRange
        let income = coverageIncome(snapshot: snapshot, range: targetRange)
        let plannedExpenses = plannedExpenseTotal(snapshot: snapshot, range: targetRange)
        guard let coverageRatio = MarinaBudgetFormulaCalculator.coverageRatio(
            income: income,
            plannedExpenses: plannedExpenses
        ) else {
            return noFormulaResult(title: title)
        }
        let difference = income - plannedExpenses
        return MarinaExecutionResult(
            kind: .metric,
            title: title,
            subtitle: rangeLabel(targetRange),
            primaryValue: percent(coverageRatio),
            rows: [
                HomeAnswerRow(title: MarinaL10n.common("income", defaultValue: "Income", comment: "Common label for income."), value: currency(income), amount: income),
                HomeAnswerRow(title: MarinaL10n.string("marina.answer.row.plannedExpenses", defaultValue: "Planned expenses", comment: "Row label for planned expenses."), value: currency(plannedExpenses), amount: plannedExpenses),
                HomeAnswerRow(title: MarinaL10n.string("marina.answer.row.coveragePercent", defaultValue: "Coverage percent", comment: "Row label for income coverage percent."), value: percent(coverageRatio), amount: coverageRatio),
                HomeAnswerRow(title: MarinaL10n.common("difference", defaultValue: "Difference", comment: "Common label for a difference value."), value: deltaSummary(difference), amount: difference)
            ]
        )
    }

    private func recurringBurdenResult(plan: MarinaQueryPlan, snapshot: MarinaWorkspaceSnapshot) -> MarinaExecutionResult {
        let recurringTotal = plannedExpenseTotal(snapshot: snapshot, range: plan.dateRange, recurringOnly: true)
        let plannedExpenseTotal = plannedExpenseTotal(snapshot: snapshot, range: plan.dateRange)
        guard let recurringBurden = MarinaBudgetFormulaCalculator.recurringBurden(
            recurringTotal: recurringTotal,
            plannedExpenseTotal: plannedExpenseTotal
        ) else {
            return noFormulaResult(title: MarinaL10n.string("marina.answer.recurringBurden.title", defaultValue: "Recurring Burden", comment: "Marina answer title for recurring burden."))
        }
        return MarinaExecutionResult(
            kind: .metric,
            title: MarinaL10n.string("marina.answer.recurringBurden.title", defaultValue: "Recurring Burden", comment: "Marina answer title for recurring burden."),
            subtitle: rangeLabel(plan.dateRange),
            primaryValue: percent(recurringBurden),
            rows: [
                HomeAnswerRow(title: MarinaL10n.string("marina.answer.row.recurringTotal", defaultValue: "Recurring total", comment: "Row label for recurring planned expenses."), value: currency(recurringTotal), amount: recurringTotal),
                HomeAnswerRow(title: MarinaL10n.string("marina.answer.row.plannedExpenses", defaultValue: "Planned expenses", comment: "Row label for planned expenses."), value: currency(plannedExpenseTotal), amount: plannedExpenseTotal),
                HomeAnswerRow(title: MarinaL10n.string("marina.answer.row.recurringBurden", defaultValue: "Recurring burden", comment: "Row label for recurring burden percentage."), value: percent(recurringBurden), amount: recurringBurden)
            ]
        )
    }

    private func categoryConcentrationResult(plan: MarinaQueryPlan, snapshot: MarinaWorkspaceSnapshot) -> MarinaExecutionResult {
        let totals = totalsByCategory(snapshot: snapshot, range: plan.dateRange)
        let wholeTotal = totals.values.reduce(0.0, +)
        let selected: (name: String, total: Double)?

        if let targetName = plan.targetName {
            guard let category = resolveCategory(named: targetName, in: snapshot) else {
                return unsupported(.unresolvedEntity)
            }
            selected = (category.name, totals[category.name] ?? 0)
        } else {
            selected = totals.max { left, right in left.value < right.value }.map { ($0.key, $0.value) }
        }

        guard let selected,
              let concentration = MarinaBudgetFormulaCalculator.concentration(
                partTotal: selected.total,
                wholeTotal: wholeTotal
              ) else {
            return noFormulaResult(title: MarinaL10n.string("marina.answer.concentration.title", defaultValue: "Category Spend Share", comment: "Marina answer title for category spend share."))
        }

        let rankedRows = totals
            .sorted { left, right in left.value > right.value }
            .prefix(plan.resultLimit)
            .compactMap { name, total -> HomeAnswerRow? in
                guard let share = MarinaBudgetFormulaCalculator.concentration(
                    partTotal: total,
                    wholeTotal: wholeTotal
                ) else {
                    return nil
                }
                return HomeAnswerRow(
                    title: name,
                    value: "\(currency(total)) - \(percent(share))",
                    amount: total
                )
            }

        return MarinaExecutionResult(
            kind: .metric,
            title: MarinaL10n.string("marina.answer.concentration.title", defaultValue: "Category Spend Share", comment: "Marina answer title for category spend share."),
            subtitle: rangeLabel(plan.dateRange),
            primaryValue: percent(concentration),
            rows: rankedRows + [
                HomeAnswerRow(title: MarinaL10n.common("category", defaultValue: "Category", comment: "Common label for category."), value: selected.name),
                HomeAnswerRow(title: MarinaL10n.string("marina.answer.row.categorySpend", defaultValue: "Category spend", comment: "Row label for category spend."), value: currency(selected.total), amount: selected.total),
                HomeAnswerRow(title: MarinaL10n.string("marina.answer.row.totalSpend", defaultValue: "Total spend", comment: "Row label for total spend."), value: currency(wholeTotal), amount: wholeTotal),
                HomeAnswerRow(title: MarinaL10n.string("marina.answer.row.concentration", defaultValue: "Concentration", comment: "Row label for budget concentration percentage."), value: percent(concentration), amount: concentration)
            ]
        )
    }

    private func noFormulaResult(title: String) -> MarinaExecutionResult {
        MarinaExecutionResult(
            kind: .message,
            title: title,
            subtitle: MarinaL10n.string("marina.answer.formula.insufficientData", defaultValue: "Not enough budget data to calculate this yet.", comment: "Empty state when a Marina formula cannot be calculated.")
        )
    }

    // MARK: - Expenses

    private func expenseResult(plan: MarinaQueryPlan, snapshot: MarinaWorkspaceSnapshot) -> MarinaExecutionResult {
        if plan.operation == .next, plan.entity == .plannedExpense {
            // Universal ownership note:
            // nextPlannedExpense is parity-proven through universal.
            // Keep this branch as the legacy fallback until universal routing is promoted beyond debug.
            return executionResult(
                from: homeAnswer(
                    query: HomeQuery(
                        intent: .nextPlannedExpense,
                        dateRange: plan.dateRange,
                        targetName: plan.dimensions.contains(.card) ? plan.targetName : nil
                    ),
                    snapshot: snapshot,
                    plan: plan,
                    plannedExpenses: snapshot.homePlannedExpenses
                )
            )
        }

        // Universal ownership note:
        // unifiedExpenseCategoryGroups and unifiedExpenseCardGroups are parity-proven through universal.
        // Other grouped expense shapes remain legacy-owned for now.
        if plan.operation == .group, plan.dimensions.contains(.category) {
            return executionResult(
                from: homeAnswer(
                    query: HomeQuery(intent: .spendTrendsSummary, dateRange: plan.dateRange, resultLimit: plan.resultLimit),
                    snapshot: snapshot,
                    plan: plan
                )
            )
        }

        let rows = filteredExpenseRows(plan: plan, snapshot: snapshot)

        if plan.operation == .last {
            // Universal ownership note:
            // latestVariableExpense is parity-proven through universal for unfiltered variable expense latest-row requests.
            // This branch remains the legacy fallback for all expense latest-row shapes.
            let matching = rows.sorted { $0.date > $1.date }
            guard let row = matching.first else {
                if let textQuery = plan.semanticRequest.textQuery {
                    return expenseTextNoResultsResult(textQuery: textQuery, plan: plan, snapshot: snapshot)
                }
                return noRowsResult(title: MarinaL10n.string("marina.answer.noExpensesFound.title", defaultValue: "No Expenses Found", comment: "Marina answer title when no expenses match."), plan: plan)
            }
            return MarinaExecutionResult(
                kind: .metric,
                title: MarinaL10n.format("marina.answer.lastTarget.title", defaultValue: "Last %@", comment: "Marina answer title for last matching target.", expenseTargetTitle(plan: plan, fallback: MarinaL10n.common("expense", defaultValue: "Expense", comment: "Common label for expense."))),
                primaryValue: shortDate(row.date),
                rows: [
                    HomeAnswerRow(title: row.title, value: currency(row.budgetImpact), sourceID: row.id, amount: row.budgetImpact, date: row.date)
                ]
            )
        }

        if plan.operation == .sum {
            // Universal ownership note:
            // merchantVariableSpend, categoryVariableSpend, cardVariableSpend, and plannedExpenseSum are
            // parity-proven through universal for their exact Phase 14 semantic shapes.
            if rows.isEmpty, let textQuery = plan.semanticRequest.textQuery {
                return expenseTextNoResultsResult(textQuery: textQuery, plan: plan, snapshot: snapshot)
            }
            let total = rows.reduce(0.0) { $0 + $1.budgetImpact }
            return MarinaExecutionResult(
                kind: .metric,
                title: MarinaL10n.format("marina.answer.namedSpend.title", defaultValue: "%@ Spend", comment: "Marina answer title for spend on a named target.", expenseTargetTitle(plan: plan, fallback: MarinaL10n.common("expense", defaultValue: "Expense", comment: "Common label for expense."))),
                subtitle: rangeLabel(plan.dateRange),
                primaryValue: currency(total),
                rows: [
                    HomeAnswerRow(title: MarinaL10n.common("total", defaultValue: "Total", comment: "Common label for totals."), value: currency(total), amount: total)
                ]
            )
        }

        if plan.operation == .average {
            if rows.isEmpty, let textQuery = plan.semanticRequest.textQuery {
                return expenseTextNoResultsResult(textQuery: textQuery, plan: plan, snapshot: snapshot)
            }
            let total = rows.reduce(0.0) { $0 + $1.budgetImpact }
            let average = rows.isEmpty ? 0 : total / Double(rows.count)
            return MarinaExecutionResult(
                kind: .metric,
                title: MarinaL10n.format("marina.answer.namedAverage.title", defaultValue: "%@ Average", comment: "Marina answer title for an average on a named target.", expenseTargetTitle(plan: plan, fallback: MarinaL10n.common("expense", defaultValue: "Expense", comment: "Common label for expense."))),
                subtitle: rangeLabel(plan.dateRange),
                primaryValue: currency(average),
                rows: [
                    HomeAnswerRow(title: MarinaL10n.common("average", defaultValue: "Average", comment: "Common label for averages."), value: currency(average), amount: average),
                    HomeAnswerRow(title: MarinaL10n.common("rows", defaultValue: "Rows", comment: "Common label for rows."), value: "\(rows.count)")
                ]
            )
        }

        if plan.operation == .count {
            return MarinaExecutionResult(
                kind: .metric,
                title: MarinaL10n.format("marina.answer.namedCount.title", defaultValue: "%@ Count", comment: "Marina answer title for a count on a named target.", expenseTargetTitle(plan: plan, fallback: MarinaL10n.common("expense", defaultValue: "Expense", comment: "Common label for expense."))),
                subtitle: rangeLabel(plan.dateRange),
                primaryValue: "\(rows.count)",
                rows: [
                    HomeAnswerRow(title: MarinaL10n.common("rows", defaultValue: "Rows", comment: "Common label for rows."), value: "\(rows.count)")
                ]
            )
        }

        if rows.isEmpty, let textQuery = plan.semanticRequest.textQuery {
            return expenseTextNoResultsResult(textQuery: textQuery, plan: plan, snapshot: snapshot)
        }

        // Universal ownership note:
        // biggestVariableExpenseRows is parity-proven through universal for amount-descending variable expense lists.
        // This branch remains the legacy fallback for all expense list shapes.
        let answerRows = sortedExpenseRows(rows, sort: plan.semanticRequest.sort)
            .prefix(plan.resultLimit)
            .map { row in
                HomeAnswerRow(
                    title: row.title,
                    value: MarinaL10n.format("marina.answer.amountDate.valueFormat", defaultValue: "%@ • %@", comment: "Row value with amount and date.", currency(row.budgetImpact), shortDate(row.date)),
                    sourceID: row.id,
                    objectType: row.objectType,
                    amount: row.budgetImpact,
                    date: row.date
                )
            }
        return listResult(
            title: MarinaL10n.format("marina.answer.namedExpenses.title", defaultValue: "%@ Expenses", comment: "Marina answer title for expenses on a named target.", expenseTargetTitle(plan: plan, fallback: MarinaL10n.common("recent", defaultValue: "Recent", comment: "Common label for recent items."))),
            subtitle: rangeLabel(plan.dateRange),
            rows: answerRows
        )
    }

    // MARK: - Shared result helpers

    private func listResult<S: Sequence>(title: String, subtitle: String? = nil, rows: S) -> MarinaExecutionResult where S.Element == HomeAnswerRow {
        let materializedRows = Array(rows)
        return MarinaExecutionResult(
            kind: materializedRows.isEmpty ? .message : .list,
            title: title,
            subtitle: subtitle,
            rows: materializedRows
        )
    }

    private func comparisonResult(
        title: String,
        subtitle: String?,
        leftTitle: String,
        leftValue: Double,
        rightTitle: String,
        rightValue: Double
    ) -> MarinaExecutionResult {
        let delta = leftValue - rightValue
        return MarinaExecutionResult(
            kind: .comparison,
            title: title,
            subtitle: subtitle,
            primaryValue: deltaSummary(delta),
            rows: [
                HomeAnswerRow(title: leftTitle, value: currency(leftValue), amount: leftValue),
                HomeAnswerRow(title: rightTitle, value: currency(rightValue), amount: rightValue),
                HomeAnswerRow(title: MarinaL10n.common("difference", defaultValue: "Difference", comment: "Common label for a difference value."), value: deltaSummary(delta), amount: delta)
            ]
        )
    }

    private func clarification(plan: MarinaQueryPlan, snapshot: MarinaWorkspaceSnapshot) -> MarinaExecutionResult {
        let question = plan.semanticRequest.clarificationQuestion ?? MarinaL10n.string("marina.clarification.defaultQuestion", defaultValue: "Can you clarify what you want Marina to look up?", comment: "Default Marina clarification question.")
        return MarinaExecutionResult(
            kind: .message,
            title: MarinaL10n.string("marina.clarification.title", defaultValue: "Can you clarify?", comment: "Marina clarification answer title."),
            subtitle: question,
            attachment: (plan.clarificationChoices ?? clarificationChoices(for: plan, snapshot: snapshot)).map(MarinaAttachment.clarificationChoices)
        )
    }

    private func clarification(_ question: String) -> MarinaExecutionResult {
        MarinaExecutionResult(
            kind: .message,
            title: MarinaL10n.string("marina.clarification.title", defaultValue: "Can you clarify?", comment: "Marina clarification answer title."),
            subtitle: question
        )
    }

    private func unsupported(_ reason: MarinaSemanticUnsupportedReason) -> MarinaExecutionResult {
        let title: String
        let subtitle: String?
        switch reason {
        case .readOnly:
            title = MarinaL10n.string("marina.unsupported.title", defaultValue: "I can't answer that yet", comment: "Marina unsupported answer title.")
            subtitle = MarinaL10n.string("marina.unsupported.readOnly", defaultValue: "I'm read-only in this rebuild. I can answer questions, but I will not edit, move, or delete records from free text.", comment: "Unsupported message for read-only Marina free-text mutations.")
        case .unavailableModel:
            title = MarinaL10n.string("marina.unsupported.title", defaultValue: "I can't answer that yet", comment: "Marina unsupported answer title.")
            subtitle = MarinaL10n.string("marina.unsupported.unavailableModel", defaultValue: "My on-device language model is not available on this device or OS yet. The create menu still works.", comment: "Unsupported message when Foundation Models are unavailable.")
        case .unsupportedCombination:
            title = MarinaL10n.string("marina.unsupported.title", defaultValue: "I can't answer that yet", comment: "Marina unsupported answer title.")
            subtitle = MarinaL10n.string("marina.unsupported.unsupportedCombination", defaultValue: "I do not know how to answer that shape of budgeting question yet.", comment: "Unsupported message for an unsupported Marina query shape.")
        case .unresolvedEntity:
            title = MarinaL10n.string("marina.unsupported.title", defaultValue: "I can't answer that yet", comment: "Marina unsupported answer title.")
            subtitle = MarinaL10n.string("marina.unsupported.unresolvedEntity", defaultValue: "I could not find a matching record in this workspace.", comment: "Unsupported message when no matching workspace record is found.")
        case .ambiguousEntity:
            title = MarinaL10n.string("marina.unsupported.title", defaultValue: "I can't answer that yet", comment: "Marina unsupported answer title.")
            subtitle = MarinaL10n.string("marina.unsupported.ambiguousEntity", defaultValue: "That request could mean more than one thing.", comment: "Unsupported message for ambiguous Marina request.")
        case .modelContextLimit:
            title = MarinaL10n.string("marina.unsupported.title", defaultValue: "I can't answer that yet", comment: "Marina unsupported answer title.")
            subtitle = MarinaL10n.string("marina.unsupported.modelContextLimit", defaultValue: "That request was too large for the on-device language model. Try asking a shorter question.", comment: "Unsupported message for model context limit.")
        case .modelGuardrail:
            title = MarinaL10n.string("marina.unsupported.title", defaultValue: "I can't answer that yet", comment: "Marina unsupported answer title.")
            subtitle = MarinaL10n.string("marina.unsupported.modelGuardrail", defaultValue: "My on-device language model declined that request. I can still answer ordinary read-only budgeting questions.", comment: "Unsupported message when model guardrails decline.")
        case .modelGenerationFailed:
            title = MarinaL10n.string("marina.unsupported.title", defaultValue: "I can't answer that yet", comment: "Marina unsupported answer title.")
            subtitle = MarinaL10n.string("marina.unsupported.modelGenerationFailed", defaultValue: "My on-device language model could not produce a usable budgeting request. I did not guess.", comment: "Unsupported message when model generation fails.")
        case .unsupportedLanguageOrLocale:
            title = MarinaL10n.string("marina.unsupported.title", defaultValue: "I can't answer that yet", comment: "Marina unsupported answer title.")
            subtitle = MarinaL10n.string("marina.unsupported.languageOrLocale", defaultValue: "My on-device language model does not support that language or locale yet.", comment: "Unsupported message when model language or locale is unsupported.")
        case .incomeSavingsWhatIfUnsupported:
            title = MarinaL10n.string("marina.unsupported.incomeSavingsWhatIf.title", defaultValue: "I can see the scenario amount, but I don't support income or savings replacement what-if calculations yet.", comment: "Unsupported title for income or savings replacement what-if scenarios.")
            subtitle = nil
        }
        return MarinaExecutionResult(
            kind: .message,
            title: title,
            subtitle: subtitle
        )
    }

    private func executionResult(from answer: HomeAnswer) -> MarinaExecutionResult {
        let answer = MarinaHomeAnswerLocalizer.localized(answer)
        return MarinaExecutionResult(
            kind: answer.kind,
            title: answer.title,
            subtitle: answer.subtitle,
            primaryValue: answer.primaryValue,
            rows: answer.rows,
            attachment: answer.attachment,
            explanation: answer.explanation
        )
    }

    private func homeAnswer(
        query: HomeQuery,
        snapshot: MarinaWorkspaceSnapshot,
        plan: MarinaQueryPlan,
        plannedExpenses: [PlannedExpense]? = nil,
        variableExpenses: [VariableExpense]? = nil
    ) -> HomeAnswer {
        homeEngine.execute(
            query: query,
            budgets: snapshot.budgets,
            categories: snapshot.categories,
            presets: snapshot.presets,
            plannedExpenses: plannedExpenses ?? snapshot.homeCalculationPlannedExpenses,
            variableExpenses: variableExpenses ?? snapshot.homeCalculationVariableExpenses,
            incomes: snapshot.incomes,
            savingsEntries: snapshot.savingsEntries,
            now: plan.now
        )
    }

    private func expenseTextNoResultsResult(
        textQuery: String,
        plan: MarinaQueryPlan,
        snapshot: MarinaWorkspaceSnapshot
    ) -> MarinaExecutionResult {
        MarinaExecutionResult(
            kind: .message,
            title: MarinaL10n.string("marina.answer.noResultsFound.title", defaultValue: "No Results Found", comment: "Marina answer title when no results are found."),
            subtitle: MarinaL10n.format("marina.answer.noExpenseTextResults.subtitle", defaultValue: "I could not find any expenses or title/description text matching \"%@\" for this range.", comment: "No-results subtitle for expense title/description text search.", textQuery),
            rows: [
                HomeAnswerRow(title: MarinaL10n.common("search", defaultValue: "Search", comment: "Common label for search text."), value: textQuery),
                HomeAnswerRow(title: MarinaL10n.common("scope", defaultValue: "Scope", comment: "Common label for search scope."), value: MarinaL10n.string("marina.answer.scope.expenseText", defaultValue: "Expense text", comment: "Scope value for searching expense text.")),
                HomeAnswerRow(title: MarinaL10n.string("marina.answer.row.dateRange", defaultValue: "Date range", comment: "Row label for date range."), value: rangeLabel(plan.dateRange))
            ],
            attachment: merchantCardFollowUpChoices(for: textQuery, plan: plan, snapshot: snapshot).map(MarinaAttachment.clarificationChoices)
        )
    }

    private func noRowsResult(title: String, plan: MarinaQueryPlan) -> MarinaExecutionResult {
        MarinaExecutionResult(
            kind: .message,
            title: title,
            subtitle: rangeLabel(plan.dateRange),
            rows: [
                HomeAnswerRow(title: MarinaL10n.string("marina.answer.row.dateRange", defaultValue: "Date range", comment: "Row label for date range."), value: rangeLabel(plan.dateRange))
            ]
        )
    }

    private func clarificationChoices(
        for plan: MarinaQueryPlan,
        snapshot: MarinaWorkspaceSnapshot
    ) -> MarinaClarificationChoices? {
        guard let textQuery = plan.semanticRequest.textQuery ?? plan.semanticRequest.targetName else {
            return nil
        }
        let matchingCard = cardMatchingMerchantText(textQuery, snapshot: snapshot)
        guard matchingCard != nil || plan.semanticRequest.clarificationQuestion?.localizedCaseInsensitiveContains("merchant") == true else {
            return nil
        }

        let expenseDisplay = expenseTextChoiceDisplay(for: textQuery, plan: plan, snapshot: snapshot)
        var choices: [MarinaClarificationChoice] = [
            MarinaClarificationChoice(
                title: expenseDisplay.title,
                kindLabel: expenseDisplay.kindLabel,
                subtitle: MarinaL10n.format("marina.clarification.searchExpenseTextFormat", defaultValue: "Search expense titles and descriptions for %@.", comment: "Clarification choice subtitle for searching expense text.", textQuery),
                aliases: ["merchant", "store", "vendor"],
                request: merchantSpendRequest(
                    textQuery: textQuery,
                    displayName: expenseDisplay.title,
                    dateRangeToken: plan.semanticRequest.dateRangeToken
                )
            )
        ]

        if let matchingCard {
            choices.append(
                MarinaClarificationChoice(
                    title: matchingCard.name,
                    kindLabel: MarinaL10n.common("card", defaultValue: "Card", comment: "Common label for card."),
                    subtitle: MarinaL10n.format("marina.clarification.useAsCardFormat", defaultValue: "Use %@ as the card.", comment: "Clarification choice subtitle for using a card.", matchingCard.name),
                    aliases: ["card", matchingCard.name, "apple card"],
                    request: cardSpendRequest(cardName: matchingCard.name, dateRangeToken: plan.semanticRequest.dateRangeToken)
                )
            )
        }

        return MarinaClarificationChoices(
            question: plan.semanticRequest.clarificationQuestion ?? MarinaL10n.string("marina.clarification.whichMeaning", defaultValue: "Which meaning should Marina use?", comment: "Clarification question for choosing a target meaning."),
            choices: choices
        )
    }

    private func expenseTextChoiceDisplay(
        for textQuery: String,
        plan: MarinaQueryPlan,
        snapshot: MarinaWorkspaceSnapshot
    ) -> (title: String, kindLabel: String) {
        var seen: Set<String> = []
        let titles = expenseRows(
            snapshot: snapshot,
            scope: .unified,
            range: plan.dateRange
        )
            .map(\.title)
            .filter { textMatches($0, query: textQuery) }
            .compactMap { title -> String? in
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.isEmpty == false else { return nil }
                let key = canonicalText(trimmed)
                guard seen.contains(key) == false else { return nil }
                seen.insert(key)
                return trimmed
            }

        if titles.count == 1, let title = titles.first {
            return (title, MarinaL10n.string("marina.clarification.kind.expenseMatch", defaultValue: "Expense match", comment: "Kind label for a matching expense."))
        }
        if titles.isEmpty {
            return (textQuery, MarinaL10n.string("marina.clarification.kind.expenseSearch", defaultValue: "Expense search", comment: "Kind label for expense search."))
        }
        return (
            MarinaL10n.format("marina.clarification.allExpenseMatchesFormat", defaultValue: "All expense matches for \"%@\"", comment: "Clarification choice title for all expense matches.", textQuery),
            MarinaL10n.string("marina.clarification.kind.expenseSearch", defaultValue: "Expense search", comment: "Kind label for expense search.")
        )
    }

    private func merchantCardFollowUpChoices(
        for textQuery: String,
        plan: MarinaQueryPlan,
        snapshot: MarinaWorkspaceSnapshot
    ) -> MarinaClarificationChoices? {
        guard let matchingCard = cardMatchingMerchantText(textQuery, snapshot: snapshot) else { return nil }
        return MarinaClarificationChoices(
            question: MarinaL10n.format("marina.clarification.checkCardInsteadFormat", defaultValue: "Want me to check %@ instead?", comment: "Clarification question offering to check a matching card instead.", matchingCard.name),
            choices: [
                MarinaClarificationChoice(
                    title: matchingCard.name,
                    kindLabel: MarinaL10n.common("card", defaultValue: "Card", comment: "Common label for card."),
                    subtitle: MarinaL10n.format("marina.clarification.useAsCardFormat", defaultValue: "Use %@ as the card.", comment: "Clarification choice subtitle for using a card.", matchingCard.name),
                    aliases: ["card", matchingCard.name, "apple card"],
                    request: cardSpendRequest(cardName: matchingCard.name, dateRangeToken: plan.semanticRequest.dateRangeToken)
                )
            ]
        )
    }

    private func merchantSpendRequest(
        textQuery: String,
        displayName: String? = nil,
        dateRangeToken: MarinaSemanticDateRangeToken
    ) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.merchantText],
            dateRangeToken: dateRangeToken,
            textQuery: textQuery,
            targetDisplayName: displayName,
            expenseScope: .unified,
            expectedAnswerShape: .metric
        )
    }

    private func cardSpendRequest(cardName: String, dateRangeToken: MarinaSemanticDateRangeToken) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .card,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.card],
            dateRangeToken: dateRangeToken,
            targetName: cardName,
            targetDisplayName: cardName,
            expenseScope: .unified,
            expectedAnswerShape: .metric
        )
    }

    private func cardMatchingMerchantText(_ text: String, snapshot: MarinaWorkspaceSnapshot) -> Card? {
        let normalizedText = normalize(text)
        return snapshot.cards.first { normalize($0.name) == normalizedText || normalize($0.name).contains(normalizedText) }
    }

    // MARK: - Row adapters

    private struct ExpenseRow {
        let id: UUID
        let title: String
        let date: Date
        let budgetImpact: Double
        let objectType: MarinaLookupObjectType
        let cardID: UUID?
        let categoryID: UUID?
        let reconciliationAccountID: UUID?
        let reconciliationAmount: Double
    }

    private func expenseRows(
        snapshot: MarinaWorkspaceSnapshot,
        scope: MarinaSemanticExpenseScope,
        range: HomeQueryDateRange?
    ) -> [ExpenseRow] {
        var rows: [ExpenseRow] = []

        if scope == .planned || scope == .unified {
            for expense in snapshot.homeCalculationPlannedExpenses where contains(expense.expenseDate, in: range) {
                rows.append(
                    ExpenseRow(
                        id: expense.id,
                        title: expense.title,
                        date: expense.expenseDate,
                        budgetImpact: SavingsMathService.plannedBudgetImpactAmount(for: expense),
                        objectType: .plannedExpense,
                        cardID: expense.card?.id,
                        categoryID: expense.category?.id,
                        reconciliationAccountID: expense.allocation?.account?.id,
                        reconciliationAmount: max(0, expense.allocation?.allocatedAmount ?? 0)
                    )
                )
            }
        }

        if scope == .variable || scope == .unified {
            for expense in snapshot.homeCalculationVariableExpenses where contains(expense.transactionDate, in: range) {
                rows.append(
                    ExpenseRow(
                        id: expense.id,
                        title: expense.descriptionText,
                        date: expense.transactionDate,
                        budgetImpact: SavingsMathService.variableBudgetImpactAmount(for: expense),
                        objectType: .variableExpense,
                        cardID: expense.card?.id,
                        categoryID: expense.category?.id,
                        reconciliationAccountID: expense.allocation?.account?.id,
                        reconciliationAmount: max(0, expense.allocation?.allocatedAmount ?? 0)
                    )
                )
            }
        }

        return rows
    }

    private func sortedExpenseRows(_ rows: [ExpenseRow], sort: MarinaSemanticSort?) -> [ExpenseRow] {
        switch sort ?? .dateDescending {
        case .amountAscending:
            return rows.sorted { left, right in
                if left.budgetImpact != right.budgetImpact { return left.budgetImpact < right.budgetImpact }
                return left.date > right.date
            }
        case .amountDescending:
            return rows.sorted { left, right in
                if left.budgetImpact != right.budgetImpact { return left.budgetImpact > right.budgetImpact }
                return left.date > right.date
            }
        case .dateAscending:
            return rows.sorted { $0.date < $1.date }
        case .dateDescending:
            return rows.sorted { $0.date > $1.date }
        case .nameAscending:
            return rows.sorted { left, right in
                let ordered = left.title.localizedCaseInsensitiveCompare(right.title)
                if ordered != .orderedSame { return ordered == .orderedAscending }
                return left.date > right.date
            }
        }
    }

    private func sortedIncomes(_ incomes: [Income], sort: MarinaSemanticSort?) -> [Income] {
        switch sort ?? .dateDescending {
        case .amountAscending:
            return incomes.sorted { left, right in
                if left.amount != right.amount { return left.amount < right.amount }
                return left.date > right.date
            }
        case .amountDescending:
            return incomes.sorted { left, right in
                if left.amount != right.amount { return left.amount > right.amount }
                return left.date > right.date
            }
        case .dateAscending:
            return incomes.sorted { $0.date < $1.date }
        case .dateDescending:
            return incomes.sorted { $0.date > $1.date }
        case .nameAscending:
            return incomes.sorted { left, right in
                let ordered = left.source.localizedCaseInsensitiveCompare(right.source)
                if ordered != .orderedSame { return ordered == .orderedAscending }
                return left.date > right.date
            }
        }
    }

    private func categoryAvailabilityListResult(plan: MarinaQueryPlan, snapshot: MarinaWorkspaceSnapshot) -> MarinaExecutionResult {
        let range = categoryAvailabilityRange(for: plan)
        let result = HomeCategoryLimitsAggregator.build(
            budgets: snapshot.budgets,
            categories: snapshot.categories,
            plannedExpenses: snapshot.homeCalculationPlannedExpenses,
            variableExpenses: snapshot.homeCalculationVariableExpenses,
            rangeStart: range.startDate,
            rangeEnd: range.endDate
        )
        let period = categoryAvailabilityPeriodLabel(range)

        guard result.activeBudget != nil else {
            return MarinaExecutionResult(
                kind: .message,
                title: categoryAvailabilityTitle(for: plan.categoryAvailabilityFilter),
                subtitle: MarinaL10n.format("marina.answer.categoryAvailability.noBudget", defaultValue: "No budget overlaps %@.", comment: "Category availability empty state when no budget overlaps the period.", period),
                rows: [
                    HomeAnswerRow(title: MarinaL10n.common("period", defaultValue: "Period", comment: "Common label for a date period."), value: period)
                ]
            )
        }

        guard result.metrics.isEmpty == false else {
            return MarinaExecutionResult(
                kind: .message,
                title: categoryAvailabilityTitle(for: plan.categoryAvailabilityFilter),
                subtitle: MarinaL10n.format("marina.answer.categoryAvailability.noCategories", defaultValue: "No categories found for %@.", comment: "Category availability empty state when no categories are found for a period.", period),
                rows: [
                    HomeAnswerRow(title: MarinaL10n.common("period", defaultValue: "Period", comment: "Common label for a date period."), value: period)
                ]
            )
        }

        let filter = plan.categoryAvailabilityFilter ?? .all
        let rows = result.metrics
            .filter { categoryAvailabilityMetric($0, matches: filter) }
            .prefix(plan.resultLimit)
            .map { categoryAvailabilityRow(for: $0) }

        guard rows.isEmpty == false else {
            return MarinaExecutionResult(
                kind: .message,
                title: categoryAvailabilityTitle(for: filter),
                subtitle: MarinaL10n.format("marina.answer.categoryAvailability.noFilteredCategories", defaultValue: "No categories are %@ for %@.", comment: "Category availability empty state for filtered category statuses.", categoryAvailabilityEmptyStatePhrase(for: filter), period),
                rows: [
                    HomeAnswerRow(title: MarinaL10n.common("budget", defaultValue: "Budget", comment: "Common label for budget."), value: result.activeBudget?.name ?? MarinaL10n.string("marina.answer.currentBudget.fallback", defaultValue: "Current budget", comment: "Fallback current budget label.")),
                    HomeAnswerRow(title: MarinaL10n.common("period", defaultValue: "Period", comment: "Common label for a date period."), value: period)
                ]
            )
        }

        return MarinaExecutionResult(
            kind: .list,
            title: categoryAvailabilityTitle(for: filter),
            subtitle: period,
            rows: rows
        )
    }

    private func categoryAvailabilityMetric(
        _ metric: CategoryAvailabilityMetric,
        matches filter: MarinaCategoryAvailabilityFilter
    ) -> Bool {
        let status = metric.status(for: .all, nearThreshold: HomeCategoryLimitsAggregator.defaultNearThreshold)
        switch filter {
        case .all:
            return true
        case .over:
            return metric.isLimited && status == .over
        case .near:
            return metric.isLimited && status == .near
        case .underLimit:
            return metric.isLimited && status != .over
        }
    }

    private func categoryAvailabilityRow(for metric: CategoryAvailabilityMetric) -> HomeAnswerRow {
        let value: String
        if let maxAmount = metric.maxAmount {
            let available = metric.availableRaw(for: .all) ?? 0
            let availability = available < 0
                ? MarinaL10n.format("marina.answer.categoryAvailability.overAmount", defaultValue: "Over %@", comment: "Category availability value for amount over limit.", currency(abs(available)))
                : MarinaL10n.format("marina.answer.categoryAvailability.remainingAmount", defaultValue: "Remaining %@", comment: "Category availability value for remaining amount.", currency(available))
            value = MarinaL10n.format("marina.answer.categoryAvailability.limitedValue", defaultValue: "%@ • Spent %@ of %@", comment: "Category availability row value for limited category.", availability, currency(metric.spentTotal), currency(maxAmount))
        } else {
            value = MarinaL10n.format("marina.answer.categoryAvailability.unlimitedValue", defaultValue: "Unlimited • Spent %@", comment: "Category availability row value for unlimited category.", currency(metric.spentTotal))
        }

        return HomeAnswerRow(
            title: metric.name,
            value: value,
            sourceID: metric.categoryID,
            objectType: .category,
            amount: metric.spentTotal
        )
    }

    private func categoryAvailabilityTitle(for filter: MarinaCategoryAvailabilityFilter?) -> String {
        switch filter ?? .all {
        case .all:
            return MarinaL10n.string("marina.answer.categoryAvailability.title", defaultValue: "Category Availability", comment: "Marina answer title for category availability.")
        case .over:
            return MarinaL10n.string("marina.answer.categoriesOverLimit.title", defaultValue: "Categories Over Limit", comment: "Marina answer title for categories over limit.")
        case .near:
            return MarinaL10n.string("marina.answer.categoriesNearLimit.title", defaultValue: "Categories Near Limit", comment: "Marina answer title for categories near limit.")
        case .underLimit:
            return MarinaL10n.string("marina.answer.categoriesUnderLimit.title", defaultValue: "Categories Under Limit", comment: "Marina answer title for categories under limit.")
        }
    }

    private func categoryAvailabilityEmptyStatePhrase(for filter: MarinaCategoryAvailabilityFilter) -> String {
        switch filter {
        case .all:
            return MarinaL10n.string("marina.answer.categoryAvailability.empty.available", defaultValue: "available", comment: "Phrase for category availability empty state.")
        case .over:
            return MarinaL10n.string("marina.answer.categoryAvailability.empty.overLimit", defaultValue: "over limit", comment: "Phrase for category availability over-limit empty state.")
        case .near:
            return MarinaL10n.string("marina.answer.categoryAvailability.empty.nearLimit", defaultValue: "near limit", comment: "Phrase for category availability near-limit empty state.")
        case .underLimit:
            return MarinaL10n.string("marina.answer.categoryAvailability.empty.underLimit", defaultValue: "under limit", comment: "Phrase for category availability under-limit empty state.")
        }
    }

    private func categoryAvailabilityRange(for plan: MarinaQueryPlan) -> HomeQueryDateRange {
        if let range = plan.dateRange {
            return range
        }

        let range = BudgetingPeriod.monthly.defaultRange(containing: plan.now, calendar: calendar)
        return HomeQueryDateRange(startDate: range.start, endDate: range.end)
    }

    private func filteredExpenseRows(plan: MarinaQueryPlan, snapshot: MarinaWorkspaceSnapshot) -> [ExpenseRow] {
        var rows = expenseRows(
            snapshot: snapshot,
            scope: plan.semanticRequest.expenseScope ?? .unified,
            range: plan.dateRange
        )

        if plan.dimensions.contains(.merchantText), let textQuery = plan.semanticRequest.textQuery {
            rows = rows.filter { textMatches($0.title, query: textQuery) }
        }

        if plan.dimensions.contains(.card), let targetName = plan.targetName {
            guard let card = resolveCard(named: targetName, in: snapshot) else { return [] }
            rows = rows.filter { $0.cardID == card.id }
        }

        if plan.dimensions.contains(.category), let targetName = plan.targetName {
            guard let category = resolveCategory(named: targetName, in: snapshot) else { return [] }
            rows = rows.filter { $0.categoryID == category.id }
        }

        if plan.dimensions.contains(.reconciliationAccount), let targetName = plan.targetName {
            guard let account = resolveReconciliationAccount(named: targetName, in: snapshot) else { return [] }
            rows = rows.filter { $0.reconciliationAccountID == account.id }
        }

        return rows
    }

    private func expenseTargetTitle(plan: MarinaQueryPlan, fallback: String) -> String {
        if let targetDisplayName = plan.semanticRequest.targetDisplayName, targetDisplayName.isEmpty == false {
            return targetDisplayName
        }
        if plan.dimensions.contains(.merchantText), let textQuery = plan.semanticRequest.textQuery {
            return textQuery
        }
        if plan.dimensions.contains(.category), let targetName = plan.targetName {
            return targetName
        }
        if plan.dimensions.contains(.card), let targetName = plan.targetName {
            return targetName
        }
        if plan.dimensions.contains(.reconciliationAccount), let targetName = plan.targetName {
            return targetName
        }
        return fallback
    }

    // MARK: - Totals

    private struct FormulaDayProgress {
        let elapsedDays: Int
        let totalDays: Int
        let remainingDays: Int
        let elapsedPercent: Double
    }

    private func totalsByCard(snapshot: MarinaWorkspaceSnapshot, range: HomeQueryDateRange?) -> [String: Double] {
        var totals: [String: Double] = [:]
        for row in expenseRows(snapshot: snapshot, scope: .unified, range: range) {
            let name = snapshot.cards.first(where: { $0.id == row.cardID })?.name ?? MarinaL10n.string("marina.answer.noCard", defaultValue: "No Card", comment: "Fallback label when an expense has no card.")
            totals[name, default: 0] += row.budgetImpact
        }
        return totals
    }

    private func totalsByCategory(snapshot: MarinaWorkspaceSnapshot, range: HomeQueryDateRange?) -> [String: Double] {
        var totals: [String: Double] = [:]
        for row in expenseRows(snapshot: snapshot, scope: .unified, range: range) {
            let name = snapshot.categories.first(where: { $0.id == row.categoryID })?.name ?? MarinaL10n.common("uncategorized", defaultValue: "Uncategorized", comment: "Common label for uncategorized expenses.")
            totals[name, default: 0] += row.budgetImpact
        }
        return totals
    }

    private func homeCardMetrics(
        for card: Card,
        plan: MarinaQueryPlan,
        snapshot: MarinaWorkspaceSnapshot
    ) -> HomeCardMetrics {
        let range = plan.dateRange ?? HomeQueryDateRange(startDate: .distantPast, endDate: .distantFuture)
        return HomeCardMetricsCalculator.metrics(
            for: card,
            plannedExpenses: snapshot.homeCalculationPlannedExpenses,
            variableExpenses: snapshot.homeCalculationVariableExpenses,
            start: range.startDate,
            end: range.endDate,
            excludeFuturePlannedExpenses: false,
            excludeFutureVariableExpenses: false,
            now: plan.now
        )
    }

    private func totalSpend(snapshot: MarinaWorkspaceSnapshot, range: HomeQueryDateRange?) -> Double {
        expenseRows(snapshot: snapshot, scope: .unified, range: range).reduce(0.0) { $0 + $1.budgetImpact }
    }

    private func actualSpendToDate(
        snapshot: MarinaWorkspaceSnapshot,
        range: HomeQueryDateRange,
        now: Date
    ) -> Double {
        MarinaBudgetFormulaCalculator.actualSpendToDate(
            snapshot: snapshot,
            range: range,
            now: now,
            calendar: calendar
        )
    }

    private func plannedExpenseTotal(
        snapshot: MarinaWorkspaceSnapshot,
        range: HomeQueryDateRange?,
        recurringOnly: Bool = false
    ) -> Double {
        MarinaBudgetFormulaCalculator.plannedExpenseTotal(
            snapshot: snapshot,
            range: range,
            recurringOnly: recurringOnly
        )
    }

    private func coverageIncome(snapshot: MarinaWorkspaceSnapshot, range: HomeQueryDateRange?) -> Double {
        MarinaBudgetFormulaCalculator.coverageIncome(snapshot: snapshot, range: range)
    }

    private func formulaDayProgress(for range: HomeQueryDateRange, now: Date) -> FormulaDayProgress {
        let progress = MarinaBudgetFormulaCalculator.dayProgress(
            for: range,
            now: now,
            calendar: calendar
        )
        return FormulaDayProgress(
            elapsedDays: progress.elapsedDays,
            totalDays: progress.totalDays,
            remainingDays: progress.remainingDays,
            elapsedPercent: progress.elapsedPercent
        )
    }

    private func inclusiveDayCount(from start: Date, through end: Date) -> Int {
        guard end >= start else { return 0 }
        return (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
    }

    private func endOfDay(_ date: Date) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }

    private func budgetRoom(snapshot: MarinaWorkspaceSnapshot, range: HomeQueryDateRange?) -> Double {
        let actualIncome = incomeTotal(snapshot.incomes, range: range, state: .actual, source: nil)
        let plannedIncome = incomeTotal(snapshot.incomes, range: range, state: .planned, source: nil)
        let income = actualIncome > 0 ? actualIncome : plannedIncome
        return income - totalSpend(snapshot: snapshot, range: range)
    }

    private func safeSpendSummary(
        snapshot: MarinaWorkspaceSnapshot,
        plan: MarinaQueryPlan,
        virtualSpendAmount: Double = 0,
        virtualSpendCategoryID: UUID? = nil,
        rangeOverride: HomeQueryDateRange? = nil
    ) -> SafeSpendTodayCalculator.Summary {
        let range = rangeOverride ?? resolvedRange(for: plan)
        return SafeSpendTodayCalculator.calculate(
            budgetingPeriod: calendar.isDate(range.startDate, inSameDayAs: range.endDate) ? .daily : .monthly,
            rangeStart: range.startDate,
            rangeEnd: range.endDate,
            budgets: snapshot.budgets,
            categories: snapshot.categories,
            incomes: snapshot.incomes,
            plannedExpenses: snapshot.homeCalculationPlannedExpenses,
            variableExpenses: snapshot.homeCalculationVariableExpenses,
            savingsEntries: snapshot.savingsEntries,
            now: plan.now,
            calendar: calendar,
            virtualSpendAmount: virtualSpendAmount,
            virtualSpendCategoryID: virtualSpendCategoryID
        )
    }

    private func resolvedRange(for plan: MarinaQueryPlan) -> HomeQueryDateRange {
        if let dateRange = plan.dateRange {
            return dateRange
        }
        let defaultRange = BudgetingPeriod.monthly.defaultRange(containing: plan.now, calendar: calendar)
        return HomeQueryDateRange(startDate: defaultRange.start, endDate: defaultRange.end)
    }

    private func matchingCategoryID(for targetName: String?, snapshot: MarinaWorkspaceSnapshot) -> UUID? {
        guard let targetName else { return nil }
        let target = canonical(targetName)
        return snapshot.categories.first { category in
            let candidate = canonical(category.name)
            return candidate == target || candidate.contains(target) || target.contains(candidate)
        }?.id
    }

    private func canonical(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func projectedSavings(snapshot: MarinaWorkspaceSnapshot, range: HomeQueryDateRange?) -> Double {
        let plannedIncome = incomeTotal(snapshot.incomes, range: range, state: .planned, source: nil)
        let plannedExpenseTotal = snapshot.homeCalculationPlannedExpenses
            .filter { contains($0.expenseDate, in: range) }
            .reduce(0.0) { $0 + SavingsMathService.plannedProjectedBudgetImpactAmount(for: $1) }
        return plannedIncome - plannedExpenseTotal
    }

    private func reconciliationBalance(for account: AllocationAccount, range: HomeQueryDateRange?) -> Double {
        guard let range else {
            return AllocationLedgerService.balance(for: account)
        }

        return AllocationLedgerService.chargeActivity(
            for: account,
            startDate: range.startDate,
            endDate: range.endDate
        )
    }

    private func incomeTotal(
        _ incomes: [Income],
        range: HomeQueryDateRange?,
        state: MarinaSemanticIncomeState,
        source: String?
    ) -> Double {
        incomes
            .filter { contains($0.date, in: range) }
            .filter { income in
                switch state {
                case .planned:
                    return income.isPlanned
                case .actual:
                    return income.isPlanned == false
                case .all:
                    return true
                }
            }
            .filter { income in
                guard let source else { return true }
                return normalize(income.source) == normalize(source)
            }
            .reduce(0.0) { $0 + $1.amount }
    }

    // MARK: - Resolution

    private func resolveCard(named name: String, in snapshot: MarinaWorkspaceSnapshot) -> Card? {
        exactMatch(named: name, in: snapshot.cards, keyPath: \.name)
    }

    private func resolveCategory(named name: String, in snapshot: MarinaWorkspaceSnapshot) -> Category? {
        exactMatch(named: name, in: snapshot.categories, keyPath: \.name)
    }

    private func resolveReconciliationAccount(named name: String, in snapshot: MarinaWorkspaceSnapshot) -> AllocationAccount? {
        exactMatch(named: name, in: snapshot.reconciliationAccounts, keyPath: \.name)
    }

    private func resolveSavingsAccount(named name: String, in snapshot: MarinaWorkspaceSnapshot) -> SavingsAccount? {
        exactMatch(named: name, in: snapshot.savingsAccounts, keyPath: \.name)
    }

    private func resolvePreset(named name: String, in snapshot: MarinaWorkspaceSnapshot) -> Preset? {
        exactMatch(named: name, in: snapshot.presets, keyPath: \.title)
    }

    private func resolveBudget(named name: String, in snapshot: MarinaWorkspaceSnapshot) -> Budget? {
        exactMatch(named: name, in: snapshot.budgets, keyPath: \.name)
    }

    private func exactMatch<T>(named name: String, in values: [T], keyPath: KeyPath<T, String>) -> T? {
        let normalized = normalize(name)
        let matches = values.filter { normalize($0[keyPath: keyPath]) == normalized }
        if matches.count == 1 {
            return matches[0]
        }
        if matches.isEmpty {
            return values.first { normalize($0[keyPath: keyPath]).contains(normalized) }
        }
        return nil
    }

    // MARK: - Formatting

    private func contains(_ date: Date, in range: HomeQueryDateRange?) -> Bool {
        guard let range else { return true }
        return date >= range.startDate && date <= range.endDate
    }

    private func rangeLabel(_ range: HomeQueryDateRange?) -> String {
        guard let range else { return MarinaL10n.string("marina.answer.range.allTime", defaultValue: "All time", comment: "Date range label for all time.") }
        return "\(shortDate(range.startDate)) - \(shortDate(range.endDate))"
    }

    private func categoryAvailabilityPeriodLabel(_ range: HomeQueryDateRange) -> String {
        let start = calendar.startOfDay(for: range.startDate)
        let end = calendar.startOfDay(for: range.endDate)
        if let interval = calendar.dateInterval(of: .month, for: start) {
            let monthStart = calendar.startOfDay(for: interval.start)
            let monthEnd = calendar.date(byAdding: .day, value: -1, to: interval.end).map {
                calendar.startOfDay(for: $0)
            }
            if start == monthStart, end == monthEnd {
                return start.formatted(.dateTime.month(.wide).year())
            }
        }
        return "\(shortDate(range.startDate)) - \(shortDate(range.endDate))"
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private func currency(_ amount: Double) -> String {
        CurrencyFormatter.string(from: amount)
    }

    private func percent(_ ratio: Double) -> String {
        ratio.formatted(.percent.precision(.fractionLength(1)))
    }

    private func deltaSummary(_ delta: Double) -> String {
        if delta > 0 {
            return MarinaL10n.format("marina.answer.delta.up", defaultValue: "Up %@", comment: "Delta summary for an increase.", currency(delta))
        }
        if delta < 0 {
            return MarinaL10n.format("marina.answer.delta.down", defaultValue: "Down %@", comment: "Delta summary for a decrease.", currency(abs(delta)))
        }
        return MarinaL10n.string("marina.answer.delta.noChange", defaultValue: "No change", comment: "Delta summary when there is no change.")
    }

    private func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .uppercased()
    }

    private func textMatches(_ value: String, query: String) -> Bool {
        let value = canonicalText(value)
        let query = canonicalText(query)
        return value == query || value.contains(query) || query.contains(value)
    }

    private func canonicalText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "[^A-Za-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
            .split(separator: " ")
            .map { singularized($0) }
            .joined(separator: " ")
    }

    private func singularized(_ word: Substring) -> String {
        var value = String(word)
        if value.hasSuffix("ies"), value.count > 3 {
            value.removeLast(3)
            return value + "y"
        }
        if value.hasSuffix("ses") == false,
           value.hasSuffix("s"),
           value.count > 1 {
            value.removeLast()
        }
        return value
    }

    private func incomeTitle(state: MarinaSemanticIncomeState, source: String?) -> String {
        let prefix: String
        switch state {
        case .planned:
            prefix = MarinaL10n.string("marina.answer.plannedIncome.title", defaultValue: "Planned Income", comment: "Marina answer title for planned income.")
        case .actual:
            prefix = MarinaL10n.string("marina.answer.actualIncome.title", defaultValue: "Actual Income", comment: "Marina answer title for actual income.")
        case .all:
            prefix = MarinaL10n.common("income", defaultValue: "Income", comment: "Common label for income.")
        }
        guard let source else { return prefix }
        return MarinaL10n.format("marina.answer.sourceIncome.title", defaultValue: "%@ %@", comment: "Marina answer title with income source and income kind.", source, prefix)
    }
}
