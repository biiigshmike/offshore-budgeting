//
//  PreviewSeed.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/20/26.
//

import SwiftUI
import SwiftData

enum PreviewSeed {

    static func makeContainer() -> ModelContainer {
        do {
            let schema = Schema([
                Workspace.self,
                Budget.self,
                BudgetCategoryLimit.self,
                Card.self,
                BudgetCardLink.self,
                BudgetPresetLink.self,
                Category.self,
                Preset.self,
                PlannedExpense.self,
                VariableExpense.self,
                SavingsAccount.self,
                SavingsLedgerEntry.self,
                Income.self
            ])
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to create preview container: \(error)")
        }
    }

    @MainActor
    static func seedBasicData(in context: ModelContext) -> Workspace {
        let ws = Workspace(name: "Personal", hexColor: "#3B82F6")
        context.insert(ws)

        let appleCard = Card(name: "Apple Card", workspace: ws)
        let chase = Card(name: "Chase Freedom", workspace: ws)
        context.insert(appleCard)
        context.insert(chase)

        let rent = Category(name: "Rent", hexColor: "#F97316", workspace: ws)
        let groceries = Category(name: "Groceries", hexColor: "#22C55E", workspace: ws)
        context.insert(rent)
        context.insert(groceries)

        // Example preset template
        let rentPreset = Preset(
            title: "Rent",
            plannedAmount: 1800,
            workspace: ws,
            defaultCard: appleCard,
            defaultCategory: rent
        )
        context.insert(rentPreset)

        let budgetStart = Date()
        let budgetEnd = Calendar.current.date(byAdding: .day, value: 30, to: budgetStart) ?? budgetStart

        let budget = Budget(
            name: "January Budget",
            startDate: budgetStart,
            endDate: budgetEnd,
            workspace: ws
        )
        context.insert(budget)

        // Track a couple cards in the budget
        context.insert(BudgetCardLink(budget: budget, card: appleCard))
        context.insert(BudgetCardLink(budget: budget, card: chase))

        // Remember selected preset (optional, but helpful for budget editing later)
        context.insert(BudgetPresetLink(budget: budget, preset: rentPreset))

        // Seed a budget-scoped spending limit example
        context.insert(BudgetCategoryLimit(minAmount: 0, maxAmount: 1800, budget: budget, category: rent))

        context.insert(Income(source: "Paycheck", amount: 2500, date: .now, isPlanned: true, workspace: ws))
        context.insert(Income(source: "Side Gig", amount: 400, date: .now.addingTimeInterval(-60 * 60 * 24 * 7), isPlanned: false, workspace: ws))

        // MARK: - Seed a few expenses so detail screens can render real data (no "add expense" UI yet)

        // Variable Expenses (transactions)
        let ve1 = VariableExpense(
            descriptionText: "Trader Joe’s",
            amount: 76.42,
            transactionDate: Calendar.current.date(byAdding: .day, value: -2, to: budgetStart) ?? budgetStart,
            workspace: ws,
            card: appleCard,
            category: groceries
        )
        let ve2 = VariableExpense(
            descriptionText: "Target",
            amount: 42.18,
            transactionDate: Calendar.current.date(byAdding: .day, value: 3, to: budgetStart) ?? budgetStart,
            workspace: ws,
            card: chase,
            category: groceries
        )
        let ve3 = VariableExpense(
            descriptionText: "Coffee",
            amount: 5.75,
            transactionDate: Calendar.current.date(byAdding: .day, value: 1, to: budgetStart) ?? budgetStart,
            workspace: ws,
            card: appleCard,
            category: groceries
        )
        context.insert(ve1)
        context.insert(ve2)
        context.insert(ve3)

        // Planned Expenses (instances)
        let pe1 = PlannedExpense(
            title: "Rent",
            plannedAmount: 1800,
            actualAmount: 1800,
            expenseDate: Calendar.current.date(byAdding: .day, value: 1, to: budgetStart) ?? budgetStart,
            workspace: ws,
            card: appleCard,
            category: rent,
            sourcePresetID: rentPreset.id
        )
        let pe2 = PlannedExpense(
            title: "Groceries (Planned)",
            plannedAmount: 300,
            actualAmount: 0,
            expenseDate: Calendar.current.date(byAdding: .day, value: 10, to: budgetStart) ?? budgetStart,
            workspace: ws,
            card: chase,
            category: groceries,
            sourcePresetID: nil
        )
        context.insert(pe1)
        context.insert(pe2)

        return ws
    }
}

@MainActor
struct PreviewHost<Content: View>: View {

    private let container: ModelContainer
    private let content: (Workspace) -> Content

    init(container: ModelContainer, content: @escaping (Workspace) -> Content) {
        self.container = container
        self.content = content
    }

    var body: some View {
        let context = container.mainContext
        let ws = PreviewSeed.seedBasicData(in: context)

        return content(ws)
            .modelContainer(container)
    }
}
