import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaManualQAPromptInterpretationSmokeTests {
    @Test func atAppleMapsToMerchantTextWhenOnlyMerchantMatches() {
        let fixture = makeFixture(includeAppleCard: false, includeAppleMerchantExpense: true)
        let interpreted = validated("How much did I spend at Apple?", snapshot: fixture.snapshot)
        let request = interpreted.request

        #expect(request.entity == .variableExpense)
        #expect(request.operation == .sum)
        #expect(request.measure == .budgetImpact)
        #expect(request.dimensions == [.merchantText])
        #expect(request.textQuery?.contains("Apple") == true)
        #expect(request.targetName == nil)
        #expect(request.expectedAnswerShape == .metric)
        #expect(interpreted.clarificationChoices == nil)
    }

    @Test func atAppleMapsToMerchantTextWhenMerchantAndCardBothMatch() {
        let fixture = makeFixture(includeAppleCard: true, includeAppleMerchantExpense: true)
        let interpreted = validated("How much did I spend at Apple?", snapshot: fixture.snapshot)
        let request = interpreted.request

        #expect(request.entity == .variableExpense)
        #expect(request.operation == .sum)
        #expect(request.measure == .budgetImpact)
        #expect(request.dimensions == [.merchantText])
        #expect(request.textQuery?.contains("Apple") == true)
        #expect(request.targetName == nil)
        #expect(request.expectedAnswerShape == .metric)
        #expect(interpreted.clarificationChoices == nil)
    }

    @Test func onAppleCardMapsToCardTarget() {
        let fixture = makeFixture(includeAppleCard: true, includeAppleMerchantExpense: false)
        let interpreted = validated("How much did I spend on Apple Card?", snapshot: fixture.snapshot)
        let request = interpreted.request

        #expect(request.entity == .card)
        #expect(request.operation == .sum)
        #expect(request.measure == .budgetImpact)
        #expect(request.dimensions == [.card])
        #expect(request.targetName == "Apple Card")
        #expect(request.expectedAnswerShape == .metric)
    }

    @Test func onAppleClarifiesWhenMerchantAndCardBothMatch() throws {
        let fixture = makeFixture(includeAppleCard: true, includeAppleMerchantExpense: true)
        let interpreted = validated("How much did I spend on Apple?", snapshot: fixture.snapshot)
        let request = interpreted.request

        #expect(request.expectedAnswerShape == .clarification)
        #expect(request.unsupportedReason == .ambiguousEntity)
        #expect(MarinaUniversalRoutingPolicy.internalParityProven.allows(request) == false)

        let choices = try #require(interpreted.clarificationChoices)
        #expect(choices.choices.map(\.title).contains("Apple Store"))
        #expect(choices.choices.map(\.title).contains("Apple Card"))
    }

    @Test func onGroceriesMapsToCategoryTargetWhenCategoryExists() {
        let fixture = makeFixture()
        let interpreted = validated("How much did I spend on groceries?", snapshot: fixture.snapshot)
        let request = interpreted.request

        #expect(request.entity == .category)
        #expect(request.operation == .sum)
        #expect(request.measure == .budgetImpact)
        #expect(request.dimensions == [.category])
        #expect(request.targetName == "Groceries")
        #expect(request.expenseScope == .unified)
        #expect(request.expectedAnswerShape == .metric)
    }

    @Test func incomeFromPaycheckMapsToIncomeSource() {
        let fixture = makeFixture()
        let interpreted = validated("How much income from Paycheck?", snapshot: fixture.snapshot)
        let request = interpreted.request

        #expect(request.entity == .income)
        #expect(request.operation == .sum)
        #expect(request.measure == .incomeAmount)
        #expect(request.dimensions == [.incomeSource])
        #expect(request.targetName == "Paycheck")
        #expect(request.incomeState == .all)
        #expect(request.expectedAnswerShape == .metric)
    }

    @Test func spendAtPaycheckStaysExpenseScopedInsteadOfIncomeSource() {
        let fixture = makeFixture()
        let interpreted = validated("How much did I spend at Paycheck?", snapshot: fixture.snapshot)
        let request = interpreted.request

        #expect(request.entity == .variableExpense)
        #expect(request.operation == .sum)
        #expect(request.measure == .budgetImpact)
        #expect(request.dimensions == [.merchantText])
        #expect(request.textQuery?.contains("Paycheck") == true)
        #expect(request.targetName == nil)
        #expect(request.expectedAnswerShape == .metric)
    }

    @Test func genericSavingsTotalDoesNotBecomeUniversalExplicitAccount() {
        let fixture = makeFixture()
        let interpreted = validated("What is my savings total?", snapshot: fixture.snapshot)
        let request = interpreted.request

        #expect(request.targetName != "Emergency")
        #expect(MarinaUniversalRoutingPolicy.internalParityProven.scenario(for: request) == nil)
        #expect(MarinaUniversalRoutingPolicy.internalParityProven.allows(request) == false)
    }

    @Test func explicitSavingsAccountWordingResolvesAccountTarget() {
        let fixture = makeFixture()
        let interpreted = validated("What is my Emergency savings account balance?", snapshot: fixture.snapshot)
        let request = interpreted.request

        #expect(request.entity == .savingsAccount)
        #expect(request.operation == .sum)
        #expect(request.measure == .savingsTotal)
        #expect(request.dimensions == [.savingsAccount])
        #expect(request.targetName == "Emergency")
        #expect(request.dateRangeToken == .allTime)
        #expect(request.expectedAnswerShape == .metric)
    }

    @Test func genericReconciliationBalanceDoesNotGuessExistingAccount() {
        let fixture = makeFixture(includeRoommateReconciliationAccount: true)
        let interpreted = validated("What is my reconciliation balance?", snapshot: fixture.snapshot)
        let request = interpreted.request

        #expect(request.targetName != "Roommate")
        #expect(MarinaUniversalRoutingPolicy.internalParityProven.scenario(for: request) == nil)
        #expect(MarinaUniversalRoutingPolicy.internalParityProven.allows(request) == false)
        #expect(request.expectedAnswerShape == .unsupported || request.expectedAnswerShape == .clarification || request.targetName == "Reconciliation")
    }

    private func validated(
        _ prompt: String,
        snapshot: MarinaWorkspaceSnapshot
    ) -> MarinaInterpretedSemanticRequest {
        let interpreted = MarinaRuleBasedInterpreter().interpretWithConfidence(prompt)
        return MarinaSemanticRequestValidator().validate(
            interpreted: interpreted,
            snapshot: snapshot
        )
    }

    private func makeFixture(
        includeAppleCard: Bool = true,
        includeAppleMerchantExpense: Bool = true,
        includeRoommateReconciliationAccount: Bool = false
    ) -> PromptSmokeFixture {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let fallbackCard = Card(name: "Chase Card", theme: "sky", effect: "matte", workspace: workspace)
        let appleCard = includeAppleCard
            ? Card(name: "Apple Card", theme: "ruby", effect: "plastic", workspace: workspace)
            : nil
        let groceries = Offshore.Category(name: "Groceries", hexColor: "#22C55E", workspace: workspace)
        let budget = Budget(name: "June", startDate: date(2026, 6, 1), endDate: date(2026, 6, 30), workspace: workspace)
        let phonePreset = Preset(title: "Phone", plannedAmount: 80, workspace: workspace, defaultCard: fallbackCard, defaultCategory: groceries)
        let plannedExpense = PlannedExpense(
            title: "Phone Bill",
            plannedAmount: 80,
            expenseDate: date(2026, 6, 16),
            workspace: workspace,
            card: fallbackCard,
            category: groceries,
            sourcePresetID: phonePreset.id,
            sourceBudgetID: budget.id
        )

        var cards = [fallbackCard]
        if let appleCard {
            cards.append(appleCard)
        }

        let appleExpense = includeAppleMerchantExpense
            ? VariableExpense(
                descriptionText: "Apple Store",
                amount: 120,
                transactionDate: date(2026, 6, 5),
                workspace: workspace,
                card: appleCard ?? fallbackCard,
                category: groceries
            )
            : nil
        let krogerExpense = VariableExpense(
            descriptionText: "Kroger",
            amount: 30,
            transactionDate: date(2026, 6, 10),
            workspace: workspace,
            card: fallbackCard,
            category: groceries
        )
        let variableExpenses = [appleExpense, krogerExpense].compactMap { $0 }

        let actualPaycheck = Income(source: "Paycheck", amount: 2_000, date: date(2026, 6, 11), isPlanned: false, workspace: workspace, card: fallbackCard)
        let plannedPaycheck = Income(source: "Paycheck", amount: 2_100, date: date(2026, 6, 25), isPlanned: true, workspace: workspace, card: fallbackCard)
        let savings = SavingsAccount(name: "Emergency", total: 1_000, workspace: workspace)
        let reconciliationAccounts = includeRoommateReconciliationAccount
            ? [AllocationAccount(name: "Roommate", workspace: workspace)]
            : []

        let snapshot = MarinaWorkspaceSnapshot(
            workspace: workspace,
            budgets: [budget],
            cards: cards,
            categories: [groceries],
            presets: [phonePreset],
            plannedExpenses: [plannedExpense],
            variableExpenses: variableExpenses,
            homePlannedExpenses: [plannedExpense],
            homeCalculationPlannedExpenses: [plannedExpense],
            homeCalculationVariableExpenses: variableExpenses,
            reconciliationAccounts: reconciliationAccounts,
            expenseAllocations: [],
            allocationSettlements: [],
            savingsAccounts: [savings],
            savingsEntries: [],
            incomes: [actualPaycheck, plannedPaycheck]
        )

        return PromptSmokeFixture(snapshot: snapshot)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        DateComponents(calendar: calendar, timeZone: TimeZone(secondsFromGMT: 0), year: year, month: month, day: day).date!
    }
}

private struct PromptSmokeFixture {
    let snapshot: MarinaWorkspaceSnapshot
}
