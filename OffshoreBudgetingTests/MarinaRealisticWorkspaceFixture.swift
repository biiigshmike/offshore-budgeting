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
        let otherWorkspace = Workspace(name: "Business", hexColor: "#111827")

        let groceries = Offshore.Category(name: "Groceries", hexColor: "#22C55E", workspace: workspace)
        let dining = Offshore.Category(name: "Dining", hexColor: "#F97316", workspace: workspace)
        let travel = Offshore.Category(name: "Travel", hexColor: "#6366F1", workspace: workspace)
        let utilities = Offshore.Category(name: "Utilities", hexColor: "#F59E0B", workspace: workspace)
        let cannabis = Offshore.Category(name: "Cannabis", hexColor: "#225522", workspace: workspace)
        let appleCard = Card(name: "Apple", workspace: workspace)
        let backupCard = Card(name: "Backup Card", workspace: workspace)
        let amexCard = Card(name: "Amex Platinum", workspace: workspace)
        let visaCard = Card(name: "Visa - Blue", workspace: workspace)
        let cashCard = Card(name: "Cash", workspace: workspace)

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
        context.insert(utilities)
        context.insert(cannabis)
        context.insert(appleCard)
        context.insert(backupCard)
        context.insert(amexCard)
        context.insert(visaCard)
        context.insert(cashCard)
        context.insert(otherGroceries)
        context.insert(otherAppleCard)
        context.insert(activeBudget)
        context.insert(groceryBudgetLimit)
        context.insert(Budget(name: "Travel 2026", startDate: date(2026, 6, 1), endDate: date(2026, 12, 31), workspace: workspace))
        context.insert(Budget(name: "Home", startDate: date(2026, 6, 1), endDate: date(2026, 6, 30), workspace: workspace))
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
            utilities: utilities,
            cannabis: cannabis,
            appleCard: appleCard,
            backupCard: backupCard,
            amexCard: amexCard,
            visaCard: visaCard,
            cashCard: cashCard,
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
        utilities: Offshore.Category,
        cannabis: Offshore.Category,
        appleCard: Card,
        backupCard: Card,
        amexCard: Card,
        visaCard: Card,
        cashCard: Card,
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
        let diningPlan = PlannedExpense(
            title: "Dining Plan",
            plannedAmount: 100,
            actualAmount: 140,
            expenseDate: date(2026, 3, 9),
            workspace: workspace,
            card: appleCard,
            category: dining,
            sourceBudgetID: budget.id
        )
        let homePlan = PlannedExpense(
            title: "Home Insurance",
            plannedAmount: 220,
            expenseDate: date(2026, 6, 25),
            workspace: workspace,
            card: visaCard,
            category: utilities,
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
        let semanticWorkspaceExpenses: [VariableExpense] = [
            VariableExpense(descriptionText: "March Market", amount: 120, transactionDate: date(2026, 3, 8), workspace: workspace, card: amexCard, category: groceries),
            VariableExpense(descriptionText: "March Market", amount: 95, transactionDate: date(2025, 3, 8), workspace: workspace, card: visaCard, category: groceries),
            VariableExpense(descriptionText: "Amazon Marketplace", amount: 42, transactionDate: date(2026, 5, 2), workspace: workspace, card: visaCard, category: travel),
            VariableExpense(descriptionText: "Amazon Fresh", amount: 58, transactionDate: date(2026, 4, 18), workspace: workspace, card: visaCard, category: groceries),
            VariableExpense(descriptionText: "Amazon Marketplace refund", amount: 12, kindRaw: VariableExpenseKind.credit.rawValue, transactionDate: date(2026, 4, 20), workspace: workspace, card: visaCard, category: travel),
            VariableExpense(descriptionText: "Cash refund", amount: 5, kindRaw: VariableExpenseKind.credit.rawValue, transactionDate: date(2026, 5, 4), workspace: workspace, card: cashCard, category: dining),
            VariableExpense(descriptionText: "February Appliance", amount: 275, transactionDate: date(2026, 2, 14), workspace: workspace, card: amexCard, category: utilities),
            VariableExpense(descriptionText: "Litter Robot", amount: 499, transactionDate: date(2025, 11, 2), workspace: workspace, card: visaCard, category: travel),
            VariableExpense(descriptionText: "Reconcile utility split", amount: 30, transactionDate: date(2026, 5, 5), workspace: workspace, card: cashCard, category: utilities),
            VariableExpense(descriptionText: "Utility Co", amount: 110, transactionDate: date(2026, 4, 7), workspace: workspace, card: visaCard, category: utilities),
            VariableExpense(descriptionText: "Utility Co", amount: 125, transactionDate: date(2026, 5, 7), workspace: workspace, card: visaCard, category: utilities),
            VariableExpense(descriptionText: "Amex Q1 Market", amount: 66, transactionDate: date(2026, 1, 12), workspace: workspace, card: amexCard, category: groceries),
            VariableExpense(descriptionText: "Amex Q1 Dining", amount: 44, transactionDate: date(2026, 2, 20), workspace: workspace, card: amexCard, category: dining),
            VariableExpense(descriptionText: "Visa 2025 Travel", amount: 150, transactionDate: date(2025, 7, 1), workspace: workspace, card: visaCard, category: travel),
            VariableExpense(descriptionText: "Cash 2025 Market", amount: 60, transactionDate: date(2025, 7, 2), workspace: workspace, card: cashCard, category: groceries),
            VariableExpense(descriptionText: "No Category Snack", amount: 11, transactionDate: date(2026, 5, 15), workspace: workspace, card: cashCard, category: nil),
            VariableExpense(descriptionText: "Last Weekend Cafe", amount: 22, transactionDate: date(2026, 5, 9), workspace: workspace, card: cashCard, category: dining),
            VariableExpense(descriptionText: "Q2 Current Books", amount: 35, transactionDate: date(2026, 4, 12), workspace: workspace, card: visaCard, category: travel),
            VariableExpense(descriptionText: "Q2 Prior Books", amount: 25, transactionDate: date(2025, 4, 12), workspace: workspace, card: visaCard, category: travel),
            VariableExpense(descriptionText: "NUG Dispensary", amount: 64, transactionDate: date(2026, 5, 12), workspace: workspace, card: cashCard, category: cannabis),
            VariableExpense(descriptionText: "NUG Edibles", amount: 36, transactionDate: date(2026, 4, 28), workspace: workspace, card: cashCard, category: cannabis)
        ]
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
        context.insert(diningPlan)
        context.insert(homePlan)
        context.insert(wholeFoods)
        context.insert(appleStore)
        context.insert(appleWatch)
        context.insert(diningExpense)
        context.insert(starbucks)
        context.insert(olderStarbucks)
        context.insert(groceryRefund)
        context.insert(adjustment)
        context.insert(aprilGroceries)
        semanticWorkspaceExpenses.forEach { context.insert($0) }
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
        let acmeJan = Income(source: "Acme Dental", amount: 700, date: date(2026, 1, 15), isPlanned: false, workspace: workspace)
        let acmeFeb = Income(source: "Acme Dental", amount: 800, date: date(2026, 2, 15), isPlanned: false, workspace: workspace)
        let acmeMar = Income(source: "Acme Dental", amount: 900, date: date(2026, 3, 15), isPlanned: false, workspace: workspace)
        let marchIncome2025 = Income(source: "Acme Dental", amount: 650, date: date(2025, 3, 15), isPlanned: false, workspace: workspace)
        let otherIncome = Income(source: "Work Retainer", amount: 9_999, date: date(2026, 5, 3), isPlanned: false, workspace: otherWorkspace)
        context.insert(series)
        context.insert(planned)
        context.insert(actual)
        context.insert(consulting)
        context.insert(acmeJan)
        context.insert(acmeFeb)
        context.insert(acmeMar)
        context.insert(marchIncome2025)
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
        let aprilLedger = SavingsLedgerEntry(
            date: date(2026, 4, 10),
            amount: 75,
            note: "April savings seed",
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
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
        context.insert(aprilLedger)
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
