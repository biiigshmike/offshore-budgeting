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
                title: "Workspace Color",
                primaryValue: snapshot.workspace.hexColor,
                rows: [
                    HomeAnswerRow(title: "Workspace", value: snapshot.workspace.name)
                ]
            )
        }

        return MarinaExecutionResult(
            kind: .metric,
            title: "Current Workspace",
            primaryValue: snapshot.workspace.name,
            rows: [
                HomeAnswerRow(title: "Color", value: snapshot.workspace.hexColor),
                HomeAnswerRow(title: "Budgets", value: "\(snapshot.budgets.count)"),
                HomeAnswerRow(title: "Cards", value: "\(snapshot.cards.count)"),
                HomeAnswerRow(title: "Categories", value: "\(snapshot.categories.count)")
            ]
        )
    }

    // MARK: - Cards

    private func cardResult(plan: MarinaQueryPlan, snapshot: MarinaWorkspaceSnapshot) -> MarinaExecutionResult {
        if plan.operation == .count {
            return MarinaExecutionResult(
                kind: .metric,
                title: "Cards",
                primaryValue: "\(snapshot.cards.count)"
            )
        }

        if plan.operation == .compare {
            guard let leftName = plan.targetName,
                  let rightName = plan.comparisonTargetName else {
                return clarification("Which two cards should I compare?")
            }
            guard let left = resolveCard(named: leftName, in: snapshot),
                  let right = resolveCard(named: rightName, in: snapshot) else {
                return unsupported(.unresolvedEntity)
            }
            let leftTotal = homeCardMetrics(for: left, plan: plan, snapshot: snapshot).total
            let rightTotal = homeCardMetrics(for: right, plan: plan, snapshot: snapshot).total
            return comparisonResult(
                title: "Card Spend Comparison",
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
                title: "Card Spend",
                subtitle: rangeLabel(plan.dateRange),
                rows: grouped.map { HomeAnswerRow(title: $0.name, value: currency($0.value), amount: $0.value) }
            )
        }

        guard let card = resolveCard(named: targetName, in: snapshot) else {
            return unsupported(.unresolvedEntity)
        }
        let metrics = homeCardMetrics(for: card, plan: plan, snapshot: snapshot)
        return MarinaExecutionResult(
            kind: .metric,
            title: "\(card.name) Spend",
            subtitle: rangeLabel(plan.dateRange),
            primaryValue: currency(metrics.total),
            rows: [
                HomeAnswerRow(title: "Planned", value: currency(metrics.plannedTotal), amount: metrics.plannedTotal),
                HomeAnswerRow(title: "Variable", value: currency(metrics.variableTotal), amount: metrics.variableTotal),
                HomeAnswerRow(title: "Total", value: currency(metrics.total), amount: metrics.total),
                HomeAnswerRow(title: "Period", value: rangeLabel(plan.dateRange))
            ]
        )
    }

    // MARK: - Categories

    private func categoryResult(plan: MarinaQueryPlan, snapshot: MarinaWorkspaceSnapshot) -> MarinaExecutionResult {
        if plan.measure == .categoryAvailability {
            return executionResult(
                from: homeAnswer(
                    query: HomeQuery(intent: .categoryAvailabilitySummary, dateRange: plan.dateRange),
                    snapshot: snapshot,
                    plan: plan
                )
            )
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
                return clarification("Which two categories should I compare?")
            }
            guard let left = resolveCategory(named: leftName, in: snapshot),
                  let right = resolveCategory(named: rightName, in: snapshot) else {
                return unsupported(.unresolvedEntity)
            }
            let rows = expenseRows(snapshot: snapshot, scope: .unified, range: plan.dateRange)
            let leftTotal = rows.filter { $0.categoryID == left.id }.reduce(0.0) { $0 + $1.budgetImpact }
            let rightTotal = rows.filter { $0.categoryID == right.id }.reduce(0.0) { $0 + $1.budgetImpact }
            return comparisonResult(
                title: "Category Spend Comparison",
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
                title: "\(category.name) Count",
                subtitle: rangeLabel(plan.dateRange),
                primaryValue: "\(rows.count)",
                rows: [HomeAnswerRow(title: "Rows", value: "\(rows.count)")]
            )
        }
        let total = rows
            .reduce(0.0) { $0 + $1.budgetImpact }
        let primaryValue = plan.operation == .average && rows.isEmpty == false ? total / Double(rows.count) : total
        return MarinaExecutionResult(
            kind: .metric,
            title: plan.operation == .average ? "\(category.name) Average" : "\(category.name) Spend",
            subtitle: rangeLabel(plan.dateRange),
            primaryValue: currency(primaryValue),
            rows: [
                HomeAnswerRow(title: plan.operation == .average ? "Average" : "Total", value: currency(primaryValue), amount: primaryValue)
            ]
        )
    }

    // MARK: - Presets

    private func presetResult(plan: MarinaQueryPlan, snapshot: MarinaWorkspaceSnapshot) -> MarinaExecutionResult {
        if plan.operation == .next {
            let planned = snapshot.homePlannedExpenses
                .filter { $0.sourcePresetID != nil }
                .filter { contains($0.expenseDate, in: plan.dateRange) && $0.expenseDate >= calendar.startOfDay(for: plan.now) }
                .sorted { $0.expenseDate < $1.expenseDate }
            guard let next = planned.first else {
                return MarinaExecutionResult(kind: .message, title: "Next Preset", subtitle: "No preset-generated planned expenses are due in this period.")
            }
            let presetName = snapshot.presets.first(where: { $0.id == next.sourcePresetID })?.title ?? next.title
            return MarinaExecutionResult(
                kind: .metric,
                title: "Next Preset Due",
                subtitle: rangeLabel(plan.dateRange),
                primaryValue: presetName,
                rows: [
                    HomeAnswerRow(title: "Amount", value: currency(next.effectiveAmount()), amount: next.effectiveAmount()),
                    HomeAnswerRow(title: "Date", value: shortDate(next.expenseDate), date: next.expenseDate)
                ]
            )
        }

        if plan.operation == .group, plan.dimensions.contains(.category) {
            let groups = Dictionary(grouping: snapshot.presets) { preset in
                preset.defaultCategory?.name ?? "Uncategorized"
            }
            let rows = groups
                .map { (name: $0.key, count: $0.value.count) }
                .sorted { $0.count > $1.count }
                .prefix(plan.resultLimit)
                .map { HomeAnswerRow(title: $0.name, value: "\($0.count)") }
            return listResult(title: "Preset Categories", subtitle: "By assigned default category", rows: rows)
        }

        if plan.measure == .actualAmount {
            let rows = snapshot.plannedExpenses
                .filter { $0.actualAmount > 0 && $0.sourcePresetID != nil && contains($0.expenseDate, in: plan.dateRange) }
                .sorted { $0.expenseDate > $1.expenseDate }
                .prefix(plan.resultLimit)
                .map { expense in
                    HomeAnswerRow(
                        title: expense.title,
                        value: "\(currency(expense.actualAmount)) • \(shortDate(expense.expenseDate))",
                        amount: expense.actualAmount,
                        date: expense.expenseDate
                    )
                }
            return listResult(title: "Actualized Presets", subtitle: rangeLabel(plan.dateRange), rows: rows)
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
            return listResult(title: "\(category.name) Presets", subtitle: "By assigned default category", rows: rows)
        }

        let rows = snapshot.presets
            .filter { $0.isArchived == false }
            .sorted { $0.plannedAmount > $1.plannedAmount }
            .prefix(plan.resultLimit)
            .map { HomeAnswerRow(title: $0.title, value: currency($0.plannedAmount), sourceID: $0.id, objectType: .preset, amount: $0.plannedAmount) }
        return listResult(title: "Presets", rows: rows)
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
                title: "\(account.name) \(category.name) Reconciliation",
                subtitle: rangeLabel(plan.dateRange),
                primaryValue: currency(total),
                rows: [
                    HomeAnswerRow(title: "Allocated spend", value: currency(total), amount: total)
                ]
            )
        }

        let total = reconciliationBalance(for: account, range: plan.dateRange)
        return MarinaExecutionResult(
            kind: .metric,
            title: "\(account.name) Balance",
            subtitle: plan.dateRange == nil ? "Current outstanding balance across all history" : rangeLabel(plan.dateRange),
            primaryValue: currency(total),
            rows: [
                HomeAnswerRow(title: "Balance", value: currency(total), amount: total)
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
            let total = account?.total ?? snapshot.savingsEntries.reduce(0.0) { $0 + $1.amount }
            return MarinaExecutionResult(
                kind: .metric,
                title: "\(account?.name ?? "Savings") Balance",
                primaryValue: currency(total),
                rows: [
                    HomeAnswerRow(title: account?.name ?? "Savings Account", value: currency(total), amount: total)
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
                title: "Income Comparison",
                subtitle: rangeLabel(plan.dateRange),
                leftTitle: "Current period",
                leftValue: current,
                rightTitle: "Previous period",
                rightValue: previous
            )
        }

        let total = incomeTotal(snapshot.incomes, range: plan.dateRange, state: plan.semanticRequest.incomeState ?? .all, source: plan.targetName)
        return MarinaExecutionResult(
            kind: .metric,
            title: incomeTitle(state: plan.semanticRequest.incomeState ?? .all, source: plan.targetName),
            subtitle: rangeLabel(plan.dateRange),
            primaryValue: currency(total),
            rows: [
                HomeAnswerRow(title: "Total", value: currency(total), amount: total)
            ]
        )
    }

    // MARK: - Budgets

    private func budgetResult(plan: MarinaQueryPlan, snapshot: MarinaWorkspaceSnapshot) -> MarinaExecutionResult {
        if plan.operation == .whatIf {
            let amount = max(0, plan.semanticRequest.whatIfAmount ?? 0)
            guard amount > 0 else {
                return clarification("What amount should I use for the what-if?")
            }
            let baseline = plan.measure == .savingsTotal
                ? projectedSavings(snapshot: snapshot, range: plan.dateRange)
                : budgetRoom(snapshot: snapshot, range: plan.dateRange)
            let scenario = baseline - amount
            return MarinaExecutionResult(
                kind: .comparison,
                title: "What If",
                subtitle: rangeLabel(plan.dateRange),
                primaryValue: currency(scenario),
                rows: [
                    HomeAnswerRow(title: "Current room", value: currency(baseline), amount: baseline),
                    HomeAnswerRow(title: "Virtual spend", value: "-\(currency(amount))", amount: -amount),
                    HomeAnswerRow(title: "After what-if", value: currency(scenario), amount: scenario),
                    HomeAnswerRow(title: "Status", value: scenario >= 0 ? "Still above zero" : "Would go below zero")
                ]
            )
        }

        if plan.operation == .compare {
            let current = totalSpend(snapshot: snapshot, range: plan.dateRange)
            let previous = totalSpend(snapshot: snapshot, range: plan.comparisonDateRange)
            return comparisonResult(
                title: "Budget Period Comparison",
                subtitle: rangeLabel(plan.dateRange),
                leftTitle: "Current spend",
                leftValue: current,
                rightTitle: "Previous spend",
                rightValue: previous
            )
        }

        return executionResult(
            from: homeAnswer(
                query: HomeQuery(intent: plan.measure == .remainingRoom ? .safeSpendToday : .periodOverview, dateRange: plan.dateRange),
                snapshot: snapshot,
                plan: plan
            )
        )
    }

    // MARK: - Expenses

    private func expenseResult(plan: MarinaQueryPlan, snapshot: MarinaWorkspaceSnapshot) -> MarinaExecutionResult {
        if plan.operation == .next, plan.entity == .plannedExpense {
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
            let matching = rows.sorted { $0.date > $1.date }
            guard let row = matching.first else {
                if let textQuery = plan.semanticRequest.textQuery {
                    return expenseTextNoResultsResult(textQuery: textQuery, plan: plan, snapshot: snapshot)
                }
                return noRowsResult(title: "No Expenses Found", plan: plan)
            }
            return MarinaExecutionResult(
                kind: .metric,
                title: "Last \(expenseTargetTitle(plan: plan, fallback: "Expense"))",
                primaryValue: shortDate(row.date),
                rows: [
                    HomeAnswerRow(title: row.title, value: currency(row.budgetImpact), sourceID: row.id, amount: row.budgetImpact, date: row.date)
                ]
            )
        }

        if plan.operation == .sum {
            if rows.isEmpty, let textQuery = plan.semanticRequest.textQuery {
                return expenseTextNoResultsResult(textQuery: textQuery, plan: plan, snapshot: snapshot)
            }
            let total = rows.reduce(0.0) { $0 + $1.budgetImpact }
            return MarinaExecutionResult(
                kind: .metric,
                title: "\(expenseTargetTitle(plan: plan, fallback: "Expense")) Spend",
                subtitle: rangeLabel(plan.dateRange),
                primaryValue: currency(total),
                rows: [
                    HomeAnswerRow(title: "Total", value: currency(total), amount: total)
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
                title: "\(expenseTargetTitle(plan: plan, fallback: "Expense")) Average",
                subtitle: rangeLabel(plan.dateRange),
                primaryValue: currency(average),
                rows: [
                    HomeAnswerRow(title: "Average", value: currency(average), amount: average),
                    HomeAnswerRow(title: "Rows", value: "\(rows.count)")
                ]
            )
        }

        if plan.operation == .count {
            return MarinaExecutionResult(
                kind: .metric,
                title: "\(expenseTargetTitle(plan: plan, fallback: "Expense")) Count",
                subtitle: rangeLabel(plan.dateRange),
                primaryValue: "\(rows.count)",
                rows: [
                    HomeAnswerRow(title: "Rows", value: "\(rows.count)")
                ]
            )
        }

        if rows.isEmpty, let textQuery = plan.semanticRequest.textQuery {
            return expenseTextNoResultsResult(textQuery: textQuery, plan: plan, snapshot: snapshot)
        }

        let answerRows = rows
            .sorted { $0.date > $1.date }
            .prefix(plan.resultLimit)
            .map { row in
                HomeAnswerRow(
                    title: row.title,
                    value: "\(currency(row.budgetImpact)) • \(shortDate(row.date))",
                    sourceID: row.id,
                    amount: row.budgetImpact,
                    date: row.date
                )
            }
        return listResult(title: "\(expenseTargetTitle(plan: plan, fallback: "Recent")) Expenses", subtitle: rangeLabel(plan.dateRange), rows: answerRows)
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
                HomeAnswerRow(title: "Difference", value: deltaSummary(delta), amount: delta)
            ]
        )
    }

    private func clarification(plan: MarinaQueryPlan, snapshot: MarinaWorkspaceSnapshot) -> MarinaExecutionResult {
        let question = plan.semanticRequest.clarificationQuestion ?? "Can you clarify what you want Marina to look up?"
        return MarinaExecutionResult(
            kind: .message,
            title: "Can you clarify?",
            subtitle: question,
            attachment: (plan.clarificationChoices ?? clarificationChoices(for: plan, snapshot: snapshot)).map(MarinaAttachment.clarificationChoices)
        )
    }

    private func clarification(_ question: String) -> MarinaExecutionResult {
        MarinaExecutionResult(kind: .message, title: "Can you clarify?", subtitle: question)
    }

    private func unsupported(_ reason: MarinaSemanticUnsupportedReason) -> MarinaExecutionResult {
        let subtitle: String
        switch reason {
        case .readOnly:
            subtitle = "Marina is read-only in this rebuild. She can answer questions, but she will not edit, move, or delete records from free text."
        case .unavailableModel:
            subtitle = "Marina's on-device language model is not available on this device or OS yet. The create menu still works."
        case .unsupportedCombination:
            subtitle = "Marina does not know how to answer that shape of budgeting question yet."
        case .unresolvedEntity:
            subtitle = "I could not find a matching record in this workspace."
        case .ambiguousEntity:
            subtitle = "That request could mean more than one thing."
        case .modelContextLimit:
            subtitle = "That request was too large for the on-device language model. Try asking a shorter question."
        case .modelGuardrail:
            subtitle = "The on-device language model declined that request. Marina can still answer ordinary read-only budgeting questions."
        case .modelGenerationFailed:
            subtitle = "The on-device language model could not produce a usable budgeting request. Marina did not guess."
        case .unsupportedLanguageOrLocale:
            subtitle = "The on-device language model does not support that language or locale for Marina yet."
        }
        return MarinaExecutionResult(kind: .message, title: "Marina cannot answer that yet", subtitle: subtitle)
    }

    private func executionResult(from answer: HomeAnswer) -> MarinaExecutionResult {
        MarinaExecutionResult(
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
            title: "No Results Found",
            subtitle: "I could not find any expenses or title/description text matching \"\(textQuery)\" for this range.",
            rows: [
                HomeAnswerRow(title: "Search", value: textQuery),
                HomeAnswerRow(title: "Scope", value: "Expense text"),
                HomeAnswerRow(title: "Date range", value: rangeLabel(plan.dateRange))
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
                HomeAnswerRow(title: "Date range", value: rangeLabel(plan.dateRange))
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
                subtitle: "Search expense titles and descriptions for \(textQuery).",
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
                    kindLabel: "Card",
                    subtitle: "Use \(matchingCard.name) as the card.",
                    aliases: ["card", matchingCard.name, "apple card"],
                    request: cardSpendRequest(cardName: matchingCard.name, dateRangeToken: plan.semanticRequest.dateRangeToken)
                )
            )
        }

        return MarinaClarificationChoices(
            question: plan.semanticRequest.clarificationQuestion ?? "Which meaning should Marina use?",
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
            return (title, "Expense match")
        }
        if titles.isEmpty {
            return (textQuery, "Expense search")
        }
        return ("All expense matches for \"\(textQuery)\"", "Expense search")
    }

    private func merchantCardFollowUpChoices(
        for textQuery: String,
        plan: MarinaQueryPlan,
        snapshot: MarinaWorkspaceSnapshot
    ) -> MarinaClarificationChoices? {
        guard let matchingCard = cardMatchingMerchantText(textQuery, snapshot: snapshot) else { return nil }
        return MarinaClarificationChoices(
            question: "Want me to check \(matchingCard.name) instead?",
            choices: [
                MarinaClarificationChoice(
                    title: matchingCard.name,
                    kindLabel: "Card",
                    subtitle: "Use \(matchingCard.name) as the card.",
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

    private func totalsByCard(snapshot: MarinaWorkspaceSnapshot, range: HomeQueryDateRange?) -> [String: Double] {
        var totals: [String: Double] = [:]
        for row in expenseRows(snapshot: snapshot, scope: .unified, range: range) {
            let name = snapshot.cards.first(where: { $0.id == row.cardID })?.name ?? "No Card"
            totals[name, default: 0] += row.budgetImpact
        }
        return totals
    }

    private func totalsByCategory(snapshot: MarinaWorkspaceSnapshot, range: HomeQueryDateRange?) -> [String: Double] {
        var totals: [String: Double] = [:]
        for row in expenseRows(snapshot: snapshot, scope: .unified, range: range) {
            let name = snapshot.categories.first(where: { $0.id == row.categoryID })?.name ?? "Uncategorized"
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

    private func budgetRoom(snapshot: MarinaWorkspaceSnapshot, range: HomeQueryDateRange?) -> Double {
        let actualIncome = incomeTotal(snapshot.incomes, range: range, state: .actual, source: nil)
        let plannedIncome = incomeTotal(snapshot.incomes, range: range, state: .planned, source: nil)
        let income = actualIncome > 0 ? actualIncome : plannedIncome
        return income - totalSpend(snapshot: snapshot, range: range)
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
        guard let range else { return "All time" }
        return "\(shortDate(range.startDate)) - \(shortDate(range.endDate))"
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private func currency(_ amount: Double) -> String {
        CurrencyFormatter.string(from: amount)
    }

    private func deltaSummary(_ delta: Double) -> String {
        if delta > 0 {
            return "Up \(currency(delta))"
        }
        if delta < 0 {
            return "Down \(currency(abs(delta)))"
        }
        return "No change"
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
            prefix = "Planned Income"
        case .actual:
            prefix = "Actual Income"
        case .all:
            prefix = "Income"
        }
        guard let source else { return prefix }
        return "\(source) \(prefix)"
    }
}
