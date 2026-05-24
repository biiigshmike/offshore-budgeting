import Foundation

struct MarinaPresetPromptContext: Equatable {
    let budgetNames: [String]
    let cardNames: [String]
    let categoryNames: [String]
    let presetTitles: [String]
    let incomeSourceNames: [String]
    let savingsAccountNames: [String]
    let allocationAccountNames: [String]
    let supportsPromptBackedSuggestions: Bool

    init(
        budgetNames: [String] = [],
        cardNames: [String] = [],
        categoryNames: [String] = [],
        presetTitles: [String] = [],
        incomeSourceNames: [String] = [],
        savingsAccountNames: [String] = [],
        allocationAccountNames: [String] = [],
        supportsPromptBackedSuggestions: Bool = false
    ) {
        self.budgetNames = Self.clean(budgetNames)
        self.cardNames = Self.clean(cardNames)
        self.categoryNames = Self.clean(categoryNames)
        self.presetTitles = Self.clean(presetTitles)
        self.incomeSourceNames = Self.clean(incomeSourceNames)
        self.savingsAccountNames = Self.clean(savingsAccountNames)
        self.allocationAccountNames = Self.clean(allocationAccountNames)
        self.supportsPromptBackedSuggestions = supportsPromptBackedSuggestions
    }

    static let empty = MarinaPresetPromptContext()

    var primaryBudgetName: String? { budgetNames.first }
    var primaryCardName: String? { cardNames.first }
    var primaryCategoryName: String? { categoryNames.first }
    var primaryPresetTitle: String? { presetTitles.first }
    var primaryIncomeSourceName: String? { incomeSourceNames.first }
    var primarySavingsAccountName: String? { savingsAccountNames.first }
    var primaryAllocationAccountName: String? { allocationAccountNames.first }

    private static func clean(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var cleaned: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            cleaned.append(trimmed)
        }
        return cleaned
    }
}

enum MarinaPresetPromptGroup: String, CaseIterable, Identifiable {
    case budgets
    case income
    case accounts
    case expenses
    case trends
    case planning

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .budgets:
            return "chart.pie.fill"
        case .income:
            return "calendar"
        case .accounts:
            return "creditcard"
        case .expenses:
            return "dollarsign"
        case .trends:
            return "chart.bar.xaxis"
        case .planning:
            return "bubble.left.and.text.bubble.right"
        }
    }

    var title: String {
        switch self {
        case .budgets:
            return "Budget Prompt Suggestions"
        case .income:
            return "Income Prompt Suggestions"
        case .accounts:
            return "Account Prompt Suggestions"
        case .expenses:
            return "Expense Prompt Suggestions"
        case .trends:
            return "Trend Prompt Suggestions"
        case .planning:
            return "Planning Prompt Suggestions"
        }
    }
}

struct MarinaPresetPrompt: Identifiable, Equatable {
    let id: String
    let group: MarinaPresetPromptGroup?
    let title: String
    let query: HomeQuery
    let promptText: String?
    let action: MarinaSuggestionAction?
    let expectedMetric: HomeQueryMetric
    let expectedAnswerKind: HomeAnswerKind?
    let expectedTitleFamily: String

    init(
        group: MarinaPresetPromptGroup?,
        title: String,
        query: HomeQuery,
        promptText: String? = nil,
        action: MarinaSuggestionAction? = nil,
        expectedAnswerKind: HomeAnswerKind?,
        expectedTitleFamily: String
    ) {
        let trimmedPrompt = promptText?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = [group?.rawValue ?? "default", title, trimmedPrompt ?? query.intent.rawValue].joined(separator: "::")
        self.group = group
        self.title = title
        self.query = query
        self.promptText = trimmedPrompt?.isEmpty == false ? trimmedPrompt : nil
        self.action = action
        self.expectedMetric = query.intent.metric
        self.expectedAnswerKind = expectedAnswerKind
        self.expectedTitleFamily = expectedTitleFamily
    }

    var isPromptBacked: Bool {
        promptText != nil
    }

    var suggestion: MarinaSuggestion {
        MarinaSuggestion(
            title: title,
            query: query,
            promptText: promptText,
            action: action,
            reasoning: "preset_prompt:\(id)"
        )
    }
}

enum MarinaPresetPromptCatalog {
    static func prompts(defaultPeriodUnit: HomeQueryPeriodUnit) -> [MarinaPresetPrompt] {
        prompts(defaultPeriodUnit: defaultPeriodUnit, context: .empty)
    }

    static func prompts(
        defaultPeriodUnit: HomeQueryPeriodUnit,
        context: MarinaPresetPromptContext
    ) -> [MarinaPresetPrompt] {
        emptyStatePrompts(defaultPeriodUnit: defaultPeriodUnit, context: context) + defaultPrompts()
    }

    static func prompts(
        for group: MarinaPresetPromptGroup,
        defaultPeriodUnit: HomeQueryPeriodUnit,
        context: MarinaPresetPromptContext = .empty
    ) -> [MarinaPresetPrompt] {
        emptyStatePrompts(defaultPeriodUnit: defaultPeriodUnit, context: context).filter { $0.group == group }
    }

    static func suggestions(
        for group: MarinaPresetPromptGroup,
        defaultPeriodUnit: HomeQueryPeriodUnit,
        context: MarinaPresetPromptContext = .empty
    ) -> [MarinaSuggestion] {
        prompts(for: group, defaultPeriodUnit: defaultPeriodUnit, context: context).map(\.suggestion)
    }

    static func defaultSuggestions() -> [MarinaSuggestion] {
        defaultPrompts().map(\.suggestion)
    }

    private static func emptyStatePrompts(
        defaultPeriodUnit: HomeQueryPeriodUnit,
        context: MarinaPresetPromptContext
    ) -> [MarinaPresetPrompt] {
        var prompts: [MarinaPresetPrompt] = [
            prompt(.budgets, "How am I doing this month?", .periodOverview, .list, "Budget Overview"),
            prompt(.budgets, "Spend this month", .spendThisMonth, .metric, "Spend"),
            prompt(.budgets, "Compare with last month", .compareThisMonthToPreviousMonth, .comparison, "Spending Comparison"),
            prompt(.budgets, "How am I doing with savings?", .savingsStatus, .metric, "Savings Status"),

            prompt(.income, "Actual income this month", text: "What is my actual income this month?", fallback: .incomeAverageActual, requiresPromptSupport: true, context: context, expectedAnswerKind: .metric, expectedTitleFamily: "Actual Income"),
            prompt(.income, "Average actual income this year", .incomeAverageActual, .metric, "Average Actual Income"),
            prompt(.income, "Income share by source this month", .incomeSourceShare, .list, "Income Share by Source"),
            prompt(
                .income,
                "Income share trend (last 4 months)",
                HomeQuery(intent: .incomeSourceShareTrend, resultLimit: 4, periodUnit: .month),
                .list,
                "Income Share Trend"
            ),

            prompt(.accounts, "Card spend total this month", .cardSpendTotal, .metric, "Card Spend"),
            prompt(.accounts, "Variable spending habits by card", .cardVariableSpendingHabits, .list, "Card Spending Habits"),
            prompt(.accounts, "Savings status", .savingsStatus, .metric, "Savings Status"),
            prompt(
                .accounts,
                "Savings average (last 6 periods)",
                HomeQuery(intent: .savingsAverageRecentPeriods, resultLimit: 6, periodUnit: defaultPeriodUnit),
                .metric,
                "Average Savings"
            ),

            prompt(.expenses, "Spend this month", .spendThisMonth, .metric, "Spend"),
            prompt(.expenses, "Top categories this month", .topCategoriesThisMonth, .list, "Top Categories"),
            prompt(.expenses, "Category spend share this month", .categorySpendShare, .list, "Category Spend Share"),
            prompt(.expenses, "Top merchants this month", .topMerchantsThisMonth, .list, "Top Merchants"),
            prompt(.expenses, "Largest recent expenses", .largestRecentTransactions, .list, "Largest Recent Expenses"),
            prompt(.expenses, "Do I have presets due soon?", .presetDueSoon, .list, "Presets Due Soon"),
            prompt(.expenses, "Most expensive preset", .presetHighestCost, .list, "Highest Preset Costs"),
            prompt(.expenses, "Top preset category", .presetTopCategory, .list, "Categories Assigned to Presets"),
            prompt(.expenses, "Preset spend by category", .presetCategorySpend, .list, "Preset Spend by Category"),

            prompt(.trends, "Compare with last month", .compareThisMonthToPreviousMonth, .comparison, "Spending Comparison"),
            prompt(
                .trends,
                "Income share trend (last 4 months)",
                HomeQuery(intent: .incomeSourceShareTrend, resultLimit: 4, periodUnit: .month),
                .list,
                "Income Share Trend"
            ),
            prompt(
                .trends,
                "Category share trend (last 4 months)",
                HomeQuery(intent: .categorySpendShareTrend, resultLimit: 4, periodUnit: .month),
                .list,
                "Category Share Trend"
            ),
            prompt(.trends, "Top category changes", .topCategoryChangesThisMonth, .list, "Top Category Changes"),
            prompt(.trends, "Top card changes", .topCardChangesThisMonth, .list, "Top Card Changes"),

            prompt(.planning, "Safe spend today", .safeSpendToday, .metric, "Safe Spend Today"),
            prompt(.planning, "Forecast savings", .forecastSavings, .metric, "Forecast Savings"),
            prompt(.planning, "Next planned expense", .nextPlannedExpense, .message, "Next Planned Expense"),
            prompt(.planning, "Potential savings by category", .categoryPotentialSavings, .list, "Category Potential Savings"),
            prompt(.planning, "Category reallocation guidance", .categoryReallocationGuidance, .list, "Category Reallocation Guidance")
        ].compactMap { $0 }

        guard context.supportsPromptBackedSuggestions else {
            return prompts
        }

        prompts.append(contentsOf: promptBackedPrompts(context: context))
        return prompts
    }

    private static func defaultPrompts() -> [MarinaPresetPrompt] {
        [
            prompt(nil, "How am I doing this month?", .periodOverview, .list, "Budget Overview"),
            prompt(nil, "Spend this month", .spendThisMonth, .metric, "Spend"),
            prompt(nil, "Top categories this month", .topCategoriesThisMonth, .list, "Top Categories"),
            prompt(nil, "Compare with last month", .compareThisMonthToPreviousMonth, .comparison, "Spending Comparison"),
            prompt(nil, "Safe spend today", .safeSpendToday, .metric, "Safe Spend Today"),
            prompt(nil, "Next planned expense", .nextPlannedExpense, .message, "Next Planned Expense"),
            prompt(nil, "Top merchants this month", .topMerchantsThisMonth, .list, "Top Merchants"),
            prompt(nil, "Largest recent expenses", .largestRecentTransactions, .list, "Largest Recent Expenses"),
            prompt(nil, "Variable spending habits by card", .cardVariableSpendingHabits, .list, "Card Spending Habits"),
            prompt(nil, "Average actual income this year", .incomeAverageActual, .metric, "Average Actual Income"),
            prompt(nil, "How am I doing this month with savings?", .savingsStatus, .metric, "Savings Status"),
            prompt(nil, "Income share by source this month", .incomeSourceShare, .list, "Income Share by Source"),
            prompt(nil, "Do I have presets due soon?", .presetDueSoon, .list, "Presets Due Soon")
        ]
    }

    private static func prompt(
        _ group: MarinaPresetPromptGroup?,
        _ title: String,
        _ intent: HomeQueryIntent,
        _ expectedAnswerKind: HomeAnswerKind?,
        _ expectedTitleFamily: String
    ) -> MarinaPresetPrompt {
        prompt(
            group,
            title,
            HomeQuery(intent: intent),
            expectedAnswerKind,
            expectedTitleFamily
        )
    }

    private static func prompt(
        _ group: MarinaPresetPromptGroup?,
        _ title: String,
        _ query: HomeQuery,
        _ expectedAnswerKind: HomeAnswerKind?,
        _ expectedTitleFamily: String
    ) -> MarinaPresetPrompt {
        MarinaPresetPrompt(
            group: group,
            title: title,
            query: query,
            expectedAnswerKind: expectedAnswerKind,
            expectedTitleFamily: expectedTitleFamily
        )
    }

    private static func prompt(
        _ group: MarinaPresetPromptGroup?,
        _ title: String,
        text: String,
        fallback fallbackIntent: HomeQueryIntent,
        requiresPromptSupport: Bool,
        context: MarinaPresetPromptContext,
        expectedAnswerKind: HomeAnswerKind?,
        expectedTitleFamily: String
    ) -> MarinaPresetPrompt? {
        guard requiresPromptSupport == false || context.supportsPromptBackedSuggestions else {
            return nil
        }
        return MarinaPresetPrompt(
            group: group,
            title: title,
            query: HomeQuery(intent: fallbackIntent),
            promptText: text,
            expectedAnswerKind: expectedAnswerKind,
            expectedTitleFamily: expectedTitleFamily
        )
    }

    private static func typedPrompt(
        _ group: MarinaPresetPromptGroup?,
        _ title: String,
        typedIntent: MarinaCanonicalTypedIntent,
        text: String,
        fallback fallbackIntent: HomeQueryIntent,
        requiresPromptSupport: Bool,
        context: MarinaPresetPromptContext,
        expectedAnswerKind: HomeAnswerKind?,
        expectedTitleFamily: String
    ) -> MarinaPresetPrompt? {
        guard requiresPromptSupport == false || context.supportsPromptBackedSuggestions else {
            return nil
        }
        return MarinaPresetPrompt(
            group: group,
            title: title,
            query: HomeQuery(intent: fallbackIntent),
            promptText: text,
            action: .typedIntent(typedIntent),
            expectedAnswerKind: expectedAnswerKind,
            expectedTitleFamily: expectedTitleFamily
        )
    }

    private static func promptBackedPrompts(
        context: MarinaPresetPromptContext
    ) -> [MarinaPresetPrompt] {
        var prompts: [MarinaPresetPrompt?] = [
            typedPrompt(.budgets, "What is my active budget?", typedIntent: .activeBudgetStatus, text: "What is my active budget?", fallback: .periodOverview, requiresPromptSupport: true, context: context, expectedAnswerKind: .message, expectedTitleFamily: "Active Budget"),
            prompt(.budgets, "Which budgets share links?", text: "Which budgets share the same card or preset?", fallback: .periodOverview, requiresPromptSupport: true, context: context, expectedAnswerKind: .list, expectedTitleFamily: "Budget Shared Links"),
            prompt(.income, "Compare planned vs actual income", text: "Compare actual vs planned income this month.", fallback: .incomeAverageActual, requiresPromptSupport: true, context: context, expectedAnswerKind: .comparison, expectedTitleFamily: "Income"),
            prompt(.income, "Expenses before next income", text: "What upcoming expenses will hit before my next income?", fallback: .nextPlannedExpense, requiresPromptSupport: true, context: context, expectedAnswerKind: .list, expectedTitleFamily: "Upcoming Expenses"),
            prompt(.accounts, "Show savings activity", text: "Show savings activity.", fallback: .savingsAverageRecentPeriods, requiresPromptSupport: true, context: context, expectedAnswerKind: .list, expectedTitleFamily: "Savings Activity"),
            prompt(.accounts, "Show settlement rows", text: "Show settlement rows.", fallback: .savingsStatus, requiresPromptSupport: true, context: context, expectedAnswerKind: .list, expectedTitleFamily: "Settlement Rows"),
            prompt(.expenses, "Show recent transactions", text: "Show recent transactions.", fallback: .largestRecentTransactions, requiresPromptSupport: true, context: context, expectedAnswerKind: .list, expectedTitleFamily: "Recent Transactions"),
            prompt(.trends, "Spending increase drivers", text: "Why is my spending higher this month than last month?", fallback: .compareThisMonthToPreviousMonth, requiresPromptSupport: true, context: context, expectedAnswerKind: .list, expectedTitleFamily: "Spending Increase Drivers"),
            prompt(.trends, "Unusual merchant spend", text: "What merchants are unusually high this month?", fallback: .topMerchantsThisMonth, requiresPromptSupport: true, context: context, expectedAnswerKind: .list, expectedTitleFamily: "Unusual Merchant Spend"),
            prompt(.trends, "Recurring expense increases", text: "What recurring expenses increased?", fallback: .mostFrequentTransactions, requiresPromptSupport: true, context: context, expectedAnswerKind: .list, expectedTitleFamily: "Recurring Charge"),
            prompt(.planning, "Categories over pace", text: "What categories are over pace for this point in the month?", fallback: .categoryPotentialSavings, requiresPromptSupport: true, context: context, expectedAnswerKind: .list, expectedTitleFamily: "Categories Over Pace")
        ]

        if let budgetName = context.primaryBudgetName {
            prompts.append(prompt(.budgets, "Cards linked to \(budgetName)", text: "Which cards are linked to \(budgetName)?", fallback: .periodOverview, requiresPromptSupport: true, context: context, expectedAnswerKind: .list, expectedTitleFamily: "Cards linked"))
            prompts.append(prompt(.budgets, "Presets linked to \(budgetName)", text: "Which presets are linked to \(budgetName)?", fallback: .presetDueSoon, requiresPromptSupport: true, context: context, expectedAnswerKind: .list, expectedTitleFamily: "Presets linked"))
        }

        if let categoryName = context.primaryCategoryName {
            prompts.append(prompt(.budgets, "\(categoryName) budget limit", text: "Show my \(categoryName) budget limit.", fallback: .categorySpendTotal, requiresPromptSupport: true, context: context, expectedAnswerKind: .message, expectedTitleFamily: "Budget Limit"))
            prompts.append(prompt(.planning, "What if I cut \(categoryName)?", text: "What if I spend 200 less on \(categoryName)?", fallback: .forecastSavings, requiresPromptSupport: true, context: context, expectedAnswerKind: .message, expectedTitleFamily: "Budget Forecast"))
        }

        if let cardName = context.primaryCardName {
            prompts.append(prompt(.accounts, "Show \(cardName)", text: "Show \(cardName) card details.", fallback: .cardSnapshotSummary, requiresPromptSupport: true, context: context, expectedAnswerKind: .message, expectedTitleFamily: "Card"))
            prompts.append(prompt(.accounts, "\(cardName) recent transactions", text: "Show expenses on \(cardName).", fallback: .largestRecentTransactions, requiresPromptSupport: true, context: context, expectedAnswerKind: .list, expectedTitleFamily: "Recent Transactions"))
        }

        if let allocationName = context.primaryAllocationAccountName {
            prompts.append(prompt(.accounts, "\(allocationName) balance", text: "What is \(allocationName)'s balance?", fallback: .savingsStatus, requiresPromptSupport: true, context: context, expectedAnswerKind: .message, expectedTitleFamily: "Reconciliation Balance"))
            prompts.append(prompt(.accounts, "\(allocationName) allocation rows", text: "Show \(allocationName) allocation rows.", fallback: .largestRecentTransactions, requiresPromptSupport: true, context: context, expectedAnswerKind: .list, expectedTitleFamily: "Allocation Rows"))
        }

        if let presetTitle = context.primaryPresetTitle {
            prompts.append(prompt(.expenses, "Planned from \(presetTitle)", text: "What planned expenses came from \(presetTitle)?", fallback: .presetDueSoon, requiresPromptSupport: true, context: context, expectedAnswerKind: .list, expectedTitleFamily: "Planned Expenses"))
        }

        if let incomeSourceName = context.primaryIncomeSourceName {
            prompts.append(prompt(.income, "\(incomeSourceName) income", text: "How much did \(incomeSourceName) pay this month?", fallback: .incomeSourceShare, requiresPromptSupport: true, context: context, expectedAnswerKind: .metric, expectedTitleFamily: "Income"))
        }

        if let savingsAccountName = context.primarySavingsAccountName {
            prompts.append(prompt(.accounts, "Show \(savingsAccountName)", text: "Show \(savingsAccountName) savings account status.", fallback: .savingsStatus, requiresPromptSupport: true, context: context, expectedAnswerKind: .message, expectedTitleFamily: "Savings Account"))
        }

        return prompts.compactMap { $0 }
    }
}

struct MarinaPresetPromptQueryAdapter {
    func executablePlan(
        for query: HomeQuery,
        sourceTitle: String
    ) -> MarinaExecutableAggregationPlan {
        let spec = spec(for: query)
        let target = query.targetName.map {
            MarinaResolvedAggregationTarget(
                role: .filter,
                entityType: spec.targetType ?? .transaction,
                displayName: $0
            )
        }
        let aggregationPlan = MarinaAggregationPlan(
            status: .executable,
            operation: spec.operation,
            measure: spec.measure,
            targets: target.map { [$0] } ?? [],
            dateRange: query.dateRange,
            comparisonDateRange: query.comparisonDateRange,
            grouping: spec.grouping.map { MarinaGroupingCandidate(dimension: $0) },
            ranking: spec.ranking.map { MarinaRankingCandidate(direction: $0, limit: query.resultLimit) },
            limit: query.resultLimit,
            incomeStatusScope: spec.incomeStatus,
            responseShape: spec.responseShape,
            routeIntent: MarinaRouteIntent(
                kind: spec.routeKind,
                subject: spec.subject,
                operation: spec.operation,
                measure: spec.measure,
                grouping: spec.grouping,
                targetTypes: target.map { [$0.entityType] } ?? [],
                requestedDetail: spec.requestedDetail,
                responseShape: spec.responseShape,
                preferredExecutorRoute: .homeAdapter
            )
        )
        let homeQueryPlan = HomeQueryPlan(
            metric: query.intent.metric,
            dateRange: query.dateRange,
            comparisonDateRange: query.comparisonDateRange,
            resultLimit: query.resultLimit,
            confidenceBand: .high,
            targetName: query.targetName,
            targetTypeRaw: spec.targetType?.rawValue,
            periodUnit: query.periodUnit
        )
        return MarinaExecutableAggregationPlan(
            aggregationPlan: aggregationPlan,
            homeQueryPlan: homeQueryPlan
        )
    }

    func candidate(
        for query: HomeQuery,
        sourceTitle: String
    ) -> MarinaQueryPlanCandidate {
        let spec = spec(for: query)
        let targetMention = query.targetName.map {
            MarinaUnresolvedEntityMention(
                role: .filter,
                rawText: $0,
                typeHint: spec.targetType
            )
        }
        let timeScopes = [
            query.dateRange.map {
                MarinaUnresolvedTimeScope(
                    role: .primary,
                    rawText: nil,
                    resolvedRangeHint: $0,
                    periodUnitHint: query.periodUnit
                )
            },
            query.comparisonDateRange.map {
                MarinaUnresolvedTimeScope(
                    role: .comparison,
                    rawText: nil,
                    resolvedRangeHint: $0,
                    periodUnitHint: query.periodUnit
                )
            }
        ].compactMap { $0 }

        return MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: sourceTitle,
            operation: spec.operation,
            measure: spec.measure,
            entityMentions: targetMention.map { [$0] } ?? [],
            timeScopes: timeScopes,
            grouping: spec.grouping.map { MarinaGroupingCandidate(dimension: $0) },
            ranking: spec.ranking.map { MarinaRankingCandidate(direction: $0, limit: query.resultLimit) },
            limit: query.resultLimit,
            responseShapeHint: spec.responseShape,
            confidence: .high,
            routeIntent: MarinaRouteIntent(
                kind: spec.routeKind,
                subject: spec.subject,
                operation: spec.operation,
                measure: spec.measure,
                grouping: spec.grouping,
                targetTypes: spec.targetType.map { [$0] } ?? [],
                requestedDetail: spec.requestedDetail,
                responseShape: spec.responseShape,
                preferredExecutorRoute: .homeAdapter
            )
        )
    }

    private func spec(for query: HomeQuery) -> Spec {
        switch query.intent {
        case .periodOverview:
            return Spec(.lookupDetails, .remainingBudget, .summaryCard, subject: .budgets, requestedDetail: .status, routeKind: .periodOverview)
        case .spendThisMonth:
            return Spec(.sum, .spend, .scalarCurrency, subject: .variableExpenses)
        case .categorySpendTotal:
            return Spec(.sum, .spend, .scalarCurrency, subject: .variableExpenses, targetType: .category)
        case .topCategoriesThisMonth:
            return Spec(.rank, .spend, .rankedList, subject: .variableExpenses, grouping: .category, ranking: .top)
        case .compareThisMonthToPreviousMonth:
            return Spec(.compare, .spend, .comparison, subject: .variableExpenses)
        case .compareCategoryThisMonthToPreviousMonth:
            return Spec(.compare, .spend, .comparison, subject: .variableExpenses, targetType: .category)
        case .compareCardThisMonthToPreviousMonth:
            return Spec(.compare, .spend, .comparison, subject: .variableExpenses, targetType: .card)
        case .compareIncomeSourceThisMonthToPreviousMonth:
            return Spec(.compare, .income, .comparison, subject: .income, targetType: .incomeSource, incomeStatus: .actual)
        case .compareMerchantThisMonthToPreviousMonth:
            return Spec(.compare, .spend, .comparison, subject: .variableExpenses, targetType: .merchant)
        case .largestRecentTransactions:
            return Spec(.listRows, .transactionAmount, .rankedList, subject: .variableExpenses, grouping: .transaction, ranking: .newest)
        case .mostFrequentTransactions:
            return Spec(.rank, .transactionFrequency, .rankedList, subject: .variableExpenses, grouping: .transaction, ranking: .mostFrequent)
        case .spendAveragePerPeriod:
            return Spec(.average, .spend, .scalarCurrency, subject: .variableExpenses)
        case .cardSpendTotal:
            return Spec(.sum, .spend, .rankedList, subject: .variableExpenses, targetType: .card, grouping: .card)
        case .cardVariableSpendingHabits:
            return Spec(.listRows, .spend, .rankedList, subject: .variableExpenses, grouping: .card)
        case .incomeAverageActual:
            return Spec(.average, .income, .scalarCurrency, subject: .income, targetType: .incomeSource, incomeStatus: .actual)
        case .savingsStatus:
            return Spec(.lookupDetails, .savings, .summaryCard, subject: .savingsAccounts, requestedDetail: .status)
        case .savingsAverageRecentPeriods:
            return Spec(.average, .savingsMovement, .rankedList, subject: .savingsLedgerEntries, grouping: .savingsLedgerEntry)
        case .incomeSourceShare:
            return Spec(.sum, .income, .groupedBreakdown, subject: .income, targetType: .incomeSource, grouping: .incomeSource, incomeStatus: .actual)
        case .categorySpendShare:
            return Spec(.sum, .categoryShare, .groupedBreakdown, subject: .variableExpenses, targetType: .category, grouping: .category)
        case .incomeSourceShareTrend:
            return Spec(.trend, .income, .chartRows, subject: .income, targetType: .incomeSource, grouping: .incomeSource, incomeStatus: .actual)
        case .categorySpendShareTrend:
            return Spec(.trend, .categoryShare, .chartRows, subject: .variableExpenses, targetType: .category, grouping: .category)
        case .presetDueSoon:
            return Spec(.listRows, .presetAmount, .relationshipList, subject: .plannedExpenses, grouping: .preset, ranking: .newest)
        case .presetHighestCost:
            return Spec(.rank, .presetAmount, .rankedList, subject: .plannedExpenses, grouping: .preset, ranking: .largest)
        case .presetTopCategory:
            return Spec(.rank, .presetAmount, .rankedList, subject: .plannedExpenses, grouping: .category, ranking: .top)
        case .presetCategorySpend:
            return Spec(.sum, .presetAmount, .groupedBreakdown, subject: .plannedExpenses, targetType: .category, grouping: .category)
        case .categoryPotentialSavings:
            return Spec(.simulate, .categoryShare, .summaryCard, subject: .variableExpenses, targetType: .category, grouping: .category)
        case .categoryReallocationGuidance:
            return Spec(.simulate, .categoryShare, .summaryCard, subject: .variableExpenses, targetType: .category, grouping: .category)
        case .safeSpendToday:
            return Spec(.lookupDetails, .remainingBudget, .summaryCard, subject: .budgets, requestedDetail: .status)
        case .forecastSavings:
            return Spec(.forecast, .savings, .summaryCard, subject: .savingsAccounts)
        case .nextPlannedExpense:
            return Spec(.lookupDetails, .presetAmount, .relationshipList, subject: .plannedExpenses, requestedDetail: .date)
        case .spendTrendsSummary:
            return Spec(.trend, .spend, .chartRows, subject: .variableExpenses)
        case .cardSnapshotSummary:
            return Spec(.lookupDetails, .spend, .summaryCard, subject: .variableExpenses, targetType: .card, grouping: .card)
        case .merchantSpendTotal:
            return Spec(.sum, .spend, .scalarCurrency, subject: .variableExpenses, targetType: .merchant)
        case .merchantSpendSummary:
            return Spec(.lookupDetails, .spend, .summaryCard, subject: .variableExpenses, targetType: .merchant)
        case .topMerchantsThisMonth:
            return Spec(.rank, .spend, .rankedList, subject: .variableExpenses, grouping: .merchant, ranking: .top)
        case .topCategoryChangesThisMonth:
            return Spec(.compare, .spend, .rankedList, subject: .variableExpenses, grouping: .category, ranking: .top)
        case .topCardChangesThisMonth:
            return Spec(.compare, .spend, .rankedList, subject: .variableExpenses, grouping: .card, ranking: .top)
        }
    }

    private struct Spec {
        let operation: MarinaCandidateOperation
        let measure: MarinaCandidateMeasure
        let responseShape: MarinaResponseShapeHint
        let subject: MarinaSubject
        let targetType: MarinaCandidateEntityTypeHint?
        let grouping: MarinaGroupingDimensionCandidate?
        let ranking: MarinaRankingDirectionCandidate?
        let incomeStatus: MarinaIncomeStatusScope?
        let requestedDetail: MarinaSemanticRequestedDetail?
        let routeKind: MarinaRouteIntentKind

        init(
            _ operation: MarinaCandidateOperation,
            _ measure: MarinaCandidateMeasure,
            _ responseShape: MarinaResponseShapeHint,
            subject: MarinaSubject,
            targetType: MarinaCandidateEntityTypeHint? = nil,
            grouping: MarinaGroupingDimensionCandidate? = nil,
            ranking: MarinaRankingDirectionCandidate? = nil,
            incomeStatus: MarinaIncomeStatusScope? = nil,
            requestedDetail: MarinaSemanticRequestedDetail? = nil,
            routeKind: MarinaRouteIntentKind = .generic
        ) {
            self.operation = operation
            self.measure = measure
            self.responseShape = responseShape
            self.subject = subject
            self.targetType = targetType
            self.grouping = grouping
            self.ranking = ranking
            self.incomeStatus = incomeStatus
            self.requestedDetail = requestedDetail
            self.routeKind = routeKind
        }
    }
}

struct MarinaAnswerTitleResolver {
    func applyingTitle(
        to answer: HomeAnswer,
        query: HomeQuery,
        userPrompt: String?,
        now: Date = Date()
    ) -> HomeAnswer {
        let resolvedTitle = title(for: query, defaultTitle: answer.title, userPrompt: userPrompt, now: now)
        guard resolvedTitle != answer.title else { return answer }
        return HomeAnswer(
            id: answer.id,
            queryID: answer.queryID,
            kind: answer.kind,
            userPrompt: answer.userPrompt,
            title: resolvedTitle,
            subtitle: answer.subtitle,
            primaryValue: answer.primaryValue,
            rows: answer.rows,
            attachment: answer.attachment,
            explanation: answer.explanation,
            generatedAt: answer.generatedAt
        )
    }

    func title(
        for query: HomeQuery,
        defaultTitle: String,
        userPrompt: String?,
        now: Date = Date()
    ) -> String {
        let base = baseTitle(for: query, defaultTitle: defaultTitle, userPrompt: userPrompt)
        guard let suffix = scopeSuffix(for: query, userPrompt: userPrompt, now: now),
              base.localizedCaseInsensitiveContains(suffix) == false else {
            return base
        }
        return "\(base) \(suffix)"
    }

    private func baseTitle(
        for query: HomeQuery,
        defaultTitle: String,
        userPrompt: String?
    ) -> String {
        switch query.intent {
        case .periodOverview:
            return "Budget Overview"
        case .spendThisMonth:
            return "Spend"
        case .categorySpendTotal:
            return query.targetName.map { "Category Spend (\($0))" } ?? "Category Spend"
        case .topCategoriesThisMonth:
            return query.resultLimit == 1 ? "Top 1 Category" : "Top Categories"
        case .compareThisMonthToPreviousMonth:
            return "Spending Comparison"
        case .compareCategoryThisMonthToPreviousMonth:
            return query.targetName.map { "Category Comparison (\($0))" } ?? "Category Comparison"
        case .compareCardThisMonthToPreviousMonth:
            return query.targetName.map { "Card Comparison (\($0))" } ?? "Card Comparison"
        case .compareIncomeSourceThisMonthToPreviousMonth:
            return query.targetName.map { "Income Source Comparison (\($0))" } ?? "Income Source Comparison"
        case .compareMerchantThisMonthToPreviousMonth:
            return query.targetName.map { "Merchant Comparison (\($0))" } ?? "Merchant Comparison"
        case .largestRecentTransactions:
            return recentRowsTitle(defaultTitle: defaultTitle, userPrompt: userPrompt)
        case .mostFrequentTransactions:
            return "Most Frequent Expenses"
        case .spendAveragePerPeriod:
            return "Average Spending"
        case .cardSpendTotal:
            return query.targetName.map { "Card Spend (\($0))" } ?? "Card Spend"
        case .cardVariableSpendingHabits:
            return query.targetName.map { "Card Spending Habits (\($0))" } ?? "Card Spending Habits"
        case .incomeAverageActual:
            return query.targetName.map { "Average Actual Income (\($0))" } ?? "Average Actual Income"
        case .savingsStatus:
            return "Savings Status"
        case .savingsAverageRecentPeriods:
            return "Average Savings"
        case .incomeSourceShare:
            return query.targetName.map { "Income Share (\($0))" } ?? "Income Share by Source"
        case .categorySpendShare:
            return query.targetName.map { "Category Spend Share (\($0))" } ?? "Category Spend Share"
        case .incomeSourceShareTrend:
            return query.targetName.map { "Income Share Trend (\($0))" } ?? "Income Share Trend"
        case .categorySpendShareTrend:
            return query.targetName.map { "Category Share Trend (\($0))" } ?? "Category Share Trend"
        case .presetDueSoon:
            return "Presets Due Soon"
        case .presetHighestCost:
            return "Highest Preset Costs"
        case .presetTopCategory:
            return "Categories Assigned to Presets"
        case .presetCategorySpend:
            return query.targetName.map { "Preset Spend by Category (\($0))" } ?? "Preset Spend by Category"
        case .categoryPotentialSavings:
            return query.targetName.map { "Potential Savings (\($0))" } ?? "Category Potential Savings"
        case .categoryReallocationGuidance:
            return query.targetName.map { "Reallocation Guidance (\($0))" } ?? "Category Reallocation Guidance"
        case .safeSpendToday:
            return "Safe Spend Today"
        case .forecastSavings:
            return "Forecast Savings"
        case .nextPlannedExpense:
            return "Next Planned Expense"
        case .spendTrendsSummary:
            return "Spending Trends"
        case .cardSnapshotSummary:
            return query.targetName.map { "Card Snapshot (\($0))" } ?? "Card Snapshot"
        case .merchantSpendTotal:
            return query.targetName.map { "Merchant Spend (\($0))" } ?? "Merchant Spend"
        case .merchantSpendSummary:
            return query.targetName.map { "Merchant Spend Summary (\($0))" } ?? "Merchant Spend Summary"
        case .topMerchantsThisMonth:
            return query.resultLimit == 1 ? "Top 1 Merchant" : "Top Merchants"
        case .topCategoryChangesThisMonth:
            return "Top Category Changes"
        case .topCardChangesThisMonth:
            return "Top Card Changes"
        }
    }

    private func recentRowsTitle(defaultTitle: String, userPrompt: String?) -> String {
        let normalized = normalized(userPrompt ?? "")
        if normalized.contains("purchase") {
            return "Purchases"
        }
        if normalized.contains("transaction") || normalized.contains("charge") {
            return "Transactions"
        }
        if normalized.contains("what did i spend")
            || normalized.contains("spend my money on")
            || normalized.contains("where did my money go") {
            return "Spending"
        }
        if defaultTitle.isEmpty == false {
            return defaultTitle
        }
        return "Expenses"
    }

    private func scopeSuffix(for query: HomeQuery, userPrompt: String?, now: Date) -> String? {
        let prompt = normalized(userPrompt ?? "")
        if prompt.contains("today") { return "Today" }
        if prompt.contains("yesterday") { return "Yesterday" }
        if prompt.contains("last week") { return "Last Week" }
        if prompt.contains("this week") { return "This Week" }
        if prompt.contains("last month") { return "Last Month" }
        if prompt.contains("this month") { return "This Month" }
        if prompt.contains("last year") { return "Last Year" }
        if prompt.contains("this year") { return "This Year" }

        if query.intent == .safeSpendToday {
            return nil
        }
        guard let range = query.dateRange else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: range.startDate)
        let end = calendar.startOfDay(for: range.endDate)
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let currentMonthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: currentMonthStart) ?? currentMonthStart
        if calendar.isDate(start, inSameDayAs: currentMonthStart),
           calendar.isDate(end, inSameDayAs: currentMonthEnd) {
            return "This Month"
        }
        let currentYearStart = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now
        let currentYearEnd = calendar.date(byAdding: DateComponents(year: 1, day: -1), to: currentYearStart) ?? currentYearStart
        if calendar.isDate(start, inSameDayAs: currentYearStart),
           calendar.isDate(end, inSameDayAs: currentYearEnd) {
            return "This Year"
        }
        return nil
    }

    private func normalized(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
