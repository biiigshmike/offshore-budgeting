import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct MarinaCrudParityTests {

    private struct CrudParityRow: Equatable {
        enum Support: String, Equatable {
            case supported
            case partial
            case unsupported
        }

        let entity: String
        let create: Support
        let update: Support
        let delete: Support
    }

    private let mutationService = HomeAssistantMutationService()

    private var coreCrudMatrix: [CrudParityRow] {
        [
            CrudParityRow(entity: "Expense", create: .supported, update: .supported, delete: .supported),
            CrudParityRow(entity: "Income", create: .supported, update: .supported, delete: .supported),
            CrudParityRow(entity: "Card", create: .supported, update: .supported, delete: .supported),
            CrudParityRow(entity: "Category", create: .supported, update: .supported, delete: .supported),
            CrudParityRow(entity: "Preset", create: .supported, update: .supported, delete: .supported),
            CrudParityRow(entity: "Budget", create: .supported, update: .supported, delete: .supported),
            CrudParityRow(entity: "Planned Expense", create: .supported, update: .supported, delete: .supported)
        ]
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

    private func fetchAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }

    private func makeCommandParser() -> HomeAssistantCommandParser {
        HomeAssistantCommandParser()
    }

    private func makeWorkspace(in context: ModelContext) throws -> Workspace {
        let workspace = Workspace(name: "WS", hexColor: "#3B82F6")
        context.insert(workspace)
        try context.save()
        return workspace
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func coreCrudMatrix_matchesCurrentMarinaParity() {
        #expect(coreCrudMatrix == [
            CrudParityRow(entity: "Expense", create: .supported, update: .supported, delete: .supported),
            CrudParityRow(entity: "Income", create: .supported, update: .supported, delete: .supported),
            CrudParityRow(entity: "Card", create: .supported, update: .supported, delete: .supported),
            CrudParityRow(entity: "Category", create: .supported, update: .supported, delete: .supported),
            CrudParityRow(entity: "Preset", create: .supported, update: .supported, delete: .supported),
            CrudParityRow(entity: "Budget", create: .supported, update: .supported, delete: .supported),
            CrudParityRow(entity: "Planned Expense", create: .supported, update: .supported, delete: .supported)
        ])
    }

    @Test func parser_supportedCrudPrompts_mapToCurrentCoreEntityIntents() {
        let parser = makeCommandParser()

        #expect(parser.parse("add expense coffee $18")?.intent == .addExpense)
        #expect(parser.parse("edit expense coffee $20")?.intent == .editExpense)
        #expect(parser.parse("delete expense $20 coffee")?.intent == .deleteExpense)

        #expect(parser.parse("add income paycheck $1200")?.intent == .addIncome)
        #expect(parser.parse("edit income paycheck to $1400")?.intent == .editIncome)
        #expect(parser.parse("delete income paycheck $1400")?.intent == .deleteIncome)

        #expect(parser.parse("create card named Travel Card")?.intent == .addCard)
        #expect(parser.parse("edit card named Travel Card theme aqua")?.intent == .editCard)
        #expect(parser.parse("remove card named Travel Card")?.intent == .deleteCard)

        #expect(parser.parse("edit category groceries to dining")?.intent == .editCategory)
        #expect(parser.parse("delete category groceries")?.intent == .deleteCategory)
        #expect(parser.parse("edit preset rent to 1600")?.intent == .editPreset)
        #expect(parser.parse("delete preset rent")?.intent == .deletePreset)
        #expect(parser.parse("edit budget March 2026 to April 2026")?.intent == .editBudget)
        #expect(parser.parse("delete budget March 2026")?.intent == .deleteBudget)
        #expect(parser.parse("create planned expense rent 1450 on 2026-03-01")?.intent == .addPlannedExpense)
        #expect(parser.parse("edit planned expense rent actual to $1450")?.intent == .editPlannedExpense)
        #expect(parser.parse("delete planned expense rent")?.intent == .deletePlannedExpense)
    }

    @Test func expenseCrud_supportedMutationFlow_persistsCreateUpdateDeleteAndCategoryMove() throws {
        let context = try makeContext()
        let workspace = try makeWorkspace(in: context)
        let card = Card(name: "Visa", workspace: workspace)
        let oldCategory = Category(name: "Dining", hexColor: "#FF0000", workspace: workspace)
        let newCategory = Category(name: "Groceries", hexColor: "#00FF00", workspace: workspace)
        context.insert(card)
        context.insert(oldCategory)
        context.insert(newCategory)
        try context.save()

        let logged = try mutationService.addExpense(
            amount: 18,
            notes: "Coffee",
            date: makeDate(2026, 2, 1),
            card: card,
            category: oldCategory,
            workspace: workspace,
            modelContext: context
        )

        #expect(logged.title == "Expense logged")

        var expenses = try fetchAll(VariableExpense.self, in: context)
        #expect(expenses.count == 1)
        #expect(expenses[0].descriptionText == "Coffee")
        #expect(expenses[0].category?.name == "Dining")

        let editCommand = HomeAssistantCommandPlan(
            intent: .editExpense,
            confidenceBand: .high,
            rawPrompt: "edit expense coffee to $20",
            amount: 20,
            notes: "Coffee beans"
        )
        let updated = try mutationService.editExpense(
            expenses[0],
            command: editCommand,
            card: nil,
            modelContext: context
        )
        #expect(updated.title == "Expense updated")

        let moved = try mutationService.moveExpenseCategory(
            expense: expenses[0],
            category: newCategory,
            modelContext: context
        )
        #expect(moved.title == "Expense category updated")

        expenses = try fetchAll(VariableExpense.self, in: context)
        #expect(expenses[0].amount == 20)
        #expect(expenses[0].descriptionText == "Coffee beans")
        #expect(expenses[0].category?.name == "Groceries")

        let deleted = try mutationService.deleteExpense(expenses[0], modelContext: context)
        #expect(deleted.title == "Expense deleted")
        #expect(try fetchAll(VariableExpense.self, in: context).isEmpty)
    }

    @Test func incomeCrud_supportedMutationFlow_persistsCreateUpdateDelete() throws {
        let context = try makeContext()
        let workspace = try makeWorkspace(in: context)

        let created = try mutationService.addIncome(
            amount: 1200,
            source: "Paycheck",
            date: makeDate(2026, 2, 1),
            isPlanned: true,
            workspace: workspace,
            modelContext: context
        )
        #expect(created.title == "Income logged")

        var incomes = try fetchAll(Income.self, in: context)
        #expect(incomes.count == 1)
        #expect(incomes[0].source == "Paycheck")
        #expect(incomes[0].isPlanned)

        let editCommand = HomeAssistantCommandPlan(
            intent: .editIncome,
            confidenceBand: .high,
            rawPrompt: "edit income paycheck to 1400 actual",
            amount: 1400,
            source: "Main Paycheck",
            isPlannedIncome: false
        )
        let updated = try mutationService.editIncome(incomes[0], command: editCommand, modelContext: context)
        #expect(updated.title == "Income updated")

        incomes = try fetchAll(Income.self, in: context)
        #expect(incomes[0].amount == 1400)
        #expect(incomes[0].source == "Main Paycheck")
        #expect(incomes[0].isPlanned == false)

        let deleted = try mutationService.deleteIncome(incomes[0], modelContext: context)
        #expect(deleted.title == "Income deleted")
        #expect(try fetchAll(Income.self, in: context).isEmpty)
    }

    @Test func cardCrud_currentParity_supportsCreateRenameStyleUpdateAndDelete() throws {
        let context = try makeContext()
        let workspace = try makeWorkspace(in: context)

        let created = try mutationService.addCard(
            name: "Travel Card",
            themeRaw: "aqua",
            effectRaw: "glass",
            workspace: workspace,
            modelContext: context
        )
        #expect(created.title == "Card created")

        var cards = try fetchAll(Card.self, in: context)
        #expect(cards.count == 1)
        #expect(cards[0].name == "Travel Card")

        let updated = try mutationService.editCard(
            card: cards[0],
            newName: "Travel Rewards",
            themeRaw: "sunset",
            effectRaw: nil,
            modelContext: context
        )
        #expect(updated.title == "Card updated")

        cards = try fetchAll(Card.self, in: context)
        #expect(cards[0].name == "Travel Rewards")
        #expect(cards[0].theme == CardThemeOption.sunset.rawValue)

        let deleted = try mutationService.deleteCard(cards[0], workspace: workspace, modelContext: context)
        #expect(deleted.title == "Card deleted")
        #expect(try fetchAll(Card.self, in: context).isEmpty)
    }

    @Test func categoryPresetBudgetAndPlannedExpense_currentParity_matchesSupportedOperations() throws {
        let context = try makeContext()
        let workspace = try makeWorkspace(in: context)
        let card = Card(name: "Visa", workspace: workspace)
        let category = Category(name: "Rent", hexColor: "#111111", workspace: workspace)
        context.insert(card)
        context.insert(category)
        try context.save()

        let categoryResult = try mutationService.addCategory(
            name: "Groceries",
            colorHex: "#22C55E",
            workspace: workspace,
            modelContext: context
        )
        #expect(categoryResult.title == "Category created")

        let createdCategory = try #require(fetchAll(Category.self, in: context).first(where: { $0.name == "Groceries" }))
        let editedCategory = try mutationService.editCategory(
            createdCategory,
            newName: "Dining",
            colorHex: "#EF4444",
            modelContext: context
        )
        #expect(editedCategory.title == "Category updated")

        let presetResult = try mutationService.addPreset(
            title: "Rent",
            plannedAmount: 1500,
            frequencyRaw: RecurrenceFrequency.monthly.rawValue,
            interval: 1,
            weeklyWeekday: 6,
            monthlyDayOfMonth: 1,
            monthlyIsLastDay: false,
            yearlyMonth: 1,
            yearlyDayOfMonth: 1,
            card: card,
            category: category,
            workspace: workspace,
            modelContext: context
        )
        #expect(presetResult.title == "Preset created")

        let createdPreset = try #require(fetchAll(Preset.self, in: context).first(where: { $0.title == "Rent" }))
        let presetEditCommand = HomeAssistantCommandPlan(
            intent: .editPreset,
            confidenceBand: .high,
            rawPrompt: "edit preset rent to 1600",
            amount: 1600,
            updatedEntityName: "Mortgage"
        )
        let editedPreset = try mutationService.editPreset(
            createdPreset,
            command: presetEditCommand,
            card: card,
            category: category,
            workspace: workspace,
            modelContext: context
        )
        #expect(editedPreset.title == "Preset updated")

        let budgetResult = try mutationService.addBudget(
            name: "March 2026",
            dateRange: HomeQueryDateRange(
                startDate: makeDate(2026, 3, 1),
                endDate: makeDate(2026, 3, 31)
            ),
            cards: [card],
            presets: [],
            workspace: workspace,
            modelContext: context
        )
        #expect(budgetResult.title == "Budget created")

        let createdBudget = try #require(fetchAll(Budget.self, in: context).first(where: { $0.name == "March 2026" }))
        let budgetEditCommand = HomeAssistantCommandPlan(
            intent: .editBudget,
            confidenceBand: .high,
            rawPrompt: "edit budget March 2026 to April 2026",
            dateRange: HomeQueryDateRange(
                startDate: makeDate(2026, 4, 1),
                endDate: makeDate(2026, 4, 30)
            ),
            updatedEntityName: "April 2026"
        )
        let editedBudget = try mutationService.editBudget(
            createdBudget,
            command: budgetEditCommand,
            workspace: workspace,
            modelContext: context
        )
        #expect(editedBudget.title == "Budget updated")

        let plannedExpenseResult = try mutationService.addPlannedExpense(
            title: "Rent",
            amount: 1500,
            date: makeDate(2026, 3, 1),
            card: card,
            category: category,
            workspace: workspace,
            modelContext: context
        )
        #expect(plannedExpenseResult.title == "Planned expense created")

        let plannedExpense = try #require(fetchAll(PlannedExpense.self, in: context).first(where: { $0.title == "Rent" }))
        let plannedEditCommand = HomeAssistantCommandPlan(
            intent: .editPlannedExpense,
            confidenceBand: .high,
            rawPrompt: "edit planned expense rent actual to $1450",
            amount: 1450,
            updatedEntityName: "Rent - Actual",
            plannedExpenseAmountTarget: .actual
        )
        let plannedUpdate = try mutationService.editPlannedExpense(
            plannedExpense,
            command: plannedEditCommand,
            card: card,
            category: category,
            modelContext: context
        )
        #expect(plannedUpdate.title == "Planned expense updated")

        let categories = try fetchAll(Category.self, in: context)
        let presets = try fetchAll(Preset.self, in: context)
        let budgets = try fetchAll(Budget.self, in: context)
        let plannedExpenses = try fetchAll(PlannedExpense.self, in: context)

        #expect(categories.contains(where: { $0.name == "Dining" && $0.hexColor == "#EF4444" }))
        #expect(presets.contains(where: { $0.title == "Mortgage" && $0.plannedAmount == 1600 }))
        #expect(budgets.contains(where: { $0.name == "April 2026" }))
        #expect(plannedExpenses.contains(where: { $0.title == "Rent - Actual" && $0.actualAmount == 1450 }))

        let categoryToDelete = try #require(categories.first(where: { $0.name == "Dining" }))
        let presetToDelete = try #require(presets.first(where: { $0.title == "Mortgage" }))
        let budgetToDelete = try #require(budgets.first(where: { $0.name == "April 2026" }))
        let plannedToDelete = try #require(plannedExpenses.first(where: { $0.title == "Rent - Actual" }))

        #expect(try mutationService.deleteCategory(categoryToDelete, modelContext: context).title == "Category deleted")
        #expect(try mutationService.deletePreset(presetToDelete, modelContext: context).title == "Preset deleted")
        #expect(try mutationService.deleteBudget(budgetToDelete, modelContext: context).title == "Budget deleted")
        #expect(try mutationService.deletePlannedExpense(plannedToDelete, modelContext: context).title == "Planned expense deleted")
    }
}
