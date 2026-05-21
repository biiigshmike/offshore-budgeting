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

struct MarinaFoundationModelsService: MarinaStructuredIntentInterpreting, MarinaAIInterpreter {
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

enum MarinaFoundationInterpretationPromptBuilder {
    static let maximumResponseTokens = 256

    static func instructions(context: MarinaInterpretationContext) -> String {
        """
        Prompt version: \(MarinaFoundationPromptVersion.interpretation.rawValue)
        You are Marina inside Offshore. Extract one tiny typed envelope for deterministic Swift execution.
        Swift validates workspace scope, resolves entities, reads data, computes math, and writes the final answer.

        Rules:
        - Return only MarinaFoundationIntentEnvelope fields.
        - routeRaw must be readQuery, lookup, clarification, scenario, help, or unsupported.
        - Use null for unused optional fields; never write placeholder strings like null, nil, none, n/a, or unknown.
        - Never calculate totals, balances, rows, percentages, or final answer text.
        - Preserve date phrases exactly in dateText or comparisonDateText; if no date appears, leave dateText null.
        - targetText is only a concrete named object or filter. Do not put generic concepts like spending, income, actual income, active budget, savings, budget, transactions, or uncategorized spending in targetText.
        - For relationships, copy words like linked cards, linked presets, budget limit, allocation rows, settlement rows, status, or balance into relationshipText.
        - For explicit what-if prompts, copy the amount phrase into amountText and use valueDirectionRaw more, less, set, increase, or decrease when obvious.
        - For CRUD commands, set routeRaw unsupported and unsupportedReasonRaw crud.

        Route hints:
        - readQuery: totals, averages, comparisons, ranked lists, rows, breakdowns, insights.
        - lookup: object details, relationships, balances, memberships, records.
        - scenario: explicit what-if prompts.
        - help: capability questions.
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
        Produce the typed envelope only.
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
    do {
        let provider = MarinaFoundationModelsSessionProvider()
        let routeSession = try provider.makeSession(
            instructions: MarinaFoundationInterpretationPromptBuilder.instructions(context: context)
        )
        let response = try await routeSession.respond(
            to: MarinaFoundationInterpretationPromptBuilder.prompt(userPrompt: prompt),
            generating: MarinaFoundationIntentEnvelope.self,
            includeSchemaInPrompt: true,
            options: marinaInterpretationOptions(maximumResponseTokens: MarinaFoundationInterpretationPromptBuilder.maximumResponseTokens)
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
private func marinaInterpretationOptions(maximumResponseTokens: Int) -> GenerationOptions {
    GenerationOptions(
        sampling: .greedy,
        temperature: nil,
        maximumResponseTokens: maximumResponseTokens
    )
}

#else
private func interpretWithFoundationModels(
    prompt _: String,
    context _: MarinaInterpretationContext
) async throws -> MarinaAIIntent {
    throw MarinaFoundationModelsServiceError.unavailable
}
#endif
