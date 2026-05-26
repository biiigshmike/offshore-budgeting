import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
@Suite(.serialized)
struct MarinaSemanticInterpretationContractTests {
    @Test func registry_promotesOverviewAndBudgetSummaryToExecutableContracts() throws {
        let registry = MarinaSemanticInterpretationContractRegistry.current
        let contractIDs = Set(registry.contracts.map(\.id))
        let requiredCoreIDs: Set<MarinaSemanticInterpretationContractID> = [
            .periodOverview,
            .budgetSummary,
            .spendTotal,
            .entityLookup,
            .savingsStatus,
            .savingsActivity,
            .incomeStatus,
            .reconciliationBalance,
            .budgetLinkedRelationships,
            .plannedExpenseDueRows,
            .categoryRemaining,
            .safeSpendRemaining,
            .transactionActivity,
            .reconciliationActivity,
            .presetDetails
        ]
        #expect(requiredCoreIDs.isSubset(of: contractIDs))

        let overview = try #require(registry.contract(for: .periodOverview))
        #expect(overview.routeKind == .periodOverview)
        #expect(overview.homeMetric == .overview)
        #expect(overview.preferredExecutorRoute == .homeAdapter)

        let budgetSummary = try #require(registry.contract(for: .budgetSummary))
        #expect(budgetSummary.routeKind == .budgetSummary)
        #expect(budgetSummary.requiredEntityTypes == [.budget])
        #expect(budgetSummary.datePolicy == .budgetRange)
        #expect(budgetSummary.preferredExecutorRoute == .composableWorkspace)

        let metricContract = try #require(MarinaMetricContractRegistry.current.contract(for: .periodOverview))
        #expect(metricContract.supportStatus == .executable)
    }

    @Test func freeTextBudgetSummary_usesContractResolverAfterWeakAIEnvelope() async throws {
        let fixture = try makeFixture()
        let juneBudget = Budget(
            name: "June 2026",
            startDate: date(2026, 6, 1),
            endDate: date(2026, 6, 30),
            workspace: fixture.workspace
        )
        fixture.context.insert(juneBudget)
        fixture.context.insert(BudgetCardLink(budget: juneBudget, card: fixture.appleCard))
        fixture.context.insert(VariableExpense(
            descriptionText: "June Groceries",
            amount: 100,
            transactionDate: date(2026, 6, 5),
            workspace: fixture.workspace,
            card: fixture.appleCard,
            category: fixture.groceries
        ))
        fixture.context.insert(PlannedExpense(
            title: "June Rent",
            plannedAmount: 200,
            expenseDate: date(2026, 6, 1),
            workspace: fixture.workspace,
            card: fixture.appleCard,
            category: fixture.groceries,
            sourceBudgetID: juneBudget.id
        ))
        try fixture.context.save()

        let prompt = "How is my June budget looking?"
        let coordinator = MarinaTurnCoordinator(
            availability: AvailableMarinaModel(),
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: [
                prompt: canonicalInterpretation(unsupportedCandidate(prompt: prompt))
            ])
        )

        let result = await coordinator.run(
            prompt: prompt,
            context: turnContext(fixture, budgetNames: ["June 2026"])
        )

        guard case .handled(let answer, _, _, let amountBasis, let route) = result else {
            Issue.record("Expected the semantic contract resolver to run the June budget summary.")
            return
        }

        #expect(answer.title == "June 2026 Budget Summary")
        #expect(answer.primaryValue == "$300.00")
        #expect(answer.rows.contains { $0.title == "Budget period" && $0.value.contains("Jun") })
        #expect(answer.rows.contains { $0.title == "Execution route" && $0.value == "groupedRanked" })
        #expect(amountBasis == .budgetImpact)
        #expect(route?.traceName == "groupedRanked")
    }

    @Test func freeTextPeriodOverview_usesContractResolverForDatedCheckIn() async throws {
        let fixture = try makeFixture()
        fixture.context.insert(VariableExpense(
            descriptionText: "June Spend",
            amount: 80,
            transactionDate: date(2026, 6, 6),
            workspace: fixture.workspace,
            card: fixture.appleCard,
            category: fixture.groceries
        ))
        fixture.context.insert(PlannedExpense(
            title: "June Plan",
            plannedAmount: 120,
            expenseDate: date(2026, 6, 8),
            workspace: fixture.workspace,
            card: fixture.appleCard,
            category: fixture.groceries
        ))
        try fixture.context.save()

        let prompt = "How am I doing for June 2026?"
        let coordinator = MarinaTurnCoordinator(
            availability: AvailableMarinaModel(),
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: [
                prompt: canonicalInterpretation(unsupportedCandidate(prompt: prompt))
            ])
        )

        let result = await coordinator.run(
            prompt: prompt,
            context: turnContext(fixture)
        )

        guard case .handled(let answer, _, let homeQueryPlan, _, let route) = result else {
            Issue.record("Expected the semantic contract resolver to run the period overview.")
            return
        }

        #expect(answer.title == "Budget Overview")
        #expect(answer.primaryValue == "$200.00")
        #expect(homeQueryPlan?.metric == .overview)
        #expect(homeQueryPlan?.query.intent == .periodOverview)
        #expect(route?.traceName == "aggregate")
    }

    @Test func datedCheckInWithSingleMatchingBudget_prefersBudgetSummaryContract() async throws {
        let fixture = try makeFixture()
        let juneBudget = Budget(
            name: "June 2026",
            startDate: date(2026, 6, 1),
            endDate: date(2026, 6, 30),
            workspace: fixture.workspace
        )
        fixture.context.insert(juneBudget)
        fixture.context.insert(BudgetCardLink(budget: juneBudget, card: fixture.appleCard))
        fixture.context.insert(VariableExpense(
            descriptionText: "June Groceries",
            amount: 90,
            transactionDate: date(2026, 6, 5),
            workspace: fixture.workspace,
            card: fixture.appleCard,
            category: fixture.groceries
        ))
        try fixture.context.save()

        let prompt = "How am I doing for June 2026?"
        let coordinator = MarinaTurnCoordinator(
            availability: AvailableMarinaModel(),
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: [
                prompt: canonicalInterpretation(unsupportedCandidate(prompt: prompt))
            ])
        )

        let result = await coordinator.run(
            prompt: prompt,
            context: turnContext(fixture, budgetNames: ["June 2026"])
        )

        guard case .handled(let answer, _, _, _, let route) = result else {
            Issue.record("Expected a matching named budget to win over generic period overview.")
            return
        }

        #expect(answer.title == "June 2026 Budget Summary")
        #expect(answer.primaryValue == "$90.00")
        #expect(route?.traceName == "groupedRanked")
    }

    @Test func budgetSummaryUsesSelectedBudgetInclusiveRangeInsteadOfWholeMentionedMonth() async throws {
        let fixture = try makeFixture()
        let juneBudget = Budget(
            name: "June Sprint",
            startDate: date(2026, 6, 10),
            endDate: date(2026, 6, 20),
            workspace: fixture.workspace
        )
        fixture.context.insert(juneBudget)
        fixture.context.insert(BudgetCardLink(budget: juneBudget, card: fixture.appleCard))
        fixture.context.insert(VariableExpense(
            descriptionText: "Outside Sprint",
            amount: 100,
            transactionDate: date(2026, 6, 5),
            workspace: fixture.workspace,
            card: fixture.appleCard,
            category: fixture.groceries
        ))
        fixture.context.insert(VariableExpense(
            descriptionText: "Inside Sprint",
            amount: 30,
            transactionDate: date(2026, 6, 12),
            workspace: fixture.workspace,
            card: fixture.appleCard,
            category: fixture.groceries
        ))
        try fixture.context.save()

        let prompt = "Show my June budget summary"
        let coordinator = MarinaTurnCoordinator(
            availability: AvailableMarinaModel(),
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: [
                prompt: canonicalInterpretation(unsupportedCandidate(prompt: prompt))
            ])
        )

        let result = await coordinator.run(
            prompt: prompt,
            context: turnContext(fixture, budgetNames: ["June Sprint"])
        )

        guard case .handled(let answer, _, _, _, _) = result else {
            Issue.record("Expected June budget summary to execute through the selected budget contract.")
            return
        }

        #expect(answer.title == "June Sprint Budget Summary")
        #expect(answer.primaryValue == "$30.00")
        #expect(answer.rows.contains { $0.title == "Budget period" && $0.value.contains("Jun 10") && $0.value.contains("Jun 20") })
    }

    @Test func budgetSummaryAmbiguity_returnsExecutableActionChoicesWithoutRawTypeSuffixes() async throws {
        let fixture = try makeFixture()
        let junePersonal = Budget(name: "June 2026", startDate: date(2026, 6, 1), endDate: date(2026, 6, 30), workspace: fixture.workspace)
        let juneTravel = Budget(name: "June Travel", startDate: date(2026, 6, 1), endDate: date(2026, 6, 30), workspace: fixture.workspace)
        fixture.context.insert(junePersonal)
        fixture.context.insert(juneTravel)
        try fixture.context.save()

        let prompt = "Show my June budget summary"
        let coordinator = MarinaTurnCoordinator(
            availability: AvailableMarinaModel(),
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: [
                prompt: canonicalInterpretation(unsupportedCandidate(prompt: prompt))
            ])
        )

        let result = await coordinator.run(
            prompt: prompt,
            context: turnContext(fixture, budgetNames: ["June 2026", "June Travel"])
        )

        guard case .clarification(let answer, let clarification) = result else {
            Issue.record("Expected an executable clarification for ambiguous June budgets.")
            return
        }

        #expect(clarification.choices.count == 2)
        #expect(clarification.choices.allSatisfy { $0.resumeIntent != nil })
        #expect(clarification.choices.contains { $0.title == "Show budget summary: June 2026" })
        #expect(clarification.choices.contains { $0.title.contains("(budget)") } == false)
        #expect(answer.rows.contains { $0.title.contains("(budget)") } == false)
    }

    @Test func foundationGenerationFailureReturnsSafeFailureWithoutPromptStringFallback() async throws {
        let fixture = try makeFixture()
        fixture.context.insert(VariableExpense(
            descriptionText: "June Spend",
            amount: 44,
            transactionDate: date(2026, 6, 4),
            workspace: fixture.workspace,
            card: fixture.appleCard,
            category: fixture.groceries
        ))
        try fixture.context.save()

        let prompt = "How am I doing for June 2026?"
        let diagnostic = MarinaFoundationModelsFailureDiagnostic(
            category: .malformedResponse,
            step: .typedEnvelope,
            debugSummary: "scripted failure"
        )
        let coordinator = MarinaTurnCoordinator(
            availability: AvailableMarinaModel(),
            interpreter: ThrowingCanonicalAIInterpreter(error: MarinaFoundationModelsServiceError.diagnosedGenerationFailure(diagnostic))
        )

        let result = await coordinator.run(
            prompt: prompt,
            context: turnContext(fixture)
        )

        guard case .blocked(let answer, let validationOutcome) = result else {
            Issue.record("Expected Foundation generation failure to stop before deterministic execution.")
            return
        }

        #expect(validationOutcome == nil)
        #expect(answer.title == diagnostic.userTitle)
        #expect(answer.rows.contains { $0.title == "Data safety" })
    }

    private func canonicalInterpretation(
        _ candidate: MarinaQueryPlanCandidate
    ) -> MarinaCanonicalReadInterpretation {
        MarinaCanonicalReadInterpretation(
            result: MarinaSemanticQueryAdapter().interpretationResult(from: candidate),
            compatibilityCandidate: candidate
        )
    }

    private func unsupportedCandidate(prompt: String) -> MarinaQueryPlanCandidate {
        MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: prompt,
            responseShapeHint: .unsupported,
            confidence: .medium,
            unsupportedHint: .unsupportedOperation
        )
    }

    private func turnContext(
        _ fixture: MarinaPhase5Fixture,
        budgetNames: [String] = []
    ) -> MarinaTurnContext {
        MarinaTurnContext(
            provider: fixture.provider,
            routerContext: MarinaInterpretationContext(
                workspaceName: fixture.workspace.name,
                defaultPeriodUnit: .month,
                sessionContext: MarinaSessionContext(),
                priorQueryContext: .empty,
                cardNames: ["Apple Card", "Backup Card"],
                categoryNames: ["Groceries", "Travel"],
                incomeSourceNames: [],
                presetTitles: [],
                budgetNames: budgetNames,
                aliasSummaries: [],
                now: date(2026, 5, 15)
            ),
            defaultPeriodUnit: .month,
            aiEnabled: true,
            now: date(2026, 5, 15)
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }

    private struct AvailableMarinaModel: MarinaModelAvailabilityProviding {
        func currentStatus() -> MarinaModelAvailability.Status { .available }
    }

    private struct ThrowingCanonicalAIInterpreter: MarinaCanonicalAIInterpreting {
        let error: Error

        func interpretCanonical(
            prompt _: String,
            context _: MarinaInterpretationContext
        ) async throws -> MarinaCanonicalReadInterpretation {
            throw error
        }
    }
}
