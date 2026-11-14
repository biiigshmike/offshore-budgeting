//
//  SwiftDataCRUDTests.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/29/26.
//


import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct SwiftDataCRUDTests {

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
            AllocationAccount.self,
            ExpenseAllocation.self,
            AllocationSettlement.self,
            IncomeSeries.self,
            ImportMerchantRule.self,
            MarinaChatSession.self,
            Income.self
        ])

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        return ModelContext(container)
    }

    private func fetchAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }

    // MARK: - Workspace

    @Test func workspace_CRUD() throws {
        let context = try makeContext()

        let ws = Workspace(name: "Personal", hexColor: "#3B82F6")
        context.insert(ws)
        try context.save()

        let fetched1 = try fetchAll(Workspace.self, in: context)
        #expect(fetched1.count == 1)
        #expect(fetched1.first?.name == "Personal")

        ws.name = "Personal Updated"
        try context.save()

        let fetched2 = try fetchAll(Workspace.self, in: context)
        #expect(fetched2.first?.name == "Personal Updated")

        context.delete(ws)
        try context.save()

        let fetched3 = try fetchAll(Workspace.self, in: context)
        #expect(fetched3.isEmpty)
    }

    // MARK: - Card

    @Test func card_CRUD() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Visa", theme: "default", effect: "none", workspace: ws)

        context.insert(ws)
        context.insert(card)
        try context.save()

        let cards = try fetchAll(Card.self, in: context)
        #expect(cards.count == 1)
        #expect(cards.first?.name == "Visa")

        card.name = "Visa Updated"
        try context.save()

        let cards2 = try fetchAll(Card.self, in: context)
        #expect(cards2.first?.name == "Visa Updated")

        context.delete(card)
        try context.save()

        let cards3 = try fetchAll(Card.self, in: context)
        #expect(cards3.isEmpty)
    }

    // MARK: - Category

    @Test func category_CRUD() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let cat = Category(name: "Groceries", hexColor: "#00FF00", workspace: ws)

        context.insert(ws)
        context.insert(cat)
        try context.save()

        let cats = try fetchAll(Category.self, in: context)
        #expect(cats.count == 1)
        #expect(cats.first?.name == "Groceries")
        #expect(cats.first?.isArchived == false)
        #expect(cats.first?.archivedAt == nil)

        cat.name = "Groceries Updated"
        let archivedAt = Date()
        cat.isArchived = true
        cat.archivedAt = archivedAt
        try context.save()

        let cats2 = try fetchAll(Category.self, in: context)
        #expect(cats2.first?.name == "Groceries Updated")
        #expect(cats2.first?.isArchived == true)
        #expect(cats2.first?.archivedAt == archivedAt)

        cat.isArchived = false
        cat.archivedAt = nil
        try context.save()

        let cats3 = try fetchAll(Category.self, in: context)
        #expect(cats3.first?.isArchived == false)
        #expect(cats3.first?.archivedAt == nil)

        context.delete(cat)
        try context.save()

        let cats4 = try fetchAll(Category.self, in: context)
        #expect(cats4.isEmpty)
    }

    // MARK: - Preset

    @Test func preset_CRUD() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let cat = Category(name: "Rent", hexColor: "#111111", workspace: ws)
        let preset = Preset(title: "Rent", plannedAmount: 1200, workspace: ws, defaultCategory: cat)

        context.insert(ws)
        context.insert(cat)
        context.insert(preset)
        try context.save()

        let presets = try fetchAll(Preset.self, in: context)
        #expect(presets.count == 1)
        #expect(presets.first?.title == "Rent")
        #expect(presets.first?.plannedAmount == 1200)

        preset.plannedAmount = 1250
        try context.save()

        let presets2 = try fetchAll(Preset.self, in: context)
        #expect(presets2.first?.plannedAmount == 1250)

        context.delete(preset)
        try context.save()

        let presets3 = try fetchAll(Preset.self, in: context)
        #expect(presets3.isEmpty)
    }

    @Test(arguments: [0.0, 1250.0])
    func deletingPreset_preservesGeneratedPlannedExpense(actualAmount: Double) throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let card = Card(name: "Visa", theme: "default", effect: "none", workspace: workspace)
        let category = Category(name: "Housing", hexColor: "#111111", workspace: workspace)
        let date = Calendar.current.startOfDay(for: Date())
        let budget = Budget(name: "Rent budget", startDate: date, endDate: date, workspace: workspace)
        let preset = Preset(title: "Rent", plannedAmount: 1200, workspace: workspace,
                            defaultCard: card, defaultCategory: category)
        let expense = PlannedExpense(
            title: preset.title, plannedAmount: preset.plannedAmount, actualAmount: actualAmount,
            expenseDate: date, workspace: workspace, card: card, category: category,
            sourcePresetID: preset.id, sourceBudgetID: budget.id
        )
        let expenseID = expense.id
        let presetID = preset.id
        let budgetID = budget.id
        let workspaceID = workspace.id
        let cardID = card.id
        let categoryID = category.id

        context.insert(workspace)
        context.insert(card)
        context.insert(category)
        context.insert(budget)
        context.insert(preset)
        context.insert(BudgetCardLink(budget: budget, card: card))
        context.insert(BudgetPresetLink(budget: budget, preset: preset))
        context.insert(expense)
        try context.save()
        #expect(try fetchAll(PlannedExpense.self, in: context).count == 1)

        // Match the direct deletion used by Settings and onboarding.
        context.delete(preset)
        try context.save()

        // Fetch through a fresh context so assertions check saved data.
        let verificationContext = ModelContext(context.container)
        #expect(try fetchAll(Preset.self, in: verificationContext).isEmpty)
        let remaining = try fetchAll(PlannedExpense.self, in: verificationContext)
        #expect(remaining.count == 1)
        let savedExpense = try #require(remaining.first)
        #expect(savedExpense.id == expenseID)
        #expect(savedExpense.title == "Rent")
        #expect(savedExpense.plannedAmount == 1200)
        #expect(savedExpense.actualAmount == actualAmount)
        #expect(savedExpense.expenseDate == date)
        #expect(savedExpense.sourcePresetID == presetID)
        #expect(savedExpense.sourceBudgetID == budgetID)
        #expect(savedExpense.workspace?.id == workspaceID)
        #expect(savedExpense.card?.id == cardID)
        #expect(savedExpense.category?.id == categoryID)
    }

    @Test(arguments: [0.0, 1250.0])
    func budgetEditCleanup_preservesExpensesFromDeletedPreset(actualAmount: Double) throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let card = Card(name: "Visa", workspace: workspace)
        let date = Calendar.current.startOfDay(for: Date())
        let budget = Budget(name: "Original", startDate: date, endDate: date, workspace: workspace)
        let preset = Preset(title: "Rent", plannedAmount: 1200, workspace: workspace, defaultCard: card)
        let expense = PlannedExpense(
            title: "Rent", plannedAmount: 1200, actualAmount: actualAmount,
            expenseDate: date, workspace: workspace, card: card,
            sourcePresetID: preset.id, sourceBudgetID: budget.id
        )
        let expenseID = expense.id
        let presetID = preset.id
        context.insert(workspace)
        context.insert(card)
        context.insert(budget)
        context.insert(preset)
        context.insert(BudgetCardLink(budget: budget, card: card))
        context.insert(BudgetPresetLink(budget: budget, preset: preset))
        context.insert(expense)
        try context.save()
        context.delete(preset)
        try context.save()

        // Exercise the cleanup used by EditBudgetView when saving a name-only edit.
        budget.name = "Renamed"
        try BudgetPlannedExpenseCleanupService.cleanup(
            budget: budget, workspaceID: workspace.id, selectedPresetIDs: [],
            selectedCardIDs: [card.id], modelContext: context
        )
        try context.save()

        let verificationContext = ModelContext(context.container)
        #expect(try fetchAll(Preset.self, in: verificationContext).isEmpty)
        let remaining = try fetchAll(PlannedExpense.self, in: verificationContext)
        #expect(remaining.count == 1)
        let saved = try #require(remaining.first)
        #expect(saved.id == expenseID)
        #expect(saved.sourcePresetID == presetID)
        #expect(saved.sourceBudgetID == budget.id)
        #expect(saved.workspace?.id == workspace.id)
        #expect(saved.card?.id == card.id)
        #expect(saved.title == "Rent")
        #expect(saved.plannedAmount == 1200)
        #expect(saved.actualAmount == actualAmount)
        #expect(saved.expenseDate == date)
        let savedBudget = try #require(fetchAll(Budget.self, in: verificationContext).first)
        #expect(savedBudget.name == "Renamed")
        #expect(BudgetPlannedExpenseStore.plannedExpenses(in: workspace, for: budget).map(\.id) == [expenseID])
    }

    @Test(arguments: [0.0, 1250.0])
    func budgetEditCleanup_preservesSelectionRulesAndScope(actualAmount: Double) throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let otherWorkspace = Workspace(name: "Work", hexColor: "#111111")
        let card = Card(name: "Visa", workspace: workspace)
        let removedCard = Card(name: "Removed", workspace: workspace)
        let date = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: date)!
        let budget = Budget(name: "Today", startDate: date, endDate: date, workspace: workspace)
        let otherBudget = Budget(name: "Other", startDate: date, endDate: date, workspace: workspace)
        let selected = Preset(title: "Selected", plannedAmount: 100, workspace: workspace)
        let deselected = Preset(title: "Deselected", plannedAmount: 100, workspace: workspace)
        let archived = Preset(title: "Archived", plannedAmount: 100, workspace: workspace, isArchived: true)
        context.insert(workspace)
        context.insert(otherWorkspace)
        context.insert(card)
        context.insert(removedCard)
        context.insert(budget)
        context.insert(otherBudget)
        context.insert(selected)
        context.insert(deselected)
        context.insert(archived)
        let missingPresetID = UUID()
        func insert(_ title: String, presetID: UUID?, date expenseDate: Date,
                    card expenseCard: Card, budgetID: UUID, owner: Workspace) -> UUID {
            let expense = PlannedExpense(
                title: title, plannedAmount: 100, actualAmount: actualAmount,
                expenseDate: expenseDate, workspace: owner, card: expenseCard,
                sourcePresetID: presetID, sourceBudgetID: budgetID
            )
            context.insert(expense)
            return expense.id
        }
        let selectedID = insert("Selected", presetID: selected.id, date: date, card: card, budgetID: budget.id, owner: workspace)
        let archivedID = insert("Archived selected", presetID: archived.id, date: date, card: card, budgetID: budget.id, owner: workspace)
        _ = insert("Deselected", presetID: deselected.id, date: date, card: card, budgetID: budget.id, owner: workspace)
        _ = insert("Outside dates", presetID: missingPresetID, date: tomorrow, card: card, budgetID: budget.id, owner: workspace)
        _ = insert("Removed card", presetID: missingPresetID, date: date, card: removedCard, budgetID: budget.id, owner: workspace)
        _ = insert("No source preset", presetID: nil, date: date, card: card, budgetID: budget.id, owner: workspace)
        let otherBudgetID = insert("Other budget", presetID: deselected.id, date: date, card: card, budgetID: otherBudget.id, owner: workspace)
        // Even a matching sourceBudgetID cannot cross the workspace boundary.
        let otherWorkspaceID = insert("Other workspace", presetID: deselected.id, date: date, card: card, budgetID: budget.id, owner: otherWorkspace)
        try context.save()
        try BudgetPlannedExpenseCleanupService.cleanup(
            budget: budget, workspaceID: workspace.id, selectedPresetIDs: [selected.id, archived.id],
            selectedCardIDs: [card.id], modelContext: context
        )
        try context.save()
        let verificationContext = ModelContext(context.container)
        let remaining = try fetchAll(PlannedExpense.self, in: verificationContext)
        #expect(Set(remaining.map(\.id)) == [selectedID, archivedID, otherBudgetID, otherWorkspaceID])
    }

    // MARK: - Budget + join links

    @Test func budget_withLinks_CRUD() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Amex", workspace: ws)
        let preset = Preset(title: "Netflix", plannedAmount: 19.99, workspace: ws)

        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let end = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        let budget = Budget(name: "January", startDate: start, endDate: end, workspace: ws)

        context.insert(ws)
        context.insert(card)
        context.insert(preset)
        context.insert(budget)

        let link1 = BudgetCardLink(budget: budget, card: card)
        let link2 = BudgetPresetLink(budget: budget, preset: preset)
        context.insert(link1)
        context.insert(link2)

        try context.save()

        let budgets = try fetchAll(Budget.self, in: context)
        #expect(budgets.count == 1)
        #expect(budgets.first?.name == "January")

        let cardLinks = try fetchAll(BudgetCardLink.self, in: context)
        let presetLinks = try fetchAll(BudgetPresetLink.self, in: context)
        #expect(cardLinks.count == 1)
        #expect(presetLinks.count == 1)

        budget.name = "January Updated"
        try context.save()

        let budgets2 = try fetchAll(Budget.self, in: context)
        #expect(budgets2.first?.name == "January Updated")

        context.delete(budget)
        try context.save()

        let budgets3 = try fetchAll(Budget.self, in: context)
        #expect(budgets3.isEmpty)
    }

    // MARK: - Income, PlannedExpense, VariableExpense

    @Test func transactions_CRUD() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Visa", workspace: ws)
        let cat = Category(name: "Food", hexColor: "#FF0000", workspace: ws)

        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 10))!

        let income = Income(source: "Paycheck", amount: 2000, date: date, isPlanned: true, workspace: ws, card: card)
        let planned = PlannedExpense(title: "Dinner", plannedAmount: 50, actualAmount: 40, expenseDate: date, workspace: ws, card: card, category: cat)
        let variable = VariableExpense(descriptionText: "Coffee", amount: 6.50, transactionDate: date, workspace: ws, card: card, category: cat)

        context.insert(ws)
        context.insert(card)
        context.insert(cat)
        context.insert(income)
        context.insert(planned)
        context.insert(variable)
        try context.save()

        #expect(try fetchAll(Income.self, in: context).count == 1)
        #expect(try fetchAll(PlannedExpense.self, in: context).count == 1)
        #expect(try fetchAll(VariableExpense.self, in: context).count == 1)

        income.amount = 2100
        planned.actualAmount = 45
        variable.amount = 7.25
        try context.save()

        let income2 = try fetchAll(Income.self, in: context).first
        let planned2 = try fetchAll(PlannedExpense.self, in: context).first
        let variable2 = try fetchAll(VariableExpense.self, in: context).first

        #expect(income2?.amount == 2100)
        #expect(planned2?.actualAmount == 45)
        #expect(variable2?.amount == 7.25)

        context.delete(income)
        context.delete(planned)
        context.delete(variable)
        try context.save()

        #expect(try fetchAll(Income.self, in: context).isEmpty)
        #expect(try fetchAll(PlannedExpense.self, in: context).isEmpty)
        #expect(try fetchAll(VariableExpense.self, in: context).isEmpty)
    }

    // MARK: - Linked settlement integrity

    @Test func deletingLinkedSettlement_keepsGrossExpenseAmountAndUnlinks() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Visa", workspace: ws)
        let cat = Category(name: "Food", hexColor: "#FF0000", workspace: ws)
        let account = AllocationAccount(name: "Partner", workspace: ws)
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 10))!

        let expense = VariableExpense(
            descriptionText: "Groceries",
            amount: 60,
            transactionDate: date,
            workspace: ws,
            card: card,
            category: cat
        )

        let settlement = AllocationSettlement(
            date: date,
            note: "Offset applied",
            amount: -20,
            workspace: ws,
            account: account,
            expense: expense
        )
        expense.offsetSettlement = settlement

        context.insert(ws)
        context.insert(card)
        context.insert(cat)
        context.insert(account)
        context.insert(expense)
        context.insert(settlement)
        try context.save()

        expense.offsetSettlement = nil
        context.delete(settlement)
        try context.save()

        let fetchedExpense = try fetchAll(VariableExpense.self, in: context).first
        let settlements = try fetchAll(AllocationSettlement.self, in: context)

        #expect(settlements.isEmpty)
        #expect(fetchedExpense?.amount == 60)
        #expect(fetchedExpense?.offsetSettlement == nil)
    }

    @Test func editingLinkedSettlement_keepsGrossExpenseAmountAndUpdatesDate() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Visa", workspace: ws)
        let cat = Category(name: "Food", hexColor: "#FF0000", workspace: ws)
        let account = AllocationAccount(name: "Partner", workspace: ws)

        let originalDate = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 10))!
        let updatedDate = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 12))!

        let expense = VariableExpense(
            descriptionText: "Groceries",
            amount: 60,
            transactionDate: originalDate,
            workspace: ws,
            card: card,
            category: cat
        )

        let settlement = AllocationSettlement(
            date: originalDate,
            note: "Offset applied",
            amount: -20,
            workspace: ws,
            account: account,
            expense: expense
        )
        expense.offsetSettlement = settlement

        context.insert(ws)
        context.insert(card)
        context.insert(cat)
        context.insert(account)
        context.insert(expense)
        context.insert(settlement)
        try context.save()

        let newOffset = 10.0

        settlement.amount = -newOffset
        settlement.date = updatedDate
        settlement.note = "Updated offset"

        expense.transactionDate = updatedDate

        try context.save()

        let fetchedExpense = try fetchAll(VariableExpense.self, in: context).first
        let fetchedSettlement = try fetchAll(AllocationSettlement.self, in: context).first

        #expect(fetchedExpense?.amount == 60)
        #expect(fetchedExpense?.transactionDate == updatedDate)
        #expect(fetchedSettlement?.amount == -10)
        #expect(fetchedSettlement?.date == updatedDate)
    }

    // MARK: - Linked split charge integrity

    @Test func deletingLinkedSplitCharge_restoresVariableGrossAndUnlinks() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Visa", workspace: ws)
        let cat = Category(name: "Food", hexColor: "#FF0000", workspace: ws)
        let account = AllocationAccount(name: "Partner", workspace: ws)
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 10))!

        let expense = VariableExpense(
            descriptionText: "Groceries",
            amount: 100,
            transactionDate: date,
            workspace: ws,
            card: card,
            category: cat
        )

        let allocation = ExpenseAllocation(
            allocatedAmount: 20,
            preservesGrossAmount: true,
            createdAt: .now,
            updatedAt: .now,
            workspace: ws,
            account: account,
            expense: expense
        )
        expense.allocation = allocation

        context.insert(ws)
        context.insert(card)
        context.insert(cat)
        context.insert(account)
        context.insert(expense)
        context.insert(allocation)
        try context.save()

        expense.allocation = nil
        context.delete(allocation)
        try context.save()

        let fetchedExpense = try fetchAll(VariableExpense.self, in: context).first
        let allocations = try fetchAll(ExpenseAllocation.self, in: context)

        #expect(allocations.isEmpty)
        #expect(fetchedExpense?.amount == 100)
        #expect(fetchedExpense?.allocation == nil)
    }

    @Test func editingLinkedSplitCharge_updatesPlannedActualAndAllocationAmount() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Visa", workspace: ws)
        let cat = Category(name: "Housing", hexColor: "#FF0000", workspace: ws)
        let account = AllocationAccount(name: "Partner", workspace: ws)
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1))!

        let plannedExpense = PlannedExpense(
            title: "Rent",
            plannedAmount: 1200,
            actualAmount: 900,
            expenseDate: date,
            workspace: ws,
            card: card,
            category: cat
        )

        let allocation = ExpenseAllocation(
            allocatedAmount: 300,
            preservesGrossAmount: true,
            createdAt: .now,
            updatedAt: .now,
            workspace: ws,
            account: account,
            expense: nil,
            plannedExpense: plannedExpense
        )
        plannedExpense.allocation = allocation

        context.insert(ws)
        context.insert(card)
        context.insert(cat)
        context.insert(account)
        context.insert(plannedExpense)
        context.insert(allocation)
        try context.save()

        let newSplit = AllocationLedgerService.cappedAllocationAmount(450, expenseAmount: plannedExpense.plannedAmount)
        allocation.allocatedAmount = newSplit
        plannedExpense.actualAmount = 900
        try context.save()

        let fetchedPlanned = try fetchAll(PlannedExpense.self, in: context).first
        let fetchedAllocation = try fetchAll(ExpenseAllocation.self, in: context).first

        #expect(fetchedAllocation?.allocatedAmount == 450)
        #expect(fetchedPlanned?.actualAmount == 900)
        #expect(fetchedPlanned?.allocation?.id == fetchedAllocation?.id)
    }

    @Test func deletingLinkedPlannedSplitCharge_resetsActualAndUnlinks() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Visa", workspace: ws)
        let cat = Category(name: "Housing", hexColor: "#FF0000", workspace: ws)
        let account = AllocationAccount(name: "Partner", workspace: ws)
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1))!

        let plannedExpense = PlannedExpense(
            title: "Rent",
            plannedAmount: 1200,
            actualAmount: 900,
            expenseDate: date,
            workspace: ws,
            card: card,
            category: cat
        )

        let allocation = ExpenseAllocation(
            allocatedAmount: 300,
            preservesGrossAmount: true,
            createdAt: .now,
            updatedAt: .now,
            workspace: ws,
            account: account,
            expense: nil,
            plannedExpense: plannedExpense
        )
        plannedExpense.allocation = allocation

        context.insert(ws)
        context.insert(card)
        context.insert(cat)
        context.insert(account)
        context.insert(plannedExpense)
        context.insert(allocation)
        try context.save()

        plannedExpense.allocation = nil
        context.delete(allocation)
        try context.save()

        let fetchedPlanned = try fetchAll(PlannedExpense.self, in: context).first
        let allocations = try fetchAll(ExpenseAllocation.self, in: context)

        #expect(allocations.isEmpty)
        #expect(fetchedPlanned?.actualAmount == 900)
        #expect(fetchedPlanned?.allocation == nil)
    }
}
