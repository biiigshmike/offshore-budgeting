//
//  HomeAssistantRequestRouting.swift
//  OffshoreBudgeting
//
//  Created by OpenAI Codex on 4/8/26.
//

import Foundation

enum HomeAssistantRequestShape: Equatable {
    case single
    case spendAndWhere
    case spendByDay
    case incomePeriodSummary
    case savingsDiagnostic
    case categoryAvailability
    case spendDrivers
    case cardSummary
}

struct HomeAssistantRequestRoutingResolution: Equatable {
    let shape: HomeAssistantRequestShape
    let plan: HomeQueryPlan
}

struct HomeAssistantRequestRoutingResolver {
    private let calendar: Calendar
    private let compoundPromptResolver = HomeAssistantCompoundPromptResolver()
    private let capabilityCatalog = HomeAssistantCapabilityCatalog()

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func resolve(
        prompt: String,
        basePlan: HomeQueryPlan,
        now: Date = Date()
    ) -> HomeAssistantRequestRoutingResolution {
        let effectivePlan = cappedPlanIfNeeded(basePlan, prompt: prompt, now: now)
        let normalizedPrompt = normalized(prompt)

        if let capability = capabilityCatalog.resolve(prompt: prompt),
           shouldUseCapability(capability, with: effectivePlan) {
            return HomeAssistantRequestRoutingResolution(shape: capability.shape, plan: effectivePlan)
        }

        guard effectivePlan.metric == .spendTotal else {
            return HomeAssistantRequestRoutingResolution(shape: .single, plan: effectivePlan)
        }

        if wantsSpendByDay(normalizedPrompt) {
            return HomeAssistantRequestRoutingResolution(shape: .spendByDay, plan: effectivePlan)
        }

        if compoundPromptResolver.isSpendAndWherePrompt(prompt) {
            return HomeAssistantRequestRoutingResolution(shape: .spendAndWhere, plan: effectivePlan)
        }

        return HomeAssistantRequestRoutingResolution(shape: .single, plan: effectivePlan)
    }

    private func shouldUseCapability(
        _ capability: HomeAssistantCapabilityResolution,
        with plan: HomeQueryPlan
    ) -> Bool {
        switch capability.shape {
        case .spendAndWhere, .spendByDay:
            return plan.metric == .spendTotal
        case .incomePeriodSummary:
            return plan.metric == .incomeAverageActual || plan.metric == .incomeSourceShare
        case .savingsDiagnostic:
            return plan.metric == .savingsStatus || plan.metric == .forecastSavings
        case .categoryAvailability:
            return plan.metric == .topCategories || plan.metric == .overview
        case .spendDrivers:
            return plan.metric == .topCategoryChanges
                || plan.metric == .monthComparison
                || plan.metric == .spendTrendsSummary
                || plan.metric == .overview
        case .cardSummary:
            return plan.metric == .cardSnapshotSummary
                || plan.metric == .cardSpendTotal
                || plan.metric == .cardVariableSpendingHabits
        case .single:
            return false
        }
    }

    private func cappedPlanIfNeeded(
        _ plan: HomeQueryPlan,
        prompt: String,
        now: Date
    ) -> HomeQueryPlan {
        guard let dateRange = plan.dateRange else { return plan }

        let normalizedPrompt = normalized(prompt)
        let requestsPartialCurrentPeriod = normalizedPrompt.contains("so far")
            || normalizedPrompt.contains("thus far")
            || normalizedPrompt.contains("to date")

        guard requestsPartialCurrentPeriod else { return plan }
        guard dateRange.startDate <= now, dateRange.endDate > now else { return plan }

        let cappedRange = HomeQueryDateRange(startDate: dateRange.startDate, endDate: now)
        return HomeQueryPlan(
            metric: plan.metric,
            dateRange: cappedRange,
            comparisonDateRange: plan.comparisonDateRange,
            resultLimit: plan.resultLimit,
            confidenceBand: plan.confidenceBand,
            targetName: plan.targetName,
            periodUnit: plan.periodUnit
        )
    }

    private func wantsSpendByDay(_ normalizedPrompt: String) -> Bool {
        let groupingPhrases = [
            "by day",
            "per day",
            "daily",
            "day by day"
        ]
        let spendingPhrases = [
            "break down my spending",
            "breakdown my spending",
            "spending",
            "spend"
        ]

        return groupingPhrases.contains(where: { normalizedPrompt.contains($0) })
            && spendingPhrases.contains(where: { normalizedPrompt.contains($0) })
    }

    private func normalized(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct HomeAssistantDailySpendAnswerBuilder {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func makeAnswer(
        queryID: UUID,
        userPrompt: String?,
        dateRange: HomeQueryDateRange,
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense]
    ) -> HomeAnswer {
        let dayTotals = dailyTotals(
            in: dateRange,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses
        )

        guard dayTotals.isEmpty == false else {
            return HomeAnswer(
                queryID: queryID,
                kind: .message,
                userPrompt: userPrompt,
                title: "Daily Spending",
                subtitle: "No spending activity in this range yet.",
                primaryValue: nil,
                rows: []
            )
        }

        let total = dayTotals.reduce(0) { $0 + $1.total }
        let rows = dayTotals.map { item in
            HomeAnswerRow(
                title: AppDateFormat.shortDate(item.day),
                value: CurrencyFormatter.string(from: item.total)
            )
        }

        return HomeAnswer(
            queryID: queryID,
            kind: .list,
            userPrompt: userPrompt,
            title: "Daily Spending",
            subtitle: "\(AppDateFormat.shortDate(dateRange.startDate)) - \(AppDateFormat.shortDate(dateRange.endDate))",
            primaryValue: CurrencyFormatter.string(from: total),
            rows: rows
        )
    }

    private func dailyTotals(
        in range: HomeQueryDateRange,
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense]
    ) -> [(day: Date, total: Double)] {
        var totalsByDay: [Date: Double] = [:]

        for expense in plannedExpenses where expense.expenseDate >= range.startDate && expense.expenseDate <= range.endDate {
            let day = calendar.startOfDay(for: expense.expenseDate)
            totalsByDay[day, default: 0] += expense.effectiveAmount()
        }

        for expense in variableExpenses where expense.transactionDate >= range.startDate && expense.transactionDate <= range.endDate {
            let day = calendar.startOfDay(for: expense.transactionDate)
            totalsByDay[day, default: 0] += expense.ledgerSignedAmount()
        }

        return totalsByDay
            .map { (day: $0.key, total: $0.value) }
            .sorted { $0.day < $1.day }
    }
}

struct HomeAssistantIncomePeriodSummaryAnswerBuilder {
    private let currencyFormatter: NumberFormatter

    init(currencyFormatter: NumberFormatter? = nil) {
        if let currencyFormatter {
            self.currencyFormatter = currencyFormatter
        } else {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.locale = .autoupdatingCurrent
            self.currencyFormatter = formatter
        }
    }

    func makeAnswer(
        queryID: UUID,
        userPrompt: String?,
        dateRange: HomeQueryDateRange,
        incomes: [Income]
    ) -> HomeAnswer {
        let inRange = incomes.filter { $0.date >= dateRange.startDate && $0.date <= dateRange.endDate }
        let planned = inRange.filter(\.isPlanned).reduce(0.0) { $0 + $1.amount }
        let actual = inRange.filter { $0.isPlanned == false }.reduce(0.0) { $0 + $1.amount }
        let gap = actual - planned
        let sources = Dictionary(grouping: inRange.filter { $0.isPlanned == false }, by: \.source)
            .map { (source: $0.key, total: $0.value.reduce(0.0) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }

        guard planned != 0 || actual != 0 else {
            return HomeAnswer(
                queryID: queryID,
                kind: .message,
                userPrompt: userPrompt,
                title: "Income Summary",
                subtitle: "No income in this range yet.",
                primaryValue: nil,
                rows: []
            )
        }

        var rows: [HomeAnswerRow] = [
            HomeAnswerRow(title: "Actual income", value: currency(actual)),
            HomeAnswerRow(title: "Planned income", value: currency(planned)),
            HomeAnswerRow(title: "Gap vs planned", value: delta(gap))
        ]
        rows.append(contentsOf: sources.prefix(3).map { HomeAnswerRow(title: $0.source, value: currency($0.total)) })

        return HomeAnswer(
            queryID: queryID,
            kind: .list,
            userPrompt: userPrompt,
            title: "Income Summary",
            subtitle: rangeLabel(dateRange),
            primaryValue: currency(actual),
            rows: rows
        )
    }

    private func currency(_ value: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    private func delta(_ value: Double) -> String {
        if value > 0 { return "Up \(currency(value))" }
        if value < 0 { return "Down \(currency(abs(value)))" }
        return "No change"
    }

    private func rangeLabel(_ range: HomeQueryDateRange) -> String {
        "\(AppDateFormat.shortDate(range.startDate)) - \(AppDateFormat.shortDate(range.endDate))"
    }
}

struct HomeAssistantCategoryAvailabilityAnswerBuilder {
    func makeAnswer(
        queryID: UUID,
        userPrompt: String?,
        dateRange: HomeQueryDateRange,
        budgets: [Budget],
        categories: [Category],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense]
    ) -> HomeAnswer {
        let result = HomeCategoryLimitsAggregator.build(
            budgets: budgets,
            categories: categories,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            rangeStart: dateRange.startDate,
            rangeEnd: dateRange.endDate
        )

        guard result.metrics.isEmpty == false else {
            return HomeAnswer(
                queryID: queryID,
                kind: .message,
                userPrompt: userPrompt,
                title: "Category Availability",
                subtitle: "No category budget availability to show for this range.",
                primaryValue: nil,
                rows: []
            )
        }

        let rows = result.metrics.prefix(5).map { metric in
            HomeAnswerRow(
                title: metric.name,
                value: availabilityLabel(metric)
            )
        }

        return HomeAnswer(
            queryID: queryID,
            kind: .list,
            userPrompt: userPrompt,
            title: "Category Availability",
            subtitle: "\(result.overCount) over, \(result.nearCount) near",
            primaryValue: rows.first?.value,
            rows: Array(rows)
        )
    }

    private func availabilityLabel(_ metric: CategoryAvailabilityMetric) -> String {
        guard metric.isLimited else {
            return "\(CurrencyFormatter.string(from: metric.spentTotal)) spent"
        }

        let status: String
        switch metric.status(for: .all, nearThreshold: HomeCategoryLimitsAggregator.defaultNearThreshold) {
        case .over:
            status = "Over"
        case .near:
            status = "Near"
        case .ok:
            status = "Available"
        }

        let available = metric.availableRaw(for: .all) ?? 0
        return "\(status) \(CurrencyFormatter.string(from: abs(available)))"
    }
}

struct HomeAssistantCardSummaryAnswerBuilder {
    func makeAnswer(
        queryID: UUID,
        userPrompt: String?,
        dateRange: HomeQueryDateRange,
        cards: [Card],
        targetName: String?
    ) -> HomeAnswer {
        let cardMetrics = cards
            .filter { card in
                guard let targetName else { return true }
                return card.name.localizedCaseInsensitiveCompare(targetName) == .orderedSame
            }
            .map { card in
                (
                    card: card,
                    metrics: HomeCardMetricsCalculator.metrics(
                        for: card,
                        start: dateRange.startDate,
                        end: dateRange.endDate,
                        excludeFuturePlannedExpenses: false,
                        excludeFutureVariableExpenses: false
                    )
                )
            }
            .sorted { $0.metrics.total > $1.metrics.total }

        guard cardMetrics.isEmpty == false, let top = cardMetrics.first, top.metrics.total > 0 else {
            return HomeAnswer(
                queryID: queryID,
                kind: .message,
                userPrompt: userPrompt,
                title: targetName.map { "\($0) Summary" } ?? "Card Summary",
                subtitle: "No card activity in this range yet.",
                primaryValue: nil,
                rows: []
            )
        }

        let rows: [HomeAnswerRow]
        if targetName != nil {
            rows = [
                HomeAnswerRow(title: "Total", value: CurrencyFormatter.string(from: top.metrics.total)),
                HomeAnswerRow(title: "Planned", value: CurrencyFormatter.string(from: top.metrics.plannedTotal)),
                HomeAnswerRow(title: "Variable", value: CurrencyFormatter.string(from: top.metrics.variableTotal))
            ]
        } else {
            rows = cardMetrics.prefix(5).map { item in
                HomeAnswerRow(title: item.card.name, value: CurrencyFormatter.string(from: item.metrics.total))
            }
        }

        return HomeAnswer(
            queryID: queryID,
            kind: .list,
            userPrompt: userPrompt,
            title: targetName.map { "\($0) Summary" } ?? "Card Summary",
            subtitle: "\(AppDateFormat.shortDate(dateRange.startDate)) - \(AppDateFormat.shortDate(dateRange.endDate))",
            primaryValue: CurrencyFormatter.string(from: top.metrics.total),
            rows: rows
        )
    }
}
