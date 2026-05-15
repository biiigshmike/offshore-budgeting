import Foundation

struct MarinaQueryValidator {
    private let semanticAdapter = MarinaSemanticQueryAdapter()

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

        if operation == .trend {
            return unsupported(
                .unsupportedOperation,
                message: "Trend plans are not validated in this phase.",
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
                        rawValue: unresolvedMention.rawText,
                        mentionID: unresolvedMention.id
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

        guard MarinaQueryCapabilityMatrix.supports(
            operation: operation,
            measure: measure,
            targetTypes: resolved.resolvedTargets.map(\.entityType),
            grouping: candidate.grouping?.dimension
        ) else {
            return unsupported(
                .unsupportedCombination,
                message: "That operation and measure combination is not supported by Marina's entity capability matrix.",
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

    func validate(
        _ resolved: MarinaResolvedSemanticQuery,
        catalog: MarinaEntityCatalog = .current
    ) -> MarinaPlanValidationOutcome {
        let candidate = resolved.candidate ?? compatibilityCandidate(from: resolved.query)
        let query = resolved.query

        guard let descriptor = catalog.descriptor(for: entityName(for: query.subject)) else {
            return unsupported(
                .unsupportedTargetType,
                message: "That data type is not available to Marina's safe query model.",
                candidate: candidate
            )
        }

        guard descriptor.workspaceScope.isMandatory == false || descriptor.workspaceScope.path.isEmpty == false else {
            return unsupported(
                .unsupportedTargetType,
                message: "That data type does not expose a safe workspace scope.",
                candidate: candidate
            )
        }

        if query.operation != .lookupDetails,
           let ambiguous = resolved.ambiguousFilters.first {
            return clarification(
                .ambiguousTarget,
                message: "I found multiple possible matches for that target.",
                candidate: candidate,
                choices: ambiguous.choices
            )
        }

        if query.operation != .lookupDetails,
           let unresolved = resolved.unresolvedFilters.first {
            return clarification(
                .missingTarget,
                message: "I couldn't safely resolve that target.",
                candidate: candidate,
                choices: [
                    MarinaClarificationChoice(
                        title: unresolved.value.isEmpty ? "Target" : unresolved.value,
                        entityRole: mentionRole(from: unresolved.role),
                        entityTypeHint: unresolved.entityTypeHint,
                        rawValue: unresolved.value,
                        mentionID: unresolved.id
                    )
                ]
            )
        }

        if query.operation != .lookupDetails,
           requiresResolvedTarget(query),
           resolved.resolvedFilters.isEmpty {
            return clarification(
                .missingTarget,
                message: "I need a target before I can answer that safely.",
                candidate: candidate
            )
        }

        guard supports(operation: query.operation, descriptor: descriptor) else {
            return unsupported(
                .unsupportedOperation,
                message: "That operation is not supported for \(descriptor.displayName).",
                candidate: candidate
            )
        }

        if requiresAmountField(query.operation),
           query.amountField == nil || amountFieldSupported(query.amountField, by: descriptor) == false {
            return unsupported(
                .unsupportedCombination,
                message: "That money operation needs a supported amount field for \(descriptor.displayName).",
                candidate: candidate
            )
        }

        if let amountField = query.amountField,
           amountFieldSupported(amountField, by: descriptor) == false,
           query.operation != .lookupDetails {
            return unsupported(
                .unsupportedCombination,
                message: "The \(amountField.rawValue) field is not available for \(descriptor.displayName).",
                candidate: candidate
            )
        }

        if query.operation == .compare, resolved.comparisonDateRange == nil {
            return clarification(
                .missingDateRange,
                message: "I need the comparison period before I can answer that safely.",
                candidate: candidate
            )
        }

        guard query.operation == .lookupDetails || relationshipsSupported(resolved.resolvedFilters, by: descriptor) else {
            return unsupported(
                .unsupportedCombination,
                message: "One of those filters is not supported for \(descriptor.displayName).",
                candidate: candidate
            )
        }

        let basePlan = semanticAdapter.aggregationPlan(from: query)
        let plan = MarinaAggregationPlan(
            status: .notExecutableShell,
            operation: basePlan.operation,
            measure: basePlan.measure,
            targets: resolved.resolvedFilters.map { filter in
                MarinaResolvedAggregationTarget(
                    id: filter.id,
                    role: filter.role,
                    entityType: filter.entityType,
                    displayName: filter.displayName,
                    sourceID: filter.sourceID
                )
            },
            dateRange: resolved.primaryDateRange,
            comparisonDateRange: resolved.comparisonDateRange,
            grouping: basePlan.grouping,
            ranking: basePlan.ranking,
            limit: basePlan.limit,
            responseShape: basePlan.responseShape ?? responseShape(operation: basePlan.operation, measure: basePlan.measure, candidate: candidate)
        )

        if query.operation != .lookupDetails,
           MarinaQueryCapabilityMatrix.supports(
               operation: plan.operation,
               measure: plan.measure,
               targetTypes: plan.targets.map(\.entityType),
               grouping: plan.grouping?.dimension
           ) == false {
            return unsupported(
                .unsupportedCombination,
                message: "That operation and measure combination is not supported by Marina's entity catalog.",
                candidate: candidate
            )
        }

        return .executable(plan)
    }

    private func requiresResolvedTarget(_ candidate: MarinaQueryPlanCandidate) -> Bool {
        candidate.entityMentions.contains { mention in
            switch mention.role {
            case .filter, .excludeFilter, .primaryTarget, .comparisonTarget, .simulationInput, .simulationOutput:
                return true
            case .groupingDimension:
                return false
            }
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
        case .listRows:
            return .rankedList
        case .sum where measure == .categoryShare:
            return .groupedBreakdown
        case .trend:
            return .chartRows
        case .sum, .average, .count, .minimum, .maximum, .forecast, .simulate, .lookupDetails:
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
            return "That operation is not supported for safe Marina queries yet."
        case .unsupportedCombination:
            return "That query shape is not supported for safe Marina queries yet."
        case .missingRequiredTarget:
            return "The candidate is missing a required target."
        case .unsupportedSimulation:
            return "Simulation plans are not supported for read-only Marina answers yet."
        case .unsupportedProjection:
            return "Projection and forecast plans are not supported for read-only Marina answers yet."
        case .unsupportedExclusionFilter:
            return "Exclusion filters are not supported for safe Marina queries yet."
        case .unsupportedBudgetLimit:
            return "Budget-limit availability checks are not supported for safe Marina queries yet."
        case .unsupportedFrequencyRanking:
            return "Frequency rankings are not supported for safe Marina queries yet."
        case .unsupportedCardRanking:
            return "Card rankings are not supported for safe Marina queries yet."
        case .unsupportedRankedComparison:
            return "Ranked comparison and delta plans are not supported for safe Marina queries yet."
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

    private func entityName(for subject: MarinaSubject) -> String {
        switch subject {
        case .variableExpenses:
            return "VariableExpense"
        case .plannedExpenses:
            return "PlannedExpense"
        case .income:
            return "Income"
        case .budgets:
            return "Budget"
        case .cards:
            return "Card"
        case .categories:
            return "Category"
        case .presets:
            return "Preset"
        case .savingsAccounts:
            return "SavingsAccount"
        case .savingsLedgerEntries:
            return "SavingsLedgerEntry"
        case .reconciliationAccounts:
            return "AllocationAccount"
        case .reconciliationItems:
            return "AllocationSettlement"
        case .workspaces:
            return "Workspace"
        case .merchant:
            return "Virtual: Merchant"
        case .incomeSource:
            return "Virtual: IncomeSource"
        case .uncategorizedExpenses:
            return "Virtual: Uncategorized"
        }
    }

    private func supports(
        operation: MarinaOperation,
        descriptor: MarinaEntityDescriptor
    ) -> Bool {
        let supported = Set(descriptor.supportedOperations.map { $0.lowercased() })
        switch operation {
        case .sum:
            return supported.contains("total")
                || supported.contains("plannedaggregation")
                || supported.contains("allocatedspend")
                || descriptor.isAggregatable
        case .average:
            return supported.contains("average") || descriptor.isAggregatable
        case .count:
            return descriptor.isQueryable
        case .minimum, .maximum, .median:
            return descriptor.isAggregatable
        case .list:
            return supported.contains("listrows") || descriptor.isSearchable || descriptor.isQueryable
        case .compare:
            return supported.contains("compare") || descriptor.isAggregatable
        case .rank:
            return supported.contains("rank")
        case .breakdown:
            return descriptor.canBeRelationshipFilter || supported.contains("category bucket summaries")
        case .percentageShare:
            return supported.contains("share")
                || supported.contains("category bucket summaries")
                || descriptor.entityName == "VariableExpense"
        case .lookupDetails:
            return supported.contains("lookupdetails") || descriptor.isSearchable
        case .forecast:
            return descriptor.entityName == "Budget"
                || descriptor.entityName == "SavingsLedgerEntry"
                || supported.contains("forecast")
        case .simulate:
            return descriptor.entityName == "Budget" || supported.contains("simulate")
        }
    }

    private func requiresAmountField(_ operation: MarinaOperation) -> Bool {
        switch operation {
        case .sum, .average, .minimum, .maximum, .median, .percentageShare:
            return true
        case .compare:
            return false
        case .count, .list, .rank, .breakdown, .lookupDetails, .forecast, .simulate:
            return false
        }
    }

    private func amountFieldSupported(
        _ field: MarinaAmountField?,
        by descriptor: MarinaEntityDescriptor
    ) -> Bool {
        guard let field else { return false }
        let fields = Set(descriptor.amountFields.map { normalized($0) })
        switch field {
        case .amount:
            return fields.contains("amount") || descriptor.amountFields.isEmpty == false
        case .plannedAmount:
            return fields.contains("plannedamount")
        case .actualAmount:
            return fields.contains("actualamount")
        case .effectivePlannedAmount:
            return fields.contains("effectiveamount") || fields.contains("effectiveplannedamount")
        case .spendingAmount:
            return fields.contains("spendingamount") || fields.contains("expenseamount") || fields.contains("amount")
        case .ledgerSignedAmount:
            return fields.contains("ledgersignedamount") || fields.contains("amount")
        case .budgetImpactAmount:
            return fields.contains("budgetimpact") || fields.contains("budgetimpactamount") || fields.contains("expenseamount") || fields.contains("amount")
        case .incomeAmount:
            return fields.contains("incomeamount") || fields.contains("amount")
        case .savingsAmount:
            return fields.contains("savingsamount") || fields.contains("actualsavings") || fields.contains("amount") || fields.contains("total")
        case .allocatedAmount:
            return fields.contains("allocatedamount") || fields.contains("amount")
        case .reconciliationBalance:
            return descriptor.entityName == "AllocationAccount"
                || fields.contains("reconciliationbalance")
                || fields.contains("amount")
        }
    }

    private func relationshipsSupported(
        _ filters: [MarinaResolvedFilter],
        by descriptor: MarinaEntityDescriptor
    ) -> Bool {
        guard filters.isEmpty == false else { return true }
        if descriptor.canBeRelationshipFilter == false {
            return false
        }
        return filters.allSatisfy { filter in
            switch filter.relationship {
            case .unknown:
                return false
            case .uncategorized:
                return descriptor.relationships.contains { normalized($0.name).contains("category") }
                    || descriptor.entityName == "Virtual: Uncategorized"
            default:
                return true
            }
        }
    }

    private func requiresResolvedTarget(_ query: MarinaSemanticQuery) -> Bool {
        query.filters.contains { filter in
            switch filter.role {
            case .filter, .excludeFilter, .primaryTarget, .comparisonTarget, .simulationInput, .simulationOutput:
                return true
            case .groupingDimension:
                return false
            }
        }
    }

    private func mentionRole(from role: MarinaResolvedTargetRole) -> MarinaEntityMentionRole {
        switch role {
        case .filter:
            return .filter
        case .excludeFilter:
            return .excludeFilter
        case .primaryTarget:
            return .primaryTarget
        case .comparisonTarget:
            return .comparisonTarget
        case .groupingDimension:
            return .groupingDimension
        case .simulationInput:
            return .simulationInput
        case .simulationOutput:
            return .simulationOutput
        }
    }

    private func compatibilityCandidate(from query: MarinaSemanticQuery) -> MarinaQueryPlanCandidate {
        let plan = semanticAdapter.aggregationPlan(from: query)
        return MarinaQueryPlanCandidate(
            source: .heuristic,
            rawPrompt: "semantic query",
            operation: plan.operation,
            measure: plan.measure,
            entityMentions: query.filters.map { filter in
                MarinaUnresolvedEntityMention(
                    id: filter.id,
                    role: mentionRole(from: filter.role),
                    rawText: filter.value,
                    typeHint: filter.entityTypeHint,
                    allowedTypeHints: filter.entityTypeHint.map { [$0] },
                    confidence: .medium
                )
            },
            timeScopes: [
                query.dateRange.map {
                    MarinaUnresolvedTimeScope(
                        role: $0.role,
                        rawText: $0.rawText,
                        resolvedRangeHint: $0.resolvedRange,
                        periodUnitHint: $0.periodUnit
                    )
                },
                query.comparisonDateRange.map {
                    MarinaUnresolvedTimeScope(
                        role: $0.role,
                        rawText: $0.rawText,
                        resolvedRangeHint: $0.resolvedRange,
                        periodUnitHint: $0.periodUnit
                    )
                }
            ].compactMap { $0 },
            grouping: plan.grouping,
            ranking: plan.ranking,
            limit: plan.limit,
            responseShapeHint: plan.responseShape,
            confidence: .medium
        )
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }
}

typealias MarinaPlanValidator = MarinaQueryValidator
