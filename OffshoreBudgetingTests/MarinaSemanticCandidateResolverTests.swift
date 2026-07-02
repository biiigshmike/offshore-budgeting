import Foundation
import Testing
@testable import Offshore

struct MarinaSemanticCandidateResolverTests {
    private let resolver = MarinaSemanticCandidateResolver()

    @Test func targetMerchantOnlyResolvesToMerchantTextSearch() {
        let fixture = makeFixture()
        let resolved = resolve(
            MarinaSemanticRequest(
                entity: .variableExpense,
                operation: .sum,
                measure: .budgetImpact,
                targetName: "Target",
                expectedAnswerShape: .metric
            ),
            snapshot: fixture.snapshot
        )

        #expect(resolved.request.entity == .variableExpense)
        #expect(resolved.request.dimensions == [.merchantText])
        #expect(resolved.request.textQuery == "Target groceries")
        #expect(resolved.request.targetDisplayName == "Target groceries")
        #expect(resolved.request.unsupportedReason == nil)
    }

    @Test func targetMerchantAndCategoryClarifiesInsteadOfGuessing() {
        let fixture = makeFixture(includeTargetCategory: true)
        let resolved = resolve(
            MarinaSemanticRequest(
                entity: .variableExpense,
                operation: .sum,
                measure: .budgetImpact,
                targetName: "Target",
                expectedAnswerShape: .metric
            ),
            snapshot: fixture.snapshot
        )

        #expect(resolved.request.expectedAnswerShape == .clarification)
        #expect(resolved.request.unsupportedReason == .ambiguousEntity)
        #expect(resolved.clarificationChoices?.choices.contains { $0.title == "Target" && $0.kindLabel == "Category" } == true)
        #expect(resolved.clarificationChoices?.choices.contains { $0.title == "Target groceries" && $0.kindLabel == "Expense match" } == true)
    }

    @Test func appleMerchantAndCardClarifiesWhenExpenseTargetIsUntyped() {
        let fixture = makeFixture(includeAppleMerchant: true)
        let resolved = resolve(
            MarinaSemanticRequest(
                entity: .variableExpense,
                operation: .sum,
                measure: .budgetImpact,
                targetName: "Apple",
                expectedAnswerShape: .metric
            ),
            snapshot: fixture.snapshot
        )

        #expect(resolved.request.expectedAnswerShape == .clarification)
        #expect(resolved.clarificationChoices?.choices.contains { $0.title == "Apple Card" && $0.kindLabel == "Card" } == true)
        #expect(resolved.clarificationChoices?.choices.contains { $0.title == "Apple Store" && $0.kindLabel == "Expense match" } == true)
    }

    @Test func appleCardHintResolvesCardDespiteMerchantMatch() {
        let fixture = makeFixture(includeAppleMerchant: true)
        let resolved = resolve(
            MarinaSemanticRequest(
                entity: .card,
                operation: .sum,
                measure: .budgetImpact,
                dimensions: [.card],
                targetName: "Apple",
                expectedAnswerShape: .metric
            ),
            snapshot: fixture.snapshot
        )

        #expect(resolved.request.entity == .card)
        #expect(resolved.request.dimensions == [.card])
        #expect(resolved.request.targetName == "Apple Card")
        #expect(resolved.request.expectedAnswerShape == .metric)
    }

    @Test func groceriesCategoryHintResolvesCategorySpend() {
        let fixture = makeFixture()
        let resolved = resolve(
            MarinaSemanticRequest(
                entity: .category,
                operation: .sum,
                measure: .budgetImpact,
                dimensions: [.category],
                targetName: "Groceries",
                expectedAnswerShape: .metric
            ),
            snapshot: fixture.snapshot
        )

        #expect(resolved.request.entity == .category)
        #expect(resolved.request.dimensions == [.category])
        #expect(resolved.request.targetName == "Groceries")
        #expect(resolved.request.expectedAnswerShape == .metric)
    }

    @Test func alejandroBalanceResolvesReconciliationAccount() {
        let fixture = makeFixture()
        let resolved = resolve(
            MarinaSemanticRequest(
                entity: .reconciliationAccount,
                operation: .sum,
                measure: .reconciliationBalance,
                dimensions: [.reconciliationAccount],
                targetName: "Alejandro",
                expectedAnswerShape: .metric
            ),
            snapshot: fixture.snapshot
        )

        #expect(resolved.request.entity == .reconciliationAccount)
        #expect(resolved.request.targetName == "Alejandro")
        #expect(resolved.request.measure == .reconciliationBalance)
    }

    @Test func nonexistentUntypedExpenseTargetPreservesUnsupportedNoMatchBehavior() {
        let fixture = makeFixture()
        let resolved = resolve(
            MarinaSemanticRequest(
                entity: .variableExpense,
                operation: .sum,
                measure: .budgetImpact,
                targetName: "Nonexistent",
                expectedAnswerShape: .metric
            ),
            snapshot: fixture.snapshot
        )

        #expect(resolved.request.expectedAnswerShape == .unsupported)
        #expect(resolved.request.unsupportedReason == .unresolvedEntity)
    }

    @Test func comparisonTargetCanBeRepairedWithSameTypedHint() {
        let fixture = makeFixture()
        let resolved = resolve(
            MarinaSemanticRequest(
                entity: .card,
                operation: .compare,
                measure: .budgetImpact,
                dimensions: [.card],
                targetName: "Apple",
                comparisonTargetName: "Chase",
                expectedAnswerShape: .comparison
            ),
            snapshot: fixture.snapshot
        )

        #expect(resolved.request.entity == .card)
        #expect(resolved.request.targetName == "Apple Card")
        #expect(resolved.request.comparisonTargetName == "Chase Card")
        #expect(resolved.request.expectedAnswerShape == .comparison)
    }

    private func resolve(
        _ request: MarinaSemanticRequest,
        snapshot: MarinaWorkspaceSnapshot
    ) -> MarinaInterpretedSemanticRequest {
        resolver.resolve(
            interpreted: MarinaInterpretedSemanticRequest(
                request: request,
                confidence: .medium,
                source: .foundationModel
            ),
            snapshot: snapshot
        )
    }

    private func makeFixture(
        includeTargetCategory: Bool = false,
        includeAppleMerchant: Bool = false
    ) -> ResolverFixture {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let appleCard = Card(name: "Apple Card", workspace: workspace)
        let chaseCard = Card(name: "Chase Card", workspace: workspace)
        let groceries = Offshore.Category(name: "Groceries", hexColor: "#22C55E", workspace: workspace)
        let targetCategory = includeTargetCategory
            ? Offshore.Category(name: "Target", hexColor: "#0EA5E9", workspace: workspace)
            : nil
        let budget = Budget(name: "July 2026", startDate: date(2026, 7, 1), endDate: date(2026, 7, 31), workspace: workspace)
        let preset = Preset(title: "Grocery Envelope", plannedAmount: 200, workspace: workspace, defaultCard: chaseCard, defaultCategory: groceries)
        let savings = SavingsAccount(name: "Emergency Fund", workspace: workspace)
        let alejandro = AllocationAccount(name: "Alejandro", workspace: workspace)
        let target = VariableExpense(descriptionText: "Target groceries", amount: 80, transactionDate: date(2026, 7, 7), workspace: workspace, card: appleCard, category: groceries)
        let groceryOutlet = VariableExpense(descriptionText: "Grocery Outlet", amount: 42, transactionDate: date(2026, 7, 8), workspace: workspace, card: chaseCard, category: groceries)
        let appleStore = includeAppleMerchant
            ? VariableExpense(descriptionText: "Apple Store", amount: 120, transactionDate: date(2026, 7, 9), workspace: workspace, card: appleCard, category: groceries)
            : nil
        let planned = PlannedExpense(title: "Grocery Envelope", plannedAmount: 200, expenseDate: date(2026, 7, 10), workspace: workspace, card: chaseCard, category: groceries)
        let categories = [groceries] + [targetCategory].compactMap { $0 }
        let variableExpenses = [target, groceryOutlet] + [appleStore].compactMap { $0 }
        let snapshot = MarinaWorkspaceSnapshot(
            workspace: workspace,
            budgets: [budget],
            cards: [appleCard, chaseCard],
            categories: categories,
            presets: [preset],
            plannedExpenses: [planned],
            variableExpenses: variableExpenses,
            homePlannedExpenses: [planned],
            homeCalculationPlannedExpenses: [planned],
            homeCalculationVariableExpenses: variableExpenses,
            reconciliationAccounts: [alejandro],
            expenseAllocations: [],
            allocationSettlements: [],
            savingsAccounts: [savings],
            savingsEntries: [],
            incomes: []
        )
        return ResolverFixture(snapshot: snapshot)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }
}

private struct ResolverFixture {
    let snapshot: MarinaWorkspaceSnapshot
}
