//
//  MarinaLanguageModels.swift
//  OffshoreBudgeting
//
//  Created by OpenAI Codex on 4/15/26.
//

import Foundation

enum MarinaInterpretedRequest: Equatable {
    case query(HomeQueryPlan, source: HomeAssistantPlanResolutionSource)
    case command(HomeAssistantCommandPlan, source: HomeAssistantPlanResolutionSource)
    case clarification(MarinaClarificationRequest, source: HomeAssistantPlanResolutionSource?)
    case unresolved
}

extension MarinaInterpretedRequest {
    var executableQueryPlan: HomeQueryPlan? {
        guard case let .query(plan, _) = self else { return nil }
        return plan
    }
}

enum MarinaStructuredIntentKind: String, Equatable {
    case semanticCommand
    case query
    case command
    case clarification
    case unresolved
}

enum MarinaStructuredTargetType: String, Equatable {
    case category
    case card
    case incomeSource
    case merchant
    case budget
    case preset
    case expense
    case income
    case plannedExpense
}

enum MarinaStructuredMissingField: String, CaseIterable, Equatable {
    case date
    case dateRange
    case comparisonDateRange
    case targetName
    case amount
    case originalAmount
    case notes
    case source
    case cardName
    case categoryName
    case entityName
    case updatedEntityName
    case plannedExpenseAmountTarget
    case recurrence
    case intent
}

struct MarinaStructuredAmbiguity: Equatable {
    let field: MarinaStructuredMissingField
    let candidates: [String]
}

struct MarinaStructuredClarification: Equatable {
    let subtitle: String?
    let missingFields: [MarinaStructuredMissingField]
    let ambiguities: [MarinaStructuredAmbiguity]
    let shouldRunBestEffort: Bool
}

extension MarinaStructuredClarification {
    var isActionable: Bool {
        missingFields.isEmpty == false || ambiguities.isEmpty == false
    }

    var isMeaningful: Bool {
        subtitle?.isEmpty == false || missingFields.isEmpty == false || ambiguities.isEmpty == false
    }
}

struct MarinaStructuredQueryIntent: Equatable {
    let metricRaw: String?
    let targetName: String?
    let targetTypeRaw: String?
    let dateStartISO8601: String?
    let dateEndISO8601: String?
    let comparisonDateStartISO8601: String?
    let comparisonDateEndISO8601: String?
    let resultLimit: Int?
    let periodUnitRaw: String?
    let confidenceRaw: String?
    let clarification: MarinaStructuredClarification?
    let insightIntent: MarinaInsightIntent?
    let softTimeHint: MarinaInsightSoftTimeHint?

    init(
        metricRaw: String?,
        targetName: String?,
        targetTypeRaw: String?,
        dateStartISO8601: String?,
        dateEndISO8601: String?,
        comparisonDateStartISO8601: String?,
        comparisonDateEndISO8601: String?,
        resultLimit: Int?,
        periodUnitRaw: String?,
        confidenceRaw: String?,
        clarification: MarinaStructuredClarification?,
        insightIntent: MarinaInsightIntent? = nil,
        softTimeHint: MarinaInsightSoftTimeHint? = nil
    ) {
        self.metricRaw = metricRaw
        self.targetName = targetName
        self.targetTypeRaw = targetTypeRaw
        self.dateStartISO8601 = dateStartISO8601
        self.dateEndISO8601 = dateEndISO8601
        self.comparisonDateStartISO8601 = comparisonDateStartISO8601
        self.comparisonDateEndISO8601 = comparisonDateEndISO8601
        self.resultLimit = resultLimit
        self.periodUnitRaw = periodUnitRaw
        self.confidenceRaw = confidenceRaw
        self.clarification = clarification
        self.insightIntent = insightIntent
        self.softTimeHint = softTimeHint
    }
}

struct MarinaStructuredCommandIntent: Equatable {
    let intentRaw: String?
    let confidenceRaw: String?
    let amount: Double?
    let originalAmount: Double?
    let dateISO8601: String?
    let dateRangeStartISO8601: String?
    let dateRangeEndISO8601: String?
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
    let recurrenceEndDateISO8601: String?
    let plannedExpenseAmountTargetRaw: String?
    let attachAllCards: Bool?
    let attachAllPresets: Bool?
    let selectedCardNames: [String]
    let selectedPresetTitles: [String]
    let clarification: MarinaStructuredClarification?
}

enum MarinaStructuredIntent: Equatable {
    case semanticCommand(MarinaSemanticCommand)
    case query(MarinaStructuredQueryIntent)
    case command(MarinaStructuredCommandIntent)
    case clarification(MarinaStructuredClarification)
    case unresolved
}

struct MarinaClarificationRequest: Equatable {
    let subtitle: String
    let reasons: [HomeAssistantClarificationReason]
    let shouldRunBestEffort: Bool
    let queryPlan: HomeQueryPlan?
    let commandPlan: HomeAssistantCommandPlan?
    let isActionable: Bool
}

struct MarinaPriorQueryContext: Equatable {
    let lastQueryPlan: HomeQueryPlan?
    let lastMetric: HomeQueryMetric?
    let lastTargetName: String?
    let lastTargetType: HomeAssistantAnswerTargetType?
    let lastDateRange: HomeQueryDateRange?
    let lastResultLimit: Int?
    let lastPeriodUnit: HomeQueryPeriodUnit?

    var hasContext: Bool {
        lastQueryPlan != nil
            || lastMetric != nil
            || lastTargetName != nil
            || lastDateRange != nil
            || lastResultLimit != nil
            || lastPeriodUnit != nil
    }

    static let empty = MarinaPriorQueryContext(
        lastQueryPlan: nil,
        lastMetric: nil,
        lastTargetName: nil,
        lastTargetType: nil,
        lastDateRange: nil,
        lastResultLimit: nil,
        lastPeriodUnit: nil
    )
}

struct MarinaLanguageRouterContext {
    let workspaceName: String
    let defaultPeriodUnit: HomeQueryPeriodUnit
    let sessionContext: HomeAssistantSessionContext
    let priorQueryContext: MarinaPriorQueryContext
    let cardNames: [String]
    let categoryNames: [String]
    let incomeSourceNames: [String]
    let presetTitles: [String]
    let budgetNames: [String]
    let aliasSummaries: [MarinaAliasSummary]
    let now: Date
}

struct MarinaAliasSummary: Equatable {
    let entityTypeRaw: String
    let aliasKey: String
    let targetValue: String
}

enum MarinaDebugLogger {
    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[MarinaTrace] \(message())")
        #endif
    }
}

enum MarinaTurnFinalOutcome: String, Equatable {
    case answer
    case clarification
    case recovery
    case unresolved
}

enum MarinaTurnOutcomeEvaluator {
    static func outcome(
        hasExecutableQuery: Bool,
        requiredFieldsMissing: Bool,
        clarificationIsActionable: Bool,
        shouldRecover: Bool
    ) -> MarinaTurnFinalOutcome {
        if hasExecutableQuery && requiredFieldsMissing == false {
            return .answer
        }

        if shouldRecover {
            return .recovery
        }

        if clarificationIsActionable {
            return .clarification
        }

        return .unresolved
    }
}
