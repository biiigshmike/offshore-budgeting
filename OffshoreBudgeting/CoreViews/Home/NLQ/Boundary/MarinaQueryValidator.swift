import Foundation

struct MarinaQueryValidator {
    func validate(_ resolved: MarinaResolvedQueryCandidate) -> MarinaPlanValidationOutcome {
        let candidate = resolved.candidate

        if candidate.confidence == .low {
            return unsupported(
                .unsupportedCombination,
                message: "That query is too uncertain to validate safely.",
                candidate: candidate
            )
        }

        if let unsupportedHint = candidate.unsupportedHint {
            return unsupported(
                unsupportedKind(from: unsupportedHint),
                message: unsupportedMessage(from: unsupportedHint),
                candidate: candidate
            )
        }

        guard let operation = candidate.operation else {
            return unsupported(
                .unsupportedOperation,
                message: "I couldn't identify the operation for that query.",
                candidate: candidate
            )
        }

        guard let measure = candidate.measure else {
            return unsupported(
                .unsupportedOperation,
                message: "I couldn't identify the measure for that query.",
                candidate: candidate
            )
        }

        if operation == .simulate {
            return unsupported(
                .unsupportedSimulation,
                message: "Simulation plans are not validated in this phase.",
                candidate: candidate
            )
        }

        if operation == .trend || operation == .forecast {
            return unsupported(
                .unsupportedOperation,
                message: "Trend and forecast plans are not validated in this phase.",
                candidate: candidate
            )
        }

        if let ambiguous = resolved.ambiguousMentions.first {
            return clarification(
                .ambiguousTarget,
                message: "I found multiple possible matches for that target.",
                candidate: candidate,
                choices: ambiguous.choices
            )
        }

        if let unresolvedMention = resolved.unresolvedMentions.first {
            return clarification(
                .missingTarget,
                message: "I couldn't safely resolve that target.",
                candidate: candidate,
                choices: [
                    MarinaClarificationChoice(
                        title: unresolvedMention.rawText ?? "Target",
                        entityRole: unresolvedMention.role,
                        entityTypeHint: unresolvedMention.typeHint,
                        rawValue: unresolvedMention.rawText
                    )
                ]
            )
        }

        if requiresResolvedTarget(candidate), resolved.resolvedTargets.isEmpty {
            return clarification(
                .missingTarget,
                message: "I need a target before I can validate that query.",
                candidate: candidate
            )
        }

        if operation == .compare, resolved.comparisonDateRange == nil {
            return clarification(
                .missingDateRange,
                message: "I need the comparison period before I can validate that query.",
                candidate: candidate
            )
        }

        guard isSupportedCombination(operation: operation, measure: measure, candidate: candidate) else {
            return unsupported(
                .unsupportedCombination,
                message: "That operation and measure combination is not supported in this validation shell.",
                candidate: candidate
            )
        }

        return .executable(
            MarinaAggregationPlan(
                status: .notExecutableShell,
                operation: operation,
                measure: measure,
                targets: resolved.resolvedTargets.map { target in
                    MarinaResolvedAggregationTarget(
                        id: target.id,
                        role: target.role,
                        entityType: target.entityType,
                        displayName: target.displayName,
                        sourceID: target.sourceID
                    )
                },
                dateRange: resolved.primaryDateRange,
                comparisonDateRange: resolved.comparisonDateRange,
                grouping: candidate.grouping,
                ranking: candidate.ranking,
                limit: candidate.limit,
                responseShape: responseShape(operation: operation, measure: measure, candidate: candidate)
            )
        )
    }

    private func requiresResolvedTarget(_ candidate: MarinaQueryPlanCandidate) -> Bool {
        candidate.entityMentions.contains { mention in
            switch mention.role {
            case .filter, .primaryTarget, .comparisonTarget, .simulationInput, .simulationOutput:
                return true
            case .groupingDimension:
                return false
            }
        }
    }

    private func isSupportedCombination(
        operation: MarinaCandidateOperation,
        measure: MarinaCandidateMeasure,
        candidate: MarinaQueryPlanCandidate
    ) -> Bool {
        switch operation {
        case .sum:
            return [.spend, .income, .categoryShare, .presetAmount, .transactionAmount].contains(measure)
        case .average:
            return [.spend, .income, .savings].contains(measure)
        case .count:
            return measure == .transactionFrequency
        case .rank:
            return candidate.grouping != nil || candidate.ranking != nil
        case .compare:
            return [.spend, .income, .savings, .categoryShare].contains(measure)
        case .minimum, .maximum, .trend, .forecast, .simulate:
            return false
        }
    }

    private func responseShape(
        operation: MarinaCandidateOperation,
        measure: MarinaCandidateMeasure,
        candidate: MarinaQueryPlanCandidate
    ) -> MarinaResponseShapeHint {
        switch operation {
        case .compare:
            return .comparison
        case .rank:
            if candidate.responseShapeHint == .groupedBreakdown {
                return .groupedBreakdown
            }
            return .rankedList
        case .sum where measure == .categoryShare:
            return .groupedBreakdown
        case .trend:
            return .chartRows
        case .sum, .average, .count, .minimum, .maximum, .forecast, .simulate:
            if candidate.responseShapeHint == .summaryCard {
                return .summaryCard
            }
            return candidate.responseShapeHint == .groupedBreakdown ? .groupedBreakdown : .scalarCurrency
        }
    }

    private func unsupportedKind(from hint: MarinaUnsupportedHint) -> MarinaUnsupportedResponseKind {
        switch hint {
        case .unsupportedOperation:
            return .unsupportedOperation
        case .unsupportedCombination:
            return .unsupportedCombination
        case .missingRequiredTarget:
            return .unsupportedTargetType
        case .unsupportedSimulation:
            return .unsupportedSimulation
        case .unsupportedProjection:
            return .unsupportedOperation
        case .unsupportedExclusionFilter,
             .unsupportedBudgetLimit,
             .unsupportedFrequencyRanking,
             .unsupportedCardRanking,
             .unsupportedRankedComparison:
            return .unsupportedCombination
        case .lowConfidence:
            return .unsupportedCombination
        }
    }

    private func unsupportedMessage(from hint: MarinaUnsupportedHint) -> String {
        switch hint {
        case .unsupportedOperation:
            return "That operation is not supported in this validation shell."
        case .unsupportedCombination:
            return "That query shape is not supported in this validation shell."
        case .missingRequiredTarget:
            return "The candidate is missing a required target."
        case .unsupportedSimulation:
            return "Simulation plans are not validated in this phase."
        case .unsupportedProjection:
            return "Projection and forecast plans are not executable in this phase."
        case .unsupportedExclusionFilter:
            return "Exclusion filters are not executable in this phase."
        case .unsupportedBudgetLimit:
            return "Budget-limit availability checks are not executable in this phase."
        case .unsupportedFrequencyRanking:
            return "Frequency rankings are not executable in this phase."
        case .unsupportedCardRanking:
            return "Card rankings are not executable in this phase."
        case .unsupportedRankedComparison:
            return "Ranked comparison and delta plans are not executable in this phase."
        case .lowConfidence:
            return "That query is too uncertain to validate safely."
        }
    }

    private func clarification(
        _ kind: MarinaClarificationKind,
        message: String,
        candidate: MarinaQueryPlanCandidate,
        choices: [MarinaClarificationChoice] = []
    ) -> MarinaPlanValidationOutcome {
        .clarification(
            MarinaTypedClarification(
                kind: kind,
                message: message,
                candidate: candidate,
                choices: choices
            )
        )
    }

    private func unsupported(
        _ kind: MarinaUnsupportedResponseKind,
        message: String,
        candidate: MarinaQueryPlanCandidate
    ) -> MarinaPlanValidationOutcome {
        .unsupported(
            MarinaTypedUnsupportedResponse(
                kind: kind,
                message: message,
                candidate: candidate
            )
        )
    }
}
