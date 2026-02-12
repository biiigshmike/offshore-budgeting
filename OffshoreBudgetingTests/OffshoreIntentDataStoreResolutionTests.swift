import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct OffshoreIntentDataStoreResolutionTests {

    // MARK: - Test Store

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
            IncomeSeries.self,
            ImportMerchantRule.self,
            Income.self
        ])

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        return ModelContext(container)
    }

    // MARK: - Card Resolution

    @Test func resolveCard_ByName_CaseInsensitiveAndTrimmedMatch() throws {
        let context = try makeContext()
        let dataStore = OffshoreIntentDataStore.shared

        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let card = Card(name: "Apple Card", workspace: workspace)

        context.insert(workspace)
        context.insert(card)
        try context.save()

        let resolved = try dataStore.resolveCard(
            id: nil,
            name: "  apple card  ",
            in: workspace,
            modelContext: context
        )

        #expect(resolved.id == card.id)
    }

    @Test func resolveCard_ByName_AmbiguousThrows() throws {
        let context = try makeContext()
        let dataStore = OffshoreIntentDataStore.shared

        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let cardA = Card(name: "Apple Card", workspace: workspace)
        let cardB = Card(name: "APPLE   CARD", workspace: workspace)

        context.insert(workspace)
        context.insert(cardA)
        context.insert(cardB)
        try context.save()

        do {
            _ = try dataStore.resolveCard(
                id: nil,
                name: "apple card",
                in: workspace,
                modelContext: context
            )
            Issue.record("Expected ambiguous card name error.")
        } catch let error as OffshoreIntentDataStore.IntentDataError {
            #expect(error == .ambiguousCardName)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - Category Resolution

    @Test func resolveCategory_MerchantRuleMatchBeatsFallback() throws {
        let context = try makeContext()
        let dataStore = OffshoreIntentDataStore.shared

        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let groceries = Category(name: "Groceries", hexColor: "#00AA00", workspace: workspace)
        let uncategorized = Category(name: "Uncategorized", hexColor: "#999999", workspace: workspace)
        let merchantRule = ImportMerchantRule(
            merchantKey: MerchantNormalizer.normalizeKey("Whole Foods"),
            preferredName: "Whole Foods",
            preferredCategory: groceries,
            workspace: workspace
        )

        context.insert(workspace)
        context.insert(groceries)
        context.insert(uncategorized)
        context.insert(merchantRule)
        try context.save()

        let resolved = try dataStore.resolveCategory(
            id: nil,
            merchant: "WHOLE FOODS #4287",
            in: workspace,
            modelContext: context
        )

        #expect(resolved?.id == groceries.id)
    }

    @Test func resolveCategory_NoRuleFallsBackToUncategorized() throws {
        let context = try makeContext()
        let dataStore = OffshoreIntentDataStore.shared

        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")

        context.insert(workspace)
        try context.save()

        let resolved = try dataStore.resolveCategory(
            id: nil,
            merchant: "Unknown Merchant",
            in: workspace,
            modelContext: context
        )

        #expect(resolved == nil)
    }

    @Test func resolveCategory_ExplicitIDStillResolves() throws {
        let context = try makeContext()
        let dataStore = OffshoreIntentDataStore.shared

        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let groceries = Category(name: "Groceries", hexColor: "#00AA00", workspace: workspace)

        context.insert(workspace)
        context.insert(groceries)
        try context.save()

        let resolved = try dataStore.resolveCategory(
            id: groceries.id.uuidString,
            merchant: "Unknown Merchant",
            in: workspace,
            modelContext: context
        )

        #expect(resolved?.id == groceries.id)
    }
}
