import Foundation
import SwiftData

struct WorkspaceImportPreview: Identifiable, Equatable {
    var id: String { "\(sourceWorkspaceID.uuidString)-\(exportedAt.timeIntervalSinceReferenceDate)" }

    var workspaceName: String
    var exportedAt: Date
    var sourceWorkspaceID: UUID
    var selectedSections: [WorkspaceTransferSection]
    var counts: WorkspaceArchivePayloadCounts
}

@MainActor
struct WorkspaceImportService {
    enum ImportError: LocalizedError, Equatable {
        case invalidArchive
        case unsupportedSchemaVersion(Int)
        case duplicateRecordID

        var errorDescription: String? {
            switch self {
            case .invalidArchive:
                "This is not a valid Offshore workspace export."
            case .unsupportedSchemaVersion(let version):
                "This workspace export uses schema version \(version), which this app cannot import."
            case .duplicateRecordID:
                "This workspace export contains duplicate record IDs."
            }
        }
    }

    func preview(for archive: WorkspaceArchive) throws -> WorkspaceImportPreview {
        try validate(archive)
        return WorkspaceImportPreview(
            workspaceName: archive.workspace.name,
            exportedAt: archive.exportedAt,
            sourceWorkspaceID: archive.sourceWorkspaceID,
            selectedSections: archive.selectedSections,
            counts: WorkspaceArchivePayloadCounts(archive: archive)
        )
    }

    @discardableResult
    func importArchive(
        _ archive: WorkspaceArchive,
        existingWorkspaces: [Workspace],
        modelContext: ModelContext
    ) throws -> Workspace {
        try validate(archive)

        let cardIDMap = try makeIDMap(archive.cards.map(\.id))
        let categoryIDMap = try makeIDMap(archive.categories.map(\.id))
        let budgetIDMap = try makeIDMap(archive.budgets.map(\.id))
        let presetIDMap = try makeIDMap(archive.presets.map(\.id))
        let plannedExpenseIDMap = try makeIDMap(archive.plannedExpenses.map(\.id))
        let variableExpenseIDMap = try makeIDMap(archive.variableExpenses.map(\.id))
        let allocationAccountIDMap = try makeIDMap(archive.allocationAccounts.map(\.id))
        let allocationSettlementIDMap = try makeIDMap(archive.allocationSettlements.map(\.id))
        let savingsAccountIDMap = try makeIDMap(archive.savingsAccounts.map(\.id))
        let incomeSeriesIDMap = try makeIDMap(archive.incomeSeries.map(\.id))

        let importedWorkspace = Workspace(
            id: UUID(),
            name: uniqueWorkspaceName(
                baseName: archive.workspace.name,
                existingWorkspaces: existingWorkspaces
            ),
            hexColor: normalizedHexColor(archive.workspace.hexColor)
        )
        modelContext.insert(importedWorkspace)

        do {
            var cardsByOldID: [UUID: Card] = [:]
            for payload in archive.cards {
                guard let newID = cardIDMap[payload.id] else { continue }
                let card = Card(
                    id: newID,
                    name: payload.name,
                    theme: payload.theme,
                    effect: payload.effect,
                    workspace: importedWorkspace
                )
                modelContext.insert(card)
                cardsByOldID[payload.id] = card
            }

            var categoriesByOldID: [UUID: Category] = [:]
            for payload in archive.categories {
                guard let newID = categoryIDMap[payload.id] else { continue }
                let category = Category(
                    id: newID,
                    name: payload.name,
                    hexColor: normalizedHexColor(payload.hexColor),
                    workspace: importedWorkspace,
                    isArchived: payload.isArchived,
                    archivedAt: payload.archivedAt
                )
                modelContext.insert(category)
                categoriesByOldID[payload.id] = category
            }

            var budgetsByOldID: [UUID: Budget] = [:]
            for payload in archive.budgets {
                guard let newID = budgetIDMap[payload.id] else { continue }
                let budget = Budget(
                    id: newID,
                    name: payload.name,
                    startDate: payload.startDate,
                    endDate: payload.endDate,
                    workspace: importedWorkspace
                )
                modelContext.insert(budget)
                budgetsByOldID[payload.id] = budget
            }

            var presetsByOldID: [UUID: Preset] = [:]
            for payload in archive.presets {
                guard let newID = presetIDMap[payload.id] else { continue }
                let preset = Preset(
                    id: newID,
                    title: payload.title,
                    plannedAmount: payload.plannedAmount,
                    frequencyRaw: payload.frequencyRaw,
                    interval: payload.interval,
                    weeklyWeekday: payload.weeklyWeekday,
                    monthlyDayOfMonth: payload.monthlyDayOfMonth,
                    monthlyIsLastDay: payload.monthlyIsLastDay,
                    yearlyMonth: payload.yearlyMonth,
                    yearlyDayOfMonth: payload.yearlyDayOfMonth,
                    workspace: importedWorkspace,
                    defaultCard: object(payload.defaultCardID, in: cardsByOldID),
                    defaultCategory: object(payload.defaultCategoryID, in: categoriesByOldID),
                    isArchived: payload.isArchived,
                    archivedAt: payload.archivedAt
                )
                modelContext.insert(preset)
                presetsByOldID[payload.id] = preset
            }

            var incomeSeriesByOldID: [UUID: IncomeSeries] = [:]
            for payload in archive.incomeSeries {
                guard let newID = incomeSeriesIDMap[payload.id] else { continue }
                let series = IncomeSeries(
                    id: newID,
                    source: payload.source,
                    amount: payload.amount,
                    isPlanned: payload.isPlanned,
                    frequencyRaw: payload.frequencyRaw,
                    interval: payload.interval,
                    weeklyWeekday: payload.weeklyWeekday,
                    monthlyDayOfMonth: payload.monthlyDayOfMonth,
                    monthlyIsLastDay: payload.monthlyIsLastDay,
                    yearlyMonth: payload.yearlyMonth,
                    yearlyDayOfMonth: payload.yearlyDayOfMonth,
                    startDate: payload.startDate,
                    endDate: payload.endDate,
                    workspace: importedWorkspace
                )
                modelContext.insert(series)
                incomeSeriesByOldID[payload.id] = series
            }

            var allocationAccountsByOldID: [UUID: AllocationAccount] = [:]
            for payload in archive.allocationAccounts {
                guard let newID = allocationAccountIDMap[payload.id] else { continue }
                let account = AllocationAccount(
                    id: newID,
                    name: payload.name,
                    hexColor: normalizedHexColor(payload.hexColor),
                    isArchived: payload.isArchived,
                    archivedAt: payload.archivedAt,
                    workspace: importedWorkspace
                )
                modelContext.insert(account)
                allocationAccountsByOldID[payload.id] = account
            }

            var savingsAccountsByOldID: [UUID: SavingsAccount] = [:]
            for payload in archive.savingsAccounts {
                guard let newID = savingsAccountIDMap[payload.id] else { continue }
                let account = SavingsAccount(
                    id: newID,
                    name: payload.name,
                    total: payload.total,
                    didBackfillHistory: payload.didBackfillHistory,
                    autoCaptureThroughDate: payload.autoCaptureThroughDate,
                    createdAt: payload.createdAt,
                    updatedAt: payload.updatedAt,
                    workspace: importedWorkspace
                )
                modelContext.insert(account)
                savingsAccountsByOldID[payload.id] = account
            }

            var plannedExpensesByOldID: [UUID: PlannedExpense] = [:]
            for payload in archive.plannedExpenses {
                guard let newID = plannedExpenseIDMap[payload.id] else { continue }
                let plannedExpense = PlannedExpense(
                    id: newID,
                    title: payload.title,
                    plannedAmount: payload.plannedAmount,
                    actualAmount: payload.actualAmount,
                    expenseDate: payload.expenseDate,
                    workspace: importedWorkspace,
                    card: object(payload.cardID, in: cardsByOldID),
                    category: object(payload.categoryID, in: categoriesByOldID),
                    sourcePresetID: payload.sourcePresetID.flatMap { presetIDMap[$0] },
                    sourceBudgetID: payload.sourceBudgetID.flatMap { budgetIDMap[$0] }
                )
                modelContext.insert(plannedExpense)
                plannedExpensesByOldID[payload.id] = plannedExpense
            }

            var variableExpensesByOldID: [UUID: VariableExpense] = [:]
            for payload in archive.variableExpenses {
                guard let newID = variableExpenseIDMap[payload.id] else { continue }
                let expense = VariableExpense(
                    id: newID,
                    descriptionText: payload.descriptionText,
                    amount: payload.amount,
                    kindRaw: payload.kindRaw,
                    transactionDate: payload.transactionDate,
                    workspace: importedWorkspace,
                    card: object(payload.cardID, in: cardsByOldID),
                    category: object(payload.categoryID, in: categoriesByOldID)
                )
                modelContext.insert(expense)
                variableExpensesByOldID[payload.id] = expense
            }

            for payload in archive.incomes {
                let income = Income(
                    id: UUID(),
                    source: payload.source,
                    amount: payload.amount,
                    date: payload.date,
                    isPlanned: payload.isPlanned,
                    isException: payload.isException,
                    workspace: importedWorkspace,
                    series: object(payload.seriesID, in: incomeSeriesByOldID),
                    card: object(payload.cardID, in: cardsByOldID)
                )
                modelContext.insert(income)
            }

            for payload in archive.budgetCardLinks {
                guard let budget = object(payload.budgetID, in: budgetsByOldID),
                      let card = object(payload.cardID, in: cardsByOldID)
                else { continue }

                modelContext.insert(BudgetCardLink(id: UUID(), budget: budget, card: card))
            }

            for payload in archive.budgetPresetLinks {
                guard let budget = object(payload.budgetID, in: budgetsByOldID),
                      let preset = object(payload.presetID, in: presetsByOldID)
                else { continue }

                modelContext.insert(BudgetPresetLink(id: UUID(), budget: budget, preset: preset))
            }

            for payload in archive.budgetCategoryLimits {
                guard let budget = object(payload.budgetID, in: budgetsByOldID),
                      let category = object(payload.categoryID, in: categoriesByOldID)
                else { continue }

                modelContext.insert(
                    BudgetCategoryLimit(
                        id: UUID(),
                        minAmount: payload.minAmount,
                        maxAmount: payload.maxAmount,
                        budget: budget,
                        category: category
                    )
                )
            }

            for payload in archive.expenseAllocations {
                guard let account = object(payload.accountID, in: allocationAccountsByOldID) else { continue }
                let expense = object(payload.expenseID, in: variableExpensesByOldID)
                let plannedExpense = object(payload.plannedExpenseID, in: plannedExpensesByOldID)
                guard expense != nil || plannedExpense != nil else { continue }

                let allocation = ExpenseAllocation(
                    id: UUID(),
                    allocatedAmount: payload.allocatedAmount,
                    preservesGrossAmount: payload.preservesGrossAmount,
                    createdAt: payload.createdAt,
                    updatedAt: payload.updatedAt,
                    workspace: importedWorkspace,
                    account: account,
                    expense: expense,
                    plannedExpense: plannedExpense
                )
                modelContext.insert(allocation)
                expense?.allocation = allocation
                plannedExpense?.allocation = allocation
            }

            for payload in archive.allocationSettlements {
                guard let newID = allocationSettlementIDMap[payload.id],
                      let account = object(payload.accountID, in: allocationAccountsByOldID)
                else { continue }

                let expense = object(payload.expenseID, in: variableExpensesByOldID)
                let plannedExpense = object(payload.plannedExpenseID, in: plannedExpensesByOldID)
                let settlement = AllocationSettlement(
                    id: newID,
                    date: payload.date,
                    note: payload.note,
                    amount: payload.amount,
                    workspace: importedWorkspace,
                    account: account,
                    expense: expense,
                    plannedExpense: plannedExpense
                )
                modelContext.insert(settlement)
                expense?.offsetSettlement = settlement
                plannedExpense?.offsetSettlement = settlement
            }

            for payload in archive.savingsLedgerEntries {
                guard let account = object(payload.accountID, in: savingsAccountsByOldID) else { continue }

                let variableExpense = object(payload.variableExpenseID, in: variableExpensesByOldID)
                let plannedExpense = object(payload.plannedExpenseID, in: plannedExpensesByOldID)
                let entry = SavingsLedgerEntry(
                    id: UUID(),
                    date: payload.date,
                    amount: payload.amount,
                    note: payload.note,
                    kindRaw: payload.kindRaw,
                    linkedAllocationSettlementID: payload.linkedAllocationSettlementID.flatMap { allocationSettlementIDMap[$0] },
                    periodStartDate: payload.periodStartDate,
                    periodEndDate: payload.periodEndDate,
                    createdAt: payload.createdAt,
                    updatedAt: payload.updatedAt,
                    workspace: importedWorkspace,
                    account: account,
                    variableExpense: variableExpense,
                    plannedExpense: plannedExpense
                )
                modelContext.insert(entry)
                variableExpense?.savingsLedgerEntry = entry
                plannedExpense?.savingsLedgerEntry = entry
            }

            for payload in archive.importMerchantRules {
                let rule = ImportMerchantRule(
                    id: UUID(),
                    merchantKey: payload.merchantKey,
                    preferredName: payload.preferredName,
                    preferredCategory: object(payload.preferredCategoryID, in: categoriesByOldID),
                    workspace: importedWorkspace,
                    createdAt: payload.createdAt,
                    updatedAt: payload.updatedAt
                )
                modelContext.insert(rule)
            }

            for payload in archive.assistantAliasRules {
                let alias = AssistantAliasRule(
                    id: UUID(),
                    aliasKey: payload.aliasKey,
                    targetValue: payload.targetValue,
                    entityType: MarinaAliasEntityType(rawValue: payload.entityTypeRaw) ?? .category,
                    workspace: importedWorkspace,
                    createdAt: payload.createdAt,
                    updatedAt: payload.updatedAt
                )
                modelContext.insert(alias)
            }

            for account in savingsAccountsByOldID.values {
                SavingsAccountService.recalculateAccountTotal(account)
            }

            try modelContext.save()
            return importedWorkspace
        } catch {
            modelContext.delete(importedWorkspace)
            try? modelContext.save()
            throw error
        }
    }

    private func validate(_ archive: WorkspaceArchive) throws {
        guard archive.marker == WorkspaceArchive.markerValue else {
            throw ImportError.invalidArchive
        }

        guard archive.schemaVersion == WorkspaceArchive.supportedSchemaVersion else {
            throw ImportError.unsupportedSchemaVersion(archive.schemaVersion)
        }
    }

    private func makeIDMap(_ ids: [UUID]) throws -> [UUID: UUID] {
        var map: [UUID: UUID] = [:]
        for id in ids {
            guard map[id] == nil else {
                throw ImportError.duplicateRecordID
            }
            map[id] = UUID()
        }
        return map
    }

    private func object<T>(_ id: UUID?, in objects: [UUID: T]) -> T? {
        guard let id else { return nil }
        return objects[id]
    }

    private func uniqueWorkspaceName(baseName: String, existingWorkspaces: [Workspace]) -> String {
        let trimmedBase = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmedBase.isEmpty ? "Imported Workspace" : trimmedBase
        let existingNames = Set(existingWorkspaces.map { normalizedName($0.name) })

        guard existingNames.contains(normalizedName(base)) else {
            return base
        }

        let importedName = "\(base) (Imported)"
        if !existingNames.contains(normalizedName(importedName)) {
            return importedName
        }

        var suffix = 2
        while true {
            let candidate = "\(base) (Imported \(suffix))"
            if !existingNames.contains(normalizedName(candidate)) {
                return candidate
            }
            suffix += 1
        }
    }

    private func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalizedHexColor(_ hexColor: String) -> String {
        let trimmed = hexColor.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "#3B82F6" : trimmed
    }
}
