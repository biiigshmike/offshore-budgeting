import Foundation

@MainActor
struct MarinaNLQPipeline {
    let provider: MarinaDataProvider
    let normalizer: MarinaNLQNormalizer
    let extractor: MarinaNLQCandidateExtractor
    let resolver: MarinaNLQResolver
    let clarificationResolver: MarinaNLQClarificationResolver
    let aggregationEngine: MarinaNLQAggregationEngine
    let responseBuilder: MarinaNLQResponseBuilder

    init(
        provider: MarinaDataProvider,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) {
        self.provider = provider
        self.normalizer = MarinaNLQNormalizer(defaultPeriodUnit: defaultPeriodUnit)
        self.extractor = MarinaNLQCandidateExtractor()
        self.resolver = MarinaNLQResolver()
        self.clarificationResolver = MarinaNLQClarificationResolver()
        self.aggregationEngine = MarinaNLQAggregationEngine()
        self.responseBuilder = MarinaNLQResponseBuilder()
    }

    func run(
        prompt: String,
        activeBudgetPeriod: HomeQueryDateRange?,
        priorContext: MarinaNLQExecutionContext? = nil,
        now: Date = Date()
    ) -> MarinaNLQPipelineResult {
        let normalizedIntent = normalizer.normalize(prompt: prompt)
        let mergedIntentResult = mergedIntent(
            from: normalizedIntent,
            priorContext: priorContext
        )

        switch mergedIntentResult {
        case .clarification(let payload):
            return .clarification(payload)
        case .intent(let intent):
            if let unsupportedReason = intent.unsupportedShapeReason {
                MarinaDebugLogger.log("[MarinaNLQ] unsupported query shape prompt='\(prompt)'")
                return .clarification(unsupportedShapeClarification(for: intent, reason: unsupportedReason))
            }

            guard let metric = intent.normalizedMetric else {
                MarinaDebugLogger.log("[MarinaNLQ] recovery: unresolved metric for prompt='\(prompt)'")
                return .recovery("I couldn't confidently map that request yet.")
            }

            let extraction = extractor.extractCandidates(
                from: intent.rawTargetText ?? "",
                provider: provider
            )
            let resolution = resolver.resolve(intent: intent, extraction: extraction)

            switch resolution {
            case .clarifyAmbiguous(let payload):
                MarinaDebugLogger.log("[MarinaNLQ] ambiguity clarification presented")
                return .clarification(payload)
            case .clarifyNoMatch(let payload):
                MarinaDebugLogger.log("[MarinaNLQ] no-match clarification presented")
                return .clarification(payload)
            case .execute(let resolvedTargets):
                let aggregation = aggregationEngine.aggregate(
                    intent: intent,
                    metric: metric,
                    resolvedTargets: resolvedTargets,
                    provider: provider,
                    activeBudgetPeriod: activeBudgetPeriod,
                    now: now
                )
                let answer = responseBuilder.build(from: aggregation, userPrompt: prompt)
                return .answer(answer, executionContext(intent: intent, metric: metric, resolvedTargets: resolvedTargets))
            }
        }
    }

    func resolveClarificationResponse(
        typedInput: String,
        payload: MarinaNLQClarificationPayload,
        prompt: String,
        activeBudgetPeriod: HomeQueryDateRange?,
        priorContext: MarinaNLQExecutionContext? = nil,
        now: Date = Date()
    ) -> MarinaNLQPipelineResult {
        let outcome = clarificationResolver.resolveTypedResponse(typedInput, payload: payload)

        switch outcome {
        case .clarifyAmbiguous(let nextPayload):
            return .clarification(nextPayload)
        case .clarifyNoMatch(let nextPayload):
            return .clarification(nextPayload)
        case .execute(let resolvedTargets):
            let normalizedIntent = normalizer.normalize(prompt: prompt)
            let mergedIntentResult = mergedIntent(
                from: normalizedIntent,
                priorContext: priorContext
            )

            switch mergedIntentResult {
            case .clarification(let clarificationPayload):
                return .clarification(clarificationPayload)
            case .intent(let intent):
                if let unsupportedReason = intent.unsupportedShapeReason {
                    return .clarification(unsupportedShapeClarification(for: intent, reason: unsupportedReason))
                }

                guard let metric = intent.normalizedMetric else {
                    return .recovery("I couldn't complete that clarification safely.")
                }

                let aggregation = aggregationEngine.aggregate(
                    intent: intent,
                    metric: metric,
                    resolvedTargets: resolvedTargets,
                    provider: provider,
                    activeBudgetPeriod: activeBudgetPeriod,
                    now: now
                )
                return .answer(
                    responseBuilder.build(from: aggregation, userPrompt: prompt),
                    executionContext(intent: intent, metric: metric, resolvedTargets: resolvedTargets)
                )
            }
        }
    }

    private enum IntentMergeResult {
        case intent(NormalizedQueryIntent)
        case clarification(MarinaNLQClarificationPayload)
    }

    private func mergedIntent(
        from intent: NormalizedQueryIntent,
        priorContext: MarinaNLQExecutionContext?
    ) -> IntentMergeResult {
        if let unsupportedReason = intent.unsupportedShapeReason {
            return .clarification(unsupportedShapeClarification(for: intent, reason: unsupportedReason))
        }

        guard let priorContext, promptUsesReferentialCarryover(intent.rawPrompt) else {
            return .intent(intent)
        }

        if let explicitModifierType = explicitModifierTargetType(intent.modifiers),
           let priorType = priorContext.resolvedTargetType,
           explicitModifierType != priorType {
            MarinaDebugLogger.log("[MarinaNLQ] follow-up conflict: inherited type=\(priorType.rawValue) modifier=\(explicitModifierType.rawValue)")
            return .clarification(
                MarinaNLQClarificationPayload(
                    rawTargetText: intent.rawTargetText,
                    message: "That follow-up conflicts with the previous context. Please provide a new target.",
                    options: []
                )
            )
        }

        let mergedMetric = intent.normalizedMetric ?? priorContext.metric
        let mergedTarget = intent.rawTargetText ?? priorContext.resolvedTargetNames.first
        let mergedDateRange = intent.dateRange ?? priorContext.dateRange
        let mergedComparisonDateRange = intent.comparisonDateRange ?? priorContext.comparisonDateRange
        let mergedResultLimit = intent.resultLimit ?? priorContext.resultLimit
        let mergedModifiers = intent.modifiers.isEmpty ? priorContext.modifiers : intent.modifiers

        return .intent(
            NormalizedQueryIntent(
                rawPrompt: intent.rawPrompt,
                normalizedMetric: mergedMetric,
                queryShape: intent.queryShape,
                intentSignals: intent.intentSignals,
                unsupportedShapeReason: nil,
                rawTargetText: mergedTarget,
                dateRange: mergedDateRange,
                comparisonDateRange: mergedComparisonDateRange,
                resultLimit: mergedResultLimit,
                modifiers: mergedModifiers,
                confidenceLevel: intent.confidenceLevel
            )
        )
    }

    private func promptUsesReferentialCarryover(_ prompt: String) -> Bool {
        let normalized = " \(prompt.lowercased()) "
        let referentialTokens = [" that ", " it ", " those ", " them ", " this ", " same "]
        return referentialTokens.contains(where: normalized.contains)
    }

    private func explicitModifierTargetType(_ modifiers: [String]) -> MarinaNLQTargetType? {
        if modifiers.contains("breakdown_by_category") { return .category }
        if modifiers.contains("breakdown_by_merchant") { return .merchant }
        if modifiers.contains("breakdown_by_card") { return .card }
        return nil
    }

    private func unsupportedShapeClarification(
        for intent: NormalizedQueryIntent,
        reason: MarinaUnsupportedShapeReason
    ) -> MarinaNLQClarificationPayload {
        MarinaNLQClarificationPayload(
            rawTargetText: intent.rawTargetText ?? intent.queryShape.targetHint,
            message: reason.clarificationMessage,
            options: []
        )
    }

    private func executionContext(
        intent: NormalizedQueryIntent,
        metric: MarinaNormalizedMetric,
        resolvedTargets: MarinaNLQResolvedTargets
    ) -> MarinaNLQExecutionContext {
        MarinaNLQExecutionContext(
            metric: metric,
            dateRange: intent.dateRange,
            comparisonDateRange: intent.comparisonDateRange,
            resultLimit: intent.resultLimit,
            resolvedTargetType: resolvedTargets.targetType,
            resolvedTargetNames: resolvedTargets.resolvedTargetNames,
            modifiers: intent.modifiers
        )
    }
}
