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

enum HomeQueryIntent: String, CaseIterable, Codable, Equatable {
    case spendThisMonth
    case topCategoriesThisMonth
    case compareThisMonthToPreviousMonth
    case largestRecentTransactions
}

struct HomeQuery: Identifiable, Codable, Equatable {
    static let defaultTopCategoryLimit = 3
    static let defaultRecentTransactionsLimit = 5
    static let maxResultLimit = 20

    let id: UUID
    let intent: HomeQueryIntent
    let dateRange: HomeQueryDateRange?
    let resultLimit: Int

    init(
        id: UUID = UUID(),
        intent: HomeQueryIntent,
        dateRange: HomeQueryDateRange? = nil,
        resultLimit: Int? = nil
    ) {
        self.id = id
        self.intent = intent
        self.dateRange = dateRange
        self.resultLimit = HomeQuery.sanitizedResultLimit(intent: intent, requestedLimit: resultLimit)
    }

    private static func sanitizedResultLimit(intent: HomeQueryIntent, requestedLimit: Int?) -> Int {
        let baseline: Int
        switch intent {
        case .topCategoriesThisMonth:
            baseline = defaultTopCategoryLimit
        case .largestRecentTransactions:
            baseline = defaultRecentTransactionsLimit
        case .spendThisMonth, .compareThisMonthToPreviousMonth:
            baseline = 1
        }

        guard let requestedLimit else { return baseline }
        return min(max(1, requestedLimit), maxResultLimit)
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
