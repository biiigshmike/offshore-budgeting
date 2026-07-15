import Foundation
import Testing
@testable import Offshore

struct MarinaCandidateSearchServiceTests {
    private let service = MarinaCandidateSearchService()

    @Test func exactMatchesOutrankContainsAndTokenOverlap() {
        let fixture = makeFixture()
        let result = search("Groceries", request: expenseSpendRequest(), snapshot: fixture.snapshot)

        #expect(result.matches.first?.entity == .category)
        #expect(result.matches.first?.displayName == "Groceries")
        #expect(result.matches.first?.matchStrength == .exact)
        #expect(result.matches.contains { $0.displayName == "Grocery Outlet" && $0.matchStrength == .prefix })
        #expect(result.matches.contains { $0.displayName == "Monthly Grocery Plan" && $0.matchStrength == .contains })
    }

    @Test func repeatedExpenseTextMatchesReturnOccurrenceCountAndSamples() {
        let fixture = makeFixture(includeRepeatedTarget: true)
        let result = search("Target", request: expenseSpendRequest(), snapshot: fixture.snapshot)
        let target = result.matches.first { $0.entity == .variableExpense && $0.displayName == "Target groceries" }

        #expect(target?.occurrenceCount == 2)
        #expect(target?.sampleDescriptions == ["Target groceries", "Target groceries"])
        #expect(target?.fieldName == "merchantText")
    }

    @Test func multipleWeakTokenMeaningsAreAmbiguousAndNotRecommended() {
        let fixture = makeFixture()
        let result = search("Store Apple", request: merchantTextRequest(), snapshot: fixture.snapshot)

        #expect(result.matches.first?.displayName == "Apple Store")
        #expect(result.matches.first?.matchStrength == .tokenOverlap)
        #expect(result.ambiguityStatus == .ambiguous)
        #expect(result.recommendedMatch == nil)
    }

    @Test func nonexistentTargetReturnsNoUsefulCandidate() {
        let fixture = makeFixture()
        let result = search("Nonexistent", request: expenseSpendRequest(), snapshot: fixture.snapshot)

        #expect(result.matches.isEmpty)
        #expect(result.ambiguityStatus == .noUsefulCandidate)
        #expect(result.recommendedMatch == nil)
    }

    @Test func crossEntityMatchesAreAmbiguousWithoutStrongSemanticHint() {
        let fixture = makeFixture()
        let result = search("Apple", request: expenseSpendRequest(), snapshot: fixture.snapshot)

        #expect(result.matches.contains { $0.entity == .card && $0.displayName == "Apple Card" })
        #expect(result.matches.contains { $0.entity == .variableExpense && $0.displayName == "Apple Store" })
        #expect(result.ambiguityStatus == .ambiguous)
        #expect(result.recommendedMatch == nil)
    }

    @Test func strongSemanticHintDoesNotPromotePrefixOnlyMatch() {
        let fixture = makeFixture()
        let result = search(
            "Apple",
            request: MarinaSemanticRequest(
                entity: .card,
                operation: .sum,
                measure: .budgetImpact,
                dimensions: [.card],
                targetName: "Apple",
                expectedAnswerShape: .metric
            ),
            snapshot: fixture.snapshot
        )

        #expect(result.ambiguityStatus == .weakOnly)
        #expect(result.recommendedMatch == nil)
    }

    @Test func groceryLemmaExactDominatesWeakerExpenseTextMatches() {
        let fixture = makeFixture()
        let result = search("Grocery", request: expenseSpendRequest(), snapshot: fixture.snapshot)

        #expect(result.ambiguityStatus == .obvious)
        #expect(result.recommendedMatch?.entity == .category)
        #expect(result.recommendedMatch?.displayName == "Groceries")
        #expect(result.recommendedMatch?.matchStrength == .normalizedExact)
        #expect(result.matches.contains { $0.displayName == "Grocery Outlet" && $0.matchStrength == .prefix })
    }

    @Test func equallyStrongCrossMeaningMatchesRemainAmbiguous() {
        let fixture = makeFixture(includeExactGroceriesExpense: true)
        let result = search("Groceries", request: expenseSpendRequest(), snapshot: fixture.snapshot)

        #expect(result.ambiguityStatus == .ambiguous)
        #expect(result.recommendedMatch == nil)
        #expect(result.matches.contains { $0.entity == .category && $0.matchStrength == .exact })
        #expect(result.matches.contains { $0.entity == .variableExpense && $0.matchStrength == .exact })
    }

    @Test func uniquePrefixOnlyMatchIsNeverRecommended() {
        let fixture = makeFixture()
        let result = search("Emerg", request: expenseSpendRequest(), snapshot: fixture.snapshot)

        #expect(result.matches.first?.displayName == "Emergency Fund")
        #expect(result.matches.first?.matchStrength == .prefix)
        #expect(result.ambiguityStatus == .weakOnly)
        #expect(result.recommendedMatch == nil)
    }

    @Test func exactWorkspaceAliasResolvesToItsLiveCategory() {
        let fixture = makeFixture(includeCategoryAlias: true)
        let result = search("Food", request: expenseSpendRequest(), snapshot: fixture.snapshot)

        #expect(result.ambiguityStatus == .obvious)
        #expect(result.recommendedMatch?.entity == .category)
        #expect(result.recommendedMatch?.displayName == "Groceries")
        #expect(result.recommendedMatch?.matchStrength == .exact)
        #expect(result.recommendedMatch?.evidence == .assistantAlias)
    }

    @Test func conflictingExactWorkspaceAliasesRemainAmbiguous() {
        let fixture = makeFixture(includeConflictingAliases: true)
        let result = search("Daily", request: expenseSpendRequest(), snapshot: fixture.snapshot)

        #expect(result.ambiguityStatus == .ambiguous)
        #expect(result.recommendedMatch == nil)
        #expect(result.matches.contains { $0.entity == .category && $0.displayName == "Groceries" })
        #expect(result.matches.contains { $0.entity == .card && $0.displayName == "Apple Card" })
    }

    @Test func exactImportMerchantRuleAddsMerchantEvidenceWithoutRows() {
        let fixture = makeFixture(includeMerchantRule: true)
        let result = search("Whole Foods", request: expenseSpendRequest(), snapshot: fixture.snapshot)

        #expect(result.ambiguityStatus == .obvious)
        #expect(result.recommendedMatch?.entity == .variableExpense)
        #expect(result.recommendedMatch?.fieldName == "merchantText")
        #expect(result.recommendedMatch?.displayName == "Whole Foods")
        #expect(result.recommendedMatch?.evidence == .importMerchantRule)
    }

    @Test func candidateEvidenceUsesHomeCalculationEligibleRows() {
        let fixture = makeFixture(includeIneligibleRawExpense: true)
        let result = search("Future Only Merchant", request: expenseSpendRequest(), snapshot: fixture.snapshot)

        #expect(result.matches.isEmpty)
        #expect(result.ambiguityStatus == .noUsefulCandidate)
    }

    private func search(
        _ target: String,
        request: MarinaSemanticRequest,
        snapshot: MarinaWorkspaceSnapshot
    ) -> MarinaCandidateSearchResult {
        service.search(
            MarinaCandidateSearchRequest(
                rawTargetText: target,
                semanticRequest: request,
                snapshot: snapshot
            )
        )
    }

    private func expenseSpendRequest() -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            targetName: "Target",
            expectedAnswerShape: .metric
        )
    }

    private func merchantTextRequest() -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.merchantText],
            textQuery: "Store Apple",
            expectedAnswerShape: .metric
        )
    }

    private func makeFixture(
        includeRepeatedTarget: Bool = false,
        includeExactGroceriesExpense: Bool = false,
        includeCategoryAlias: Bool = false,
        includeConflictingAliases: Bool = false,
        includeMerchantRule: Bool = false,
        includeIneligibleRawExpense: Bool = false
    ) -> CandidateSearchFixture {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let appleCard = Card(name: "Apple Card", workspace: workspace)
        let groceries = Offshore.Category(name: "Groceries", hexColor: "#22C55E", workspace: workspace)
        let budget = Budget(name: "July 2026", startDate: date(2026, 7, 1), endDate: date(2026, 7, 31), workspace: workspace)
        let preset = Preset(title: "Monthly Grocery Plan", plannedAmount: 200, workspace: workspace, defaultCard: appleCard, defaultCategory: groceries)
        let savings = SavingsAccount(name: "Emergency Fund", workspace: workspace)
        let alejandro = AllocationAccount(name: "Alejandro", workspace: workspace)
        let paycheck = Income(source: "Paycheck", amount: 3_000, date: date(2026, 7, 1), isPlanned: false, workspace: workspace)
        let appleStore = VariableExpense(descriptionText: "Apple Store", amount: 120, transactionDate: date(2026, 7, 5), workspace: workspace, card: appleCard, category: groceries)
        let groceryOutlet = VariableExpense(descriptionText: "Grocery Outlet", amount: 42, transactionDate: date(2026, 7, 6), workspace: workspace, card: appleCard, category: groceries)
        let target = VariableExpense(descriptionText: "Target groceries", amount: 80, transactionDate: date(2026, 7, 7), workspace: workspace, card: appleCard, category: groceries)
        let repeatedTarget = VariableExpense(descriptionText: "Target groceries", amount: 55, transactionDate: date(2026, 7, 8), workspace: workspace, card: appleCard, category: groceries)
        let exactGroceries = VariableExpense(descriptionText: "Groceries", amount: 15, transactionDate: date(2026, 7, 8), workspace: workspace, card: appleCard, category: groceries)
        let ineligibleRawExpense = VariableExpense(descriptionText: "Future Only Merchant", amount: 25, transactionDate: date(2027, 7, 8), workspace: workspace, card: appleCard, category: groceries)
        let planned = PlannedExpense(title: "Grocery Envelope", plannedAmount: 200, expenseDate: date(2026, 7, 10), workspace: workspace, card: appleCard, category: groceries)
        var eligibleVariableExpenses = [appleStore, groceryOutlet, target]
        if includeRepeatedTarget { eligibleVariableExpenses.append(repeatedTarget) }
        if includeExactGroceriesExpense { eligibleVariableExpenses.append(exactGroceries) }
        var rawVariableExpenses = eligibleVariableExpenses
        if includeIneligibleRawExpense { rawVariableExpenses.append(ineligibleRawExpense) }
        let categoryAlias = AssistantAliasRule(
            aliasKey: "Food",
            targetValue: "Groceries",
            entityType: .category,
            workspace: workspace
        )
        let categoryConflict = AssistantAliasRule(
            aliasKey: "Daily",
            targetValue: "Groceries",
            entityType: .category,
            workspace: workspace
        )
        let cardConflict = AssistantAliasRule(
            aliasKey: "Daily",
            targetValue: "Apple Card",
            entityType: .card,
            workspace: workspace
        )
        let merchantRule = ImportMerchantRule(
            merchantKey: "WHOLE FOODS",
            preferredName: "Whole Foods",
            preferredCategory: groceries,
            workspace: workspace
        )
        let assistantAliasRules = includeConflictingAliases
            ? [categoryConflict, cardConflict]
            : (includeCategoryAlias ? [categoryAlias] : [])
        let snapshot = MarinaWorkspaceSnapshot(
            workspace: workspace,
            budgets: [budget],
            cards: [appleCard],
            categories: [groceries],
            presets: [preset],
            plannedExpenses: [planned],
            variableExpenses: rawVariableExpenses,
            homePlannedExpenses: [planned],
            homeCalculationPlannedExpenses: [planned],
            homeCalculationVariableExpenses: eligibleVariableExpenses,
            reconciliationAccounts: [alejandro],
            expenseAllocations: [],
            allocationSettlements: [],
            savingsAccounts: [savings],
            savingsEntries: [],
            incomes: [paycheck],
            importMerchantRules: includeMerchantRule ? [merchantRule] : [],
            assistantAliasRules: assistantAliasRules
        )
        return CandidateSearchFixture(snapshot: snapshot)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }
}

private struct CandidateSearchFixture {
    let snapshot: MarinaWorkspaceSnapshot
}
