//
//  MarinaLanguageRouter.swift
//  OffshoreBudgeting
//
//  Created by OpenAI Codex on 4/15/26.
//

import Foundation

protocol MarinaModelAvailabilityProviding {
    func currentStatus() -> MarinaModelAvailability.Status
}

extension MarinaModelAvailability: MarinaModelAvailabilityProviding {}

struct MarinaLanguageRouter {
    private let availability: MarinaModelAvailabilityProviding
    private let modelService: MarinaStructuredIntentInterpreting
    private let planBuilder: MarinaStructuredIntentPlanBuilder

    init(
        availability: MarinaModelAvailabilityProviding = MarinaModelAvailability(),
        modelService: MarinaStructuredIntentInterpreting = MarinaFoundationModelsService(),
        planBuilder: MarinaStructuredIntentPlanBuilder = MarinaStructuredIntentPlanBuilder()
    ) {
        self.availability = availability
        self.modelService = modelService
        self.planBuilder = planBuilder
    }

    func interpret(
        prompt: String,
        context: MarinaLanguageRouterContext,
        heuristicFallback: () -> MarinaInterpretedRequest
    ) async -> MarinaInterpretedRequest {
        guard availability.currentStatus() == .available else {
            let fallback = heuristicFallback()
            MarinaDebugLogger.log("model unavailable prompt='\(prompt)' fallback=\(fallback)")
            return fallback
        }

        do {
            let structuredIntent = try await modelService.interpret(prompt: prompt, context: context)
            MarinaDebugLogger.log("model structured output prompt='\(prompt)' intent=\(structuredIntent)")
            let interpreted = planBuilder.buildRequest(
                from: structuredIntent,
                prompt: prompt,
                defaultPeriodUnit: context.defaultPeriodUnit,
                now: context.now,
                priorQueryContext: context.priorQueryContext
            )

            switch interpreted {
            case .query(let plan, .model):
                return resolveModelQuery(
                    plan,
                    prompt: prompt,
                    context: context,
                    heuristicFallback: heuristicFallback
                )
            case .unresolved:
                return resolveQueryLikeFailure(
                    prompt: prompt,
                    context: context,
                    fallback: heuristicFallback(),
                    failureReason: "model_unresolved"
                )
            case .clarification(let clarification, _):
                let fallback = heuristicFallback()
                MarinaDebugLogger.log(
                    "model clarification prompt='\(prompt)' actionable=\(clarification.isActionable) fallbackQueryExists=\(fallback.executableQueryPlan != nil)"
                )
                if shouldPreferHeuristicFallback(
                    fallback,
                    over: clarification,
                    prompt: prompt,
                    priorQueryContext: context.priorQueryContext
                ) {
                    MarinaDebugLogger.log("clarification preferred parser fallback prompt='\(prompt)' clarification=\(clarification) fallback=\(fallback)")
                    return fallback
                }
                MarinaDebugLogger.log("final clarification prompt='\(prompt)' clarification=\(clarification)")
                return interpreted
            default:
                MarinaDebugLogger.log("final interpreted request prompt='\(prompt)' request=\(interpreted)")
                return interpreted
            }
        } catch {
            let fallback = heuristicFallback()
            MarinaDebugLogger.log("model error prompt='\(prompt)' error=\(error) fallback=\(fallback)")
            if isLikelyQueryPrompt(prompt, context: context) {
                return resolveQueryLikeFailure(
                    prompt: prompt,
                    context: context,
                    fallback: fallback,
                    failureReason: "model_error"
                )
            }
            return fallback
        }
    }

    private func resolveModelQuery(
        _ plan: HomeQueryPlan,
        prompt: String,
        context: MarinaLanguageRouterContext,
        heuristicFallback: () -> MarinaInterpretedRequest
    ) -> MarinaInterpretedRequest {
        if let failure = planBuilder.validationFailure(for: plan, prompt: prompt) {
            MarinaDebugLogger.log("model query invalid prompt='\(prompt)' reason=\(failure.rawValue) plan=\(plan)")
            if let clarification = queryClarification(for: failure, plan: plan) {
                return clarification
            }
            return resolveQueryLikeFailure(
                prompt: prompt,
                context: context,
                fallback: heuristicFallback(),
                failureReason: "model_query_invalid_\(failure.rawValue)"
            )
        }

        let fallback = heuristicFallback()
        if shouldPreferHeuristicQuery(
            fallback,
            over: plan,
            prompt: prompt,
            priorQueryContext: context.priorQueryContext
        ) {
            MarinaDebugLogger.log("model query fallback prompt='\(prompt)' modelPlan=\(plan) fallback=\(fallback)")
            return fallback
        }

        MarinaDebugLogger.log("final query plan prompt='\(prompt)' plan=\(plan)")
        return .query(plan, source: .model)
    }

    private func resolveQueryLikeFailure(
        prompt: String,
        context: MarinaLanguageRouterContext,
        fallback: MarinaInterpretedRequest,
        failureReason: String
    ) -> MarinaInterpretedRequest {
        switch fallback {
        case .query, .clarification:
            MarinaDebugLogger.log("query-like fallback prompt='\(prompt)' reason=\(failureReason) fallback=\(fallback)")
            return fallback
        default:
            break
        }

        guard isLikelyQueryPrompt(prompt, context: context) else {
            MarinaDebugLogger.log("non-query fallback prompt='\(prompt)' reason=\(failureReason) fallback=\(fallback)")
            return fallback
        }

        let clarification = MarinaClarificationRequest(
            subtitle: "I need one more detail before I run this.",
            reasons: [.lowConfidenceLanguage],
            shouldRunBestEffort: false,
            queryPlan: nil,
            commandPlan: nil,
            isActionable: false
        )
        MarinaDebugLogger.log("query-like clarification prompt='\(prompt)' reason=\(failureReason)")
        return .clarification(clarification, source: .model)
    }

    private func shouldPreferHeuristicFallback(
        _ fallback: MarinaInterpretedRequest,
        over clarification: MarinaClarificationRequest,
        prompt: String,
        priorQueryContext: MarinaPriorQueryContext
    ) -> Bool {
        guard case .query = fallback else { return false }
        guard clarification.shouldRunBestEffort == false else { return false }
        guard clarification.commandPlan == nil else { return false }

        if clarification.isActionable == false {
            MarinaDebugLogger.log(
                "clarification fallback preferred prompt='\(prompt)' reason=non_actionable priorContext=\(priorQueryContext.hasContext)"
            )
            return true
        }

        if clarification.reasons.isEmpty {
            return true
        }

        if clarification.reasons.allSatisfy({ $0 == .lowConfidenceLanguage }) {
            return true
        }

        return clarification.queryPlan == nil && promptSuggestsFollowUp(prompt)
    }

    private func shouldPreferHeuristicQuery(
        _ fallback: MarinaInterpretedRequest,
        over modelPlan: HomeQueryPlan,
        prompt: String,
        priorQueryContext: MarinaPriorQueryContext
    ) -> Bool {
        guard case .query(let fallbackPlan, _) = fallback else { return false }

        if fallbackPlan.metric != modelPlan.metric {
            return true
        }

        if fallbackPlan.dateRange != nil, modelPlan.dateRange == nil {
            return true
        }

        if fallbackPlan.targetName != nil, modelPlan.targetName == nil,
           promptSuggestsFollowUp(prompt) {
            return true
        }

        if priorQueryContext.hasContext,
           promptSuggestsFollowUp(prompt),
           let priorMetric = priorQueryContext.lastQueryPlan?.metric ?? priorQueryContext.lastMetric,
           fallbackPlan.metric == priorMetric,
           modelPlan.metric != priorMetric {
            return true
        }

        return false
    }

    private func queryClarification(
        for failure: MarinaStructuredIntentPlanBuilder.QueryValidationFailure,
        plan: HomeQueryPlan
    ) -> MarinaInterpretedRequest? {
        let reasons: [HomeAssistantClarificationReason]
        let subtitle: String

        switch failure {
        case .missingMetric:
            return nil
        case .missingDateRange:
            reasons = [.missingDate]
            subtitle = "Choose a date window so I can scope the query."
        case .missingCategoryTarget:
            reasons = [.missingCategoryTarget]
            subtitle = "Pick a category so I can run that query."
        case .missingCardTarget:
            reasons = [.missingCardTarget]
            subtitle = "Pick a card so I can run that query."
        case .missingIncomeTarget:
            reasons = [.missingIncomeSourceTarget]
            subtitle = "Pick an income source so I can run that query."
        case .missingMerchantTarget:
            reasons = [.missingMerchantTarget]
            subtitle = "Pick a merchant so I can run that query."
        }

        return .clarification(
            MarinaClarificationRequest(
                subtitle: subtitle,
                reasons: reasons,
                shouldRunBestEffort: false,
                queryPlan: plan,
                commandPlan: nil,
                isActionable: true
            ),
            source: .model
        )
    }

    private func isLikelyQueryPrompt(
        _ prompt: String,
        context: MarinaLanguageRouterContext
    ) -> Bool {
        if promptSuggestsFollowUp(prompt), context.priorQueryContext.hasContext {
            return true
        }

        let normalized = prompt
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let queryKeywords = [
            "spend", "spent", "spending", "income", "save", "savings",
            "category", "categories", "card", "cards", "merchant", "merchants",
            "week", "month", "year", "today", "yesterday", "last", "compare"
        ]
        return queryKeywords.contains(where: normalized.contains)
    }

    private func promptSuggestsFollowUp(_ prompt: String) -> Bool {
        let normalized = prompt
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalized.isEmpty == false else { return false }

        let continuationPhrases = [
            "how about", "what about", "and", "same", "for that", "for this", "last week", "last month", "this week", "this month"
        ]
        return continuationPhrases.contains { normalized.contains($0) }
    }
}
