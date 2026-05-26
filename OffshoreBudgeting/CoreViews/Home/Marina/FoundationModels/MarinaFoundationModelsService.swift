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
        context: MarinaInterpretationContext
    ) async throws -> MarinaStructuredIntent
}

struct MarinaFoundationTurnIntentService: MarinaTurnIntentInterpreting {
    func interpretTurnIntent(
        prompt: String,
        context: MarinaInterpretationContext
    ) async throws -> MarinaTurnInterpretation {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return try await interpretTurnIntentWithFoundationModels(prompt: prompt, context: context)
        } else {
            throw MarinaFoundationModelsServiceError.unavailable
        }
        #else
        try await interpretTurnIntentWithFoundationModels(prompt: prompt, context: context)
        #endif
    }
}

struct MarinaFoundationModelsService: MarinaStructuredIntentInterpreting, MarinaAIInterpreter {
    private let turnIntentService = MarinaFoundationTurnIntentService()

    func interpret(
        prompt: String,
        context: MarinaInterpretationContext
    ) async throws -> MarinaStructuredIntent {
        try await interpretAI(prompt: prompt, context: context).structuredIntent
    }

    func interpretAI(
        prompt: String,
        context: MarinaInterpretationContext
    ) async throws -> MarinaAIIntent {
        let interpretation = try await turnIntentService.interpretTurnIntent(prompt: prompt, context: context)
        switch interpretation.result {
        case .query(let query):
            return .semanticQuery(query)
        case .clarification(let clarification):
            return .clarification(
                MarinaAIClarificationIntent(
                    reasoning: "",
                    kindRaw: clarification.kind.rawValue,
                    message: clarification.message,
                    missingFieldRaws: [],
                    ambiguousFieldRaws: [],
                    patchSlotRaw: clarification.patchSlot?.rawValue,
                    shouldRunBestEffort: false
                )
            )
        case .unsupported(let unsupported):
            return .unsupported(
                MarinaAIUnsupportedIntent(
                    reasoning: "",
                    reasonRaw: unsupported.kind.rawValue,
                    message: unsupported.message
                )
            )
        }
    }
}

enum MarinaFoundationInterpretationPromptBuilder {
    static let maximumResponseTokens = 384

    static func instructions(context: MarinaInterpretationContext) -> String {
        """
        Prompt version: \(MarinaFoundationPromptVersion.interpretation.rawValue)
        You are Marina inside Offshore. Extract one tokenized read request for deterministic Swift execution.
        Swift validates workspace scope, resolves entities, reads data, computes math, and writes the final answer.

        Rules:
        - Return only MarinaTokenizedReadRequest fields.
        - kindRaw must be query, clarification, or unsupported.
        - Use null for unused optional fields; never write placeholder strings like null, nil, none, n/a, or unknown.
        - Never calculate totals, balances, rows, percentages, or final answer text.
        - Preserve date phrases exactly in dateTokens[].rawText; include ISO bounds when the period is explicit and safe.
        - Set modelNameRaw to the exact SwiftData model or supported virtual target being retrieved.
        - Put only concrete named objects, aliases, or row-search spans in targetTokens[].rawText.
        - Use targetTokens[].allowedTypeRaws when a target span could resolve to more than one object type.
        - Fill operation, amount field or basis, targets, dates, grouping, ranking, limit, response shape, detail, metric contract, and confidence when relevant.
        - Treat all selected-workspace Offshore objects as queryable, including workspace, budget, card, category, preset, planned expense, transaction, income, savings, reconciliation, import rule, and alias data.
        - Prefer kindRaw query for any safe read-only workspace request; Swift can answer broad workspace reads even when no named card, category, budget, source, account, or merchant is supplied.
        - Treat words like actual income, planned income, current workspace, selected workspace, savings activity, savings balance, budget links, linked cards, and linked presets as semantic fields or views, not as missing named targets.
        - Use clarification only when choosing among real named objects or object types would materially change the answer, such as merchant vs card vs category collisions or duplicate names.
        - Do not include command/filler words such as show, list, find, me, all, my, expenses, transactions, purchases, please in target spans.
        - For unknown merchant/transaction row text such as "Mr. Pickle", use modelNameRaw VariableExpense, operationRaw list, amountFieldRaw budgetImpactAmount, target typeRaw merchant, allowedTypeRaws merchant/expense/transaction, and isFreeText true.
        - For known formulas, set metricContractRaw to the matching MarinaMetricContractID when obvious; Swift will validate support and execution.
        - For CRUD commands, set kindRaw unsupported and unsupported.reasonRaw crud.
        - Reserve unsupported for out-of-domain, unsafe, mutating, advice-seeking, or impossible requests; do not use unsupported for safe read-only workspace questions like current workspace, income this month, savings this month, counts, lists, details, or supported numeric aggregation.

        \(MarinaFoundationSafetyPolicy.interpretationInstructions)

        Intent hints:
        - query: totals, averages, comparisons, ranked lists, rows, breakdowns, object details, relationships, balances, memberships, records, and explicit what-if prompts.
        - clarification: ambiguous request or answer to a prior clarification.
        - unsupported: anything outside safe read-only budgeting.

        Context:
        - workspace: \(context.workspaceName)
        - default period unit: \(context.defaultPeriodUnit.rawValue)
        - prior query: \(priorQuerySummary(context.priorQueryContext))
        """
    }

    static func prompt(userPrompt: String) -> String {
        """
        User prompt: \(userPrompt)
        Produce the typed MarinaTokenizedReadRequest only.
        """
    }

    private static func priorQuerySummary(_ context: MarinaPriorQueryContext) -> String {
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

    private static func isoDateString(_ date: Date) -> String {
        MarinaDateOnlyRangeCodec.dateOnlyString(from: date)
    }
}

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
private func interpretWithFoundationModels(
    prompt: String,
    context: MarinaInterpretationContext
) async throws -> MarinaAIIntent {
    let interpretation = try await interpretTurnIntentWithFoundationModels(prompt: prompt, context: context)
    switch interpretation.result {
    case .query(let query):
        return .semanticQuery(query)
    case .clarification(let clarification):
        return .clarification(
            MarinaAIClarificationIntent(
                reasoning: "",
                kindRaw: clarification.kind.rawValue,
                message: clarification.message,
                missingFieldRaws: [],
                ambiguousFieldRaws: [],
                patchSlotRaw: clarification.patchSlot?.rawValue,
                shouldRunBestEffort: false
            )
        )
    case .unsupported(let unsupported):
        return .unsupported(
            MarinaAIUnsupportedIntent(
                reasoning: "",
                reasonRaw: unsupported.kind.rawValue,
                message: unsupported.message
            )
        )
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func interpretTurnIntentWithFoundationModels(
    prompt: String,
    context: MarinaInterpretationContext
) async throws -> MarinaTurnInterpretation {
    do {
        let provider = MarinaFoundationModelsSessionProvider()
        let spec = MarinaFoundationSessionSpec.interpretation(context: context)
        let routeSession = try provider.makeSession(spec: spec)
        let response = try await routeSession.respond(
            to: MarinaFoundationInterpretationPromptBuilder.prompt(userPrompt: prompt),
            generating: MarinaTokenizedReadRequest.self,
            includeSchemaInPrompt: spec.includeSchemaInPrompt,
            options: spec.options
        )
        MarinaTraceRecorder.shared.recordFoundationTranscriptSummary(
            MarinaFoundationTranscriptSanitizer.summary(response.transcriptEntries)
        )
        let interpretation = response.content.interpretation(prompt: prompt, context: context)
        MarinaTraceRecorder.shared.recordLiveRouteOwnership(
            liveEnvelopeSummary: "tokenizedReadRequest=typed",
            canonicalRouteSummary: interpretation.generatedSchemaName,
            routeOverrideSummary: nil,
            routeGuardSummary: "semanticQueryValidatedBySwift",
            routeKeySummary: nil,
            droppedTargetSummary: nil,
            datePolicySummary: nil,
            dateSourceSummary: nil,
            effectiveDateRangeSummary: nil,
            routeRescueSummary: nil,
            blockedWrongQuery: {
                if case .unsupported = interpretation.result { return true }
                return false
            }()
        )
        return interpretation
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

#else
private func interpretWithFoundationModels(
    prompt _: String,
    context _: MarinaInterpretationContext
) async throws -> MarinaAIIntent {
    throw MarinaFoundationModelsServiceError.unavailable
}

private func interpretTurnIntentWithFoundationModels(
    prompt _: String,
    context _: MarinaInterpretationContext
) async throws -> MarinaTurnInterpretation {
    throw MarinaFoundationModelsServiceError.unavailable
}
#endif
