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
    let semanticFamilyRaw: String?
    let semanticActionRaw: String?
    let semanticDatasetsRaw: [String]
    let semanticMeasureRaw: String?
    let semanticIncludeFilterTexts: [String]
    let semanticIncludeFilterTypeRaws: [String]
    let semanticExcludeFilterTexts: [String]
    let semanticExcludeFilterTypeRaws: [String]
    let semanticGroupingRaw: String?
    let semanticSortRaw: String?
    let semanticRequestedDetailRaw: String?
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
    You are Marina, a private budgeting assistant inside Offshore.
    Your job here is interpretation only: return a structured query plan or a typed clarification/unsupported result.

    Safety rules:
    - Never calculate totals, averages, percentages, balances, row contents, or final answers.
    - Never invent transactions, entities, fields, relationships, amounts, balances, or dates.
    - Never query app data directly. The app validates, resolves, scopes, fetches, and computes deterministically.
    - Always preserve the current workspace boundary.
    - If the target entity or filter is ambiguous, return clarification.
    - If the request cannot be represented with the available entities/operations below, return unresolved or clarification.
    - If no date is supplied, leave dates null so the app's default date policy applies.

    Available semantic datasets:
    variableExpenses, plannedExpenses, income, incomeSeries, cards, categories, presets, budgets,
    savingsLedger, reconciliation, expenseAllocations, importMerchantRules, assistantAliasRules.

    Available read-only actions:
    sum, average, count, minimum, maximum, rank, compare, listRows, lookupDetails.
    forecast and simulate should be avoided unless the prompt explicitly requests them; they may be rejected by validation.

    Output rules:
    - kind must be one of: semanticCommand, query, command, clarification, unresolved.
    - Prefer semanticCommand for analytics with filters, grouping, sorting, limits, comparisons, or row lists.
    - Row/list requests such as "last purchase" or "most recent purchases" use family analytics, action listRows, measure transactionAmount, grouping transaction, sort newest, and a limit.
    - Object detail requests such as "show/tell/find details for X" use family databaseLookup and action lookupDetails.
    - Use query only for simple existing HomeQueryMetric-style requests.
    - Emit raw app values when known; dates must be YYYY-MM-DD.
    - Final answer text, totals, balances, percentages, and rows must not be included.

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
        description: "Marina structured interpretation output only. Do not include computed financial answers.",
        properties: [
            .init(name: "kind", description: "semanticCommand, query, command, clarification, or unresolved", type: String.self),
            .init(name: "semanticFamilyRaw", description: "analytics, databaseLookup, or another existing semantic family; never a final answer.", type: String?.self),
            .init(name: "semanticActionRaw", description: "Read-only operation such as sum, average, count, rank, compare, listRows, or lookupDetails.", type: String?.self),
            .init(name: "semanticDatasetsRaw", description: "Catalog dataset names only.", type: [String].self),
            .init(name: "semanticMeasureRaw", description: "Existing measure raw value only; no computed value.", type: String?.self),
            .init(name: "semanticIncludeFilterTexts", description: "User-provided entity/filter text to resolve deterministically.", type: [String].self),
            .init(name: "semanticIncludeFilterTypeRaws", description: "Catalog filter type hints aligned with include filter text.", type: [String].self),
            .init(name: "semanticExcludeFilterTexts", description: "User-provided exclusion text; use only when explicit.", type: [String].self),
            .init(name: "semanticExcludeFilterTypeRaws", description: "Catalog filter type hints aligned with exclusion text.", type: [String].self),
            .init(name: "semanticGroupingRaw", description: "Grouping dimension raw value, if requested.", type: String?.self),
            .init(name: "semanticSortRaw", description: "Sort/ranking hint raw value, if requested.", type: String?.self),
            .init(name: "semanticRequestedDetailRaw", description: "Lookup detail field requested, not the answer.", type: String?.self),
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
        semanticFamilyRaw: try content.value(String?.self, forProperty: "semanticFamilyRaw"),
        semanticActionRaw: try content.value(String?.self, forProperty: "semanticActionRaw"),
        semanticDatasetsRaw: (try? content.value([String].self, forProperty: "semanticDatasetsRaw")) ?? [],
        semanticMeasureRaw: try content.value(String?.self, forProperty: "semanticMeasureRaw"),
        semanticIncludeFilterTexts: (try? content.value([String].self, forProperty: "semanticIncludeFilterTexts")) ?? [],
        semanticIncludeFilterTypeRaws: (try? content.value([String].self, forProperty: "semanticIncludeFilterTypeRaws")) ?? [],
        semanticExcludeFilterTexts: (try? content.value([String].self, forProperty: "semanticExcludeFilterTexts")) ?? [],
        semanticExcludeFilterTypeRaws: (try? content.value([String].self, forProperty: "semanticExcludeFilterTypeRaws")) ?? [],
        semanticGroupingRaw: try content.value(String?.self, forProperty: "semanticGroupingRaw"),
        semanticSortRaw: try content.value(String?.self, forProperty: "semanticSortRaw"),
        semanticRequestedDetailRaw: try content.value(String?.self, forProperty: "semanticRequestedDetailRaw"),
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

    let kindRaw = flat.kindRaw?.nilIfBlank
    let structuredKind = kindRaw.flatMap(MarinaStructuredIntentKind.init(rawValue:))
        ?? (kindRaw?.lowercased()).flatMap(MarinaStructuredIntentKind.init(rawValue:))
    switch structuredKind {
    case .semanticCommand:
        guard let command = makeSemanticCommand(from: flat) else { return .unresolved }
        return .semanticCommand(command)
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
                clarification: clarification.isActionable ? clarification : nil
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
                clarification: clarification.isActionable ? clarification : nil
            )
        )
    case .clarification:
        return .clarification(clarification)
    case .unresolved, .none:
        if let command = makeSemanticCommand(from: flat) {
            return .semanticCommand(command)
        }
        return .unresolved
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func makeSemanticCommand(from flat: MarinaFoundationModelsFlatResponse) -> MarinaSemanticCommand? {
    guard let action = MarinaSemanticCommandAction(rawValue: flat.semanticActionRaw?.nilIfBlank ?? ""),
          let family = MarinaRequestFamily(rawValue: flat.semanticFamilyRaw?.nilIfBlank ?? MarinaRequestFamily.analytics.rawValue) else {
        return nil
    }

    let datasets = flat.semanticDatasetsRaw.compactMap { MarinaSemanticCommandDataset(rawValue: $0) }
    let periodUnit = HomeQueryPeriodUnit(rawValue: flat.queryPeriodUnitRaw ?? "")
    return MarinaSemanticCommand(
        family: family,
        action: action,
        datasets: datasets,
        measure: flat.semanticMeasureRaw.flatMap(MarinaCandidateMeasure.init(rawValue:)),
        includeFilters: semanticFilters(texts: flat.semanticIncludeFilterTexts, types: flat.semanticIncludeFilterTypeRaws),
        excludeFilters: semanticFilters(texts: flat.semanticExcludeFilterTexts, types: flat.semanticExcludeFilterTypeRaws),
        grouping: flat.semanticGroupingRaw.flatMap(MarinaGroupingDimensionCandidate.init(rawValue:)),
        sort: flat.semanticSortRaw.flatMap(MarinaSemanticCommandSort.init(rawValue:)),
        dateRange: makeDateRange(start: flat.queryDateStart, end: flat.queryDateEnd),
        comparisonDateRange: makeDateRange(start: flat.queryComparisonDateStart, end: flat.queryComparisonDateEnd),
        periodUnit: periodUnit,
        limit: flat.queryResultLimit,
        incomeStatusScope: incomeStatusScope(from: flat),
        requestedDetail: flat.semanticRequestedDetailRaw.flatMap(MarinaSemanticRequestedDetail.init(rawValue:))
    )
}

@available(iOS 26.0, macOS 26.0, *)
private func incomeStatusScope(from flat: MarinaFoundationModelsFlatResponse) -> MarinaIncomeStatusScope? {
    guard flat.semanticDatasetsRaw.contains(MarinaSemanticCommandDataset.income.rawValue)
        || flat.queryMetricRaw?.localizedCaseInsensitiveContains("income") == true else {
        return nil
    }
    if let isPlannedIncome = flat.isPlannedIncome {
        return isPlannedIncome ? .planned : .actual
    }
    let joined = ([flat.queryTargetName, flat.semanticMeasureRaw, flat.queryMetricRaw] + flat.semanticIncludeFilterTexts)
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
    if joined.contains("planned") || joined.contains("expected") || joined.contains("projected") {
        return .planned
    }
    if joined.contains("actual") || joined.contains("received") {
        return .actual
    }
    return nil
}

@available(iOS 26.0, macOS 26.0, *)
private func semanticFilters(texts: [String], types: [String]) -> [MarinaSemanticCommandFilter] {
    texts.enumerated().compactMap { index, rawText in
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        let rawTypes = types.indices.contains(index) ? types[index] : ""
        let allowed = rawTypes
            .split(separator: "|")
            .compactMap { MarinaCandidateEntityTypeHint(rawValue: String($0)) }
        return MarinaSemanticCommandFilter(rawText: trimmed, allowedTypes: allowed)
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func makeDateRange(start: String?, end: String?) -> HomeQueryDateRange? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return MarinaDateResolver(calendar: calendar).resolveExplicitRange(
        start: start,
        end: end
    )?.queryDateRange
}

@available(iOS 26.0, macOS 26.0, *)
private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
