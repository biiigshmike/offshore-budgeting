//
//  HomeQueryEngine.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/8/26.
//

import Foundation

struct HomeQueryEngine {
    private let calendar: Calendar
    private let currencyFormatter: NumberFormatter

    init(
        calendar: Calendar = .current,
        currencyFormatter: NumberFormatter? = nil
    ) {
        self.calendar = calendar

        if let currencyFormatter {
            self.currencyFormatter = currencyFormatter
        } else {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.locale = .autoupdatingCurrent
            self.currencyFormatter = formatter
        }
    }

    // MARK: - Execute

    func execute(
        query: HomeQuery,
        categories: [Category],
        presets: [Preset] = [],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        incomes: [Income] = [],
        now: Date = Date()
    ) -> HomeAnswer {
        switch query.intent {
        case .periodOverview:
            return periodOverviewAnswer(
                query: query,
                categories: categories,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                now: now
            )

        case .spendThisMonth:
            return spendThisMonthAnswer(
                query: query,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                now: now
            )

        case .topCategoriesThisMonth:
            return topCategoriesThisMonthAnswer(
                query: query,
                categories: categories,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                now: now
            )

        case .compareThisMonthToPreviousMonth:
            return compareThisMonthToPreviousMonthAnswer(
                query: query,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                now: now
            )

        case .largestRecentTransactions:
            return largestRecentTransactionsAnswer(
                query: query,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                now: now
            )

        case .cardSpendTotal:
            return cardSpendTotalAnswer(
                query: query,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                now: now
            )
        case .cardVariableSpendingHabits:
            return cardVariableSpendingHabitsAnswer(
                query: query,
                variableExpenses: variableExpenses,
                now: now
            )

        case .incomeAverageActual:
            return incomeAverageActualAnswer(
                query: query,
                incomes: incomes,
                now: now
            )
        case .savingsStatus:
            return savingsStatusAnswer(
                query: query,
                incomes: incomes,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                now: now
            )
        case .savingsAverageRecentPeriods:
            return savingsAverageRecentPeriodsAnswer(
                query: query,
                incomes: incomes,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                now: now
            )
        case .incomeSourceShare:
            return incomeSourceShareAnswer(
                query: query,
                incomes: incomes,
                now: now
            )
        case .categorySpendShare:
            return categorySpendShareAnswer(
                query: query,
                categories: categories,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                now: now
            )
        case .incomeSourceShareTrend:
            return incomeSourceShareTrendAnswer(
                query: query,
                incomes: incomes,
                now: now
            )
        case .categorySpendShareTrend:
            return categorySpendShareTrendAnswer(
                query: query,
                categories: categories,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                now: now
            )
        case .presetDueSoon:
            return presetDueSoonAnswer(
                query: query,
                presets: presets,
                plannedExpenses: plannedExpenses,
                now: now
            )
        case .presetHighestCost:
            return presetHighestCostAnswer(
                query: query,
                presets: presets
            )
        case .presetTopCategory:
            return presetTopCategoryAnswer(
                query: query,
                presets: presets
            )
        case .presetCategorySpend:
            return presetCategorySpendAnswer(
                query: query,
                presets: presets
            )
        case .categoryPotentialSavings:
            return categoryPotentialSavingsAnswer(
                query: query,
                categories: categories,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                now: now
            )
        case .categoryReallocationGuidance:
            return categoryReallocationGuidanceAnswer(
                query: query,
                categories: categories,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                now: now
            )
        }
    }

    // MARK: - Suggestions

    func defaultSuggestions() -> [HomeAssistantSuggestion] {
        [
            HomeAssistantSuggestion(
                title: "How am I doing this month?",
                query: HomeQuery(intent: .periodOverview)
            ),
            HomeAssistantSuggestion(
                title: "Spend this month",
                query: HomeQuery(intent: .spendThisMonth)
            ),
            HomeAssistantSuggestion(
                title: "Top categories this month",
                query: HomeQuery(intent: .topCategoriesThisMonth)
            ),
            HomeAssistantSuggestion(
                title: "Compare with last month",
                query: HomeQuery(intent: .compareThisMonthToPreviousMonth)
            ),
            HomeAssistantSuggestion(
                title: "Largest recent transactions",
                query: HomeQuery(intent: .largestRecentTransactions)
            ),
            HomeAssistantSuggestion(
                title: "Variable spending habits by card",
                query: HomeQuery(intent: .cardVariableSpendingHabits)
            ),
            HomeAssistantSuggestion(
                title: "Average actual income this year",
                query: HomeQuery(intent: .incomeAverageActual)
            ),
            HomeAssistantSuggestion(
                title: "How am I doing this month with savings?",
                query: HomeQuery(intent: .savingsStatus)
            ),
            HomeAssistantSuggestion(
                title: "Income share by source this month",
                query: HomeQuery(intent: .incomeSourceShare)
            ),
            HomeAssistantSuggestion(
                title: "Do I have presets due soon?",
                query: HomeQuery(intent: .presetDueSoon)
            )
        ]
    }

    // MARK: - Intent handlers

    private func periodOverviewAnswer(
        query: HomeQuery,
        categories: [Category],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        now: Date
    ) -> HomeAnswer {
        let range = query.dateRange ?? monthRange(containing: now)
        let previousRange: HomeQueryDateRange = query.dateRange == nil
            ? previousMonthRange(before: range.startDate)
            : previousEquivalentRange(matching: range)

        let plannedTotal = sumPlannedExpenses(plannedExpenses, in: range)
        let variableTotal = sumVariableExpenses(variableExpenses, in: range)
        let total = plannedTotal + variableTotal

        let previousTotal = totalSpend(
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            range: previousRange
        )
        let delta = total - previousTotal
        let status = periodStatusLabel(
            total: total,
            previousTotal: previousTotal,
            delta: delta
        )

        let metrics = HomeCategoryMetricsCalculator.calculate(
            categories: categories,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            rangeStart: range.startDate,
            rangeEnd: range.endDate
        ).metrics

        if total == 0 {
            return HomeAnswer(
                queryID: query.id,
                kind: .message,
                title: "Budget Overview",
                subtitle: "No spending in this range yet.",
                primaryValue: nil,
                rows: [
                    HomeAnswerRow(title: "Range", value: rangeLabel(for: range))
                ]
            )
        }

        var rows: [HomeAnswerRow] = [
            HomeAnswerRow(title: "Total spend", value: currency(total)),
            HomeAnswerRow(title: "Planned", value: currency(plannedTotal)),
            HomeAnswerRow(title: "Variable", value: currency(variableTotal)),
            HomeAnswerRow(title: "Change vs previous period", value: deltaSummary(delta)),
            HomeAnswerRow(title: "Status", value: status)
        ]

        if let topCategory = metrics.first {
            rows.append(
                HomeAnswerRow(
                    title: "Top category",
                    value: "\(topCategory.categoryName) (\(currency(topCategory.totalSpent)))"
                )
            )
        }

        if let largestTransaction = largestTransaction(in: range, plannedExpenses: plannedExpenses, variableExpenses: variableExpenses) {
            rows.append(
                HomeAnswerRow(
                    title: "Largest transaction",
                    value: "\(largestTransaction.title) (\(currency(largestTransaction.amount)))"
                )
            )
        }

        return HomeAnswer(
            queryID: query.id,
            kind: .list,
            title: "Budget Overview",
            subtitle: rangeLabel(for: range),
            primaryValue: currency(total),
            rows: rows
        )
    }

    private func spendThisMonthAnswer(
        query: HomeQuery,
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        now: Date
    ) -> HomeAnswer {
        let range = query.dateRange ?? monthRange(containing: now)
        let total = totalSpend(
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            range: range
        )

        return HomeAnswer(
            queryID: query.id,
            kind: .metric,
            title: "Spend This Month",
            subtitle: rangeLabel(for: range),
            primaryValue: currency(total),
            rows: [
                HomeAnswerRow(title: "Total", value: currency(total))
            ]
        )
    }

    private func topCategoriesThisMonthAnswer(
        query: HomeQuery,
        categories: [Category],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        now: Date
    ) -> HomeAnswer {
        let range = query.dateRange ?? monthRange(containing: now)
        let metrics = HomeCategoryMetricsCalculator.calculate(
            categories: categories,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            rangeStart: range.startDate,
            rangeEnd: range.endDate
        ).metrics

        let rows = Array(metrics.prefix(query.resultLimit)).map { metric in
            HomeAnswerRow(title: metric.categoryName, value: currency(metric.totalSpent))
        }

        if rows.isEmpty {
            return HomeAnswer(
                queryID: query.id,
                kind: .message,
                title: "Top Categories This Month",
                subtitle: "No spending in this range yet.",
                primaryValue: nil,
                rows: []
            )
        }

        return HomeAnswer(
            queryID: query.id,
            kind: .list,
            title: "Top Categories This Month",
            subtitle: rangeLabel(for: range),
            primaryValue: nil,
            rows: rows
        )
    }

    private func compareThisMonthToPreviousMonthAnswer(
        query: HomeQuery,
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        now: Date
    ) -> HomeAnswer {
        let currentRange = query.dateRange ?? monthRange(containing: now)
        let previousRange: HomeQueryDateRange
        if query.dateRange == nil {
            previousRange = previousMonthRange(before: currentRange.startDate)
        } else {
            previousRange = previousEquivalentRange(matching: currentRange)
        }

        let currentTotal = totalSpend(
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            range: currentRange
        )
        let previousTotal = totalSpend(
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            range: previousRange
        )

        let delta = currentTotal - previousTotal
        let deltaLabel: String
        if delta > 0 {
            deltaLabel = "Up \(currency(delta))"
        } else if delta < 0 {
            deltaLabel = "Down \(currency(abs(delta)))"
        } else {
            deltaLabel = "No change"
        }

        let currentLabel = query.dateRange == nil ? monthTitle(containing: currentRange.startDate) : rangeLabel(for: currentRange)
        let previousLabel = query.dateRange == nil ? monthTitle(containing: previousRange.startDate) : rangeLabel(for: previousRange)

        return HomeAnswer(
            queryID: query.id,
            kind: .comparison,
            title: query.dateRange == nil ? "This Month vs Last Month" : "Current Period vs Previous Period",
            subtitle: deltaLabel,
            primaryValue: currency(currentTotal),
            rows: [
                HomeAnswerRow(title: currentLabel, value: currency(currentTotal)),
                HomeAnswerRow(title: previousLabel, value: currency(previousTotal))
            ]
        )
    }

    private func largestRecentTransactionsAnswer(
        query: HomeQuery,
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        now: Date
    ) -> HomeAnswer {
        let range = query.dateRange ?? monthRange(containing: now)

        var entries: [(title: String, amount: Double)] = []
        entries.reserveCapacity(plannedExpenses.count + variableExpenses.count)

        for expense in plannedExpenses {
            guard expense.expenseDate >= range.startDate, expense.expenseDate <= range.endDate else { continue }
            entries.append((title: expense.title, amount: expense.effectiveAmount()))
        }

        for expense in variableExpenses {
            guard expense.transactionDate >= range.startDate, expense.transactionDate <= range.endDate else { continue }
            entries.append((title: expense.descriptionText, amount: expense.amount))
        }

        let rows = entries
            .sorted { $0.amount > $1.amount }
            .prefix(query.resultLimit)
            .map { HomeAnswerRow(title: $0.title, value: currency($0.amount)) }

        if rows.isEmpty {
            return HomeAnswer(
                queryID: query.id,
                kind: .message,
                title: "Largest Recent Transactions",
                subtitle: "No transactions found in this range.",
                primaryValue: nil,
                rows: []
            )
        }

        return HomeAnswer(
            queryID: query.id,
            kind: .list,
            title: "Largest Recent Transactions",
            subtitle: rangeLabel(for: range),
            primaryValue: nil,
            rows: rows
        )
    }

    private func cardSpendTotalAnswer(
        query: HomeQuery,
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        now: Date
    ) -> HomeAnswer {
        let range = query.dateRange ?? monthRange(containing: now)
        let cardName = query.targetName?.lowercased()

        let plannedFiltered = plannedExpenses.filter { expense in
            guard expense.expenseDate >= range.startDate, expense.expenseDate <= range.endDate else { return false }
            guard let cardName else { return true }
            return expense.card?.name.lowercased() == cardName
        }

        let variableFiltered = variableExpenses.filter { expense in
            guard expense.transactionDate >= range.startDate, expense.transactionDate <= range.endDate else { return false }
            guard let cardName else { return true }
            return expense.card?.name.lowercased() == cardName
        }

        let plannedTotal = plannedFiltered.reduce(0.0) { $0 + $1.effectiveAmount() }
        let variableTotal = variableFiltered.reduce(0.0) { $0 + $1.amount }
        let total = plannedTotal + variableTotal

        if total == 0 {
            return HomeAnswer(
                queryID: query.id,
                kind: .message,
                title: query.targetName == nil ? "Card Spend Total" : "\(query.targetName!) Spend",
                subtitle: "No card spending in this range.",
                primaryValue: nil,
                rows: []
            )
        }

        return HomeAnswer(
            queryID: query.id,
            kind: .metric,
            title: query.targetName == nil ? "Card Spend Total" : "\(query.targetName!) Spend",
            subtitle: rangeLabel(for: range),
            primaryValue: currency(total),
            rows: [
                HomeAnswerRow(title: "Planned", value: currency(plannedTotal)),
                HomeAnswerRow(title: "Variable", value: currency(variableTotal)),
                HomeAnswerRow(title: "Total", value: currency(total))
            ]
        )
    }

    private func cardVariableSpendingHabitsAnswer(
        query: HomeQuery,
        variableExpenses: [VariableExpense],
        now: Date
    ) -> HomeAnswer {
        let range = query.dateRange ?? monthRange(containing: now)
        let cardName = query.targetName?.lowercased()

        let filtered = variableExpenses.filter { expense in
            guard expense.transactionDate >= range.startDate, expense.transactionDate <= range.endDate else { return false }
            guard let cardName else { return true }
            return expense.card?.name.lowercased() == cardName
        }

        guard filtered.isEmpty == false else {
            return HomeAnswer(
                queryID: query.id,
                kind: .message,
                title: query.targetName == nil ? "Card Spending Habits" : "Card Spending Habits (\(query.targetName!))",
                subtitle: "No variable card spending in this range.",
                primaryValue: nil,
                rows: []
            )
        }

        var totalsByCard: [String: Double] = [:]
        var countsByCard: [String: Int] = [:]
        var largestTransactionByCard: [String: Double] = [:]

        for expense in filtered {
            let card = expense.card?.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let cardName = (card?.isEmpty == false) ? card! : "Unassigned Card"
            totalsByCard[cardName, default: 0] += expense.amount
            countsByCard[cardName, default: 0] += 1
            largestTransactionByCard[cardName] = max(largestTransactionByCard[cardName] ?? 0, expense.amount)
        }

        if let targetName = query.targetName {
            guard let total = totalsByCard.first(where: { $0.key.caseInsensitiveCompare(targetName) == .orderedSame })?.value else {
                return HomeAnswer(
                    queryID: query.id,
                    kind: .message,
                    title: "Card Spending Habits (\(targetName))",
                    subtitle: "No matching card found in this range.",
                    primaryValue: nil,
                    rows: []
                )
            }

            let exactName = totalsByCard.first(where: { $0.key.caseInsensitiveCompare(targetName) == .orderedSame })?.key ?? targetName
            let transactionCount = countsByCard[exactName, default: 0]
            let average = transactionCount > 0 ? total / Double(transactionCount) : 0
            let maxTransaction = largestTransactionByCard[exactName, default: 0]

            return HomeAnswer(
                queryID: query.id,
                kind: .metric,
                title: "Card Spending Habits (\(exactName))",
                subtitle: rangeLabel(for: range),
                primaryValue: currency(total),
                rows: [
                    HomeAnswerRow(title: "Transactions", value: "\(transactionCount)"),
                    HomeAnswerRow(title: "Average transaction", value: currency(average)),
                    HomeAnswerRow(title: "Largest variable transaction", value: currency(maxTransaction))
                ]
            )
        }

        let rows = totalsByCard
            .map { card, total in
                let count = countsByCard[card, default: 0]
                let average = count > 0 ? total / Double(count) : 0
                return (card: card, total: total, count: count, average: average)
            }
            .sorted { left, right in
                left.total > right.total
            }
            .prefix(query.resultLimit)
            .map { item in
                HomeAnswerRow(
                    title: item.card,
                    value: "\(currency(item.total)) total | \(item.count) txns | \(currency(item.average)) avg"
                )
            }

        let totalVariableSpend = filtered.reduce(0.0) { $0 + $1.amount }

        return HomeAnswer(
            queryID: query.id,
            kind: .list,
            title: "Card Spending Habits",
            subtitle: rangeLabel(for: range),
            primaryValue: currency(totalVariableSpend),
            rows: Array(rows)
        )
    }

    private func incomeAverageActualAnswer(
        query: HomeQuery,
        incomes: [Income],
        now: Date
    ) -> HomeAnswer {
        let range = query.dateRange ?? yearRange(containing: now)
        let sourceName = query.targetName?.lowercased()

        let filtered = incomes.filter { income in
            guard income.isPlanned == false else { return false }
            guard income.date >= range.startDate, income.date <= range.endDate else { return false }
            guard let sourceName else { return true }
            return income.source.lowercased() == sourceName
        }

        if filtered.isEmpty {
            return HomeAnswer(
                queryID: query.id,
                kind: .message,
                title: "Average Actual Income",
                subtitle: "No matching actual income in this range.",
                primaryValue: nil,
                rows: []
            )
        }

        var monthlyTotals: [Date: Double] = [:]
        for income in filtered {
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: income.date)) ?? income.date
            monthlyTotals[monthStart, default: 0] += income.amount
        }

        let average = monthlyTotals.values.reduce(0.0, +) / Double(monthlyTotals.count)
        let title = sourceName == nil ? "Average Actual Income" : "Average Actual Income (\(query.targetName!))"

        return HomeAnswer(
            queryID: query.id,
            kind: .metric,
            title: title,
            subtitle: rangeLabel(for: range),
            primaryValue: currency(average),
            rows: [
                HomeAnswerRow(title: "Months sampled", value: "\(monthlyTotals.count)"),
                HomeAnswerRow(title: "Average per month", value: currency(average))
            ]
        )
    }

    private func savingsStatusAnswer(
        query: HomeQuery,
        incomes: [Income],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        now: Date
    ) -> HomeAnswer {
        let range = query.dateRange ?? monthRange(containing: now)
        let totals = savingsTotals(
            in: range,
            incomes: incomes,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses
        )

        if totals.hasActivity == false {
            return HomeAnswer(
                queryID: query.id,
                kind: .message,
                title: "Savings Status",
                subtitle: "No savings activity in this range yet.",
                primaryValue: nil,
                rows: []
            )
        }

        return HomeAnswer(
            queryID: query.id,
            kind: .metric,
            title: "Savings Status",
            subtitle: rangeLabel(for: range),
            primaryValue: currency(totals.actualSavings),
            rows: [
                HomeAnswerRow(title: "Projected savings", value: currency(totals.projectedSavings)),
                HomeAnswerRow(title: "Actual savings", value: currency(totals.actualSavings)),
                HomeAnswerRow(title: "Gap vs projected", value: deltaSummary(totals.actualSavings - totals.projectedSavings))
            ]
        )
    }

    private func savingsAverageRecentPeriodsAnswer(
        query: HomeQuery,
        incomes: [Income],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        now: Date
    ) -> HomeAnswer {
        let periods = min(max(query.resultLimit, 1), 12)
        let unit = query.periodUnit ?? .month
        let periodRanges = lastPeriodRanges(count: periods, endingAt: now, unit: unit)

        var periodRows: [(periodStart: Date, actualSavings: Double)] = []
        periodRows.reserveCapacity(periodRanges.count)

        for range in periodRanges {
            let totals = savingsTotals(
                in: range,
                incomes: incomes,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses
            )
            periodRows.append((periodStart: range.startDate, actualSavings: totals.actualSavings))
        }

        guard periodRows.isEmpty == false else {
            return HomeAnswer(
                queryID: query.id,
                kind: .message,
                title: "Average Savings",
                subtitle: "No savings activity in recent periods.",
                primaryValue: nil,
                rows: []
            )
        }

        let average = periodRows.reduce(0.0) { $0 + $1.actualSavings } / Double(periodRows.count)
        let best = periodRows.max { $0.actualSavings < $1.actualSavings }
        let lowest = periodRows.min { $0.actualSavings < $1.actualSavings }
        let unitTitle = periodUnitTitle(unit, count: periodRows.count)
        let bestLabel = "Best \(periodUnitLabel(unit))"
        let lowestLabel = "Lowest \(periodUnitLabel(unit))"

        var rows = [
            HomeAnswerRow(title: "Periods sampled", value: "\(periodRows.count)"),
            HomeAnswerRow(title: "Average per \(unitTitle.lowercased())", value: currency(average))
        ]

        if let best {
            rows.append(
                HomeAnswerRow(
                    title: bestLabel,
                    value: "\(periodTitle(containing: best.periodStart, unit: unit)) (\(currency(best.actualSavings)))"
                )
            )
        }

        if let lowest {
            rows.append(
                HomeAnswerRow(
                    title: lowestLabel,
                    value: "\(periodTitle(containing: lowest.periodStart, unit: unit)) (\(currency(lowest.actualSavings)))"
                )
            )
        }

        return HomeAnswer(
            queryID: query.id,
            kind: .metric,
            title: "Average Savings (Last \(periodRows.count) \(unitTitle))",
            subtitle: "Recent period trend",
            primaryValue: currency(average),
            rows: rows
        )
    }

    private func incomeSourceShareAnswer(
        query: HomeQuery,
        incomes: [Income],
        now: Date
    ) -> HomeAnswer {
        let range = query.dateRange ?? monthRange(containing: now)
        let actualIncomes = incomes.filter { income in
            income.isPlanned == false
                && income.date >= range.startDate
                && income.date <= range.endDate
        }

        guard actualIncomes.isEmpty == false else {
            return HomeAnswer(
                queryID: query.id,
                kind: .message,
                title: "Income Share",
                subtitle: "No actual income in this range yet.",
                primaryValue: nil,
                rows: []
            )
        }

        var totalsBySource: [String: Double] = [:]
        for income in actualIncomes {
            totalsBySource[income.source, default: 0] += income.amount
        }

        let overallTotal = totalsBySource.values.reduce(0.0, +)
        guard overallTotal > 0 else {
            return HomeAnswer(
                queryID: query.id,
                kind: .message,
                title: "Income Share",
                subtitle: "No income totals available in this range.",
                primaryValue: nil,
                rows: []
            )
        }

        if let targetName = query.targetName {
            guard let entry = totalsBySource.first(where: { $0.key.caseInsensitiveCompare(targetName) == .orderedSame }) else {
                return HomeAnswer(
                    queryID: query.id,
                    kind: .message,
                    title: "Income Share (\(targetName))",
                    subtitle: "No matching source found in this range.",
                    primaryValue: nil,
                    rows: []
                )
            }

            let share = entry.value / overallTotal
            return HomeAnswer(
                queryID: query.id,
                kind: .metric,
                title: "Income Share (\(entry.key))",
                subtitle: rangeLabel(for: range),
                primaryValue: percent(share),
                rows: [
                    HomeAnswerRow(title: "Source income", value: currency(entry.value)),
                    HomeAnswerRow(title: "Total income", value: currency(overallTotal)),
                    HomeAnswerRow(title: "Share", value: percent(share))
                ]
            )
        }

        let rows = totalsBySource
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { source, amount in
                HomeAnswerRow(
                    title: source,
                    value: "\(currency(amount)) (\(percent(amount / overallTotal)))"
                )
            }

        return HomeAnswer(
            queryID: query.id,
            kind: .list,
            title: "Income Share by Source",
            subtitle: rangeLabel(for: range),
            primaryValue: currency(overallTotal),
            rows: rows
        )
    }

    private func categorySpendShareAnswer(
        query: HomeQuery,
        categories: [Category],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        now: Date
    ) -> HomeAnswer {
        let range = query.dateRange ?? monthRange(containing: now)
        let metricsResult = HomeCategoryMetricsCalculator.calculate(
            categories: categories,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            rangeStart: range.startDate,
            rangeEnd: range.endDate
        )

        guard metricsResult.totalSpent > 0, metricsResult.metrics.isEmpty == false else {
            return HomeAnswer(
                queryID: query.id,
                kind: .message,
                title: "Category Spend Share",
                subtitle: "No category spending in this range yet.",
                primaryValue: nil,
                rows: []
            )
        }

        if let targetName = query.targetName {
            guard let metric = metricsResult.metrics.first(where: { $0.categoryName.caseInsensitiveCompare(targetName) == .orderedSame }) else {
                return HomeAnswer(
                    queryID: query.id,
                    kind: .message,
                    title: "Category Spend Share (\(targetName))",
                    subtitle: "No matching category found in this range.",
                    primaryValue: nil,
                    rows: []
                )
            }

            return HomeAnswer(
                queryID: query.id,
                kind: .metric,
                title: "Category Spend Share (\(metric.categoryName))",
                subtitle: rangeLabel(for: range),
                primaryValue: percent(metric.percentOfTotal),
                rows: [
                    HomeAnswerRow(title: "Category spend", value: currency(metric.totalSpent)),
                    HomeAnswerRow(title: "Total spend", value: currency(metricsResult.totalSpent)),
                    HomeAnswerRow(title: "Share", value: percent(metric.percentOfTotal))
                ]
            )
        }

        let rows = metricsResult.metrics
            .prefix(5)
            .map { metric in
                HomeAnswerRow(
                    title: metric.categoryName,
                    value: "\(currency(metric.totalSpent)) (\(percent(metric.percentOfTotal)))"
                )
            }

        return HomeAnswer(
            queryID: query.id,
            kind: .list,
            title: "Category Spend Share",
            subtitle: rangeLabel(for: range),
            primaryValue: currency(metricsResult.totalSpent),
            rows: rows
        )
    }

    private func incomeSourceShareTrendAnswer(
        query: HomeQuery,
        incomes: [Income],
        now: Date
    ) -> HomeAnswer {
        let periods = min(max(query.resultLimit, 1), 12)
        let unit = query.periodUnit ?? .month
        let periodRanges = lastPeriodRanges(count: periods, endingAt: now, unit: unit)

        var periodTotals: [(periodStart: Date, total: Double, bySource: [String: Double])] = []
        periodTotals.reserveCapacity(periodRanges.count)

        for range in periodRanges {
            let items = incomes.filter { income in
                income.isPlanned == false
                    && income.date >= range.startDate
                    && income.date <= range.endDate
            }

            var bySource: [String: Double] = [:]
            for income in items {
                bySource[income.source, default: 0] += income.amount
            }
            let total = bySource.values.reduce(0.0, +)
            periodTotals.append((periodStart: range.startDate, total: total, bySource: bySource))
        }

        if let targetName = query.targetName {
            let shares: [(periodStart: Date, share: Double)] = periodTotals.compactMap { period in
                guard period.total > 0 else { return nil }
                guard let sourceTotal = period.bySource.first(where: { $0.key.caseInsensitiveCompare(targetName) == .orderedSame })?.value else {
                    return (period.periodStart, 0.0)
                }
                return (period.periodStart, sourceTotal / period.total)
            }

            guard shares.isEmpty == false else {
                return HomeAnswer(
                    queryID: query.id,
                    kind: .message,
                    title: "Income Share Trend (\(targetName))",
                    subtitle: "No income activity in recent periods.",
                    primaryValue: nil,
                    rows: []
                )
            }

            let averageShare = shares.reduce(0.0) { $0 + $1.share } / Double(shares.count)
            let highest = shares.max { $0.share < $1.share }
            let lowest = shares.min { $0.share < $1.share }
            let unitTitle = periodUnitTitle(unit, count: shares.count)
            let highestLabel = "Highest \(periodUnitLabel(unit))"
            let lowestLabel = "Lowest \(periodUnitLabel(unit))"

            var rows = [
                HomeAnswerRow(title: "Periods sampled", value: "\(shares.count)"),
                HomeAnswerRow(title: "Average share", value: percent(averageShare))
            ]

            if let highest {
                rows.append(
                    HomeAnswerRow(
                        title: highestLabel,
                        value: "\(periodTitle(containing: highest.periodStart, unit: unit)) (\(percent(highest.share)))"
                    )
                )
            }

            if let lowest {
                rows.append(
                    HomeAnswerRow(
                        title: lowestLabel,
                        value: "\(periodTitle(containing: lowest.periodStart, unit: unit)) (\(percent(lowest.share)))"
                    )
                )
            }

            return HomeAnswer(
                queryID: query.id,
                kind: .metric,
                title: "Income Share Trend (\(targetName))",
                subtitle: "Last \(shares.count) \(unitTitle.lowercased())",
                primaryValue: percent(averageShare),
                rows: rows
            )
        }

        var aggregateSharesBySource: [String: [Double]] = [:]
        for period in periodTotals where period.total > 0 {
            for (source, value) in period.bySource {
                let share = value / period.total
                aggregateSharesBySource[source, default: []].append(share)
            }
        }

        guard aggregateSharesBySource.isEmpty == false else {
            return HomeAnswer(
                queryID: query.id,
                kind: .message,
                title: "Income Share Trend",
                subtitle: "No income activity in recent periods.",
                primaryValue: nil,
                rows: []
            )
        }

        let rows = aggregateSharesBySource
            .map { source, shares in
                let avg = shares.reduce(0.0, +) / Double(shares.count)
                return (source: source, average: avg)
            }
            .sorted { $0.average > $1.average }
            .prefix(5)
            .map { HomeAnswerRow(title: $0.source, value: percent($0.average)) }

        let unitTitle = periodUnitTitle(unit, count: periods)
        return HomeAnswer(
            queryID: query.id,
            kind: .list,
            title: "Income Share Trend",
            subtitle: "Last \(periods) \(unitTitle.lowercased())",
            primaryValue: nil,
            rows: Array(rows)
        )
    }

    private func categorySpendShareTrendAnswer(
        query: HomeQuery,
        categories: [Category],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        now: Date
    ) -> HomeAnswer {
        let periods = min(max(query.resultLimit, 1), 12)
        let unit = query.periodUnit ?? .month
        let periodRanges = lastPeriodRanges(count: periods, endingAt: now, unit: unit)

        var periodMetrics: [(periodStart: Date, result: HomeCategoryMetricsResult)] = []
        periodMetrics.reserveCapacity(periodRanges.count)

        for range in periodRanges {
            let result = HomeCategoryMetricsCalculator.calculate(
                categories: categories,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                rangeStart: range.startDate,
                rangeEnd: range.endDate
            )
            periodMetrics.append((periodStart: range.startDate, result: result))
        }

        if let targetName = query.targetName {
            let shares: [(periodStart: Date, share: Double)] = periodMetrics.compactMap { period in
                guard period.result.totalSpent > 0 else { return nil }
                let share = period.result.metrics
                    .first(where: { $0.categoryName.caseInsensitiveCompare(targetName) == .orderedSame })?
                    .percentOfTotal ?? 0.0
                return (period.periodStart, share)
            }

            guard shares.isEmpty == false else {
                return HomeAnswer(
                    queryID: query.id,
                    kind: .message,
                    title: "Category Share Trend (\(targetName))",
                    subtitle: "No category spending activity in recent periods.",
                    primaryValue: nil,
                    rows: []
                )
            }

            let averageShare = shares.reduce(0.0) { $0 + $1.share } / Double(shares.count)
            let highest = shares.max { $0.share < $1.share }
            let lowest = shares.min { $0.share < $1.share }
            let unitTitle = periodUnitTitle(unit, count: shares.count)
            let highestLabel = "Highest \(periodUnitLabel(unit))"
            let lowestLabel = "Lowest \(periodUnitLabel(unit))"

            var rows = [
                HomeAnswerRow(title: "Periods sampled", value: "\(shares.count)"),
                HomeAnswerRow(title: "Average share", value: percent(averageShare))
            ]

            if let highest {
                rows.append(
                    HomeAnswerRow(
                        title: highestLabel,
                        value: "\(periodTitle(containing: highest.periodStart, unit: unit)) (\(percent(highest.share)))"
                    )
                )
            }

            if let lowest {
                rows.append(
                    HomeAnswerRow(
                        title: lowestLabel,
                        value: "\(periodTitle(containing: lowest.periodStart, unit: unit)) (\(percent(lowest.share)))"
                    )
                )
            }

            return HomeAnswer(
                queryID: query.id,
                kind: .metric,
                title: "Category Share Trend (\(targetName))",
                subtitle: "Last \(shares.count) \(unitTitle.lowercased())",
                primaryValue: percent(averageShare),
                rows: rows
            )
        }

        var aggregateSharesByCategory: [String: [Double]] = [:]
        for period in periodMetrics where period.result.totalSpent > 0 {
            for metric in period.result.metrics {
                aggregateSharesByCategory[metric.categoryName, default: []].append(metric.percentOfTotal)
            }
        }

        guard aggregateSharesByCategory.isEmpty == false else {
            return HomeAnswer(
                queryID: query.id,
                kind: .message,
                title: "Category Share Trend",
                subtitle: "No category spending activity in recent periods.",
                primaryValue: nil,
                rows: []
            )
        }

        let rows = aggregateSharesByCategory
            .map { name, shares in
                let avg = shares.reduce(0.0, +) / Double(shares.count)
                return (name: name, average: avg)
            }
            .sorted { $0.average > $1.average }
            .prefix(5)
            .map { HomeAnswerRow(title: $0.name, value: percent($0.average)) }

        let unitTitle = periodUnitTitle(unit, count: periods)
        return HomeAnswer(
            queryID: query.id,
            kind: .list,
            title: "Category Share Trend",
            subtitle: "Last \(periods) \(unitTitle.lowercased())",
            primaryValue: nil,
            rows: Array(rows)
        )
    }

    private func presetDueSoonAnswer(
        query: HomeQuery,
        presets: [Preset],
        plannedExpenses: [PlannedExpense],
        now: Date
    ) -> HomeAnswer {
        let range: HomeQueryDateRange
        let subtitle: String
        let lowerBound: Date

        if let explicitRange = query.dateRange {
            range = explicitRange
            subtitle = rangeLabel(for: explicitRange)
            lowerBound = explicitRange.startDate
        } else {
            let start = calendar.startOfDay(for: now)
            let endDay = calendar.date(byAdding: .day, value: 30, to: start) ?? start
            let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDay) ?? endDay
            range = HomeQueryDateRange(startDate: start, endDate: end)
            subtitle = "Next 30 days"
            lowerBound = start
        }

        let presetNameByID: [UUID: String] = Dictionary(
            uniqueKeysWithValues: presets.map { ($0.id, $0.title) }
        )

        let upcomingPresetCounts = plannedExpenses
            .filter { expense in
                expense.sourcePresetID != nil
                    && expense.expenseDate >= lowerBound
                    && expense.expenseDate <= range.endDate
            }
            .reduce(into: [String: Int]()) { partial, expense in
                guard let sourcePresetID = expense.sourcePresetID else { return }
                let fallbackTitle = expense.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let title = presetNameByID[sourcePresetID] ?? fallbackTitle
                guard title.isEmpty == false else { return }
                partial[title, default: 0] += 1
            }

        guard upcomingPresetCounts.isEmpty == false else {
            return HomeAnswer(
                queryID: query.id,
                kind: .message,
                title: "Presets Due Soon",
                subtitle: "No preset expenses due in this window.",
                primaryValue: nil,
                rows: []
            )
        }

        let rows = upcomingPresetCounts
            .sorted { left, right in
                if left.value == right.value {
                    return left.key < right.key
                }
                return left.value > right.value
            }
            .prefix(query.resultLimit)
            .map { name, count in
                HomeAnswerRow(title: name, value: count == 1 ? "1 due" : "\(count) due")
            }

        return HomeAnswer(
            queryID: query.id,
            kind: .list,
            title: "Presets Due Soon",
            subtitle: subtitle,
            primaryValue: "\(upcomingPresetCounts.count) preset\(upcomingPresetCounts.count == 1 ? "" : "s")",
            rows: Array(rows)
        )
    }

    private func presetHighestCostAnswer(
        query: HomeQuery,
        presets: [Preset]
    ) -> HomeAnswer {
        let activePresets = presets
            .filter { $0.isArchived == false }
            .filter { $0.plannedAmount > 0 }

        guard activePresets.isEmpty == false else {
            return HomeAnswer(
                queryID: query.id,
                kind: .message,
                title: "Highest Preset Costs",
                subtitle: "No active presets with planned amounts yet.",
                primaryValue: nil,
                rows: []
            )
        }

        let ranked = activePresets.sorted { left, right in
            if left.plannedAmount == right.plannedAmount {
                return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
            }
            return left.plannedAmount > right.plannedAmount
        }

        let rows = ranked
            .prefix(query.resultLimit)
            .map { preset in
                HomeAnswerRow(title: preset.title, value: currency(preset.plannedAmount))
            }

        return HomeAnswer(
            queryID: query.id,
            kind: .list,
            title: "Highest Preset Costs",
            subtitle: "Per preset amount",
            primaryValue: rows.first?.value,
            rows: rows
        )
    }

    private func presetTopCategoryAnswer(
        query: HomeQuery,
        presets: [Preset]
    ) -> HomeAnswer {
        let activePresets = presets.filter { $0.isArchived == false }
        let countsByCategory = activePresets.reduce(into: [String: Int]()) { partial, preset in
            let name = preset.defaultCategory?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard name.isEmpty == false else { return }
            partial[name, default: 0] += 1
        }

        guard countsByCategory.isEmpty == false else {
            return HomeAnswer(
                queryID: query.id,
                kind: .message,
                title: "Preset Category Coverage",
                subtitle: "No category assignments found on active presets.",
                primaryValue: nil,
                rows: []
            )
        }

        let rows = countsByCategory
            .sorted { left, right in
                if left.value == right.value {
                    return left.key < right.key
                }
                return left.value > right.value
            }
            .prefix(query.resultLimit)
            .map { name, count in
                HomeAnswerRow(title: name, value: count == 1 ? "1 preset" : "\(count) presets")
            }

        return HomeAnswer(
            queryID: query.id,
            kind: .list,
            title: "Categories Assigned to Presets",
            subtitle: "Most assigned categories",
            primaryValue: rows.first?.value,
            rows: Array(rows)
        )
    }

    private func presetCategorySpendAnswer(
        query: HomeQuery,
        presets: [Preset]
    ) -> HomeAnswer {
        let activePresets = presets.filter { $0.isArchived == false }
        let totalsByCategory = activePresets.reduce(into: [String: Double]()) { partial, preset in
            let name = preset.defaultCategory?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard name.isEmpty == false else { return }
            partial[name, default: 0] += preset.plannedAmount
        }

        guard totalsByCategory.isEmpty == false else {
            return HomeAnswer(
                queryID: query.id,
                kind: .message,
                title: "Preset Spend by Category",
                subtitle: "No category-linked preset spend found.",
                primaryValue: nil,
                rows: []
            )
        }

        if let targetName = query.targetName {
            guard let match = totalsByCategory.first(where: { $0.key.caseInsensitiveCompare(targetName) == .orderedSame }) else {
                return HomeAnswer(
                    queryID: query.id,
                    kind: .message,
                    title: "Preset Spend by Category (\(targetName))",
                    subtitle: "No matching category found on active presets.",
                    primaryValue: nil,
                    rows: []
                )
            }

            let totalAcrossAllCategories = totalsByCategory.values.reduce(0.0, +)
            let share = totalAcrossAllCategories > 0 ? match.value / totalAcrossAllCategories : 0.0

            return HomeAnswer(
                queryID: query.id,
                kind: .metric,
                title: "Preset Spend by Category (\(match.key))",
                subtitle: "Per preset amount",
                primaryValue: currency(match.value),
                rows: [
                    HomeAnswerRow(title: "Category total", value: currency(match.value)),
                    HomeAnswerRow(title: "All preset categories", value: currency(totalAcrossAllCategories)),
                    HomeAnswerRow(title: "Share", value: percent(share))
                ]
            )
        }

        let rows = totalsByCategory
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { category, total in
                HomeAnswerRow(title: category, value: currency(total))
            }

        return HomeAnswer(
            queryID: query.id,
            kind: .list,
            title: "Preset Spend by Category",
            subtitle: "Per preset amount",
            primaryValue: nil,
            rows: rows
        )
    }

    private func categoryPotentialSavingsAnswer(
        query: HomeQuery,
        categories: [Category],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        now: Date
    ) -> HomeAnswer {
        let range = query.dateRange ?? monthRange(containing: now)
        let metricsResult = HomeCategoryMetricsCalculator.calculate(
            categories: categories,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            rangeStart: range.startDate,
            rangeEnd: range.endDate
        )

        guard metricsResult.totalSpent > 0, metricsResult.metrics.isEmpty == false else {
            return HomeAnswer(
                queryID: query.id,
                kind: .message,
                title: "Category Potential Savings",
                subtitle: "No category spending in this range yet.",
                primaryValue: nil,
                rows: []
            )
        }

        let targetMetric = metricsResult.metrics.first(where: { metric in
            guard let targetName = query.targetName else { return false }
            return metric.categoryName.caseInsensitiveCompare(targetName) == .orderedSame
        }) ?? metricsResult.metrics.first

        guard let targetMetric else {
            return HomeAnswer(
                queryID: query.id,
                kind: .message,
                title: "Category Potential Savings",
                subtitle: "No matching category found in this range.",
                primaryValue: nil,
                rows: []
            )
        }

        let scenarios: [Double] = [0.05, 0.10, 0.15]
        let rows = scenarios.map { reduction in
            let savings = targetMetric.totalSpent * reduction
            let percentText = NumberFormatter.localizedString(
                from: NSNumber(value: Int(reduction * 100)),
                number: .none
            )
            return HomeAnswerRow(
                title: "Reduce by \(percentText)%",
                value: currency(savings)
            )
        }

        let tenPercentSavings = targetMetric.totalSpent * 0.10
        return HomeAnswer(
            queryID: query.id,
            kind: .list,
            title: "Potential Savings (\(targetMetric.categoryName))",
            subtitle: rangeLabel(for: range),
            primaryValue: currency(tenPercentSavings),
            rows: [
                HomeAnswerRow(title: "Current spend", value: currency(targetMetric.totalSpent)),
                HomeAnswerRow(title: "Share of total", value: percent(targetMetric.percentOfTotal))
            ] + rows
        )
    }

    private func categoryReallocationGuidanceAnswer(
        query: HomeQuery,
        categories: [Category],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        now: Date
    ) -> HomeAnswer {
        let range = query.dateRange ?? monthRange(containing: now)
        let metricsResult = HomeCategoryMetricsCalculator.calculate(
            categories: categories,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            rangeStart: range.startDate,
            rangeEnd: range.endDate
        )

        guard metricsResult.totalSpent > 0, metricsResult.metrics.count > 1 else {
            return HomeAnswer(
                queryID: query.id,
                kind: .message,
                title: "Category Reallocation Guidance",
                subtitle: "Need at least two spending categories in this range.",
                primaryValue: nil,
                rows: []
            )
        }

        let targetMetric = metricsResult.metrics.first(where: { metric in
            guard let targetName = query.targetName else { return false }
            return metric.categoryName.caseInsensitiveCompare(targetName) == .orderedSame
        }) ?? metricsResult.metrics.first

        guard let targetMetric else {
            return HomeAnswer(
                queryID: query.id,
                kind: .message,
                title: "Category Reallocation Guidance",
                subtitle: "No matching category found in this range.",
                primaryValue: nil,
                rows: []
            )
        }

        let otherMetrics = metricsResult.metrics.filter { $0.categoryID != targetMetric.categoryID }
        let othersTotal = otherMetrics.reduce(0.0) { $0 + $1.totalSpent }

        guard othersTotal > 0 else {
            return HomeAnswer(
                queryID: query.id,
                kind: .message,
                title: "Category Reallocation Guidance",
                subtitle: "No other category spending found to rebalance.",
                primaryValue: nil,
                rows: []
            )
        }

        let targetIncrease = 0.10
        let addedSpend = targetMetric.totalSpent * targetIncrease

        let rows = otherMetrics
            .prefix(query.resultLimit)
            .map { metric in
                let proportionalCut = addedSpend * (metric.totalSpent / othersTotal)
                let adjustedSpend = max(0.0, metric.totalSpent - proportionalCut)
                return HomeAnswerRow(
                    title: metric.categoryName,
                    value: "\(currency(adjustedSpend)) (from \(currency(metric.totalSpent)))"
                )
            }

        return HomeAnswer(
            queryID: query.id,
            kind: .list,
            title: "Reallocation Guidance (\(targetMetric.categoryName))",
            subtitle: "If \(targetMetric.categoryName) increases by 10%",
            primaryValue: "+\(currency(addedSpend))",
            rows: [
                HomeAnswerRow(title: "Current \(targetMetric.categoryName)", value: currency(targetMetric.totalSpent)),
                HomeAnswerRow(title: "Reduce other categories by", value: currency(addedSpend))
            ] + rows
        )
    }

    // MARK: - Helpers

    private func totalSpend(
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        range: HomeQueryDateRange
    ) -> Double {
        sumPlannedExpenses(plannedExpenses, in: range) + sumVariableExpenses(variableExpenses, in: range)
    }

    private func sumPlannedExpenses(
        _ plannedExpenses: [PlannedExpense],
        in range: HomeQueryDateRange
    ) -> Double {
        plannedExpenses.reduce(0.0) { partial, expense in
            guard expense.expenseDate >= range.startDate, expense.expenseDate <= range.endDate else { return partial }
            return partial + expense.effectiveAmount()
        }
    }

    private func sumVariableExpenses(
        _ variableExpenses: [VariableExpense],
        in range: HomeQueryDateRange
    ) -> Double {
        variableExpenses.reduce(0.0) { partial, expense in
            guard expense.transactionDate >= range.startDate, expense.transactionDate <= range.endDate else { return partial }
            return partial + expense.amount
        }
    }

    private func largestTransaction(
        in range: HomeQueryDateRange,
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense]
    ) -> (title: String, amount: Double)? {
        var entries: [(title: String, amount: Double)] = []
        entries.reserveCapacity(plannedExpenses.count + variableExpenses.count)

        for expense in plannedExpenses {
            guard expense.expenseDate >= range.startDate, expense.expenseDate <= range.endDate else { continue }
            entries.append((title: expense.title, amount: expense.effectiveAmount()))
        }

        for expense in variableExpenses {
            guard expense.transactionDate >= range.startDate, expense.transactionDate <= range.endDate else { continue }
            entries.append((title: expense.descriptionText, amount: expense.amount))
        }

        return entries.max { left, right in
            left.amount < right.amount
        }
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

    private func savingsTotals(
        in range: HomeQueryDateRange,
        incomes: [Income],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense]
    ) -> (
        projectedSavings: Double,
        actualSavings: Double,
        hasActivity: Bool
    ) {
        let plannedIncomeTotal = incomes
            .filter { $0.isPlanned && $0.date >= range.startDate && $0.date <= range.endDate }
            .reduce(0.0) { $0 + $1.amount }

        let actualIncomeTotal = incomes
            .filter { $0.isPlanned == false && $0.date >= range.startDate && $0.date <= range.endDate }
            .reduce(0.0) { $0 + $1.amount }

        let plannedExpensesPlannedTotal = plannedExpenses
            .filter { $0.expenseDate >= range.startDate && $0.expenseDate <= range.endDate }
            .reduce(0.0) { $0 + $1.plannedAmount }

        let plannedExpensesEffectiveActualTotal = plannedExpenses
            .filter { $0.expenseDate >= range.startDate && $0.expenseDate <= range.endDate }
            .reduce(0.0) { $0 + $1.effectiveAmount() }

        let variableExpensesTotal = variableExpenses
            .filter { $0.transactionDate >= range.startDate && $0.transactionDate <= range.endDate }
            .reduce(0.0) { $0 + $1.amount }

        let projectedSavings = plannedIncomeTotal - plannedExpensesPlannedTotal
        let actualSavings = actualIncomeTotal - (plannedExpensesEffectiveActualTotal + variableExpensesTotal)
        let hasActivity = plannedIncomeTotal != 0
            || actualIncomeTotal != 0
            || plannedExpensesPlannedTotal != 0
            || plannedExpensesEffectiveActualTotal != 0
            || variableExpensesTotal != 0

        return (projectedSavings, actualSavings, hasActivity)
    }

    private func monthRange(containing date: Date) -> HomeQueryDateRange {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? start
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func periodStatusLabel(total: Double, previousTotal: Double, delta: Double) -> String {
        guard total > 0 else { return "No activity yet" }
        guard previousTotal > 0 else { return "Baseline period (no prior comparison)" }

        let changeRatio = delta / previousTotal
        if changeRatio <= -0.05 {
            return "Good: spending improved vs previous period"
        }
        if changeRatio <= 0.10 {
            return "OK: spending is relatively stable"
        }
        return "Watch: spending is above previous period"
    }

    private func weekRange(containing date: Date) -> HomeQueryDateRange {
        let interval = calendar.dateInterval(of: .weekOfYear, for: date)
        let start = calendar.startOfDay(for: interval?.start ?? date)
        let end = calendar.date(byAdding: DateComponents(day: 6), to: start) ?? start
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func quarterRange(containing date: Date) -> HomeQueryDateRange {
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? calendar.component(.year, from: date)
        let month = components.month ?? calendar.component(.month, from: date)

        let quarterStartMonth: Int
        switch month {
        case 1...3:
            quarterStartMonth = 1
        case 4...6:
            quarterStartMonth = 4
        case 7...9:
            quarterStartMonth = 7
        default:
            quarterStartMonth = 10
        }

        let start = calendar.date(from: DateComponents(year: year, month: quarterStartMonth, day: 1)) ?? date
        let end = calendar.date(byAdding: DateComponents(month: 3, day: -1), to: start) ?? start
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func yearRange(containing date: Date) -> HomeQueryDateRange {
        let start = calendar.date(from: calendar.dateComponents([.year], from: date)) ?? date
        let end = calendar.date(byAdding: DateComponents(year: 1, day: -1), to: start) ?? start
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func previousMonthRange(before date: Date) -> HomeQueryDateRange {
        let thisMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let previousMonthStart = calendar.date(byAdding: .month, value: -1, to: thisMonthStart) ?? thisMonthStart
        let previousMonthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: previousMonthStart) ?? previousMonthStart
        return HomeQueryDateRange(startDate: previousMonthStart, endDate: previousMonthEnd)
    }

    private func previousEquivalentRange(matching range: HomeQueryDateRange) -> HomeQueryDateRange {
        let startOfCurrent = calendar.startOfDay(for: range.startDate)
        let startOfEnd = calendar.startOfDay(for: range.endDate)

        let daySpan = (calendar.dateComponents([.day], from: startOfCurrent, to: startOfEnd).day ?? 0) + 1

        let previousEnd = calendar.date(byAdding: .day, value: -1, to: startOfCurrent) ?? startOfCurrent
        let previousStart = calendar.date(byAdding: .day, value: -(daySpan - 1), to: previousEnd) ?? previousEnd

        return HomeQueryDateRange(startDate: previousStart, endDate: previousEnd)
    }

    private func lastPeriodRanges(
        count: Int,
        endingAt now: Date,
        unit: HomeQueryPeriodUnit
    ) -> [HomeQueryDateRange] {
        let safeCount = max(1, count)

        switch unit {
        case .day:
            let today = calendar.startOfDay(for: now)
            return (0..<safeCount)
                .compactMap { offset -> HomeQueryDateRange? in
                    guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
                    let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: date) ?? date
                    return HomeQueryDateRange(startDate: date, endDate: end)
                }
                .reversed()

        case .week:
            let currentStart = weekRange(containing: now).startDate
            return (0..<safeCount)
                .compactMap { offset -> HomeQueryDateRange? in
                    guard let date = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentStart) else { return nil }
                    return weekRange(containing: date)
                }
                .reversed()

        case .month:
            let currentStart = monthRange(containing: now).startDate
            return (0..<safeCount)
                .compactMap { offset -> HomeQueryDateRange? in
                    guard let date = calendar.date(byAdding: .month, value: -offset, to: currentStart) else { return nil }
                    return monthRange(containing: date)
                }
                .reversed()

        case .quarter:
            let currentStart = quarterRange(containing: now).startDate
            return (0..<safeCount)
                .compactMap { offset -> HomeQueryDateRange? in
                    guard let date = calendar.date(byAdding: .month, value: -(offset * 3), to: currentStart) else { return nil }
                    return quarterRange(containing: date)
                }
                .reversed()

        case .year:
            let currentStart = yearRange(containing: now).startDate
            return (0..<safeCount)
                .compactMap { offset -> HomeQueryDateRange? in
                    guard let date = calendar.date(byAdding: .year, value: -offset, to: currentStart) else { return nil }
                    return yearRange(containing: date)
                }
                .reversed()
        }
    }

    private func monthTitle(containing date: Date) -> String {
        date.formatted(.dateTime.year().month(.wide))
    }

    private func periodUnitLabel(_ unit: HomeQueryPeriodUnit) -> String {
        switch unit {
        case .day:
            return "day"
        case .week:
            return "week"
        case .month:
            return "month"
        case .quarter:
            return "quarter"
        case .year:
            return "year"
        }
    }

    private func periodUnitTitle(_ unit: HomeQueryPeriodUnit, count: Int) -> String {
        let label = periodUnitLabel(unit)
        return count == 1 ? label.capitalized : "\(label.capitalized)s"
    }

    private func periodTitle(containing date: Date, unit: HomeQueryPeriodUnit) -> String {
        switch unit {
        case .day:
            return date.formatted(.dateTime.year().month(.abbreviated).day())
        case .week:
            let range = weekRange(containing: date)
            return "\(shortDate(range.startDate)) - \(shortDate(range.endDate))"
        case .month:
            return monthTitle(containing: date)
        case .quarter:
            let range = quarterRange(containing: date)
            return rangeLabel(for: range)
        case .year:
            return date.formatted(.dateTime.year())
        }
    }

    private func rangeLabel(for range: HomeQueryDateRange) -> String {
        if isFullMonth(range) {
            return monthTitle(containing: range.startDate)
        }

        if isFullYear(range) {
            return range.startDate.formatted(.dateTime.year())
        }

        return "\(shortDate(range.startDate)) - \(shortDate(range.endDate))"
    }

    private func shortDate(_ date: Date) -> String {
        AppDateFormat.abbreviatedDate(date)
    }

    private func isFullMonth(_ range: HomeQueryDateRange) -> Bool {
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: range.startDate)) ?? range.startDate
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) ?? monthStart
        return calendar.isDate(monthStart, inSameDayAs: range.startDate)
            && calendar.isDate(monthEnd, inSameDayAs: range.endDate)
    }

    private func isFullYear(_ range: HomeQueryDateRange) -> Bool {
        let yearStart = calendar.date(from: calendar.dateComponents([.year], from: range.startDate)) ?? range.startDate
        let yearEnd = calendar.date(byAdding: DateComponents(year: 1, day: -1), to: yearStart) ?? yearStart
        return calendar.isDate(yearStart, inSameDayAs: range.startDate)
            && calendar.isDate(yearEnd, inSameDayAs: range.endDate)
    }

    private func currency(_ amount: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: amount)) ?? amount.formatted(.number)
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(1)))
    }
}
