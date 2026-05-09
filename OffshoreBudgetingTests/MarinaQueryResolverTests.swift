import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
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
            source: .heuristic,
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

    @Test func resolver_preservesUnresolvedMentionWhenNoWorkspaceMatchExists() throws {
        let fixture = try makeFixture()
        let candidate = MarinaQueryPlanCandidate(
            source: .heuristic,
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

    @Test func resolver_noTargetRankingHasNoResolutionProblems() throws {
        let fixture = try makeFixture()
        let candidate = MarinaQueryPlanCandidate(
            source: .heuristic,
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
            source: .heuristic,
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
            source: .heuristic,
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
            source: .heuristic,
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
            IncomeSeries.self,
            ImportMerchantRule.self,
            Income.self
        ])

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        return ModelContext(container)
    }
}
