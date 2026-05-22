import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
@Suite(.serialized)
struct MarinaMetricFormulaExecutorTests {
    @Test func safeSpendRemaining_reportsRestOfMonthRoomNotDailyAllowance() throws {
        let fixture = try makeFixture()
        fixture.context.insert(Income(source: "Paycheck", amount: 1_000, date: date(2026, 5, 5), isPlanned: false, workspace: fixture.workspace))
        try fixture.context.save()

        let card = try handledCard(execute(.safeSpendRemaining, fixture: fixture))

        #expect(card.primaryValue == "$1,000.00")
        let perDay = try #require(card.rows.first { $0.label == "Per-day reference" })
        #expect(perDay.value != card.primaryValue)
    }

    @Test func trueOwnedSpend_usesBudgetImpactInsteadOfGrossOrLedgerSpend() throws {
        let fixture = try makeFixture()
        let savings = SavingsAccount(name: "True Savings", total: 0, workspace: fixture.workspace)
        let expense = VariableExpense(
            descriptionText: "Shared dinner",
            amount: 100,
            transactionDate: date(2026, 5, 8),
            workspace: fixture.workspace,
            card: fixture.appleCard,
            category: fixture.groceries
        )
        let allocation = ExpenseAllocation(
            allocatedAmount: 40,
            preservesGrossAmount: true,
            workspace: fixture.workspace,
            account: AllocationAccount(name: "Roommate", workspace: fixture.workspace),
            expense: expense
        )
        let offset = SavingsLedgerEntry(
            date: date(2026, 5, 8),
            amount: -20,
            note: "Savings offset",
            kindRaw: SavingsLedgerEntryKind.expenseOffset.rawValue,
            workspace: fixture.workspace,
            account: savings,
            variableExpense: expense
        )
        expense.allocation = allocation
        expense.savingsLedgerEntry = offset
        fixture.context.insert(savings)
        fixture.context.insert(expense)
        fixture.context.insert(allocation.account!)
        fixture.context.insert(allocation)
        fixture.context.insert(offset)
        try fixture.context.save()

        let card = try handledCard(execute(.trueOwnedSpend, fixture: fixture))

        #expect(card.primaryValue == "$40.00")
        #expect(card.rows.contains { $0.label == "Gross comparison" && $0.value == "$100.00" })
        #expect(card.rows.contains { $0.label == "Ledger comparison" && $0.value == "$100.00" })
    }

    @Test func reconciliationOwed_usesAllocationsAndSettlementsNeverSavings() throws {
        let fixture = try makeFixture()
        let account = AllocationAccount(name: "Alejandro", workspace: fixture.workspace)
        let savings = SavingsAccount(name: "True Savings", total: 0, workspace: fixture.workspace)
        let expense = VariableExpense(
            descriptionText: "Shared groceries",
            amount: 100,
            transactionDate: date(2026, 5, 4),
            workspace: fixture.workspace,
            card: fixture.appleCard,
            category: fixture.groceries
        )
        let allocation = ExpenseAllocation(allocatedAmount: 100, workspace: fixture.workspace, account: account, expense: expense)
        expense.allocation = allocation
        fixture.context.insert(account)
        fixture.context.insert(expense)
        fixture.context.insert(allocation)
        fixture.context.insert(AllocationSettlement(date: date(2026, 5, 9), note: "Paid back", amount: -40, workspace: fixture.workspace, account: account))
        fixture.context.insert(savings)
        fixture.context.insert(SavingsLedgerEntry(date: date(2026, 5, 10), amount: 999, note: "Unrelated savings", kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue, workspace: fixture.workspace, account: savings))
        try fixture.context.save()

        let card = try handledCard(execute(.reconciliationOwedThisMonth, fixture: fixture))

        #expect(card.primaryValue == "$60.00")
        #expect(card.rows.contains { $0.label == "Allocated share" && $0.value == "$100.00" })
        #expect(card.rows.contains { $0.label == "Signed settlements" && $0.amount == -40 })
    }

    @Test func unrecordedPlannedExpenses_excludesRowsWithRecordedActuals() throws {
        let fixture = try makeFixture()
        fixture.context.insert(PlannedExpense(title: "Still Planned", plannedAmount: 80, actualAmount: 0, expenseDate: date(2026, 5, 12), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries))
        fixture.context.insert(PlannedExpense(title: "Already Recorded", plannedAmount: 90, actualAmount: 95, expenseDate: date(2026, 5, 13), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries))
        try fixture.context.save()

        let card = try handledCard(execute(.unrecordedPlannedExpenses, fixture: fixture))

        #expect(card.rows.map(\.label) == ["Still Planned"])
        #expect(card.rows.contains { $0.label == "Already Recorded" } == false)
    }

    @Test func cardOverspendingDriver_usesPlanBaselineNotRawCardSpend() throws {
        let fixture = try makeFixture()
        fixture.context.insert(PlannedExpense(title: "Apple Baseline", plannedAmount: 500, expenseDate: date(2026, 5, 2), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries))
        fixture.context.insert(VariableExpense(descriptionText: "Apple Actual", amount: 100, transactionDate: date(2026, 5, 3), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries))
        fixture.context.insert(PlannedExpense(title: "Backup Baseline", plannedAmount: 100, expenseDate: date(2026, 5, 2), workspace: fixture.workspace, card: fixture.backupCard, category: fixture.travel))
        fixture.context.insert(VariableExpense(descriptionText: "Backup Actual", amount: 200, transactionDate: date(2026, 5, 3), workspace: fixture.workspace, card: fixture.backupCard, category: fixture.travel))
        try fixture.context.save()

        let card = try handledCard(execute(.cardOverspendingDriver, fixture: fixture))

        #expect(card.rows.first?.label == "Backup Card")
        #expect(card.rows.first?.value.contains("actual $200.00 vs planned $100.00") == true)
    }

    @Test func incomeBySource_usesActualIncomeAndExcludesPlannedIncome() throws {
        let fixture = try makeFixture()
        fixture.context.insert(Income(source: "Paycheck", amount: 1_200, date: date(2026, 5, 5), isPlanned: false, workspace: fixture.workspace))
        fixture.context.insert(Income(source: "Side Work", amount: 300, date: date(2026, 5, 9), isPlanned: false, workspace: fixture.workspace))
        fixture.context.insert(Income(source: "Expected Bonus", amount: 900, date: date(2026, 5, 20), isPlanned: true, workspace: fixture.workspace))
        try fixture.context.save()

        let card = try handledCard(execute(.incomeBySource, fixture: fixture, prompt: "income by source"))

        #expect(card.title == "Income by Source")
        #expect(card.primaryValue == "$1,500.00")
        #expect(card.rows.contains { $0.label == "Paycheck" && $0.value == "$1,200.00" })
        #expect(card.rows.contains { $0.label == "Side Work" && $0.value == "$300.00" })
        #expect(card.rows.contains { $0.label == "Expected Bonus" } == false)
    }

    @Test func setupDependentContractsReturnContractAwareBlockedCards() throws {
        let fixture = try makeFixture()

        let subscription = try blockedAnswer(execute(.subscriptionSpend, fixture: fixture))
        #expect(subscription.title == "Marina needs one setup step")
        #expect(subscription.rows.contains { $0.title == "Metric contract" && $0.value == "subscriptionSpend" })
        #expect(subscription.rows.contains { $0.title == "Refused substitution" && $0.value.contains("subscriptions") })

        let checkIn = try blockedAnswer(execute(.sinceLastCheckIn, fixture: fixture))
        #expect(checkIn.title == "Marina needs one setup step")
        #expect(checkIn.rows.contains { $0.title == "Metric contract" && $0.value == "sinceLastCheckIn" })
        #expect(checkIn.rows.contains { $0.title == "Required setup" && $0.value.contains("check-in snapshot") })
    }

    private func execute(
        _ id: MarinaMetricContractID,
        fixture: MarinaPhase5Fixture,
        prompt: String? = nil
    ) throws -> MarinaMetricFormulaExecutionResult {
        let contract = try #require(MarinaMetricContractRegistry.current.contract(for: id))
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: prompt ?? contract.seedPrompt,
            responseShapeHint: contract.responseShape,
            confidence: .high,
            unsupportedHint: .unsupportedOperation
        )
        let resolved = MarinaQueryResolver().resolve(
            candidate: candidate,
            provider: fixture.provider,
            now: date(2026, 5, 15),
            defaultPeriodUnit: .month
        )
        return MarinaMetricFormulaExecutor(calendar: Calendar(identifier: .gregorian)).execute(
            contract: contract,
            candidate: candidate,
            resolved: resolved,
            semanticResolved: nil,
            context: turnContext(fixture)
        )
    }

    private func handledCard(_ result: MarinaMetricFormulaExecutionResult) throws -> MarinaWorkspaceAggregationCard {
        guard case .handled(let card, _, _) = result else {
            Issue.record("Expected handled metric formula result.")
            throw TestFailure()
        }
        return card
    }

    private func blockedAnswer(_ result: MarinaMetricFormulaExecutionResult) throws -> HomeAnswer {
        guard case .blocked(let answer, _) = result else {
            Issue.record("Expected blocked metric formula result.")
            throw TestFailure()
        }
        return answer
    }

    private func turnContext(_ fixture: MarinaPhase5Fixture) -> MarinaTurnContext {
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
                budgetNames: [],
                allocationAccountNames: ["Alejandro", "Roommate"],
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

    private struct TestFailure: Error {}
}
