import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
@Suite(.serialized)
struct MarinaQueryResolverTests {
    @Test func resolver_resolvesCategoryMentionAgainstCurrentWorkspace() throws {
        let fixture = try makeFixture()
        let groceries = Category(name: "Groceries", hexColor: "#00AA00", workspace: fixture.workspace)
        let otherWorkspace = Workspace(name: "Other", hexColor: "#111111")
        let otherGroceries = Category(name: "Groceries", hexColor: "#FF0000", workspace: otherWorkspace)
        fixture.context.insert(groceries)
        fixture.context.insert(otherWorkspace)
        fixture.context.insert(otherGroceries)
        try fixture.context.save()

        let candidate = MarinaQueryPlanCandidate(
            source: .deterministic,
            rawPrompt: "total groceries",
            operation: .sum,
            measure: .spend,
            entityMentions: [
                MarinaUnresolvedEntityMention(role: .primaryTarget, rawText: "Groceries", typeHint: .category)
            ],
            confidence: .medium
        )

        let resolved = MarinaQueryResolver().resolve(candidate: candidate, provider: fixture.provider)

        #expect(resolved.resolvedTargets.count == 1)
        #expect(resolved.resolvedTargets.first?.displayName == "Groceries")
        #expect(resolved.resolvedTargets.first?.entityType == .category)
        #expect(resolved.resolvedTargets.first?.sourceID == groceries.id)
        #expect(resolved.resolvedTargets.first?.sourceID != otherGroceries.id)
        #expect(resolved.unresolvedMentions.isEmpty)
        #expect(resolved.ambiguousMentions.isEmpty)
    }

    @Test func resolver_resolvesCardMentionAgainstCurrentWorkspace() throws {
        let fixture = try makeFixture()
        let appleCard = Card(name: "Apple Card", workspace: fixture.workspace)
        fixture.context.insert(appleCard)
        try fixture.context.save()

        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: "total spend on my Apple Card",
            operation: .sum,
            measure: .spend,
            entityMentions: [
                MarinaUnresolvedEntityMention(role: .filter, rawText: "Apple Card", typeHint: .card)
            ],
            confidence: .high
        )

        let resolved = MarinaQueryResolver().resolve(candidate: candidate, provider: fixture.provider)

        #expect(resolved.resolvedTargets.count == 1)
        #expect(resolved.resolvedTargets.first?.role == .filter)
        #expect(resolved.resolvedTargets.first?.entityType == .card)
        #expect(resolved.resolvedTargets.first?.displayName == "Apple Card")
        #expect(resolved.unresolvedMentions.isEmpty)
    }

    @Test func resolver_resolvesAllocationAccountAndCategoryFiltersTogether() throws {
        let fixture = try makeFixture()
        let account = AllocationAccount(name: "Alejandro", workspace: fixture.workspace)
        let cannabis = Category(name: "Cannabis", hexColor: "#225522", workspace: fixture.workspace)
        fixture.context.insert(account)
        fixture.context.insert(cannabis)
        try fixture.context.save()

        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: "What had Alejandro spent on Cannabis?",
            operation: .sum,
            measure: .spend,
            entityMentions: [
                MarinaUnresolvedEntityMention(role: .filter, rawText: "Alejandro", typeHint: .allocationAccount),
                MarinaUnresolvedEntityMention(role: .filter, rawText: "Cannabis", typeHint: .category)
            ],
            confidence: .high
        )

        let resolved = MarinaQueryResolver().resolve(candidate: candidate, provider: fixture.provider)

        #expect(resolved.resolvedTargets.count == 2)
        #expect(resolved.resolvedTargets.map(\.entityType) == [.allocationAccount, .category])
        #expect(resolved.resolvedTargets.map(\.displayName) == ["Alejandro", "Cannabis"])
        #expect(resolved.unresolvedMentions.isEmpty)
        #expect(resolved.ambiguousMentions.isEmpty)
    }

    @Test func resolver_clarifiesAllocationAccountVersusMerchantCollision() throws {
        let fixture = try makeFixture()
        let account = AllocationAccount(name: "Alejandro", workspace: fixture.workspace)
        let card = Card(name: "Apple Card", workspace: fixture.workspace)
        fixture.context.insert(account)
        fixture.context.insert(card)
        fixture.context.insert(VariableExpense(
            descriptionText: "Alejandro",
            amount: 42,
            transactionDate: Date(),
            workspace: fixture.workspace,
            card: card
        ))
        try fixture.context.save()

        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: "What had Alejandro spent?",
            operation: .sum,
            measure: .spend,
            entityMentions: [
                MarinaUnresolvedEntityMention(
                    role: .filter,
                    rawText: "Alejandro",
                    typeHint: nil,
                    allowedTypeHints: [.allocationAccount, .merchant, .expense],
                    confidence: .high
                )
            ],
            confidence: .high
        )

        let resolved = MarinaQueryResolver().resolve(candidate: candidate, provider: fixture.provider)
        let choiceTypes = resolved.ambiguousMentions.first?.choices.compactMap(\.entityTypeHint).sorted { $0.rawValue < $1.rawValue } ?? []

        #expect(resolved.resolvedTargets.isEmpty)
        #expect(resolved.unresolvedMentions.isEmpty)
        #expect(resolved.ambiguousMentions.count == 1)
        #expect(choiceTypes == [.allocationAccount, .merchant])
    }

    @Test func resolver_preservesUnresolvedMentionWhenNoWorkspaceMatchExists() throws {
        let fixture = try makeFixture()
        let candidate = MarinaQueryPlanCandidate(
            source: .deterministic,
            rawPrompt: "spend on Travel",
            operation: .sum,
            measure: .spend,
            entityMentions: [
                MarinaUnresolvedEntityMention(role: .primaryTarget, rawText: "Travel", typeHint: .category)
            ],
            confidence: .medium
        )

        let resolved = MarinaQueryResolver().resolve(candidate: candidate, provider: fixture.provider)

        #expect(resolved.resolvedTargets.isEmpty)
        #expect(resolved.unresolvedMentions.count == 1)
        #expect(resolved.unresolvedMentions.first?.rawText == "Travel")
        #expect(resolved.ambiguousMentions.isEmpty)
    }

    @Test func resolver_reportsCrossDomainAmbiguityWhenTypeHintIsAbsent() throws {
        let fixture = try makeFixture()
        fixture.context.insert(Category(name: "Apple", hexColor: "#00AA00", workspace: fixture.workspace))
        fixture.context.insert(Card(name: "Apple", workspace: fixture.workspace))
        try fixture.context.save()

        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: "spend on Apple",
            operation: .sum,
            measure: .spend,
            entityMentions: [
                MarinaUnresolvedEntityMention(role: .primaryTarget, rawText: "Apple", typeHint: nil)
            ],
            confidence: .medium
        )

        let resolved = MarinaQueryResolver().resolve(candidate: candidate, provider: fixture.provider)

        #expect(resolved.resolvedTargets.isEmpty)
        #expect(resolved.unresolvedMentions.isEmpty)
        #expect(resolved.ambiguousMentions.count == 1)
        let choiceTypes = resolved.ambiguousMentions[0].choices
            .compactMap(\.entityTypeHint?.rawValue)
            .sorted()
        #expect(choiceTypes == ["card", "category"])
    }

    @Test func resolver_reportsCardVersusMerchantAmbiguityWhenTypeHintIsAbsent() throws {
        let fixture = try makeFixture()
        let appleCard = Card(name: "Apple", workspace: fixture.workspace)
        fixture.context.insert(appleCard)
        fixture.context.insert(VariableExpense(
            descriptionText: "Apple",
            amount: 9.99,
            transactionDate: Date(),
            workspace: fixture.workspace,
            card: appleCard
        ))
        try fixture.context.save()

        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: "What was my spend on Apple last period?",
            operation: .sum,
            measure: .spend,
            entityMentions: [
                MarinaUnresolvedEntityMention(role: .filter, rawText: "Apple", typeHint: nil)
            ],
            confidence: .high
        )

        let resolved = MarinaQueryResolver().resolve(candidate: candidate, provider: fixture.provider)

        #expect(resolved.resolvedTargets.isEmpty)
        #expect(resolved.unresolvedMentions.isEmpty)
        #expect(resolved.ambiguousMentions.count == 1)
        let choiceTypes = resolved.ambiguousMentions[0].choices
            .compactMap(\.entityTypeHint?.rawValue)
            .sorted()
        #expect(choiceTypes == ["card", "merchant"])
    }

    @Test func resolver_allowedTypesPreferExactCategoryOverExpensePrefixes() throws {
        let fixture = try makeFixture()
        let cannabis = Category(name: "Cannabis", hexColor: "#225522", workspace: fixture.workspace)
        let card = Card(name: "Apple Card", workspace: fixture.workspace)
        fixture.context.insert(cannabis)
        fixture.context.insert(card)
        fixture.context.insert(VariableExpense(
            descriptionText: "Cannabis Purchase 1",
            amount: 40,
            transactionDate: Date(),
            workspace: fixture.workspace,
            card: card,
            category: cannabis
        ))
        try fixture.context.save()

        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: "List my last 5 Cannabis purchases",
            operation: .listRows,
            measure: .transactionAmount,
            entityMentions: [
                MarinaUnresolvedEntityMention(
                    role: .filter,
                    rawText: "Cannabis",
                    typeHint: nil,
                    allowedTypeHints: [.category, .merchant, .expense],
                    confidence: .high
                )
            ],
            grouping: MarinaGroupingCandidate(dimension: .transaction),
            ranking: MarinaRankingCandidate(direction: .newest, limit: 5),
            limit: 5,
            confidence: .high
        )

        let resolved = MarinaQueryResolver().resolve(candidate: candidate, provider: fixture.provider)

        #expect(resolved.resolvedTargets.count == 1)
        #expect(resolved.resolvedTargets.first?.entityType == .category)
        #expect(resolved.resolvedTargets.first?.displayName == "Cannabis")
        #expect(resolved.ambiguousMentions.isEmpty)
    }

    @Test func resolver_aggregateSpendPrefersExactCategoryOverSameNamedExpenseDescription() throws {
        let fixture = try makeFixture()
        let groceries = Category(name: "Groceries", hexColor: "#00AA00", workspace: fixture.workspace)
        let card = Card(name: "Apple Card", workspace: fixture.workspace)
        fixture.context.insert(groceries)
        fixture.context.insert(card)
        fixture.context.insert(VariableExpense(
            descriptionText: "Groceries",
            amount: 42,
            transactionDate: date(2026, 5, 12),
            workspace: fixture.workspace,
            card: card,
            category: groceries
        ))
        try fixture.context.save()

        let candidate = MarinaQueryPlanCandidate(
            source: .deterministic,
            rawPrompt: "How much did I spend on Groceries?",
            operation: .sum,
            measure: .spend,
            entityMentions: [
                MarinaUnresolvedEntityMention(
                    role: .primaryTarget,
                    rawText: "Groceries",
                    typeHint: nil,
                    allowedTypeHints: [.category, .merchant, .expense],
                    confidence: .high
                )
            ],
            confidence: .high
        )

        let resolved = MarinaQueryResolver().resolve(candidate: candidate, provider: fixture.provider)

        #expect(resolved.resolvedTargets.count == 1)
        #expect(resolved.resolvedTargets.first?.entityType == .category)
        #expect(resolved.resolvedTargets.first?.displayName == "Groceries")
        #expect(resolved.ambiguousMentions.isEmpty)
    }

    @Test func resolver_lookupDetailsClarifiesExactCategoryAndExpenseDescriptionCollision() throws {
        let fixture = try makeFixture()
        let groceries = Category(name: "Groceries", hexColor: "#00AA00", workspace: fixture.workspace)
        let card = Card(name: "Apple Card", workspace: fixture.workspace)
        fixture.context.insert(groceries)
        fixture.context.insert(card)
        fixture.context.insert(VariableExpense(
            descriptionText: "Groceries",
            amount: 42,
            transactionDate: date(2026, 5, 12),
            workspace: fixture.workspace,
            card: card,
            category: groceries
        ))
        try fixture.context.save()

        let candidate = MarinaQueryPlanCandidate(
            source: .deterministic,
            rawPrompt: "Show Groceries",
            operation: .lookupDetails,
            measure: .spend,
            entityMentions: [
                MarinaUnresolvedEntityMention(
                    role: .primaryTarget,
                    rawText: "Groceries",
                    typeHint: nil,
                    allowedTypeHints: [.category, .merchant, .expense],
                    confidence: .high
                )
            ],
            confidence: .high
        )

        let resolved = MarinaQueryResolver().resolve(candidate: candidate, provider: fixture.provider)
        let choices = resolved.ambiguousMentions.first?.choices ?? []
        let choiceTypes = choices.compactMap(\.entityTypeHint)

        #expect(resolved.resolvedTargets.isEmpty)
        #expect(resolved.ambiguousMentions.count == 1)
        #expect(choiceTypes.contains(.category))
        #expect(choiceTypes.contains(.expense))
        #expect(choices.first(where: { $0.entityTypeHint == .expense })?.subtitle?.contains("$42.00") == true)
        #expect(choices.first(where: { $0.entityTypeHint == .expense })?.subtitle?.contains("Apple Card") == true)
    }

    @Test func semanticResolver_allowedTypesPreferExactCategoryOverExpensePrefixes() throws {
        let fixture = try makeFixture()
        let cannabis = Category(name: "Cannabis", hexColor: "#225522", workspace: fixture.workspace)
        let card = Card(name: "Apple Card", workspace: fixture.workspace)
        fixture.context.insert(cannabis)
        fixture.context.insert(card)
        fixture.context.insert(VariableExpense(
            descriptionText: "Cannabis Purchase 1",
            amount: 40,
            transactionDate: Date(),
            workspace: fixture.workspace,
            card: card,
            category: cannabis
        ))
        try fixture.context.save()

        let query = MarinaSemanticQuery(
            subject: .variableExpenses,
            operation: .list,
            filters: [
                MarinaFilter(
                    role: .filter,
                    relationship: .unknown,
                    value: "Cannabis",
                    entityTypeHint: nil,
                    allowedEntityTypeHints: [.category, .merchant, .expense]
                )
            ],
            amountField: .budgetImpactAmount,
            grouping: MarinaGrouping(dimension: .transaction, rawText: nil),
            ranking: MarinaRanking(direction: .newest, limit: 5, rawText: nil),
            limit: 5,
            responseShape: .rankedList
        )

        let resolved = MarinaQueryResolver().resolve(query: query, provider: fixture.provider)

        #expect(resolved.resolvedFilters.count == 1)
        #expect(resolved.resolvedFilters.first?.entityType == .category)
        #expect(resolved.resolvedFilters.first?.displayName == "Cannabis")
        #expect(resolved.ambiguousFilters.isEmpty)
    }

    @Test func resolver_allowedTypesStillClarifiesMultipleExactEntityTypes() throws {
        let fixture = try makeFixture()
        fixture.context.insert(Category(name: "Apple", hexColor: "#225522", workspace: fixture.workspace))
        fixture.context.insert(Card(name: "Apple", workspace: fixture.workspace))
        try fixture.context.save()

        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: "spend on Apple",
            operation: .sum,
            measure: .spend,
            entityMentions: [
                MarinaUnresolvedEntityMention(
                    role: .filter,
                    rawText: "Apple",
                    typeHint: nil,
                    allowedTypeHints: [.category, .card, .merchant],
                    confidence: .high
                )
            ],
            confidence: .high
        )

        let resolved = MarinaQueryResolver().resolve(candidate: candidate, provider: fixture.provider)

        #expect(resolved.resolvedTargets.isEmpty)
        #expect(resolved.ambiguousMentions.count == 1)
        let choiceTypes = resolved.ambiguousMentions[0].choices
            .compactMap(\.entityTypeHint?.rawValue)
            .sorted()
        #expect(choiceTypes == ["card", "category"])
    }

    @Test func resolver_noTargetRankingHasNoResolutionProblems() throws {
        let fixture = try makeFixture()
        let candidate = MarinaQueryPlanCandidate(
            source: .deterministic,
            rawPrompt: "where is my money going?",
            operation: .rank,
            measure: .spend,
            grouping: MarinaGroupingCandidate(dimension: .category),
            ranking: MarinaRankingCandidate(direction: .top, limit: 5),
            confidence: .medium
        )

        let resolved = MarinaQueryResolver().resolve(candidate: candidate, provider: fixture.provider)

        #expect(resolved.resolvedTargets.isEmpty)
        #expect(resolved.unresolvedMentions.isEmpty)
        #expect(resolved.ambiguousMentions.isEmpty)
        #expect(resolved.hasResolutionProblems == false)
    }

    @Test func resolver_duplicateEquivalentMerchantMatches_collapseToSingleResolution() throws {
        let fixture = try makeFixture()
        let groceries = Category(name: "Groceries", hexColor: "#00AA00", workspace: fixture.workspace)
        let card = Card(name: "Apple Card", workspace: fixture.workspace)
        fixture.context.insert(groceries)
        fixture.context.insert(card)
        fixture.context.insert(VariableExpense(
            descriptionText: "Starbucks Coffee",
            amount: 9.0,
            transactionDate: Date(),
            workspace: fixture.workspace,
            card: card,
            category: groceries
        ))
        fixture.context.insert(VariableExpense(
            descriptionText: "Starbucks Coffee",
            amount: 12.0,
            transactionDate: Date(),
            workspace: fixture.workspace,
            card: card,
            category: groceries
        ))
        try fixture.context.save()

        let candidate = MarinaQueryPlanCandidate(
            source: .deterministic,
            rawPrompt: "Compare Starbucks in March to February.",
            operation: .compare,
            measure: .spend,
            entityMentions: [
                MarinaUnresolvedEntityMention(role: .primaryTarget, rawText: "Starbucks", typeHint: nil)
            ],
            confidence: .high
        )

        let resolved = MarinaQueryResolver().resolve(candidate: candidate, provider: fixture.provider)

        #expect(resolved.unresolvedMentions.isEmpty)
        #expect(resolved.ambiguousMentions.isEmpty)
        #expect(resolved.resolvedTargets.count == 1)
        #expect(resolved.resolvedTargets.first?.entityType == .merchant)
        #expect(resolved.resolvedTargets.first?.displayName.localizedCaseInsensitiveContains("starbucks") == true)
    }

    @Test func resolver_distinctMerchantCandidatesRemainAmbiguous() throws {
        let fixture = try makeFixture()
        let groceries = Category(name: "Groceries", hexColor: "#00AA00", workspace: fixture.workspace)
        let card = Card(name: "Apple Card", workspace: fixture.workspace)
        fixture.context.insert(groceries)
        fixture.context.insert(card)
        fixture.context.insert(VariableExpense(
            descriptionText: "Target",
            amount: 14.0,
            transactionDate: Date(),
            workspace: fixture.workspace,
            card: card,
            category: groceries
        ))
        fixture.context.insert(VariableExpense(
            descriptionText: "Target Grocery",
            amount: 22.0,
            transactionDate: Date(),
            workspace: fixture.workspace,
            card: card,
            category: groceries
        ))
        try fixture.context.save()

        let candidate = MarinaQueryPlanCandidate(
            source: .deterministic,
            rawPrompt: "Compare Target in March to February.",
            operation: .compare,
            measure: .spend,
            entityMentions: [
                MarinaUnresolvedEntityMention(role: .primaryTarget, rawText: "Target", typeHint: .merchant)
            ],
            confidence: .high
        )

        let resolved = MarinaQueryResolver().resolve(candidate: candidate, provider: fixture.provider)

        #expect(resolved.resolvedTargets.isEmpty)
        #expect(resolved.ambiguousMentions.count == 1)
        let titles = resolved.ambiguousMentions[0].choices.map { $0.title.lowercased() }
        #expect(Set(titles).count == titles.count)
        #expect(titles.contains("target"))
        #expect(titles.contains("target grocery"))
    }

    @Test func resolver_crossFamilySpendTargetKeepsRepresentativeExpenseChoices() throws {
        let fixture = try makeFixture()
        let card = Card(name: "Apple Card", workspace: fixture.workspace)
        fixture.context.insert(card)
        fixture.context.insert(VariableExpense(
            descriptionText: "Apple Watch",
            amount: 25.0,
            transactionDate: Date(),
            workspace: fixture.workspace,
            card: card,
            category: nil
        ))
        try fixture.context.save()

        let candidate = MarinaQueryPlanCandidate(
            source: .deterministic,
            rawPrompt: "What did I spend at Apple?",
            operation: .sum,
            measure: .spend,
            entityMentions: [
                MarinaUnresolvedEntityMention(role: .primaryTarget, rawText: "Apple", typeHint: nil)
            ],
            confidence: .high
        )

        let resolved = MarinaQueryResolver().resolve(candidate: candidate, provider: fixture.provider)
        let choiceTypes = resolved.ambiguousMentions.first?.choices.compactMap(\.entityTypeHint) ?? []

        #expect(choiceTypes.contains(.card))
        #expect(choiceTypes.contains(.expense))
        #expect(choiceTypes.contains(.merchant) == false)
    }

    @Test func resolver_transactionBackedAppleChoicesDistinguishMerchantFromExpense() throws {
        let fixture = try makeFixture()
        let card = Card(name: "Apple Card", workspace: fixture.workspace)
        fixture.context.insert(card)
        fixture.context.insert(VariableExpense(
            descriptionText: "Apple Store",
            amount: 129.0,
            transactionDate: Date(),
            workspace: fixture.workspace,
            card: card,
            category: nil
        ))
        fixture.context.insert(VariableExpense(
            descriptionText: "Apple Watch",
            amount: 35.0,
            transactionDate: Date(),
            workspace: fixture.workspace,
            card: card,
            category: nil
        ))
        try fixture.context.save()

        let candidate = MarinaQueryPlanCandidate(
            source: .deterministic,
            rawPrompt: "What did I spend at Apple?",
            operation: .sum,
            measure: .spend,
            entityMentions: [
                MarinaUnresolvedEntityMention(role: .primaryTarget, rawText: "Apple", typeHint: nil)
            ],
            confidence: .high
        )

        let resolved = MarinaQueryResolver().resolve(candidate: candidate, provider: fixture.provider)
        let choicesByTitle = Dictionary(
            uniqueKeysWithValues: (resolved.ambiguousMentions.first?.choices ?? []).map { ($0.title, $0.entityTypeHint) }
        )

        #expect(choicesByTitle["Apple Store"] == .merchant)
        #expect(choicesByTitle["Apple Watch"] == .expense)
    }

    @Test func resolver_bareTargetWithCategoryMerchantExpenseAndCardClarifies() throws {
        let fixture = try makeFixture()
        fixture.context.insert(Category(name: "Apple", hexColor: "#00AA00", workspace: fixture.workspace))
        let card = Card(name: "Apple Card", workspace: fixture.workspace)
        fixture.context.insert(card)
        fixture.context.insert(VariableExpense(
            descriptionText: "Apple Store",
            amount: 129.0,
            transactionDate: Date(),
            workspace: fixture.workspace,
            card: card,
            category: nil
        ))
        fixture.context.insert(VariableExpense(
            descriptionText: "Apple Watch",
            amount: 35.0,
            transactionDate: Date(),
            workspace: fixture.workspace,
            card: card,
            category: nil
        ))
        try fixture.context.save()

        let candidate = MarinaQueryPlanCandidate(
            source: .deterministic,
            rawPrompt: "What did I spend at Apple?",
            operation: .sum,
            measure: .spend,
            entityMentions: [
                MarinaUnresolvedEntityMention(role: .primaryTarget, rawText: "Apple", typeHint: nil)
            ],
            confidence: .high
        )

        let resolved = MarinaQueryResolver().resolve(candidate: candidate, provider: fixture.provider)
        let choiceTypes = resolved.ambiguousMentions.first?.choices.compactMap(\.entityTypeHint?.rawValue).sorted() ?? []

        #expect(resolved.resolvedTargets.isEmpty)
        #expect(resolved.ambiguousMentions.count == 1)
        #expect(choiceTypes == ["card", "category", "expense", "merchant"])
    }

    @Test func resolver_bareStoredObjectCrossFamilyExactMatchesClarify() throws {
        let fixture = try makeFixture()
        fixture.context.insert(Category(name: "Salary", hexColor: "#00AA00", workspace: fixture.workspace))
        fixture.context.insert(Preset(title: "Salary", plannedAmount: 100, workspace: fixture.workspace))
        fixture.context.insert(Income(source: "Salary", amount: 100, date: Date(), isPlanned: false, workspace: fixture.workspace))
        try fixture.context.save()

        let candidate = MarinaQueryPlanCandidate(
            source: .deterministic,
            rawPrompt: "Show Salary",
            operation: .lookupDetails,
            measure: .spend,
            entityMentions: [
                MarinaUnresolvedEntityMention(role: .primaryTarget, rawText: "Salary", typeHint: nil)
            ],
            confidence: .high
        )

        let resolved = MarinaQueryResolver().resolve(candidate: candidate, provider: fixture.provider)
        let choiceTypes = resolved.ambiguousMentions.first?.choices.compactMap(\.entityTypeHint?.rawValue).sorted() ?? []

        #expect(resolved.resolvedTargets.isEmpty)
        #expect(resolved.ambiguousMentions.count == 1)
        #expect(choiceTypes == ["category", "incomeSource", "preset"])
    }

    @Test func resolver_typeHintMerchantResolvesCrossDomainName() throws {
        let fixture = try makeFixture()
        fixture.context.insert(Category(name: "Starbucks", hexColor: "#22AA44", workspace: fixture.workspace))
        let groceries = Category(name: "Groceries", hexColor: "#00AA00", workspace: fixture.workspace)
        let card = Card(name: "Apple Card", workspace: fixture.workspace)
        fixture.context.insert(groceries)
        fixture.context.insert(card)
        fixture.context.insert(VariableExpense(
            descriptionText: "Starbucks Coffee",
            amount: 8.0,
            transactionDate: Date(),
            workspace: fixture.workspace,
            card: card,
            category: groceries
        ))
        try fixture.context.save()

        let candidate = MarinaQueryPlanCandidate(
            source: .deterministic,
            rawPrompt: "Compare merchant Starbucks in March to February.",
            operation: .compare,
            measure: .spend,
            entityMentions: [
                MarinaUnresolvedEntityMention(role: .primaryTarget, rawText: "Starbucks", typeHint: .merchant)
            ],
            confidence: .high
        )

        let resolved = MarinaQueryResolver().resolve(candidate: candidate, provider: fixture.provider)

        #expect(resolved.ambiguousMentions.isEmpty)
        #expect(resolved.resolvedTargets.count == 1)
        #expect(resolved.resolvedTargets.first?.entityType == .merchant)
    }

    @Test func semanticResolver_uncategorizedMapsToNilCategoryFilter() throws {
        let fixture = try makeFixture()
        let query = MarinaSemanticQuery(
            subject: .variableExpenses,
            operation: .list,
            filters: [
                MarinaFilter(
                    role: .filter,
                    relationship: .uncategorized,
                    value: "uncategorized",
                    entityTypeHint: .category
                )
            ],
            amountField: .budgetImpactAmount
        )

        let resolved = MarinaQueryResolver().resolve(query: query, provider: fixture.provider)

        #expect(resolved.resolvedFilters.count == 1)
        #expect(resolved.resolvedFilters.first?.relationship == .uncategorized)
        #expect(resolved.resolvedFilters.first?.entityType == .category)
        #expect(resolved.resolvedFilters.first?.displayName == "Uncategorized")
        #expect(resolved.resolvedFilters.first?.sourceID == nil)
        #expect(resolved.hasResolutionProblems == false)
    }

    @Test func semanticResolver_categoryStaysWorkspaceScoped() throws {
        let fixture = try makeFixture()
        let groceries = Category(name: "Groceries", hexColor: "#00AA00", workspace: fixture.workspace)
        let otherWorkspace = Workspace(name: "Other", hexColor: "#111111")
        let otherGroceries = Category(name: "Groceries", hexColor: "#FF0000", workspace: otherWorkspace)
        fixture.context.insert(groceries)
        fixture.context.insert(otherWorkspace)
        fixture.context.insert(otherGroceries)
        try fixture.context.save()

        let query = MarinaSemanticQuery(
            subject: .variableExpenses,
            operation: .sum,
            filters: [
                MarinaFilter(
                    role: .primaryTarget,
                    relationship: .category,
                    value: "groceries",
                    entityTypeHint: .category
                )
            ],
            amountField: .budgetImpactAmount
        )

        let resolved = MarinaQueryResolver().resolve(query: query, provider: fixture.provider)

        #expect(resolved.resolvedFilters.count == 1)
        #expect(resolved.resolvedFilters.first?.sourceID == groceries.id)
        #expect(resolved.resolvedFilters.first?.sourceID != otherGroceries.id)
    }

    @Test func semanticResolver_resolvesRawDateTextCentrally() throws {
        let fixture = try makeFixture()
        let query = MarinaSemanticQuery(
            subject: .variableExpenses,
            operation: .compare,
            amountField: .budgetImpactAmount,
            dateRange: MarinaDateRangeRequest(role: .primary, rawText: "May 2026", periodUnit: .month),
            comparisonDateRange: MarinaDateRangeRequest(role: .comparison, rawText: "last month", periodUnit: .month)
        )

        let resolved = MarinaQueryResolver().resolve(
            query: query,
            provider: fixture.provider,
            now: localDate(2026, 5, 15),
            defaultPeriodUnit: .month
        )

        #expect(resolved.primaryDateRange?.startDate == localDate(2026, 5, 1))
        #expect(resolved.primaryDateRange?.endDate == localDate(2026, 5, 31, 23, 59, 59))
        #expect(resolved.comparisonDateRange?.startDate == localDate(2026, 4, 1))
        #expect(resolved.comparisonDateRange?.endDate == localDate(2026, 4, 30, 23, 59, 59))
    }

    private struct Fixture {
        let context: ModelContext
        let workspace: Workspace
        let provider: MarinaDataProvider
    }

    private func makeFixture() throws -> Fixture {
        let context = try makeContext()
        let workspace = Workspace(name: "Resolver Workspace", hexColor: "#3B82F6")
        context.insert(workspace)
        try context.save()
        return Fixture(
            context: context,
            workspace: workspace,
            provider: MarinaDataProvider(modelContext: context, workspaceID: workspace.id)
        )
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Workspace.self,
            Budget.self,
            Card.self,
            BudgetCardLink.self,
            Category.self,
            Preset.self,
            BudgetPresetLink.self,
            BudgetCategoryLimit.self,
            PlannedExpense.self,
            VariableExpense.self,
            AllocationAccount.self,
            ExpenseAllocation.self,
            AllocationSettlement.self,
            SavingsAccount.self,
            SavingsLedgerEntry.self,
            IncomeSeries.self,
            ImportMerchantRule.self,
            AssistantAliasRule.self,
            Income.self
        ])

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        return ModelContext(container)
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0,
        _ second: Int = 0
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.timeZone = calendar.timeZone
        return calendar.date(from: components) ?? .distantPast
    }

    private func localDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0,
        _ second: Int = 0
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.timeZone = calendar.timeZone
        return calendar.date(from: components) ?? .distantPast
    }
}
