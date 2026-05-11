import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct MarinaSharedPipelineParityTests {
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

        for prompt in ["Where is my money going?", "Show my top categories this month"] {
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
