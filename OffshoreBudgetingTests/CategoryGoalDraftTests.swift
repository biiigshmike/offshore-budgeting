import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct CategoryGoalDraftTests {
    @Test func emptyAndOneSidedGoalsAreOptional() {
        #expect(CategoryGoalDraft().isValid)
        #expect(!CategoryGoalDraft().hasValues)
        #expect(CategoryGoalDraft(minimum: 25, maximum: nil).isValid)
        #expect(CategoryGoalDraft(minimum: nil, maximum: 100).isValid)
        #expect(CategoryGoalDraft(minimum: 0, maximum: 0).isValid)
    }

    @Test func malformedNegativeAndReversedGoalsCannotBeSaved() {
        #expect(!CategoryGoalDraft(minimumText: "not a number").isValid)
        #expect(!CategoryGoalDraft(minimum: -1, maximum: nil).isValid)
        #expect(!CategoryGoalDraft(minimum: nil, maximum: -1).isValid)
        #expect(!CategoryGoalDraft(minimum: 101, maximum: 100).isValid)
        #expect(CategoryGoalDraft(minimum: 100, maximum: 100).isValid)
    }

    @Test func editingAndDiscardingADraftDoesNotChangeStoredGoals() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#000000")
        let category = Category(name: "Groceries", hexColor: "#000000", workspace: workspace)
        let budget = Budget(name: "Budget", startDate: .now, endDate: .now, workspace: workspace)
        let goal = BudgetCategoryLimit(minAmount: 20, maxAmount: 100, budget: budget, category: category)
        context.insert(workspace)
        context.insert(budget)
        context.insert(category)
        context.insert(goal)
        try context.save()

        var drafts = BudgetCategoryGoalStore.drafts(for: budget)
        drafts[category.id] = CategoryGoalDraft(minimum: 40, maximum: 200)
        #expect(goal.minAmount == 20)
        #expect(goal.maxAmount == 100)
        #expect(try context.fetchCount(FetchDescriptor<BudgetCategoryLimit>()) == 1)

        drafts.removeAll()
        #expect(goal.minAmount == 20)
        #expect(goal.maxAmount == 100)
    }

    @Test func creationDraftsArePersistedOnlyWhenExplicitlyApplied() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#000000")
        let category = Category(name: "Groceries", hexColor: "#000000", workspace: workspace)
        let budget = Budget(name: "Budget", startDate: .now, endDate: .now, workspace: workspace)
        context.insert(workspace)
        context.insert(category)
        context.insert(budget)
        let drafts = [category.id: CategoryGoalDraft(minimum: 25, maximum: 100)]
        #expect(try context.fetchCount(FetchDescriptor<BudgetCategoryLimit>()) == 0)

        #expect(BudgetCategoryGoalStore.apply(drafts, categories: [category], budget: budget,
                                            workspaceID: workspace.id, modelContext: context))
        try context.save()
        let stored = try #require(context.fetch(FetchDescriptor<BudgetCategoryLimit>()).first)
        #expect(stored.budget?.id == budget.id)
        #expect(stored.category?.id == category.id)
        #expect(stored.minAmount == 25)
        #expect(stored.maxAmount == 100)
    }

    @Test func goalsCannotCrossWorkspaceOrBudgetBoundaries() throws {
        let context = try makeContext()
        let personal = Workspace(name: "Personal", hexColor: "#000000")
        let work = Workspace(name: "Work", hexColor: "#000000")
        let personalCategory = Category(name: "Travel", hexColor: "#000000", workspace: personal)
        let workCategory = Category(name: "Travel", hexColor: "#000000", workspace: work)
        let first = Budget(name: "First", startDate: .now, endDate: .now, workspace: personal)
        let other = Budget(name: "Other", startDate: .now, endDate: .now, workspace: personal)
        let existing = BudgetCategoryLimit(maxAmount: 300, budget: other, category: personalCategory)
        for workspace in [personal, work] { context.insert(workspace) }
        for category in [personalCategory, workCategory] { context.insert(category) }
        for budget in [first, other] { context.insert(budget) }
        context.insert(existing)
        try context.save()

        let drafts = [personalCategory.id: CategoryGoalDraft(maximumText: "100"),
                      workCategory.id: CategoryGoalDraft(maximumText: "200")]
        #expect(!BudgetCategoryGoalStore.apply(drafts, categories: [personalCategory, workCategory],
                                              budget: first, workspaceID: work.id, modelContext: context))
        #expect(BudgetCategoryGoalStore.apply(drafts, categories: [personalCategory, workCategory],
                                             budget: first, workspaceID: personal.id, modelContext: context))
        try context.save()
        let goals = try context.fetch(FetchDescriptor<BudgetCategoryLimit>())
        #expect(goals.count == 2)
        #expect(goals.filter { $0.budget?.id == first.id }.allSatisfy { $0.category?.workspace?.id == personal.id })
        #expect(existing.maxAmount == 300)
    }

    @Test func clearingAGoalPreservesExpensesAndOtherBudgets() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#000000")
        let category = Category(name: "Groceries", hexColor: "#000000", workspace: workspace)
        let first = Budget(name: "First", startDate: .now, endDate: .now, workspace: workspace)
        let other = Budget(name: "Other", startDate: .now, endDate: .now, workspace: workspace)
        let firstGoal = BudgetCategoryLimit(maxAmount: 100, budget: first, category: category)
        let otherGoal = BudgetCategoryLimit(maxAmount: 200, budget: other, category: category)
        let expense = VariableExpense(descriptionText: "Groceries", amount: 25, transactionDate: .now, workspace: workspace, category: category)
        context.insert(workspace)
        context.insert(category)
        context.insert(first)
        context.insert(other)
        context.insert(firstGoal)
        context.insert(otherGoal)
        context.insert(expense)
        try context.save()

        #expect(BudgetCategoryGoalStore.apply([category.id: CategoryGoalDraft()], categories: [category],
                                             budget: first, workspaceID: workspace.id, modelContext: context))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<BudgetCategoryLimit>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<VariableExpense>()) == 1)
        #expect(otherGoal.maxAmount == 200)
        #expect(expense.category?.id == category.id)
    }

    @Test func invalidBatchDoesNotPartiallyChangeOtherGoals() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#000000")
        let groceries = Category(name: "Groceries", hexColor: "#000000", workspace: workspace)
        let dining = Category(name: "Dining", hexColor: "#000000", workspace: workspace)
        let budget = Budget(name: "Budget", startDate: .now, endDate: .now, workspace: workspace)
        let existing = BudgetCategoryLimit(maxAmount: 100, budget: budget, category: groceries)
        context.insert(workspace)
        context.insert(groceries)
        context.insert(dining)
        context.insert(budget)
        context.insert(existing)
        try context.save()

        let drafts = [groceries.id: CategoryGoalDraft(minimum: nil, maximum: 200),
                      dining.id: CategoryGoalDraft(minimum: 100, maximum: 50)]
        #expect(!BudgetCategoryGoalStore.apply(drafts, categories: [groceries, dining],
                                              budget: budget, workspaceID: workspace.id, modelContext: context))
        #expect(existing.maxAmount == 100)
        #expect(try context.fetchCount(FetchDescriptor<BudgetCategoryLimit>()) == 1)
    }

    @Test func failedCreationCleanupPreservesHistoryAndUnrelatedPendingRecords() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#000000")
        let category = Category(name: "Bills", hexColor: "#000000", workspace: workspace)
        let card = Card(name: "Debit", workspace: workspace)
        let existingBudget = Budget(name: "Existing", startDate: .now, endDate: .now, workspace: workspace)
        let existingPlan = PlannedExpense(title: "Existing bill", plannedAmount: 50, actualAmount: 50,
                                          expenseDate: .now, workspace: workspace, card: card,
                                          sourceBudgetID: existingBudget.id)
        context.insert(workspace)
        context.insert(category)
        context.insert(card)
        context.insert(existingBudget)
        context.insert(existingPlan)
        try context.save()

        let unrelatedPending = VariableExpense(descriptionText: "Pending groceries", amount: 20,
                                               transactionDate: .now, workspace: workspace, card: card)
        context.insert(unrelatedPending)
        let attempt = Budget(name: "Attempt", startDate: .now, endDate: .now, workspace: workspace)
        let attemptPlan = PlannedExpense(title: "New bill", plannedAmount: 100, expenseDate: .now,
                                         workspace: workspace, card: card, sourceBudgetID: attempt.id)
        context.insert(attempt)
        context.insert(BudgetCardLink(budget: attempt, card: card))
        context.insert(BudgetCategoryLimit(maxAmount: 100, budget: attempt, category: category))
        context.insert(attemptPlan)

        #expect(BudgetCreationAttemptCleanup.discard(budget: attempt,
                                                     createdPlannedExpenses: [attemptPlan, existingPlan],
                                                     modelContext: context))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Budget>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<BudgetCategoryLimit>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<BudgetCardLink>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PlannedExpense>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<VariableExpense>()) == 1)
        #expect(existingPlan.actualAmount == 50)
        #expect(unrelatedPending.amount == 20)
        #expect(!BudgetCreationAttemptCleanup.discard(budget: existingBudget,
                                                      createdPlannedExpenses: [existingPlan],
                                                      modelContext: context))
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Workspace.self, Budget.self, BudgetCategoryLimit.self, Card.self, BudgetCardLink.self,
            BudgetPresetLink.self, Category.self, Preset.self, PlannedExpense.self, VariableExpense.self,
            AllocationAccount.self, ExpenseAllocation.self, AllocationSettlement.self, SavingsAccount.self,
            SavingsLedgerEntry.self, ImportMerchantRule.self, AssistantAliasRule.self, MarinaChatSession.self,
            IncomeSeries.self, Income.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: configuration))
    }
}
