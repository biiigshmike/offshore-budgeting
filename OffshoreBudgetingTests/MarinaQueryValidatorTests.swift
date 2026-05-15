import Foundation
import Testing
@testable import Offshore

struct MarinaQueryValidatorTests {
    @Test func validator_validCardSpendPromotesToNonExecutableShellPlan() {
        let mention = MarinaUnresolvedEntityMention(role: .filter, rawText: "Apple Card", typeHint: .card)
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: "total spend on my Apple Card",
            operation: .sum,
            measure: .spend,
            entityMentions: [mention],
            responseShapeHint: .scalarCurrency,
            confidence: .high
        )
        let resolved = resolvedCandidate(
            candidate,
            targets: [
                resolvedTarget(mention: mention, role: .filter, entityType: .card, displayName: "Apple Card")
            ]
        )

        let outcome = MarinaQueryValidator().validate(resolved)

        guard case .executable(let plan) = outcome else {
            Issue.record("Expected executable shell plan")
            return
        }
        #expect(plan.status == .notExecutableShell)
        #expect(plan.operation == .sum)
        #expect(plan.measure == .spend)
        #expect(plan.targets.first?.role == .filter)
        #expect(plan.targets.first?.entityType == .card)
        #expect(plan.responseShape == .scalarCurrency)
    }

    @Test func validator_validComparisonRequiresAndCarriesComparisonRange() {
        let mention = MarinaUnresolvedEntityMention(role: .primaryTarget, rawText: "Groceries", typeHint: .category)
        let primary = HomeQueryDateRange(startDate: date(2026, 5, 1), endDate: date(2026, 5, 31))
        let comparison = HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30))
        let candidate = MarinaQueryPlanCandidate(
            source: .heuristic,
            rawPrompt: "compare groceries this month to last month",
            operation: .compare,
            measure: .spend,
            entityMentions: [mention],
            timeScopes: [
                MarinaUnresolvedTimeScope(role: .primary, rawText: "this month", resolvedRangeHint: primary, periodUnitHint: .month),
                MarinaUnresolvedTimeScope(role: .comparison, rawText: "last month", resolvedRangeHint: comparison, periodUnitHint: .month)
            ],
            responseShapeHint: .scalarCurrency,
            confidence: .medium
        )
        let resolved = resolvedCandidate(
            candidate,
            targets: [
                resolvedTarget(mention: mention, role: .primaryTarget, entityType: .category, displayName: "Groceries")
            ],
            primaryDateRange: primary,
            comparisonDateRange: comparison
        )

        let outcome = MarinaQueryValidator().validate(resolved)

        guard case .executable(let plan) = outcome else {
            Issue.record("Expected executable shell plan")
            return
        }
        #expect(plan.status == .notExecutableShell)
        #expect(plan.operation == .compare)
        #expect(plan.comparisonDateRange?.startDate == comparison.startDate)
        #expect(plan.responseShape == .comparison)
    }

    @Test func validator_validNoTargetRankingPromotesToNonExecutableShellPlan() {
        let candidate = MarinaQueryPlanCandidate(
            source: .heuristic,
            rawPrompt: "where is my money going?",
            operation: .rank,
            measure: .spend,
            grouping: MarinaGroupingCandidate(dimension: .category),
            ranking: MarinaRankingCandidate(direction: .top, limit: 5),
            responseShapeHint: .scalarCurrency,
            confidence: .medium
        )

        let outcome = MarinaQueryValidator().validate(resolvedCandidate(candidate))

        guard case .executable(let plan) = outcome else {
            Issue.record("Expected executable shell plan")
            return
        }
        #expect(plan.status == .notExecutableShell)
        #expect(plan.targets.isEmpty)
        #expect(plan.grouping?.dimension == .category)
        #expect(plan.ranking?.direction == .top)
        #expect(plan.responseShape == .rankedList)
    }

    @Test func validator_unresolvedTargetReturnsTypedClarification() {
        let mention = MarinaUnresolvedEntityMention(role: .primaryTarget, rawText: "Travel", typeHint: .category)
        let candidate = MarinaQueryPlanCandidate(
            source: .heuristic,
            rawPrompt: "spend on Travel",
            operation: .sum,
            measure: .spend,
            entityMentions: [mention],
            confidence: .medium
        )

        let outcome = MarinaQueryValidator().validate(
            resolvedCandidate(candidate, unresolvedMentions: [mention])
        )

        guard case .clarification(let clarification) = outcome else {
            Issue.record("Expected typed clarification")
            return
        }
        #expect(clarification.kind == .missingTarget)
        #expect(clarification.candidate?.rawPrompt == candidate.rawPrompt)
        #expect(clarification.candidate?.operation == candidate.operation)
        #expect(clarification.candidate?.measure == candidate.measure)
        #expect(clarification.choices.first?.rawValue == "Travel")
    }

    @Test func validator_ambiguousTargetReturnsTypedClarification() {
        let mention = MarinaUnresolvedEntityMention(role: .primaryTarget, rawText: "Apple", typeHint: nil)
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: "spend on Apple",
            operation: .sum,
            measure: .spend,
            entityMentions: [mention],
            confidence: .medium
        )
        let ambiguous = MarinaAmbiguousEntityMention(
            mention: mention,
            choices: [
                MarinaClarificationChoice(title: "Apple", entityRole: .primaryTarget, entityTypeHint: .category, rawValue: "Apple"),
                MarinaClarificationChoice(title: "Apple", entityRole: .primaryTarget, entityTypeHint: .card, rawValue: "Apple")
            ]
        )

        let outcome = MarinaQueryValidator().validate(
            resolvedCandidate(candidate, ambiguousMentions: [ambiguous])
        )

        guard case .clarification(let clarification) = outcome else {
            Issue.record("Expected typed clarification")
            return
        }
        #expect(clarification.kind == .ambiguousTarget)
        #expect(clarification.choices.count == 2)
    }

    @Test func validator_missingComparisonRangeReturnsTypedDateClarification() {
        let candidate = MarinaQueryPlanCandidate(
            source: .heuristic,
            rawPrompt: "compare this month",
            operation: .compare,
            measure: .spend,
            confidence: .medium
        )

        let outcome = MarinaQueryValidator().validate(resolvedCandidate(candidate))

        guard case .clarification(let clarification) = outcome else {
            Issue.record("Expected typed clarification")
            return
        }
        #expect(clarification.kind == .missingDateRange)
    }

    @Test func validator_missingOperationAndMeasureReturnUnsupportedOperation() {
        let missingOperation = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: "groceries",
            measure: .spend,
            confidence: .medium
        )
        let missingMeasure = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: "sum something",
            operation: .sum,
            confidence: .medium
        )

        let operationOutcome = MarinaQueryValidator().validate(resolvedCandidate(missingOperation))
        let measureOutcome = MarinaQueryValidator().validate(resolvedCandidate(missingMeasure))

        guard case .unsupported(let operationUnsupported) = operationOutcome else {
            Issue.record("Expected unsupported missing operation")
            return
        }
        guard case .unsupported(let measureUnsupported) = measureOutcome else {
            Issue.record("Expected unsupported missing measure")
            return
        }

        #expect(operationUnsupported.kind == .unsupportedOperation)
        #expect(measureUnsupported.kind == .unsupportedOperation)
    }

    @Test func validator_lowConfidenceReturnsUnsupportedAndSimulationCanValidate() {
        let lowConfidence = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: "maybe groceries?",
            operation: .sum,
            measure: .spend,
            confidence: .low
        )
        let simulation = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: "if I increase Shopping",
            operation: .simulate,
            measure: .remainingBudget,
            confidence: .medium
        )

        let lowOutcome = MarinaQueryValidator().validate(resolvedCandidate(lowConfidence))
        let simulationOutcome = MarinaQueryValidator().validate(resolvedCandidate(simulation))

        guard case .unsupported(let lowUnsupported) = lowOutcome else {
            Issue.record("Expected low confidence unsupported")
            return
        }
        guard case .executable(let simulationPlan) = simulationOutcome else {
            Issue.record("Expected simulation to validate for composable execution")
            return
        }

        #expect(lowUnsupported.kind == .unsupportedCombination)
        #expect(simulationPlan.operation == .simulate)
        #expect(simulationPlan.measure == .remainingBudget)
    }

    @Test func validator_phase6BUnsupportedHintsReturnTypedUnsupportedBeforeExecution() {
        let cases: [(MarinaUnsupportedHint, MarinaCandidateOperation, MarinaCandidateMeasure, MarinaUnsupportedResponseKind)] = [
            (.unsupportedProjection, .forecast, .remainingBudget, .unsupportedOperation),
            (.unsupportedExclusionFilter, .sum, .spend, .unsupportedCombination),
            (.unsupportedBudgetLimit, .compare, .remainingBudget, .unsupportedCombination),
            (.unsupportedCardRanking, .rank, .spend, .unsupportedCombination),
            (.unsupportedRankedComparison, .compare, .spend, .unsupportedCombination)
        ]

        for (hint, operation, measure, expectedKind) in cases {
            let candidate = MarinaQueryPlanCandidate(
                source: .heuristic,
                rawPrompt: hint.rawValue,
                operation: operation,
                measure: measure,
                unsupportedHint: hint
            )

            let outcome = MarinaQueryValidator().validate(resolvedCandidate(candidate))

            guard case .unsupported(let unsupported) = outcome else {
                Issue.record("Expected unsupported for \(hint.rawValue)")
                continue
            }
            #expect(unsupported.kind == expectedKind)
            #expect(unsupported.candidate?.operation == operation)
            #expect(unsupported.candidate?.measure == measure)
        }
    }

    @Test func validator_rankedComparisonUnsupportedDoesNotRequireAdapterEvenWithDateScopes() {
        let primary = HomeQueryDateRange(startDate: date(2026, 5, 1), endDate: date(2026, 6, 1))
        let comparison = HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 5, 1))
        let candidate = MarinaQueryPlanCandidate(
            source: .heuristic,
            rawPrompt: "What expenses are making this month higher than last month?",
            operation: .compare,
            measure: .spend,
            timeScopes: [
                MarinaUnresolvedTimeScope(role: .primary, rawText: "this month", resolvedRangeHint: primary, periodUnitHint: .month),
                MarinaUnresolvedTimeScope(role: .comparison, rawText: "last month", resolvedRangeHint: comparison, periodUnitHint: .month)
            ],
            grouping: MarinaGroupingCandidate(dimension: .transaction),
            ranking: MarinaRankingCandidate(direction: .largest),
            responseShapeHint: .rankedList,
            unsupportedHint: .unsupportedRankedComparison
        )

        let outcome = MarinaQueryValidator().validate(
            resolvedCandidate(
                candidate,
                primaryDateRange: primary,
                comparisonDateRange: comparison
            )
        )

        guard case .unsupported(let unsupported) = outcome else {
            Issue.record("Expected ranked delta comparison to stay typed unsupported")
            return
        }
        #expect(unsupported.kind == .unsupportedCombination)
        #expect(unsupported.candidate?.operation == .compare)
        #expect(unsupported.candidate?.grouping?.dimension == .transaction)
    }

    @Test func validator_supportedPhase6ShapesStillPromoteToExecutablePlans() {
        let shareMention = MarinaUnresolvedEntityMention(role: .primaryTarget, rawText: "Food & Drink", typeHint: .category)
        let shareCandidate = MarinaQueryPlanCandidate(
            source: .heuristic,
            rawPrompt: "How much of my spending was Food & Drink?",
            operation: .sum,
            measure: .categoryShare,
            entityMentions: [shareMention],
            grouping: MarinaGroupingCandidate(dimension: .category),
            responseShapeHint: .groupedBreakdown
        )
        let shareOutcome = MarinaQueryValidator().validate(
            resolvedCandidate(
                shareCandidate,
                targets: [
                    resolvedTarget(mention: shareMention, role: .primaryTarget, entityType: .category, displayName: "Food & Drink")
                ]
            )
        )

        guard case .executable(let sharePlan) = shareOutcome else {
            Issue.record("Expected category share to remain executable")
            return
        }
        #expect(sharePlan.operation == .sum)
        #expect(sharePlan.measure == .categoryShare)
        #expect(sharePlan.responseShape == .groupedBreakdown)

        let frequencyCandidate = MarinaQueryPlanCandidate(
            source: .heuristic,
            rawPrompt: "spending too often",
            operation: .rank,
            measure: .transactionFrequency,
            grouping: MarinaGroupingCandidate(dimension: .transaction),
            ranking: MarinaRankingCandidate(direction: .mostFrequent),
            responseShapeHint: .rankedList
        )
        let frequencyOutcome = MarinaQueryValidator().validate(resolvedCandidate(frequencyCandidate))

        guard case .executable(let frequencyPlan) = frequencyOutcome else {
            Issue.record("Expected transaction frequency ranking to remain executable")
            return
        }
        #expect(frequencyPlan.operation == .rank)
        #expect(frequencyPlan.measure == .transactionFrequency)
        #expect(frequencyPlan.grouping?.dimension == .transaction)
    }

    @Test func validator_responseShapeHintIsAdvisoryAndCanBeOverridden() {
        let candidate = MarinaQueryPlanCandidate(
            source: .heuristic,
            rawPrompt: "what did I spend?",
            operation: .sum,
            measure: .spend,
            responseShapeHint: .rankedList,
            confidence: .medium
        )

        let outcome = MarinaQueryValidator().validate(resolvedCandidate(candidate))

        guard case .executable(let plan) = outcome else {
            Issue.record("Expected executable shell plan")
            return
        }
        #expect(plan.responseShape == .scalarCurrency)
    }

    @Test func semanticValidator_usesCatalogAndResolvedFiltersForExecutablePlan() {
        let categoryID = UUID()
        let filter = MarinaFilter(
            role: .primaryTarget,
            relationship: .category,
            value: "groceries",
            entityTypeHint: .category
        )
        let query = MarinaSemanticQuery(
            subject: .variableExpenses,
            operation: .average,
            filters: [filter],
            amountField: .budgetImpactAmount,
            averageBasis: .perTransaction,
            responseShape: .scalarCurrency
        )
        let resolved = MarinaResolvedSemanticQuery(
            query: query,
            candidate: nil,
            resolvedFilters: [
                MarinaResolvedFilter(
                    id: filter.id,
                    filter: filter,
                    role: .primaryTarget,
                    relationship: .category,
                    entityType: .category,
                    displayName: "Groceries",
                    sourceID: categoryID
                )
            ],
            unresolvedFilters: [],
            ambiguousFilters: [],
            primaryDateRange: nil,
            comparisonDateRange: nil,
            databaseLookupRequest: nil
        )

        let outcome = MarinaQueryValidator().validate(resolved)

        guard case .executable(let plan) = outcome else {
            Issue.record("Expected semantic query to validate")
            return
        }
        #expect(plan.operation == .average)
        #expect(plan.measure == .spend)
        #expect(plan.targets.first?.displayName == "Groceries")
        #expect(plan.targets.first?.sourceID == categoryID)
    }

    @Test func semanticValidator_rejectsUnsupportedCatalogOperation() {
        let query = MarinaSemanticQuery(
            subject: .cards,
            operation: .median,
            amountField: .budgetImpactAmount
        )
        let resolved = MarinaResolvedSemanticQuery(
            query: query,
            candidate: nil,
            resolvedFilters: [],
            unresolvedFilters: [],
            ambiguousFilters: [],
            primaryDateRange: nil,
            comparisonDateRange: nil,
            databaseLookupRequest: nil
        )

        let outcome = MarinaQueryValidator().validate(resolved)

        guard case .unsupported(let unsupported) = outcome else {
            Issue.record("Expected unsupported semantic operation")
            return
        }
        #expect(unsupported.kind == .unsupportedOperation)
    }

    private func resolvedCandidate(
        _ candidate: MarinaQueryPlanCandidate,
        targets: [MarinaResolvedEntityMention] = [],
        unresolvedMentions: [MarinaUnresolvedEntityMention] = [],
        ambiguousMentions: [MarinaAmbiguousEntityMention] = [],
        primaryDateRange: HomeQueryDateRange? = nil,
        comparisonDateRange: HomeQueryDateRange? = nil
    ) -> MarinaResolvedQueryCandidate {
        MarinaResolvedQueryCandidate(
            candidate: candidate,
            resolvedTargets: targets,
            unresolvedMentions: unresolvedMentions,
            ambiguousMentions: ambiguousMentions,
            primaryDateRange: primaryDateRange,
            comparisonDateRange: comparisonDateRange
        )
    }

    private func resolvedTarget(
        mention: MarinaUnresolvedEntityMention,
        role: MarinaResolvedTargetRole,
        entityType: MarinaCandidateEntityTypeHint,
        displayName: String
    ) -> MarinaResolvedEntityMention {
        MarinaResolvedEntityMention(
            id: mention.id,
            mention: mention,
            role: role,
            entityType: entityType,
            displayName: displayName,
            sourceID: UUID()
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
