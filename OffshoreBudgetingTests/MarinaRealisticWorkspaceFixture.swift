import Foundation
import SwiftData
@testable import Offshore

@MainActor
struct MarinaRealisticWorkspaceFixture {
    let context: ModelContext
    let workspace: Workspace
    let otherWorkspace: Workspace
    let groceries: Offshore.Category
    let dining: Offshore.Category
    let travel: Offshore.Category
    let appleCard: Card
    let backupCard: Card
    let activeBudget: Budget
    let groceryBudgetLimit: BudgetCategoryLimit
    let rentPreset: Preset
    let primarySavings: SavingsAccount
    let sharedAccount: AllocationAccount
    let provider: MarinaDataProvider

    var contextForSharedPipeline: MarinaSharedPipelineContext {
        sharedPipelineContext()
    }

    func sharedPipelineContext(
        turnClassification: MarinaPromptTurnClassification = .freshQuestion,
        priorQueryContext: MarinaPriorQueryContext = .empty,
        aiOptInEnabled: Bool = false
    ) -> MarinaSharedPipelineContext {
        MarinaSharedPipelineContext(
            provider: provider,
            routerContext: MarinaLanguageRouterContext(
                workspaceName: workspace.name,
                defaultPeriodUnit: .month,
                sessionContext: HomeAssistantSessionContext(),
                priorQueryContext: priorQueryContext,
                cardNames: ["Apple", "Backup Card"],
                categoryNames: ["Groceries", "Dining", "Travel"],
                incomeSourceNames: ["Salary", "Consulting"],
                presetTitles: ["Rent"],
                budgetNames: ["May Budget"],
                aliasSummaries: [
                    MarinaAliasSummary(
                        entityTypeRaw: HomeAssistantAliasEntityType.category.rawValue,
                        aliasKey: "food",
                        targetValue: "Groceries"
                    )
                ],
                now: Self.date(2026, 5, 15)
            ),
            defaultPeriodUnit: .month,
            sharedPipelineEnabled: true,
            aiOptInEnabled: aiOptInEnabled,
            turnClassification: turnClassification,
            now: Self.date(2026, 5, 15)
        )
    }

    func run(_ prompt: String) async -> MarinaSharedPipelineRuntimeResult {
        await MarinaSharedPipelineCoordinator().run(
            prompt: prompt,
            context: contextForSharedPipeline
        )
    }

    static func make() throws -> MarinaRealisticWorkspaceFixture {
        let schema = Schema([
            Workspace.self,
            Budget.self,
            Card.self,
            BudgetCardLink.self,
            Offshore.Category.self,
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
            AssistantAliasRule.self,
            Income.self,
            SavingsAccount.self,
            SavingsLedgerEntry.self
        ])
        let config = ModelConfiguration(UUID().uuidString, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)

        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let otherWorkspace = Workspace(name: "Work", hexColor: "#111827")

        let groceries = Offshore.Category(name: "Groceries", hexColor: "#22C55E", workspace: workspace)
        let dining = Offshore.Category(name: "Dining", hexColor: "#F97316", workspace: workspace)
        let travel = Offshore.Category(name: "Travel", hexColor: "#6366F1", workspace: workspace)
        let appleCard = Card(name: "Apple", workspace: workspace)
        let backupCard = Card(name: "Backup Card", workspace: workspace)

        let otherGroceries = Offshore.Category(name: "Groceries", hexColor: "#22C55E", workspace: otherWorkspace)
        let otherAppleCard = Card(name: "Apple", workspace: otherWorkspace)

        let activeBudget = Budget(
            name: "May Budget",
            startDate: date(2026, 5, 1),
            endDate: date(2026, 5, 31),
            workspace: workspace
        )
        let groceryBudgetLimit = BudgetCategoryLimit(
            minAmount: nil,
            maxAmount: 500,
            budget: activeBudget,
            category: groceries
        )
        let rentPreset = Preset(
            title: "Rent",
            plannedAmount: 1_500,
            workspace: workspace,
            defaultCard: appleCard,
            defaultCategory: dining
        )
        let budgetCardLink = BudgetCardLink(budget: activeBudget, card: appleCard)
        let budgetPresetLink = BudgetPresetLink(budget: activeBudget, preset: rentPreset)

        let primarySavings = SavingsAccount(name: "Emergency Fund", total: 250, workspace: workspace)
        let sharedAccount = AllocationAccount(name: "Roommate", hexColor: "#14B8A6", workspace: workspace)

        context.insert(workspace)
        context.insert(otherWorkspace)
        context.insert(groceries)
        context.insert(dining)
        context.insert(travel)
        context.insert(appleCard)
        context.insert(backupCard)
        context.insert(otherGroceries)
        context.insert(otherAppleCard)
        context.insert(activeBudget)
        context.insert(groceryBudgetLimit)
        context.insert(rentPreset)
        context.insert(budgetCardLink)
        context.insert(budgetPresetLink)
        context.insert(primarySavings)
        context.insert(sharedAccount)

        seedExpenses(
            context: context,
            workspace: workspace,
            otherWorkspace: otherWorkspace,
            groceries: groceries,
            dining: dining,
            travel: travel,
            appleCard: appleCard,
            backupCard: backupCard,
            otherGroceries: otherGroceries,
            otherAppleCard: otherAppleCard,
            budget: activeBudget,
            preset: rentPreset,
            sharedAccount: sharedAccount
        )
        seedIncome(context: context, workspace: workspace, otherWorkspace: otherWorkspace, card: appleCard)
        seedSavings(context: context, workspace: workspace, otherWorkspace: otherWorkspace, account: primarySavings)
        seedMetadata(context: context, workspace: workspace, groceries: groceries)

        try context.save()

        return MarinaRealisticWorkspaceFixture(
            context: context,
            workspace: workspace,
            otherWorkspace: otherWorkspace,
            groceries: groceries,
            dining: dining,
            travel: travel,
            appleCard: appleCard,
            backupCard: backupCard,
            activeBudget: activeBudget,
            groceryBudgetLimit: groceryBudgetLimit,
            rentPreset: rentPreset,
            primarySavings: primarySavings,
            sharedAccount: sharedAccount,
            provider: MarinaDataProvider(modelContext: context, workspaceID: workspace.id)
        )
    }

    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }

    private static func seedExpenses(
        context: ModelContext,
        workspace: Workspace,
        otherWorkspace: Workspace,
        groceries: Offshore.Category,
        dining: Offshore.Category,
        travel: Offshore.Category,
        appleCard: Card,
        backupCard: Card,
        otherGroceries: Offshore.Category,
        otherAppleCard: Card,
        budget: Budget,
        preset: Preset,
        sharedAccount: AllocationAccount
    ) {
        let rent = PlannedExpense(
            title: "Rent",
            plannedAmount: 1_500,
            expenseDate: date(2026, 5, 1),
            workspace: workspace,
            card: appleCard,
            category: dining,
            sourcePresetID: preset.id,
            sourceBudgetID: budget.id
        )
        let groceriesPlan = PlannedExpense(
            title: "Groceries Plan",
            plannedAmount: 250,
            expenseDate: date(2026, 5, 5),
            workspace: workspace,
            card: appleCard,
            category: groceries,
            sourceBudgetID: budget.id
        )
        let phonePlan = PlannedExpense(
            title: "Phone Plan",
            plannedAmount: 90,
            expenseDate: date(2026, 5, 22),
            workspace: workspace,
            card: backupCard,
            category: travel,
            sourceBudgetID: budget.id
        )
        let wholeFoods = VariableExpense(
            descriptionText: "Whole Foods",
            amount: 80,
            transactionDate: date(2026, 5, 10),
            workspace: workspace,
            card: appleCard,
            category: groceries
        )
        let appleStore = VariableExpense(
            descriptionText: "Apple",
            amount: 120,
            transactionDate: date(2026, 5, 12),
            workspace: workspace,
            card: backupCard,
            category: travel
        )
        let appleWatch = VariableExpense(
            descriptionText: "Apple Watch",
            amount: 25,
            transactionDate: date(2026, 5, 11),
            workspace: workspace,
            card: backupCard,
            category: travel
        )
        let diningExpense = VariableExpense(
            descriptionText: "Cafe",
            amount: 60,
            transactionDate: date(2026, 5, 14),
            workspace: workspace,
            card: appleCard,
            category: dining
        )
        let starbucks = VariableExpense(
            descriptionText: "Starbucks Coffee",
            amount: 8,
            transactionDate: date(2026, 5, 13),
            workspace: workspace,
            card: backupCard,
            category: dining
        )
        let olderStarbucks = VariableExpense(
            descriptionText: "Starbucks Coffee",
            amount: 6,
            transactionDate: date(2026, 4, 13),
            workspace: workspace,
            card: backupCard,
            category: dining
        )
        let groceryRefund = VariableExpense(
            descriptionText: "Grocery Refund",
            amount: 20,
            kindRaw: VariableExpenseKind.credit.rawValue,
            transactionDate: date(2026, 5, 15),
            workspace: workspace,
            card: appleCard,
            category: groceries
        )
        let adjustment = VariableExpense(
            descriptionText: "Statement Adjustment",
            amount: 15,
            kindRaw: VariableExpenseKind.adjustment.rawValue,
            transactionDate: date(2026, 5, 16),
            workspace: workspace,
            card: appleCard,
            category: nil
        )
        let aprilGroceries = VariableExpense(
            descriptionText: "April Market",
            amount: 40,
            transactionDate: date(2026, 4, 10),
            workspace: workspace,
            card: appleCard,
            category: groceries
        )
        let otherWorkspaceGroceries = VariableExpense(
            descriptionText: "Work Whole Foods",
            amount: 999,
            transactionDate: date(2026, 5, 10),
            workspace: otherWorkspace,
            card: otherAppleCard,
            category: otherGroceries
        )
        let allocation = ExpenseAllocation(
            allocatedAmount: 30,
            preservesGrossAmount: true,
            createdAt: date(2026, 5, 14),
            updatedAt: date(2026, 5, 14),
            workspace: workspace,
            account: sharedAccount,
            expense: diningExpense
        )
        let settlement = AllocationSettlement(
            date: date(2026, 5, 20),
            note: "Roommate paid back",
            amount: -20,
            workspace: workspace,
            account: sharedAccount,
            expense: diningExpense
        )

        context.insert(rent)
        context.insert(groceriesPlan)
        context.insert(phonePlan)
        context.insert(wholeFoods)
        context.insert(appleStore)
        context.insert(appleWatch)
        context.insert(diningExpense)
        context.insert(starbucks)
        context.insert(olderStarbucks)
        context.insert(groceryRefund)
        context.insert(adjustment)
        context.insert(aprilGroceries)
        context.insert(otherWorkspaceGroceries)
        context.insert(allocation)
        context.insert(settlement)
    }

    private static func seedIncome(
        context: ModelContext,
        workspace: Workspace,
        otherWorkspace: Workspace,
        card: Card
    ) {
        let series = IncomeSeries(
            source: "Salary",
            amount: 3_000,
            isPlanned: true,
            frequencyRaw: RecurrenceFrequency.monthly.rawValue,
            interval: 1,
            weeklyWeekday: 6,
            monthlyDayOfMonth: 1,
            monthlyIsLastDay: false,
            yearlyMonth: 1,
            yearlyDayOfMonth: 1,
            startDate: date(2026, 1, 1),
            endDate: date(2026, 12, 31),
            workspace: workspace
        )
        let planned = Income(source: "Salary", amount: 3_000, date: date(2026, 5, 1), isPlanned: true, workspace: workspace, series: series, card: card)
        let actual = Income(source: "Salary", amount: 3_100, date: date(2026, 5, 3), isPlanned: false, workspace: workspace, series: series, card: card)
        let consulting = Income(source: "Consulting", amount: 450, date: date(2026, 4, 20), isPlanned: false, workspace: workspace)
        let otherIncome = Income(source: "Work Retainer", amount: 9_999, date: date(2026, 5, 3), isPlanned: false, workspace: otherWorkspace)
        context.insert(series)
        context.insert(planned)
        context.insert(actual)
        context.insert(consulting)
        context.insert(otherIncome)
    }

    private static func seedSavings(
        context: ModelContext,
        workspace: Workspace,
        otherWorkspace: Workspace,
        account: SavingsAccount
    ) {
        let manual = SavingsLedgerEntry(
            date: date(2026, 5, 6),
            amount: 250,
            note: "Manual savings transfer",
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
            workspace: workspace,
            account: account
        )
        let close = SavingsLedgerEntry(
            date: date(2026, 4, 30),
            amount: 100,
            note: "April close",
            kindRaw: SavingsLedgerEntryKind.periodClose.rawValue,
            periodStartDate: date(2026, 4, 1),
            periodEndDate: date(2026, 4, 30),
            workspace: workspace,
            account: account
        )
        let otherSavings = SavingsAccount(name: "Work Reserve", total: 9_999, workspace: otherWorkspace)
        let otherSavingsEntry = SavingsLedgerEntry(
            date: date(2026, 5, 6),
            amount: 9_999,
            note: "Work savings transfer",
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
            workspace: otherWorkspace,
            account: otherSavings
        )
        let otherPreset = Preset(title: "Office Rent", plannedAmount: 9_999, workspace: otherWorkspace)
        let otherPlanned = PlannedExpense(
            title: "Office Rent",
            plannedAmount: 9_999,
            expenseDate: date(2026, 5, 5),
            workspace: otherWorkspace
        )
        let otherShared = AllocationAccount(name: "Work Partner", hexColor: "#111827", workspace: otherWorkspace)
        let otherAllocation = ExpenseAllocation(
            allocatedAmount: 9_999,
            createdAt: date(2026, 5, 5),
            updatedAt: date(2026, 5, 5),
            workspace: otherWorkspace,
            account: otherShared
        )
        context.insert(manual)
        context.insert(close)
        context.insert(otherSavings)
        context.insert(otherSavingsEntry)
        context.insert(otherPreset)
        context.insert(otherPlanned)
        context.insert(otherShared)
        context.insert(otherAllocation)
    }

    private static func seedMetadata(
        context: ModelContext,
        workspace: Workspace,
        groceries: Offshore.Category
    ) {
        context.insert(AssistantAliasRule(aliasKey: "food", targetValue: "Groceries", entityType: .category, workspace: workspace))
        context.insert(ImportMerchantRule(merchantKey: "whole foods", preferredName: "Whole Foods", preferredCategory: groceries, workspace: workspace))
    }
}
