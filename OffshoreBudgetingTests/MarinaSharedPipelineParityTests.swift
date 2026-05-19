import Foundation
import SwiftData
import Testing
@testable import Offshore

@Suite(.serialized)
@MainActor
struct MarinaSharedPipelineParityTests {
    @Test func parity_sharedReadShimHandlesProvenModelRouterReadPrompts() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        try fixture.seedComparisonData()

        let cases: [(prompt: String, legacyPlan: HomeQueryPlan)] = [
            (
                "What did I spend this month?",
                HomeQueryPlan(metric: .spendTotal, dateRange: nil, resultLimit: nil, confidenceBand: .high, periodUnit: .month)
            ),
            (
                "What did I spend on Groceries this month?",
                HomeQueryPlan(metric: .categorySpendTotal, dateRange: nil, resultLimit: nil, confidenceBand: .high, targetName: "Groceries", periodUnit: .month)
            ),
            (
                "What is the total spend on my Apple Card?",
                HomeQueryPlan(metric: .cardSpendTotal, dateRange: nil, resultLimit: nil, confidenceBand: .high, targetName: "Apple Card", periodUnit: .month)
            ),
            (
                "Compare Groceries this month to last month",
                HomeQueryPlan(metric: .categoryMonthComparison, dateRange: nil, comparisonDateRange: nil, resultLimit: nil, confidenceBand: .high, targetName: "Groceries", periodUnit: .month)
            ),
            (
                "Show my top categories this month",
                HomeQueryPlan(metric: .topCategories, dateRange: nil, resultLimit: nil, confidenceBand: .high, periodUnit: .month)
            ),
            (
                "What were my biggest purchases this month?",
                HomeQueryPlan(metric: .largestTransactions, dateRange: nil, resultLimit: nil, confidenceBand: .high, periodUnit: .month)
            )
        ]

        let router = MarinaLanguageRouter(
            availability: SharedPipelineStubAvailability(status: .unavailable(reason: "shim parity")),
            modelService: SharedPipelineThrowingStructuredInterpreter(),
            planBuilder: MarinaStructuredIntentPlanBuilder()
        )
        let shim = MarinaSharedReadShim()

        for testCase in cases {
            let legacy = await router.interpret(
                prompt: testCase.prompt,
                context: sharedContext(fixture: fixture).routerContext,
                heuristicFallback: {
                    .query(testCase.legacyPlan, source: .parser)
                }
            )
            guard case .query(let legacyPlan, _) = legacy else {
                Issue.record("Expected legacy model-router query fallback for \(testCase.prompt)")
                continue
            }

            let shimResult = await shim.run(
                prompt: testCase.prompt,
                context: sharedContext(fixture: fixture, sharedPipelineEnabled: false)
            )
            guard case .handled(_, _, let sharedPlan, let trace) = shimResult else {
                Issue.record("Expected shared read shim to handle \(testCase.prompt): \(shimResult)")
                continue
            }

            #expect(trace.selectedPath != .sharedAttemptedThenLegacyFallback)
            #expect(sharedPlan?.metric == legacyPlan.metric)
            #expect(sharedPlan?.targetName == legacyPlan.targetName)
        }
    }

    @Test func parity_sharedReadShimCoversLegacyModelRouterReadAssertionsBeforeRetirement() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let cannabis = Offshore.Category(name: "Cannabis", hexColor: "#225522", workspace: fixture.workspace)
        fixture.context.insert(cannabis)
        fixture.context.insert(VariableExpense(descriptionText: "Cannabis March", amount: 30, transactionDate: date(2026, 3, 9), workspace: fixture.workspace, card: fixture.appleCard, category: cannabis))
        try fixture.context.save()

        let cases: [(prompt: String, expectedMetric: HomeQueryMetric, expectedTarget: String?)] = [
            ("What did I spend on groceries last month?", .categorySpendTotal, "Groceries"),
            ("Top expense of all time", .largestTransactions, nil),
            ("Spending by category for this period", .topCategories, nil),
            ("Spend in Cannabis this year", .categorySpendTotal, "Cannabis")
        ]

        for testCase in cases {
            let result = await MarinaSharedReadShim().run(
                prompt: testCase.prompt,
                context: sharedContext(fixture: fixture, sharedPipelineEnabled: false)
            )

            guard case .handled(_, _, let plan, let trace) = result else {
                Issue.record("Expected shared-read replacement coverage before retiring legacy model-router assertion: \(testCase.prompt), result=\(result)")
                continue
            }
            #expect(trace.selectedPath != .sharedAttemptedThenLegacyFallback)
            #expect(plan?.metric == testCase.expectedMetric)
            #expect(plan?.targetName == testCase.expectedTarget)
        }
    }

    @Test func parity_sharedReadShimHandlesActualIncomeSummaryWhenSharedPipelineSupportsIt() async throws {
        let fixture = try makeFixture()
        fixture.context.insert(Income(source: "Salary", amount: 2_400, date: date(2026, 5, 5), isPlanned: false, workspace: fixture.workspace))
        fixture.context.insert(Income(source: "Salary", amount: 2_500, date: date(2026, 5, 15), isPlanned: true, workspace: fixture.workspace))
        try fixture.context.save()

        let result = await MarinaSharedReadShim().run(
            prompt: "What is my actual income this month?",
            context: sharedContext(fixture: fixture, sharedPipelineEnabled: false)
        )

        guard case .handled(let answer, _, _, let trace) = result else {
            Issue.record("Expected actual income summary to be shimmed when shared pipeline handles it: \(result)")
            return
        }
        #expect(answer.title == "Actual Income")
        #expect(trace.executorResultSummary?.contains("workspaceAggregation=incomeSummary") == true)
        #expect(trace.selectedPath != .sharedAttemptedThenLegacyFallback)
    }

    @Test func parity_sharedReadShimDeclinesUnprovenLegacyRoutes() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let shim = MarinaSharedReadShim()

        let excludedPrompts = [
            "/explain What did I spend this month?",
            "If I add $75 to Shopping, does Transportation still have room?",
            "hello"
        ]

        for prompt in excludedPrompts {
            let result = await shim.run(prompt: prompt, context: sharedContext(fixture: fixture))
            guard case .notShimmed(let reason, let trace) = result else {
                Issue.record("Expected excluded prompt to decline shim: \(prompt), result=\(result)")
                continue
            }
            #expect(reason == .excludedPrompt)
            #expect(trace == nil)
        }

        let commandResult = await shim.run(
            prompt: "create card named Travel Card",
            context: sharedContext(fixture: fixture)
        )
        guard case .notShimmed(let commandReason, let commandTrace) = commandResult else {
            Issue.record("Expected command prompt to decline shim: \(commandResult)")
            return
        }
        #expect(commandReason == .command)
        #expect(commandTrace == nil)

        let validationResult = await shim.run(
            prompt: "What did I spend on Unknown this month?",
            context: sharedContext(fixture: fixture)
        )
        guard case .notShimmed(let validationReason, let validationTrace) = validationResult else {
            Issue.record("Expected unknown target to decline shim: \(validationResult)")
            return
        }
        #expect(validationReason == .validationBlocked)
        #expect(validationTrace?.executorResultSummary == nil)
    }

    @Test func parity_broadSpendMatchesLegacyMetricFamily() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let result = await run("What did I spend this month?", fixture: fixture)

        guard case .handled(let answer, let aggregationResult, let homeQueryPlan, _) = result else {
            Issue.record("Expected broad spend to be handled: \(result.trace.compactSummary)")
            return
        }
        #expect(homeQueryPlan?.metric == .spendTotal)
        #expect(answer.kind == .metric)
        guard case .scalar(let scalar) = aggregationResult else {
            Issue.record("Expected scalar broad spend.")
            return
        }
        #expect((scalar.renderedValue ?? "").filter(\.isNumber).contains("600"))
    }

    @Test func parity_categorySpendPreservesResolvedTarget() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let result = await run("What did I spend on Groceries this month?", fixture: fixture)

        guard case .handled(let answer, let aggregationResult, let homeQueryPlan, _) = result else {
            Issue.record("Expected category spend to be handled.")
            return
        }
        #expect(homeQueryPlan?.metric == .categorySpendTotal)
        #expect(homeQueryPlan?.targetName == "Groceries")
        #expect(answer.kind == .metric)
        guard case .scalar(let scalar) = aggregationResult else {
            Issue.record("Expected scalar category spend.")
            return
        }
        #expect((scalar.renderedValue ?? "").filter(\.isNumber).contains("300"))
    }

    @Test func parity_sharedCandidateBoundaryHandlesRequestedPromptSet() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        try fixture.seedComparisonData()
        let cannabis = Offshore.Category(name: "Cannabis", hexColor: "#225522", workspace: fixture.workspace)
        fixture.context.insert(cannabis)
        fixture.context.insert(VariableExpense(descriptionText: "Cannabis March", amount: 30, transactionDate: date(2026, 3, 9), workspace: fixture.workspace, card: fixture.appleCard, category: cannabis))
        fixture.context.insert(VariableExpense(descriptionText: "Cannabis April", amount: 60, transactionDate: date(2026, 4, 10), workspace: fixture.workspace, card: fixture.appleCard, category: cannabis))
        fixture.context.insert(VariableExpense(descriptionText: "Cannabis Current", amount: 45, transactionDate: date(2026, 5, 11), workspace: fixture.workspace, card: fixture.appleCard, category: cannabis))
        try fixture.context.save()

        let prompts = [
            "What did I spend on groceries this month?",
            "List my most recent Groceries purchases",
            "What was my last Cannabis purchase?",
            "What do I normally spend on Cannabis each month?",
            "Compare groceries this month to last month",
            "Break down my spending by category this month",
            "What percent of my spending was groceries this month?"
        ]

        for prompt in prompts {
            let result = await run(prompt, fixture: fixture)
            guard case .handled(_, let aggregationResult, let homeQueryPlan, let trace) = result else {
                Issue.record("Expected shared pipeline to handle '\(prompt)': \(result.trace.compactSummary)")
                continue
            }
            assertSharedTrace(trace, prompt: prompt)
            #expect(homeQueryPlan != nil || trace.executorResultSummary?.contains("composableWorkspace=") == true)

            switch prompt {
            case "List my most recent Groceries purchases":
                #expect(trace.candidateSummary?.contains("operation=listRows") == true)
                #expect(trace.candidateSummary?.contains("ranking=newest") == true)
            case "What was my last Cannabis purchase?":
                #expect(trace.candidateSummary?.contains("operation=listRows") == true)
                #expect(trace.candidateSummary?.contains("ranking=newest:1") == true)
            case "What do I normally spend on Cannabis each month?":
                #expect(trace.candidateSummary?.contains("operation=average") == true)
                #expect(trace.candidateSummary?.contains("grouping=month") == true)
                #expect(trace.candidateSummary?.contains("last 3 completed months") == true)
                #expect(trace.candidateSummary?.contains("2026-02") == true)
            case "Compare groceries this month to last month":
                #expect(homeQueryPlan?.comparisonDateRange != nil)
            case "Break down my spending by category this month":
                #expect(trace.candidateSummary?.contains("responseHint=groupedBreakdown") == true)
                #expect(trace.responseBridgeSummary?.contains("responseShape=groupedBreakdown") == true)
            case "What percent of my spending was groceries this month?":
                #expect(trace.candidateSummary?.contains("measure=categoryShare") == true)
                switch aggregationResult {
                case .groupedBreakdown(let list), .rankedList(let list):
                    #expect(list.rows.contains { $0.label.localizedCaseInsensitiveContains("Groceries") })
                case .scalar(let scalar):
                    #expect((scalar.renderedValue ?? "").contains("%") || scalar.rows.contains { $0.renderedValue.contains("%") })
                default:
                    Issue.record("Expected category share percentage result.")
                }
            default:
                break
            }
        }
    }

    @Test func parity_cardSpendPreservesResolvedTarget() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let result = await run("What is the total spend on my Apple Card?", fixture: fixture)

        guard case .handled(_, let aggregationResult, let homeQueryPlan, _) = result else {
            Issue.record("Expected card spend to be handled.")
            return
        }
        #expect(homeQueryPlan?.metric == .cardSpendTotal)
        #expect(homeQueryPlan?.targetName == "Apple Card")
        guard case .scalar(let scalar) = aggregationResult else {
            Issue.record("Expected scalar card spend.")
            return
        }
        #expect((scalar.renderedValue ?? "").filter(\.isNumber).contains("500"))
    }

    @Test func parity_comparisonPreservesShapeAndRanges() async throws {
        let fixture = try makeFixture()
        try fixture.seedComparisonData()
        let result = await run("Compare Groceries this month to last month", fixture: fixture)

        guard case .handled(let answer, let aggregationResult, let homeQueryPlan, _) = result else {
            Issue.record("Expected comparison to be handled: \(result.trace.compactSummary)")
            return
        }
        #expect(homeQueryPlan?.metric == .categoryMonthComparison)
        #expect(homeQueryPlan?.targetName == "Groceries")
        #expect(homeQueryPlan?.comparisonDateRange != nil)
        #expect(answer.kind == .comparison)
        guard case .comparison = aggregationResult else {
            Issue.record("Expected comparison result shape.")
            return
        }
    }

    @Test func parity_whereMoneyGoingAndTopCategoriesStayRankedLists() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()

        for prompt in ["Where is my money going?", "Where did my money go this month?", "Show my top categories this month"] {
            let result = await run(prompt, fixture: fixture)
            guard case .handled(let answer, let aggregationResult, let homeQueryPlan, _) = result else {
                Issue.record("Expected ranked prompt to be handled: \(prompt)")
                continue
            }
            #expect(homeQueryPlan?.metric == .topCategories)
            #expect(answer.kind == .list)
            guard case .rankedList(let list) = aggregationResult else {
                Issue.record("Expected ranked-list result: \(prompt)")
                continue
            }
            #expect(list.rows.isEmpty == false)
        }
    }

    @Test func parity_userReportedReadPhrasesStayOnSharedPath() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        try fixture.seedComparisonData()
        try fixture.seedIncomeData()
        fixture.context.insert(VariableExpense(descriptionText: "Apple Card May 12 A", amount: 12, transactionDate: date(2026, 5, 12), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries))
        fixture.context.insert(VariableExpense(descriptionText: "Apple Card May 12 B", amount: 18, transactionDate: date(2026, 5, 12), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.travel))
        fixture.context.insert(VariableExpense(descriptionText: "Apple Card May 13", amount: 90, transactionDate: date(2026, 5, 13), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.travel))
        try fixture.context.save()

        let metricCases: [(prompt: String, metric: HomeQueryMetric, target: String?)] = [
            ("How much did I spend on groceries?", .categorySpendTotal, "Groceries"),
            ("How much did I spend on groceries last month?", .categorySpendTotal, "Groceries"),
            ("What was my Apple Card spend last month?", .cardSpendTotal, "Apple Card"),
            ("What did groceries cost me last month?", .categorySpendTotal, "Groceries"),
            ("What is my average actual income each month?", .incomeAverageActual, nil)
        ]

        for testCase in metricCases {
            let result = await run(testCase.prompt, fixture: fixture)
            guard case .handled(let answer, let aggregationResult, let homeQueryPlan, let trace) = result else {
                Issue.record("Expected handled shared result for \(testCase.prompt): \(result.trace.compactSummary)")
                continue
            }
            assertSharedTrace(trace, prompt: testCase.prompt)
            #expect(homeQueryPlan?.metric == testCase.metric)
            #expect(homeQueryPlan?.targetName == testCase.target)
            #expect(answer.title != "Unsupported Marina Query")
            switch aggregationResult {
            case .scalar, .rankedList, .workspaceCard:
                break
            default:
                Issue.record("Unexpected result shape for \(testCase.prompt): \(aggregationResult)")
            }
        }

        for prompt in ["List the last 10 expenses on my Apple Card", "Show the last 10 expenses on my Apple Card"] {
            let result = await run(prompt, fixture: fixture)
            guard case .handled(_, let aggregationResult, _, let trace) = result else {
                Issue.record("Expected handled shared expense list for \(prompt): \(result.trace.compactSummary)")
                continue
            }
            assertSharedTrace(trace, prompt: prompt)
            #expect(trace.candidateSummary?.contains("operation=listRows") == true)
            #expect(trace.candidateSummary?.contains("limit=10") == true || trace.candidateSummary?.contains("ranking=newest:10") == true)
            guard case .workspaceCard(let card) = aggregationResult else {
                Issue.record("Expected workspace-card list result for \(prompt): \(aggregationResult)")
                continue
            }
            #expect(card.rows.count <= 10)
            #expect(card.rows.isEmpty == false)
            #expect(card.rows.allSatisfy { $0.label.localizedCaseInsensitiveContains("Apple Card") || $0.value.localizedCaseInsensitiveContains("Apple Card") })
        }

        let exactDay = await run("Show Apple Card expenses on May 12, 2026", fixture: fixture)
        guard case .handled(_, let exactDayResult, _, let exactDayTrace) = exactDay else {
            Issue.record("Expected exact-day Apple Card expense list to be handled: \(exactDay.trace.compactSummary)")
            return
        }
        assertSharedTrace(exactDayTrace, prompt: "Show Apple Card expenses on May 12, 2026")
        guard case .workspaceCard(let exactDayCard) = exactDayResult else {
            Issue.record("Expected exact-day expense list to use workspace card result: \(exactDayResult)")
            return
        }
        #expect(exactDayCard.subtitle?.contains("May 12") == true, "Expected exact-day subtitle, got \(exactDayCard.subtitle ?? "nil")")
        #expect(exactDayCard.subtitle?.contains("May 1-May 31") != true, "Expected exact-day subtitle instead of month range, got \(exactDayCard.subtitle ?? "nil")")
        #expect(exactDayCard.rows.count == 2)
        #expect(exactDayCard.rows.allSatisfy { $0.date.map { Calendar(identifier: .gregorian).component(.day, from: $0) == 12 } ?? false })
    }

    @Test func parity_questionRepertoireHandlesHybridCategoryExpenseAmbiguityPolicy() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        fixture.context.insert(VariableExpense(descriptionText: "Groceries", amount: 42, transactionDate: date(2026, 5, 12), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries))
        fixture.context.insert(VariableExpense(descriptionText: "Groceries", amount: 18, transactionDate: date(2026, 5, 13), workspace: fixture.workspace, card: fixture.backupCard, category: fixture.travel))
        fixture.context.insert(VariableExpense(descriptionText: "Whole Foods Groceries", amount: 64, transactionDate: date(2026, 5, 14), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries))
        fixture.context.insert(VariableExpense(descriptionText: "Starbucks", amount: 9, transactionDate: date(2026, 5, 15), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.travel))
        try fixture.context.save()

        let categoryAggregate = await run("How much did I spend on Groceries?", fixture: fixture)
        guard case .handled(_, _, let categoryPlan, let categoryTrace) = categoryAggregate else {
            Issue.record("Expected category aggregate to execute despite same-named expenses: \(categoryAggregate.trace.compactSummary)")
            return
        }
        assertSharedTrace(categoryTrace, prompt: "How much did I spend on Groceries?")
        #expect(categoryPlan?.metric == .categorySpendTotal)
        #expect(categoryPlan?.targetName == "Groceries")
        #expect(categoryPlan?.targetTypeRaw == "category")

        let merchantAggregate = await run("What did I spend at Groceries?", fixture: fixture)
        guard case .handled(_, _, let merchantPlan, let merchantTrace) = merchantAggregate else {
            Issue.record("Expected explicit merchant/description aggregate to execute: \(merchantAggregate.trace.compactSummary)")
            return
        }
        assertSharedTrace(merchantTrace, prompt: "What did I spend at Groceries?")
        #expect(merchantPlan?.metric == .merchantSpendTotal)
        #expect(merchantPlan?.targetName == "Groceries")
        #expect(merchantPlan?.targetTypeRaw == "merchant")

        let bareLookup = await run("Show Groceries", fixture: fixture)
        guard case .validationBlocked(let lookupAnswer, let lookupOutcome, let lookupTrace) = bareLookup,
              case .clarification(let clarification) = lookupOutcome else {
            Issue.record("Expected bare lookup to clarify across category and expense rows: \(bareLookup.trace.compactSummary)")
            return
        }
        #expect(lookupTrace.compactSummary.contains("family=databaseLookup"))
        #expect(lookupAnswer.title.contains("Which Groceries"))
        #expect(lookupAnswer.rows.contains { $0.value.contains("Category") })
        #expect(lookupAnswer.rows.contains { $0.value.contains("$42.00") && $0.value.contains("Apple Card") })
        #expect(clarification.choices.contains { $0.entityTypeHint == .category })
        #expect(clarification.choices.contains { $0.entityTypeHint == .expense })

    }

    @Test func parity_questionRepertoireCoversBroaderReadEntitiesAndAggregations() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        try fixture.seedIncomeData()
        fixture.context.insert(VariableExpense(descriptionText: "Starbucks", amount: 9, transactionDate: date(2026, 5, 15), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.travel))
        let budget = Budget(name: "May Budget", startDate: date(2026, 5, 1), endDate: date(2026, 5, 31), workspace: fixture.workspace)
        fixture.context.insert(budget)
        fixture.context.insert(PlannedExpense(title: "Internet", plannedAmount: 90, expenseDate: date(2026, 5, 20), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.travel))
        fixture.context.insert(SavingsAccount(name: "True Savings", total: 500, workspace: fixture.workspace))
        fixture.context.insert(AllocationAccount(name: "Roommate", workspace: fixture.workspace))
        try fixture.context.save()

        let cases: [(prompt: String, metric: HomeQueryMetric?)] = [
            ("Where did my money go this month?", .topCategories),
            ("What merchants did I spend the most at?", .topMerchants),
            ("What is my average actual income each month?", .incomeAverageActual),
            ("What is my safe spend today?", .safeSpendToday),
            ("What is my next planned expense?", .nextPlannedExpense),
            ("Show shared balances.", nil)
        ]

        for testCase in cases {
            let result = await run(testCase.prompt, fixture: fixture)
            guard case .handled(_, _, let plan, let trace) = result else {
                Issue.record("Expected repertoire prompt to be handled: \(testCase.prompt), trace=\(result.trace.compactSummary)")
                continue
            }
            #expect(trace.selectedPath != .sharedAttemptedThenLegacyFallback)
            if let expectedMetric = testCase.metric {
                #expect(plan?.metric == expectedMetric, "Unexpected metric for \(testCase.prompt): \(String(describing: plan?.metric))")
            } else {
                #expect(trace.executorResultSummary?.contains("workspaceAggregation=sharedBalances") == true)
            }
        }
    }

    @Test func parity_followUpCompareToLastMonthUsesPriorTopCategory() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        try fixture.seedComparisonData()

        let priorRange = HomeQueryDateRange(startDate: date(2026, 5, 1), endDate: date(2026, 5, 31))
        let prior = MarinaPriorQueryContext(
            lastQueryPlan: HomeQueryPlan(metric: .topCategories, dateRange: priorRange, resultLimit: 1, confidenceBand: .high, targetName: "Groceries", targetTypeRaw: "category", periodUnit: .month),
            lastMetric: .topCategories,
            lastTargetName: "Groceries",
            lastTargetType: .category,
            lastDateRange: priorRange,
            lastResultLimit: 1,
            lastPeriodUnit: .month
        )

        let result = await MarinaSharedPipelineCoordinator().run(
            prompt: "Compare to last month",
            context: sharedContext(
                fixture: fixture,
                turnClassification: .followUp,
                priorQueryContext: prior
            )
        )

        guard case .handled(let answer, let aggregationResult, let homeQueryPlan, let trace) = result else {
            Issue.record("Expected follow-up comparison to use prior top category: \(result.trace.compactSummary)")
            return
        }
        assertSharedTrace(trace, prompt: "Compare to last month")
        #expect(trace.priorContextIncluded == true)
        #expect(homeQueryPlan?.metric == .categoryMonthComparison)
        #expect(homeQueryPlan?.targetName == "Groceries")
        #expect(homeQueryPlan?.comparisonDateRange != nil)
        #expect(answer.kind == .comparison)
        guard case .comparison = aggregationResult else {
            Issue.record("Expected comparison aggregation for follow-up.")
            return
        }
    }

    @Test func parity_followUpCompareThisToLastMonthUsesPriorTopCategory() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        try fixture.seedComparisonData()

        let priorRange = HomeQueryDateRange(startDate: date(2026, 5, 1), endDate: date(2026, 5, 31))
        let prior = MarinaPriorQueryContext(
            lastQueryPlan: HomeQueryPlan(metric: .topCategories, dateRange: priorRange, resultLimit: 1, confidenceBand: .high, targetName: "Groceries", targetTypeRaw: "category", periodUnit: .month),
            lastMetric: .topCategories,
            lastTargetName: "Groceries",
            lastTargetType: .category,
            lastDateRange: priorRange,
            lastResultLimit: 1,
            lastPeriodUnit: .month
        )

        let result = await MarinaSharedPipelineCoordinator().run(
            prompt: "Compare this to last month",
            context: sharedContext(
                fixture: fixture,
                turnClassification: .followUp,
                priorQueryContext: prior
            )
        )

        guard case .handled(let answer, let aggregationResult, let homeQueryPlan, let trace) = result else {
            Issue.record("Expected follow-up comparison to use prior top category: \(result.trace.compactSummary)")
            return
        }
        assertSharedTrace(trace, prompt: "Compare this to last month")
        #expect(homeQueryPlan?.metric == .categoryMonthComparison)
        #expect(homeQueryPlan?.targetName == "Groceries")
        #expect(answer.kind == .comparison)
        guard case .comparison = aggregationResult else {
            Issue.record("Expected comparison aggregation for follow-up.")
            return
        }
    }

    @Test func parity_largestTransactionsStaySharedPathWithoutLegacyFallback() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()

        let cases: [(String, Int?)] = [
            ("What were my biggest purchases this month?", nil)
        ]

        for (prompt, expectedLimit) in cases {
            let result = await run(prompt, fixture: fixture)
            guard case .handled(_, _, let plan, let trace) = result else {
                Issue.record("Expected largest-transactions prompt to be handled: \(prompt)")
                continue
            }
            #expect(trace.selectedPath != .sharedAttemptedThenLegacyFallback)
            #expect(plan?.metric == .largestTransactions)
            if let expectedLimit {
                #expect(plan?.resultLimit == expectedLimit)
            }
        }
    }

    @Test func parity_explicitUnsupportedPromptsBlockInsteadOfApproximating() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()

        for prompt in [
            "If I increase Shopping by $100, what will I have left for Transportation?",
            "What did I spend on Unknown this month?"
        ] {
            let result = await run(prompt, fixture: fixture)
            guard case .validationBlocked(let answer, let outcome, let trace) = result else {
                Issue.record("Expected unsupported prompt to be blocked: \(prompt)")
                continue
            }
            #expect(answer.kind == .message)
            switch outcome {
            case .clarification, .unsupported:
                break
            case .executable:
                Issue.record("Blocked prompt should not carry an executable validation outcome: \(prompt)")
            }
            #expect(trace.selectedPath == .sharedHeuristic)
            #expect(trace.fallbackReason == nil)
            #expect(trace.executorResultSummary == nil)
        }
    }

    @Test func parity_consoleNegativeInteractionPromptsAvoidGenericUnsupported() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let cannabis = Offshore.Category(name: "Cannabis", hexColor: "#225522", workspace: fixture.workspace)
        fixture.context.insert(cannabis)
        fixture.context.insert(Preset(title: "Rent", plannedAmount: 1_500, workspace: fixture.workspace, defaultCard: fixture.appleCard, defaultCategory: fixture.groceries))
        fixture.context.insert(PlannedExpense(title: "Rent", plannedAmount: 1_500, expenseDate: date(2026, 5, 4), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries))
        fixture.context.insert(VariableExpense(descriptionText: "Cannabis Purchase 1", amount: 40, transactionDate: date(2026, 5, 9), workspace: fixture.workspace, card: fixture.appleCard, category: cannabis))
        fixture.context.insert(VariableExpense(descriptionText: "Cannabis Purchase 2", amount: 50, transactionDate: date(2026, 5, 10), workspace: fixture.workspace, card: fixture.appleCard, category: cannabis))
        try fixture.context.save()

        let cases = [
            "Average spend on Rent?",
            "List most recent Cannabis expenses",
            "Most recent expenses in Cannabis category",
            "Spend in Cannabis this year"
        ]

        for prompt in cases {
            let result = await run(prompt, fixture: fixture)
            switch result {
            case .handled(let answer, _, _, let trace):
                #expect(answer.title != "Unsupported Marina Query")
                #expect(trace.selectedPath != .sharedAttemptedThenLegacyFallback)
                #expect(trace.operationPreserved == true)
            case .validationBlocked(let answer, let outcome, let trace):
                #expect(answer.title != "Unsupported Marina Query")
                #expect(trace.selectedPath != .sharedAttemptedThenLegacyFallback)
                switch outcome {
                case .clarification:
                    break
                case .unsupported, .executable:
                    Issue.record("Console prompt should answer or clarify, not dead-end: \(prompt)")
                }
            case .fallbackToLegacy(let trace):
                Issue.record("Console prompt should stay in shared pipeline: \(prompt), trace=\(trace.compactSummary)")
            }
        }
    }

    @Test func parity_ambiguousTargetFallsBackForClarification() async throws {
        let fixture = try makeFixture()
        fixture.context.insert(Offshore.Category(name: "Apple", hexColor: "#00AA00", workspace: fixture.workspace))
        fixture.context.insert(Card(name: "Apple", workspace: fixture.workspace))
        try fixture.context.save()

        let model = SharedPipelineStubStructuredInterpreter(
            structuredIntent: .query(
                MarinaStructuredQueryIntent(
                    metricRaw: "spendTotal",
                    targetName: "Apple",
                    targetTypeRaw: nil,
                    dateStartISO8601: "2026-05-01",
                    dateEndISO8601: "2026-06-01",
                    comparisonDateStartISO8601: nil,
                    comparisonDateEndISO8601: nil,
                    resultLimit: nil,
                    periodUnitRaw: "month",
                    confidenceRaw: "high",
                    clarification: nil
                )
            )
        )

        let result = await MarinaSharedPipelineCoordinator(
            availability: SharedPipelineStubAvailability(status: .available),
            structuredInterpreter: model
        ).run(
            prompt: "Apple",
            context: sharedContext(fixture: fixture, aiOptInEnabled: true)
        )

        guard case .validationBlocked(_, let outcome, let trace) = result else {
            Issue.record("Ambiguous target should not execute: \(result.trace.compactSummary)")
            return
        }
        guard case .clarification(let clarification) = outcome else {
            Issue.record("Expected typed clarification.")
            return
        }
        #expect(clarification.kind == .ambiguousTarget)
        #expect(trace.selectedPath == .sharedFoundationModels)
        #expect(trace.fallbackReason == nil)
        #expect(trace.validatorOutcomeSummary?.contains("clarification") == true)
    }

    @Test func parity_appleCardVersusMerchantClarifiesBeforeSpendAggregation() async throws {
        let fixture = try makeFixture()
        let appleCard = Card(name: "Apple", workspace: fixture.workspace)
        fixture.context.insert(appleCard)
        fixture.context.insert(VariableExpense(descriptionText: "Apple", amount: 12, transactionDate: date(2026, 5, 10), workspace: fixture.workspace, card: fixture.backupCard, category: fixture.groceries))
        try fixture.context.save()

        let command = MarinaSemanticCommand(
            family: .analytics,
            action: .total,
            datasets: [.variableExpenses, .plannedExpenses],
            measure: .spend,
            includeFilters: [
                MarinaSemanticCommandFilter(rawText: "Apple", allowedTypes: [.card, .merchant])
            ],
            excludeFilters: [],
            grouping: nil,
            sort: nil,
            dateRange: HomeQueryDateRange(startDate: date(2026, 5, 1), endDate: date(2026, 5, 31)),
            comparisonDateRange: nil,
            periodUnit: .month,
            limit: nil,
            requestedDetail: nil
        )

        let result = await MarinaSharedPipelineCoordinator(
            availability: SharedPipelineStubAvailability(status: .available),
            structuredInterpreter: SharedPipelineStubStructuredInterpreter(structuredIntent: .semanticCommand(command))
        ).run(
            prompt: "What was my spend on Apple last period?",
            context: sharedContext(fixture: fixture, aiOptInEnabled: true)
        )

        guard case .validationBlocked(_, let outcome, let trace) = result else {
            Issue.record("Apple should clarify before aggregation: \(result.trace.compactSummary)")
            return
        }
        guard case .clarification(let clarification) = outcome else {
            Issue.record("Expected typed clarification.")
            return
        }
        #expect(clarification.kind == .ambiguousTarget)
        #expect(clarification.choices.compactMap(\.entityTypeHint).contains(.card))
        #expect(clarification.choices.compactMap(\.entityTypeHint).contains(.merchant))
        #expect(trace.executorResultSummary == nil)
    }

    private func run(
        _ prompt: String,
        fixture: MarinaPhase5Fixture
    ) async -> MarinaSharedPipelineRuntimeResult {
        await MarinaSharedPipelineCoordinator().run(
            prompt: prompt,
            context: sharedContext(fixture: fixture)
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func assertSharedTrace(_ trace: MarinaSharedPipelineTrace, prompt: String) {
        #expect(trace.selectedPath != .sharedAttemptedThenLegacyFallback, "Unexpected legacy fallback for \(prompt)")
        #expect(trace.candidateSummary?.isEmpty == false, "Missing candidate trace for \(prompt)")
        #expect(trace.resolverSummary?.isEmpty == false, "Missing resolver trace for \(prompt)")
        #expect(trace.validatorOutcomeSummary?.contains("executable") == true, "Missing validator executable trace for \(prompt)")
        #expect(trace.candidateSummary?.contains("plan=") == true, "Missing executable plan trace for \(prompt)")
        #expect(trace.executorResultSummary?.isEmpty == false, "Missing executor trace for \(prompt)")
        #expect(trace.responseBridgeSummary?.contains("responseShape=") == true, "Missing response shape trace for \(prompt)")
        #expect(trace.responseBridgeSummary?.contains("suggestions=") == true, "Missing suggestion trace for \(prompt)")
    }
}
