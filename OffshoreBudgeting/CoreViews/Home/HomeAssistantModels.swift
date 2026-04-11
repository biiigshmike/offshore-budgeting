//
//  HomeAssistantModels.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/8/26.
//

import Foundation

// MARK: - Query Models

struct HomeQueryDateRange: Codable, Equatable {
    let startDate: Date
    let endDate: Date

    init(startDate: Date, endDate: Date) {
        if startDate <= endDate {
            self.startDate = startDate
            self.endDate = endDate
        } else {
            self.startDate = endDate
            self.endDate = startDate
        }
    }
}

enum HomeQueryPeriodUnit: String, Codable, Equatable {
    case day
    case week
    case month
    case quarter
    case year
}

enum HomeQueryIntent: String, CaseIterable, Codable, Equatable {
    case periodOverview
    case spendThisMonth
    case topCategoriesThisMonth
    case compareThisMonthToPreviousMonth
    case compareCategoryThisMonthToPreviousMonth
    case compareCardThisMonthToPreviousMonth
    case compareIncomeSourceThisMonthToPreviousMonth
    case compareMerchantThisMonthToPreviousMonth
    case largestRecentTransactions
    case spendAveragePerPeriod
    case cardSpendTotal
    case cardVariableSpendingHabits
    case incomeAverageActual
    case savingsStatus
    case savingsAverageRecentPeriods
    case incomeSourceShare
    case categorySpendShare
    case incomeSourceShareTrend
    case categorySpendShareTrend
    case presetDueSoon
    case presetHighestCost
    case presetTopCategory
    case presetCategorySpend
    case categoryPotentialSavings
    case categoryReallocationGuidance
    case safeSpendToday
    case forecastSavings
    case nextPlannedExpense
    case spendTrendsSummary
    case cardSnapshotSummary
    case merchantSpendTotal
    case merchantSpendSummary
    case topMerchantsThisMonth
    case topCategoryChangesThisMonth
    case topCardChangesThisMonth
}

enum HomeQueryMetric: String, Codable, Equatable {
    case overview
    case spendTotal
    case topCategories
    case monthComparison
    case categoryMonthComparison
    case cardMonthComparison
    case incomeSourceMonthComparison
    case merchantMonthComparison
    case largestTransactions
    case spendAveragePerPeriod
    case cardSpendTotal
    case cardVariableSpendingHabits
    case incomeAverageActual
    case savingsStatus
    case savingsAverageRecentPeriods
    case incomeSourceShare
    case categorySpendShare
    case incomeSourceShareTrend
    case categorySpendShareTrend
    case presetDueSoon
    case presetHighestCost
    case presetTopCategory
    case presetCategorySpend
    case categoryPotentialSavings
    case categoryReallocationGuidance
    case safeSpendToday
    case forecastSavings
    case nextPlannedExpense
    case spendTrendsSummary
    case cardSnapshotSummary
    case merchantSpendTotal
    case merchantSpendSummary
    case topMerchants
    case topCategoryChanges
    case topCardChanges
}

enum HomeQueryConfidenceBand: String, Codable, Equatable {
    case high
    case medium
    case low
}

struct HomeQueryPlan: Equatable {
    let metric: HomeQueryMetric
    let dateRange: HomeQueryDateRange?
    let comparisonDateRange: HomeQueryDateRange?
    let resultLimit: Int?
    let confidenceBand: HomeQueryConfidenceBand
    let targetName: String?
    let periodUnit: HomeQueryPeriodUnit?

    init(
        metric: HomeQueryMetric,
        dateRange: HomeQueryDateRange?,
        comparisonDateRange: HomeQueryDateRange? = nil,
        resultLimit: Int?,
        confidenceBand: HomeQueryConfidenceBand,
        targetName: String? = nil,
        periodUnit: HomeQueryPeriodUnit? = nil
    ) {
        self.metric = metric
        self.dateRange = dateRange
        self.comparisonDateRange = comparisonDateRange
        self.resultLimit = resultLimit
        self.confidenceBand = confidenceBand
        self.targetName = targetName
        self.periodUnit = periodUnit
    }

    var query: HomeQuery {
        HomeQuery(
            intent: metric.intent,
            dateRange: dateRange,
            comparisonDateRange: comparisonDateRange,
            resultLimit: resultLimit,
            targetName: targetName,
            periodUnit: periodUnit
        )
    }
}

extension HomeQueryMetric {
    var intent: HomeQueryIntent {
        switch self {
        case .overview:
            return .periodOverview
        case .spendTotal:
            return .spendThisMonth
        case .topCategories:
            return .topCategoriesThisMonth
        case .monthComparison:
            return .compareThisMonthToPreviousMonth
        case .categoryMonthComparison:
            return .compareCategoryThisMonthToPreviousMonth
        case .cardMonthComparison:
            return .compareCardThisMonthToPreviousMonth
        case .incomeSourceMonthComparison:
            return .compareIncomeSourceThisMonthToPreviousMonth
        case .merchantMonthComparison:
            return .compareMerchantThisMonthToPreviousMonth
        case .largestTransactions:
            return .largestRecentTransactions
        case .spendAveragePerPeriod:
            return .spendAveragePerPeriod
        case .cardSpendTotal:
            return .cardSpendTotal
        case .cardVariableSpendingHabits:
            return .cardVariableSpendingHabits
        case .incomeAverageActual:
            return .incomeAverageActual
        case .savingsStatus:
            return .savingsStatus
        case .savingsAverageRecentPeriods:
            return .savingsAverageRecentPeriods
        case .incomeSourceShare:
            return .incomeSourceShare
        case .categorySpendShare:
            return .categorySpendShare
        case .incomeSourceShareTrend:
            return .incomeSourceShareTrend
        case .categorySpendShareTrend:
            return .categorySpendShareTrend
        case .presetDueSoon:
            return .presetDueSoon
        case .presetHighestCost:
            return .presetHighestCost
        case .presetTopCategory:
            return .presetTopCategory
        case .presetCategorySpend:
            return .presetCategorySpend
        case .categoryPotentialSavings:
            return .categoryPotentialSavings
        case .categoryReallocationGuidance:
            return .categoryReallocationGuidance
        case .safeSpendToday:
            return .safeSpendToday
        case .forecastSavings:
            return .forecastSavings
        case .nextPlannedExpense:
            return .nextPlannedExpense
        case .spendTrendsSummary:
            return .spendTrendsSummary
        case .cardSnapshotSummary:
            return .cardSnapshotSummary
        case .merchantSpendTotal:
            return .merchantSpendTotal
        case .merchantSpendSummary:
            return .merchantSpendSummary
        case .topMerchants:
            return .topMerchantsThisMonth
        case .topCategoryChanges:
            return .topCategoryChangesThisMonth
        case .topCardChanges:
            return .topCardChangesThisMonth
        }
    }
}

extension HomeQueryIntent {
    var metric: HomeQueryMetric {
        switch self {
        case .periodOverview:
            return .overview
        case .spendThisMonth:
            return .spendTotal
        case .topCategoriesThisMonth:
            return .topCategories
        case .compareThisMonthToPreviousMonth:
            return .monthComparison
        case .compareCategoryThisMonthToPreviousMonth:
            return .categoryMonthComparison
        case .compareCardThisMonthToPreviousMonth:
            return .cardMonthComparison
        case .compareIncomeSourceThisMonthToPreviousMonth:
            return .incomeSourceMonthComparison
        case .compareMerchantThisMonthToPreviousMonth:
            return .merchantMonthComparison
        case .largestRecentTransactions:
            return .largestTransactions
        case .spendAveragePerPeriod:
            return .spendAveragePerPeriod
        case .cardSpendTotal:
            return .cardSpendTotal
        case .cardVariableSpendingHabits:
            return .cardVariableSpendingHabits
        case .incomeAverageActual:
            return .incomeAverageActual
        case .savingsStatus:
            return .savingsStatus
        case .savingsAverageRecentPeriods:
            return .savingsAverageRecentPeriods
        case .incomeSourceShare:
            return .incomeSourceShare
        case .categorySpendShare:
            return .categorySpendShare
        case .incomeSourceShareTrend:
            return .incomeSourceShareTrend
        case .categorySpendShareTrend:
            return .categorySpendShareTrend
        case .presetDueSoon:
            return .presetDueSoon
        case .presetHighestCost:
            return .presetHighestCost
        case .presetTopCategory:
            return .presetTopCategory
        case .presetCategorySpend:
            return .presetCategorySpend
        case .categoryPotentialSavings:
            return .categoryPotentialSavings
        case .categoryReallocationGuidance:
            return .categoryReallocationGuidance
        case .safeSpendToday:
            return .safeSpendToday
        case .forecastSavings:
            return .forecastSavings
        case .nextPlannedExpense:
            return .nextPlannedExpense
        case .spendTrendsSummary:
            return .spendTrendsSummary
        case .cardSnapshotSummary:
            return .cardSnapshotSummary
        case .merchantSpendTotal:
            return .merchantSpendTotal
        case .merchantSpendSummary:
            return .merchantSpendSummary
        case .topMerchantsThisMonth:
            return .topMerchants
        case .topCategoryChangesThisMonth:
            return .topCategoryChanges
        case .topCardChangesThisMonth:
            return .topCardChanges
        }
    }
}

struct HomeAssistantSessionContext {
    var lastMetric: HomeQueryMetric?
    var lastDateRange: HomeQueryDateRange?
    var lastResultLimit: Int?
    var lastTargetName: String?
    var lastPeriodUnit: HomeQueryPeriodUnit?
    var recentAnswerContexts: [HomeAssistantAnswerContext] = []
}

enum HomeAssistantAnswerTargetType: String, Codable, Equatable {
    case category
    case card
    case incomeSource
    case merchant
}

struct HomeAssistantAnswerContext: Identifiable, Codable, Equatable {
    let id: UUID
    let query: HomeQuery
    let answerTitle: String
    let answerKind: HomeAnswerKind
    let userPrompt: String?
    let targetName: String?
    let targetType: HomeAssistantAnswerTargetType?
    let rowTitles: [String]
    let rowValues: [String]
    let scenarioPercent: Double?
    let generatedAt: Date

    init(
        id: UUID = UUID(),
        query: HomeQuery,
        answerTitle: String,
        answerKind: HomeAnswerKind,
        userPrompt: String? = nil,
        targetName: String? = nil,
        targetType: HomeAssistantAnswerTargetType? = nil,
        rowTitles: [String] = [],
        rowValues: [String] = [],
        scenarioPercent: Double? = nil,
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.query = query
        self.answerTitle = answerTitle
        self.answerKind = answerKind
        self.userPrompt = userPrompt
        self.targetName = targetName
        self.targetType = targetType
        self.rowTitles = rowTitles
        self.rowValues = rowValues
        self.scenarioPercent = scenarioPercent
        self.generatedAt = generatedAt
    }
}

enum HomeAssistantFollowUpAnchorDecision: Equatable {
    case none
    case matched(HomeAssistantAnswerContext)
    case ambiguous([HomeAssistantAnswerContext])
}

struct HomeAssistantFollowUpAnchorResolver {
    private static let recentContextLimit = 3

    func resolve(
        prompt: String,
        recentContexts: [HomeAssistantAnswerContext]
    ) -> HomeAssistantFollowUpAnchorDecision {
        let normalizedPrompt = normalized(prompt)
        guard isFollowUpShaped(normalizedPrompt) else { return .none }

        let candidates = Array(recentContexts.suffix(Self.recentContextLimit).reversed())
        guard candidates.isEmpty == false else { return .none }

        let scored = candidates
            .map { (context: $0, score: score($0, normalizedPrompt: normalizedPrompt)) }
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.context.generatedAt > rhs.context.generatedAt
                }
                return lhs.score > rhs.score
            }

        guard let top = scored.first else { return .none }
        guard top.score >= 6 else { return .none }

        if scored.count > 1, let second = scored.dropFirst().first, top.score - second.score <= 1 {
            return .ambiguous([top.context, second.context])
        }

        return .matched(top.context)
    }

    private func isFollowUpShaped(_ normalizedPrompt: String) -> Bool {
        let followUpPhrases = [
            "that", "this", "it", "those", "them",
            "how about", "what about", "and if", "same", "same for", "again",
            "instead", "will that", "does that", "is that right", "so if",
            "reduce", "increase", "cut", "save", "reallocate", "rebalance"
        ]
        return followUpPhrases.contains(where: { normalizedPrompt.contains($0) })
    }

    private func score(
        _ context: HomeAssistantAnswerContext,
        normalizedPrompt: String
    ) -> Int {
        var score = 0
        let promptTokens = significantTokens(in: normalizedPrompt)

        if normalizedPrompt.contains("that")
            || normalizedPrompt.contains("this")
            || normalizedPrompt.contains("it")
            || normalizedPrompt.contains("same")
            || normalizedPrompt.contains("instead")
        {
            score += 2
        }

        if let targetName = context.targetName {
            let normalizedTarget = normalized(targetName)
            if normalizedPrompt.contains(normalizedTarget) {
                score += 5
            }

            let targetTokens = significantTokens(in: normalizedTarget)
            let overlap = promptTokens.intersection(targetTokens).count
            score += min(6, overlap * 3)
        }

        let rowTokenOverlap = rowTokenOverlapScore(context: context, promptTokens: promptTokens)
        score += rowTokenOverlap

        if let scenarioPercent = context.scenarioPercent,
           let promptPercent = extractedPercent(from: normalizedPrompt),
           abs(promptPercent - scenarioPercent) < 0.001 {
            score += 3
        } else if extractedPercent(from: normalizedPrompt) != nil {
            score += 1
        }

        if promptHasDateLanguage(normalizedPrompt),
           context.query.dateRange != nil || context.query.comparisonDateRange != nil {
            score += 1
        }

        score += metricFamilyCueScore(context: context, normalizedPrompt: normalizedPrompt)
        return score
    }

    private func rowTokenOverlapScore(
        context: HomeAssistantAnswerContext,
        promptTokens: Set<String>
    ) -> Int {
        let rowTokens = significantTokens(
            in: (context.rowTitles + context.rowValues).joined(separator: " ")
        )
        let overlap = promptTokens.intersection(rowTokens).count
        return min(4, overlap * 2)
    }

    private func metricFamilyCueScore(
        context: HomeAssistantAnswerContext,
        normalizedPrompt: String
    ) -> Int {
        switch context.query.intent.metric {
        case .categoryReallocationGuidance:
            if ["reduce", "increase", "save", "reallocate", "rebalance"].contains(where: normalizedPrompt.contains) {
                return 4
            }
        case .categoryPotentialSavings:
            if ["reduce", "cut", "save", "savings", "decrease"].contains(where: normalizedPrompt.contains) {
                return 4
            }
        case .monthComparison, .categoryMonthComparison, .cardMonthComparison, .incomeSourceMonthComparison, .merchantMonthComparison:
            if ["compare", "vs", "versus", "difference", "changed", "instead"].contains(where: normalizedPrompt.contains) {
                return 4
            }
        case .merchantSpendTotal, .merchantSpendSummary:
            if ["merchant", "spend", "spent", "how much"].contains(where: normalizedPrompt.contains) {
                return 2
            }
        default:
            break
        }
        return 0
    }

    private func promptHasDateLanguage(_ normalizedPrompt: String) -> Bool {
        let patterns = [
            "\\b(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december|today|yesterday|week|month|year)\\b",
            "\\d{4}-\\d{1,2}-\\d{1,2}"
        ]
        return patterns.contains { pattern in
            normalizedPrompt.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private func extractedPercent(from normalizedPrompt: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: "(\\d+(?:\\.\\d+)?)\\s*%", options: []) else {
            return nil
        }
        let searchRange = NSRange(normalizedPrompt.startIndex..., in: normalizedPrompt)
        guard let match = regex.firstMatch(in: normalizedPrompt, options: [], range: searchRange),
              let valueRange = Range(match.range(at: 1), in: normalizedPrompt) else {
            return nil
        }
        return Double(normalizedPrompt[valueRange])
    }

    private func significantTokens(in text: String) -> Set<String> {
        let stopWords: Set<String> = [
            "the", "and", "for", "that", "this", "with", "from", "what", "about",
            "same", "will", "does", "mean", "your", "have", "been", "into", "than",
            "please", "month", "year"
        ]
        return Set(
            normalized(text)
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count > 2 && stopWords.contains($0) == false }
        )
    }

    private func normalized(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s%]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct HomeQuery: Identifiable, Codable, Equatable {
    static let defaultTopCategoryLimit = 3
    static let defaultRecentTransactionsLimit = 5
    static let maxResultLimit = 20

    let id: UUID
    let intent: HomeQueryIntent
    let dateRange: HomeQueryDateRange?
    let comparisonDateRange: HomeQueryDateRange?
    let resultLimit: Int
    let targetName: String?
    let periodUnit: HomeQueryPeriodUnit?

    init(
        id: UUID = UUID(),
        intent: HomeQueryIntent,
        dateRange: HomeQueryDateRange? = nil,
        comparisonDateRange: HomeQueryDateRange? = nil,
        resultLimit: Int? = nil,
        targetName: String? = nil,
        periodUnit: HomeQueryPeriodUnit? = nil
    ) {
        self.id = id
        self.intent = intent
        self.dateRange = dateRange
        self.comparisonDateRange = comparisonDateRange
        self.resultLimit = HomeQuery.sanitizedResultLimit(intent: intent, requestedLimit: resultLimit)
        self.targetName = targetName
        self.periodUnit = periodUnit
    }

    private static func sanitizedResultLimit(intent: HomeQueryIntent, requestedLimit: Int?) -> Int {
        let baseline: Int
        switch intent {
        case .periodOverview:
            baseline = 1
        case .topCategoriesThisMonth:
            baseline = defaultTopCategoryLimit
        case .largestRecentTransactions:
            baseline = defaultRecentTransactionsLimit
        case .cardVariableSpendingHabits:
            baseline = 3
        case .savingsAverageRecentPeriods, .incomeSourceShareTrend, .categorySpendShareTrend:
            baseline = 3
        case .presetDueSoon, .presetHighestCost, .presetTopCategory:
            baseline = 3
        case .presetCategorySpend:
            baseline = 1
        case .categoryPotentialSavings, .categoryReallocationGuidance:
            baseline = 3
        case .merchantSpendSummary, .topMerchantsThisMonth, .topCategoryChangesThisMonth, .topCardChangesThisMonth:
            baseline = 3
        case .spendThisMonth, .spendAveragePerPeriod, .compareThisMonthToPreviousMonth, .compareCategoryThisMonthToPreviousMonth, .compareCardThisMonthToPreviousMonth, .compareIncomeSourceThisMonthToPreviousMonth, .compareMerchantThisMonthToPreviousMonth, .cardSpendTotal, .incomeAverageActual, .savingsStatus, .incomeSourceShare, .categorySpendShare, .safeSpendToday, .forecastSavings, .nextPlannedExpense, .spendTrendsSummary, .cardSnapshotSummary, .merchantSpendTotal:
            baseline = 1
        }

        guard let requestedLimit else { return baseline }
        return min(max(1, requestedLimit), maxResultLimit)
    }
}

extension BudgetingPeriod {
    var queryPeriodUnit: HomeQueryPeriodUnit {
        switch self {
        case .daily:
            return .day
        case .weekly:
            return .week
        case .monthly:
            return .month
        case .quarterly:
            return .quarter
        case .yearly:
            return .year
        }
    }
}

// MARK: - Answer Models

struct HomeAnswerRow: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let value: String

    init(id: UUID = UUID(), title: String, value: String) {
        self.id = id
        self.title = title
        self.value = value
    }
}

enum HomeAnswerKind: String, Codable, Equatable {
    case metric
    case list
    case comparison
    case message
}

struct HomeAnswer: Identifiable, Codable, Equatable {
    let id: UUID
    let queryID: UUID
    let kind: HomeAnswerKind
    let userPrompt: String?
    let title: String
    let subtitle: String?
    let primaryValue: String?
    let rows: [HomeAnswerRow]
    let attachment: HomeAssistantAttachment?
    let generatedAt: Date

    init(
        id: UUID = UUID(),
        queryID: UUID,
        kind: HomeAnswerKind,
        userPrompt: String? = nil,
        title: String,
        subtitle: String? = nil,
        primaryValue: String? = nil,
        rows: [HomeAnswerRow] = [],
        attachment: HomeAssistantAttachment? = nil,
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.queryID = queryID
        self.kind = kind
        self.userPrompt = userPrompt
        self.title = title
        self.subtitle = subtitle
        self.primaryValue = primaryValue
        self.rows = rows
        self.attachment = attachment
        self.generatedAt = generatedAt
    }
}

enum HomeAssistantAttachment: Codable, Equatable {
    case inlineCreateForm(HomeAssistantInlineCreateForm)

    private enum CodingKeys: String, CodingKey {
        case kind
        case form
    }

    private enum Kind: String, Codable {
        case inlineCreateForm
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .inlineCreateForm:
            self = .inlineCreateForm(try container.decode(HomeAssistantInlineCreateForm.self, forKey: .form))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .inlineCreateForm(form):
            try container.encode(Kind.inlineCreateForm, forKey: .kind)
            try container.encode(form, forKey: .form)
        }
    }
}

enum HomeAssistantInlineCreateEntity: String, Codable, Equatable, CaseIterable, Identifiable {
    case expense
    case income
    case budget
    case card
    case preset
    case category
    case plannedExpense

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .expense:
            return "Expense"
        case .income:
            return "Income"
        case .budget:
            return "Budget"
        case .card:
            return "Card"
        case .preset:
            return "Preset"
        case .category:
            return "Category"
        case .plannedExpense:
            return "Planned Expense"
        }
    }
}

struct HomeAssistantInlineCreateForm: Codable, Equatable {
    let entity: HomeAssistantInlineCreateEntity
    var summary: String?
    var nameText: String
    var amountText: String
    var date: Date
    var secondaryDate: Date
    var sourceText: String
    var notesText: String
    var isPlannedIncome: Bool
    var selectedCardID: UUID?
    var selectedCategoryID: UUID?
    var selectedCardIDs: [UUID]
    var selectedPresetIDs: [UUID]
    var cardThemeRaw: String
    var cardEffectRaw: String
    var categoryColorHex: String
    var recurrenceFrequencyRaw: String
    var recurrenceInterval: Int
    var weeklyWeekday: Int
    var monthlyDayOfMonth: Int
    var monthlyIsLastDay: Bool
    var yearlyMonth: Int
    var yearlyDayOfMonth: Int
    var showsValidation: Bool

    init(
        entity: HomeAssistantInlineCreateEntity,
        summary: String? = nil,
        nameText: String = "",
        amountText: String = "",
        date: Date = .now,
        secondaryDate: Date = .now,
        sourceText: String = "",
        notesText: String = "",
        isPlannedIncome: Bool = false,
        selectedCardID: UUID? = nil,
        selectedCategoryID: UUID? = nil,
        selectedCardIDs: [UUID] = [],
        selectedPresetIDs: [UUID] = [],
        cardThemeRaw: String = CardThemeOption.ruby.rawValue,
        cardEffectRaw: String = CardEffectOption.plastic.rawValue,
        categoryColorHex: String = "#3B82F6",
        recurrenceFrequencyRaw: String = RecurrenceFrequency.monthly.rawValue,
        recurrenceInterval: Int = 1,
        weeklyWeekday: Int = 6,
        monthlyDayOfMonth: Int = 15,
        monthlyIsLastDay: Bool = false,
        yearlyMonth: Int = 1,
        yearlyDayOfMonth: Int = 15,
        showsValidation: Bool = false
    ) {
        self.entity = entity
        self.summary = summary
        self.nameText = nameText
        self.amountText = amountText
        self.date = date
        self.secondaryDate = secondaryDate
        self.sourceText = sourceText
        self.notesText = notesText
        self.isPlannedIncome = isPlannedIncome
        self.selectedCardID = selectedCardID
        self.selectedCategoryID = selectedCategoryID
        self.selectedCardIDs = selectedCardIDs
        self.selectedPresetIDs = selectedPresetIDs
        self.cardThemeRaw = cardThemeRaw
        self.cardEffectRaw = cardEffectRaw
        self.categoryColorHex = categoryColorHex
        self.recurrenceFrequencyRaw = recurrenceFrequencyRaw
        self.recurrenceInterval = recurrenceInterval
        self.weeklyWeekday = weeklyWeekday
        self.monthlyDayOfMonth = monthlyDayOfMonth
        self.monthlyIsLastDay = monthlyIsLastDay
        self.yearlyMonth = yearlyMonth
        self.yearlyDayOfMonth = yearlyDayOfMonth
        self.showsValidation = showsValidation
    }
}

// MARK: - Suggestions

struct HomeAssistantSuggestion: Identifiable, Equatable {
    let id: UUID
    let title: String
    let query: HomeQuery

    init(id: UUID = UUID(), title: String, query: HomeQuery) {
        self.id = id
        self.title = title
        self.query = query
    }
}

// MARK: - Command Models

enum HomeAssistantCommandIntent: String, Equatable {
    case addExpense
    case addIncome
    case addBudget
    case editBudget
    case deleteBudget
    case addCard
    case editCard
    case deleteCard
    case addPreset
    case editPreset
    case deletePreset
    case addCategory
    case editCategory
    case deleteCategory
    case addPlannedExpense
    case editPlannedExpense
    case deletePlannedExpense
    case editExpense
    case deleteExpense
    case editIncome
    case deleteIncome
    case markIncomeReceived
    case moveExpenseCategory
    case updatePlannedExpenseAmount
    case deleteLastExpense
    case deleteLastIncome
}

enum HomeAssistantCommandConfidenceBand: String, Equatable {
    case high
    case medium
    case low
}

enum HomeAssistantPlannedExpenseAmountTarget: String, Equatable {
    case planned
    case actual
}

struct HomeAssistantCommandPlan: Equatable {
    let intent: HomeAssistantCommandIntent
    let confidenceBand: HomeAssistantCommandConfidenceBand
    let rawPrompt: String
    let amount: Double?
    let originalAmount: Double?
    let date: Date?
    let dateRange: HomeQueryDateRange?
    let notes: String?
    let source: String?
    let cardName: String?
    let categoryName: String?
    let entityName: String?
    let updatedEntityName: String?
    let isPlannedIncome: Bool?
    let categoryColorHex: String?
    let categoryColorName: String?
    let cardThemeRaw: String?
    let cardEffectRaw: String?
    let recurrenceFrequencyRaw: String?
    let recurrenceInterval: Int?
    let weeklyWeekday: Int?
    let monthlyDayOfMonth: Int?
    let monthlyIsLastDay: Bool?
    let yearlyMonth: Int?
    let yearlyDayOfMonth: Int?
    let recurrenceEndDate: Date?
    let plannedExpenseAmountTarget: HomeAssistantPlannedExpenseAmountTarget?
    let attachAllCards: Bool?
    let attachAllPresets: Bool?
    let selectedCardNames: [String]
    let selectedPresetTitles: [String]

    init(
        intent: HomeAssistantCommandIntent,
        confidenceBand: HomeAssistantCommandConfidenceBand,
        rawPrompt: String,
        amount: Double? = nil,
        originalAmount: Double? = nil,
        date: Date? = nil,
        dateRange: HomeQueryDateRange? = nil,
        notes: String? = nil,
        source: String? = nil,
        cardName: String? = nil,
        categoryName: String? = nil,
        entityName: String? = nil,
        updatedEntityName: String? = nil,
        isPlannedIncome: Bool? = nil,
        categoryColorHex: String? = nil,
        categoryColorName: String? = nil,
        cardThemeRaw: String? = nil,
        cardEffectRaw: String? = nil,
        recurrenceFrequencyRaw: String? = nil,
        recurrenceInterval: Int? = nil,
        weeklyWeekday: Int? = nil,
        monthlyDayOfMonth: Int? = nil,
        monthlyIsLastDay: Bool? = nil,
        yearlyMonth: Int? = nil,
        yearlyDayOfMonth: Int? = nil,
        recurrenceEndDate: Date? = nil,
        plannedExpenseAmountTarget: HomeAssistantPlannedExpenseAmountTarget? = nil,
        attachAllCards: Bool? = nil,
        attachAllPresets: Bool? = nil,
        selectedCardNames: [String] = [],
        selectedPresetTitles: [String] = []
    ) {
        self.intent = intent
        self.confidenceBand = confidenceBand
        self.rawPrompt = rawPrompt
        self.amount = amount
        self.originalAmount = originalAmount
        self.date = date
        self.dateRange = dateRange
        self.notes = notes
        self.source = source
        self.cardName = cardName
        self.categoryName = categoryName
        self.entityName = entityName
        self.updatedEntityName = updatedEntityName
        self.isPlannedIncome = isPlannedIncome
        self.categoryColorHex = categoryColorHex
        self.categoryColorName = categoryColorName
        self.cardThemeRaw = cardThemeRaw
        self.cardEffectRaw = cardEffectRaw
        self.recurrenceFrequencyRaw = recurrenceFrequencyRaw
        self.recurrenceInterval = recurrenceInterval
        self.weeklyWeekday = weeklyWeekday
        self.monthlyDayOfMonth = monthlyDayOfMonth
        self.monthlyIsLastDay = monthlyIsLastDay
        self.yearlyMonth = yearlyMonth
        self.yearlyDayOfMonth = yearlyDayOfMonth
        self.recurrenceEndDate = recurrenceEndDate
        self.plannedExpenseAmountTarget = plannedExpenseAmountTarget
        self.attachAllCards = attachAllCards
        self.attachAllPresets = attachAllPresets
        self.selectedCardNames = selectedCardNames
        self.selectedPresetTitles = selectedPresetTitles
    }
}

extension HomeAssistantCommandPlan {
    func updating(
        cardName: String? = nil,
        categoryName: String? = nil,
        entityName: String? = nil,
        updatedEntityName: String? = nil,
        isPlannedIncome: Bool? = nil,
        recurrenceFrequencyRaw: String? = nil,
        recurrenceInterval: Int? = nil,
        plannedExpenseAmountTarget: HomeAssistantPlannedExpenseAmountTarget? = nil
    ) -> HomeAssistantCommandPlan {
        HomeAssistantCommandPlan(
            intent: intent,
            confidenceBand: confidenceBand,
            rawPrompt: rawPrompt,
            amount: amount,
            originalAmount: originalAmount,
            date: date,
            dateRange: dateRange,
            notes: notes,
            source: source,
            cardName: cardName ?? self.cardName,
            categoryName: categoryName ?? self.categoryName,
            entityName: entityName ?? self.entityName,
            updatedEntityName: updatedEntityName ?? self.updatedEntityName,
            isPlannedIncome: isPlannedIncome ?? self.isPlannedIncome,
            categoryColorHex: categoryColorHex,
            categoryColorName: categoryColorName,
            cardThemeRaw: cardThemeRaw,
            cardEffectRaw: cardEffectRaw,
            recurrenceFrequencyRaw: recurrenceFrequencyRaw ?? self.recurrenceFrequencyRaw,
            recurrenceInterval: recurrenceInterval ?? self.recurrenceInterval,
            weeklyWeekday: weeklyWeekday,
            monthlyDayOfMonth: monthlyDayOfMonth,
            monthlyIsLastDay: monthlyIsLastDay,
            yearlyMonth: yearlyMonth,
            yearlyDayOfMonth: yearlyDayOfMonth,
            recurrenceEndDate: recurrenceEndDate,
            plannedExpenseAmountTarget: plannedExpenseAmountTarget ?? self.plannedExpenseAmountTarget,
            attachAllCards: attachAllCards,
            attachAllPresets: attachAllPresets,
            selectedCardNames: selectedCardNames,
            selectedPresetTitles: selectedPresetTitles
        )
    }
}

struct HomeAssistantMutationResult {
    let title: String
    let subtitle: String?
    let rows: [HomeAnswerRow]
}
