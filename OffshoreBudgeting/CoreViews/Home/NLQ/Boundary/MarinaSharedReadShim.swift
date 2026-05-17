import Foundation

@MainActor
struct MarinaSharedReadShim {
    enum Result: Equatable {
        case handled(
            answer: HomeAnswer,
            aggregationResult: MarinaAggregationResult,
            homeQueryPlan: HomeQueryPlan?,
            trace: MarinaSharedPipelineTrace
        )
        case notShimmed(reason: NotShimmedReason, trace: MarinaSharedPipelineTrace?)
    }

    enum NotShimmedReason: String, Equatable {
        case excludedPrompt
        case command
        case followUpOrClarification
        case validationBlocked
        case sharedPipelineFallback
        case unsupportedReadMetric
    }

    private let coordinator: MarinaSharedPipelineCoordinator
    private let classifier: MarinaPromptTurnClassifier

    init(
        coordinator: MarinaSharedPipelineCoordinator? = nil,
        classifier: MarinaPromptTurnClassifier = MarinaPromptTurnClassifier()
    ) {
        self.coordinator = coordinator ?? MarinaSharedPipelineCoordinator()
        self.classifier = classifier
    }

    func run(
        prompt: String,
        context: MarinaSharedPipelineContext
    ) async -> Result {
        if Self.isExcludedPrompt(prompt) {
            return .notShimmed(reason: .excludedPrompt, trace: nil)
        }

        switch classifier.classify(
            prompt,
            defaultPeriodUnit: context.defaultPeriodUnit,
            hasActiveClarification: false
        ) {
        case .freshQuestion:
            break
        case .command:
            return .notShimmed(reason: .command, trace: nil)
        case .followUp, .clarificationAnswer:
            return .notShimmed(reason: .followUpOrClarification, trace: nil)
        }

        let shimContext = MarinaSharedPipelineContext(
            provider: context.provider,
            routerContext: context.routerContext,
            defaultPeriodUnit: context.defaultPeriodUnit,
            sharedPipelineEnabled: true,
            aiOptInEnabled: false,
            turnClassification: .freshQuestion,
            now: context.now
        )
        let result = await coordinator.run(prompt: prompt, context: shimContext)

        switch result {
        case .handled(let answer, let aggregationResult, let homeQueryPlan, let trace):
            guard Self.isSupportedRead(homeQueryPlan: homeQueryPlan, trace: trace) else {
                return .notShimmed(reason: .unsupportedReadMetric, trace: trace)
            }
            return .handled(
                answer: answer,
                aggregationResult: aggregationResult,
                homeQueryPlan: homeQueryPlan,
                trace: trace
            )
        case .validationBlocked(_, _, let trace):
            return .notShimmed(reason: .validationBlocked, trace: trace)
        case .fallbackToLegacy(let trace):
            return .notShimmed(reason: .sharedPipelineFallback, trace: trace)
        }
    }

    private static func isExcludedPrompt(_ prompt: String) -> Bool {
        let normalized = prompt
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s/:-]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.hasPrefix("/explain") || normalized.hasPrefix("explain:") {
            return true
        }
        if normalized.hasPrefix("what if ") || normalized.hasPrefix("if ") {
            return true
        }
        return [
            "hi", "hello", "hey", "help", "thanks", "thank you"
        ].contains(normalized)
    }

    private static func isSupportedRead(
        homeQueryPlan: HomeQueryPlan?,
        trace: MarinaSharedPipelineTrace
    ) -> Bool {
        if trace.executorResultSummary?.contains("workspaceAggregation=incomeSummary") == true {
            return true
        }

        guard let metric = homeQueryPlan?.metric else { return false }
        switch metric {
        case .spendTotal,
             .categorySpendTotal,
             .cardSpendTotal,
             .monthComparison,
             .categoryMonthComparison,
             .topCategories,
             .largestTransactions:
            return true
        default:
            return false
        }
    }
}
