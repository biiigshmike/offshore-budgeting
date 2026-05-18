import Foundation
import Testing
@testable import Offshore

struct MarinaHeuristicInterpreterTests {
    @Test func databaseLookup_whenDidIPurchase_extractsSearchTextAndDateDetail() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "When did I purchase Litter Robot?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.requestFamily == .databaseLookup)
        #expect(candidate.databaseLookupRequest?.objectTypes == [.variableExpense, .plannedExpense])
        #expect(candidate.databaseLookupRequest?.searchText == "Litter Robot")
        #expect(candidate.databaseLookupRequest?.requestedDetail == .date)
    }

    @Test func databaseLookup_commonDetailPrompts_extractObjectTypesAndDetails() {
        let cases: [(String, String, [MarinaLookupObjectType], MarinaDatabaseLookupRequest.RequestedDetail)] = [
            ("How much was Litter Robot?", "Litter Robot", [.variableExpense, .plannedExpense], .amount),
            ("What card did I use for Litter Robot?", "Litter Robot", [.variableExpense, .plannedExpense], .card),
            ("Find my Litter Robot expense.", "Litter Robot", [.variableExpense, .plannedExpense], .general),
            ("Show me the Litter Robot transaction.", "Litter Robot", [.variableExpense, .plannedExpense], .general),
            ("Show me my March budget.", "March", [.budget], .general),
            ("Find my Apple Card.", "Apple Card", [.card], .general),
            ("Tell me about Food & Drink category.", "Food & Drink", [.category], .general),
            ("Find my paycheck income.", "paycheck", [.income], .general),
            ("Show my rent preset.", "rent", [.preset], .general),
            ("Find my savings account.", "savings account", [.savingsAccount], .general),
            ("Show my reconciliation account.", "reconciliation account", [.reconciliationAccount, .reconciliationItem], .general)
        ]

        for testCase in cases {
            let candidate = MarinaHeuristicInterpreter().interpret(
                prompt: testCase.0,
                defaultPeriodUnit: .month
            )
            #expect(candidate.requestFamily == .databaseLookup)
            #expect(candidate.databaseLookupRequest?.searchText == testCase.1)
            #expect(candidate.databaseLookupRequest?.objectTypes == testCase.2)
            #expect(candidate.databaseLookupRequest?.requestedDetail == testCase.3)
        }
    }

    @Test func databaseLookup_regression_analyticsPromptsStayAnalytics() {
        let prompts = [
            "What did I spend this month?",
            "What did I spend on groceries this month?",
            "Compare groceries this month to last month.",
            "Top categories this month.",
            "Top merchants this month.",
            "Which merchants do I spend the most at?",
            "Largest purchases this month.",
            "What percent of my spending was groceries this month?"
        ]

        for prompt in prompts {
            let candidate = MarinaHeuristicInterpreter().interpret(
                prompt: prompt,
                defaultPeriodUnit: .month
            )
            #expect(candidate.requestFamily == .analytics)
        }
    }

    @Test func requestShape_inventoryListVerbsRouteToDatabaseLookup() {
        let cases: [(String, MarinaLookupObjectType)] = [
            ("Show all my cards", .card),
            ("List all of my cards", .card),
            ("What cards do I have?", .card),
            ("Show all my budgets", .budget),
            ("List all my categories", .category),
            ("What presets do I have?", .preset),
            ("List reconciliation accounts", .reconciliationAccount),
            ("Show all my savings accounts", .savingsAccount),
            ("Show recurring income", .incomeSeries),
            ("What income repeats monthly?", .incomeSeries),
            ("Show learned merchant rules", .importMerchantRule),
            ("List all my Marina aliases", .assistantAliasRule),
            ("Do I have any other workspaces?", .workspace)
        ]

        for testCase in cases {
            let candidate = MarinaHeuristicInterpreter().interpret(
                prompt: testCase.0,
                defaultPeriodUnit: .month
            )

            #expect(candidate.requestFamily == .databaseLookup)
            #expect(candidate.operation == .lookupDetails)
            #expect(candidate.databaseLookupRequest?.searchText == "")
            #expect(candidate.databaseLookupRequest?.objectTypes == [testCase.1])
            #expect(candidate.requestShape == .objectInventoryList)
            #expect(MarinaCandidateTrace(candidate: candidate).compactSummary.contains("requestShape=objectInventoryList"))
        }
    }

    @Test func requestShape_rowListPromptsStayLedgerRowLists() {
        let cases = [
            "List expenses this week",
            "Show my last 10 expenses",
            "List income this month",
            "Show savings activity this month"
        ]

        for prompt in cases {
            let candidate = MarinaHeuristicInterpreter().interpret(
                prompt: prompt,
                defaultPeriodUnit: .month
            )

            #expect(candidate.requestFamily == .analytics)
            #expect(candidate.operation == .listRows || candidate.operation == .rank)
            #expect(MarinaCandidateTrace(candidate: candidate).compactSummary.contains("requestShape=ledgerRowList"))
        }
    }

    @Test func heuristic_workspaceAggregationPrompts_emitSummaryCardCandidates() {
        let cases: [(String, MarinaCandidateOperation, MarinaCandidateMeasure, MarinaGroupingDimensionCandidate?)] = [
            ("What income came in this month?", .sum, .income, nil),
            ("What is my actual income this month?", .sum, .income, nil),
            ("What is my planned income this month?", .sum, .income, nil),
            ("What is my income so far this month?", .sum, .income, nil),
            ("What paid me the most this month?", .rank, .income, .incomeSource),
            ("Show income by source.", .sum, .income, .incomeSource),
            ("Compare income this month to last month.", .compare, .income, nil),
            ("What are my biggest upcoming bills?", .rank, .presetAmount, .transaction),
            ("Which presets cost the most?", .rank, .presetAmount, .preset),
            ("Show planned expenses by category.", .sum, .presetAmount, .category),
            ("Show planned expenses by card.", .sum, .presetAmount, .card),
            ("Largest savings movements this month.", .rank, .savingsMovement, .savingsLedgerEntry),
            ("Show shared balances.", .rank, .reconciliationBalance, .allocationAccount)
        ]

        for testCase in cases {
            let candidate = MarinaHeuristicInterpreter().interpret(
                prompt: testCase.0,
                defaultPeriodUnit: .month
            )
            #expect(candidate.requestFamily == .analytics)
            #expect(candidate.operation == testCase.1)
            #expect(candidate.measure == testCase.2)
            #expect(candidate.grouping?.dimension == testCase.3)
            #expect(candidate.responseShapeHint == .summaryCard || candidate.responseShapeHint == .comparison)
        }
    }

    @Test func heuristic_composableWorkspacePrompts_emitExecutableCandidateShapes() {
        let cases: [(String, MarinaCandidateOperation, MarinaCandidateMeasure, MarinaGroupingDimensionCandidate?, MarinaRankingDirectionCandidate?)] = [
            ("Which card is eating the most of my budget?", .rank, .spend, .card, .top),
            ("What did I spend on Apple Card outside of Food & Drink?", .sum, .spend, nil, nil),
            ("List my last 5 Cannabis purchases", .listRows, .transactionAmount, .transaction, .newest),
            ("List my Cannabis purchases", .listRows, .transactionAmount, .transaction, .newest),
            ("What was my average weekly Shopping spending over the last 3 months?", .average, .spend, .week, nil),
            ("Which expenses made this month higher than last month?", .compare, .spend, .transaction, .largest),
            ("How much did Roommate spend on Food & Drink?", .sum, .spend, nil, nil),
            ("What planned expenses are due this month?", .rank, .presetAmount, .transaction, .newest),
            ("Which categories are over budget?", .rank, .remainingBudget, .category, .largest),
            ("What is my Roommate balance?", .rank, .reconciliationBalance, .allocationAccount, .largest),
            ("Which expenses are split with Roommate?", .rank, .reconciliationBalance, .allocationAccount, .newest),
            ("Show allocations this month.", .rank, .reconciliationBalance, .allocationAccount, .newest),
            ("What settlements happened this month?", .rank, .reconciliationBalance, .allocationAccount, .newest),
            ("If I spend $50 on Groceries, how will that affect my budget?", .simulate, .remainingBudget, nil, nil)
        ]

        for testCase in cases {
            let candidate = MarinaHeuristicInterpreter().interpret(
                prompt: testCase.0,
                defaultPeriodUnit: .month
            )
            #expect(candidate.requestFamily == .analytics)
            #expect(candidate.operation == testCase.1)
            #expect(candidate.measure == testCase.2)
            #expect(candidate.grouping?.dimension == testCase.3)
            #expect(candidate.ranking?.direction == testCase.4)
            #expect(candidate.unsupportedHint == nil)
        }
    }

    @Test func heuristic_totalSpendOnAppleCard_emitsUnresolvedCardFilterCandidate() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "total spend on my Apple Card",
            defaultPeriodUnit: .month
        )

        #expect(candidate.source == .heuristic)
        #expect(candidate.rawPrompt == "total spend on my Apple Card")
        #expect(candidate.operation == .sum)
        #expect(candidate.measure == .spend)
        #expect(candidate.entityMentions.count <= 1)

        if let mention = candidate.entityMentions.first {
            #expect(mention.role == .filter || mention.role == .primaryTarget)
            #expect(mention.rawText?.lowercased().contains("apple") == true)
            #expect(mention.rawText?.lowercased().contains("card") == true)
            #expect(mention.typeHint == nil || mention.typeHint == .card)
        }
    }

    @Test func heuristic_shortNamedSpendTargetDoesNotForceMerchantHint() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "What did I spend at Apple?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.requestFamily == .analytics)
        #expect(candidate.operation == .sum)
        #expect(candidate.measure == .spend)
        #expect(candidate.entityMentions.first?.rawText?.localizedCaseInsensitiveContains("Apple") == true)
        #expect(candidate.entityMentions.first?.typeHint == nil)
    }

    @Test func heuristic_explicitMerchantSpendTargetKeepsMerchantHint() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "What did I spend at Apple Store?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.requestFamily == .analytics)
        #expect(candidate.operation == .sum)
        #expect(candidate.measure == .spend)
        #expect(candidate.entityMentions.first?.rawText?.localizedCaseInsensitiveContains("Apple Store") == true)
        #expect(candidate.entityMentions.first?.typeHint == .merchant)
    }

    @Test func heuristic_averageFoodAndDrinkLastThreeMonths_emitsAverageCandidateWithoutResolvingEntityTruth() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "average Food & Drink for the last 3 months",
            defaultPeriodUnit: .month
        )

        #expect(candidate.source == .heuristic)
        #expect(candidate.operation == .average)
        #expect(candidate.measure == .spend)
        #expect(candidate.responseShapeHint == .scalarCurrency || candidate.responseShapeHint == .unsupported)

        if let mention = candidate.entityMentions.first {
            #expect(mention.role == .primaryTarget)
            #expect(mention.confidence == .low || mention.confidence == .medium || mention.confidence == .high)
            #expect(mention.typeHint == nil || mention.typeHint == .category)
        }

        #expect(candidate.timeScopes.allSatisfy { $0.role == .primary || $0.role == .lookbackWindow })
    }

    @Test func heuristic_compareGroceriesThisMonthToLastMonth_emitsComparisonCandidate() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "compare groceries this month to last month",
            defaultPeriodUnit: .month
        )

        #expect(candidate.source == .heuristic)
        #expect(candidate.operation == .compare)
        #expect(candidate.measure == .spend)
        #expect(candidate.responseShapeHint == .comparison || candidate.responseShapeHint == .unsupported)
        #expect(candidate.entityMentions.count <= 1)
        #expect(candidate.timeScopes.contains { $0.role == .primary })
        #expect(candidate.timeScopes.contains { $0.role == .comparison })

        if let mention = candidate.entityMentions.first {
            #expect(mention.rawText?.lowercased().contains("groceries") == true)
            #expect(mention.typeHint == nil || MarinaCandidateEntityTypeHint.allCases.contains(mention.typeHint!))
        }
    }

    @Test func heuristic_whereIsMyMoneyGoing_emitsGroupedRankingWithoutSpecificEntityTruth() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "where is my money going?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.source == .heuristic)
        #expect(candidate.operation == .rank)
        #expect(candidate.measure == .spend)
        #expect(candidate.entityMentions.isEmpty)
        #expect(candidate.grouping?.dimension == .category)
        #expect(candidate.ranking?.direction == .top)
        #expect(candidate.responseShapeHint == .rankedList)
    }

    @Test func heuristic_broadSpendAndRankingPrompts_doNotEmitSyntheticTargets() {
        let prompts = [
            "How much have I spent this month?",
            "What’s my total spending so far this month?",
            "How much money went out this month?",
            "Show me what I spent for April.",
            "Who did I pay the most this month?",
            "What stores did I spend the most at?"
        ]

        for prompt in prompts {
            let candidate = MarinaHeuristicInterpreter().interpret(
                prompt: prompt,
                defaultPeriodUnit: .month
            )
            #expect(candidate.entityMentions.isEmpty)
        }
    }

    @Test func heuristic_targetedSpendPrompts_preserveTargetMentions() {
        let prompts = [
            "What did I spend at Starbucks this month?",
            "What did I spend on Groceries this month?"
        ]

        for prompt in prompts {
            let candidate = MarinaHeuristicInterpreter().interpret(
                prompt: prompt,
                defaultPeriodUnit: .month
            )
            #expect(candidate.entityMentions.count == 1)
            #expect(candidate.entityMentions.first?.rawText?.isEmpty == false)
        }
    }

    @Test func heuristic_higherOrLowerThisMonth_infersComparisonBaseline() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "Was I higher or lower on Transportation this month?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .compare)
        #expect(candidate.timeScopes.contains { $0.role == .primary })
        #expect(candidate.timeScopes.contains { $0.role == .comparison })
        #expect(candidate.entityMentions.first?.typeHint == .category)
    }

    @Test func heuristic_phase2b_targetSpanAndShareCueCleanup() {
        let groceries = MarinaHeuristicInterpreter().interpret(
            prompt: "How much did groceries cost me last month?",
            defaultPeriodUnit: .month
        )
        #expect(groceries.operation == .sum)
        #expect(groceries.entityMentions.first?.rawText?.contains("grocer") == true)
        #expect(groceries.entityMentions.first?.typeHint == .category)

        let transportationTotal = MarinaHeuristicInterpreter().interpret(
            prompt: "What did I spend in Transportation this period?",
            defaultPeriodUnit: .month
        )
        #expect(transportationTotal.entityMentions.first?.rawText?.contains("transportation") == true)
        #expect(transportationTotal.entityMentions.first?.typeHint == .category)

        let transportationShare = MarinaHeuristicInterpreter().interpret(
            prompt: "What portion of my money went to Transportation?",
            defaultPeriodUnit: .month
        )
        #expect(transportationShare.measure == .categoryShare)
        #expect(transportationShare.entityMentions.first?.typeHint == .category)

        let shoppingShare = MarinaHeuristicInterpreter().interpret(
            prompt: "How much of my money went to Shopping this month?",
            defaultPeriodUnit: .month
        )
        #expect(shoppingShare.measure == .categoryShare)
        #expect(shoppingShare.entityMentions.first?.typeHint == .category)
    }

    @Test func heuristic_whatIfPromptDoesNotPretendToSolveMultiEntityExtraction() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "If I increase Shopping by $100, what will I have left for Transportation?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.source == .heuristic)
        #expect(candidate.operation == .simulate || candidate.operation == .sum || candidate.operation == nil)
        #expect(candidate.measure == .remainingBudget || candidate.measure == .spend || candidate.measure == nil)
        #expect(candidate.responseShapeHint == .unsupported || candidate.responseShapeHint == nil)
        #expect(candidate.entityMentions.count <= 1)
        #expect(candidate.entityMentions.map(\.role).contains(.simulationInput) == false)
        #expect(candidate.entityMentions.map(\.role).contains(.simulationOutput) == false)
    }

    @Test func heuristic_dirtyFoodComparisonCleansTrailingClauseOnlyAfterShape() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "Am I spending more on food lately, or is it about normal?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .compare)
        #expect(candidate.measure == .spend)
        #expect(candidate.entityMentions.first?.rawText == "food")
        #expect(candidate.entityMentions.first?.typeHint == .category)
    }

    @Test func heuristic_simulationShapeSplitsShoppingAndTransportationMentions() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "If I add $75 to Shopping, does Transportation still have room?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .simulate)
        #expect(candidate.measure == .remainingBudget)
        #expect(candidate.unsupportedHint == nil)
        #expect(candidate.entityMentions.map(\.role) == [.simulationInput, .simulationOutput])
        #expect(candidate.entityMentions.map(\.rawText) == ["shopping", "transportation"])
        #expect(candidate.entityMentions.allSatisfy { $0.typeHint == .category })
    }

    @Test func heuristic_sharePromptPreservesCategoryShareShape() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "How much of my spending this month was Food & Drink?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .sum)
        #expect(candidate.measure == .categoryShare)
        #expect(candidate.entityMentions.first?.rawText == "food & drink")
        #expect(candidate.entityMentions.first?.typeHint == .category)
        #expect(candidate.responseShapeHint == .groupedBreakdown)
    }

    @Test func heuristic_groupedBreakdownPromptPreservesCategoryGroupedShape() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "Break down where my money went this month, but don’t just give me the total.",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .rank)
        #expect(candidate.measure == .spend)
        #expect(candidate.entityMentions.isEmpty)
        #expect(candidate.grouping?.dimension == .category)
        #expect(candidate.ranking?.direction == .top)
        #expect(candidate.responseShapeHint == .groupedBreakdown)
    }

    @Test func heuristic_frequencyPromptPreservesFrequencyRankingShape() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "Show me the stuff I’m spending on too often, not necessarily the most money.",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .rank)
        #expect(candidate.measure == .transactionFrequency)
        #expect(candidate.grouping?.dimension == .transaction)
        #expect(candidate.ranking?.direction == .mostFrequent)
        #expect(candidate.entityMentions.isEmpty)
    }

    @Test func heuristic_projectionPromptPreservesUnsupportedForecastShape() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "If I keep spending like this, how much will I have left by the end of the period?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .forecast)
        #expect(candidate.measure == .remainingBudget)
        #expect(candidate.unsupportedHint == .unsupportedProjection)
        #expect(candidate.entityMentions.isEmpty)
    }

    @Test func heuristic_exclusionPromptPreservesComposableFilterShape() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "What did I spend on Apple Card outside of Food & Drink?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .sum)
        #expect(candidate.measure == .spend)
        #expect(candidate.unsupportedHint == nil)
        #expect(candidate.responseShapeHint == .summaryCard)
        #expect(candidate.entityMentions.map(\.rawText) == ["apple card", "food & drink"])
        #expect(candidate.entityMentions.map(\.typeHint) == [.card, .category])
    }

    @Test func heuristic_categoryAvailabilityPromptPreservesUnsupportedBudgetLimitShape() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "Is Shopping over where it should be for this budget?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .compare)
        #expect(candidate.measure == .remainingBudget)
        #expect(candidate.unsupportedHint == .unsupportedBudgetLimit)
        #expect(candidate.entityMentions.first?.rawText == "shopping")
        #expect(candidate.entityMentions.first?.typeHint == .category)
    }

    @Test func heuristic_cardRankingPromptPreservesComposableCardRankingShape() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "What card is eating most of my budget this period?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .rank)
        #expect(candidate.measure == .spend)
        #expect(candidate.grouping?.dimension == .card)
        #expect(candidate.ranking?.direction == .top)
        #expect(candidate.unsupportedHint == nil)
        #expect(candidate.entityMentions.isEmpty)
    }

    @Test func heuristic_categoryDeltaRankingPreservesComposableRankedComparisonShape() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "What category changed the most compared to last month?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .compare)
        #expect(candidate.measure == .spend)
        #expect(candidate.grouping?.dimension == .category)
        #expect(candidate.ranking?.direction == .largest)
        #expect(candidate.unsupportedHint == nil)
        #expect(candidate.entityMentions.isEmpty)
    }

    @Test func heuristic_comparedToLastMonthBuildsPrimaryAndComparisonScopes() {
        let candidate = fixedNowInterpreter().interpret(
            prompt: "How bad was Food & Drink compared to last month?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .compare)
        #expect(candidate.measure == .spend)
        #expect(candidate.entityMentions.first?.rawText == "food & drink")
        #expect(candidate.entityMentions.first?.typeHint == .category)
        assertMonthScopes(candidate, primaryMonth: 5, comparisonMonth: 4)
    }

    @Test func heuristic_thisMonthThanLastMonthBuildsPrimaryAndComparisonScopes() {
        let candidate = fixedNowInterpreter().interpret(
            prompt: "Did I spend more on restaurants this month than last month?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .compare)
        #expect(candidate.measure == .spend)
        #expect(candidate.entityMentions.first?.rawText == "restaurants")
        assertMonthScopes(candidate, primaryMonth: 5, comparisonMonth: 4)
    }

    @Test func heuristic_thisMonthVsLastMonthBuildsPrimaryAndComparisonScopes() {
        let candidate = fixedNowInterpreter().interpret(
            prompt: "Compare Food & Drink this month vs last month",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .compare)
        #expect(candidate.measure == .spend)
        assertMonthScopes(candidate, primaryMonth: 5, comparisonMonth: 4)
    }

    @Test func heuristic_fromMarchToAprilBuildsBothScopesWithAprilPrimary() {
        let candidate = fixedNowInterpreter().interpret(
            prompt: "Did groceries go up or down from March to April?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .compare)
        #expect(candidate.measure == .spend)
        #expect(candidate.entityMentions.first?.rawText == "groceries")
        assertMonthScopes(candidate, primaryMonth: 4, comparisonMonth: 3)
    }

    @Test func heuristic_transactionDeltaDriversPreservesComposableRankedComparisonShape() {
        let candidate = fixedNowInterpreter().interpret(
            prompt: "What expenses are making this month higher than last month?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .compare)
        #expect(candidate.measure == .spend)
        #expect(candidate.grouping?.dimension == .transaction)
        #expect(candidate.ranking?.direction == .largest)
        #expect(candidate.unsupportedHint == nil)
        #expect(candidate.entityMentions.isEmpty)
        assertMonthScopes(candidate, primaryMonth: 5, comparisonMonth: 4)
    }

    @Test func heuristicCandidateTrace_summarizesAdapterOutput() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "where is my money going?",
            defaultPeriodUnit: .month
        )
        let trace = MarinaCandidateTrace(candidate: candidate)

        #expect(trace.interpreterSource == .heuristic)
        #expect(trace.operation == candidate.operation)
        #expect(trace.measure == candidate.measure)
        #expect(trace.compactSummary.contains("source=heuristic"))
        #expect(trace.executablePlanSummary == nil)
        #expect(trace.validatorOutcomeSummary == nil)
    }

    private func fixedNowInterpreter() -> MarinaHeuristicInterpreter {
        MarinaHeuristicInterpreter(now: { date(2026, 5, 8) })
    }

    private func assertMonthScopes(
        _ candidate: MarinaQueryPlanCandidate,
        primaryMonth: Int,
        comparisonMonth: Int,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let calendar = Calendar(identifier: .gregorian)
        let primary = candidate.timeScopes.first { $0.role == .primary }?.resolvedRangeHint?.startDate
        let comparison = candidate.timeScopes.first { $0.role == .comparison }?.resolvedRangeHint?.startDate

        #expect(primary != nil, sourceLocation: sourceLocation)
        #expect(comparison != nil, sourceLocation: sourceLocation)
        #expect(primary.map { calendar.component(.month, from: $0) } == primaryMonth, sourceLocation: sourceLocation)
        #expect(comparison.map { calendar.component(.month, from: $0) } == comparisonMonth, sourceLocation: sourceLocation)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        return components.date ?? Date(timeIntervalSince1970: 0)
    }
}
