import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct MarinaAggregationExecutorTests {
    @Test func executor_broadCategoryAndCardSpendReturnScalarResults() throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let executor = MarinaAggregationExecutor()
        let range = monthRange()

        let broad = executor.execute(try executable(MarinaAggregationPlan(operation: .sum, measure: .spend, dateRange: range)), provider: fixture.provider, now: date(2026, 5, 15))
        let category = executor.execute(try executable(MarinaAggregationPlan(operation: .sum, measure: .spend, targets: [target(.category, "Groceries")], dateRange: range)), provider: fixture.provider, now: date(2026, 5, 15))
        let card = executor.execute(try executable(MarinaAggregationPlan(operation: .sum, measure: .spend, targets: [target(.card, "Apple Card")], dateRange: range)), provider: fixture.provider, now: date(2026, 5, 15))

        assertScalar(broad, containsDigits: "600")
        assertScalar(category, containsDigits: "300")
        assertScalar(card, containsDigits: "500")
    }

    @Test func executor_incomeAverageReturnsScalarResult() throws {
        let fixture = try makeFixture()
        try fixture.seedIncomeData()
        let plan = MarinaAggregationPlan(
            operation: .average,
            measure: .income,
            dateRange: HomeQueryDateRange(startDate: date(2026, 1, 1), endDate: date(2026, 3, 31))
        )

        let result = MarinaAggregationExecutor().execute(try executable(plan), provider: fixture.provider, now: date(2026, 3, 20))

        assertScalar(result, containsDigits: "2200")
    }

    @Test func executor_comparisonPreservesPrimaryAndComparisonValues() throws {
        let fixture = try makeFixture()
        try fixture.seedComparisonData()
        let primary = HomeQueryDateRange(startDate: date(2026, 5, 1), endDate: date(2026, 5, 31))
        let comparison = HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30))
        let plan = MarinaAggregationPlan(
            operation: .compare,
            measure: .spend,
            targets: [target(.category, "Groceries")],
            dateRange: primary,
            comparisonDateRange: comparison,
            responseShape: .comparison
        )

        let result = MarinaAggregationExecutor().execute(try executable(plan), provider: fixture.provider, now: date(2026, 5, 15))

        guard case .comparison(let comparisonResult) = result else {
            Issue.record("Expected comparison result.")
            return
        }
        #expect(comparisonResult.primaryRenderedValue.filter(\.isNumber).contains("300"))
        #expect(comparisonResult.comparisonRenderedValue.filter(\.isNumber).contains("100"))
    }

    @Test func executor_rankedAndGroupedResultsPreserveRowsAndPercentages() throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let range = monthRange()
        let rankingPlan = MarinaAggregationPlan(
            operation: .rank,
            measure: .spend,
            dateRange: range,
            grouping: MarinaGroupingCandidate(dimension: .category),
            ranking: MarinaRankingCandidate(direction: .top, limit: 3),
            limit: 3,
            responseShape: .rankedList
        )
        let sharePlan = MarinaAggregationPlan(
            operation: .sum,
            measure: .categoryShare,
            dateRange: range,
            responseShape: .groupedBreakdown
        )
        let executor = MarinaAggregationExecutor()

        let ranking = executor.execute(try executable(rankingPlan), provider: fixture.provider, now: date(2026, 5, 15))
        let share = executor.execute(try executable(sharePlan), provider: fixture.provider, now: date(2026, 5, 15))

        guard case .rankedList(let ranked) = ranking else {
            Issue.record("Expected ranked list result.")
            return
        }
        #expect(ranked.rows.contains(where: { $0.label == "Groceries" }))

        guard case .groupedBreakdown(let grouped) = share else {
            Issue.record("Expected grouped breakdown result.")
            return
        }
        #expect(grouped.rows.contains(where: { $0.label == "Groceries" && $0.renderedValue.contains("%") && $0.percentage != nil }))
    }

    @Test func executor_unsupportedPlansReturnTypedUnsupported() throws {
        let fixture = try makeFixture()
        let simulation = MarinaPlanValidationOutcome.executable(
            MarinaAggregationPlan(operation: .simulate, measure: .remainingBudget)
        )
        let incomeTotal = MarinaPlanValidationOutcome.executable(
            MarinaAggregationPlan(operation: .sum, measure: .income)
        )
        let targetedAverage = MarinaPlanValidationOutcome.executable(
            MarinaAggregationPlan(operation: .average, measure: .spend, targets: [target(.category, "Groceries")])
        )
        let executor = MarinaAggregationExecutor()

        assertUnsupported(executor.execute(outcome: simulation, provider: fixture.provider))
        assertUnsupported(executor.execute(outcome: incomeTotal, provider: fixture.provider))
        assertUnsupported(executor.execute(outcome: targetedAverage, provider: fixture.provider))
    }

    @Test func workspaceExecutor_incomeSummaryRankingAndComparisonUseActualIncome() throws {
        let fixture = try makeFixture()
        fixture.context.insert(Income(source: "Salary", amount: 2_500, date: date(2026, 5, 5), isPlanned: false, workspace: fixture.workspace))
        fixture.context.insert(Income(source: "Side Gig", amount: 700, date: date(2026, 5, 12), isPlanned: false, workspace: fixture.workspace))
        fixture.context.insert(Income(source: "Salary", amount: 2_300, date: date(2026, 4, 5), isPlanned: false, workspace: fixture.workspace))
        fixture.context.insert(Income(source: "Expected Bonus", amount: 900, date: date(2026, 5, 20), isPlanned: true, workspace: fixture.workspace))
        try fixture.context.save()

        let executor = MarinaWorkspaceAggregationExecutor(calendar: Calendar(identifier: .gregorian))
        let may = monthRange()
        let april = HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30))

        let summary = handledCard(executor.execute(
            plan: MarinaAggregationPlan(operation: .sum, measure: .income, dateRange: may),
            provider: fixture.provider,
            now: date(2026, 5, 15)
        ))
        #expect(summary.primaryValue?.filter(\.isNumber).contains("3200") == true)
        #expect(summary.rows.contains(where: { $0.label == "Planned income" && $0.value.filter(\.isNumber).contains("900") }))

        let ranking = handledCard(executor.execute(
            plan: MarinaAggregationPlan(
                operation: .rank,
                measure: .income,
                dateRange: may,
                grouping: MarinaGroupingCandidate(dimension: .incomeSource),
                ranking: MarinaRankingCandidate(direction: .top, limit: 2)
            ),
            provider: fixture.provider,
            now: date(2026, 5, 15)
        ))
        #expect(ranking.rows.first?.label == "Salary")

        let comparison = handledCard(executor.execute(
            plan: MarinaAggregationPlan(operation: .compare, measure: .income, dateRange: may, comparisonDateRange: april),
            provider: fixture.provider,
            now: date(2026, 5, 15)
        ))
        #expect(comparison.rows.contains(where: { $0.label == "Change" && $0.value.contains("Up") }))
    }

    @Test func workspaceExecutor_plannedExpenseAndPresetAggregationsReturnSummaryCards() throws {
        let fixture = try makeFixture()
        fixture.context.insert(Preset(title: "Rent", plannedAmount: 1_500, workspace: fixture.workspace, defaultCard: fixture.appleCard, defaultCategory: fixture.groceries))
        fixture.context.insert(Preset(title: "Internet", plannedAmount: 90, workspace: fixture.workspace, defaultCard: fixture.backupCard, defaultCategory: fixture.travel))
        fixture.context.insert(PlannedExpense(title: "Rent", plannedAmount: 1_500, expenseDate: date(2026, 5, 20), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries))
        fixture.context.insert(PlannedExpense(title: "Internet", plannedAmount: 90, expenseDate: date(2026, 5, 22), workspace: fixture.workspace, card: fixture.backupCard, category: fixture.travel))
        try fixture.context.save()

        let executor = MarinaWorkspaceAggregationExecutor(calendar: Calendar(identifier: .gregorian))
        let upcoming = handledCard(executor.execute(
            plan: MarinaAggregationPlan(
                operation: .rank,
                measure: .presetAmount,
                grouping: MarinaGroupingCandidate(dimension: .transaction),
                ranking: MarinaRankingCandidate(direction: .largest, limit: 2)
            ),
            provider: fixture.provider,
            now: date(2026, 5, 15)
        ))
        #expect(upcoming.rows.first?.label == "Rent")

        let byCategory = handledCard(executor.execute(
            plan: MarinaAggregationPlan(
                operation: .sum,
                measure: .presetAmount,
                dateRange: monthRange(),
                grouping: MarinaGroupingCandidate(dimension: .category)
            ),
            provider: fixture.provider,
            now: date(2026, 5, 15)
        ))
        #expect(byCategory.rows.contains(where: { $0.label == "Groceries" && $0.value.filter(\.isNumber).contains("1500") }))

        let presets = handledCard(executor.execute(
            plan: MarinaAggregationPlan(
                operation: .rank,
                measure: .presetAmount,
                grouping: MarinaGroupingCandidate(dimension: .preset),
                ranking: MarinaRankingCandidate(direction: .largest)
            ),
            provider: fixture.provider,
            now: date(2026, 5, 15)
        ))
        #expect(presets.rows.first?.label == "Rent")
    }

    @Test func workspaceExecutor_savingsMovementsAndSharedBalancesReturnRankedCards() throws {
        let fixture = try makeFixture()
        let savings = SavingsAccount(name: "True Savings", total: 0, workspace: fixture.workspace)
        let shared = AllocationAccount(name: "Roommate", workspace: fixture.workspace)
        let allocation = ExpenseAllocation(allocatedAmount: 225, workspace: fixture.workspace, account: shared)
        let settlement = AllocationSettlement(date: date(2026, 5, 8), note: "Paid back", amount: -25, workspace: fixture.workspace, account: shared)
        fixture.context.insert(savings)
        fixture.context.insert(SavingsLedgerEntry(date: date(2026, 5, 3), amount: 400, note: "Period close", kindRaw: SavingsLedgerEntryKind.periodClose.rawValue, workspace: fixture.workspace, account: savings))
        fixture.context.insert(SavingsLedgerEntry(date: date(2026, 5, 10), amount: -125, note: "Manual adjustment", kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue, workspace: fixture.workspace, account: savings))
        fixture.context.insert(shared)
        fixture.context.insert(allocation)
        fixture.context.insert(settlement)
        try fixture.context.save()

        let executor = MarinaWorkspaceAggregationExecutor(calendar: Calendar(identifier: .gregorian))
        let savingsCard = handledCard(executor.execute(
            plan: MarinaAggregationPlan(
                operation: .rank,
                measure: .savingsMovement,
                dateRange: monthRange(),
                grouping: MarinaGroupingCandidate(dimension: .savingsLedgerEntry),
                ranking: MarinaRankingCandidate(direction: .largest)
            ),
            provider: fixture.provider,
            now: date(2026, 5, 15)
        ))
        #expect(savingsCard.rows.first?.label == "Period close")

        let sharedCard = handledCard(executor.execute(
            plan: MarinaAggregationPlan(
                operation: .rank,
                measure: .reconciliationBalance,
                grouping: MarinaGroupingCandidate(dimension: .allocationAccount),
                ranking: MarinaRankingCandidate(direction: .largest)
            ),
            provider: fixture.provider,
            now: date(2026, 5, 15)
        ))
        #expect(sharedCard.rows.first?.label == "Roommate")
        #expect(sharedCard.rows.first?.value.filter(\.isNumber).contains("200") == true)
    }

    @Test func workspaceAggregationResponseBridge_mapsSummaryCardToHomeAnswerRows() {
        let card = MarinaWorkspaceAggregationCard(
            title: "Top Income Sources",
            subtitle: "May",
            primaryValue: "$2,500.00",
            rows: [
                .init(label: "Salary", value: "$2,500.00", amount: 2_500, sortValue: 2_500)
            ],
            traceSummary: "workspaceAggregation=topIncomeSources,resultCount=1"
        )

        let answer = MarinaWorkspaceAggregationResponseBridge().responseCompatibleAnswer(from: card)

        #expect(answer.title == "Top Income Sources")
        #expect(answer.primaryValue == "$2,500.00")
        #expect(answer.rows.first?.title == "Salary")
    }

    @Test func composableExecutor_cardRankingAndExclusionUseBudgetImpactRows() throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let executor = MarinaComposableWorkspaceQueryExecutor(calendar: Calendar(identifier: .gregorian))
        let range = monthRange()

        let cardRanking = handledCard(executor.execute(
            candidate: candidate(
                prompt: "Which card is eating the most of my budget?",
                operation: .rank,
                measure: .spend
            ),
            resolved: resolvedCandidate(),
            plan: MarinaAggregationPlan(
                operation: .rank,
                measure: .spend,
                dateRange: range,
                grouping: MarinaGroupingCandidate(dimension: .card),
                ranking: MarinaRankingCandidate(direction: .top)
            ),
            provider: fixture.provider,
            now: date(2026, 5, 15)
        ))
        #expect(cardRanking.title == "Cards by Budget Impact")
        #expect(cardRanking.rows.first?.label == "Apple Card")
        #expect(cardRanking.rows.first?.value.filter(\.isNumber).contains("500") == true)

        let cardMention = mention("apple card", .card)
        let categoryMention = mention("groceries", .category)
        let filtered = handledCard(executor.execute(
            candidate: candidate(
                prompt: "What did I spend on Apple Card outside of Groceries?",
                operation: .sum,
                measure: .spend,
                mentions: [cardMention, categoryMention]
            ),
            resolved: resolvedCandidate(targets: [
                resolvedTarget(mention: cardMention, role: .filter, entityType: .card, displayName: "Apple Card", sourceID: fixture.appleCard.id),
                resolvedTarget(mention: categoryMention, role: .filter, entityType: .category, displayName: "Groceries", sourceID: fixture.groceries.id)
            ]),
            plan: MarinaAggregationPlan(
                operation: .sum,
                measure: .spend,
                targets: [
                    target(.card, "Apple Card", sourceID: fixture.appleCard.id),
                    target(.category, "Groceries", sourceID: fixture.groceries.id)
                ],
                dateRange: range
            ),
            provider: fixture.provider,
            now: date(2026, 5, 15)
        ))
        #expect(filtered.primaryValue?.filter(\.isNumber).contains("200") == true)
        #expect(filtered.rows.allSatisfy { $0.label.contains("Travel") })
    }

    @Test func composableExecutor_recentFilteredPurchasesAndTargetedAverages() throws {
        let fixture = try makeFixture()
        let cannabis = Offshore.Category(name: "Cannabis", hexColor: "#225522", workspace: fixture.workspace)
        fixture.context.insert(cannabis)
        for day in 1...6 {
            fixture.context.insert(VariableExpense(
                descriptionText: "Cannabis Purchase \(day)",
                amount: Double(day * 10),
                transactionDate: date(2026, 5, day),
                workspace: fixture.workspace,
                card: fixture.appleCard,
                category: cannabis
            ))
        }
        fixture.context.insert(VariableExpense(descriptionText: "Groceries Week 1", amount: 70, transactionDate: date(2026, 5, 1), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries))
        fixture.context.insert(VariableExpense(descriptionText: "Groceries Week 2", amount: 140, transactionDate: date(2026, 5, 8), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries))
        try fixture.context.save()

        let executor = MarinaComposableWorkspaceQueryExecutor(calendar: Calendar(identifier: .gregorian))
        let categoryMention = mention("cannabis", .category)
        let recent = handledCard(executor.execute(
            candidate: candidate(prompt: "List my last 5 Cannabis purchases", operation: .rank, measure: .transactionAmount, mentions: [categoryMention]),
            resolved: resolvedCandidate(targets: [
                resolvedTarget(mention: categoryMention, role: .filter, entityType: .category, displayName: "Cannabis", sourceID: cannabis.id)
            ]),
            plan: MarinaAggregationPlan(
                operation: .rank,
                measure: .transactionAmount,
                targets: [target(.category, "Cannabis", sourceID: cannabis.id)],
                grouping: MarinaGroupingCandidate(dimension: .transaction),
                ranking: MarinaRankingCandidate(direction: .newest, limit: 5),
                limit: 5
            ),
            provider: fixture.provider,
            now: date(2026, 5, 15)
        ))
        #expect(recent.rows.count == 5)
        #expect(recent.rows.first?.label == "Cannabis Purchase 6")

        let groceriesMention = mention("groceries", .category)
        let average = handledCard(executor.execute(
            candidate: candidate(prompt: "What was my average weekly Groceries spending over the last 3 months?", operation: .average, measure: .spend, mentions: [groceriesMention]),
            resolved: resolvedCandidate(targets: [
                resolvedTarget(mention: groceriesMention, role: .primaryTarget, entityType: .category, displayName: "Groceries", sourceID: fixture.groceries.id)
            ]),
            plan: MarinaAggregationPlan(
                operation: .average,
                measure: .spend,
                targets: [target(.category, "Groceries", sourceID: fixture.groceries.id)],
                dateRange: monthRange(),
                grouping: MarinaGroupingCandidate(dimension: .week)
            ),
            provider: fixture.provider,
            now: date(2026, 5, 15)
        ))
        #expect(average.title == "Average Weekly Spending")
        #expect(average.rows.isEmpty == false)
        #expect(average.primaryValue != nil)
    }

    @Test func composableExecutor_deltaReconciliationAndSimulationReturnCards() throws {
        let fixture = try makeFixture()
        let food = fixture.groceries
        let shared = AllocationAccount(name: "Roommate", workspace: fixture.workspace)
        let allocatedExpense = VariableExpense(descriptionText: "Dinner", amount: 120, transactionDate: date(2026, 5, 5), workspace: fixture.workspace, card: fixture.appleCard, category: food)
        fixture.context.insert(shared)
        fixture.context.insert(allocatedExpense)
        fixture.context.insert(ExpenseAllocation(allocatedAmount: 60, workspace: fixture.workspace, account: shared, expense: allocatedExpense))
        fixture.context.insert(VariableExpense(descriptionText: "May Groceries", amount: 300, transactionDate: date(2026, 5, 8), workspace: fixture.workspace, card: fixture.appleCard, category: food))
        fixture.context.insert(VariableExpense(descriptionText: "April Groceries", amount: 100, transactionDate: date(2026, 4, 8), workspace: fixture.workspace, card: fixture.appleCard, category: food))
        let budget = Budget(name: "May", startDate: date(2026, 5, 1), endDate: date(2026, 5, 31), workspace: fixture.workspace)
        fixture.context.insert(budget)
        fixture.context.insert(BudgetCategoryLimit(maxAmount: 350, budget: budget, category: food))
        fixture.context.insert(Income(source: "Planned", amount: 1_000, date: date(2026, 5, 1), isPlanned: true, workspace: fixture.workspace))
        try fixture.context.save()

        let executor = MarinaComposableWorkspaceQueryExecutor(calendar: Calendar(identifier: .gregorian))
        let primary = monthRange()
        let comparison = HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30))

        let delta = handledCard(executor.execute(
            candidate: candidate(prompt: "Which expenses made this month higher than last month?", operation: .compare, measure: .spend),
            resolved: resolvedCandidate(),
            plan: MarinaAggregationPlan(
                operation: .compare,
                measure: .spend,
                dateRange: primary,
                comparisonDateRange: comparison,
                grouping: MarinaGroupingCandidate(dimension: .category),
                ranking: MarinaRankingCandidate(direction: .largest)
            ),
            provider: fixture.provider,
            now: date(2026, 5, 15)
        ))
        #expect(delta.title == "Spending Increase Drivers")
        #expect(delta.rows.first?.label == "Groceries")

        let accountMention = mention("roommate", .allocationAccount)
        let categoryMention = mention("groceries", .category)
        let allocated = handledCard(executor.execute(
            candidate: candidate(prompt: "How much did Roommate spend on Groceries?", operation: .sum, measure: .spend, mentions: [accountMention, categoryMention]),
            resolved: resolvedCandidate(targets: [
                resolvedTarget(mention: accountMention, role: .filter, entityType: .allocationAccount, displayName: "Roommate", sourceID: shared.id),
                resolvedTarget(mention: categoryMention, role: .filter, entityType: .category, displayName: "Groceries", sourceID: food.id)
            ]),
            plan: MarinaAggregationPlan(
                operation: .sum,
                measure: .spend,
                targets: [
                    target(.allocationAccount, "Roommate", sourceID: shared.id),
                    target(.category, "Groceries", sourceID: food.id)
                ],
                dateRange: primary
            ),
            provider: fixture.provider,
            now: date(2026, 5, 15)
        ))
        #expect(allocated.primaryValue?.filter(\.isNumber).contains("60") == true)

        let simulationMention = mention("groceries", .category, role: .simulationInput)
        let simulation = handledCard(executor.execute(
            candidate: candidate(prompt: "If I spend $50 on Groceries, how will that affect my budget?", operation: .simulate, measure: .remainingBudget, mentions: [simulationMention]),
            resolved: resolvedCandidate(targets: [
                resolvedTarget(mention: simulationMention, role: .simulationInput, entityType: .category, displayName: "Groceries", sourceID: food.id)
            ]),
            plan: MarinaAggregationPlan(
                operation: .simulate,
                measure: .remainingBudget,
                targets: [target(.category, "Groceries", role: .simulationInput, sourceID: food.id)],
                dateRange: primary
            ),
            provider: fixture.provider,
            now: date(2026, 5, 15)
        ))
        #expect(simulation.title == "What-If Budget Impact")
        #expect(simulation.rows.contains(where: { $0.label == "Category limit" }))
    }

    private func executable(_ plan: MarinaAggregationPlan) throws -> MarinaExecutableAggregationPlan {
        switch MarinaAggregationPlanHomeQueryAdapter().executablePlan(from: plan) {
        case .success(let executable):
            return executable
        case .failure(let unsupported):
            throw TestFailure(message: unsupported.message)
        }
    }

    private func assertScalar(_ result: MarinaAggregationResult, containsDigits digits: String) {
        guard case .scalar(let scalar) = result else {
            Issue.record("Expected scalar result.")
            return
        }
        #expect((scalar.renderedValue ?? "").filter(\.isNumber).contains(digits))
    }

    private func assertUnsupported(_ result: MarinaAggregationResult) {
        guard case .unsupported = result else {
            Issue.record("Expected unsupported result.")
            return
        }
    }

    private func handledCard(_ result: MarinaWorkspaceAggregationExecutionResult) -> MarinaWorkspaceAggregationCard {
        guard case .handled(let card) = result else {
            Issue.record("Expected workspace aggregation card.")
            return MarinaWorkspaceAggregationCard(title: "Missing", traceSummary: "missing")
        }
        return card
    }

    private func handledCard(_ result: MarinaComposableWorkspaceQueryExecutionResult) -> MarinaWorkspaceAggregationCard {
        guard case .handled(let card) = result else {
            Issue.record("Expected composable workspace card.")
            return MarinaWorkspaceAggregationCard(title: "Missing", traceSummary: "missing")
        }
        return card
    }

    private func target(
        _ type: MarinaCandidateEntityTypeHint,
        _ name: String,
        role: MarinaResolvedTargetRole = .primaryTarget,
        sourceID: UUID? = nil
    ) -> MarinaResolvedAggregationTarget {
        MarinaResolvedAggregationTarget(role: role, entityType: type, displayName: name, sourceID: sourceID)
    }

    private func candidate(
        prompt: String,
        operation: MarinaCandidateOperation,
        measure: MarinaCandidateMeasure,
        mentions: [MarinaUnresolvedEntityMention] = []
    ) -> MarinaQueryPlanCandidate {
        MarinaQueryPlanCandidate(
            source: .heuristic,
            rawPrompt: prompt,
            operation: operation,
            measure: measure,
            entityMentions: mentions
        )
    }

    private func mention(
        _ rawText: String,
        _ type: MarinaCandidateEntityTypeHint,
        role: MarinaEntityMentionRole = .filter
    ) -> MarinaUnresolvedEntityMention {
        MarinaUnresolvedEntityMention(role: role, rawText: rawText, typeHint: type)
    }

    private func resolvedCandidate(targets: [MarinaResolvedEntityMention] = []) -> MarinaResolvedQueryCandidate {
        MarinaResolvedQueryCandidate(
            candidate: candidate(prompt: "test", operation: .sum, measure: .spend),
            resolvedTargets: targets,
            unresolvedMentions: [],
            ambiguousMentions: [],
            primaryDateRange: nil,
            comparisonDateRange: nil
        )
    }

    private func resolvedTarget(
        mention: MarinaUnresolvedEntityMention,
        role: MarinaResolvedTargetRole,
        entityType: MarinaCandidateEntityTypeHint,
        displayName: String,
        sourceID: UUID? = nil
    ) -> MarinaResolvedEntityMention {
        MarinaResolvedEntityMention(
            id: mention.id,
            mention: mention,
            role: role,
            entityType: entityType,
            displayName: displayName,
            sourceID: sourceID
        )
    }

    private func monthRange() -> HomeQueryDateRange {
        HomeQueryDateRange(startDate: date(2026, 5, 1), endDate: date(2026, 5, 31))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }

    private struct TestFailure: Error {
        let message: String
    }
}

@MainActor
struct MarinaPhase5Fixture {
    let context: ModelContext
    let workspace: Workspace
    let groceries: Offshore.Category
    let travel: Offshore.Category
    let appleCard: Card
    let backupCard: Card
    let provider: MarinaDataProvider

    func seedSpendData() throws {
        context.insert(PlannedExpense(title: "Groceries Plan", plannedAmount: 250, expenseDate: date(2026, 5, 5), workspace: workspace, card: appleCard, category: groceries))
        context.insert(VariableExpense(descriptionText: "Groceries Variable", amount: 50, transactionDate: date(2026, 5, 10), workspace: workspace, card: appleCard, category: groceries))
        context.insert(PlannedExpense(title: "Travel Plan", plannedAmount: 200, expenseDate: date(2026, 5, 7), workspace: workspace, card: appleCard, category: travel))
        context.insert(VariableExpense(descriptionText: "Travel Variable", amount: 100, transactionDate: date(2026, 5, 12), workspace: workspace, card: backupCard, category: travel))
        try context.save()
    }

    func seedComparisonData() throws {
        context.insert(PlannedExpense(title: "May Groceries", plannedAmount: 300, expenseDate: date(2026, 5, 5), workspace: workspace, card: appleCard, category: groceries))
        context.insert(PlannedExpense(title: "April Groceries", plannedAmount: 100, expenseDate: date(2026, 4, 5), workspace: workspace, card: appleCard, category: groceries))
        try context.save()
    }

    func seedIncomeData() throws {
        context.insert(Income(source: "Salary", amount: 2_000, date: date(2026, 1, 5), isPlanned: false, workspace: workspace))
        context.insert(Income(source: "Salary", amount: 2_200, date: date(2026, 2, 5), isPlanned: false, workspace: workspace))
        context.insert(Income(source: "Salary", amount: 2_400, date: date(2026, 3, 5), isPlanned: false, workspace: workspace))
        try context.save()
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }
}

@MainActor
func makeFixture() throws -> MarinaPhase5Fixture {
    let schema = Schema([
        Workspace.self,
        Budget.self,
        Card.self,
        BudgetCardLink.self,
        Offshore.Category.self,
        Preset.self,
        BudgetPresetLink.self,
        BudgetCategoryLimit.self,
        PlannedExpense.self,
        VariableExpense.self,
        AllocationAccount.self,
        ExpenseAllocation.self,
        AllocationSettlement.self,
        IncomeSeries.self,
        ImportMerchantRule.self,
        Income.self,
        SavingsAccount.self,
        SavingsLedgerEntry.self
    ])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: config)
    let context = ModelContext(container)
    let workspace = Workspace(name: "Phase 5 Workspace", hexColor: "#3B82F6")
    let groceries = Offshore.Category(name: "Groceries", hexColor: "#00AA00", workspace: workspace)
    let travel = Offshore.Category(name: "Travel", hexColor: "#0000AA", workspace: workspace)
    let appleCard = Card(name: "Apple Card", workspace: workspace)
    let backupCard = Card(name: "Backup Card", workspace: workspace)
    context.insert(workspace)
    context.insert(groceries)
    context.insert(travel)
    context.insert(appleCard)
    context.insert(backupCard)
    try context.save()

    return MarinaPhase5Fixture(
        context: context,
        workspace: workspace,
        groceries: groceries,
        travel: travel,
        appleCard: appleCard,
        backupCard: backupCard,
        provider: MarinaDataProvider(modelContext: context, workspaceID: workspace.id)
    )
}
