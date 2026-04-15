//
//  MarinaFoundationModelsService.swift
//  OffshoreBudgeting
//
//  Created by OpenAI Codex on 4/15/26.
//

import Foundation

enum MarinaFoundationModelsServiceError: Error {
    case unavailable
    case malformedResponse
}

protocol MarinaStructuredIntentInterpreting {
    func interpret(
        prompt: String,
        context: MarinaLanguageRouterContext
    ) async throws -> MarinaStructuredIntent
}

struct MarinaFoundationModelsService: MarinaStructuredIntentInterpreting {
    func interpret(
        prompt: String,
        context: MarinaLanguageRouterContext
    ) async throws -> MarinaStructuredIntent {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return try await interpretWithFoundationModels(prompt: prompt, context: context)
        } else {
            throw MarinaFoundationModelsServiceError.unavailable
        }
        #else
        try await interpretWithFoundationModels(prompt: prompt, context: context)
        #endif
    }
}

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
private struct MarinaFoundationModelsFlatResponse {
    let kindRaw: String?
    let queryMetricRaw: String?
    let queryTargetName: String?
    let queryTargetTypeRaw: String?
    let queryDateStart: String?
    let queryDateEnd: String?
    let queryComparisonDateStart: String?
    let queryComparisonDateEnd: String?
    let queryResultLimit: Int?
    let queryPeriodUnitRaw: String?
    let queryConfidenceRaw: String?
    let commandIntentRaw: String?
    let commandConfidenceRaw: String?
    let amount: Double?
    let originalAmount: Double?
    let commandDate: String?
    let commandDateRangeStart: String?
    let commandDateRangeEnd: String?
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
    let recurrenceEndDate: String?
    let plannedExpenseAmountTargetRaw: String?
    let attachAllCards: Bool?
    let attachAllPresets: Bool?
    let selectedCardNames: [String]
    let selectedPresetTitles: [String]
    let clarificationSubtitle: String?
    let clarificationMissingFields: [String]
    let clarificationAmbiguousFields: [String]
    let clarificationShouldRunBestEffort: Bool
}

@available(iOS 26.0, macOS 26.0, *)
private func interpretWithFoundationModels(
    prompt: String,
    context: MarinaLanguageRouterContext
) async throws -> MarinaStructuredIntent {
    let model = SystemLanguageModel.default
    guard model.isAvailable else {
        throw MarinaFoundationModelsServiceError.unavailable
    }

    let session = LanguageModelSession(
        model: model,
        instructions: marinaInstructions(context: context)
    )

    let response = try await session.respond(
        to: prompt,
        schema: marinaResponseSchema(),
        includeSchemaInPrompt: true,
        options: GenerationOptions(
            sampling: .greedy,
            maximumResponseTokens: 700
        )
    )

    let flat = try makeFlatResponse(from: response.rawContent)
    return makeStructuredIntent(from: flat)
}

@available(iOS 26.0, macOS 26.0, *)
private func marinaInstructions(context: MarinaLanguageRouterContext) -> String {
    let aliasLines = context.aliasSummaries
        .prefix(20)
        .map { "\($0.entityTypeRaw): \($0.aliasKey) -> \($0.targetValue)" }
        .joined(separator: ", ")
    let priorQuerySummary = marinaPriorQuerySummary(context.priorQueryContext)

    return """
    You are Marina, the interpretation layer for Offshore, a private budgeting app.

    Rules:
    - Interpret the user's prompt into structured app intent only.
    - Never write the final financial answer.
    - Offshore uses deterministic app logic for financial truth.
    - Never invent transactions, balances, totals, or unsupported actions.
    - Workspaces are isolated. Never reference data outside the current workspace.
    - Cards own expenses.
    - Budgets are lenses over data, not owners of all transactions.
    - Prefer existing app metrics and command families instead of inventing new ones.
    - If required information is missing or ambiguous, set kind to clarification and fill the clarification fields explicitly.
    - Be concise and grounded.

    Output rules:
    - kind must be one of: query, command, clarification, unresolved
    - Use existing raw values from the app when possible.
    - Dates must be YYYY-MM-DD.
    - If a field is not known, return null.

    Current workspace:
    - workspace name: \(context.workspaceName)
    - default period unit: \(context.defaultPeriodUnit.rawValue)
    - prior query context: \(priorQuerySummary)
    - cards: \(joinedList(context.cardNames))
    - categories: \(joinedList(context.categoryNames))
    - income sources: \(joinedList(context.incomeSourceNames))
    - presets: \(joinedList(context.presetTitles))
    - budgets: \(joinedList(context.budgetNames))
    - aliases: \(aliasLines.isEmpty ? "none" : aliasLines)
    """
}

@available(iOS 26.0, macOS 26.0, *)
private func marinaPriorQuerySummary(_ context: MarinaPriorQueryContext) -> String {
    guard context.hasContext else { return "none" }

    let dateSummary: String = {
        guard let range = context.lastDateRange else { return "none" }
        return "\(isoDateString(range.startDate)) to \(isoDateString(range.endDate))"
    }()

    return [
        "metric=\(context.lastQueryPlan?.metric.rawValue ?? context.lastMetric?.rawValue ?? "none")",
        "target=\(context.lastTargetName ?? "none")",
        "targetType=\(context.lastTargetType?.rawValue ?? "none")",
        "dateRange=\(dateSummary)",
        "resultLimit=\(context.lastResultLimit.map(String.init) ?? "none")",
        "periodUnit=\(context.lastQueryPlan?.periodUnit?.rawValue ?? context.lastPeriodUnit?.rawValue ?? "none")"
    ]
    .joined(separator: ", ")
}

@available(iOS 26.0, macOS 26.0, *)
private func isoDateString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}

@available(iOS 26.0, macOS 26.0, *)
private func joinedList(_ values: [String]) -> String {
    let cleaned = values
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { $0.isEmpty == false }
        .prefix(30)
    return cleaned.isEmpty ? "none" : cleaned.joined(separator: ", ")
}

@available(iOS 26.0, macOS 26.0, *)
private func marinaResponseSchema() -> GenerationSchema {
    GenerationSchema(
        type: GeneratedContent.self,
        description: "Marina structured interpretation output.",
        properties: [
            .init(name: "kind", description: "query, command, clarification, or unresolved", type: String.self),
            .init(name: "queryMetricRaw", type: String?.self),
            .init(name: "queryTargetName", type: String?.self),
            .init(name: "queryTargetTypeRaw", type: String?.self),
            .init(name: "queryDateStart", type: String?.self),
            .init(name: "queryDateEnd", type: String?.self),
            .init(name: "queryComparisonDateStart", type: String?.self),
            .init(name: "queryComparisonDateEnd", type: String?.self),
            .init(name: "queryResultLimit", type: Int?.self),
            .init(name: "queryPeriodUnitRaw", type: String?.self),
            .init(name: "queryConfidenceRaw", type: String?.self),
            .init(name: "commandIntentRaw", type: String?.self),
            .init(name: "commandConfidenceRaw", type: String?.self),
            .init(name: "amount", type: Double?.self),
            .init(name: "originalAmount", type: Double?.self),
            .init(name: "commandDate", type: String?.self),
            .init(name: "commandDateRangeStart", type: String?.self),
            .init(name: "commandDateRangeEnd", type: String?.self),
            .init(name: "notes", type: String?.self),
            .init(name: "source", type: String?.self),
            .init(name: "cardName", type: String?.self),
            .init(name: "categoryName", type: String?.self),
            .init(name: "entityName", type: String?.self),
            .init(name: "updatedEntityName", type: String?.self),
            .init(name: "isPlannedIncome", type: Bool?.self),
            .init(name: "categoryColorHex", type: String?.self),
            .init(name: "categoryColorName", type: String?.self),
            .init(name: "cardThemeRaw", type: String?.self),
            .init(name: "cardEffectRaw", type: String?.self),
            .init(name: "recurrenceFrequencyRaw", type: String?.self),
            .init(name: "recurrenceInterval", type: Int?.self),
            .init(name: "weeklyWeekday", type: Int?.self),
            .init(name: "monthlyDayOfMonth", type: Int?.self),
            .init(name: "monthlyIsLastDay", type: Bool?.self),
            .init(name: "yearlyMonth", type: Int?.self),
            .init(name: "yearlyDayOfMonth", type: Int?.self),
            .init(name: "recurrenceEndDate", type: String?.self),
            .init(name: "plannedExpenseAmountTargetRaw", type: String?.self),
            .init(name: "attachAllCards", type: Bool?.self),
            .init(name: "attachAllPresets", type: Bool?.self),
            .init(name: "selectedCardNames", type: [String].self),
            .init(name: "selectedPresetTitles", type: [String].self),
            .init(name: "clarificationSubtitle", type: String?.self),
            .init(name: "clarificationMissingFields", type: [String].self),
            .init(name: "clarificationAmbiguousFields", type: [String].self),
            .init(name: "clarificationShouldRunBestEffort", type: Bool.self)
        ]
    )
}

@available(iOS 26.0, macOS 26.0, *)
private func makeFlatResponse(from content: GeneratedContent) throws -> MarinaFoundationModelsFlatResponse {
    MarinaFoundationModelsFlatResponse(
        kindRaw: try content.value(String?.self, forProperty: "kind"),
        queryMetricRaw: try content.value(String?.self, forProperty: "queryMetricRaw"),
        queryTargetName: try content.value(String?.self, forProperty: "queryTargetName"),
        queryTargetTypeRaw: try content.value(String?.self, forProperty: "queryTargetTypeRaw"),
        queryDateStart: try content.value(String?.self, forProperty: "queryDateStart"),
        queryDateEnd: try content.value(String?.self, forProperty: "queryDateEnd"),
        queryComparisonDateStart: try content.value(String?.self, forProperty: "queryComparisonDateStart"),
        queryComparisonDateEnd: try content.value(String?.self, forProperty: "queryComparisonDateEnd"),
        queryResultLimit: try content.value(Int?.self, forProperty: "queryResultLimit"),
        queryPeriodUnitRaw: try content.value(String?.self, forProperty: "queryPeriodUnitRaw"),
        queryConfidenceRaw: try content.value(String?.self, forProperty: "queryConfidenceRaw"),
        commandIntentRaw: try content.value(String?.self, forProperty: "commandIntentRaw"),
        commandConfidenceRaw: try content.value(String?.self, forProperty: "commandConfidenceRaw"),
        amount: try content.value(Double?.self, forProperty: "amount"),
        originalAmount: try content.value(Double?.self, forProperty: "originalAmount"),
        commandDate: try content.value(String?.self, forProperty: "commandDate"),
        commandDateRangeStart: try content.value(String?.self, forProperty: "commandDateRangeStart"),
        commandDateRangeEnd: try content.value(String?.self, forProperty: "commandDateRangeEnd"),
        notes: try content.value(String?.self, forProperty: "notes"),
        source: try content.value(String?.self, forProperty: "source"),
        cardName: try content.value(String?.self, forProperty: "cardName"),
        categoryName: try content.value(String?.self, forProperty: "categoryName"),
        entityName: try content.value(String?.self, forProperty: "entityName"),
        updatedEntityName: try content.value(String?.self, forProperty: "updatedEntityName"),
        isPlannedIncome: try content.value(Bool?.self, forProperty: "isPlannedIncome"),
        categoryColorHex: try content.value(String?.self, forProperty: "categoryColorHex"),
        categoryColorName: try content.value(String?.self, forProperty: "categoryColorName"),
        cardThemeRaw: try content.value(String?.self, forProperty: "cardThemeRaw"),
        cardEffectRaw: try content.value(String?.self, forProperty: "cardEffectRaw"),
        recurrenceFrequencyRaw: try content.value(String?.self, forProperty: "recurrenceFrequencyRaw"),
        recurrenceInterval: try content.value(Int?.self, forProperty: "recurrenceInterval"),
        weeklyWeekday: try content.value(Int?.self, forProperty: "weeklyWeekday"),
        monthlyDayOfMonth: try content.value(Int?.self, forProperty: "monthlyDayOfMonth"),
        monthlyIsLastDay: try content.value(Bool?.self, forProperty: "monthlyIsLastDay"),
        yearlyMonth: try content.value(Int?.self, forProperty: "yearlyMonth"),
        yearlyDayOfMonth: try content.value(Int?.self, forProperty: "yearlyDayOfMonth"),
        recurrenceEndDate: try content.value(String?.self, forProperty: "recurrenceEndDate"),
        plannedExpenseAmountTargetRaw: try content.value(String?.self, forProperty: "plannedExpenseAmountTargetRaw"),
        attachAllCards: try content.value(Bool?.self, forProperty: "attachAllCards"),
        attachAllPresets: try content.value(Bool?.self, forProperty: "attachAllPresets"),
        selectedCardNames: (try? content.value([String].self, forProperty: "selectedCardNames")) ?? [],
        selectedPresetTitles: (try? content.value([String].self, forProperty: "selectedPresetTitles")) ?? [],
        clarificationSubtitle: try content.value(String?.self, forProperty: "clarificationSubtitle"),
        clarificationMissingFields: (try? content.value([String].self, forProperty: "clarificationMissingFields")) ?? [],
        clarificationAmbiguousFields: (try? content.value([String].self, forProperty: "clarificationAmbiguousFields")) ?? [],
        clarificationShouldRunBestEffort: (try? content.value(Bool.self, forProperty: "clarificationShouldRunBestEffort")) ?? false
    )
}

@available(iOS 26.0, macOS 26.0, *)
private func makeStructuredIntent(from flat: MarinaFoundationModelsFlatResponse) -> MarinaStructuredIntent {
    let clarification = MarinaStructuredClarification(
        subtitle: flat.clarificationSubtitle?.nilIfBlank,
        missingFields: flat.clarificationMissingFields.compactMap(MarinaStructuredMissingField.init(rawValue:)),
        ambiguities: flat.clarificationAmbiguousFields.compactMap { rawValue in
            guard let field = MarinaStructuredMissingField(rawValue: rawValue) else { return nil }
            return MarinaStructuredAmbiguity(field: field, candidates: [])
        },
        shouldRunBestEffort: flat.clarificationShouldRunBestEffort
    )

    switch MarinaStructuredIntentKind(rawValue: flat.kindRaw?.lowercased() ?? "") {
    case .query:
        return .query(
            MarinaStructuredQueryIntent(
                metricRaw: flat.queryMetricRaw?.nilIfBlank,
                targetName: flat.queryTargetName?.nilIfBlank,
                targetTypeRaw: flat.queryTargetTypeRaw?.nilIfBlank,
                dateStartISO8601: flat.queryDateStart?.nilIfBlank,
                dateEndISO8601: flat.queryDateEnd?.nilIfBlank,
                comparisonDateStartISO8601: flat.queryComparisonDateStart?.nilIfBlank,
                comparisonDateEndISO8601: flat.queryComparisonDateEnd?.nilIfBlank,
                resultLimit: flat.queryResultLimit,
                periodUnitRaw: flat.queryPeriodUnitRaw?.nilIfBlank,
                confidenceRaw: flat.queryConfidenceRaw?.nilIfBlank,
                clarification: clarification.isMeaningful ? clarification : nil
            )
        )
    case .command:
        return .command(
            MarinaStructuredCommandIntent(
                intentRaw: flat.commandIntentRaw?.nilIfBlank,
                confidenceRaw: flat.commandConfidenceRaw?.nilIfBlank,
                amount: flat.amount,
                originalAmount: flat.originalAmount,
                dateISO8601: flat.commandDate?.nilIfBlank,
                dateRangeStartISO8601: flat.commandDateRangeStart?.nilIfBlank,
                dateRangeEndISO8601: flat.commandDateRangeEnd?.nilIfBlank,
                notes: flat.notes?.nilIfBlank,
                source: flat.source?.nilIfBlank,
                cardName: flat.cardName?.nilIfBlank,
                categoryName: flat.categoryName?.nilIfBlank,
                entityName: flat.entityName?.nilIfBlank,
                updatedEntityName: flat.updatedEntityName?.nilIfBlank,
                isPlannedIncome: flat.isPlannedIncome,
                categoryColorHex: flat.categoryColorHex?.nilIfBlank,
                categoryColorName: flat.categoryColorName?.nilIfBlank,
                cardThemeRaw: flat.cardThemeRaw?.nilIfBlank,
                cardEffectRaw: flat.cardEffectRaw?.nilIfBlank,
                recurrenceFrequencyRaw: flat.recurrenceFrequencyRaw?.nilIfBlank,
                recurrenceInterval: flat.recurrenceInterval,
                weeklyWeekday: flat.weeklyWeekday,
                monthlyDayOfMonth: flat.monthlyDayOfMonth,
                monthlyIsLastDay: flat.monthlyIsLastDay,
                yearlyMonth: flat.yearlyMonth,
                yearlyDayOfMonth: flat.yearlyDayOfMonth,
                recurrenceEndDateISO8601: flat.recurrenceEndDate?.nilIfBlank,
                plannedExpenseAmountTargetRaw: flat.plannedExpenseAmountTargetRaw?.nilIfBlank,
                attachAllCards: flat.attachAllCards,
                attachAllPresets: flat.attachAllPresets,
                selectedCardNames: flat.selectedCardNames,
                selectedPresetTitles: flat.selectedPresetTitles,
                clarification: clarification.isMeaningful ? clarification : nil
            )
        )
    case .clarification:
        return .clarification(clarification)
    case .unresolved, .none:
        return .unresolved
    }
}

@available(iOS 26.0, macOS 26.0, *)
private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@available(iOS 26.0, macOS 26.0, *)
private extension MarinaStructuredClarification {
    var isMeaningful: Bool {
        subtitle?.isEmpty == false || missingFields.isEmpty == false || ambiguities.isEmpty == false
    }
}
#else
private func interpretWithFoundationModels(
    prompt _: String,
    context _: MarinaLanguageRouterContext
) async throws -> MarinaStructuredIntent {
    throw MarinaFoundationModelsServiceError.unavailable
}
#endif
