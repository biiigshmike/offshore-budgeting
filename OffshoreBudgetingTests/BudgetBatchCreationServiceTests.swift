import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct BudgetBatchCreationServiceTests {
    private func container() throws -> ModelContainer {
        let schema = Schema([
            Workspace.self, Budget.self, BudgetCategoryLimit.self, Card.self, BudgetCardLink.self,
            BudgetPresetLink.self, Category.self, Preset.self, PlannedExpense.self, VariableExpense.self,
            AllocationAccount.self, ExpenseAllocation.self, AllocationSettlement.self, SavingsAccount.self,
            SavingsLedgerEntry.self, ImportMerchantRule.self, AssistantAliasRule.self, MarinaChatSession.self,
            IncomeSeries.self, Income.self
        ])
        return try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    private func date(_ month: Int, _ day: Int = 1) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day))!
    }

    private func preview(_ workspace: Workspace, _ context: ModelContext, presets: [Preset] = [], name: String = "Household") throws -> BudgetBatchPreview {
        try BudgetBatchCreationService.preview(
            workspace: workspace,
            ranges: BudgetCycleCalculator.ranges(startDate: date(1), period: .monthly, interval: 1, count: 2),
            templateName: name, customName: true, preserveFirstName: true, presets: presets, modelContext: context
        )
    }

    @Test func createsIndependentBudgetsAndOnlyFreshPlannedExpenses() throws {
        let store = try container()
        let context = ModelContext(store)
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        context.insert(workspace)
        let card = Card(name: "Card", workspace: workspace)
        let category = Category(name: "Bills", hexColor: "#123456", workspace: workspace)
        let preset = Preset(title: "Rent", plannedAmount: 100, monthlyDayOfMonth: 15, workspace: workspace, defaultCard: card, defaultCategory: category)
        context.insert(card)
        context.insert(category)
        context.insert(preset)
        let source = Budget(name: "Historical", startDate: date(3), endDate: date(3, 31), workspace: workspace)
        let recorded = PlannedExpense(title: "Recorded rent", plannedAmount: 100, actualAmount: 125, expenseDate: date(3, 15), workspace: workspace, card: card, category: category, sourcePresetID: preset.id, sourceBudgetID: source.id)
        let variable = VariableExpense(descriptionText: "Groceries", amount: 45, transactionDate: date(3, 15), workspace: workspace, card: card, category: category)
        let income = Income(source: "Salary", amount: 500, date: date(3, 15), isPlanned: false, workspace: workspace, card: card)
        context.insert(source)
        context.insert(recorded)
        context.insert(variable)
        context.insert(income)
        try context.save()
        let plan = try preview(workspace, context, presets: [preset])
        #expect(plan.plannedExpenseCount == 2)
        var saveCount = 0
        let created = try BudgetBatchCreationService.create(
            workspace: workspace, preview: plan, cards: [card], presets: [preset], categories: [category],
            categoryGoalDrafts: [category.id: CategoryGoalDraft(minimum: 50, maximum: 200)],
            allowOverlaps: false, modelContext: context, save: {
                saveCount += 1
                try context.save()
            }
        )
        #expect(saveCount == 1)
        #expect(created.count == 2)
        let allExpenses = try context.fetch(FetchDescriptor<PlannedExpense>())
        #expect(allExpenses.count == plan.plannedExpenseCount + 1)
        let expenses = allExpenses.filter { $0.id != recorded.id }
        #expect(expenses.count == plan.plannedExpenseCount)
        #expect(Set(expenses.compactMap(\.sourceBudgetID)) == Set(created.map(\.id)))
        #expect(expenses.allSatisfy { $0.actualAmount == 0 && $0.sourcePresetID == preset.id && $0.card?.id == card.id })
        #expect(try context.fetch(FetchDescriptor<BudgetCardLink>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<BudgetPresetLink>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<BudgetCategoryLimit>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<VariableExpense>()).map(\.id) == [variable.id])
        #expect(try context.fetch(FetchDescriptor<Income>()).map(\.id) == [income.id])
        #expect(recorded.actualAmount == 125 && recorded.sourceBudgetID == source.id)
        #expect(recorded.card?.id == card.id && recorded.category?.id == category.id)
        #expect(variable.amount == 45 && variable.transactionDate == date(3, 15))
        #expect(income.amount == 500 && !income.isPlanned && income.card?.id == card.id)
        #expect(source.name == "Historical" && source.startDate == date(3) && source.endDate == date(3, 31))
        #expect(try context.fetch(FetchDescriptor<SavingsLedgerEntry>()).isEmpty)
        created[0].name = "Edited independently"
        #expect(created[1].name == plan.drafts[1].name)
    }

    @Test func nameCollisionsAndDateConflictsAreWorkspaceScoped() throws {
        let store = try container()
        let context = ModelContext(store)
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        let other = Workspace(name: "Work", hexColor: "#123456")
        context.insert(workspace)
        context.insert(other)
        context.insert(Budget(name: " household ", startDate: date(5), endDate: date(5, 31), workspace: workspace))
        context.insert(Budget(name: "Household (2)", startDate: date(1), endDate: date(1, 31), workspace: other))
        try context.save()
        let plan = try preview(workspace, context)
        #expect(plan.drafts[0].name == "Household (2)")
        #expect(plan.overlappingBudgetNames.isEmpty)
        context.insert(Budget(name: "Existing January", startDate: date(1), endDate: date(1, 31), workspace: workspace))
        #expect(throws: BudgetBatchCreationService.CreationError.self) { try preview(workspace, context) }
        #expect(throws: BudgetBatchCreationService.CreationError.self) {
            try BudgetBatchCreationService.create(workspace: workspace, preview: plan, cards: [], presets: [], categories: [], categoryGoalDrafts: [:], allowOverlaps: true, modelContext: context)
        }
        #expect(try context.fetch(FetchDescriptor<Budget>()).count == 3)
    }

    @Test func overlappingBudgetsRequireConfirmationAndAreRechecked() throws {
        let store = try container()
        let context = ModelContext(store)
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        context.insert(workspace)
        context.insert(Budget(name: "Existing", startDate: date(1, 15), endDate: date(2, 15), workspace: workspace))
        try context.save()
        let plan = try preview(workspace, context)
        #expect(plan.overlappingBudgetNames == ["Existing"])
        #expect(throws: BudgetBatchCreationService.CreationError.self) {
            try BudgetBatchCreationService.create(workspace: workspace, preview: plan, cards: [], presets: [], categories: [], categoryGoalDrafts: [:], allowOverlaps: false, modelContext: context)
        }
        context.insert(Budget(name: "New conflict", startDate: date(2, 10), endDate: date(3), workspace: workspace))
        #expect(throws: BudgetBatchCreationService.CreationError.self) {
            try BudgetBatchCreationService.create(workspace: workspace, preview: plan, cards: [], presets: [], categories: [], categoryGoalDrafts: [:], allowOverlaps: true, modelContext: context)
        }
        #expect(try context.fetch(FetchDescriptor<Budget>()).count == 2)
    }

    @Test func confirmedOverlapCreatesBatchWithoutChangingExistingBudget() throws {
        let store = try container()
        let context = ModelContext(store)
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        context.insert(workspace)
        let existing = Budget(name: "Existing", startDate: date(1, 15), endDate: date(2, 15), workspace: workspace)
        context.insert(existing)
        try context.save()
        let plan = try preview(workspace, context)
        let created = try BudgetBatchCreationService.create(workspace: workspace, preview: plan, cards: [], presets: [], categories: [], categoryGoalDrafts: [:], allowOverlaps: true, modelContext: context)
        #expect(created.count == 2)
        #expect(try context.fetch(FetchDescriptor<Budget>()).count == 3)
        #expect(existing.name == "Existing" && existing.startDate == date(1, 15) && existing.endDate == date(2, 15))
    }

    @Test func archivedPresetsAreExcludedAndForeignSelectionsRejected() throws {
        let store = try container()
        let context = ModelContext(store)
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        let other = Workspace(name: "Work", hexColor: "#123456")
        context.insert(workspace)
        context.insert(other)
        let archived = Preset(title: "Old", plannedAmount: 100, workspace: workspace, isArchived: true)
        let foreignCard = Card(name: "Foreign", workspace: other)
        context.insert(archived)
        context.insert(foreignCard)
        try context.save()
        let plan = try preview(workspace, context, presets: [archived])
        #expect(plan.plannedExpenseCount == 0)
        #expect(throws: BudgetBatchCreationService.CreationError.self) {
            try BudgetBatchCreationService.create(workspace: workspace, preview: plan, cards: [foreignCard], presets: [archived], categories: [], categoryGoalDrafts: [:], allowOverlaps: false, modelContext: context)
        }
        try BudgetBatchCreationService.create(workspace: workspace, preview: plan, cards: [], presets: [archived], categories: [], categoryGoalDrafts: [:], allowOverlaps: false, modelContext: context)
        #expect(try context.fetch(FetchDescriptor<BudgetPresetLink>()).isEmpty)
    }

    @Test func failedSaveCleansOnlyAttemptAndAllowsRetry() throws {
        enum SaveFailure: Error { case expected }
        let store = try container()
        let context = ModelContext(store)
        context.autosaveEnabled = false
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        context.insert(workspace)
        let card = Card(name: "Card", workspace: workspace)
        let preset = Preset(title: "Rent", plannedAmount: 100, workspace: workspace, defaultCard: card)
        let category = Category(name: "Bills", hexColor: "#123456", workspace: workspace)
        context.insert(card)
        context.insert(preset)
        context.insert(category)
        try context.save()
        card.name = "Unrelated pending edit"
        let unrelated = Budget(name: "Other", startDate: date(6), endDate: date(6, 30), workspace: workspace)
        context.insert(unrelated)
        let plan = try preview(workspace, context, presets: [preset])
        let goals = [category.id: CategoryGoalDraft(minimum: 50, maximum: 200)]
        var saveCount = 0
        #expect(throws: SaveFailure.self) {
            try BudgetBatchCreationService.create(workspace: workspace, preview: plan, cards: [card], presets: [preset], categories: [category], categoryGoalDrafts: goals, allowOverlaps: false, modelContext: context, save: {
                saveCount += 1
                throw SaveFailure.expected
            })
        }
        #expect(saveCount == 1)
        #expect(card.name == "Unrelated pending edit")
        #expect(!WorkspaceProgressService.completedSteps(in: workspace).contains(.budget))
        #expect(try context.fetch(FetchDescriptor<Budget>()).map(\.id) == [unrelated.id])
        #expect(try context.fetch(FetchDescriptor<PlannedExpense>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<BudgetCardLink>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<BudgetPresetLink>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<BudgetCategoryLimit>()).isEmpty)
        let retried = try BudgetBatchCreationService.create(workspace: workspace, preview: plan, cards: [card], presets: [preset], categories: [category], categoryGoalDrafts: goals, allowOverlaps: false, modelContext: context)
        #expect(retried.count == 2)
        #expect(try context.fetch(FetchDescriptor<PlannedExpense>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<BudgetCardLink>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<BudgetPresetLink>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<BudgetCategoryLimit>()).count == 2)
    }

    @Test func excessivePlannedExpenseCountIsRejectedBeforeInsertion() throws {
        let store = try container()
        let context = ModelContext(store)
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        context.insert(workspace)
        let preset = Preset(title: "Daily", plannedAmount: 1, frequencyRaw: RecurrenceFrequency.daily.rawValue, workspace: workspace)
        context.insert(preset)
        try context.save()
        let ranges = try BudgetCycleCalculator.ranges(startDate: date(1), period: .yearly, interval: 30, count: 1)
        #expect(throws: BudgetBatchCreationService.CreationError.self) {
            try BudgetBatchCreationService.preview(workspace: workspace, ranges: ranges, templateName: "Too many", customName: false, preserveFirstName: true, presets: [preset], modelContext: context)
        }
        #expect(try context.fetch(FetchDescriptor<Budget>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PlannedExpense>()).isEmpty)
    }
}
