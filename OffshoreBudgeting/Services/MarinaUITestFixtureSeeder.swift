import Foundation
import SwiftData

#if DEBUG
enum MarinaUITestFixtureSeeder {
    static let workspaceID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    static func makeLocalStoreContainer() throws -> ModelContainer {
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
            IncomeSeries.self,
            Income.self
        ])

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

        let storeURL = appSupport.appendingPathComponent("Local.store")
        let configuration = ModelConfiguration(
            "Local",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )

        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func seed(in context: ModelContext) {
        let calendar = Calendar(identifier: .gregorian)
        let monthStart = date(2026, 5, 1, calendar: calendar)
        let monthEnd = date(2026, 5, 31, calendar: calendar)

        let workspace = Workspace(
            id: workspaceID,
            name: "Marina Harness",
            hexColor: "#2563EB"
        )
        context.insert(workspace)

        let mayBudget = Budget(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "May 2026",
            startDate: monthStart,
            endDate: monthEnd,
            workspace: workspace
        )
        context.insert(mayBudget)

        let checkingCard = Card(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            name: "Harbor Checking",
            theme: "ruby",
            effect: "plastic",
            workspace: workspace
        )
        let appleCard = Card(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333334")!,
            name: "Apple Card",
            theme: "periwinkle",
            effect: "glass",
            workspace: workspace
        )
        let backupCard = Card(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333335")!,
            name: "Backup Card",
            theme: "emerald",
            effect: "matte",
            workspace: workspace
        )
        context.insert(checkingCard)
        context.insert(appleCard)
        context.insert(backupCard)

        context.insert(BudgetCardLink(budget: mayBudget, card: checkingCard))
        context.insert(BudgetCardLink(budget: mayBudget, card: appleCard))
        context.insert(BudgetCardLink(budget: mayBudget, card: backupCard))

        let groceries = Category(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            name: "Groceries",
            hexColor: "#16A34A",
            workspace: workspace
        )
        let rent = Category(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444445")!,
            name: "Rent",
            hexColor: "#7C3AED",
            workspace: workspace
        )
        let utilities = Category(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444446")!,
            name: "Utilities",
            hexColor: "#F97316",
            workspace: workspace
        )
        let dining = Category(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444447")!,
            name: "Dining",
            hexColor: "#EF4444",
            workspace: workspace
        )
        let shopping = Category(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444448")!,
            name: "Apple",
            hexColor: "#64748B",
            workspace: workspace
        )
        context.insert(groceries)
        context.insert(rent)
        context.insert(utilities)
        context.insert(dining)
        context.insert(shopping)

        context.insert(BudgetCategoryLimit(minAmount: 250, maxAmount: 650, budget: mayBudget, category: groceries))
        context.insert(BudgetCategoryLimit(minAmount: nil, maxAmount: 2300, budget: mayBudget, category: rent))
        context.insert(BudgetCategoryLimit(minAmount: nil, maxAmount: 300, budget: mayBudget, category: dining))
        context.insert(BudgetCategoryLimit(minAmount: nil, maxAmount: 500, budget: mayBudget, category: shopping))

        let rentPreset = Preset(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            title: "Rent",
            plannedAmount: 2100,
            frequencyRaw: RecurrenceFrequency.monthly.rawValue,
            interval: 1,
            weeklyWeekday: 6,
            monthlyDayOfMonth: 1,
            monthlyIsLastDay: false,
            yearlyMonth: 5,
            yearlyDayOfMonth: 1,
            workspace: workspace,
            defaultCard: checkingCard,
            defaultCategory: rent
        )
        let utilityPreset = Preset(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555556")!,
            title: "Electric Bill",
            plannedAmount: 145,
            frequencyRaw: RecurrenceFrequency.monthly.rawValue,
            interval: 1,
            weeklyWeekday: 6,
            monthlyDayOfMonth: 20,
            monthlyIsLastDay: false,
            yearlyMonth: 5,
            yearlyDayOfMonth: 20,
            workspace: workspace,
            defaultCard: appleCard,
            defaultCategory: utilities
        )
        context.insert(rentPreset)
        context.insert(utilityPreset)
        context.insert(BudgetPresetLink(budget: mayBudget, preset: rentPreset))
        context.insert(BudgetPresetLink(budget: mayBudget, preset: utilityPreset))

        let plannedRent = PlannedExpense(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            title: "Rent",
            plannedAmount: 2100,
            actualAmount: 2100,
            expenseDate: date(2026, 5, 1, calendar: calendar),
            workspace: workspace,
            card: checkingCard,
            category: rent,
            sourcePresetID: rentPreset.id,
            sourceBudgetID: mayBudget.id
        )
        let plannedElectric = PlannedExpense(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666667")!,
            title: "Electric Bill",
            plannedAmount: 145,
            actualAmount: 0,
            expenseDate: date(2026, 5, 20, calendar: calendar),
            workspace: workspace,
            card: appleCard,
            category: utilities,
            sourcePresetID: utilityPreset.id,
            sourceBudgetID: mayBudget.id
        )
        context.insert(plannedRent)
        context.insert(plannedElectric)

        let marketRun = VariableExpense(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            descriptionText: "Whole Foods",
            amount: 84.25,
            kindRaw: VariableExpenseKind.debit.rawValue,
            transactionDate: date(2026, 5, 6, calendar: calendar),
            workspace: workspace,
            card: appleCard,
            category: groceries
        )
        let groceryRefund = VariableExpense(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777778")!,
            descriptionText: "Whole Foods refund",
            amount: 12.50,
            kindRaw: VariableExpenseKind.credit.rawValue,
            transactionDate: date(2026, 5, 8, calendar: calendar),
            workspace: workspace,
            card: appleCard,
            category: groceries
        )
        let balanceAdjustment = VariableExpense(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777779")!,
            descriptionText: "Opening card balance adjustment",
            amount: 25,
            kindRaw: VariableExpenseKind.adjustment.rawValue,
            transactionDate: date(2026, 5, 2, calendar: calendar),
            workspace: workspace,
            card: checkingCard,
            category: nil
        )
        let starbucks = VariableExpense(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777780")!,
            descriptionText: "Starbucks Coffee",
            amount: 8.75,
            kindRaw: VariableExpenseKind.debit.rawValue,
            transactionDate: date(2026, 5, 13, calendar: calendar),
            workspace: workspace,
            card: backupCard,
            category: dining
        )
        let olderStarbucks = VariableExpense(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777781")!,
            descriptionText: "Starbucks Coffee",
            amount: 6.50,
            kindRaw: VariableExpenseKind.debit.rawValue,
            transactionDate: date(2026, 4, 13, calendar: calendar),
            workspace: workspace,
            card: backupCard,
            category: dining
        )
        let appleStore = VariableExpense(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777782")!,
            descriptionText: "Apple Store",
            amount: 129,
            kindRaw: VariableExpenseKind.debit.rawValue,
            transactionDate: date(2026, 5, 11, calendar: calendar),
            workspace: workspace,
            card: backupCard,
            category: shopping
        )
        let appleWatch = VariableExpense(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777783")!,
            descriptionText: "Apple Watch",
            amount: 35,
            kindRaw: VariableExpenseKind.debit.rawValue,
            transactionDate: date(2026, 5, 12, calendar: calendar),
            workspace: workspace,
            card: appleCard,
            category: shopping
        )
        context.insert(marketRun)
        context.insert(groceryRefund)
        context.insert(balanceAdjustment)
        context.insert(starbucks)
        context.insert(olderStarbucks)
        context.insert(appleStore)
        context.insert(appleWatch)

        let roommate = AllocationAccount(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            name: "Roommate",
            hexColor: "#0EA5E9",
            workspace: workspace
        )
        context.insert(roommate)

        let grocerySplit = ExpenseAllocation(
            id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
            allocatedAmount: 30,
            preservesGrossAmount: true,
            createdAt: date(2026, 5, 6, calendar: calendar),
            updatedAt: date(2026, 5, 6, calendar: calendar),
            workspace: workspace,
            account: roommate,
            expense: marketRun
        )
        context.insert(grocerySplit)

        let rentSettlement = AllocationSettlement(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            date: date(2026, 5, 3, calendar: calendar),
            note: "Roommate rent reimbursement",
            amount: -1050,
            workspace: workspace,
            account: roommate,
            plannedExpense: plannedRent
        )
        let grocerySettlement = AllocationSettlement(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAB")!,
            date: date(2026, 5, 12, calendar: calendar),
            note: "Roommate grocery settlement",
            amount: -30,
            workspace: workspace,
            account: roommate,
            expense: marketRun
        )
        context.insert(rentSettlement)
        context.insert(grocerySettlement)

        let paycheckSeries = IncomeSeries(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            source: "Paycheck",
            amount: 3200,
            isPlanned: true,
            frequencyRaw: RecurrenceFrequency.monthly.rawValue,
            interval: 1,
            weeklyWeekday: 6,
            monthlyDayOfMonth: 15,
            monthlyIsLastDay: false,
            yearlyMonth: 5,
            yearlyDayOfMonth: 15,
            startDate: monthStart,
            endDate: monthEnd,
            workspace: workspace
        )
        context.insert(paycheckSeries)

        context.insert(
            Income(
                id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
                source: "Paycheck",
                amount: 3200,
                date: date(2026, 5, 15, calendar: calendar),
                isPlanned: false,
                workspace: workspace,
                series: paycheckSeries,
                card: checkingCard
            )
        )
        context.insert(
            Income(
                id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCD")!,
                source: "Freelance",
                amount: 600,
                date: date(2026, 5, 24, calendar: calendar),
                isPlanned: true,
                workspace: workspace,
                card: checkingCard
            )
        )

        let savings = SavingsAccount(
            id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            name: "Emergency Fund",
            total: 950,
            didBackfillHistory: true,
            autoCaptureThroughDate: monthEnd,
            createdAt: monthStart,
            updatedAt: monthEnd,
            workspace: workspace
        )
        context.insert(savings)

        context.insert(
            SavingsLedgerEntry(
                id: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
                date: date(2026, 5, 15, calendar: calendar),
                amount: 1000,
                note: "May savings transfer",
                kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
                createdAt: date(2026, 5, 15, calendar: calendar),
                updatedAt: date(2026, 5, 15, calendar: calendar),
                workspace: workspace,
                account: savings
            )
        )
        context.insert(
            SavingsLedgerEntry(
                id: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEF")!,
                date: date(2026, 5, 20, calendar: calendar),
                amount: -50,
                note: "Electric bill savings offset",
                kindRaw: SavingsLedgerEntryKind.expenseOffset.rawValue,
                createdAt: date(2026, 5, 20, calendar: calendar),
                updatedAt: date(2026, 5, 20, calendar: calendar),
                workspace: workspace,
                account: savings,
                plannedExpense: plannedElectric
            )
        )

        context.insert(
            ImportMerchantRule(
                id: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!,
                merchantKey: "whole foods",
                preferredName: "Whole Foods",
                preferredCategory: groceries,
                workspace: workspace,
                createdAt: monthStart,
                updatedAt: monthStart
            )
        )
        context.insert(
            ImportMerchantRule(
                id: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFE")!,
                merchantKey: "starbucks coffee",
                preferredName: "Starbucks",
                preferredCategory: dining,
                workspace: workspace,
                createdAt: monthStart,
                updatedAt: monthStart
            )
        )
        context.insert(
            AssistantAliasRule(
                id: UUID(uuidString: "ABABABAB-ABAB-ABAB-ABAB-ABABABABABAB")!,
                aliasKey: "apple",
                targetValue: "Apple Card",
                entityType: .card,
                workspace: workspace,
                createdAt: monthStart,
                updatedAt: monthStart
            )
        )
        context.insert(
            AssistantAliasRule(
                id: UUID(uuidString: "ABABABAB-ABAB-ABAB-ABAB-ABABABABABAC")!,
                aliasKey: "food",
                targetValue: "Groceries",
                entityType: .category,
                workspace: workspace,
                createdAt: monthStart,
                updatedAt: monthStart
            )
        )

        let otherWorkspace = Workspace(
            id: UUID(uuidString: "12121212-1212-1212-1212-121212121212")!,
            name: "Decoy Workspace",
            hexColor: "#111827"
        )
        let decoyCard = Card(name: "Apple Card", workspace: otherWorkspace)
        let decoyCategory = Category(name: "Groceries", hexColor: "#22C55E", workspace: otherWorkspace)
        let decoyExpense = VariableExpense(
            descriptionText: "Work Whole Foods",
            amount: 999,
            transactionDate: date(2026, 5, 10, calendar: calendar),
            workspace: otherWorkspace,
            card: decoyCard,
            category: decoyCategory
        )
        context.insert(otherWorkspace)
        context.insert(decoyCard)
        context.insert(decoyCategory)
        context.insert(decoyExpense)
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }
}
#endif
