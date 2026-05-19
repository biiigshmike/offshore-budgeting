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
    case generationFailed(MarinaFoundationModelsErrorCategory)
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
private func interpretWithFoundationModels(
    prompt: String,
    context: MarinaLanguageRouterContext
) async throws -> MarinaStructuredIntent {
    do {
        let provider = MarinaFoundationModelsSessionProvider()
        let routeSession = try provider.makeSession(
            instructions: marinaRouteInstructions(context: context)
        )
        let routeResponse = try await routeSession.respond(
            to: marinaRoutePrompt(prompt: prompt, context: context),
            generating: MarinaFoundationRouteIntent.self,
            includeSchemaInPrompt: true,
            options: marinaInterpretationOptions(maximumResponseTokens: 180)
        )
        let route = routeResponse.content
        let routeKind = route.routeKind
        let tools = provider.tools(for: routeKind, context: context)
        let session = try provider.makeSession(
            instructions: marinaInstructions(context: context, route: route),
            tools: tools
        )

        switch routeKind {
        case .readQuery:
            let response = try await session.respond(
                to: marinaFocusedPrompt(prompt: prompt, route: route),
                generating: MarinaFoundationReadQueryIntent.self,
                includeSchemaInPrompt: true,
                options: marinaInterpretationOptions(maximumResponseTokens: 360)
            )
            return makeStructuredIntent(from: response.content)
        case .lookup:
            let response = try await session.respond(
                to: marinaFocusedPrompt(prompt: prompt, route: route),
                generating: MarinaFoundationLookupIntent.self,
                includeSchemaInPrompt: true,
                options: marinaInterpretationOptions(maximumResponseTokens: 280)
            )
            return makeStructuredIntent(from: response.content)
        case .clarification:
            let response = try await session.respond(
                to: marinaFocusedPrompt(prompt: prompt, route: route),
                generating: MarinaFoundationClarificationIntent.self,
                includeSchemaInPrompt: true,
                options: marinaInterpretationOptions(maximumResponseTokens: 220)
            )
            return .clarification(response.content.structuredClarification)
        case .help, .unsupported:
            _ = try await session.respond(
                to: marinaFocusedPrompt(prompt: prompt, route: route),
                generating: MarinaFoundationUnsupportedIntent.self,
                includeSchemaInPrompt: true,
                options: marinaInterpretationOptions(maximumResponseTokens: 160)
            )
            return .unresolved
        }
    } catch let error as MarinaFoundationModelsServiceError {
        throw error
    } catch {
        throw MarinaFoundationModelsServiceError.generationFailed(.from(error))
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func marinaRouteInstructions(context: MarinaLanguageRouterContext) -> String {
    """
    Prompt version: \(MarinaFoundationPromptVersion.interpretationV1.rawValue)
    You are Marina inside Offshore. Classify the user's budgeting prompt into exactly one route.

    Routes:
    - readQuery: totals, averages, comparisons, ranked lists, recent rows, breakdowns, insight questions.
    - lookup: object details such as dates, linked cards, schedules, balances, membership, or specific records.
    - clarification: missing or ambiguous target/date/details.
    - help: capability or example questions.
    - unsupported: CRUD commands, financial advice, unsupported simulations, or anything outside safe read-only interpretation.

    Do not answer the user. Do not compute money. Preserve workspace: \(context.workspaceName).
    """
}

@available(iOS 26.0, macOS 26.0, *)
private func marinaRoutePrompt(prompt: String, context: MarinaLanguageRouterContext) -> String {
    """
    User prompt: \(prompt)
    Default period unit: \(context.defaultPeriodUnit.rawValue)
    Prior context: \(marinaPriorQuerySummary(context.priorQueryContext))
    Classify this prompt for deterministic Offshore execution.
    """
}

@available(iOS 26.0, macOS 26.0, *)
private func marinaFocusedPrompt(prompt: String, route: MarinaFoundationRouteIntent) -> String {
    """
    User prompt: \(prompt)
    Chosen route: \(route.routeRaw)
    Focus text: \(route.focusText ?? "none")
    Route reasoning: \(route.reasoning)
    Generate only the requested structured contract. Do not include final answer text, totals, balances, percentages, rows, or entity IDs.
    """
}

@available(iOS 26.0, macOS 26.0, *)
private func marinaInstructions(
    context: MarinaLanguageRouterContext,
    route: MarinaFoundationRouteIntent
) -> String {
    let aliasLines = context.aliasSummaries
        .prefix(20)
        .map { "\($0.entityTypeRaw): \($0.aliasKey) -> \($0.targetValue)" }
        .joined(separator: ", ")
    let priorQuerySummary = marinaPriorQuerySummary(context.priorQueryContext)

    return """
    Prompt version: \(MarinaFoundationPromptVersion.interpretationV1.rawValue)
    You are Marina, a private budgeting assistant inside Offshore.
    Your job here is interpretation only for route \(route.routeRaw): return a small structured contract for deterministic Offshore validation.

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
    - Fill only the route-specific @Generable contract requested by the app.
    - For analytics, set subjectRaw, operationRaw, measureRaw, include/exclude mentions, dates, grouping, ranking, and limit.
    - Row/list requests such as "last purchase" or "most recent purchases" use operationRaw listRows, measureRaw transactionAmount, groupingRaw transaction, rankingRaw newest, and a limit.
    - Object detail requests such as "show/tell/find details for X" use the lookup route.
    - For NLQ-only insight requests, set insightIntentRaw to changeSummary, contributorAnalysis, normalityCheck, watchOuts, explainBudgeting, or multiPartContributors.
    - Map words like "weird", "normal", or "lately" to normalityCheck; "worse", "changed", or "what changed" to changeSummary; "why higher" to contributorAnalysis; "watch" or "risk" to watchOuts; "explain" to explainBudgeting; and "biggest offenders" to multiPartContributors.
    - softTimeHintRaw may be lately, sincePayday, budgetCycle, or aroundTrip when the user uses fuzzy timing language.
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
private func marinaInterpretationOptions(maximumResponseTokens: Int) -> GenerationOptions {
    GenerationOptions(
        sampling: .greedy,
        temperature: nil,
        maximumResponseTokens: maximumResponseTokens
    )
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
private func makeStructuredIntent(from intent: MarinaFoundationReadQueryIntent) -> MarinaStructuredIntent {
    guard let action = semanticAction(from: intent.operationRaw),
          let dataset = semanticDataset(from: intent.subjectRaw) else {
        return .unresolved
    }

    let command = MarinaSemanticCommand(
        family: .analytics,
        action: action,
        datasets: [dataset],
        measure: semanticMeasure(from: intent.measureRaw),
        includeFilters: semanticFilters(from: intent.includeMentions),
        excludeFilters: semanticFilters(from: intent.excludeMentions),
        grouping: semanticGrouping(from: intent.groupingRaw),
        sort: semanticSort(from: intent.rankingRaw),
        dateRange: makeDateRange(from: intent.primaryDateRange),
        comparisonDateRange: makeDateRange(from: intent.comparisonDateRange),
        periodUnit: periodUnit(from: intent.primaryDateRange?.periodUnitRaw),
        limit: intent.limit,
        incomeStatusScope: incomeStatus(from: intent.incomeStatusRaw),
        requestedDetail: requestedDetail(from: intent.requestedDetailRaw),
        insightIntent: insightIntent(from: intent.insightIntentRaw),
        softTimeHint: softTimeHint(from: intent.softTimeHintRaw)
    )
    return .semanticCommand(command)
}

@available(iOS 26.0, macOS 26.0, *)
private func makeStructuredIntent(from intent: MarinaFoundationLookupIntent) -> MarinaStructuredIntent {
    guard let searchText = intent.searchText?.nilIfBlank else {
        return .clarification(
            MarinaStructuredClarification(
                subtitle: "I need the name or text to look up.",
                missingFields: [.targetName],
                ambiguities: [],
                shouldRunBestEffort: false
            )
        )
    }

    let datasets = intent.objectTypeRaws
        .compactMap(semanticDataset(from:))
    let command = MarinaSemanticCommand(
        family: .databaseLookup,
        action: .lookupDetails,
        datasets: datasets.isEmpty ? [.variableExpenses] : datasets,
        includeFilters: [
            MarinaSemanticCommandFilter(
                rawText: searchText,
                allowedTypes: intent.objectTypeRaws.compactMap(entityTypeHint(from:))
            )
        ],
        dateRange: makeDateRange(from: intent.dateRange),
        limit: intent.limit,
        requestedDetail: requestedDetail(from: intent.requestedDetailRaw)
    )
    return .semanticCommand(command)
}

@available(iOS 26.0, macOS 26.0, *)
private func semanticAction(from rawValue: String?) -> MarinaSemanticCommandAction? {
    if let exact = exactRawValue(rawValue, as: MarinaSemanticCommandAction.self) {
        return exact
    }
    guard let normalized = normalizedToken(rawValue) else { return nil }
    switch normalized {
    case "sum", "total", "spend_total", "amount_total", "count", "minimum", "min", "maximum", "max":
        return .total
    case "average", "avg", "normally":
        return .average
    case "rank", "top", "largest", "biggest", "smallest", "bottom":
        return .rank
    case "breakdown", "group", "grouped", "grouped_breakdown":
        return .group
    case "compare", "comparison", "change":
        return .compare
    case "list", "list_rows", "rows", "recent", "latest", "newest":
        return .listRows
    case "lookup", "lookup_details", "details":
        return .lookupDetails
    case "simulate":
        return .simulate
    default:
        return MarinaSemanticCommandAction(rawValue: normalized)
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func semanticDataset(from rawValue: String?) -> MarinaSemanticCommandDataset? {
    if let exact = exactRawValue(rawValue, as: MarinaSemanticCommandDataset.self) {
        return exact
    }
    guard let normalized = normalizedToken(rawValue) else { return nil }
    switch normalized {
    case "variable_expenses", "variableexpenses", "expenses", "expense", "transactions", "transaction", "merchant":
        return .variableExpenses
    case "planned_expenses", "plannedexpenses", "planned_expense", "plannedexpense", "presets_due":
        return .plannedExpenses
    case "income", "income_source", "incomesource":
        return .income
    case "income_series", "incomeseries":
        return .incomeSeries
    case "cards", "card":
        return .cards
    case "categories", "category":
        return .categories
    case "presets", "preset":
        return .presets
    case "budgets", "budget":
        return .budgets
    case "savings", "savings_ledger", "savingsledger", "savings_ledger_entries", "savingsledgerentries":
        return .savingsLedger
    case "reconciliation", "reconciliation_accounts", "reconciliationaccounts", "allocation_account", "allocationaccount":
        return .reconciliation
    case "expense_allocations", "expenseallocations", "allocations":
        return .expenseAllocations
    case "import_merchant_rules", "importmerchantrules":
        return .importMerchantRules
    case "assistant_alias_rules", "assistantaliasrules", "aliases":
        return .assistantAliasRules
    default:
        return MarinaSemanticCommandDataset(rawValue: normalized)
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func entityTypeHint(from rawValue: String?) -> MarinaCandidateEntityTypeHint? {
    if let exact = exactRawValue(rawValue, as: MarinaCandidateEntityTypeHint.self) {
        return exact
    }
    guard let normalized = normalizedToken(rawValue) else { return nil }
    switch normalized {
    case "category", "categories":
        return .category
    case "merchant":
        return .merchant
    case "expense", "transaction", "transactions":
        return .transaction
    case "card", "cards":
        return .card
    case "budget", "budgets":
        return .budget
    case "preset", "presets":
        return .preset
    case "income_source", "incomesource", "income":
        return .incomeSource
    case "allocation_account", "allocationaccount", "reconciliation":
        return .allocationAccount
    case "savings_account", "savingsaccount", "savings":
        return .savingsAccount
    case "workspace":
        return .workspace
    default:
        return MarinaCandidateEntityTypeHint(rawValue: normalized)
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func semanticSort(from rawValue: String?) -> MarinaSemanticCommandSort? {
    if let exact = exactRawValue(rawValue, as: MarinaSemanticCommandSort.self) {
        return exact
    }
    guard let normalized = normalizedToken(rawValue) else { return nil }
    switch normalized {
    case "newest", "latest", "recent", "most_recent":
        return .newest
    case "largest", "biggest", "top", "highest":
        return .largest
    case "delta_descending", "changed", "change":
        return .deltaDescending
    case "grouped_total_descending", "breakdown":
        return .groupedTotalDescending
    default:
        return MarinaSemanticCommandSort(rawValue: normalized)
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func semanticMeasure(from rawValue: String?) -> MarinaCandidateMeasure? {
    if let exact = exactRawValue(rawValue, as: MarinaCandidateMeasure.self) {
        return exact
    }
    guard let normalized = normalizedToken(rawValue) else { return nil }
    switch normalized {
    case "spend", "spending", "total_spend", "expense_amount":
        return .spend
    case "income", "earnings", "received_income", "planned_income":
        return .income
    case "savings", "saved":
        return .savings
    case "remaining_budget", "remainingbudget", "safe_spend", "safespend":
        return .remainingBudget
    case "reconciliation_balance", "reconciliationbalance", "allocation_balance", "allocationbalance":
        return .reconciliationBalance
    case "category_share", "categoryshare", "share", "percentage":
        return .categoryShare
    case "transaction_amount", "transactionamount", "amount", "purchase_amount", "purchaseamount":
        return .transactionAmount
    case "transaction_frequency", "transactionfrequency", "frequency", "count":
        return .transactionFrequency
    case "preset_amount", "presetamount":
        return .presetAmount
    case "savings_movement", "savingsmovement":
        return .savingsMovement
    default:
        return nil
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func semanticGrouping(from rawValue: String?) -> MarinaGroupingDimensionCandidate? {
    if let exact = exactRawValue(rawValue, as: MarinaGroupingDimensionCandidate.self) {
        return exact
    }
    guard let normalized = normalizedToken(rawValue) else { return nil }
    switch normalized {
    case "category", "categories":
        return .category
    case "merchant", "merchants":
        return .merchant
    case "card", "cards":
        return .card
    case "transaction", "transactions", "row", "rows":
        return .transaction
    case "income_source", "incomesource", "source":
        return .incomeSource
    case "preset", "presets":
        return .preset
    case "savings_ledger_entry", "savingsledgerentry", "savings_ledger":
        return .savingsLedgerEntry
    case "allocation_account", "allocationaccount", "reconciliation":
        return .allocationAccount
    case "day", "daily":
        return .day
    case "week", "weekly":
        return .week
    case "month", "monthly":
        return .month
    default:
        return nil
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func requestedDetail(from rawValue: String?) -> MarinaSemanticRequestedDetail? {
    if let exact = exactRawValue(rawValue, as: MarinaSemanticRequestedDetail.self) {
        return exact
    }
    guard let normalized = normalizedToken(rawValue) else { return nil }
    switch normalized {
    case "general", "summary", "details":
        return .general
    case "date", "when":
        return .date
    case "amount", "value":
        return .amount
    case "card":
        return .card
    case "category":
        return .category
    case "status":
        return .status
    case "schedule", "due":
        return .schedule
    case "recurrence", "repeat":
        return .recurrence
    case "account":
        return .account
    case "balance":
        return .balance
    case "linked_objects", "linkedobjects", "links":
        return .linkedObjects
    case "linked_cards", "linkedcards":
        return .linkedCards
    case "linked_presets", "linkedpresets":
        return .linkedPresets
    case "category_limits", "categorylimits":
        return .categoryLimits
    case "membership", "member":
        return .membership
    default:
        return nil
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func incomeStatus(from rawValue: String?) -> MarinaIncomeStatusScope? {
    if let exact = exactRawValue(rawValue, as: MarinaIncomeStatusScope.self) {
        return exact
    }
    guard let normalized = normalizedToken(rawValue) else { return nil }
    switch normalized {
    case "planned", "expected", "projected":
        return .planned
    case "actual", "received", "real":
        return .actual
    case "all", "both":
        return .all
    default:
        return nil
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func insightIntent(from rawValue: String?) -> MarinaInsightIntent? {
    if let exact = exactRawValue(rawValue, as: MarinaInsightIntent.self) {
        return exact
    }
    guard let normalized = normalizedToken(rawValue) else { return nil }
    switch normalized {
    case "change_summary", "changesummary", "changed":
        return .changeSummary
    case "contributor_analysis", "contributoranalysis", "driver", "why":
        return .contributorAnalysis
    case "normality_check", "normalitycheck", "normal", "weird":
        return .normalityCheck
    case "watch_outs", "watchouts", "watch", "risk":
        return .watchOuts
    case "explain_budgeting", "explainbudgeting", "explain":
        return .explainBudgeting
    case "multi_part_contributors", "multipartcontributors", "biggest_offenders", "biggestoffenders":
        return .multiPartContributors
    default:
        return nil
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func softTimeHint(from rawValue: String?) -> MarinaInsightSoftTimeHint? {
    if let exact = exactRawValue(rawValue, as: MarinaInsightSoftTimeHint.self) {
        return exact
    }
    guard let normalized = normalizedToken(rawValue) else { return nil }
    switch normalized {
    case "lately", "recently":
        return .lately
    case "since_payday", "sincepayday", "payday":
        return .sincePayday
    case "budget_cycle", "budgetcycle":
        return .budgetCycle
    case "around_trip", "aroundtrip", "trip":
        return .aroundTrip
    default:
        return nil
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func periodUnit(from rawValue: String?) -> HomeQueryPeriodUnit? {
    if let exact = exactRawValue(rawValue, as: HomeQueryPeriodUnit.self) {
        return exact
    }
    guard let normalized = normalizedToken(rawValue) else { return nil }
    switch normalized {
    case "day", "daily":
        return .day
    case "week", "weekly":
        return .week
    case "month", "monthly":
        return .month
    case "quarter", "quarterly":
        return .quarter
    case "year", "yearly", "annual":
        return .year
    default:
        return nil
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func semanticFilters(from mentions: [MarinaFoundationEntityMentionIntent]) -> [MarinaSemanticCommandFilter] {
    mentions.compactMap { mention in
        guard let rawText = mention.rawText?.nilIfBlank else { return nil }
        let allowed = ([mention.typeRaw].compactMap { $0 } + mention.allowedTypeRaws)
            .compactMap(entityTypeHint(from:))
        return MarinaSemanticCommandFilter(rawText: rawText, allowedTypes: allowed)
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func makeDateRange(from intent: MarinaFoundationDateRangeIntent?) -> HomeQueryDateRange? {
    makeDateRange(start: intent?.startISO8601, end: intent?.endISO8601)
}

@available(iOS 26.0, macOS 26.0, *)
private func exactRawValue<Value: RawRepresentable>(
    _ rawValue: String?,
    as _: Value.Type
) -> Value? where Value.RawValue == String {
    guard let rawValue = rawValue?.nilIfBlank else { return nil }
    return Value(rawValue: rawValue)
}

@available(iOS 26.0, macOS 26.0, *)
private func normalizedToken(_ rawValue: String?) -> String? {
    guard let rawValue = rawValue?.nilIfBlank else { return nil }
    return rawValue
        .lowercased()
        .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        .nilIfBlank
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
