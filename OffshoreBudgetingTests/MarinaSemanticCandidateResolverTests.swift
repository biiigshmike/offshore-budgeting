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

    @Test func explicitPromptTargetFallbackRecoversDroppedCategoryAndTracesSearch() {
        let fixture = makeFixture(includeHairCareCategory: true)
        let validator = MarinaSemanticRequestValidator()
        let interpreted = MarinaInterpretedSemanticRequest(
            request: MarinaSemanticRequest(
                entity: .variableExpense,
                operation: .list,
                measure: .budgetImpact,
                dimensions: [.category, .merchantText],
                dateRangeToken: .previousMonth,
                resultLimit: 10,
                expectedAnswerShape: .list
            ),
            confidence: .medium,
            source: .foundationModel
        )

        let trace = validator.validateWithTrace(
            interpreted: interpreted,
            snapshot: fixture.snapshot,
            originalPrompt: "What did I spend on Hair Care last month?"
        )

        #expect(trace.interpreted.request.entity == .variableExpense)
        #expect(trace.interpreted.request.operation == .list)
        #expect(trace.interpreted.request.measure == .budgetImpact)
        #expect(trace.interpreted.request.dimensions == [.category])
        #expect(trace.interpreted.request.dimensions.contains(.merchantText) == false)
        #expect(trace.interpreted.request.dateRangeToken == .previousMonth)
        #expect(trace.interpreted.request.targetName == "Hair Care")
        #expect(trace.interpreted.request.targetDisplayName == "Hair Care")
        #expect(trace.interpreted.request.expenseScope == .unified)
        #expect(trace.interpreted.request.expectedAnswerShape == .list)
        #expect(trace.candidateSearches.contains { $0.rawTargetText == "Hair Care" && $0.slot == "explicitPromptTarget" })
    }

    @Test func explicitPromptTargetFallbackDoesNotAutoSelectWeakMatches() {
        let fixture = makeFixture(includeAppleMerchant: true)
        let interpreted = MarinaInterpretedSemanticRequest(
            request: MarinaSemanticRequest(
                entity: .variableExpense,
                operation: .sum,
                measure: .budgetImpact,
                dimensions: [.merchantText],
                expectedAnswerShape: .metric
            ),
            confidence: .medium,
            source: .foundationModel
        )

        let resolved = resolver.resolveExplicitPromptTargetsWithTrace(
            interpreted: interpreted,
            snapshot: fixture.snapshot,
            explicitPromptTargets: ["Store Apple"]
        )

        #expect(resolved.interpreted.request == interpreted.request)
        #expect(resolved.candidateSearches.first?.ambiguityStatus == .weakOnly)
        #expect(resolved.candidateSearches.first?.recommendedDisplayName == nil)
    }

    @Test func explicitPromptTargetFallbackClarifiesAmbiguousStrongMatches() {
        let fixture = makeFixture(includeTargetCategory: true)
        let interpreted = MarinaInterpretedSemanticRequest(
            request: MarinaSemanticRequest(
                entity: .variableExpense,
                operation: .sum,
                measure: .budgetImpact,
                expectedAnswerShape: .metric
            ),
            confidence: .medium,
            source: .foundationModel
        )

        let resolved = resolver.resolveExplicitPromptTargetsWithTrace(
            interpreted: interpreted,
            snapshot: fixture.snapshot,
            explicitPromptTargets: ["Target"]
        )

        #expect(resolved.interpreted.request.expectedAnswerShape == .clarification)
        #expect(resolved.interpreted.request.unsupportedReason == .ambiguousEntity)
        #expect(resolved.interpreted.clarificationChoices?.choices.contains { $0.title == "Target" && $0.kindLabel == "Category" } == true)
        #expect(resolved.interpreted.clarificationChoices?.choices.contains { $0.title == "Target groceries" && $0.kindLabel == "Expense match" } == true)
    }

    @Test func explicitPromptTargetFallbackUsesCategoryHintAndDropsContradictoryMerchantDimension() {
        let fixture = makeFixture(includeTargetCategory: true)
        let interpreted = MarinaInterpretedSemanticRequest(
            request: MarinaSemanticRequest(
                entity: .variableExpense,
                operation: .list,
                measure: .budgetImpact,
                dimensions: [.category, .merchantText],
                expectedAnswerShape: .list
            ),
            confidence: .medium,
            source: .foundationModel
        )

        let resolved = resolver.resolveExplicitPromptTargetsWithTrace(
            interpreted: interpreted,
            snapshot: fixture.snapshot,
            explicitPromptTargets: ["Target"]
        )

        #expect(resolved.interpreted.request.entity == .variableExpense)
        #expect(resolved.interpreted.request.dimensions == [.category])
        #expect(resolved.interpreted.request.dimensions.contains(.merchantText) == false)
        #expect(resolved.interpreted.request.targetName == "Target")
        #expect(resolved.interpreted.request.textQuery == nil)
    }

    @Test func existingTargetPathStillResolvesCategoryHint() {
        let fixture = makeFixture(includeHairCareCategory: true)
        let resolved = resolve(
            MarinaSemanticRequest(
                entity: .variableExpense,
                operation: .list,
                measure: .budgetImpact,
                dimensions: [.category],
                targetName: "Hair Care",
                expectedAnswerShape: .list
            ),
            snapshot: fixture.snapshot
        )

        #expect(resolved.request.entity == .variableExpense)
        #expect(resolved.request.dimensions == [.category])
        #expect(resolved.request.targetName == "Hair Care")
        #expect(resolved.request.expectedAnswerShape == .list)
    }

    @Test func explicitPromptTargetsPreferLongestNonOverlappingCardMatch() {
        let fixture = makeFixture(includeNestedAppleText: true)
        let trace = validate(
            MarinaSemanticRequest(
                entity: .card,
                operation: .list,
                measure: .budgetImpact,
                dimensions: [.card],
                expectedAnswerShape: .list
            ),
            snapshot: fixture.snapshot,
            originalPrompt: "Show my Apple Card expenses."
        )

        #expect(trace.explicitPromptTargets == ["Apple Card"])
        #expect(trace.explicitPromptTargets.contains("Apple") == false)
    }

    @Test func explicitPromptTargetsKeepTwoPromptOrderedCardTargetsForComparison() {
        let fixture = makeFixture(includeDebitCard: true, includeNestedAppleText: true)
        let trace = validate(
            MarinaSemanticRequest(
                entity: .card,
                operation: .compare,
                measure: .budgetImpact,
                dimensions: [.card],
                dateRangeToken: .previousMonth,
                expectedAnswerShape: .comparison
            ),
            snapshot: fixture.snapshot,
            originalPrompt: "Compare Apple Card to Debit Card last month."
        )

        #expect(trace.explicitPromptTargets == ["Apple Card", "Debit Card"])
        #expect(trace.explicitPromptTargets.contains("Apple") == false)
    }

    @Test func explicitPromptTargetFallbackRecoversDroppedCardComparisonTargets() {
        let fixture = makeFixture(includeDebitCard: true, includeNestedAppleText: true)
        let trace = validate(
            MarinaSemanticRequest(
                entity: .card,
                operation: .compare,
                dimensions: [.card],
                dateRangeToken: .previousMonth,
                expectedAnswerShape: .comparison
            ),
            snapshot: fixture.snapshot,
            originalPrompt: "Which was higher last month, Apple Card or Debit Card?"
        )

        #expect(trace.interpreted.request.entity == .card)
        #expect(trace.interpreted.request.operation == .compare)
        #expect(trace.interpreted.request.measure == .budgetImpact)
        #expect(trace.interpreted.request.dimensions == [.card])
        #expect(trace.interpreted.request.dateRangeToken == .previousMonth)
        #expect(trace.interpreted.request.targetName == "Apple Card")
        #expect(trace.interpreted.request.comparisonTargetName == "Debit Card")
        #expect(trace.interpreted.request.expectedAnswerShape == .comparison)
        #expect(trace.candidateSearches.contains { $0.rawTargetText == "Apple Card" && $0.slot == "explicitPromptTarget" })
        #expect(trace.candidateSearches.contains { $0.rawTargetText == "Debit Card" && $0.slot == "explicitPromptTarget" })
    }

    @Test func explicitPromptTargetFallbackRepairsNaturalCardComparisonListShape() {
        let fixture = makeFixture(includeDebitCard: true)
        let trace = validate(
            MarinaSemanticRequest(
                entity: .card,
                operation: .list,
                dimensions: [.card, .card],
                dateRangeToken: .previousPeriod,
                expectedAnswerShape: .list
            ),
            snapshot: fixture.snapshot,
            originalPrompt: "Compare my debit card and Apple Card spend last month."
        )

        #expect(trace.interpreted.request.entity == .card)
        #expect(trace.interpreted.request.operation == .compare)
        #expect(trace.interpreted.request.measure == .budgetImpact)
        #expect(trace.interpreted.request.dimensions == [.card])
        #expect(trace.interpreted.request.dateRangeToken == .previousPeriod)
        #expect(trace.interpreted.request.targetName == "Debit Card")
        #expect(trace.interpreted.request.comparisonTargetName == "Apple Card")
        #expect(trace.interpreted.request.expectedAnswerShape == .comparison)
        #expect(trace.interpreted.request.unsupportedReason == nil)
        #expect(trace.interpreted.clarificationChoices == nil)
    }

    @Test func explicitPromptTargetFallbackKeepsSimplerCardComparisonRecovery() {
        let fixture = makeFixture(includeDebitCard: true)
        let trace = validate(
            MarinaSemanticRequest(
                entity: .card,
                operation: .compare,
                measure: .budgetImpact,
                dimensions: [.card],
                dateRangeToken: .previousMonth,
                expectedAnswerShape: .comparison
            ),
            snapshot: fixture.snapshot,
            originalPrompt: "Compare Debit Card and Apple Card last month."
        )

        #expect(trace.interpreted.request.entity == .card)
        #expect(trace.interpreted.request.operation == .compare)
        #expect(trace.interpreted.request.measure == .budgetImpact)
        #expect(trace.interpreted.request.dimensions == [.card])
        #expect(trace.interpreted.request.targetName == "Debit Card")
        #expect(trace.interpreted.request.comparisonTargetName == "Apple Card")
        #expect(trace.interpreted.request.expectedAnswerShape == .comparison)
        #expect(trace.interpreted.clarificationChoices == nil)
    }

    @Test func explicitPromptTargetFallbackDoesNotRepairWeakSecondCardComparisonTarget() {
        let fixture = makeFixture()
        let interpreted = MarinaInterpretedSemanticRequest(
            request: MarinaSemanticRequest(
                entity: .card,
                operation: .list,
                dimensions: [.card, .card],
                dateRangeToken: .previousPeriod,
                expectedAnswerShape: .list
            ),
            confidence: .medium,
            source: .foundationModel
        )

        let resolved = resolver.resolveExplicitPromptTargetsWithTrace(
            interpreted: interpreted,
            snapshot: fixture.snapshot,
            explicitPromptTargets: ["Apple Card", "Store Apple"],
            hasExplicitCardComparisonIntent: true
        )

        #expect(resolved.interpreted.request.expectedAnswerShape != .comparison)
        #expect(resolved.interpreted.request.comparisonTargetName == nil)
        #expect(resolved.candidateSearches.contains { $0.rawTargetText == "Store Apple" && $0.ambiguityStatus == .weakOnly })
    }

    @Test func comparisonClarificationChoiceKeepsComparisonShapeForSingleCardSelection() {
        let fixture = makeFixture(includeUberMerchant: true, includeUberCard: true)
        let interpreted = MarinaInterpretedSemanticRequest(
            request: MarinaSemanticRequest(
                entity: .card,
                operation: .list,
                dimensions: [.card, .card],
                dateRangeToken: .previousPeriod,
                expectedAnswerShape: .list
            ),
            confidence: .medium,
            source: .foundationModel
        )

        let resolved = resolver.resolveExplicitPromptTargetsWithTrace(
            interpreted: interpreted,
            snapshot: fixture.snapshot,
            explicitPromptTargets: ["Apple Card", "Uber"],
            hasExplicitCardComparisonIntent: true
        )

        #expect(resolved.interpreted.request.expectedAnswerShape == .clarification)
        let appleChoice = resolved.interpreted.clarificationChoices?.choices.first {
            $0.title == "Apple Card" && $0.kindLabel == "Card"
        }
        #expect(appleChoice?.request.entity == .card)
        #expect(appleChoice?.request.operation == .compare)
        #expect(appleChoice?.request.measure == .budgetImpact)
        #expect(appleChoice?.request.dimensions == [.card])
        #expect(appleChoice?.request.targetName == "Apple Card")
        #expect(appleChoice?.request.comparisonTargetName == nil)
        #expect(appleChoice?.request.expectedAnswerShape == .comparison)
    }

    @Test func explicitPromptTargetFallbackRecoversAppleCardExpenseList() {
        let fixture = makeFixture(includeNestedAppleText: true)
        let trace = validate(
            MarinaSemanticRequest(
                entity: .card,
                operation: .list,
                measure: .budgetImpact,
                dimensions: [.card],
                resultLimit: 20,
                expectedAnswerShape: .list
            ),
            snapshot: fixture.snapshot,
            originalPrompt: "Show my Apple Card expenses."
        )

        #expect(trace.interpreted.request.entity == .variableExpense)
        #expect(trace.interpreted.request.operation == .list)
        #expect(trace.interpreted.request.measure == .budgetImpact)
        #expect(trace.interpreted.request.dimensions == [.card])
        #expect(trace.interpreted.request.targetName == "Apple Card")
        #expect(trace.interpreted.request.targetDisplayName == "Apple Card")
        #expect(trace.interpreted.request.resultLimit == 20)
        #expect(trace.interpreted.request.expenseScope == .unified)
        #expect(trace.interpreted.request.expectedAnswerShape == .list)
    }

    @Test func explicitPromptTargetFallbackRecoversUberListFromBadCardHint() {
        let fixture = makeFixture(includeUberMerchant: true)
        let trace = validate(
            MarinaSemanticRequest(
                entity: .card,
                operation: .list,
                measure: .budgetImpact,
                dimensions: [.card],
                expectedAnswerShape: .list
            ),
            snapshot: fixture.snapshot,
            originalPrompt: "Show my Uber expenses."
        )

        #expect(trace.interpreted.request.entity == .variableExpense)
        #expect(trace.interpreted.request.operation == .list)
        #expect(trace.interpreted.request.measure == .budgetImpact)
        #expect(trace.interpreted.request.dimensions == [.merchantText])
        #expect(trace.interpreted.request.textQuery == "Uber")
        #expect(trace.interpreted.request.targetDisplayName == "Uber")
        #expect(trace.interpreted.request.targetName == nil)
        #expect(trace.interpreted.request.expenseScope == .unified)
        #expect(trace.interpreted.request.expectedAnswerShape == .list)
        #expect(trace.candidateSearches.contains { $0.rawTargetText == "Uber" && $0.slot == "explicitPromptTarget" })
    }

    @Test func explicitPromptTargetFallbackRecoversUberMetricFromBadCardHint() {
        let fixture = makeFixture(includeUberMerchant: true)
        let trace = validate(
            MarinaSemanticRequest(
                entity: .card,
                operation: .sum,
                measure: .budgetImpact,
                dimensions: [.card],
                expectedAnswerShape: .metric
            ),
            snapshot: fixture.snapshot,
            originalPrompt: "What did I spend at Uber?"
        )

        #expect(trace.interpreted.request.entity == .variableExpense)
        #expect(trace.interpreted.request.operation == .sum)
        #expect(trace.interpreted.request.measure == .budgetImpact)
        #expect(trace.interpreted.request.dimensions == [.merchantText])
        #expect(trace.interpreted.request.textQuery == "Uber")
        #expect(trace.interpreted.request.targetDisplayName == "Uber")
        #expect(trace.interpreted.request.expenseScope == .unified)
        #expect(trace.interpreted.request.expectedAnswerShape == .metric)
    }

    @Test func explicitPromptTargetFallbackClarifiesExactCardAndExpenseTextWhenUntyped() {
        let fixture = makeFixture(includeUberMerchant: true, includeUberCard: true)
        let trace = validate(
            MarinaSemanticRequest(
                entity: .variableExpense,
                operation: .sum,
                measure: .budgetImpact,
                expectedAnswerShape: .metric
            ),
            snapshot: fixture.snapshot,
            originalPrompt: "Show my Uber expenses."
        )

        #expect(trace.interpreted.request.expectedAnswerShape == .clarification)
        #expect(trace.interpreted.request.unsupportedReason == .ambiguousEntity)
        #expect(trace.interpreted.clarificationChoices?.choices.contains { $0.title == "Uber" && $0.kindLabel == "Card" } == true)
        #expect(trace.interpreted.clarificationChoices?.choices.contains { $0.title == "Uber" && $0.kindLabel == "Expense match" } == true)
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

    private func validate(
        _ request: MarinaSemanticRequest,
        snapshot: MarinaWorkspaceSnapshot,
        originalPrompt: String
    ) -> MarinaSemanticValidationTrace {
        let validator = MarinaSemanticRequestValidator()
        return validator.validateWithTrace(
            interpreted: MarinaInterpretedSemanticRequest(
                request: request,
                confidence: .medium,
                source: .foundationModel
            ),
            snapshot: snapshot,
            originalPrompt: originalPrompt
        )
    }

    private func makeFixture(
        includeTargetCategory: Bool = false,
        includeAppleMerchant: Bool = false,
        includeHairCareCategory: Bool = false,
        includeDebitCard: Bool = false,
        includeNestedAppleText: Bool = false,
        includeUberMerchant: Bool = false,
        includeUberCard: Bool = false
    ) -> ResolverFixture {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let appleCard = Card(name: "Apple Card", workspace: workspace)
        let chaseCard = Card(name: "Chase Card", workspace: workspace)
        let debitCard = includeDebitCard
            ? Card(name: "Debit Card", workspace: workspace)
            : nil
        let uberCard = includeUberCard
            ? Card(name: "Uber", workspace: workspace)
            : nil
        let groceries = Offshore.Category(name: "Groceries", hexColor: "#22C55E", workspace: workspace)
        let hairCare = includeHairCareCategory
            ? Offshore.Category(name: "Hair Care", hexColor: "#DB2777", workspace: workspace)
            : nil
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
        let apple = includeNestedAppleText
            ? VariableExpense(descriptionText: "Apple", amount: 9, transactionDate: date(2026, 7, 11), workspace: workspace, card: appleCard, category: groceries)
            : nil
        let uberExpenses = includeUberMerchant
            ? [
                VariableExpense(descriptionText: "Uber", amount: 18, transactionDate: date(2026, 7, 12), workspace: workspace, card: chaseCard, category: groceries),
                VariableExpense(descriptionText: "Uber", amount: 21, transactionDate: date(2026, 7, 13), workspace: workspace, card: chaseCard, category: groceries),
                VariableExpense(descriptionText: "Uber", amount: 16, transactionDate: date(2026, 7, 14), workspace: workspace, card: chaseCard, category: groceries)
            ]
            : []
        let planned = PlannedExpense(title: "Grocery Envelope", plannedAmount: 200, expenseDate: date(2026, 7, 10), workspace: workspace, card: chaseCard, category: groceries)
        let categories = [groceries] + [targetCategory, hairCare].compactMap { $0 }
        let cards = [appleCard, chaseCard] + [debitCard, uberCard].compactMap { $0 }
        let variableExpenses = [target, groceryOutlet] + [appleStore, apple].compactMap { $0 } + uberExpenses
        let snapshot = MarinaWorkspaceSnapshot(
            workspace: workspace,
            budgets: [budget],
            cards: cards,
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
