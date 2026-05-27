import Foundation

struct HomeQueryDateRange: Codable, Equatable, Sendable {
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

enum HomeQueryPeriodUnit: String, Codable, Equatable, Sendable {
    case day
    case week
    case month
    case quarter
    case year
}

enum HomeQueryIntent: String, CaseIterable, Codable, Equatable {
    case periodOverview
    case spendThisMonth
    case categorySpendTotal
    case topCategoriesThisMonth
    case compareThisMonthToPreviousMonth
    case compareCategoryThisMonthToPreviousMonth
    case compareCardThisMonthToPreviousMonth
    case compareIncomeSourceThisMonthToPreviousMonth
    case compareMerchantThisMonthToPreviousMonth
    case largestRecentTransactions
    case mostFrequentTransactions
    case spendAveragePerPeriod
    case cardSpendTotal
    case cardVariableSpendingHabits
    case incomeAverageActual
    case incomeProgressSummary
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
    case categoryAvailabilitySummary
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
        self.resultLimit = Self.sanitizedResultLimit(intent: intent, requestedLimit: resultLimit)
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
        case .largestRecentTransactions, .mostFrequentTransactions:
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
        case .categoryAvailabilitySummary:
            baseline = 1
        case .merchantSpendSummary, .topMerchantsThisMonth, .topCategoryChangesThisMonth, .topCardChangesThisMonth:
            baseline = 3
        case .spendThisMonth, .categorySpendTotal, .spendAveragePerPeriod, .compareThisMonthToPreviousMonth, .compareCategoryThisMonthToPreviousMonth, .compareCardThisMonthToPreviousMonth, .compareIncomeSourceThisMonthToPreviousMonth, .compareMerchantThisMonthToPreviousMonth, .cardSpendTotal, .incomeAverageActual, .incomeProgressSummary, .savingsStatus, .incomeSourceShare, .categorySpendShare, .safeSpendToday, .forecastSavings, .nextPlannedExpense, .spendTrendsSummary, .cardSnapshotSummary, .merchantSpendTotal:
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

enum MarinaLookupObjectType: String, Codable, Sendable, Equatable, CaseIterable {
    case budget
    case income
    case incomeSeries
    case variableExpense
    case plannedExpense
    case category
    case preset
    case card
    case savingsAccount
    case savingsLedgerEntry
    case reconciliationAccount
    case reconciliationItem
    case expenseAllocation
    case importMerchantRule
    case assistantAliasRule
    case workspace
    case unknown
}

enum HomeAnswerRowRole: String, Codable, Equatable, Sendable {
    case result
    case evidence
    case formula
    case assumption
    case warning
}

struct HomeAnswerRow: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let value: String
    let sourceID: UUID?
    let objectType: MarinaLookupObjectType?
    let amount: Double?
    let date: Date?
    let role: HomeAnswerRowRole

    init(
        id: UUID = UUID(),
        title: String,
        value: String,
        sourceID: UUID? = nil,
        objectType: MarinaLookupObjectType? = nil,
        amount: Double? = nil,
        date: Date? = nil,
        role: HomeAnswerRowRole = .result
    ) {
        self.id = id
        self.title = title
        self.value = value
        self.sourceID = sourceID
        self.objectType = objectType
        self.amount = amount
        self.date = date
        self.role = role
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
    let attachment: MarinaAttachment?
    let explanation: String?
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
        attachment: MarinaAttachment? = nil,
        explanation: String? = nil,
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
        self.explanation = explanation
        self.generatedAt = generatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case queryID
        case kind
        case userPrompt
        case title
        case subtitle
        case primaryValue
        case rows
        case attachment
        case explanation
        case generatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        queryID = try container.decode(UUID.self, forKey: .queryID)
        kind = try container.decode(HomeAnswerKind.self, forKey: .kind)
        userPrompt = try container.decodeIfPresent(String.self, forKey: .userPrompt)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        primaryValue = try container.decodeIfPresent(String.self, forKey: .primaryValue)
        rows = try container.decodeIfPresent([HomeAnswerRow].self, forKey: .rows) ?? []
        attachment = try? container.decodeIfPresent(MarinaAttachment.self, forKey: .attachment)
        explanation = try container.decodeIfPresent(String.self, forKey: .explanation)
        generatedAt = try container.decodeIfPresent(Date.self, forKey: .generatedAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(queryID, forKey: .queryID)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(userPrompt, forKey: .userPrompt)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(subtitle, forKey: .subtitle)
        try container.encodeIfPresent(primaryValue, forKey: .primaryValue)
        try container.encode(rows, forKey: .rows)
        try container.encodeIfPresent(attachment, forKey: .attachment)
        try container.encodeIfPresent(explanation, forKey: .explanation)
        try container.encode(generatedAt, forKey: .generatedAt)
    }
}

struct MarinaClarificationChoice: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let title: String
    let kindLabel: String?
    let subtitle: String?
    let aliases: [String]
    let request: MarinaSemanticRequest

    init(
        id: UUID = UUID(),
        title: String,
        kindLabel: String? = nil,
        subtitle: String? = nil,
        aliases: [String],
        request: MarinaSemanticRequest
    ) {
        self.id = id
        self.title = title
        self.kindLabel = kindLabel
        self.subtitle = subtitle
        self.aliases = aliases
        self.request = request
    }

    func matches(_ reply: String) -> Bool {
        let normalizedReply = Self.normalized(reply)
        guard normalizedReply.isEmpty == false else { return false }
        return Self.normalized(title) == normalizedReply
            || aliases.contains { Self.normalized($0) == normalizedReply }
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }
}

struct MarinaClarificationChoices: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let originalPrompt: String?
    let question: String
    var choices: [MarinaClarificationChoice]
    var resolvedChoiceID: UUID?

    init(
        id: UUID = UUID(),
        originalPrompt: String? = nil,
        question: String,
        choices: [MarinaClarificationChoice],
        resolvedChoiceID: UUID? = nil
    ) {
        self.id = id
        self.originalPrompt = originalPrompt
        self.question = question
        self.choices = choices
        self.resolvedChoiceID = resolvedChoiceID
    }

    var isResolved: Bool {
        resolvedChoiceID != nil
    }

    func choice(matching reply: String) -> MarinaClarificationChoice? {
        choices.first { $0.matches(reply) }
    }
}

enum MarinaAttachment: Codable, Equatable, Sendable {
    case inlineCreateForm(MarinaInlineCreateForm)
    case clarificationChoices(MarinaClarificationChoices)

    private enum CodingKeys: String, CodingKey {
        case kind
        case form
        case clarificationChoices
    }

    private enum Kind: String, Codable {
        case inlineCreateForm
        case clarificationChoices
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .inlineCreateForm:
            self = .inlineCreateForm(try container.decode(MarinaInlineCreateForm.self, forKey: .form))
        case .clarificationChoices:
            self = .clarificationChoices(try container.decode(MarinaClarificationChoices.self, forKey: .clarificationChoices))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .inlineCreateForm(let form):
            try container.encode(Kind.inlineCreateForm, forKey: .kind)
            try container.encode(form, forKey: .form)
        case .clarificationChoices(let clarificationChoices):
            try container.encode(Kind.clarificationChoices, forKey: .kind)
            try container.encode(clarificationChoices, forKey: .clarificationChoices)
        }
    }
}
