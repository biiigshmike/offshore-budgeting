import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
@Suite(.serialized)
struct MarinaSemanticPipelineRealAppTests {
    @Test func semanticPipeline_semanticCoveragePromptsReturnHandledWorkspaceCards() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()

        for prompt in Self.semanticWorkspacePrompts {
            let result = await fixture.run(prompt)
            let handled = try requireHandled(result)
            #expect(handled.trace.selectedPath != .sharedAttemptedThenLegacyFallback)
            #expect(handled.answer.kind == .list || handled.answer.kind == .message)
            #expect(answerText(handled.answer).localizedCaseInsensitiveContains("different way") == false)
            #expect(answerText(handled.answer).localizedCaseInsensitiveContains("unsupported") == false)
            #expect(renderedText(handled.aggregationResult).contains("$9,999.00") == false)
            #expect(handled.trace.executorResultSummary?.localizedCaseInsensitiveContains("semanticWorkspace") == true)
        }
    }

    @Test func semanticPipeline_categoryPurchaseListDoesNotRequireRecentQualifier() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("List my cannabis purchases")

        let handled = try requireHandled(result)
        #expect(handled.answer.kind == .list)
        #expect(handled.trace.executorResultSummary?.contains("recentFilteredTransactions") == true)
        #expect(answerText(handled.answer).localizedCaseInsensitiveContains("unsupported") == false)

        guard case .workspaceCard(let card) = handled.aggregationResult else {
            Issue.record("Expected workspace-card purchase rows.")
            return
        }
        assertRows(card, contain: ["NUG Dispensary", "NUG Edibles"])
    }

    @Test func semanticPipeline_explicitMerchantLookbackHandlesNonAmazonMerchant() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("Spend at merchant \"NUG\" last 90 days")

        let handled = try requireHandled(result)
        #expect(handled.answer.kind == .list)
        #expect(handled.trace.executorResultSummary?.localizedCaseInsensitiveContains("semanticWorkspace") == true)
        #expect(answerText(handled.answer).localizedCaseInsensitiveContains("unsupported") == false)
        #expect(renderedText(handled.aggregationResult).contains("$100.00"))
        #expect(renderedText(handled.aggregationResult).contains("$9,999.00") == false)
    }

    @Test func semanticPipeline_aggregateSpendUsesWorkspaceScopedRealData() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("What did I spend on groceries this month?")

        let handled = try requireHandled(result)
        assertSemanticTrace(
            handled.trace,
            operation: "sum",
            subject: "variableExpenses",
            resolved: 1,
            routeContains: "categorySpendTotal"
        )
        assertMayDateRange(handled.trace)
        #expect(handled.answer.kind == .metric)
        #expect(renderedText(handled.aggregationResult).contains("$310.00"))
        #expect(renderedText(handled.aggregationResult).contains("$999.00") == false)
    }

    @Test func semanticPipeline_recentListPreservesEntityDateRouteRowsAndResponseType() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("Show my last 3 groceries expenses this month")

        let handled = try requireHandled(result)
        assertSemanticTrace(
            handled.trace,
            operation: "list",
            subject: "variableExpenses",
            resolved: 1,
            routeContains: "recentFilteredTransactions"
        )
        assertMayDateRange(handled.trace)
        #expect(handled.answer.kind == .list)

        guard case .workspaceCard(let card) = handled.aggregationResult else {
            Issue.record("Expected recent list to use workspace-card route.")
            return
        }
        #expect(card.rows.isEmpty == false)
        #expect(card.rows.contains { $0.label.localizedCaseInsensitiveContains("Whole Foods") })
        #expect(card.rows.allSatisfy { $0.label.localizedCaseInsensitiveContains("Work Whole Foods") == false })
    }

    @Test func semanticPipeline_dateScopedExpenseListExecutesWithoutRecentPhrase() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("List expenses this week")

        let handled = try requireHandled(result)
        assertSemanticTrace(
            handled.trace,
            operation: "list",
            subject: "variableExpenses",
            resolved: 0,
            routeContains: "recentFilteredTransactions"
        )
        #expect(handled.trace.semanticResolverSummary?.contains("primary=2026-05-10") == true)
        #expect(handled.answer.kind == .list)

        guard case .workspaceCard(let card) = handled.aggregationResult else {
            Issue.record("Expected date-scoped expense list to use workspace-card route.")
            return
        }
        #expect(card.rows.isEmpty == false)
        assertRows(card, contain: ["Cafe", "Whole Foods"])
        #expect(renderedText(handled.aggregationResult).localizedCaseInsensitiveContains("Work Whole Foods") == false)
    }

    @Test func semanticPipeline_lastTenExpensesStillUsesListRoute() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("Show my last 10 expenses")

        let handled = try requireHandled(result)
        assertSemanticTrace(
            handled.trace,
            operation: "list",
            subject: "variableExpenses",
            resolved: 0,
            routeContains: "recentFilteredTransactions"
        )
        #expect(handled.answer.kind == .list)
    }

    @Test func semanticPipeline_categoryAvailabilityUsesCategoryLimitMath() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("How much do I have left in Groceries?")

        let handled = try requireHandled(result)
        assertSemanticTrace(
            handled.trace,
            operation: "lookupDetails",
            subject: "budgets",
            resolved: 1,
            routeContains: "categoryAvailability"
        )
        #expect(handled.answer.kind == .list)

        guard case .workspaceCard(let card) = handled.aggregationResult else {
            Issue.record("Expected category availability to use workspace-card route.")
            return
        }
        assertRows(card, contain: ["Groceries Availability", "Remaining", "$190.00", "Max", "$500.00", "Spent", "$310.00"])
    }

    @Test func semanticPipeline_lastBuyLookupReturnsNewestMatchingExpense() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("When did I last buy Starbucks?")

        let handled = try requireHandled(result)
        assertSemanticTrace(
            handled.trace,
            operation: "lookupDetails",
            subject: "variableExpenses",
            resolved: 0,
            routeContains: "databaseLookup"
        )
        #expect(handled.answer.kind == .message || handled.answer.kind == .list)
        #expect(answerText(handled.answer).localizedCaseInsensitiveContains("Starbucks"))
        #expect(answerText(handled.answer).localizedCaseInsensitiveContains("May"))
        #expect(answerText(handled.answer).localizedCaseInsensitiveContains("Apr") == false)
    }

    @Test func semanticPipeline_lookupDetailsUsesDatabaseLookupRoute() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("Show my savings account details")

        let handled = try requireHandled(result)
        assertSemanticTrace(
            handled.trace,
            operation: "lookupDetails",
            subject: "savingsAccounts",
            resolved: 0,
            routeContains: "databaseLookup"
        )
        #expect(handled.answer.kind == .message || handled.answer.kind == .list)
        #expect(renderedText(handled.aggregationResult).localizedCaseInsensitiveContains("Emergency Fund"))
    }

    @Test func semanticPipeline_comparisonPreservesComparisonRangeAndCategoryTarget() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("Compare groceries this month to last month")

        let handled = try requireHandled(result)
        assertSemanticTrace(
            handled.trace,
            operation: "compare",
            subject: "variableExpenses",
            resolved: 1,
            routeContains: "categoryMonthComparison"
        )
        assertMayDateRange(handled.trace)
        #expect(handled.trace.semanticResolverSummary?.contains("comparison=2026-04") == true)
        #expect(handled.answer.kind == .comparison)
        guard case .comparison = handled.aggregationResult else {
            Issue.record("Expected semantic comparison result.")
            return
        }
    }

    @Test func semanticPipeline_incomeSummaryUsesWorkspaceScopedActualAndPlannedIncome() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("What income came in this month?")

        let handled = try requireHandled(result)
        assertSemanticTrace(
            handled.trace,
            operation: "sum",
            subject: "income",
            resolved: 0,
            routeContains: "incomeSummary"
        )
        assertMayDateRange(handled.trace)
        #expect(handled.answer.kind == .list)

        guard case .workspaceCard(let card) = handled.aggregationResult else {
            Issue.record("Expected income summary to use workspace aggregation route.")
            return
        }
        assertRows(card, contain: ["Actual income", "$3,100.00", "Planned income", "$3,000.00"])
        #expect(renderedText(handled.aggregationResult).contains("$9,999.00") == false)
    }

    @Test func semanticPipeline_actualIncomeUsesStatusScopeWithoutTargetLookup() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("What is my actual income this month?")

        let handled = try requireHandled(result)
        assertSemanticTrace(
            handled.trace,
            operation: "sum",
            subject: "income",
            resolved: 0,
            routeContains: "incomeSummary"
        )
        #expect(handled.trace.semanticInterpretationSummary?.contains("incomeStatus=actual") == true)
        #expect(handled.trace.validatorOutcomeSummary?.contains("incomeStatus=actual") == true)
        guard case .workspaceCard(let card) = handled.aggregationResult else {
            Issue.record("Expected actual income to use workspace aggregation.")
            return
        }
        #expect(card.title == "Actual Income")
        #expect(card.primaryValue == "$3,100.00")
        assertRows(card, contain: ["Actual income", "$3,100.00", "Planned income", "$3,000.00", "Gap vs planned"])
    }

    @Test func semanticPipeline_plannedIncomeUsesStatusScopeWithoutTargetLookup() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("What is my planned income this month?")

        let handled = try requireHandled(result)
        assertSemanticTrace(
            handled.trace,
            operation: "sum",
            subject: "income",
            resolved: 0,
            routeContains: "incomeSummary"
        )
        #expect(handled.trace.semanticInterpretationSummary?.contains("incomeStatus=planned") == true)
        guard case .workspaceCard(let card) = handled.aggregationResult else {
            Issue.record("Expected planned income to use workspace aggregation.")
            return
        }
        #expect(card.title == "Planned Income")
        #expect(card.primaryValue == "$3,000.00")
        assertRows(card, contain: ["Actual income", "$3,100.00", "Planned income", "$3,000.00"])
    }

    @Test func semanticPipeline_incomeSoFarShowsSplitSummaryByDefault() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("What is my income so far this month?")

        let handled = try requireHandled(result)
        assertSemanticTrace(
            handled.trace,
            operation: "sum",
            subject: "income",
            resolved: 0,
            routeContains: "incomeSummary"
        )
        guard case .workspaceCard(let card) = handled.aggregationResult else {
            Issue.record("Expected income so far to use workspace aggregation.")
            return
        }
        assertRows(card, contain: ["Income Summary", "Actual income", "$3,100.00", "Planned income", "$3,000.00", "Gap vs planned"])
    }

    @Test func semanticPipeline_actualIncomeFromSourceCombinesStatusAndSourceFilter() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("What actual income came from Salary this month?")

        let handled = try requireHandled(result)
        assertSemanticTrace(
            handled.trace,
            operation: "sum",
            subject: "income",
            resolved: 1,
            routeContains: "incomeSummary"
        )
        guard case .workspaceCard(let card) = handled.aggregationResult else {
            Issue.record("Expected source-filtered income to use workspace aggregation.")
            return
        }
        #expect(card.primaryValue == "$3,100.00")
        assertRows(card, contain: ["Top source", "Salary", "$3,100.00"])
    }

    @Test func semanticPipeline_plannedIncomeEntriesRouteAsRows() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("Show planned income entries this month")

        let handled = try requireHandled(result)
        assertSemanticTrace(
            handled.trace,
            operation: "list",
            subject: "income",
            resolved: 0,
            routeContains: "incomeRows"
        )
        guard case .workspaceCard(let card) = handled.aggregationResult else {
            Issue.record("Expected planned income entries to use workspace rows.")
            return
        }
        #expect(card.title == "Planned Income Entries")
        assertRows(card, contain: ["Salary", "Planned income", "$3,000.00"])
    }

    @Test func semanticPipeline_incomeComparisonPreservesPrimaryAndComparisonRanges() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("Compare income this month to last month.")

        let handled = try requireHandled(result)
        assertSemanticTrace(
            handled.trace,
            operation: "compare",
            subject: "income",
            resolved: 0,
            routeContains: "incomeComparison"
        )
        assertMayDateRange(handled.trace)
        #expect(handled.trace.semanticResolverSummary?.contains("comparison=2026-04") == true)
        #expect(handled.answer.kind == .list)

        guard case .workspaceCard(let card) = handled.aggregationResult else {
            Issue.record("Expected income comparison to use workspace aggregation route.")
            return
        }
        assertRows(card, contain: ["Current period", "$3,100.00", "Previous period", "$450.00", "Change"])
        #expect(renderedText(handled.aggregationResult).contains("$9,999.00") == false)
    }

    @Test func semanticPipeline_presetRankingUsesActiveWorkspacePresets() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("Which presets cost the most?")

        let handled = try requireHandled(result)
        assertSemanticTrace(
            handled.trace,
            operation: "rank",
            subject: "plannedExpenses",
            resolved: 0,
            routeContains: "highestCostPresets"
        )
        #expect(handled.answer.kind == .list)

        guard case .workspaceCard(let card) = handled.aggregationResult else {
            Issue.record("Expected preset ranking to use workspace aggregation route.")
            return
        }
        #expect(card.rows.first?.label == "Rent")
        assertRows(card, contain: ["Rent", "$1,500.00"])
        #expect(renderedText(handled.aggregationResult).contains("$9,999.00") == false)
    }

    @Test func semanticPipeline_plannedExpensesByCategoryPreservesDateRangeAndRows() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("Show planned expenses by category this month.")

        let handled = try requireHandled(result)
        assertSemanticTrace(
            handled.trace,
            operation: "sum",
            subject: "plannedExpenses",
            resolved: 0,
            routeContains: "plannedExpensesByCategory"
        )
        assertMayDateRange(handled.trace)
        #expect(handled.answer.kind == .list)

        guard case .workspaceCard(let card) = handled.aggregationResult else {
            Issue.record("Expected planned-expense category summary to use workspace aggregation route.")
            return
        }
        assertRows(card, contain: ["Dining", "$1,500.00", "Groceries", "$250.00"])
        assertRows(card, contain: ["Travel", "$90.00"])
        #expect(renderedText(handled.aggregationResult).contains("$9,999.00") == false)
    }

    @Test func semanticPipeline_upcomingPlannedExpensesReturnsExecutableRows() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("What are my biggest upcoming bills?")

        let handled = try requireHandled(result)
        assertSemanticTrace(
            handled.trace,
            operation: "rank",
            subject: "plannedExpenses",
            resolved: 0,
            routeContains: "upcomingPlannedExpenses"
        )
        #expect(handled.answer.kind == .list)

        guard case .workspaceCard(let card) = handled.aggregationResult else {
            Issue.record("Expected upcoming planned expenses to use workspace aggregation route.")
            return
        }
        #expect(card.rows.first?.label == "Phone Plan")
        assertRows(card, contain: ["Phone Plan", "$90.00"])
        #expect(card.subtitle?.contains("5/15/26") == true)
        #expect(card.subtitle?.contains("6/14/26") == true)
        #expect(renderedText(handled.aggregationResult).contains("$9,999.00") == false)
    }

    @Test func semanticPipeline_savingsMovementsStayWorkspaceScoped() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("Largest savings movements this month.")

        let handled = try requireHandled(result)
        assertSemanticTrace(
            handled.trace,
            operation: "rank",
            subject: "savingsLedgerEntries",
            resolved: 0,
            routeContains: "largestSavingsMovements"
        )
        assertMayDateRange(handled.trace)
        #expect(handled.answer.kind == .list)

        guard case .workspaceCard(let card) = handled.aggregationResult else {
            Issue.record("Expected savings movements to use workspace aggregation route.")
            return
        }
        assertRows(card, contain: ["Manual savings transfer", "$250.00"])
        #expect(renderedText(handled.aggregationResult).localizedCaseInsensitiveContains("April close") == false)
        #expect(renderedText(handled.aggregationResult).contains("$9,999.00") == false)
    }

    @Test func semanticPipeline_reconciliationBalancesUseAllocationLedgerRows() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("Show shared balances.")

        let handled = try requireHandled(result)
        assertSemanticTrace(
            handled.trace,
            operation: "rank",
            subject: "reconciliationAccounts",
            resolved: 0,
            routeContains: "sharedBalances"
        )
        #expect(handled.answer.kind == .list)

        guard case .workspaceCard(let card) = handled.aggregationResult else {
            Issue.record("Expected shared balances to use workspace aggregation route.")
            return
        }
        assertRows(card, contain: ["Roommate", "$10.00"])
        #expect(renderedText(handled.aggregationResult).contains("$9,999.00") == false)
    }

    @Test func semanticPipeline_userReportedUnsupportedWorkspacePromptsAreHandled() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        fixture.groceryBudgetLimit.maxAmount = 50
        try fixture.context.save()

        let cases: [(prompt: String, expectedFragments: [String])] = [
            ("What budgets do I have this month?", ["Budgets", "May Budget"]),
            ("Which presets are linked to May Budget?", ["Presets linked", "Rent"]),
            ("Which categories are over budget?", ["Categories Over Budget", "Groceries"]),
            ("What planned expenses are due this month?", ["Planned Expenses Due", "Rent"]),
            ("Show income by source.", ["Income by Source", "Salary"]),
            ("How much do I have in savings?", ["Savings"]),
            ("Show savings activity this month.", ["Savings Activity", "Manual savings transfer"]),
            ("What is my Roommate balance?", ["Shared Balances", "Roommate", "$10.00"]),
            ("Which expenses are split with Roommate?", ["Allocations", "Cafe", "Roommate"]),
            ("Show allocations this month.", ["Allocations", "Cafe", "$30.00"]),
            ("What settlements happened this month?", ["Settlements", "Roommate paid back", "$20.00"]),
            ("Which merchants do I spend the most at?", ["Top Merchants"])
        ]

        for testCase in cases {
            let result = await fixture.run(testCase.prompt)
            let handled = try requireHandled(result)
            let text = renderedText(handled.aggregationResult)
            #expect(handled.trace.selectedPath != .sharedAttemptedThenLegacyFallback)
            #expect(text.localizedCaseInsensitiveContains("unsupported") == false)
            for fragment in testCase.expectedFragments {
                #expect(text.localizedCaseInsensitiveContains(fragment), "Expected \(testCase.prompt) to include \(fragment). Text: \(text)")
            }
        }
    }

    @Test func semanticPipeline_step5PhraseCapabilityVariantsStayOnSharedReadOnlyRoutes() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        fixture.groceryBudgetLimit.maxAmount = 50
        try fixture.context.save()

        let cases: [(prompt: String, routeFragment: String?, routeIntent: String?, expectedFragments: [String])] = [
            ("Which cards are in May Budget?", "budgetLinkedCards", "budgetLinkedCards", ["Cards linked", "Apple"]),
            ("Show May Budget presets", "budgetLinkedPresets", "budgetLinkedPresets", ["Presets linked", "Rent"]),
            ("Show category limits for May Budget", "budgetCategoryLimits", "budgetCategoryLimits", ["Category limits", "Groceries"]),
            ("How much have I saved?", nil, "savingsStatus", ["Savings"]),
            ("Show split expenses with Roommate this month", "allocationRows", "allocationRows", ["Allocations", "Cafe", "Roommate"]),
            ("When did Roommate last pay me back?", "settlementRows", "settlementRows", ["Settlements", "Roommate paid back", "$20.00"])
        ]

        for testCase in cases {
            let handled = try requireHandled(await fixture.run(testCase.prompt))
            let text = renderedText(handled.aggregationResult)
            #expect(handled.trace.selectedPath != .sharedAttemptedThenLegacyFallback)
            if let routeFragment = testCase.routeFragment {
                #expect(
                    handled.trace.executorResultSummary?.localizedCaseInsensitiveContains(routeFragment) == true,
                    "Expected \(testCase.prompt) executor summary to include \(routeFragment). Summary: \(handled.trace.executorResultSummary ?? "nil")"
                )
            }
            if let routeIntent = testCase.routeIntent {
                #expect(
                    handled.trace.candidateSummary?.localizedCaseInsensitiveContains("routeIntent=\(routeIntent)") == true,
                    "Expected \(testCase.prompt) candidate summary to include routeIntent=\(routeIntent). Summary: \(handled.trace.candidateSummary ?? "nil")"
                )
            }
            #expect(text.localizedCaseInsensitiveContains("unsupported") == false)
            for fragment in testCase.expectedFragments {
                #expect(text.localizedCaseInsensitiveContains(fragment), "Expected \(testCase.prompt) to include \(fragment). Text: \(text)")
            }
        }
    }

    @Test func semanticPipeline_step5MutationPromptsDoNotExecuteSharedReadOrMutateData() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let before = counts(in: fixture)
        let prompts = [
            "create settlement with Roommate for $20",
            "mark Roommate paid",
            "move this to savings",
            "add allocation for Roommate",
            "delete allocation",
            "add preset Rent"
        ]

        for prompt in prompts {
            let result = await fixture.run(prompt)

            guard case .validationBlocked(_, let outcome, let trace) = result else {
                Issue.record("Expected \(prompt) to be blocked before shared read execution. Trace: \(result.trace.compactSummary)")
                continue
            }
            guard case .unsupported = outcome else {
                Issue.record("Expected \(prompt) to produce typed unsupported.")
                continue
            }
            #expect(trace.executorResultSummary == nil)
            #expect(trace.selectedPath != .sharedAttemptedThenLegacyFallback)
            #expect(counts(in: fixture) == before, "Expected \(prompt) not to mutate seeded data.")
        }
    }

    @Test func semanticPipeline_budgetImpactSimulationIncludesCategoryLimitWithoutFallback() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("If I spend $80 on Groceries this month, how will that affect my budget?")

        let handled = try requireHandled(result)
        assertSemanticTrace(
            handled.trace,
            operation: "simulate",
            subject: "budgets",
            resolved: 1,
            routeContains: "simulation"
        )
        assertMayDateRange(handled.trace)
        #expect(handled.answer.kind == .list)
        #expect(handled.homeQueryPlan == nil)
        #expect(handled.trace.selectedPath != .sharedAttemptedThenLegacyFallback)

        guard case .workspaceCard(let card) = handled.aggregationResult else {
            Issue.record("Expected budget simulation to use composable workspace route.")
            return
        }
        assertRows(card, contain: ["Category limit", "$500.00", "Groceries"])
    }

    @Test func semanticPipeline_budgetLimitStatusStaysTypedUnsupportedWithoutBroadFallback() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("Is Groceries over where it should be for this budget?")

        guard case .validationBlocked(let answer, let outcome, let trace) = result else {
            Issue.record("Expected category budget limit status to stay blocked: \(result.trace.compactSummary)")
            return
        }
        guard case .unsupported(let unsupported) = outcome else {
            Issue.record("Expected typed unsupported budget-limit outcome.")
            return
        }
        #expect(answer.kind == .message)
        #expect(unsupported.kind == .unsupportedCombination)
        #expect(unsupported.candidate?.measure == .remainingBudget)
        #expect(unsupported.candidate?.operation == .compare)
        #expect(unsupported.candidate?.entityMentions.first?.typeHint == .category)
        #expect(trace.validatorOutcomeSummary?.contains("unsupported") == true)
        #expect(trace.executorResultSummary == nil)
        #expect(trace.responseBridgeSummary?.contains("kind=message") == true)
        #expect(trace.selectedPath != .sharedAttemptedThenLegacyFallback)
    }

    @Test func semanticPipeline_rankedBreakdownRoutesThroughGroupedResponse() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("Break down my spending by category this month")

        let handled = try requireHandled(result)
        assertSemanticTrace(
            handled.trace,
            operation: "rank",
            subject: "variableExpenses",
            resolved: 0,
            routeContains: "topCategories"
        )
        #expect(handled.answer.kind == .list)
        guard case .groupedBreakdown(let list) = handled.aggregationResult else {
            Issue.record("Expected grouped breakdown result.")
            return
        }
        #expect(list.rows.contains { $0.label.localizedCaseInsensitiveContains("Groceries") })
    }

    @Test func semanticPipeline_broadSpendPromptsExecuteWithoutClarificationLoops() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let prompts = [
            "What did I spend this month?",
            "What did I spend last month?",
            "What did I spend last week?",
            "What did I spend today?"
        ]

        for prompt in prompts {
            let result = await fixture.run(prompt)
            let handled = try requireHandled(result)
            assertSemanticTrace(
                handled.trace,
                operation: "sum",
                subject: "variableExpenses",
                resolved: 0,
                routeContains: "spendTotal"
            )
            #expect(handled.answer.kind == .metric)
            #expect(handled.homeQueryPlan?.metric == .spendTotal)
            #expect(handled.trace.validatorOutcomeSummary?.contains("clarification") != true)
        }
    }

    @Test func semanticPipeline_sequentialFreshTurnsDoNotInheritPriorContext() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let coordinator = MarinaSharedPipelineCoordinator()

        let first = try requireHandled(
            await coordinator.run(
                prompt: "What did I spend this week?",
                context: fixture.sharedPipelineContext()
            )
        )
        #expect(first.answer.kind == .metric)
        #expect(first.answer.title == "Spend This Week")

        let prior = MarinaPriorQueryContext(
            lastQueryPlan: first.homeQueryPlan,
            lastMetric: first.homeQueryPlan?.metric,
            lastTargetName: first.homeQueryPlan?.targetName,
            lastTargetType: nil,
            lastDateRange: first.homeQueryPlan?.dateRange,
            lastResultLimit: first.homeQueryPlan?.resultLimit,
            lastPeriodUnit: first.homeQueryPlan?.periodUnit
        )

        let second = try requireHandled(
            await coordinator.run(
                prompt: "What did I spend last month?",
                context: fixture.sharedPipelineContext(
                    turnClassification: .freshQuestion,
                    priorQueryContext: prior
                )
            )
        )
        #expect(second.answer.kind == .metric)
        #expect(second.answer.title == "Spend Last Month")
        #expect(second.trace.turnClassification == .freshQuestion)
        #expect(second.trace.priorContextIncluded == false)

        let third = try requireHandled(
            await coordinator.run(
                prompt: "What did I spend this week?",
                context: fixture.sharedPipelineContext(
                    turnClassification: .freshQuestion,
                    priorQueryContext: prior
                )
            )
        )
        #expect(third.answer.kind == .metric)
        #expect(third.answer.title == "Spend This Week")
        #expect(third.trace.turnClassification == .freshQuestion)
        #expect(third.trace.priorContextIncluded == false)
    }

    @Test func semanticPipeline_compareToLastMonthFollowUpAnchorsTopCategoryRow() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let coordinator = MarinaSharedPipelineCoordinator()

        let first = try requireHandled(
            await coordinator.run(
                prompt: "Where did my money go this month?",
                context: fixture.sharedPipelineContext()
            )
        )
        let topCategory: String?
        switch first.aggregationResult {
        case .rankedList(let list), .groupedBreakdown(let list):
            topCategory = list.rows.first?.label
        default:
            topCategory = nil
        }
        guard let topCategory else {
            Issue.record("Expected a ranked category answer with rows.")
            return
        }

        let prior = MarinaPriorQueryContext(
            lastQueryPlan: first.homeQueryPlan,
            lastMetric: first.homeQueryPlan?.metric,
            lastTargetName: topCategory,
            lastTargetType: .category,
            lastDateRange: first.homeQueryPlan?.dateRange,
            lastResultLimit: first.homeQueryPlan?.resultLimit,
            lastPeriodUnit: first.homeQueryPlan?.periodUnit
        )

        let second = try requireHandled(
            await coordinator.run(
                prompt: "Compare to last month",
                context: fixture.sharedPipelineContext(
                    turnClassification: .followUp,
                    priorQueryContext: prior
                )
            )
        )

        #expect(second.answer.kind == .comparison)
        #expect(second.trace.turnClassification == .followUp)
        #expect(second.trace.priorContextIncluded == true)
        #expect(second.trace.semanticResolverSummary?.contains("resolvedTypes=category") == true)
        #expect(renderedText(second.aggregationResult).localizedCaseInsensitiveContains(topCategory))
    }

    @Test func semanticPipeline_cardMerchantCollisionClarifiesWithoutExecuting() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("What did I spend on Apple this month?")

        guard case .validationBlocked(let answer, let outcome, let trace) = result else {
            Issue.record("Expected Apple card/merchant collision to clarify: \(result.trace.compactSummary)")
            return
        }
        guard case .clarification(let clarification) = outcome else {
            Issue.record("Expected typed clarification for Apple collision.")
            return
        }
        #expect(answer.kind == .message)
        #expect(clarification.kind == .ambiguousTarget)
        #expect(clarification.choices.compactMap(\.entityTypeHint).contains(.card))
        #expect(clarification.choices.compactMap(\.entityTypeHint).contains(.merchant))
        #expect(clarification.choices.first(where: { $0.title == "Apple Watch" })?.entityTypeHint == .expense)
        #expect(clarification.choices.first?.entityTypeHint == .card)
        #expect(trace.semanticResolverSummary?.contains("ambiguous=1") == true)
        #expect(trace.executorResultSummary == nil)
    }

    @Test func semanticPipeline_bareAppleClarifiesAcrossCategoryMerchantExpenseAndCard() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        fixture.context.insert(Category(name: "Apple", hexColor: "#111111", workspace: fixture.workspace))
        try fixture.context.save()

        let result = await fixture.run("What did I spend at Apple?")

        guard case .validationBlocked(_, let outcome, let trace) = result,
              case .clarification(let clarification) = outcome else {
            Issue.record("Expected Apple cross-entity collision to clarify: \(result.trace.compactSummary)")
            return
        }

        let choiceTypes = Set(clarification.choices.compactMap(\.entityTypeHint))
        #expect(choiceTypes.contains(.card))
        #expect(choiceTypes.contains(.category))
        #expect(choiceTypes.contains(.merchant))
        #expect(choiceTypes.contains(.expense))
        #expect(trace.semanticResolverSummary?.contains("ambiguous=1") == true)
        #expect(trace.semanticResolverSummary?.contains("ambiguousTypes=") == true)
        #expect(trace.executorResultSummary == nil)
    }

    @Test func semanticPipeline_scenarioExecutesThroughWhatIfRouteWithoutBroadFallback() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("If I spend $80 on dining, how does that affect savings?")

        let handled = try requireHandled(result)
        assertSemanticTrace(
            handled.trace,
            operation: "simulate",
            subject: "budgets",
            resolved: 1,
            routeContains: "simulation"
        )
        #expect(handled.answer.kind == .list)
        #expect(handled.homeQueryPlan == nil)
        #expect(renderedText(handled.aggregationResult).localizedCaseInsensitiveContains("what-if"))
        #expect(handled.trace.selectedPath != .sharedAttemptedThenLegacyFallback)
    }

    @Test func semanticPipeline_clarificationChoicePatchesPendingRequestAndExecutes() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("What did I spend on Apple this month?")

        guard case .validationBlocked(_, let outcome, _) = result,
              case .clarification(let clarification) = outcome,
              let cardChoice = clarification.choices.first(where: { $0.entityTypeHint == .card }) else {
            Issue.record("Expected Apple clarification with a card choice.")
            return
        }

        let resumed = await MarinaSharedPipelineCoordinator().resume(
            clarification: clarification,
            choice: cardChoice,
            context: fixture.contextForSharedPipeline
        )

        let handled = try requireHandled(resumed)
        #expect(handled.answer.kind == .metric)
        #expect(handled.trace.semanticResolverSummary?.contains("resolved=1") == true)
        #expect(handled.trace.compactSummary.contains("cardSpendTotal") || handled.trace.executorResultSummary?.contains("cardSpendTotal") == true)
        #expect(renderedText(handled.aggregationResult).contains("$1,885.00"))
    }

    @Test func semanticPipeline_clarificationChoiceCanExecuteMerchantSpend() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("What did I spend at Apple?")

        guard case .validationBlocked(_, let outcome, _) = result,
              case .clarification(let clarification) = outcome,
              let merchantChoice = clarification.choices.first(where: { $0.entityTypeHint == .merchant }) else {
            Issue.record("Expected Apple clarification with a merchant choice.")
            return
        }

        let resumed = await MarinaSharedPipelineCoordinator().resume(
            clarification: clarification,
            choice: merchantChoice,
            context: fixture.contextForSharedPipeline
        )

        let handled = try requireHandled(resumed)
        #expect(handled.answer.kind == .metric)
        #expect(renderedText(handled.aggregationResult).localizedCaseInsensitiveContains("Merchant Spend"))
        #expect(renderedText(handled.aggregationResult).contains("$120.00"))
    }

    @Test func semanticPipeline_clarificationChoiceCanAdaptExpenseToLookupDetail() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("What did I spend at Apple?")

        guard case .validationBlocked(_, let outcome, _) = result,
              case .clarification(let clarification) = outcome else {
            Issue.record("Expected Apple clarification with an expense choice.")
            return
        }
        let expenseChoice = clarification.choices.first(where: { $0.title == "Apple Watch" && $0.entityTypeHint == .expense })
        guard let expenseChoice else {
            Issue.record("Expected Apple clarification with an expense choice.")
            return
        }

        let resumed = await MarinaSharedPipelineCoordinator().resume(
            clarification: clarification,
            choice: expenseChoice,
            context: fixture.contextForSharedPipeline
        )

        let handled = try requireHandled(resumed)
        assertSemanticTrace(
            handled.trace,
            operation: "lookupDetails",
            subject: "variableExpenses",
            resolved: 1,
            routeContains: "databaseLookup"
        )
        #expect(handled.answer.kind == .message || handled.answer.kind == .list)
        #expect(answerText(handled.answer).localizedCaseInsensitiveContains("Apple"))
    }

    @Test func semanticPipeline_clarificationChoiceCanExecuteCategorySpend() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let appleCategory = Category(name: "Apple", hexColor: "#111111", workspace: fixture.workspace)
        fixture.context.insert(appleCategory)
        fixture.context.insert(VariableExpense(
            descriptionText: "Apple Category Item",
            amount: 44,
            transactionDate: MarinaRealisticWorkspaceFixture.date(2026, 5, 13),
            workspace: fixture.workspace,
            card: fixture.appleCard,
            category: appleCategory
        ))
        try fixture.context.save()

        let result = await fixture.run("What did I spend at Apple?")

        guard case .validationBlocked(_, let outcome, _) = result,
              case .clarification(let clarification) = outcome,
              let categoryChoice = clarification.choices.first(where: { $0.title == "Apple" && $0.entityTypeHint == .category }) else {
            Issue.record("Expected Apple clarification with a category choice.")
            return
        }

        let resumed = await MarinaSharedPipelineCoordinator().resume(
            clarification: clarification,
            choice: categoryChoice,
            context: fixture.contextForSharedPipeline
        )

        let handled = try requireHandled(resumed)
        #expect(handled.answer.kind == .metric)
        #expect(handled.trace.semanticResolverSummary?.contains("resolvedTypes=category") == true)
        #expect(renderedText(handled.aggregationResult).localizedCaseInsensitiveContains("Category Spend"))
    }

    @Test func semanticPipeline_databaseLookupAmbiguitySurfacesTypedClarificationAndResumes() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("Show Groceries.")

        guard case .validationBlocked(let answer, let outcome, let trace) = result,
              case .clarification(let clarification) = outcome else {
            Issue.record("Expected Groceries lookup ambiguity to surface typed clarification: \(result.trace.compactSummary)")
            return
        }

        #expect(answer.title.localizedCaseInsensitiveContains("Groceries"))
        #expect(clarification.kind == .ambiguousTarget)
        #expect(clarification.choices.compactMap(\.entityTypeHint).contains(.category))
        #expect(clarification.choices.compactMap(\.entityTypeHint).contains(.expense))
        #expect(trace.executorResultSummary?.contains("ambiguityCount") == true)

        guard let categoryChoice = clarification.choices.first(where: { $0.entityTypeHint == .category }) else {
            Issue.record("Expected a category clarification choice.")
            return
        }

        let resumed = await MarinaSharedPipelineCoordinator().resume(
            clarification: clarification,
            choice: categoryChoice,
            context: fixture.contextForSharedPipeline
        )

        let handled = try requireHandled(resumed)
        #expect(answerText(handled.answer).localizedCaseInsensitiveContains("Groceries"))
        #expect(answerText(handled.answer).localizedCaseInsensitiveContains("Category"))
    }

    @Test func semanticPipeline_tellMeAboutAppleLookupAmbiguityProvidesChipChoices() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("Tell me about Apple")

        guard case .validationBlocked(_, let outcome, _) = result,
              case .clarification(let clarification) = outcome else {
            Issue.record("Expected Apple lookup ambiguity to surface typed clarification: \(result.trace.compactSummary)")
            return
        }

        let choiceTypes = Set(clarification.choices.compactMap(\.entityTypeHint))
        #expect(choiceTypes.contains(.card))
        #expect(choiceTypes.contains(.expense) || choiceTypes.contains(.merchant))
        #expect(clarification.choices.isEmpty == false)
    }

    @Test func semanticPipeline_explicitAppleStoreTargetExecutesMerchantSpendDirectly() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("What did I spend at Apple Store?")

        let handled = try requireHandled(result)
        #expect(handled.answer.kind == .metric)
        #expect(handled.trace.semanticResolverSummary?.contains("resolved=1") == true)
        #expect(handled.trace.semanticResolverSummary?.contains("ambiguous=0") == true)
        #expect(renderedText(handled.aggregationResult).localizedCaseInsensitiveContains("Merchant Spend"))
    }

    @Test func semanticPipeline_comparisonDateFollowUpPatchesPendingSemanticQuery() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let result = await fixture.run("Compare groceries this month")

        guard case .validationBlocked(_, let outcome, _) = result,
              case .clarification(let clarification) = outcome else {
            Issue.record("Expected missing comparison date clarification.")
            return
        }
        #expect(clarification.patchSlot == .comparison)
        #expect(clarification.pendingSemanticQuery?.operation == .compare)
        #expect(clarification.pendingSemanticQuery?.filters.first?.value.localizedCaseInsensitiveContains("groceries") == true)

        let resumed = await MarinaSharedPipelineCoordinator().resume(
            clarification: clarification,
            choice: MarinaClarificationChoice(title: "last month", patchSlot: .comparison, rawValue: "last month"),
            context: fixture.contextForSharedPipeline
        )

        let handled = try requireHandled(resumed)
        #expect(handled.trace.semanticResolverSummary?.contains("resolved=1") == true)
        #expect(handled.trace.semanticResolverSummary?.contains("comparison=2026-04") == true)
        #expect(handled.answer.kind == .comparison)
        guard case .comparison = handled.aggregationResult else {
            Issue.record("Expected resumed comparison result.")
            return
        }
    }

    private struct HandledResult {
        let answer: HomeAnswer
        let aggregationResult: MarinaAggregationResult
        let homeQueryPlan: HomeQueryPlan?
        let trace: MarinaSharedPipelineTrace
    }

    private struct EntityCounts: Equatable {
        let savingsAccounts: Int
        let savingsLedgerEntries: Int
        let allocationAccounts: Int
        let allocations: Int
        let settlements: Int
        let presets: Int
        let budgets: Int
        let plannedExpenses: Int
        let variableExpenses: Int
    }

    private func counts(in fixture: MarinaRealisticWorkspaceFixture) -> EntityCounts {
        EntityCounts(
            savingsAccounts: fixture.provider.fetchAllSavingsAccounts().count,
            savingsLedgerEntries: fixture.provider.fetchAllSavingsLedgerEntries().count,
            allocationAccounts: fixture.provider.fetchAllAllocationAccounts().count,
            allocations: fixture.provider.fetchAllExpenseAllocations().count,
            settlements: fixture.provider.fetchAllAllocationSettlements().count,
            presets: fixture.provider.fetchAllPresets().count,
            budgets: fixture.provider.fetchAllBudgets().count,
            plannedExpenses: fixture.provider.fetchAllPlannedExpenses().count,
            variableExpenses: fixture.provider.fetchAllVariableExpenses().count
        )
    }

    private func requireHandled(_ result: MarinaSharedPipelineRuntimeResult) throws -> HandledResult {
        guard case .handled(let answer, let aggregationResult, let homeQueryPlan, let trace) = result else {
            throw TestFailure(message: "Expected handled result, got \(result.trace.compactSummary)")
        }
        return HandledResult(
            answer: answer,
            aggregationResult: aggregationResult,
            homeQueryPlan: homeQueryPlan,
            trace: trace
        )
    }

    private func assertSemanticTrace(
        _ trace: MarinaSharedPipelineTrace,
        operation: String,
        subject: String,
        resolved: Int,
        routeContains: String
    ) {
        #expect(trace.selectedPath == .sharedHeuristic || trace.selectedPath == .sharedFoundationModels)
        #expect(trace.semanticInterpretationSummary?.contains("query") == true)
        #expect(trace.semanticInterpretationSummary?.contains("operation=\(operation)") == true)
        #expect(trace.semanticInterpretationSummary?.contains("subject=\(subject)") == true)
        #expect(trace.semanticResolverSummary?.contains("resolved=\(resolved)") == true)
        #expect(trace.validatorOutcomeSummary?.contains("executable") == true)
        #expect(trace.executorResultSummary?.contains("route=") == true)
        #expect(trace.executorResultSummary?.contains("amountBasis=") == true)
        #expect(trace.compactSummary.contains(routeContains) || trace.executorResultSummary?.contains(routeContains) == true)
        #expect(trace.responseBridgeSummary?.contains("responseShape=") == true)
    }

    private func assertMayDateRange(_ trace: MarinaSharedPipelineTrace) {
        #expect(trace.semanticResolverSummary?.contains("primary=2026-05") == true)
    }

    private func assertRows(_ card: MarinaWorkspaceAggregationCard, contain expectedFragments: [String]) {
        let text = ([card.title, card.subtitle, card.primaryValue] + card.rows.flatMap { [$0.label, $0.value] }).compactMap { $0 }.joined(separator: " ")
        for fragment in expectedFragments {
            #expect(text.localizedCaseInsensitiveContains(fragment))
        }
        #expect(card.rows.isEmpty == false)
    }

    private func renderedText(_ result: MarinaAggregationResult) -> String {
        switch result {
        case .scalar(let scalar):
            return ([scalar.title, scalar.renderedValue] + scalar.rows.flatMap { [$0.label, $0.renderedValue] }).compactMap { $0 }.joined(separator: " ")
        case .comparison(let comparison):
            return [
                comparison.title,
                comparison.primaryLabel,
                comparison.primaryRenderedValue,
                comparison.comparisonLabel,
                comparison.comparisonRenderedValue,
                comparison.deltaRenderedValue
            ].compactMap { $0 }.joined(separator: " ")
        case .rankedList(let list), .groupedBreakdown(let list):
            return ([list.title, list.primaryRenderedValue] + list.rows.flatMap { [$0.label, $0.renderedValue] }).compactMap { $0 }.joined(separator: " ")
        case .message(let message):
            return [message.title, message.message].compactMap { $0 }.joined(separator: " ")
        case .noData(let noData):
            return [noData.title, noData.message].joined(separator: " ")
        case .unsupported(let unsupported):
            return unsupported.message
        case .workspaceCard(let card):
            return ([card.title, card.subtitle, card.primaryValue] + card.rows.flatMap { [$0.label, $0.value] }).compactMap { $0 }.joined(separator: " ")
        }
    }

    private func answerText(_ answer: HomeAnswer) -> String {
        ([answer.title, answer.subtitle, answer.primaryValue] + answer.rows.flatMap { [$0.title, $0.value] }).compactMap { $0 }.joined(separator: " ")
    }

    private struct TestFailure: Error {
        let message: String
    }

    private static let semanticWorkspacePrompts: [String] = [
        "spend groceries Mar 2026 vs Mar 2025",
        "average groceries per week last quarter",
        "total spend card Amex Platinum in Q1 2026",
        "income from \"Acme Dental\" Jan-Mar 2026",
        "top 5 categories by spend last 30 days",
        "percent of spending that was groceries in April",
        "largest transaction this month",
        "median variable expense last year",
        "planned vs actual dining May 2026",
        "savings: actual vs target YTD",
        "total refunds last month",
        "spend at merchant \"Amazon\" last 90 days",
        "spend at merchants containing \"amazon\" last 90 days",
        "uncategorized spend this week",
        "average daily spend in March 2026",
        "rolling 7-day spend ending Apr 15, 2026",
        "card \"Visa - Blue\" share of spend in 2025",
        "income seasonality: Mar 2026 vs Mar 2025",
        "category groceries day-of-week average (last 12 weeks)",
        "budget \"Travel 2026\" remaining this month",
        "top merchants by count this quarter",
        "transactions over $250 in February",
        "first purchase of \"Litter Robot\" ever",
        "time to next planned expense for budget \"Home\"",
        "workspace \"Personal\" total spend YTD vs \"Business\"",
        "category \"Utilities\" month-over-month change (Apr -> May 2026)",
        "net cash flow last pay period",
        "average tip percentage dining last 60 days",
        "spend in \"Q2 2026 to date\" vs \"same days Q2 2025\"",
        "number of transactions with note containing \"reconcile\"",
        "card \"Cash\" vs \"Visa - Blue\" refunds YTD",
        "average planned expense slip (actual - planned) last quarter",
        "categories with zero spend last month",
        "top 3 categories by variance (planned vs actual) this month",
        "recurring merchants detected in May 2026",
        "total spend \"last weekend\"",
        "budget \"Groceries Weekly\" over/under for week of May 11, 2026",
        "savings ledger entries between Apr 1-15, 2026",
        "forecast: average weekly spend next 4 weeks (baseline = last 8)"
    ]
}
