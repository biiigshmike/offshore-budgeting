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

// Legacy reachable: this router is still selected by MarinaRuntimeSettings when
// the shared pipeline and NLQ v1 gates do not handle a prompt. Avoid warning-based
// deprecation while it has active callers; migrate behavior behind tested shared
// pipeline shims before removal.
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
        MarinaTraceRecorder.shared.ensure(
            prompt: prompt,
            routingMode: .modelRouter,
            marinaNLQv1Enabled: false
        )

        let availabilityStatus = availability.currentStatus()
        MarinaTraceRecorder.shared.recordModelAvailability(availabilityStatus)

        guard availabilityStatus == .available else {
            let fallback = heuristicFallback()
            MarinaTraceRecorder.shared.recordFallbackAttempt(outputSummary: fallback.traceSummary)
            MarinaTraceRecorder.shared.recordFallbackSelection(
                reason: .modelUnavailable,
                replacedModelOutput: false
            )
            MarinaTraceRecorder.shared.recordSelectedRoute(.fallback, reason: "model unavailable")
            MarinaDebugLogger.log("model unavailable prompt='\(prompt)' fallback=\(fallback)")
            return fallback
        }

        do {
            let structuredIntent = try await modelService.interpret(prompt: prompt, context: context)
            MarinaTraceRecorder.shared.recordModelOutputSummary("\(structuredIntent)")
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
                MarinaTraceRecorder.shared.recordModelPlanSummary(plan.traceSummary)
                return resolveModelQuery(
                    plan,
                    prompt: prompt,
                    context: context,
                    heuristicFallback: heuristicFallback
                )
            case .unresolved:
                MarinaTraceRecorder.shared.recordModelValidationSummary("unresolved")
                return resolveQueryLikeFailure(
                    prompt: prompt,
                    context: context,
                    fallback: heuristicFallback(),
                    failureReason: "model_unresolved"
                )
            case .clarification(let clarification, _):
                MarinaTraceRecorder.shared.recordModelValidationSummary("clarification actionable=\(clarification.isActionable)")
                let fallback = heuristicFallback()
                MarinaTraceRecorder.shared.recordFallbackAttempt(outputSummary: fallback.traceSummary)
                MarinaDebugLogger.log(
                    "model clarification prompt='\(prompt)' actionable=\(clarification.isActionable) fallbackQueryExists=\(fallback.executableQueryPlan != nil)"
                )
                if shouldPreferHeuristicFallback(
                    fallback,
                    over: clarification,
                    prompt: prompt,
                    priorQueryContext: context.priorQueryContext
                ) {
                    MarinaTraceRecorder.shared.recordFallbackSelection(
                        reason: .preferHeuristicClarificationBypass,
                        replacedModelOutput: true
                    )
                    MarinaTraceRecorder.shared.recordSelectedRoute(.fallback, reason: "heuristic preferred over model clarification")
                    MarinaDebugLogger.log("clarification preferred parser fallback prompt='\(prompt)' clarification=\(clarification) fallback=\(fallback)")
                    return fallback
                }
                MarinaTraceRecorder.shared.recordSelectedRoute(.clarification, reason: "model clarification")
                MarinaDebugLogger.log("final clarification prompt='\(prompt)' clarification=\(clarification)")
                return interpreted
            default:
                MarinaTraceRecorder.shared.recordSelectedRoute(.model, reason: "model interpretation")
                MarinaDebugLogger.log("final interpreted request prompt='\(prompt)' request=\(interpreted)")
                return interpreted
            }
        } catch {
            let fallback = heuristicFallback()
            MarinaTraceRecorder.shared.recordFallbackAttempt(outputSummary: fallback.traceSummary)
            MarinaTraceRecorder.shared.recordFallbackSelection(reason: .modelError, replacedModelOutput: false)
            MarinaDebugLogger.log("model error prompt='\(prompt)' error=\(error) fallback=\(fallback)")
            if isLikelyQueryPrompt(prompt, context: context) {
                return resolveQueryLikeFailure(
                    prompt: prompt,
                    context: context,
                    fallback: fallback,
                    failureReason: "model_error"
                )
            }
            MarinaTraceRecorder.shared.recordSelectedRoute(.fallback, reason: "model error fallback")
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
            MarinaTraceRecorder.shared.recordModelValidationSummary("invalid: \(failure.rawValue)")
            MarinaDebugLogger.log("model query invalid prompt='\(prompt)' reason=\(failure.rawValue) plan=\(plan)")
            if let clarification = queryClarification(for: failure, plan: plan) {
                MarinaTraceRecorder.shared.recordSelectedRoute(.clarification, reason: "model query invalid")
                return clarification
            }
            MarinaTraceRecorder.shared.recordFallbackSelection(reason: .modelQueryInvalid, replacedModelOutput: true)
            return resolveQueryLikeFailure(
                prompt: prompt,
                context: context,
                fallback: heuristicFallback(),
                failureReason: "model_query_invalid_\(failure.rawValue)"
            )
        }

        let fallback = heuristicFallback()
        MarinaTraceRecorder.shared.recordFallbackAttempt(outputSummary: fallback.traceSummary)
        if shouldPreferHeuristicQuery(
            fallback,
            over: plan,
            prompt: prompt,
            priorQueryContext: context.priorQueryContext
        ) {
            MarinaTraceRecorder.shared.recordFallbackSelection(reason: .preferHeuristicQuery, replacedModelOutput: true)
            MarinaTraceRecorder.shared.recordSelectedRoute(.fallback, reason: "heuristic query specificity")
            MarinaDebugLogger.log("model query fallback prompt='\(prompt)' modelPlan=\(plan) fallback=\(fallback)")
            return fallback
        }

        MarinaTraceRecorder.shared.recordModelValidationSummary("accepted")
        MarinaTraceRecorder.shared.recordSelectedRoute(.model, reason: "model query accepted")
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
        case .query(let plan, _):
            if shouldPreserveClarificationOverFallback(
                prompt: prompt,
                fallbackPlan: plan,
                failureReason: failureReason
            ) {
                break
            }
            if failureReason == "model_unresolved" {
                MarinaTraceRecorder.shared.recordFallbackSelection(reason: .modelUnresolved, replacedModelOutput: true)
            } else if failureReason == "model_error" {
                MarinaTraceRecorder.shared.recordFallbackSelection(reason: .modelError, replacedModelOutput: true)
            } else if failureReason.hasPrefix("model_query_invalid_") {
                MarinaTraceRecorder.shared.recordFallbackSelection(reason: .modelQueryInvalid, replacedModelOutput: true)
            }
            MarinaDebugLogger.log("query-like fallback prompt='\(prompt)' reason=\(failureReason) fallback=\(fallback)")
            MarinaTraceRecorder.shared.recordSelectedRoute(.fallback, reason: failureReason)
            return fallback
        case .clarification:
            MarinaDebugLogger.log("query-like fallback prompt='\(prompt)' reason=\(failureReason) fallback=\(fallback)")
            MarinaTraceRecorder.shared.recordSelectedRoute(.clarification, reason: failureReason)
            return fallback
        default:
            break
        }

        guard isLikelyQueryPrompt(prompt, context: context) else {
            MarinaDebugLogger.log("non-query fallback prompt='\(prompt)' reason=\(failureReason) fallback=\(fallback)")
            MarinaTraceRecorder.shared.recordSelectedRoute(.fallback, reason: failureReason)
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
        MarinaTraceRecorder.shared.recordSelectedRoute(.clarification, reason: failureReason)
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
        let subtitle = clarification.subtitle.lowercased()
        if subtitle.contains("isn't supported yet") || subtitle.contains("not supported") {
            return false
        }

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

        if priorQueryContext.hasContext,
           let priorMetric = priorQueryContext.lastQueryPlan?.metric ?? priorQueryContext.lastMetric,
           fallbackPlan.metric == priorMetric,
           modelPlan.metric != priorMetric,
           modelPlan.metric == .overview {
            return true
        }

        if fallbackPlan.metric != modelPlan.metric {
            let fallbackStrength = querySpecificityScore(for: fallbackPlan)
            let modelStrength = querySpecificityScore(for: modelPlan)

            if fallbackStrength > modelStrength {
                return true
            }

            if fallbackStrength < modelStrength {
                return false
            }
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

    private func shouldPreserveClarificationOverFallback(
        prompt: String,
        fallbackPlan: HomeQueryPlan,
        failureReason: String
    ) -> Bool {
        guard failureReason.hasPrefix("model_") else { return false }
        guard fallbackPlan.metric == .spendTotal || fallbackPlan.metric == .monthComparison else {
            return false
        }

        let normalized = prompt
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let groupedPrompt = normalized.contains("by category")
            || normalized.contains("by merchant")
            || normalized.contains("by card")
        let rankedPrompt = normalized.contains("top ")
            || normalized.contains("largest")
            || normalized.contains("biggest")
            || normalized.contains("most money on")
            || normalized.contains("spend the most on")
            || normalized.contains("spend the most money on")
            || normalized.contains("most of my money go")
        let unsupportedAverageRanking = normalized.contains("average")
            && (normalized.contains("top ") || normalized.contains("largest") || normalized.contains("biggest") || normalized.contains("most expensive"))

        return groupedPrompt || rankedPrompt || unsupportedAverageRanking
    }

    private func querySpecificityScore(for plan: HomeQueryPlan) -> Int {
        switch plan.metric {
        case .spendTotal, .monthComparison:
            return 1
        case .categorySpendTotal, .cardSpendTotal, .merchantSpendTotal,
             .categoryMonthComparison, .cardMonthComparison, .incomeSourceMonthComparison, .merchantMonthComparison:
            return 2
        case .topCategories, .topMerchants, .largestTransactions, .mostFrequentTransactions,
             .cardVariableSpendingHabits, .merchantSpendSummary, .topCategoryChanges, .topCardChanges:
            return 3
        default:
            return 2
        }
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
