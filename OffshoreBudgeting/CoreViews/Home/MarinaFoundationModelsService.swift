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
    case diagnosedGenerationFailure(MarinaFoundationModelsFailureDiagnostic)
}

protocol MarinaStructuredIntentInterpreting {
    func interpret(
        prompt: String,
        context: MarinaLanguageRouterContext
    ) async throws -> MarinaStructuredIntent
}

struct MarinaFoundationModelsService: MarinaStructuredIntentInterpreting, MarinaAIInterpreter {
    func interpret(
        prompt: String,
        context: MarinaLanguageRouterContext
    ) async throws -> MarinaStructuredIntent {
        try await interpretAI(prompt: prompt, context: context).structuredIntent
    }

    func interpretAI(
        prompt: String,
        context: MarinaLanguageRouterContext
    ) async throws -> MarinaAIIntentV2 {
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
) async throws -> MarinaAIIntentV2 {
    do {
        let provider = MarinaFoundationModelsSessionProvider()
        let routeSession = try provider.makeSession(
            instructions: marinaInstructions(context: context)
        )
        let response = try await routeSession.respond(
            to: marinaEnvelopePrompt(prompt: prompt, context: context),
            generating: MarinaFoundationIntentEnvelopeV3.self,
            includeSchemaInPrompt: true,
            options: marinaInterpretationOptions(maximumResponseTokens: 900)
        )
        let mapping = MarinaLiveDomainIntentMapper(nowProvider: { context.now }).map(
            payload: response.content.payload,
            prompt: prompt,
            context: context
        )
        MarinaTraceRecorder.shared.recordLiveRouteOwnership(
            liveEnvelopeSummary: mapping.liveEnvelopeSummary,
            canonicalRouteSummary: mapping.canonicalRouteSummary,
            routeOverrideSummary: mapping.routeOverrideSummary,
            routeGuardSummary: mapping.routeGuardSummary,
            routeKeySummary: mapping.routeKeySummary,
            droppedTargetSummary: mapping.droppedTargetSummary,
            datePolicySummary: mapping.datePolicySummary,
            dateSourceSummary: mapping.dateSourceSummary,
            effectiveDateRangeSummary: mapping.effectiveDateRangeSummary,
            routeRescueSummary: mapping.routeRescueSummary,
            blockedWrongQuery: mapping.blockedWrongQuery
        )
        return mapping.intent
    } catch let error as MarinaFoundationModelsServiceError {
        throw error
    } catch {
        throw MarinaFoundationModelsServiceError.diagnosedGenerationFailure(
            MarinaFoundationModelsFailureDiagnostic(
                category: .from(error),
                step: .typedEnvelope,
                debugSummary: String(describing: error)
            )
        )
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func marinaInstructions(context: MarinaLanguageRouterContext) -> String {
    let aliasLines = context.aliasSummaries
        .prefix(20)
        .map { "\($0.entityTypeRaw): \($0.aliasKey) -> \($0.targetValue)" }
        .joined(separator: ", ")
    let priorQuerySummary = marinaPriorQuerySummary(context.priorQueryContext)

    return """
    Prompt version: \(MarinaFoundationPromptVersion.interpretationV3.rawValue)
    You are Marina, a private budgeting assistant inside Offshore.
    Return exactly one tiny typed language envelope for deterministic Offshore execution.
    Do not include prose, explanation, chain-of-thought, raw reasoning, final answer text, rows, totals, or calculations.
    Your job is coarse language extraction only. Swift chooses the exact finance route, validates entities, reads data, computes math, and writes the final answer.

    Safety rules:
    - Never calculate totals, averages, percentages, balances, row contents, or final answers.
    - Never invent transactions, entities, fields, relationships, amounts, balances, or dates.
    - Never query app data directly. The app validates, resolves, scopes, fetches, and computes deterministically.
    - Always preserve the current workspace boundary.
    - If no date is supplied, leave dateText null so Swift's default date policy applies.
    - If the user says "this month", "last month", "today", or similar, copy that phrase into dateText or comparisonDateText. Do not make ISO dates.
    - For CRUD prompts, return routeRaw unsupported with unsupportedReasonRaw crud.

    routeRaw values:
    - readQuery: totals, averages, comparisons, ranked lists, recent rows, breakdowns, insights.
    - lookup: object details, relationships, balances, memberships, records.
    - scenario: explicit what-if/hypothetical prompts.
    - help: capability or example questions.
    - unsupported: CRUD commands, advice, or anything outside read-only budgeting.
    - clarification: only when the user explicitly asks Marina to clarify a previous choice.

    Envelope rules:
    - Fill one MarinaFoundationIntentEnvelopeV3 only.
    - routeRaw must be readQuery, lookup, clarification, scenario, help, or unsupported.
    - Use only scalar strings/numbers in the provided fields. Leave unused optional fields as actual null values.
    - Never put placeholder words like "null", "nil", "none", "n/a", "unknown", or empty JSON fragments into string fields.
    - No field named reasoning exists; do not invent one.
    - intentRaw is a short hint, not the final route. Examples: workspace, activeBudget, linkedCards, linkedPresets, categoryLimit, spendTotal, recentTransactions, topCategories, categoryBreakdown, spendComparison, incomeActual, incomePlanned, incomeCompare, savingsStatus, savingsActivity, reconciliationBalance, allocationRows, settlementRows, whatIf, lookup, unsupported.
    - targetText is only the concrete user-named object or filter, such as Apple Card, Groceries, Salary, May Budget, Dining, Roommate, or Apple.
    - Do not put generic concepts such as "spending", "total spending", "income", "actual income", "active budget", "savings", "budget", "transactions", or "uncategorized spending" into targetText.
    - For relationships, copy the relationship words into relationshipText, such as linked cards, linked presets, budget limit, allocation rows, settlement rows, status, or balance.
    - For what-if prompts, copy the amount phrase into amountText and use valueDirectionRaw more, less, set, increase, or decrease when obvious.
    - Final answer text, typed subject/operation/measure fields, totals, balances, percentages, rows, and ISO dates must not be included.

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
private func marinaEnvelopePrompt(prompt: String, context: MarinaLanguageRouterContext) -> String {
    """
    User prompt: \(prompt)
    Default period unit: \(context.defaultPeriodUnit.rawValue)
    Prior context: \(marinaPriorQuerySummary(context.priorQueryContext))
    Produce the typed envelope only.
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
    MarinaDateOnlyRangeCodec.dateOnlyString(from: date)
}

@available(iOS 26.0, macOS 26.0, *)
private func joinedList(_ values: [String]) -> String {
    let cleaned = values
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { $0.isEmpty == false }
        .prefix(30)
    return cleaned.isEmpty ? "none" : cleaned.joined(separator: ", ")
}

#else
private func interpretWithFoundationModels(
    prompt _: String,
    context _: MarinaLanguageRouterContext
) async throws -> MarinaAIIntentV2 {
    throw MarinaFoundationModelsServiceError.unavailable
}
#endif
