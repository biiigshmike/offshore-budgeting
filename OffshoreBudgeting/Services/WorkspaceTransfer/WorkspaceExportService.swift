import Foundation
import SwiftData

@MainActor
struct WorkspaceExportService {
    func exportArchive(
        for workspace: Workspace,
        sections: Set<WorkspaceTransferSection>,
        modelContext: ModelContext,
        now: Date = .now
    ) throws -> WorkspaceArchive {
        let orderedSections = WorkspaceTransferSection.allCases.filter { sections.contains($0) }
        let workspaceID = workspace.id

        let budgets = sections.contains(.budgets) ? try fetchBudgets(workspaceID: workspaceID, modelContext: modelContext) : []
        let cards = sections.contains(.cards) ? try fetchCards(workspaceID: workspaceID, modelContext: modelContext) : []
        let categories = sections.contains(.categories) ? try fetchCategories(workspaceID: workspaceID, modelContext: modelContext) : []
        let presets = sections.contains(.presets) ? try fetchPresets(workspaceID: workspaceID, modelContext: modelContext) : []
        let plannedExpenses = sections.contains(.expenseHistory) ? try fetchPlannedExpenses(workspaceID: workspaceID, modelContext: modelContext) : []
        let variableExpenses = sections.contains(.expenseHistory) ? try fetchVariableExpenses(workspaceID: workspaceID, modelContext: modelContext) : []
        let allocationAccounts = sections.contains(.reconciliations) ? try fetchAllocationAccounts(workspaceID: workspaceID, modelContext: modelContext) : []
        let expenseAllocations = sections.contains(.reconciliations) ? try fetchExpenseAllocations(workspaceID: workspaceID, modelContext: modelContext) : []
        let allocationSettlements = sections.contains(.reconciliations) ? try fetchAllocationSettlements(workspaceID: workspaceID, modelContext: modelContext) : []
        let savingsAccounts = sections.contains(.savings) ? try fetchSavingsAccounts(workspaceID: workspaceID, modelContext: modelContext) : []
        let savingsLedgerEntries = sections.contains(.savings) ? try fetchSavingsLedgerEntries(workspaceID: workspaceID, modelContext: modelContext) : []
        let importMerchantRules = sections.contains(.importRules) ? try fetchImportMerchantRules(workspaceID: workspaceID, modelContext: modelContext) : []
        let assistantAliasRules = sections.contains(.marinaAliases) ? try fetchAssistantAliasRules(workspaceID: workspaceID, modelContext: modelContext) : []
        let incomeSeries = sections.contains(.incomes) ? try fetchIncomeSeries(workspaceID: workspaceID, modelContext: modelContext) : []
        let incomes = sections.contains(.incomes) ? try fetchIncomes(workspaceID: workspaceID, modelContext: modelContext) : []

        let budgetCardLinks = sections.contains(.budgets) ? try fetchBudgetCardLinks(workspaceID: workspaceID, modelContext: modelContext) : []
        let budgetPresetLinks = sections.contains(.budgets) || sections.contains(.presets) ? try fetchBudgetPresetLinks(workspaceID: workspaceID, modelContext: modelContext) : []
        let budgetCategoryLimits = sections.contains(.budgets) ? try fetchBudgetCategoryLimits(workspaceID: workspaceID, modelContext: modelContext) : []

        return WorkspaceArchive(
            exportedAt: now,
            sourceWorkspaceID: workspaceID,
            selectedSections: orderedSections,
            workspace: WorkspacePayload(
                id: workspace.id,
                name: workspace.name,
                hexColor: workspace.hexColor
            ),
            budgets: budgets.map {
                BudgetPayload(
                    id: $0.id,
                    name: $0.name,
                    startDate: $0.startDate,
                    endDate: $0.endDate
                )
            },
            budgetCardLinks: budgetCardLinks.map {
                BudgetCardLinkPayload(
                    id: $0.id,
                    budgetID: $0.budget?.id,
                    cardID: $0.card?.id
                )
            },
            budgetPresetLinks: budgetPresetLinks.map {
                BudgetPresetLinkPayload(
                    id: $0.id,
                    budgetID: $0.budget?.id,
                    presetID: $0.preset?.id
                )
            },
            budgetCategoryLimits: budgetCategoryLimits.map {
                BudgetCategoryLimitPayload(
                    id: $0.id,
                    minAmount: $0.minAmount,
                    maxAmount: $0.maxAmount,
                    budgetID: $0.budget?.id,
                    categoryID: $0.category?.id
                )
            },
            cards: cards.map {
                CardPayload(
                    id: $0.id,
                    name: $0.name,
                    theme: $0.theme,
                    effect: $0.effect
                )
            },
            categories: categories.map {
                CategoryPayload(
                    id: $0.id,
                    name: $0.name,
                    hexColor: $0.hexColor,
                    isArchived: $0.isArchived,
                    archivedAt: $0.archivedAt
                )
            },
            presets: presets.map {
                PresetPayload(
                    id: $0.id,
                    title: $0.title,
                    plannedAmount: $0.plannedAmount,
                    isArchived: $0.isArchived,
                    archivedAt: $0.archivedAt,
                    frequencyRaw: $0.frequencyRaw,
                    interval: $0.interval,
                    weeklyWeekday: $0.weeklyWeekday,
                    monthlyDayOfMonth: $0.monthlyDayOfMonth,
                    monthlyIsLastDay: $0.monthlyIsLastDay,
                    yearlyMonth: $0.yearlyMonth,
                    yearlyDayOfMonth: $0.yearlyDayOfMonth,
                    defaultCardID: $0.defaultCard?.id,
                    defaultCategoryID: $0.defaultCategory?.id
                )
            },
            plannedExpenses: plannedExpenses.map {
                PlannedExpensePayload(
                    id: $0.id,
                    title: $0.title,
                    plannedAmount: $0.plannedAmount,
                    actualAmount: $0.actualAmount,
                    expenseDate: $0.expenseDate,
                    cardID: $0.card?.id,
                    categoryID: $0.category?.id,
                    sourcePresetID: $0.sourcePresetID,
                    sourceBudgetID: $0.sourceBudgetID
                )
            },
            variableExpenses: variableExpenses.map {
                VariableExpensePayload(
                    id: $0.id,
                    descriptionText: $0.descriptionText,
                    amount: $0.amount,
                    kindRaw: $0.kindRaw,
                    transactionDate: $0.transactionDate,
                    cardID: $0.card?.id,
                    categoryID: $0.category?.id
                )
            },
            allocationAccounts: allocationAccounts.map {
                AllocationAccountPayload(
                    id: $0.id,
                    name: $0.name,
                    hexColor: $0.hexColor,
                    isArchived: $0.isArchived,
                    archivedAt: $0.archivedAt
                )
            },
            expenseAllocations: expenseAllocations.map {
                ExpenseAllocationPayload(
                    id: $0.id,
                    allocatedAmount: $0.allocatedAmount,
                    preservesGrossAmount: $0.preservesGrossAmount,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    accountID: $0.account?.id,
                    expenseID: $0.expense?.id,
                    plannedExpenseID: $0.plannedExpense?.id
                )
            },
            allocationSettlements: allocationSettlements.map {
                AllocationSettlementPayload(
                    id: $0.id,
                    date: $0.date,
                    note: $0.note,
                    amount: $0.amount,
                    accountID: $0.account?.id,
                    expenseID: $0.expense?.id,
                    plannedExpenseID: $0.plannedExpense?.id
                )
            },
            savingsAccounts: savingsAccounts.map {
                SavingsAccountPayload(
                    id: $0.id,
                    name: $0.name,
                    total: $0.total,
                    didBackfillHistory: $0.didBackfillHistory,
                    autoCaptureThroughDate: $0.autoCaptureThroughDate,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            savingsLedgerEntries: savingsLedgerEntries.map {
                SavingsLedgerEntryPayload(
                    id: $0.id,
                    date: $0.date,
                    amount: $0.amount,
                    note: $0.note,
                    kindRaw: $0.kindRaw,
                    linkedAllocationSettlementID: $0.linkedAllocationSettlementID,
                    periodStartDate: $0.periodStartDate,
                    periodEndDate: $0.periodEndDate,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    accountID: $0.account?.id,
                    variableExpenseID: $0.variableExpense?.id,
                    plannedExpenseID: $0.plannedExpense?.id
                )
            },
            importMerchantRules: importMerchantRules.map {
                ImportMerchantRulePayload(
                    id: $0.id,
                    merchantKey: $0.merchantKey,
                    preferredName: $0.preferredName,
                    preferredCategoryID: $0.preferredCategory?.id,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            assistantAliasRules: assistantAliasRules.map {
                AssistantAliasRulePayload(
                    id: $0.id,
                    aliasKey: $0.aliasKey,
                    targetValue: $0.targetValue,
                    entityTypeRaw: $0.entityTypeRaw,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            incomeSeries: incomeSeries.map {
                IncomeSeriesPayload(
                    id: $0.id,
                    source: $0.source,
                    amount: $0.amount,
                    isPlanned: $0.isPlanned,
                    frequencyRaw: $0.frequencyRaw,
                    interval: $0.interval,
                    weeklyWeekday: $0.weeklyWeekday,
                    monthlyDayOfMonth: $0.monthlyDayOfMonth,
                    monthlyIsLastDay: $0.monthlyIsLastDay,
                    yearlyMonth: $0.yearlyMonth,
                    yearlyDayOfMonth: $0.yearlyDayOfMonth,
                    startDate: $0.startDate,
                    endDate: $0.endDate
                )
            },
            incomes: incomes.map {
                IncomePayload(
                    id: $0.id,
                    source: $0.source,
                    amount: $0.amount,
                    date: $0.date,
                    isPlanned: $0.isPlanned,
                    isException: $0.isException,
                    seriesID: $0.series?.id,
                    cardID: $0.card?.id
                )
            }
        )
    }

    private func fetchBudgets(workspaceID: UUID, modelContext: ModelContext) throws -> [Budget] {
        let descriptor = FetchDescriptor<Budget>(
            predicate: #Predicate<Budget> { $0.workspace?.id == workspaceID }
        )
        return try modelContext.fetch(descriptor).sortedByID()
    }

    private func fetchBudgetCardLinks(workspaceID: UUID, modelContext: ModelContext) throws -> [BudgetCardLink] {
        let links = try modelContext.fetch(FetchDescriptor<BudgetCardLink>())
        return links
            .filter { $0.budget?.workspace?.id == workspaceID && $0.card?.workspace?.id == workspaceID }
            .sortedByID()
    }

    private func fetchBudgetPresetLinks(workspaceID: UUID, modelContext: ModelContext) throws -> [BudgetPresetLink] {
        let links = try modelContext.fetch(FetchDescriptor<BudgetPresetLink>())
        return links
            .filter { $0.budget?.workspace?.id == workspaceID && $0.preset?.workspace?.id == workspaceID }
            .sortedByID()
    }

    private func fetchBudgetCategoryLimits(workspaceID: UUID, modelContext: ModelContext) throws -> [BudgetCategoryLimit] {
        let links = try modelContext.fetch(FetchDescriptor<BudgetCategoryLimit>())
        return links
            .filter { $0.budget?.workspace?.id == workspaceID && $0.category?.workspace?.id == workspaceID }
            .sortedByID()
    }

    private func fetchCards(workspaceID: UUID, modelContext: ModelContext) throws -> [Card] {
        let descriptor = FetchDescriptor<Card>(
            predicate: #Predicate<Card> { $0.workspace?.id == workspaceID }
        )
        return try modelContext.fetch(descriptor).sortedByID()
    }

    private func fetchCategories(workspaceID: UUID, modelContext: ModelContext) throws -> [Category] {
        let descriptor = FetchDescriptor<Category>(
            predicate: #Predicate<Category> { $0.workspace?.id == workspaceID }
        )
        return try modelContext.fetch(descriptor).sortedByID()
    }

    private func fetchPresets(workspaceID: UUID, modelContext: ModelContext) throws -> [Preset] {
        let descriptor = FetchDescriptor<Preset>(
            predicate: #Predicate<Preset> { $0.workspace?.id == workspaceID }
        )
        return try modelContext.fetch(descriptor).sortedByID()
    }

    private func fetchPlannedExpenses(workspaceID: UUID, modelContext: ModelContext) throws -> [PlannedExpense] {
        let descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate<PlannedExpense> { $0.workspace?.id == workspaceID }
        )
        return try modelContext.fetch(descriptor).sortedByID()
    }

    private func fetchVariableExpenses(workspaceID: UUID, modelContext: ModelContext) throws -> [VariableExpense] {
        let descriptor = FetchDescriptor<VariableExpense>(
            predicate: #Predicate<VariableExpense> { $0.workspace?.id == workspaceID }
        )
        return try modelContext.fetch(descriptor).sortedByID()
    }

    private func fetchAllocationAccounts(workspaceID: UUID, modelContext: ModelContext) throws -> [AllocationAccount] {
        let descriptor = FetchDescriptor<AllocationAccount>(
            predicate: #Predicate<AllocationAccount> { $0.workspace?.id == workspaceID }
        )
        return try modelContext.fetch(descriptor).sortedByID()
    }

    private func fetchExpenseAllocations(workspaceID: UUID, modelContext: ModelContext) throws -> [ExpenseAllocation] {
        let descriptor = FetchDescriptor<ExpenseAllocation>(
            predicate: #Predicate<ExpenseAllocation> { $0.workspace?.id == workspaceID }
        )
        return try modelContext.fetch(descriptor).sortedByID()
    }

    private func fetchAllocationSettlements(workspaceID: UUID, modelContext: ModelContext) throws -> [AllocationSettlement] {
        let descriptor = FetchDescriptor<AllocationSettlement>(
            predicate: #Predicate<AllocationSettlement> { $0.workspace?.id == workspaceID }
        )
        return try modelContext.fetch(descriptor).sortedByID()
    }

    private func fetchSavingsAccounts(workspaceID: UUID, modelContext: ModelContext) throws -> [SavingsAccount] {
        let descriptor = FetchDescriptor<SavingsAccount>(
            predicate: #Predicate<SavingsAccount> { $0.workspace?.id == workspaceID }
        )
        return try modelContext.fetch(descriptor).sortedByID()
    }

    private func fetchSavingsLedgerEntries(workspaceID: UUID, modelContext: ModelContext) throws -> [SavingsLedgerEntry] {
        let descriptor = FetchDescriptor<SavingsLedgerEntry>(
            predicate: #Predicate<SavingsLedgerEntry> { $0.workspace?.id == workspaceID }
        )
        return try modelContext.fetch(descriptor).sortedByID()
    }

    private func fetchImportMerchantRules(workspaceID: UUID, modelContext: ModelContext) throws -> [ImportMerchantRule] {
        let descriptor = FetchDescriptor<ImportMerchantRule>(
            predicate: #Predicate<ImportMerchantRule> { $0.workspace?.id == workspaceID }
        )
        return try modelContext.fetch(descriptor).sortedByID()
    }

    private func fetchAssistantAliasRules(workspaceID: UUID, modelContext: ModelContext) throws -> [AssistantAliasRule] {
        let descriptor = FetchDescriptor<AssistantAliasRule>(
            predicate: #Predicate<AssistantAliasRule> { $0.workspace?.id == workspaceID }
        )
        return try modelContext.fetch(descriptor).sortedByID()
    }

    private func fetchIncomeSeries(workspaceID: UUID, modelContext: ModelContext) throws -> [IncomeSeries] {
        let descriptor = FetchDescriptor<IncomeSeries>(
            predicate: #Predicate<IncomeSeries> { $0.workspace?.id == workspaceID }
        )
        return try modelContext.fetch(descriptor).sortedByID()
    }

    private func fetchIncomes(workspaceID: UUID, modelContext: ModelContext) throws -> [Income] {
        let descriptor = FetchDescriptor<Income>(
            predicate: #Predicate<Income> { $0.workspace?.id == workspaceID }
        )
        return try modelContext.fetch(descriptor).sortedByID()
    }
}

private extension Array where Element: AnyObject {
    func sortedByID() -> [Element] {
        sorted {
            let lhs = ($0 as? any WorkspaceTransferIdentifiable)?.workspaceTransferID.uuidString ?? ""
            let rhs = ($1 as? any WorkspaceTransferIdentifiable)?.workspaceTransferID.uuidString ?? ""
            return lhs < rhs
        }
    }
}

private protocol WorkspaceTransferIdentifiable {
    var workspaceTransferID: UUID { get }
}

extension Budget: WorkspaceTransferIdentifiable { var workspaceTransferID: UUID { id } }
extension BudgetCardLink: WorkspaceTransferIdentifiable { var workspaceTransferID: UUID { id } }
extension BudgetPresetLink: WorkspaceTransferIdentifiable { var workspaceTransferID: UUID { id } }
extension BudgetCategoryLimit: WorkspaceTransferIdentifiable { var workspaceTransferID: UUID { id } }
extension Card: WorkspaceTransferIdentifiable { var workspaceTransferID: UUID { id } }
extension Category: WorkspaceTransferIdentifiable { var workspaceTransferID: UUID { id } }
extension Preset: WorkspaceTransferIdentifiable { var workspaceTransferID: UUID { id } }
extension PlannedExpense: WorkspaceTransferIdentifiable { var workspaceTransferID: UUID { id } }
extension VariableExpense: WorkspaceTransferIdentifiable { var workspaceTransferID: UUID { id } }
extension AllocationAccount: WorkspaceTransferIdentifiable { var workspaceTransferID: UUID { id } }
extension ExpenseAllocation: WorkspaceTransferIdentifiable { var workspaceTransferID: UUID { id } }
extension AllocationSettlement: WorkspaceTransferIdentifiable { var workspaceTransferID: UUID { id } }
extension SavingsAccount: WorkspaceTransferIdentifiable { var workspaceTransferID: UUID { id } }
extension SavingsLedgerEntry: WorkspaceTransferIdentifiable { var workspaceTransferID: UUID { id } }
extension ImportMerchantRule: WorkspaceTransferIdentifiable { var workspaceTransferID: UUID { id } }
extension AssistantAliasRule: WorkspaceTransferIdentifiable { var workspaceTransferID: UUID { id } }
extension IncomeSeries: WorkspaceTransferIdentifiable { var workspaceTransferID: UUID { id } }
extension Income: WorkspaceTransferIdentifiable { var workspaceTransferID: UUID { id } }
