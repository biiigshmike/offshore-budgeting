import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct MarinaSharedPipelineCoordinatorTests {
    @Test func coordinator_gateOffFallsBackWithoutRunningSharedPipeline() async throws {
        let fixture = try makeFixture()
        let result = await coordinator().run(
            prompt: "What did I spend this month?",
            context: sharedContext(fixture: fixture, sharedPipelineEnabled: false)
        )

        guard case .fallbackToLegacy(let trace) = result else {
            Issue.record("Gate-off shared pipeline should fall back to legacy.")
            return
        }
        #expect(trace.fallbackReason == .gateDisabled)
        #expect(trace.selectedPath == .legacy)
        #expect(trace.candidateSummary == nil)
    }

    @Test func coordinator_gateOnAIOptOutUsesHeuristicInterpreter() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let result = await coordinator().run(
            prompt: "total spend on my Apple Card",
            context: sharedContext(fixture: fixture, aiOptInEnabled: false)
        )

        guard case .handled(let answer, let aggregationResult, let homeQueryPlan, let trace) = result else {
            Issue.record("Expected heuristic shared pipeline to handle card spend.")
            return
        }
        #expect(trace.selectedPath == .sharedHeuristic)
        #expect(trace.interpreterSource == .heuristic)
        #expect(trace.aiOptIn == false)
        #expect(trace.aiRouteEligible == false)
        #expect(trace.selectedInterpreter == .heuristic)
        #expect(trace.interpreterSelectionReason == .aiOptOut)
        #expect(trace.modelAttempted == false)
        #expect(trace.heuristicAttempted == true)
        #expect(trace.heuristicUsedAsFallback == false)
        #expect(homeQueryPlan?.metric == .cardSpendTotal)
        #expect(answer.kind == .metric)
        guard case .scalar(let scalar) = aggregationResult else {
            Issue.record("Expected scalar result.")
            return
        }
        #expect((scalar.renderedValue ?? "").filter(\.isNumber).contains("500"))
    }

    @Test func coordinator_aiUnavailableFallsBackToHeuristic() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let result = await coordinator(availability: SharedPipelineStubAvailability(status: .unavailable(reason: "test_unavailable"))).run(
            prompt: "total spend on my Apple Card",
            context: sharedContext(fixture: fixture, aiOptInEnabled: true)
        )

        guard case .handled(_, _, let homeQueryPlan, let trace) = result else {
            Issue.record("AI unavailable should still allow heuristic execution.")
            return
        }
        #expect(trace.modelAvailabilitySummary == "unavailable:test_unavailable")
        #expect(trace.selectedPath == .sharedHeuristic)
        #expect(trace.aiAvailable == false)
        #expect(trace.aiRouteEligible == false)
        #expect(trace.selectedInterpreter == .heuristic)
        #expect(trace.interpreterSelectionReason == .modelUnavailable)
        #expect(trace.modelAttempted == false)
        #expect(trace.heuristicAttempted == true)
        #expect(trace.heuristicUsedAsFallback == false)
        #expect(homeQueryPlan?.metric == .cardSpendTotal)
    }

    @Test func recoveryPolicy_weirdLatelyAddsNormalityInsightWithoutChangingTarget() {
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: "am I spending weirdly on groceries lately?",
            operation: .sum,
            measure: .spend,
            entityMentions: [
                MarinaUnresolvedEntityMention(role: .filter, rawText: "Groceries", typeHint: .category)
            ]
        )

        let repaired = MarinaQueryRecoveryPolicy().canonicalized(
            candidate: candidate,
            explicitConstraints: MarinaExplicitPromptConstraints(categories: ["groceries"]),
            now: sharedPipelineDate(2026, 5, 15),
            defaultPeriodUnit: .month
        )

        #expect(repaired.operation == .sum)
        #expect(repaired.measure == .spend)
        #expect(repaired.entityMentions == candidate.entityMentions)
        #expect(repaired.insightIntent == .normalityCheck)
    }

    @Test func recoveryPolicy_worseThisMonthThanLastMonthBecomesComparison() {
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: "is groceries worse this month than last month?",
            operation: nil,
            measure: .spend,
            entityMentions: [
                MarinaUnresolvedEntityMention(role: .primaryTarget, rawText: "Groceries", typeHint: .category)
            ],
            unsupportedHint: .unsupportedOperation
        )

        let repaired = MarinaQueryRecoveryPolicy().canonicalized(
            candidate: candidate,
            explicitConstraints: MarinaExplicitPromptConstraints(categories: ["groceries"], hasDateConstraint: true),
            now: sharedPipelineDate(2026, 5, 15),
            defaultPeriodUnit: .month
        )

        #expect(repaired.operation == .compare)
        #expect(repaired.measure == .spend)
        #expect(repaired.unsupportedHint == nil)
        #expect(repaired.insightIntent == .changeSummary)
        #expect(repaired.timeScopes.map(\.role).contains(.primary))
        #expect(repaired.timeScopes.map(\.role).contains(.comparison))
    }

    @Test func recoveryPolicy_whyHigherAddsContributorInsightAndComparisonDates() {
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: "why is groceries higher?",
            operation: .sum,
            measure: .spend,
            entityMentions: [
                MarinaUnresolvedEntityMention(role: .filter, rawText: "Groceries", typeHint: .category)
            ]
        )

        let repaired = MarinaQueryRecoveryPolicy().canonicalized(
            candidate: candidate,
            explicitConstraints: MarinaExplicitPromptConstraints(categories: ["groceries"]),
            now: sharedPipelineDate(2026, 5, 15),
            defaultPeriodUnit: .month
        )

        #expect(repaired.operation == .compare)
        #expect(repaired.measure == .spend)
        #expect(repaired.entityMentions == candidate.entityMentions)
        #expect(repaired.insightIntent == .contributorAnalysis)
        #expect(repaired.timeScopes.map(\.role).contains(.comparison))
    }

    @Test func recoveryPolicy_biggestOffendersPreservesLargestRanking() {
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: "show groceries this month and the biggest offenders",
            operation: .sum,
            measure: .spend,
            entityMentions: [
                MarinaUnresolvedEntityMention(role: .filter, rawText: "Groceries", typeHint: .category)
            ],
            timeScopes: [
                MarinaUnresolvedTimeScope(
                    role: .primary,
                    rawText: "this month",
                    resolvedRangeHint: HomeQueryDateRange(startDate: sharedPipelineDate(2026, 5, 1), endDate: sharedPipelineDate(2026, 5, 31)),
                    periodUnitHint: .month
                )
            ]
        )

        let repaired = MarinaQueryRecoveryPolicy().canonicalized(
            candidate: candidate,
            explicitConstraints: MarinaExplicitPromptConstraints(categories: ["groceries"], hasDateConstraint: true, sort: .largest),
            now: sharedPipelineDate(2026, 5, 15),
            defaultPeriodUnit: .month
        )

        #expect(repaired.operation == .rank)
        #expect(repaired.measure == .transactionAmount)
        #expect(repaired.grouping?.dimension == .transaction)
        #expect(repaired.ranking?.direction == .largest)
        #expect(repaired.limit == 5)
        #expect(repaired.insightIntent == .multiPartContributors)
    }

    @Test func insightBuilder_changeSummaryAddsStatusAndComparisonRows() throws {
        let fixture = try makeFixture()
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: "is groceries worse?",
            operation: .compare,
            measure: .spend,
            insightIntent: .changeSummary
        )
        let answer = HomeAnswer(
            queryID: UUID(),
            kind: .comparison,
            title: "Groceries Comparison",
            rows: [
                HomeAnswerRow(title: "May", value: "$120.00"),
                HomeAnswerRow(title: "April", value: "$80.00")
            ]
        )
        let result = MarinaAggregationResult.comparison(
            MarinaComparisonAggregationResult(
                title: "Groceries Comparison",
                primaryLabel: "May",
                primaryRenderedValue: "$120.00",
                primaryAmount: 120,
                comparisonLabel: "April",
                comparisonRenderedValue: "$80.00",
                comparisonAmount: 80,
                deltaRenderedValue: "Up $40.00",
                sourceAnswer: answer
            )
        )

        let enriched = MarinaInsightContextBuilder().enrich(
            answer: answer,
            result: result,
            candidate: candidate,
            resolved: emptyResolved(candidate),
            semanticResolved: nil,
            provider: fixture.provider,
            now: sharedPipelineDate(2026, 5, 15)
        )

        #expect(enriched.rows.contains { $0.title == "Status" && $0.value.hasPrefix("Watch") })
        #expect(enriched.rows.contains { $0.title == "Compared With" && $0.value.contains("April") })
        #expect(enriched.rows.contains { $0.title == "Pattern" && $0.value == "rising" })
    }

    @Test func insightBuilder_contributorAnalysisAddsLargestDriver() throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: "why is groceries higher?",
            operation: .sum,
            measure: .spend,
            entityMentions: [
                MarinaUnresolvedEntityMention(role: .filter, rawText: "Groceries", typeHint: .category)
            ],
            insightIntent: .contributorAnalysis
        )
        let resolved = MarinaResolvedQueryCandidate(
            candidate: candidate,
            resolvedTargets: [
                MarinaResolvedEntityMention(
                    id: UUID(),
                    mention: candidate.entityMentions[0],
                    role: .filter,
                    entityType: .category,
                    displayName: "Groceries",
                    sourceID: fixture.groceries.id
                )
            ],
            unresolvedMentions: [],
            ambiguousMentions: [],
            primaryDateRange: HomeQueryDateRange(startDate: sharedPipelineDate(2026, 5, 1), endDate: sharedPipelineDate(2026, 5, 31)),
            comparisonDateRange: nil
        )
        let answer = HomeAnswer(queryID: UUID(), kind: .metric, title: "Groceries", primaryValue: "$50.00")
        let result = MarinaAggregationResult.scalar(
            MarinaScalarAggregationResult(
                title: "Groceries",
                renderedValue: "$50.00",
                amount: 50,
                rows: [],
                sourceAnswer: answer
            )
        )

        let enriched = MarinaInsightContextBuilder().enrich(
            answer: answer,
            result: result,
            candidate: candidate,
            resolved: resolved,
            semanticResolved: nil,
            provider: fixture.provider,
            now: sharedPipelineDate(2026, 5, 15)
        )

        #expect(enriched.rows.contains { $0.title == "Main Driver" && $0.value.contains("Groceries Variable") })
    }

    @Test func insightBuilder_noDataUsesThinDataFallbackForNormality() throws {
        let fixture = try makeFixture()
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: "am I spending weirdly on groceries lately?",
            operation: .sum,
            measure: .spend,
            insightIntent: .normalityCheck
        )
        let answer = HomeAnswer(queryID: UUID(), kind: .metric, title: "Groceries", primaryValue: "$0.00")
        let result = MarinaAggregationResult.scalar(
            MarinaScalarAggregationResult(
                title: "Groceries",
                renderedValue: "$0.00",
                amount: 0,
                rows: [],
                sourceAnswer: answer
            )
        )

        let enriched = MarinaInsightContextBuilder().enrich(
            answer: answer,
            result: result,
            candidate: candidate,
            resolved: emptyResolved(candidate),
            semanticResolved: nil,
            provider: fixture.provider,
            now: sharedPipelineDate(2026, 5, 15)
        )

        #expect(enriched.rows.contains { $0.title == "Status" && $0.value.hasPrefix("OK") })
        #expect(enriched.rows.contains { $0.title == "Pattern" && $0.value == "thin-data" })
    }

    @Test func insightBuilder_watchOutsOnlyAddsWatchWhenSupported() throws {
        let fixture = try makeFixture()
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: "what should I watch?",
            operation: .compare,
            measure: .spend,
            insightIntent: .watchOuts
        )
        let answer = HomeAnswer(queryID: UUID(), kind: .comparison, title: "Spend Comparison")
        let result = MarinaAggregationResult.comparison(
            MarinaComparisonAggregationResult(
                title: "Spend Comparison",
                primaryLabel: "Current",
                primaryRenderedValue: "$150.00",
                primaryAmount: 150,
                comparisonLabel: "Previous",
                comparisonRenderedValue: "$100.00",
                comparisonAmount: 100,
                deltaRenderedValue: "Up $50.00",
                sourceAnswer: answer
            )
        )

        let enriched = MarinaInsightContextBuilder().enrich(
            answer: answer,
            result: result,
            candidate: candidate,
            resolved: emptyResolved(candidate),
            semanticResolved: nil,
            provider: fixture.provider,
            now: sharedPipelineDate(2026, 5, 15)
        )

        #expect(enriched.rows.contains { $0.title == "Watch" && $0.value.contains("Rising") })
    }

    @Test func coordinator_foundationModelsInsightAddsDeterministicRows() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let command = MarinaSemanticCommand(
            family: .analytics,
            action: .total,
            datasets: [.variableExpenses],
            measure: .spend,
            includeFilters: [
                MarinaSemanticCommandFilter(rawText: "Groceries", allowedTypes: [.category])
            ],
            dateRange: HomeQueryDateRange(startDate: sharedPipelineDate(2026, 5, 1), endDate: sharedPipelineDate(2026, 5, 31)),
            periodUnit: .month,
            insightIntent: .normalityCheck
        )

        let result = await coordinator(
            structuredInterpreter: SharedPipelineStubStructuredInterpreter(structuredIntent: .semanticCommand(command))
        ).run(
            prompt: "am I spending weirdly on groceries lately?",
            context: sharedContext(fixture: fixture, aiOptInEnabled: true)
        )

        guard case .handled(let answer, _, _, let trace) = result else {
            Issue.record("Expected Foundation Models shared pipeline to handle insight prompt.")
            return
        }
        #expect(trace.selectedPath == .sharedFoundationModels)
        #expect(answer.rows.contains { $0.title == "Status" })
        #expect(answer.rows.contains { $0.title == "Pattern" })
    }

    @Test func coordinator_foundationModelsMissingInsightMetadataIsRepairedBeforeEnrichment() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let model = SharedPipelineStubStructuredInterpreter(
            structuredIntent: .query(
                MarinaStructuredQueryIntent(
                    metricRaw: "categorySpendTotal",
                    targetName: "Groceries",
                    targetTypeRaw: "category",
                    dateStartISO8601: "2026-05-01",
                    dateEndISO8601: "2026-05-31",
                    comparisonDateStartISO8601: nil,
                    comparisonDateEndISO8601: nil,
                    resultLimit: nil,
                    periodUnitRaw: "month",
                    confidenceRaw: "high",
                    clarification: nil
                )
            )
        )

        let result = await coordinator(structuredInterpreter: model).run(
            prompt: "am I spending weirdly on groceries lately?",
            context: sharedContext(fixture: fixture, aiOptInEnabled: true)
        )

        guard case .handled(let answer, _, _, let trace) = result else {
            Issue.record("Expected repaired weird/lately prompt to execute.")
            return
        }
        #expect(trace.selectedPath == .sharedFoundationModels)
        #expect(answer.rows.contains { $0.title == "Status" })
        #expect(answer.rows.contains { $0.title == "Pattern" })
    }

    @Test func coordinator_foundationModelsUnsupportedWorseDraftRepairsBeforeValidation() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let model = SharedPipelineStubStructuredInterpreter(
            structuredIntent: .query(
                MarinaStructuredQueryIntent(
                    metricRaw: "unsupportedWorseMetric",
                    targetName: "Groceries",
                    targetTypeRaw: "category",
                    dateStartISO8601: nil,
                    dateEndISO8601: nil,
                    comparisonDateStartISO8601: nil,
                    comparisonDateEndISO8601: nil,
                    resultLimit: nil,
                    periodUnitRaw: "month",
                    confidenceRaw: "high",
                    clarification: nil
                )
            )
        )

        let result = await coordinator(structuredInterpreter: model).run(
            prompt: "is groceries worse this month than last month?",
            context: sharedContext(fixture: fixture, aiOptInEnabled: true)
        )

        guard case .handled(let answer, let aggregationResult, let homeQueryPlan, let trace) = result else {
            Issue.record("Expected unsupported worse draft to repair before validation: \(workspaceAggregationDebugSummary(result))")
            return
        }
        #expect(trace.selectedPath == .sharedFoundationModels)
        #expect(trace.fallbackReason == nil)
        #expect(homeQueryPlan?.metric == .categoryMonthComparison)
        #expect(answer.kind == .comparison)
        guard case .comparison = aggregationResult else {
            Issue.record("Expected repaired worse prompt to execute as comparison.")
            return
        }
    }

    @Test func coordinator_foodDrinkBiggestOffendersPreservesSortAndExecutesFilteredRanking() async throws {
        let fixture = try makeFixture()
        let food = Offshore.Category(name: "Food & Drink", hexColor: "#AA00AA", workspace: fixture.workspace)
        fixture.context.insert(food)
        fixture.context.insert(VariableExpense(descriptionText: "Cafe", amount: 70, transactionDate: sharedPipelineDate(2026, 5, 9), workspace: fixture.workspace, card: fixture.appleCard, category: food))
        fixture.context.insert(VariableExpense(descriptionText: "Market", amount: 45, transactionDate: sharedPipelineDate(2026, 5, 10), workspace: fixture.workspace, card: fixture.appleCard, category: food))
        fixture.context.insert(VariableExpense(descriptionText: "Travel Outside Scope", amount: 500, transactionDate: sharedPipelineDate(2026, 5, 11), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.travel))
        try fixture.context.save()
        let model = SharedPipelineStubStructuredInterpreter(
            structuredIntent: .query(
                MarinaStructuredQueryIntent(
                    metricRaw: "categorySpendTotal",
                    targetName: "Food & Drink",
                    targetTypeRaw: "category",
                    dateStartISO8601: "2026-05-01",
                    dateEndISO8601: "2026-05-31",
                    comparisonDateStartISO8601: nil,
                    comparisonDateEndISO8601: nil,
                    resultLimit: nil,
                    periodUnitRaw: "month",
                    confidenceRaw: "high",
                    clarification: nil
                )
            )
        )

        let result = await coordinator(structuredInterpreter: model).run(
            prompt: "show Food & Drink this month and the biggest offenders",
            context: sharedContext(
                fixture: fixture,
                aiOptInEnabled: true,
                now: sharedPipelineDate(2026, 5, 15)
            )
        )

        guard case .handled(let answer, let aggregationResult, _, let trace) = result else {
            Issue.record("Expected biggest offenders to preserve sort and execute: \(workspaceAggregationDebugSummary(result))")
            return
        }
        #expect(trace.selectedPath == .sharedFoundationModels)
        #expect(trace.fallbackReason == nil)
        #expect(trace.executorResultSummary?.contains("recentFilteredTransactions") == true)
        #expect(answer.rows.contains { $0.title == "Main Driver" })
        guard case .workspaceCard(let card) = aggregationResult else {
            Issue.record("Expected filtered largest-offenders composable workspace result.")
            return
        }
        #expect(card.title == "Largest Purchases")
        #expect(card.rows.first?.label == "Cafe")
        #expect(card.rows.contains { $0.label == "Travel Outside Scope" } == false)
    }

    @Test func coordinator_repairedAmbiguousTargetStillClarifies() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        fixture.context.insert(Card(name: "Groceries", workspace: fixture.workspace))
        try fixture.context.save()
        let model = SharedPipelineStubStructuredInterpreter(
            structuredIntent: .query(
                MarinaStructuredQueryIntent(
                    metricRaw: "unsupportedWorseMetric",
                    targetName: "Groceries",
                    targetTypeRaw: nil,
                    dateStartISO8601: nil,
                    dateEndISO8601: nil,
                    comparisonDateStartISO8601: nil,
                    comparisonDateEndISO8601: nil,
                    resultLimit: nil,
                    periodUnitRaw: "month",
                    confidenceRaw: "high",
                    clarification: nil
                )
            )
        )

        let result = await coordinator(structuredInterpreter: model).run(
            prompt: "is groceries worse this month than last month?",
            context: sharedContext(fixture: fixture, aiOptInEnabled: true)
        )

        guard case .validationBlocked(_, let outcome, let trace) = result else {
            Issue.record("Expected ambiguous repaired target to remain blocked for clarification.")
            return
        }
        #expect(trace.selectedPath == .sharedFoundationModels)
        guard case .clarification(let clarification) = outcome else {
            Issue.record("Expected ambiguity clarification.")
            return
        }
        #expect(clarification.kind == .ambiguousTarget)
    }

    @Test func coordinator_heuristicPathDoesNotAddNLQOnlyInsightRows() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let result = await coordinator().run(
            prompt: "What did I spend on groceries this month?",
            context: sharedContext(fixture: fixture, aiOptInEnabled: false)
        )

        guard case .handled(let answer, _, _, let trace) = result else {
            Issue.record("Expected heuristic shared pipeline to handle prompt.")
            return
        }
        #expect(trace.selectedPath == .sharedHeuristic)
        #expect(answer.rows.contains { $0.title == "Status" } == false)
        #expect(answer.rows.contains { $0.title == "Pattern" } == false)
    }

    @Test func coordinator_modelUnavailableDoesNotAddInsightRows() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let command = MarinaSemanticCommand(
            family: .analytics,
            action: .total,
            datasets: [.variableExpenses],
            measure: .spend,
            includeFilters: [
                MarinaSemanticCommandFilter(rawText: "Groceries", allowedTypes: [.category])
            ],
            dateRange: HomeQueryDateRange(startDate: sharedPipelineDate(2026, 5, 1), endDate: sharedPipelineDate(2026, 5, 31)),
            periodUnit: .month,
            insightIntent: .normalityCheck
        )

        let result = await coordinator(
            availability: SharedPipelineStubAvailability(status: .unavailable(reason: "test_unavailable")),
            structuredInterpreter: SharedPipelineStubStructuredInterpreter(structuredIntent: .semanticCommand(command))
        ).run(
            prompt: "am I spending weirdly on groceries lately?",
            context: sharedContext(fixture: fixture, aiOptInEnabled: true)
        )

        guard case .handled(let answer, _, _, let trace) = result else {
            Issue.record("Expected unavailable model to fall back to heuristic.")
            return
        }
        #expect(trace.selectedPath == .sharedHeuristic)
        #expect(answer.rows.contains { $0.title == "Status" } == false)
        #expect(answer.rows.contains { $0.title == "Pattern" } == false)
    }

    @Test func coordinator_invalidModelOutputFallsBackToHeuristicWithTrace() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let result = await coordinator(structuredInterpreter: SharedPipelineThrowingStructuredInterpreter()).run(
            prompt: "total spend on my Apple Card",
            context: sharedContext(fixture: fixture, aiOptInEnabled: true)
        )

        guard case .handled(_, _, let homeQueryPlan, let trace) = result else {
            Issue.record("Model service failure should not crash and should use heuristic.")
            return
        }
        #expect(trace.selectedPath == .sharedHeuristic)
        #expect(trace.selectedInterpreter == .heuristic)
        #expect(trace.interpreterSelectionReason == .modelInvalidStructuredOutput)
        #expect(trace.modelAttempted == true)
        #expect(trace.heuristicAttempted == true)
        #expect(trace.heuristicUsedAsFallback == true)
        #expect(trace.fallbackReason == .modelInvalidStructuredOutput)
        #expect(trace.disagreementSummary == MarinaSharedPipelineFallbackReason.modelInvalidStructuredOutput.rawValue)
        #expect(homeQueryPlan?.metric == .cardSpendTotal)
    }

    @Test func coordinator_modelUnsupportedUsesHeuristicOnlyForExactExecutableFallback() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let result = await coordinator(
            structuredInterpreter: SharedPipelineStubStructuredInterpreter(structuredIntent: .unresolved)
        ).run(
            prompt: "total spend on my Apple Card",
            context: sharedContext(fixture: fixture, aiOptInEnabled: true)
        )

        guard case .handled(_, _, let homeQueryPlan, let trace) = result else {
            Issue.record("Expected unsupported model output to use exact executable heuristic fallback.")
            return
        }

        #expect(trace.selectedPath == .sharedHeuristic)
        #expect(trace.selectedInterpreter == .heuristic)
        #expect(trace.interpreterSelectionReason == .modelUnsupportedHeuristicExactMatch)
        #expect(trace.modelAttempted == true)
        #expect(trace.heuristicAttempted == true)
        #expect(trace.heuristicUsedAsFallback == true)
        #expect(trace.fallbackReason == .modelUnsupportedHeuristicExactMatch)
        #expect(homeQueryPlan?.metric == .cardSpendTotal)
    }

    @Test func coordinator_modelUnsupportedUsesHeuristicForFreshTemporalSpendPrompt() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()

        for prompt in ["What did I spend last month?", "What did I spend last week?"] {
            let result = await coordinator(
                structuredInterpreter: SharedPipelineStubStructuredInterpreter(structuredIntent: .unresolved)
            ).run(
                prompt: prompt,
                context: sharedContext(fixture: fixture, aiOptInEnabled: true)
            )

            guard case .handled(let answer, _, let homeQueryPlan, let trace) = result else {
                Issue.record("Expected unsupported model output to use executable heuristic for \(prompt): \(workspaceAggregationDebugSummary(result))")
                continue
            }

            #expect(answer.kind == .metric)
            #expect(homeQueryPlan?.metric == .spendTotal)
            #expect(trace.selectedPath == .sharedHeuristic)
            #expect(trace.interpreterSelectionReason == .modelUnsupportedHeuristicExactMatch)
            #expect(trace.turnClassification == .freshQuestion)
            #expect(trace.priorContextIncluded == false)
        }
    }

    @Test func coordinator_freshTurnSanitizesPriorContextBeforeFoundationModels() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let model = SharedPipelineCapturingStructuredInterpreter(structuredIntent: .unresolved)
        let prior = MarinaPriorQueryContext(
            lastQueryPlan: HomeQueryPlan(
                metric: .spendTotal,
                dateRange: nil,
                resultLimit: nil,
                confidenceBand: .high
            ),
            lastMetric: .spendTotal,
            lastTargetName: "Groceries",
            lastTargetType: .category,
            lastDateRange: HomeQueryDateRange(
                startDate: sharedPipelineDate(2026, 5, 1),
                endDate: sharedPipelineDate(2026, 5, 31)
            ),
            lastResultLimit: 5,
            lastPeriodUnit: .month
        )

        _ = await coordinator(structuredInterpreter: model).run(
            prompt: "What did I spend last month?",
            context: sharedContext(
                fixture: fixture,
                aiOptInEnabled: true,
                turnClassification: .freshQuestion,
                priorQueryContext: prior
            )
        )

        #expect(model.observedPriorContext?.hasContext == false)
    }

    @Test func coordinator_followUpTargetNarrowingPreservesPriorContextForFoundationModels() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let command = MarinaSemanticCommand(
            family: .analytics,
            action: .total,
            datasets: [.variableExpenses],
            measure: .spend,
            includeFilters: [
                MarinaSemanticCommandFilter(rawText: "Apple Card", allowedTypes: [.card])
            ],
            dateRange: HomeQueryDateRange(
                startDate: sharedPipelineDate(2026, 5, 1),
                endDate: sharedPipelineDate(2026, 5, 31)
            ),
            periodUnit: .month
        )
        let model = SharedPipelineCapturingStructuredInterpreter(structuredIntent: .semanticCommand(command))
        let prior = MarinaPriorQueryContext(
            lastQueryPlan: HomeQueryPlan(
                metric: .categorySpendTotal,
                dateRange: HomeQueryDateRange(
                    startDate: sharedPipelineDate(2026, 5, 1),
                    endDate: sharedPipelineDate(2026, 5, 31)
                ),
                resultLimit: nil,
                confidenceBand: .high,
                targetName: "Groceries"
            ),
            lastMetric: .categorySpendTotal,
            lastTargetName: "Groceries",
            lastTargetType: .category,
            lastDateRange: HomeQueryDateRange(
                startDate: sharedPipelineDate(2026, 5, 1),
                endDate: sharedPipelineDate(2026, 5, 31)
            ),
            lastResultLimit: nil,
            lastPeriodUnit: .month
        )

        let result = await coordinator(structuredInterpreter: model).run(
            prompt: "what about just Apple Card?",
            context: sharedContext(
                fixture: fixture,
                aiOptInEnabled: true,
                turnClassification: .followUp,
                priorQueryContext: prior
            )
        )

        guard case .handled(_, _, _, let trace) = result else {
            Issue.record("Expected Foundation Models follow-up narrowing to execute.")
            return
        }
        #expect(model.observedPriorContext?.lastTargetName == "Groceries")
        #expect(trace.priorContextIncluded == true)
        #expect(trace.selectedPath == .sharedFoundationModels)
    }

    @Test func coordinator_modelClarificationUsesExecutableHeuristicForBroadSpendPrompt() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let prompt = "What did I spend this month?"
        let model = SharedPipelineStubStructuredInterpreter(
            structuredIntent: .query(
                MarinaStructuredQueryIntent(
                    metricRaw: "spendTotal",
                    targetName: prompt,
                    targetTypeRaw: "entity",
                    dateStartISO8601: "2026-05-01",
                    dateEndISO8601: "2026-05-31",
                    comparisonDateStartISO8601: nil,
                    comparisonDateEndISO8601: nil,
                    resultLimit: nil,
                    periodUnitRaw: "month",
                    confidenceRaw: "high",
                    clarification: nil
                )
            )
        )

        let result = await coordinator(structuredInterpreter: model).run(
            prompt: prompt,
            context: sharedContext(fixture: fixture, aiOptInEnabled: true)
        )

        guard case .handled(let answer, _, let homeQueryPlan, let trace) = result else {
            Issue.record("Bad model clarification should be rescued by heuristic execution: \(workspaceAggregationDebugSummary(result))")
            return
        }
        #expect(answer.kind == .metric)
        #expect(homeQueryPlan?.metric == .spendTotal)
        #expect(trace.selectedPath == .sharedHeuristic)
        #expect(trace.selectedInterpreter == .heuristic)
        #expect(trace.interpreterSelectionReason == .modelClarificationHeuristicExactMatch)
        #expect(trace.modelAttempted == true)
        #expect(trace.heuristicAttempted == true)
        #expect(trace.heuristicUsedAsFallback == true)
        #expect(trace.fallbackReason == .modelClarificationHeuristicExactMatch)
    }

    @Test func coordinator_echoedMissingTargetClarificationIsNotActionable() {
        let prompt = "What did I spend last month?"
        let clarification = MarinaTypedClarification(
            kind: .missingTarget,
            message: "I couldn't safely resolve that target.",
            candidate: MarinaQueryPlanCandidate(source: .foundationModels, rawPrompt: prompt),
            pendingSemanticQuery: MarinaSemanticQuery(
                subject: .variableExpenses,
                operation: .sum,
                filters: [
                    MarinaFilter(
                        role: .filter,
                        relationship: .unknown,
                        value: prompt,
                        entityTypeHint: .merchant
                    )
                ],
                amountField: .spendingAmount
            ),
            patchSlot: .target,
            choices: [
                MarinaClarificationChoice(
                    title: prompt,
                    rawValue: prompt
                )
            ]
        )

        #expect(clarification.isActionable(for: prompt) == false)
        #expect(clarification.actionableChoices.isEmpty)
    }

    @Test func coordinator_typedClarificationKeepsTypedChoiceThatOverlapsPrompt() {
        let prompt = "Show Groceries"
        let clarification = MarinaTypedClarification(
            kind: .ambiguousTarget,
            message: "Which Groceries?",
            candidate: MarinaQueryPlanCandidate(source: .heuristic, rawPrompt: prompt),
            pendingSemanticQuery: MarinaSemanticQuery(
                subject: .variableExpenses,
                operation: .list,
                filters: [],
                amountField: .spendingAmount
            ),
            patchSlot: .target,
            choices: [
                MarinaClarificationChoice(
                    title: "Groceries",
                    entityRole: .filter,
                    entityTypeHint: .category,
                    patchSlot: .target,
                    rawValue: "Groceries",
                    sourceID: UUID()
                ),
                MarinaClarificationChoice(
                    title: "Groceries",
                    subtitle: "May 12 • $42.00 • Apple",
                    entityRole: .filter,
                    entityTypeHint: .expense,
                    patchSlot: .target,
                    rawValue: "Groceries",
                    sourceID: UUID()
                )
            ]
        )

        #expect(clarification.isActionable(for: prompt))
        #expect(clarification.actionableChoices(for: prompt).count == 2)
        #expect(clarification.actionableChoices(for: prompt).contains { $0.entityTypeHint == MarinaCandidateEntityTypeHint.category })
    }

    @Test func coordinator_modelSelectedWhenOptedInAvailableAndExecutable() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let model = SharedPipelineStubStructuredInterpreter(
            structuredIntent: .query(
                MarinaStructuredQueryIntent(
                    metricRaw: "cardSpendTotal",
                    targetName: "Apple Card",
                    targetTypeRaw: "card",
                    dateStartISO8601: nil,
                    dateEndISO8601: nil,
                    comparisonDateStartISO8601: nil,
                    comparisonDateEndISO8601: nil,
                    resultLimit: nil,
                    periodUnitRaw: "month",
                    confidenceRaw: "high",
                    clarification: nil
                )
            )
        )

        let result = await coordinator(structuredInterpreter: model).run(
            prompt: "total spend on my Apple Card",
            context: sharedContext(fixture: fixture, aiOptInEnabled: true)
        )

        guard case .handled(_, _, let homeQueryPlan, let trace) = result else {
            Issue.record("Expected executable model candidate to handle.")
            return
        }
        #expect(trace.selectedPath == .sharedFoundationModels)
        #expect(trace.interpreterSource == .foundationModels)
        #expect(trace.aiAvailable == true)
        #expect(trace.aiOptIn == true)
        #expect(trace.aiRouteEligible == true)
        #expect(trace.selectedInterpreter == .foundationModels)
        #expect(trace.interpreterSelectionReason == .modelEligible)
        #expect(trace.modelAttempted == true)
        #expect(trace.heuristicAttempted == false)
        #expect(trace.heuristicUsedAsFallback == false)
        #expect(trace.fallbackReason == nil)
        #expect(homeQueryPlan?.metric == .cardSpendTotal)
    }

    @Test func coordinator_aiEligibleRecentCategoryListRoutesModelFirstWithoutHeuristicPreemption() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let model = SharedPipelineStubStructuredInterpreter(
            structuredIntent: .semanticCommand(recentGroceriesListCommand(limit: 10))
        )

        let result = await coordinator(structuredInterpreter: model).run(
            prompt: "List 10 most recent groceries expenses",
            context: sharedContext(fixture: fixture, aiOptInEnabled: true)
        )

        guard case .handled(let answer, let aggregationResult, let homeQueryPlan, let trace) = result else {
            Issue.record("Expected model-first recent grocery list to execute: \(workspaceAggregationDebugSummary(result))")
            return
        }

        #expect(trace.selectedPath == .sharedFoundationModels)
        #expect(trace.selectedInterpreter == .foundationModels)
        #expect(trace.interpreterSelectionReason == .modelEligible)
        #expect(trace.modelAttempted == true)
        #expect(trace.heuristicAttempted == false)
        #expect(trace.heuristicUsedAsFallback == false)
        #expect(trace.fallbackReason == nil)
        #expect(homeQueryPlan == nil)
        #expect(answer.kind == .list)
        #expect(trace.semanticInterpretationSummary?.contains("operation=list") == true)
        #expect(trace.semanticResolverSummary?.contains("resolved=1") == true)
        #expect(trace.executorResultSummary?.contains("recentFilteredTransactions") == true)
        guard case .workspaceCard(let card) = aggregationResult else {
            Issue.record("Expected workspace-card result.")
            return
        }
        #expect(card.rows.allSatisfy { $0.label.lowercased().contains("groceries") })
    }

    @Test func coordinator_aiEligibleRecentCategoryListKeepsValidLowConfidenceModelOutput() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let model = SharedPipelineStubStructuredInterpreter(
            structuredIntent: .query(
                MarinaStructuredQueryIntent(
                    metricRaw: "categorySpendTotal",
                    targetName: "Groceries",
                    targetTypeRaw: "category",
                    dateStartISO8601: "2026-05-01",
                    dateEndISO8601: "2026-05-31",
                    comparisonDateStartISO8601: nil,
                    comparisonDateEndISO8601: nil,
                    resultLimit: nil,
                    periodUnitRaw: "month",
                    confidenceRaw: "low",
                    clarification: nil
                )
            )
        )

        let result = await coordinator(structuredInterpreter: model).run(
            prompt: "What did I spend on groceries this month?",
            context: sharedContext(fixture: fixture, aiOptInEnabled: true)
        )

        guard case .handled(_, _, let homeQueryPlan, let trace) = result else {
            Issue.record("Expected valid low-confidence model output to remain selected: \(workspaceAggregationDebugSummary(result))")
            return
        }

        #expect(trace.selectedPath == .sharedFoundationModels)
        #expect(trace.selectedInterpreter == .foundationModels)
        #expect(trace.modelAttempted == true)
        #expect(trace.heuristicAttempted == false)
        #expect(trace.heuristicUsedAsFallback == false)
        #expect(trace.fallbackReason == nil)
        #expect(homeQueryPlan?.metric == .categorySpendTotal)
    }

    @Test func coordinator_litterRobotBadModelMetricBlocksWithoutDatabaseBypassOrLegacyFallback() async throws {
        let fixture = try makeFixture()
        fixture.context.insert(VariableExpense(
            descriptionText: "Litter Robot",
            amount: 699,
            transactionDate: sharedPipelineDate(2025, 1, 14),
            workspace: fixture.workspace,
            card: fixture.appleCard,
            category: fixture.groceries
        ))
        try fixture.context.save()

        let model = SharedPipelineStubStructuredInterpreter(
            structuredIntent: .query(
                MarinaStructuredQueryIntent(
                    metricRaw: "card_purchase_date",
                    targetName: "Litter Robot",
                    targetTypeRaw: "entity",
                    dateStartISO8601: "2025-01-01",
                    dateEndISO8601: "2025-12-31",
                    comparisonDateStartISO8601: "2025-01-01",
                    comparisonDateEndISO8601: "2025-12-31",
                    resultLimit: 1,
                    periodUnitRaw: "month",
                    confidenceRaw: "high",
                    clarification: nil
                )
            )
        )

        let result = await coordinator(
            availability: SharedPipelineStubAvailability(status: .available),
            structuredInterpreter: model
        ).run(
            prompt: "When did I purchase Litter Robot?",
            context: sharedContext(fixture: fixture, aiOptInEnabled: true)
        )

        guard case .handled(let answer, let aggregationResult, let homeQueryPlan, let trace) = result else {
            Issue.record("Expected Litter Robot lookupDetails shape to use the shared database lookup path.")
            return
        }

        #expect(trace.selectedPath == .sharedFoundationModels || trace.selectedPath == .sharedHeuristic)
        #expect(trace.selectedPath != .sharedAttemptedThenLegacyFallback)
        #expect(trace.compactSummary.contains("family=databaseLookup"))
        #expect(trace.executorResultSummary?.contains("requestFamily=databaseLookup") == true)
        #expect(homeQueryPlan == nil)
        #expect(answer.kind == .message)
        switch aggregationResult {
        case .message, .noData:
            break
        default:
            Issue.record("Expected typed lookup message or no-data result.")
            return
        }
    }

    @Test func coordinator_workspaceAggregationPromptsUseSharedHeuristicWithoutLegacyFallback() async throws {
        let fixture = try makeFixture()
        fixture.context.insert(Income(source: "Salary", amount: 2_500, date: sharedPipelineDate(2026, 5, 5), isPlanned: false, workspace: fixture.workspace))
        fixture.context.insert(Income(source: "Side Gig", amount: 700, date: sharedPipelineDate(2026, 5, 12), isPlanned: false, workspace: fixture.workspace))
        fixture.context.insert(PlannedExpense(title: "Rent", plannedAmount: 1_500, expenseDate: sharedPipelineDate(2026, 5, 20), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries))
        fixture.context.insert(SavingsLedgerEntry(date: sharedPipelineDate(2026, 5, 3), amount: 400, note: "Period close", kindRaw: SavingsLedgerEntryKind.periodClose.rawValue, workspace: fixture.workspace))
        let shared = AllocationAccount(name: "Roommate", workspace: fixture.workspace)
        fixture.context.insert(shared)
        fixture.context.insert(ExpenseAllocation(allocatedAmount: 225, workspace: fixture.workspace, account: shared))
        try fixture.context.save()

        let prompts = [
            "What paid me the most this month?",
            "What are my biggest upcoming bills?",
            "Largest savings movements this month.",
            "Show shared balances."
        ]

        for prompt in prompts {
            let result = await coordinator().run(
                prompt: prompt,
                context: sharedContext(fixture: fixture, aiOptInEnabled: false)
            )

            guard case .handled(let answer, let aggregationResult, let homeQueryPlan, let trace) = result else {
                Issue.record("Expected workspace aggregation prompt to be handled: \(prompt), actual=\(workspaceAggregationDebugSummary(result))")
                continue
            }
            #expect(homeQueryPlan == nil)
            #expect(trace.selectedPath == .sharedHeuristic)
            #expect(trace.executorResultSummary?.contains("workspaceAggregation=") == true)
            #expect(answer.kind == .list)
            guard case .workspaceCard = aggregationResult else {
                Issue.record("Expected workspace card result for \(prompt)")
                continue
            }
        }
    }

    @Test func coordinator_lowConfidenceModelDoesNotTriggerHeuristicFallbackByItself() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let model = SharedPipelineStubStructuredInterpreter(
            structuredIntent: .query(
                MarinaStructuredQueryIntent(
                    metricRaw: "cardSpendTotal",
                    targetName: "Apple Card",
                    targetTypeRaw: "card",
                    dateStartISO8601: "2026-05-01",
                    dateEndISO8601: "2026-05-31",
                    comparisonDateStartISO8601: nil,
                    comparisonDateEndISO8601: nil,
                    resultLimit: nil,
                    periodUnitRaw: "month",
                    confidenceRaw: "low",
                    clarification: nil
                )
            )
        )

        let result = await coordinator(structuredInterpreter: model).run(
            prompt: "total spend on my Apple Card",
            context: sharedContext(fixture: fixture, aiOptInEnabled: true)
        )

        guard case .handled(_, _, let homeQueryPlan, let trace) = result else {
            Issue.record("Low-confidence valid model candidate should remain model-selected.")
            return
        }
        #expect(trace.selectedPath == .sharedFoundationModels)
        #expect(trace.selectedInterpreter == .foundationModels)
        #expect(trace.modelAttempted == true)
        #expect(trace.heuristicAttempted == false)
        #expect(trace.heuristicUsedAsFallback == false)
        #expect(trace.fallbackReason == nil)
        #expect(homeQueryPlan?.metric == .cardSpendTotal)
    }

    @Test func coordinator_aiAvailableModelDroppingExplicitConstraintUsesExactHeuristicFallback() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let model = SharedPipelineStubStructuredInterpreter(
            structuredIntent: .query(
                MarinaStructuredQueryIntent(
                    metricRaw: "spendTotal",
                    targetName: nil,
                    targetTypeRaw: nil,
                    dateStartISO8601: "2026-05-01",
                    dateEndISO8601: "2026-05-31",
                    comparisonDateStartISO8601: nil,
                    comparisonDateEndISO8601: nil,
                    resultLimit: nil,
                    periodUnitRaw: "month",
                    confidenceRaw: "high",
                    clarification: nil
                )
            )
        )

        let result = await coordinator(structuredInterpreter: model).run(
            prompt: "total spend on my Apple Card",
            context: sharedContext(fixture: fixture, aiOptInEnabled: true)
        )

        guard case .handled(_, _, let homeQueryPlan, let trace) = result else {
            Issue.record("Expected dropped card constraint to use exact heuristic fallback.")
            return
        }
        #expect(trace.selectedPath == .sharedHeuristic)
        #expect(trace.selectedInterpreter == .heuristic)
        #expect(trace.interpreterSelectionReason == .modelUnsupportedHeuristicExactMatch)
        #expect(trace.modelAttempted == true)
        #expect(trace.heuristicAttempted == true)
        #expect(trace.heuristicUsedAsFallback == true)
        #expect(trace.fallbackReason == .modelUnsupportedHeuristicExactMatch)
        #expect(homeQueryPlan?.metric == .cardSpendTotal)
    }

    @Test func coordinator_semanticCommandBeatsWrongExecutableMetricForRecentCategoryList() async throws {
        let fixture = try makeFixture()
        let cannabis = Offshore.Category(name: "Cannabis", hexColor: "#225522", workspace: fixture.workspace)
        fixture.context.insert(cannabis)
        fixture.context.insert(VariableExpense(descriptionText: "Cannabis Purchase 1", amount: 40, transactionDate: sharedPipelineDate(2026, 5, 9), workspace: fixture.workspace, card: fixture.appleCard, category: cannabis))
        fixture.context.insert(VariableExpense(descriptionText: "Cannabis Purchase 2", amount: 50, transactionDate: sharedPipelineDate(2026, 5, 10), workspace: fixture.workspace, card: fixture.appleCard, category: cannabis))
        try fixture.context.save()

        let semanticCommand = MarinaSemanticCommand(
            family: .analytics,
            action: .listRows,
            datasets: [.variableExpenses, .plannedExpenses],
            measure: nil,
            includeFilters: [
                MarinaSemanticCommandFilter(rawText: "Cannabis", allowedTypes: [.category, .merchant, .expense])
            ],
            excludeFilters: [],
            grouping: .transaction,
            sort: .newest,
            dateRange: nil,
            comparisonDateRange: nil,
            periodUnit: nil,
            limit: 5,
            requestedDetail: nil
        )
        let model = SharedPipelineStubStructuredInterpreter(structuredIntent: .semanticCommand(semanticCommand))

        let result = await coordinator(structuredInterpreter: model).run(
            prompt: "List my last 5 Cannabis purchases",
            context: sharedContext(fixture: fixture, aiOptInEnabled: true)
        )

        guard case .handled(let answer, let aggregationResult, let homeQueryPlan, let trace) = result else {
            Issue.record("Expected semantic command to produce a filtered recent list: \(workspaceAggregationDebugSummary(result))")
            return
        }

        #expect(trace.selectedPath == .sharedFoundationModels)
        #expect(homeQueryPlan == nil)
        #expect(trace.candidateSummary?.contains("semantic=listRows") == true)
        #expect(trace.executorResultSummary?.contains("recentFilteredTransactions") == true)
        #expect(answer.title.contains("Recent Purchases"))
        guard case .workspaceCard(let card) = aggregationResult else {
            Issue.record("Expected workspace card")
            return
        }
        #expect(card.rows.map(\.label) == ["Cannabis Purchase 2", "Cannabis Purchase 1"])
    }

    @Test func coordinator_modelDroppingExplicitConstraintUsesHeuristicWhenHeuristicPreservesIt() async throws {
        let fixture = try makeFixture()
        fixture.context.insert(VariableExpense(descriptionText: "Groceries Purchase 1", amount: 40, transactionDate: sharedPipelineDate(2026, 5, 9), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries))
        fixture.context.insert(VariableExpense(descriptionText: "Groceries Purchase 2", amount: 50, transactionDate: sharedPipelineDate(2026, 5, 10), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries))
        try fixture.context.save()

        let model = SharedPipelineStubStructuredInterpreter(
            structuredIntent: .query(
                MarinaStructuredQueryIntent(
                    metricRaw: "topCategories",
                    targetName: nil,
                    targetTypeRaw: nil,
                    dateStartISO8601: "2026-05-01",
                    dateEndISO8601: "2026-05-31",
                    comparisonDateStartISO8601: nil,
                    comparisonDateEndISO8601: nil,
                    resultLimit: nil,
                    periodUnitRaw: "month",
                    confidenceRaw: "low",
                    clarification: nil
                )
            )
        )

        let result = await coordinator(structuredInterpreter: model).run(
            prompt: "Most recent expenses in Groceries category",
            context: sharedContext(fixture: fixture, aiOptInEnabled: true)
        )

        guard case .handled(let answer, let aggregationResult, let homeQueryPlan, let trace) = result else {
            Issue.record("Expected heuristic to preserve explicit category constraint: \(workspaceAggregationDebugSummary(result))")
            return
        }

        #expect(trace.selectedPath == .sharedHeuristic)
        #expect(trace.selectedInterpreter == .heuristic)
        #expect(trace.interpreterSelectionReason == .modelUnsupportedHeuristicExactMatch)
        #expect(trace.modelAttempted == true)
        #expect(trace.heuristicAttempted == true)
        #expect(trace.heuristicUsedAsFallback == true)
        #expect(trace.fallbackReason == .modelUnsupportedHeuristicExactMatch)
        #expect(homeQueryPlan == nil)
        #expect(answer.kind == .list)
        #expect(trace.executorResultSummary?.contains("recentFilteredTransactions") == true)
        guard case .workspaceCard(let card) = aggregationResult else {
            Issue.record("Expected preserved category list result.")
            return
        }
        #expect(card.rows.allSatisfy { $0.label.localizedCaseInsensitiveContains("Groceries") })
    }

    @Test func coordinator_constraintGuardBlocksBroaderExecutableInterpretation() async throws {
        let broadCandidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: "List 10 most recent groceries expenses",
            operation: .listRows,
            measure: .transactionAmount,
            grouping: MarinaGroupingCandidate(dimension: .transaction),
            ranking: MarinaRankingCandidate(direction: .newest, limit: 10),
            limit: 10,
            responseShapeHint: .rankedList,
            confidence: .high
        )
        let broadPlan = MarinaAggregationPlan(
            status: .notExecutableShell,
            operation: .listRows,
            measure: .transactionAmount,
            targets: [],
            dateRange: nil,
            comparisonDateRange: nil,
            grouping: MarinaGroupingCandidate(dimension: .transaction),
            ranking: MarinaRankingCandidate(direction: .newest, limit: 10),
            limit: 10,
            responseShape: .rankedList
        )
        let constraints = MarinaExplicitPromptConstraints(
            categories: ["groceries"],
            cards: [],
            hasDateConstraint: false,
            limit: 10,
            sort: .newest
        )

        let unsupported = constraints.unsupportedIfDropped(
            by: broadCandidate,
            resolvedQuery: nil,
            outcome: .executable(broadPlan)
        )

        #expect(unsupported?.kind == .unsupportedCombination)
        #expect(unsupported?.message.contains("category") == true)
    }

    @Test func coordinator_constraintGuardAllowsAppSurfaceDefaultDatePolicy() async throws {
        let candidate = MarinaQueryPlanCandidate(
            source: .heuristic,
            rawPrompt: "What is my actual savings so far this period?",
            operation: .lookupDetails,
            measure: .savings,
            responseShapeHint: .summaryCard,
            confidence: .high
        )
        let plan = MarinaAggregationPlan(
            status: .notExecutableShell,
            operation: .lookupDetails,
            measure: .savings,
            targets: [],
            dateRange: nil,
            comparisonDateRange: nil,
            grouping: nil,
            ranking: nil,
            limit: nil,
            responseShape: .summaryCard
        )
        let constraints = MarinaExplicitPromptConstraints(
            categories: [],
            cards: [],
            hasDateConstraint: true,
            limit: nil,
            sort: nil
        )

        let unsupported = constraints.unsupportedIfDropped(
            by: candidate,
            resolvedQuery: nil,
            outcome: .executable(plan)
        )

        #expect(unsupported == nil)
    }

    @Test func coordinator_composableWorkspacePromptsUseSharedHeuristicWithoutLegacyFallback() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let cannabis = Offshore.Category(name: "Cannabis", hexColor: "#225522", workspace: fixture.workspace)
        let roommate = AllocationAccount(name: "Roommate", workspace: fixture.workspace)
        let allocated = VariableExpense(descriptionText: "Dinner", amount: 120, transactionDate: sharedPipelineDate(2026, 5, 5), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries)
        fixture.context.insert(cannabis)
        fixture.context.insert(roommate)
        fixture.context.insert(allocated)
        fixture.context.insert(ExpenseAllocation(allocatedAmount: 60, workspace: fixture.workspace, account: roommate, expense: allocated))
        fixture.context.insert(VariableExpense(descriptionText: "Cannabis Purchase 1", amount: 40, transactionDate: sharedPipelineDate(2026, 5, 9), workspace: fixture.workspace, card: fixture.appleCard, category: cannabis))
        fixture.context.insert(VariableExpense(descriptionText: "Cannabis Purchase 2", amount: 50, transactionDate: sharedPipelineDate(2026, 5, 10), workspace: fixture.workspace, card: fixture.appleCard, category: cannabis))
        fixture.context.insert(VariableExpense(descriptionText: "April Groceries", amount: 75, transactionDate: sharedPipelineDate(2026, 4, 8), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries))
        let budget = Budget(name: "May", startDate: sharedPipelineDate(2026, 5, 1), endDate: sharedPipelineDate(2026, 5, 31), workspace: fixture.workspace)
        fixture.context.insert(budget)
        fixture.context.insert(BudgetCategoryLimit(maxAmount: 700, budget: budget, category: fixture.groceries))
        fixture.context.insert(Income(source: "Planned", amount: 2_000, date: sharedPipelineDate(2026, 5, 1), isPlanned: true, workspace: fixture.workspace))
        try fixture.context.save()

        let prompts = [
            "Which card is eating the most of my budget?",
            "What did I spend on Apple Card outside of Groceries?",
            "List my last 5 Cannabis purchases",
            "What was my average weekly Groceries spending over the last 3 months?",
            "Which expenses made this month higher than last month?",
            "How much did Roommate spend on Groceries?",
            "If I spend $50 on Groceries, how will that affect my budget?"
        ]

        for prompt in prompts {
            let result = await coordinator().run(
                prompt: prompt,
                context: sharedContext(fixture: fixture, aiOptInEnabled: false)
            )

            guard case .handled(let answer, let aggregationResult, let homeQueryPlan, let trace) = result else {
                Issue.record("Expected composable workspace prompt to be handled: \(prompt), actual=\(workspaceAggregationDebugSummary(result))")
                continue
            }
            #expect(homeQueryPlan == nil)
            #expect(trace.selectedPath == .sharedHeuristic)
            #expect(trace.executorResultSummary?.contains("composableWorkspace=") == true)
            #expect(answer.kind == .list)
            guard case .workspaceCard = aggregationResult else {
                Issue.record("Expected workspace card result for \(prompt)")
                continue
            }
        }
    }

    @Test func coordinator_invalidSharedResultFallsBackToLegacyWithReason() async throws {
        let fixture = try makeFixture()
        let result = await coordinator().run(
            prompt: "total spend on my Missing Card",
            context: sharedContext(fixture: fixture)
        )

        guard case .validationBlocked(let answer, let outcome, let trace) = result else {
            Issue.record("Unknown target should be blocked by typed shared clarification.")
            return
        }
        #expect(answer.kind == .message)
        guard case .clarification(let clarification) = outcome else {
            Issue.record("Expected typed clarification.")
            return
        }
        #expect(clarification.kind == .missingTarget)
        #expect(trace.selectedPath == .sharedHeuristic)
        #expect(trace.fallbackReason == nil)
        #expect(trace.validatorOutcomeSummary?.contains("clarification") == true)
    }

    private func coordinator(
        availability: MarinaModelAvailabilityProviding = SharedPipelineStubAvailability(status: .available),
        structuredInterpreter: MarinaStructuredIntentInterpreting = SharedPipelineStubStructuredInterpreter(structuredIntent: .unresolved)
    ) -> MarinaSharedPipelineCoordinator {
        MarinaSharedPipelineCoordinator(
            availability: availability,
            structuredInterpreter: structuredInterpreter
        )
    }

    private func emptyResolved(_ candidate: MarinaQueryPlanCandidate) -> MarinaResolvedQueryCandidate {
        MarinaResolvedQueryCandidate(
            candidate: candidate,
            resolvedTargets: [],
            unresolvedMentions: [],
            ambiguousMentions: [],
            primaryDateRange: nil,
            comparisonDateRange: nil
        )
    }

    private func recentGroceriesListCommand(limit: Int) -> MarinaSemanticCommand {
        MarinaSemanticCommand(
            family: .analytics,
            action: .listRows,
            datasets: [.variableExpenses, .plannedExpenses],
            measure: nil,
            includeFilters: [
                MarinaSemanticCommandFilter(rawText: "Groceries", allowedTypes: [.category])
            ],
            excludeFilters: [],
            grouping: .transaction,
            sort: .newest,
            dateRange: nil,
            comparisonDateRange: nil,
            periodUnit: nil,
            limit: limit,
            requestedDetail: nil
        )
    }

    private func workspaceAggregationDebugSummary(_ result: MarinaSharedPipelineRuntimeResult) -> String {
        switch result {
        case .handled(let answer, _, let plan, let trace):
            return "handled title=\(answer.title) plan=\(plan?.metric.rawValue ?? "nil") trace=\(trace.compactSummary)"
        case .validationBlocked(let answer, let outcome, let trace):
            return "validationBlocked title=\(answer.title) outcome=\(outcome) trace=\(trace.compactSummary)"
        case .fallbackToLegacy(let trace):
            return "fallback trace=\(trace.compactSummary)"
        }
    }
}

private final class SharedPipelineCapturingStructuredInterpreter: MarinaStructuredIntentInterpreting {
    let structuredIntent: MarinaStructuredIntent
    private(set) var observedPriorContext: MarinaPriorQueryContext?

    init(structuredIntent: MarinaStructuredIntent) {
        self.structuredIntent = structuredIntent
    }

    func interpret(
        prompt: String,
        context: MarinaLanguageRouterContext
    ) async throws -> MarinaStructuredIntent {
        observedPriorContext = context.priorQueryContext
        return structuredIntent
    }
}
