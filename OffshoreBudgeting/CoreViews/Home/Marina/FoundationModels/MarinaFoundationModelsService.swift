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
    static let maximumResponseTokens = 384

    static func instructions(context: MarinaInterpretationContext) -> String {
        """
        Prompt version: \(MarinaFoundationPromptVersion.interpretation.rawValue)
        You are Marina inside Offshore. Extract one typed semantic request for deterministic Swift execution.
        Swift validates workspace scope, resolves entities, reads data, computes math, and writes the final answer.

        Rules:
        - Return only MarinaFoundationSemanticRequest fields.
        - routeRaw must be readQuery, lookup, clarification, scenario, help, or unsupported.
        - Use null for unused optional fields; never write placeholder strings like null, nil, none, n/a, or unknown.
        - Never calculate totals, balances, rows, percentages, or final answer text.
        - Preserve date phrases exactly in dateText or comparisonDateText; if no date appears, leave dateText null.
        - Put only concrete named objects or row-search spans in filters[].rawText.
        - Do not include command/filler words such as show, list, find, me, all, my, expenses, transactions, purchases, please in filter spans.
        - For unknown merchant/transaction row text such as "Mr. Pickle", use subjectRaw variableExpenses, operationRaw list, amountFieldRaw amount, filter typeRaw merchant, allowedTypeRaws merchant/expense/transaction, and isFreeText true.
        - For known formulas, set metricContractRaw to the matching MarinaMetricContractID when obvious; Swift will validate support and execution.
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
        Produce the typed semantic request only.
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
            generating: MarinaFoundationSemanticRequest.self,
            includeSchemaInPrompt: true,
            options: marinaInterpretationOptions(maximumResponseTokens: MarinaFoundationInterpretationPromptBuilder.maximumResponseTokens)
        )
        let intent = response.content.intent(prompt: prompt, context: context)
        MarinaTraceRecorder.shared.recordLiveRouteOwnership(
            liveEnvelopeSummary: "semanticRequest=typed",
            canonicalRouteSummary: intent.kind.rawValue,
            routeOverrideSummary: nil,
            routeGuardSummary: "semanticQueryValidatedBySwift",
            routeKeySummary: nil,
            droppedTargetSummary: nil,
            datePolicySummary: nil,
            dateSourceSummary: nil,
            effectiveDateRangeSummary: nil,
            routeRescueSummary: nil,
            blockedWrongQuery: intent.kind == .unsupported
        )
        return intent
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
