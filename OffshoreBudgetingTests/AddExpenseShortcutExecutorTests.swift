import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct AddExpenseShortcutExecutorTests {

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

    @Test func execute_walletCardPath_createsExpense() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let card = Card(name: "Apple Card", workspace: workspace)

        context.insert(workspace)
        context.insert(card)
        try context.save()

        let summary = try AddExpenseShortcutExecutor.execute(
            request: .init(
                amountText: "45.44",
                offshoreCardID: nil,
                walletCardName: "Apple Card",
                categoryID: nil,
                merchant: "Whole Foods",
                date: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            in: workspace,
            modelContext: context
        )

        let expense = try #require(try context.fetch(FetchDescriptor<VariableExpense>()).first)
        #expect(expense.card?.id == card.id)
        #expect(expense.descriptionText == "Whole Foods")
        #expect(summary.contains("Apple Card"))
    }

    @Test func execute_offshoreCardID_winsOverWalletCardFallback() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let primary = Card(name: "Apple Card", workspace: workspace)
        let fallback = Card(name: "Backup Card", workspace: workspace)

        context.insert(workspace)
        context.insert(primary)
        context.insert(fallback)
        try context.save()

        _ = try AddExpenseShortcutExecutor.execute(
            request: .init(
                amountText: "12.50",
                offshoreCardID: primary.id.uuidString,
                walletCardName: "Backup Card",
                categoryID: nil,
                merchant: "Coffee Shop",
                date: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            in: workspace,
            modelContext: context
        )

        let expense = try #require(try context.fetch(FetchDescriptor<VariableExpense>()).first)
        #expect(expense.card?.id == primary.id)
    }

    @Test func execute_explicitCategoryID_winsAndMerchantRuleFallbackStillWorks() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let card = Card(name: "Apple Card", workspace: workspace)
        let groceries = Category(name: "Groceries", hexColor: "#00AA00", workspace: workspace)
        let entertainment = Category(name: "Entertainment", hexColor: "#AA00AA", workspace: workspace)
        let merchantRule = ImportMerchantRule(
            merchantKey: MerchantNormalizer.normalizeKey("Whole Foods"),
            preferredName: "Whole Foods",
            preferredCategory: groceries,
            workspace: workspace
        )

        context.insert(workspace)
        context.insert(card)
        context.insert(groceries)
        context.insert(entertainment)
        context.insert(merchantRule)
        try context.save()

        _ = try AddExpenseShortcutExecutor.execute(
            request: .init(
                amountText: "18.99",
                offshoreCardID: nil,
                walletCardName: "Apple Card",
                categoryID: entertainment.id.uuidString,
                merchant: "Whole Foods",
                date: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            in: workspace,
            modelContext: context
        )

        let expense = try #require(try context.fetch(FetchDescriptor<VariableExpense>()).first)
        #expect(expense.category?.id == entertainment.id)
    }

    @Test func execute_merchantRule_appliesWhenCategoryMissing() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let card = Card(name: "Apple Card", workspace: workspace)
        let groceries = Category(name: "Groceries", hexColor: "#00AA00", workspace: workspace)
        let merchantRule = ImportMerchantRule(
            merchantKey: MerchantNormalizer.normalizeKey("Whole Foods"),
            preferredName: "Whole Foods",
            preferredCategory: groceries,
            workspace: workspace
        )

        context.insert(workspace)
        context.insert(card)
        context.insert(groceries)
        context.insert(merchantRule)
        try context.save()

        _ = try AddExpenseShortcutExecutor.execute(
            request: .init(
                amountText: "18.99",
                offshoreCardID: nil,
                walletCardName: "Apple Card",
                categoryID: nil,
                merchant: "Whole Foods #1234",
                date: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            in: workspace,
            modelContext: context
        )

        let expense = try #require(try context.fetch(FetchDescriptor<VariableExpense>()).first)
        #expect(expense.category?.id == groceries.id)
    }

    @Test func execute_invalidAmount_throwsValidationError() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")

        context.insert(workspace)
        try context.save()

        do {
            _ = try AddExpenseShortcutExecutor.execute(
                request: .init(
                    amountText: "abc",
                    offshoreCardID: nil,
                    walletCardName: "Apple Card",
                    categoryID: nil,
                    merchant: "Store",
                    date: Date(timeIntervalSince1970: 1_700_000_000)
                ),
                in: workspace,
                modelContext: context
            )
            Issue.record("Expected invalid amount validation error.")
        } catch let error as AddExpenseShortcutExecutor.RequestValidationError {
            #expect(error == .invalidAmount)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func execute_missingMerchant_throwsValidationError() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")

        context.insert(workspace)
        try context.save()

        do {
            _ = try AddExpenseShortcutExecutor.execute(
                request: .init(
                    amountText: "12.00",
                    offshoreCardID: nil,
                    walletCardName: "Apple Card",
                    categoryID: nil,
                    merchant: "   ",
                    date: Date(timeIntervalSince1970: 1_700_000_000)
                ),
                in: workspace,
                modelContext: context
            )
            Issue.record("Expected missing merchant validation error.")
        } catch let error as AddExpenseShortcutExecutor.RequestValidationError {
            #expect(error == .missingMerchant)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func execute_missingDate_throwsValidationError() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")

        context.insert(workspace)
        try context.save()

        do {
            _ = try AddExpenseShortcutExecutor.execute(
                request: .init(
                    amountText: "12.00",
                    offshoreCardID: nil,
                    walletCardName: "Apple Card",
                    categoryID: nil,
                    merchant: "Store",
                    date: nil
                ),
                in: workspace,
                modelContext: context
            )
            Issue.record("Expected missing date validation error.")
        } catch let error as AddExpenseShortcutExecutor.RequestValidationError {
            #expect(error == .missingDate)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func execute_ambiguousWalletCard_throwsIntentDataError() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let first = Card(name: "Apple Card", workspace: workspace)
        let second = Card(name: "APPLE   CARD", workspace: workspace)

        context.insert(workspace)
        context.insert(first)
        context.insert(second)
        try context.save()

        do {
            _ = try AddExpenseShortcutExecutor.execute(
                request: .init(
                    amountText: "12.00",
                    offshoreCardID: nil,
                    walletCardName: "apple card",
                    categoryID: nil,
                    merchant: "Store",
                    date: Date(timeIntervalSince1970: 1_700_000_000)
                ),
                in: workspace,
                modelContext: context
            )
            Issue.record("Expected ambiguous Wallet card error.")
        } catch let error as OffshoreIntentDataStore.IntentDataError {
            #expect(error == .ambiguousCardName)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}
