//
//  HomeAssistantResolutionPipelineTests.swift
//  OffshoreBudgetingTests
//
//  Created by OpenAI Codex on 4/16/26.
//

import Foundation
import Testing
@testable import Offshore

struct HomeAssistantResolutionPipelineTests {

    @Test func resolver_aliasSupportsMerchantAndBudget() throws {
        let resolver = HomeAssistantEntityResolver()
        let rules = [
            AssistantAliasRule(aliasKey: "starbs", targetValue: "Starbucks", entityType: .merchant),
            AssistantAliasRule(aliasKey: "trip fund", targetValue: "Travel Budget", entityType: .budget)
        ]

        let merchantResolution = resolver.resolve(
            input: HomeAssistantEntityResolutionInput(
                prompt: "show starbs spending",
                targetPhrase: "starbs",
                categories: [],
                cards: [],
                merchants: ["Starbucks"],
                presets: [],
                budgets: [],
                incomeSources: [],
                aliasRules: rules,
                rejectedCandidateNames: []
            )
        )

        #expect(merchantResolution.bestMatch?.name == "Starbucks")
        #expect(merchantResolution.bestMatch?.entityType == .merchant)
        #expect(merchantResolution.bestMatch?.source == .alias)

        let budgetResolution = resolver.resolve(
            input: HomeAssistantEntityResolutionInput(
                prompt: "trip fund",
                targetPhrase: "trip fund",
                categories: [],
                cards: [],
                merchants: [],
                presets: [],
                budgets: ["Travel Budget"],
                incomeSources: [],
                aliasRules: rules,
                rejectedCandidateNames: []
            )
        )

        #expect(budgetResolution.bestMatch?.name == "Travel Budget")
        #expect(budgetResolution.bestMatch?.entityType == .budget)
        #expect(budgetResolution.bestMatch?.source == .alias)
    }

    @Test func resolver_tieBandAmbiguity_blocksExecution() throws {
        let resolver = HomeAssistantEntityResolver()
        let resolution = resolver.resolve(
            input: HomeAssistantEntityResolutionInput(
                prompt: "travel",
                targetPhrase: "travel",
                categories: ["Travel"],
                cards: ["Travel"],
                merchants: [],
                presets: [],
                budgets: [],
                incomeSources: [],
                aliasRules: [],
                rejectedCandidateNames: []
            )
        )

        #expect(resolution.isTieAmbiguity == true)
        #expect(resolution.bestMatch == nil)
        #expect(resolution.confidence == .medium)
        #expect(resolution.ambiguityCandidates.count == 2)
    }

    @Test func reconciler_categoryOverridesMerchantMetricDeterministically() throws {
        let reconciler = HomeAssistantPlanReconciler()
        let plan = HomeQueryPlan(
            metric: .merchantSpendTotal,
            dateRange: monthRange(2026, 4),
            resultLimit: nil,
            confidenceBand: .high,
            targetName: "Food & Drink",
            targetTypeRaw: MarinaStructuredTargetType.merchant.rawValue,
            periodUnit: .month
        )
        let resolution = HomeAssistantEntityResolution(
            resolvedPhrase: "Food & Drink",
            bestMatch: HomeAssistantEntityMatch(
                name: "Food & Drink",
                entityType: .category,
                confidence: .high,
                source: .exact,
                score: 1
            ),
            rankedCandidates: [
                HomeAssistantEntityMatch(
                    name: "Food & Drink",
                    entityType: .category,
                    confidence: .high,
                    source: .exact,
                    score: 1
                )
            ],
            confidence: .high
        )

        let reconciled = reconciler.reconcile(plan: plan, resolution: resolution)

        #expect(reconciled.plan.metric == .categorySpendTotal)
        #expect(reconciled.plan.targetTypeRaw == HomeAssistantResolvedEntityType.category.rawValue)
        #expect(reconciled.didOverrideMetric == true)
        #expect(reconciled.explanation == "No merchant found, using category instead")
    }

    @Test func resolver_rejectedCandidatesAreNotRepeated() throws {
        let resolver = HomeAssistantEntityResolver()
        let resolution = resolver.resolve(
            input: HomeAssistantEntityResolutionInput(
                prompt: "chase",
                targetPhrase: "chase",
                categories: [],
                cards: ["Chase Freedom", "Chase Sapphire"],
                merchants: [],
                presets: [],
                budgets: [],
                incomeSources: [],
                aliasRules: [],
                rejectedCandidateNames: ["Chase Freedom"]
            )
        )

        #expect(resolution.rankedCandidates.contains(where: { $0.name == "Chase Freedom" }) == false)
        #expect(resolution.rankedCandidates.contains(where: { $0.name == "Chase Sapphire" }) == true)
    }

    @Test func resolver_highConfidenceUsesConfiguredMarginThreshold() throws {
        #expect(HomeAssistantEntityResolver.highConfidenceMarginThreshold == 0.18)
    }

    @Test func reconciler_aliasAndFuzzyMatchesExplainResolution() throws {
        let reconciler = HomeAssistantPlanReconciler()
        let plan = HomeQueryPlan(
            metric: .merchantSpendTotal,
            dateRange: monthRange(2026, 4),
            resultLimit: nil,
            confidenceBand: .high,
            targetName: "starbs",
            targetTypeRaw: MarinaStructuredTargetType.merchant.rawValue,
            periodUnit: .month
        )

        let aliasResolution = HomeAssistantEntityResolution(
            resolvedPhrase: "starbs",
            bestMatch: HomeAssistantEntityMatch(
                name: "Starbucks",
                entityType: .merchant,
                confidence: .high,
                source: .alias,
                score: 0.95
            ),
            rankedCandidates: [],
            confidence: .high
        )
        let fuzzyResolution = HomeAssistantEntityResolution(
            resolvedPhrase: "starbcks",
            bestMatch: HomeAssistantEntityMatch(
                name: "Starbucks",
                entityType: .merchant,
                confidence: .medium,
                source: .fuzzy,
                score: 0.83
            ),
            rankedCandidates: [],
            confidence: .medium
        )

        #expect(reconciler.reconcile(plan: plan, resolution: aliasResolution).explanation == "Using merchant Starbucks")
        #expect(reconciler.reconcile(plan: plan, resolution: fuzzyResolution).explanation == "Using merchant Starbucks")
    }

    @Test func personaFollowUpsUseExecutedQueryWhenProvided() throws {
        let formatter = HomeAssistantPersonaFormatter(variantIndexPicker: { _, _ in 0 })
        let answer = HomeAnswer(
            queryID: UUID(),
            kind: .metric,
            title: "Merchant Spend",
            subtitle: nil,
            primaryValue: "$120",
            rows: []
        )
        let executedQuery = HomeQuery(
            intent: .categorySpendTotal,
            dateRange: monthRange(2026, 4),
            targetName: "Food & Drink"
        )

        let followUps = formatter.followUpSuggestions(
            after: answer,
            executedQuery: executedQuery,
            personaID: .marina
        )

        #expect(followUps.first?.query.intent == .compareCategoryThisMonthToPreviousMonth)
        #expect(followUps.first?.query.targetName == "Food & Drink")
    }

    private func monthRange(_ year: Int, _ month: Int) -> HomeQueryDateRange {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start)!
        return HomeQueryDateRange(startDate: start, endDate: end)
    }
}
