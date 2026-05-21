import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct HomeAssistantPresetPromptCatalogTests {
    @Test func catalog_coversAllBuiltInPresetPromptGroupsAndDefaultSuggestions() {
        let prompts = HomeAssistantPresetPromptCatalog.prompts(defaultPeriodUnit: .month)
        let groups = Set(prompts.compactMap(\.group))

        #expect(groups == Set(HomeAssistantPresetPromptGroup.allCases))
        #expect(prompts.count >= 30)

        let intents = Set(prompts.map(\.query.intent))
        let requiredIntents: Set<HomeQueryIntent> = [
            .periodOverview,
            .spendThisMonth,
            .topCategoriesThisMonth,
            .compareThisMonthToPreviousMonth,
            .savingsStatus,
            .incomeAverageActual,
            .incomeSourceShare,
            .incomeSourceShareTrend,
            .savingsAverageRecentPeriods,
            .cardSpendTotal,
            .cardVariableSpendingHabits,
            .largestRecentTransactions,
            .presetDueSoon,
            .presetHighestCost,
            .presetTopCategory,
            .presetCategorySpend,
            .categorySpendShare,
            .categoryPotentialSavings,
            .categoryReallocationGuidance,
            .categorySpendShareTrend,
            .safeSpendToday,
            .nextPlannedExpense,
            .topMerchantsThisMonth
        ]

        for intent in requiredIntents {
            #expect(intents.contains(intent), "Missing preset prompt intent \(intent.rawValue)")
        }
    }

    @Test func catalogedPresetPrompts_executeStoredQueriesThroughTypedRuntime() async throws {
        let fixture = try makeFixture()
        try seedPresetPromptData(fixture)
        let coordinator = MarinaTurnCoordinator()
        let context = turnContext(fixture)
        let prompts = HomeAssistantPresetPromptCatalog.prompts(defaultPeriodUnit: .month)

        for preset in prompts {
            let result = await coordinator.run(
                query: preset.query,
                sourceTitle: preset.title,
                context: context
            )

            guard case .handled(let answer, let aggregationResult, let homeQueryPlan, _, _) = result else {
                Issue.record("Preset prompt should execute cleanly: \(preset.title)")
                continue
            }

            #expect(homeQueryPlan?.metric == preset.expectedMetric, "Wrong metric for \(preset.title)")
            #expect(homeQueryPlan?.query.intent == preset.query.intent, "Wrong intent for \(preset.title)")
            #expect(answer.title.isEmpty == false, "Missing title for \(preset.title)")
            #expect(answer.title.localizedCaseInsensitiveContains("Unsupported") == false, "Unsupported answer for \(preset.title)")
            #expect(aggregationResult != nil)
            if let expectedKind = preset.expectedAnswerKind,
               answer.primaryValue != nil || answer.rows.isEmpty == false {
                #expect(answer.kind == expectedKind, "Unexpected answer kind for \(preset.title)")
            }
        }
    }

    @Test func typedPresetPrompt_usesStoredQueryWhenVisibleTitleIsAmbiguous() async throws {
        let fixture = try makeFixture()
        try fixture.seedIncomeData()
        let result = await MarinaTurnCoordinator().run(
            query: HomeQuery(intent: .incomeAverageActual),
            sourceTitle: "What is my actual income this year?",
            context: turnContext(fixture)
        )

        guard case .handled(let answer, _, let homeQueryPlan, _, _) = result else {
            Issue.record("Expected stored income-average query to execute.")
            return
        }

        #expect(homeQueryPlan?.metric == .incomeAverageActual)
        #expect(homeQueryPlan?.query.intent == .incomeAverageActual)
        #expect(answer.title.localizedCaseInsensitiveContains("Average Actual Income"))
        #expect(answer.primaryValue == "$2,200.00")
    }

    @Test func catalogTitles_parseToTheirStoredIntentForManualPrompts() {
        let parser = makeParser()
        let prompts = HomeAssistantPresetPromptCatalog.prompts(defaultPeriodUnit: .month)

        for preset in prompts {
            let parsed = parser.parse(preset.title)
            #expect(parsed?.intent == preset.query.intent, "Manual prompt should match catalog intent for \(preset.title)")
            let defaultLimit = HomeQuery(intent: preset.query.intent).resultLimit
            if preset.query.resultLimit != defaultLimit {
                #expect(parsed?.resultLimit == preset.query.resultLimit, "Manual prompt should preserve limit for \(preset.title)")
            }
            if let expectedPeriodUnit = preset.query.periodUnit {
                #expect(parsed?.periodUnit == expectedPeriodUnit, "Manual prompt should preserve period unit for \(preset.title)")
            }
        }
    }

    @Test func liveDomainMapper_averageActualIncomeWinsBeforeActualIncomeTotal() {
        let mapper = MarinaLiveDomainIntentMapper(nowProvider: { foundationPipelineDate(2026, 5, 15) })
        let context = routerContext()
        let mapped = mapper.map(
            payload: payload(route: "readQuery", intent: "incomeActual", target: "income"),
            prompt: "Average actual income this year",
            context: context
        )

        let command = command(mapped)
        #expect(mapped.canonicalRouteSummary == "income.averageActual")
        #expect(command?.action == .average)
        #expect(command?.measure == .income)
        #expect(command?.incomeStatusScope == .actual)
    }

    @Test func titleResolver_addsContextualHeaderForPresetFamilies() {
        let resolver = MarinaAnswerTitleResolver()
        let answer = HomeAnswer(
            queryID: UUID(),
            kind: .metric,
            title: "Average Actual Income",
            primaryValue: "$2,200.00"
        )

        let titled = resolver.applyingTitle(
            to: answer,
            query: HomeQuery(intent: .incomeAverageActual),
            userPrompt: "Average actual income this year",
            now: foundationPipelineDate(2026, 5, 15)
        )

        #expect(titled.title == "Average Actual Income This Year")
    }

    @Test func followUps_areContextAwareAndDoNotRepeatCurrentQuery() {
        let builder = HomeAssistantFollowUpSuggestionBuilder()
        let answer = HomeAnswer(
            queryID: UUID(),
            kind: .metric,
            title: "Average Actual Income This Year",
            primaryValue: "$2,200.00"
        )
        let query = HomeQuery(intent: .incomeAverageActual, periodUnit: .year)

        let suggestions = builder.suggestions(
            after: answer,
            executedQuery: query
        )

        #expect(suggestions.isEmpty == false)
        #expect(suggestions.contains { $0.query.intent == .incomeAverageActual } == false)
        #expect(suggestions.contains { $0.query.intent == .incomeSourceShare })
    }

    private func turnContext(_ fixture: MarinaPhase5Fixture) -> MarinaTurnContext {
        MarinaTurnContext(
            provider: fixture.provider,
            routerContext: MarinaInterpretationContext(
                workspaceName: fixture.workspace.name,
                defaultPeriodUnit: .month,
                sessionContext: HomeAssistantSessionContext(),
                priorQueryContext: .empty,
                cardNames: ["Apple Card", "Backup Card"],
                categoryNames: ["Groceries", "Travel"],
                incomeSourceNames: ["Salary"],
                presetTitles: ["Rent", "Gym"],
                budgetNames: ["May"],
                aliasSummaries: [],
                now: foundationPipelineDate(2026, 5, 15)
            ),
            defaultPeriodUnit: .month,
            aiEnabled: false,
            now: foundationPipelineDate(2026, 5, 15)
        )
    }

    private func seedPresetPromptData(_ fixture: MarinaPhase5Fixture) throws {
        try fixture.seedSpendData()
        try fixture.seedIncomeData()

        let budget = Budget(
            name: "May",
            startDate: foundationPipelineDate(2026, 5, 1),
            endDate: foundationPipelineDate(2026, 5, 31),
            workspace: fixture.workspace
        )
        let rent = Preset(
            title: "Rent",
            plannedAmount: 1_400,
            workspace: fixture.workspace,
            defaultCard: fixture.appleCard,
            defaultCategory: fixture.groceries
        )
        let gym = Preset(
            title: "Gym",
            plannedAmount: 80,
            workspace: fixture.workspace,
            defaultCard: fixture.backupCard,
            defaultCategory: fixture.travel
        )
        let savings = SavingsAccount(name: "Main Savings", total: 250, workspace: fixture.workspace)
        fixture.context.insert(budget)
        fixture.context.insert(rent)
        fixture.context.insert(gym)
        fixture.context.insert(BudgetPresetLink(budget: budget, preset: rent))
        fixture.context.insert(BudgetPresetLink(budget: budget, preset: gym))
        fixture.context.insert(SavingsLedgerEntry(
            date: foundationPipelineDate(2026, 5, 2),
            amount: 100,
            note: "Manual save",
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
            workspace: fixture.workspace,
            account: savings
        ))
        fixture.context.insert(savings)
        fixture.context.insert(VariableExpense(
            descriptionText: "Apple Store",
            amount: 129,
            transactionDate: foundationPipelineDate(2026, 5, 6),
            workspace: fixture.workspace,
            card: fixture.appleCard,
            category: fixture.travel
        ))
        try fixture.context.save()
    }

    private func routerContext() -> MarinaInterpretationContext {
        MarinaInterpretationContext(
            workspaceName: "Phase 5 Workspace",
            defaultPeriodUnit: .month,
            sessionContext: HomeAssistantSessionContext(),
            priorQueryContext: .empty,
            cardNames: ["Apple Card"],
            categoryNames: ["Groceries"],
            incomeSourceNames: ["Salary"],
            presetTitles: ["Rent"],
            budgetNames: ["May"],
            aliasSummaries: [],
            now: foundationPipelineDate(2026, 5, 15)
        )
    }

    private func payload(
        route: String,
        intent: String?,
        target: String?
    ) -> MarinaFoundationIntentEnvelopePayload {
        MarinaFoundationIntentEnvelopePayload(
            routeRaw: route,
            intentRaw: intent,
            targetText: target,
            secondaryTargetText: nil,
            relationshipText: nil,
            dateText: nil,
            comparisonDateText: nil,
            amountText: nil,
            valueDirectionRaw: nil,
            confidenceRaw: "high",
            unsupportedReasonRaw: nil
        )
    }

    private func makeParser() -> HomeAssistantTextParser {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4

        return HomeAssistantTextParser(
            calendar: calendar,
            nowProvider: { foundationPipelineDate(2026, 5, 15) }
        )
    }

    private func command(_ mapping: MarinaLiveDomainIntentMapping) -> MarinaSemanticCommand? {
        guard case .semanticCommand(let command) = mapping.intent.structuredIntent else { return nil }
        return command
    }
}
