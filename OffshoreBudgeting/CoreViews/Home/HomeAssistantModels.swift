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
    case largestRecentTransactions
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
}

enum HomeQueryMetric: String, Codable, Equatable {
    case overview
    case spendTotal
    case topCategories
    case monthComparison
    case largestTransactions
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
}

enum HomeQueryConfidenceBand: String, Codable, Equatable {
    case high
    case medium
    case low
}

struct HomeQueryPlan: Equatable {
    let metric: HomeQueryMetric
    let dateRange: HomeQueryDateRange?
    let resultLimit: Int?
    let confidenceBand: HomeQueryConfidenceBand
    let targetName: String?
    let periodUnit: HomeQueryPeriodUnit?

    init(
        metric: HomeQueryMetric,
        dateRange: HomeQueryDateRange?,
        resultLimit: Int?,
        confidenceBand: HomeQueryConfidenceBand,
        targetName: String? = nil,
        periodUnit: HomeQueryPeriodUnit? = nil
    ) {
        self.metric = metric
        self.dateRange = dateRange
        self.resultLimit = resultLimit
        self.confidenceBand = confidenceBand
        self.targetName = targetName
        self.periodUnit = periodUnit
    }

    var query: HomeQuery {
        HomeQuery(
            intent: metric.intent,
            dateRange: dateRange,
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
        case .largestTransactions:
            return .largestRecentTransactions
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
        case .largestRecentTransactions:
            return .largestTransactions
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
        }
    }
}

struct HomeAssistantSessionContext {
    var lastMetric: HomeQueryMetric?
    var lastDateRange: HomeQueryDateRange?
    var lastResultLimit: Int?
    var lastTargetName: String?
    var lastPeriodUnit: HomeQueryPeriodUnit?
}

struct HomeQuery: Identifiable, Codable, Equatable {
    static let defaultTopCategoryLimit = 3
    static let defaultRecentTransactionsLimit = 5
    static let maxResultLimit = 20

    let id: UUID
    let intent: HomeQueryIntent
    let dateRange: HomeQueryDateRange?
    let resultLimit: Int
    let targetName: String?
    let periodUnit: HomeQueryPeriodUnit?

    init(
        id: UUID = UUID(),
        intent: HomeQueryIntent,
        dateRange: HomeQueryDateRange? = nil,
        resultLimit: Int? = nil,
        targetName: String? = nil,
        periodUnit: HomeQueryPeriodUnit? = nil
    ) {
        self.id = id
        self.intent = intent
        self.dateRange = dateRange
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
        case .spendThisMonth, .compareThisMonthToPreviousMonth, .cardSpendTotal, .incomeAverageActual, .savingsStatus, .incomeSourceShare, .categorySpendShare:
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
        self.generatedAt = generatedAt
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
    case addCard
    case editCard
    case deleteCard
    case addPreset
    case addCategory
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
        isPlannedIncome: Bool? = nil,
        recurrenceFrequencyRaw: String? = nil,
        recurrenceInterval: Int? = nil
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
            categoryName: categoryName,
            entityName: entityName,
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
            plannedExpenseAmountTarget: plannedExpenseAmountTarget,
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
