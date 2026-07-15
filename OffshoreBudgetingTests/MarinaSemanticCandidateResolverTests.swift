import Foundation
import Testing
@testable import Offshore

struct MarinaSemanticCandidateResolverTests {
    private let resolver = MarinaSemanticCandidateResolver()

    @Test func targetMerchantPrefixIsSuggestedWithoutExecution() {
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

        #expect(resolved.request.expectedAnswerShape == .clarification)
        #expect(resolved.request.unsupportedReason == .ambiguousEntity)
        #expect(resolved.clarificationChoices?.choices.count == 1)
        #expect(resolved.clarificationChoices?.choices.first?.title == "Target groceries")
    }

    @Test func exactCategoryDominatesWeakerMerchantSuggestion() {
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

        #expect(resolved.request.expectedAnswerShape == .metric)
        #expect(resolved.request.resolvedTarget?.entity == .category)
        #expect(resolved.request.resolvedTarget?.displayName == "Target")
        #expect(resolved.clarificationChoices == nil)
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

    @Test func appleCardPrefixRequiresClarificationDespiteMerchantMatch() throws {
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

        let choice = try #require(resolved.clarificationChoices?.choices.first)
        #expect(resolved.request.entity == .card)
        #expect(resolved.request.dimensions == [.card])
        #expect(resolved.request.targetName == "Apple")
        #expect(resolved.request.expectedAnswerShape == .clarification)
        #expect(resolved.request.resolvedTarget == nil)
        #expect(choice.title == "Apple Card")
        #expect(choice.kindLabel == "Card")
        #expect(choice.executableRequest.resolvedTarget?.id == fixture.snapshot.cards.first(where: { $0.name == "Apple Card" })?.id)
        #expect(choice.executableRequest.resolvedTarget?.provenance == .clarificationChoice)
        #expect(choice.executableRequest.resolvedScope == .workspace(fixture.snapshot.workspace.id))
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
        #expect(resolved.request.resolvedTarget?.id == fixture.snapshot.categories.first(where: { $0.name == "Groceries" })?.id)
        #expect(resolved.request.resolvedTarget?.provenance == .candidateResolver)
        #expect(resolved.request.resolvedScope == .workspace(fixture.snapshot.workspace.id))
    }

    @Test func exactCategoryAndExactMerchantRequireClarification() throws {
        let fixture = makeFixture(includeExactGroceriesMerchant: true)
        let resolved = resolve(
            MarinaSemanticRequest(
                entity: .variableExpense,
                operation: .sum,
                measure: .budgetImpact,
                targetName: "Groceries",
                expectedAnswerShape: .metric
            ),
            snapshot: fixture.snapshot
        )

        let choices = try #require(resolved.clarificationChoices)
        let categoryChoice = try #require(choices.choices.first { $0.kindLabel == "Category" })
        let merchantChoice = try #require(choices.choices.first { $0.kindLabel == "Expense match" })

        #expect(resolved.request.expectedAnswerShape == .clarification)
        #expect(categoryChoice.executableRequest.resolvedTarget?.id != nil)
        #expect(merchantChoice.executableRequest.resolvedTarget?.id == nil)
        #expect(categoryChoice.meaningKey != merchantChoice.meaningKey)
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

    @Test func exactTypedComparisonResolvesBothSlotsByID() {
        let fixture = makeFixture()
        let resolved = resolve(
            MarinaSemanticRequest(
                entity: .card,
                operation: .compare,
                measure: .budgetImpact,
                dimensions: [.card],
                targetName: "Apple Card",
                comparisonTargetName: "Chase Card",
                expectedAnswerShape: .comparison
            ),
            snapshot: fixture.snapshot
        )

        #expect(resolved.request.entity == .card)
        #expect(resolved.request.targetName == "Apple Card")
        #expect(resolved.request.comparisonTargetName == "Chase Card")
        #expect(resolved.request.expectedAnswerShape == .comparison)
        #expect(resolved.request.resolvedTarget?.id == fixture.snapshot.cards.first(where: { $0.name == "Apple Card" })?.id)
        #expect(resolved.request.resolvedComparisonTarget?.id == fixture.snapshot.cards.first(where: { $0.name == "Chase Card" })?.id)
        #expect(resolved.request.resolvedTarget?.provenance == .candidateResolver)
        #expect(resolved.request.resolvedComparisonTarget?.provenance == .candidateResolver)
        #expect(resolved.request.resolvedScope == .workspace(fixture.snapshot.workspace.id))
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

    @Test func typedComparisonClarificationChoiceRetainsResolvedFirstSlotWhenSecondIsAmbiguous() throws {
        let fixture = makeFixture(
            includeUberMerchant: true,
            includeUberCard: true,
            includeDuplicateUberCard: true
        )
        let interpreted = MarinaInterpretedSemanticRequest(
            request: MarinaSemanticRequest(
                entity: .card,
                operation: .compare,
                measure: .budgetImpact,
                dimensions: [.card],
                dateRangeToken: .previousPeriod,
                targetName: "Apple Card",
                comparisonTargetName: "Uber",
                expectedAnswerShape: .comparison
            ),
            confidence: .medium,
            source: .foundationModel
        )

        let resolved = resolver.resolveWithTrace(
            interpreted: interpreted,
            snapshot: fixture.snapshot
        )

        #expect(resolved.interpreted.request.expectedAnswerShape == .clarification)
        let appleCardID: UUID? = fixture.snapshot.cards.first(where: {
            $0.name == "Apple Card"
        })?.id
        let uberCards = fixture.snapshot.cards.filter { $0.name == "Uber" }
        let uberCardIDs: Set<UUID> = Set(uberCards.map(\.id))
        #expect(resolved.interpreted.request.targetName == "Apple Card")
        #expect(resolved.interpreted.request.resolvedTarget?.id == appleCardID)
        #expect(resolved.interpreted.request.resolvedComparisonTarget == nil)

        let uberCardChoices = resolved.interpreted.clarificationChoices?.choices.filter {
            $0.title == "Uber" && $0.kindLabel == "Card"
        } ?? []
        let executableRequest: MarinaSemanticRequest = try #require(
            uberCardChoices.first?.executableRequest
        )
        let comparisonTargetID: UUID = try #require(
            executableRequest.resolvedComparisonTarget?.id
        )
        let resolvedUberCardIDs: Set<UUID> = Set(
            uberCardChoices.compactMap { choice -> UUID? in
                choice.executableRequest.resolvedComparisonTarget?.id
            }
        )
        #expect(uberCardChoices.count == 2)
        #expect(resolvedUberCardIDs == uberCardIDs)
        #expect(executableRequest.entity == .card)
        #expect(executableRequest.operation == .compare)
        #expect(executableRequest.measure == .budgetImpact)
        #expect(executableRequest.dimensions == [.card])
        #expect(executableRequest.targetName == "Apple Card")
        #expect(executableRequest.comparisonTargetName == "Uber")
        #expect(executableRequest.resolvedTarget?.id == appleCardID)
        #expect(uberCardIDs.contains(comparisonTargetID))
        #expect(executableRequest.resolvedTarget?.provenance == .candidateResolver)
        #expect(executableRequest.resolvedComparisonTarget?.provenance == .clarificationChoice)
        #expect(executableRequest.expectedAnswerShape == .comparison)
    }

    @Test func groceryLemmaCategoryDominatesWeakerMerchantSuggestions() throws {
        let fixture = makeFixture()
        let resolved = resolve(
            MarinaSemanticRequest(
                entity: .variableExpense,
                operation: .sum,
                measure: .budgetImpact,
                targetName: "Grocery",
                expectedAnswerShape: .metric
            ),
            snapshot: fixture.snapshot
        )

        let categoryID = try #require(fixture.snapshot.categories.first(where: { $0.name == "Groceries" })?.id)

        #expect(resolved.clarificationChoices == nil)
        #expect(resolved.request.resolvedTarget?.id == categoryID)
        #expect(resolved.request.resolvedTarget?.displayName == "Groceries")
        #expect(resolved.request.resolvedScope == .workspace(fixture.snapshot.workspace.id))
    }

    @Test func duplicateExactCategoryNamesRemainDistinctIDBackedChoices() throws {
        let fixture = makeFixture(includeDuplicateGroceriesCategory: true)
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

        let choices = try #require(resolved.clarificationChoices)
        let categoryChoices = choices.choices.filter { $0.kindLabel == "Category" }
        let sourceIDs = Set(categoryChoices.compactMap { $0.executableRequest.resolvedTarget?.id })
        let expectedIDs = Set(fixture.snapshot.categories.filter { $0.name == "Groceries" }.map(\.id))

        #expect(categoryChoices.count == 2)
        #expect(sourceIDs == expectedIDs)
        #expect(Set(categoryChoices.map(\.meaningKey)).count == 2)
        #expect(choices.choice(matching: "Groceries") == nil)
        #expect(categoryChoices.allSatisfy {
            $0.executableRequest.resolvedTarget?.provenance == .clarificationChoice
        })
    }

    @Test func resolvedBudgetCandidateSelectsBudgetScope() {
        let fixture = makeFixture()
        let budget = fixture.snapshot.budgets[0]
        let resolved = resolve(
            MarinaSemanticRequest(
                entity: .budget,
                operation: .forecast,
                measure: .budgetImpact,
                dimensions: [.budget],
                targetName: budget.name,
                expectedAnswerShape: .metric
            ),
            snapshot: fixture.snapshot
        )

        #expect(resolved.request.resolvedTarget?.id == budget.id)
        #expect(resolved.request.resolvedTarget?.provenance == .candidateResolver)
        #expect(resolved.request.resolvedScope == .budget(budget.id))
    }

    @Test func constraintOnlyNamedBudgetResolvesStableScopeAndUsesWholeBudgetRangeByDefault() throws {
        let fixture = makeFixture()
        let budget = try #require(fixture.snapshot.budgets.first)
        let resolved = resolve(
            MarinaSemanticRequest(
                entity: .budget,
                operation: .list,
                projection: .summary,
                constraints: [
                    MarinaSemanticConstraint(
                        dimension: .budget,
                        value: "July 2026",
                        kindSource: .explicit
                    )
                ],
                expectedAnswerShape: .list
            ),
            snapshot: fixture.snapshot
        )

        #expect(resolved.request.expectedAnswerShape == .list)
        #expect(resolved.request.constraints.first?.resolvedReference?.id == budget.id)
        #expect(resolved.request.resolvedScope == .budget(budget.id))
        #expect(resolved.request.dateRangeToken == .allTime)
        #expect(resolved.request.dateRangeSource == .defaulted)
    }

    @Test func multipleTypedConstraintsResolveIndependently() throws {
        let fixture = makeFixture()
        let category = try #require(fixture.snapshot.categories.first { $0.name == "Groceries" })
        let card = try #require(fixture.snapshot.cards.first { $0.name == "Apple Card" })
        let resolved = resolve(
            MarinaSemanticRequest(
                entity: .variableExpense,
                operation: .sum,
                measure: .budgetImpact,
                constraints: [
                    MarinaSemanticConstraint(dimension: .category, value: "Grocery", kindSource: .explicit),
                    MarinaSemanticConstraint(dimension: .card, value: "Apple Card", kindSource: .explicit)
                ],
                expectedAnswerShape: .metric
            ),
            snapshot: fixture.snapshot
        )

        #expect(resolved.request.expectedAnswerShape == .metric)
        #expect(resolved.request.constraints.first { $0.dimension == .category }?.resolvedReference?.id == category.id)
        #expect(resolved.request.constraints.first { $0.dimension == .card }?.resolvedReference?.id == card.id)
        #expect(resolved.request.resolvedScope == .workspace(fixture.snapshot.workspace.id))
    }

    @Test func duplicateSameTypeConstraintRequiresIDBackedClarification() throws {
        let fixture = makeFixture(includeDuplicateGroceriesCategory: true)
        let resolved = resolve(
            MarinaSemanticRequest(
                entity: .variableExpense,
                operation: .sum,
                measure: .budgetImpact,
                constraints: [
                    MarinaSemanticConstraint(dimension: .category, value: "Groceries", kindSource: .explicit)
                ],
                expectedAnswerShape: .metric
            ),
            snapshot: fixture.snapshot
        )

        let choices = try #require(resolved.clarificationChoices?.choices)
        #expect(resolved.request.expectedAnswerShape == .clarification)
        #expect(choices.count == 2)
        #expect(Set(choices.compactMap { $0.executableRequest.constraints.first?.resolvedReference?.id }).count == 2)
        #expect(choices.allSatisfy { $0.subtitle?.isEmpty == false })
    }

    @Test func expenseCandidateEvidenceRespectsDateAndResolvedBudgetScope() {
        let fixture = makeFixture(includeUberMerchant: true)
        let interpreted = MarinaInterpretedSemanticRequest(
            request: MarinaSemanticRequest(
                entity: .variableExpense,
                operation: .sum,
                measure: .budgetImpact,
                constraints: [
                    MarinaSemanticConstraint(dimension: .budget, value: "July 2026", kindSource: .explicit),
                    MarinaSemanticConstraint(dimension: .merchantText, value: "Target groceries", kindSource: .explicit)
                ],
                dateRangeSource: .explicit,
                expectedAnswerShape: .metric
            ),
            confidence: .medium,
            source: .foundationModel
        )
        let resolved = resolver.resolve(
            interpreted: interpreted,
            snapshot: fixture.snapshot,
            candidateDateRange: HomeQueryDateRange(startDate: date(2026, 7, 1), endDate: date(2026, 7, 10))
        )

        // Target groceries is on the unlinked Apple Card, so a budget-scoped
        // candidate search must not use it as merchant evidence.
        #expect(resolved.request.expectedAnswerShape == .unsupported)
        #expect(resolved.request.unsupportedReason == .unresolvedEntity)
    }

    @Test func explicitMerchantPrefixExecutesOneAggregateExpenseTextMeaning() {
        let fixture = makeFixture()
        let resolved = resolve(
            MarinaSemanticRequest(
                entity: .variableExpense,
                operation: .sum,
                measure: .budgetImpact,
                dimensions: [.merchantText],
                targetName: "Grocery",
                textQuery: "Grocery",
                targetKindSource: .explicit,
                expectedAnswerShape: .metric
            ),
            snapshot: fixture.snapshot
        )

        #expect(resolved.request.expectedAnswerShape == .metric)
        #expect(resolved.request.textQuery == "Grocery")
        #expect(resolved.request.resolvedTarget?.entity == .variableExpense)
        #expect(resolved.request.resolvedTarget?.id == nil)
        #expect(resolved.clarificationChoices == nil)
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
        includeAppleMerchant: Bool = false,
        includeHairCareCategory: Bool = false,
        includeDebitCard: Bool = false,
        includeNestedAppleText: Bool = false,
        includeUberMerchant: Bool = false,
        includeUberCard: Bool = false,
        includeDuplicateUberCard: Bool = false,
        includeDuplicateGroceriesCategory: Bool = false,
        includeExactGroceriesMerchant: Bool = false
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
        let duplicateUberCard = includeDuplicateUberCard
            ? Card(name: "Uber", workspace: workspace)
            : nil
        let groceries = Offshore.Category(name: "Groceries", hexColor: "#22C55E", workspace: workspace)
        let duplicateGroceries = includeDuplicateGroceriesCategory
            ? Offshore.Category(name: "Groceries", hexColor: "#16A34A", workspace: workspace)
            : nil
        let hairCare = includeHairCareCategory
            ? Offshore.Category(name: "Hair Care", hexColor: "#DB2777", workspace: workspace)
            : nil
        let targetCategory = includeTargetCategory
            ? Offshore.Category(name: "Target", hexColor: "#0EA5E9", workspace: workspace)
            : nil
        let budget = Budget(name: "July 2026", startDate: date(2026, 7, 1), endDate: date(2026, 7, 31), workspace: workspace)
        let budgetCardLink = BudgetCardLink(budget: budget, card: chaseCard)
        budget.cardLinks = [budgetCardLink]
        let preset = Preset(title: "Grocery Envelope", plannedAmount: 200, workspace: workspace, defaultCard: chaseCard, defaultCategory: groceries)
        let savings = SavingsAccount(name: "Emergency Fund", workspace: workspace)
        let alejandro = AllocationAccount(name: "Alejandro", workspace: workspace)
        let target = VariableExpense(descriptionText: "Target groceries", amount: 80, transactionDate: date(2026, 7, 7), workspace: workspace, card: appleCard, category: groceries)
        let groceryOutlet = VariableExpense(descriptionText: "Grocery Outlet", amount: 42, transactionDate: date(2026, 7, 8), workspace: workspace, card: chaseCard, category: groceries)
        let exactGroceriesMerchant = includeExactGroceriesMerchant
            ? VariableExpense(descriptionText: "Groceries", amount: 24, transactionDate: date(2026, 7, 8), workspace: workspace, card: chaseCard, category: groceries)
            : nil
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
        let categories = [groceries] + [targetCategory, hairCare, duplicateGroceries].compactMap { $0 }
        let cards = [appleCard, chaseCard] + [debitCard, uberCard, duplicateUberCard].compactMap { $0 }
        let variableExpenses = [target, groceryOutlet] + [appleStore, apple, exactGroceriesMerchant].compactMap { $0 } + uberExpenses
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
