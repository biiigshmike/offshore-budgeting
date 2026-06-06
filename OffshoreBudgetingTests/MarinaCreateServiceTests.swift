import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct MarinaCreateServiceTests {
    private func makeContext() throws -> ModelContext {
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
            AllocationAccount.self,
            ExpenseAllocation.self,
            AllocationSettlement.self,
            SavingsAccount.self,
            SavingsLedgerEntry.self,
            ImportMerchantRule.self,
            AssistantAliasRule.self,
            MarinaChatSession.self,
            IncomeSeries.self,
            Income.self
        ])

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        return ModelContext(container)
    }

    private func fetchAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }

    @Test func explicitExpenseCreate_persistsInSelectedWorkspaceOnly() throws {
        let context = try makeContext()
        let service = MarinaCreateService()
        let selectedWorkspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let otherWorkspace = Workspace(name: "Work", hexColor: "#14B8A6")
        let card = Card(name: "Apple Card", workspace: selectedWorkspace)
        let category = Category(name: "Coffee", hexColor: "#8B5CF6", workspace: selectedWorkspace)

        context.insert(selectedWorkspace)
        context.insert(otherWorkspace)
        context.insert(card)
        context.insert(category)
        try context.save()

        let result = try service.addExpense(
            amount: 12.45,
            notes: "Coffee beans",
            date: date(2026, 5, 10),
            card: card,
            category: category,
            workspace: selectedWorkspace,
            modelContext: context
        )

        let expenses = try fetchAll(VariableExpense.self, in: context)
        #expect(result.title == "Expense logged")
        #expect(expenses.count == 1)
        #expect(expenses.first?.workspace?.id == selectedWorkspace.id)
        #expect(expenses.first?.workspace?.id != otherWorkspace.id)
        #expect(expenses.first?.descriptionText == "Coffee beans")
    }

    @Test func explicitBudgetCreate_linksCardsAndPresetsInSelectedWorkspace() throws {
        let context = try makeContext()
        let service = MarinaCreateService()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let card = Card(name: "Visa", workspace: workspace)
        let category = Category(name: "Bills", hexColor: "#2563EB", workspace: workspace)
        let preset = Preset(
            title: "Internet",
            plannedAmount: 90,
            frequencyRaw: RecurrenceFrequency.monthly.rawValue,
            interval: 1,
            monthlyDayOfMonth: 15,
            workspace: workspace,
            defaultCard: card,
            defaultCategory: category
        )

        context.insert(workspace)
        context.insert(card)
        context.insert(category)
        context.insert(preset)
        try context.save()

        let range = HomeQueryDateRange(startDate: date(2026, 5, 1), endDate: date(2026, 5, 31))
        let result = try service.addBudget(
            name: "May 2026",
            dateRange: range,
            cards: [card],
            presets: [preset],
            workspace: workspace,
            modelContext: context
        )

        let budgets = try fetchAll(Budget.self, in: context)
        let cardLinks = try fetchAll(BudgetCardLink.self, in: context)
        let presetLinks = try fetchAll(BudgetPresetLink.self, in: context)
        let plannedExpenses = try fetchAll(PlannedExpense.self, in: context)

        #expect(result.title == "Budget created")
        #expect(budgets.count == 1)
        #expect(cardLinks.count == 1)
        #expect(presetLinks.count == 1)
        #expect(plannedExpenses.count == 1)
        #expect(plannedExpenses.first?.workspace?.id == workspace.id)
        #expect(plannedExpenses.first?.sourceBudgetID == budgets.first?.id)
        #expect(plannedExpenses.first?.sourcePresetID == preset.id)
    }

    @Test func explicitBudgetCreate_ignoresArchivedPresets() throws {
        let context = try makeContext()
        let service = MarinaCreateService()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let card = Card(name: "Visa", workspace: workspace)
        let archivedPreset = Preset(
            title: "Old Internet",
            plannedAmount: 90,
            frequencyRaw: RecurrenceFrequency.monthly.rawValue,
            interval: 1,
            monthlyDayOfMonth: 15,
            workspace: workspace,
            defaultCard: card,
            isArchived: true,
            archivedAt: date(2026, 4, 1)
        )

        context.insert(workspace)
        context.insert(card)
        context.insert(archivedPreset)
        try context.save()

        let range = HomeQueryDateRange(startDate: date(2026, 5, 1), endDate: date(2026, 5, 31))
        let result = try service.addBudget(
            name: "May 2026",
            dateRange: range,
            cards: [card],
            presets: [archivedPreset],
            workspace: workspace,
            modelContext: context
        )

        let budgets = try fetchAll(Budget.self, in: context)
        let cardLinks = try fetchAll(BudgetCardLink.self, in: context)
        let presetLinks = try fetchAll(BudgetPresetLink.self, in: context)
        let plannedExpenses = try fetchAll(PlannedExpense.self, in: context)

        #expect(result.rows.contains { $0.title == "Presets" && $0.value == "0 linked" })
        #expect(budgets.count == 1)
        #expect(cardLinks.count == 1)
        #expect(presetLinks.isEmpty)
        #expect(plannedExpenses.isEmpty)
    }

    @Test func freeTextSubmissionPolicy_allowsReadOnlyQuestionsWithoutMutation() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        context.insert(workspace)
        try context.save()

        #expect(MarinaPromptSubmissionPolicy.shouldHandleFreeText("how much did I spend?") == true)
        #expect(try fetchAll(VariableExpense.self, in: context).isEmpty)
        #expect(try fetchAll(Income.self, in: context).isEmpty)
        #expect(try fetchAll(Budget.self, in: context).isEmpty)
    }

    @Test func homeAnswerDecode_ignoresLegacyAttachmentKinds() throws {
        let answerID = UUID()
        let queryID = UUID()
        let json = """
        {
          "id": "\(answerID.uuidString)",
          "queryID": "\(queryID.uuidString)",
          "kind": "message",
          "title": "Legacy answer",
          "rows": [],
          "attachment": {
            "kind": "cardSummary"
          },
          "generatedAt": 0
        }
        """

        let answer = try JSONDecoder().decode(HomeAnswer.self, from: Data(json.utf8))

        #expect(answer.id == answerID)
        #expect(answer.queryID == queryID)
        #expect(answer.title == "Legacy answer")
        #expect(answer.attachment == nil)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
