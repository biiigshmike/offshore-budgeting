import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct WorkspaceTransferServiceTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Workspace.self,
            Budget.self,
            BudgetCategoryLimit.self,
            Card.self,
            BudgetCardLink.self,
            BudgetPresetLink.self,
            Offshore.Category.self,
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

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        return ModelContext(container)
    }

    private func fetchAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }

    @Test func fullArchiveRoundTrip_createsCopiedWorkspaceWithRemappedRelationships() throws {
        let context = try makeContext()
        let source = try seedTransferWorkspace(in: context)
        let sourceWorkspace = source.workspace

        let archive = try WorkspaceExportService().exportArchive(
            for: sourceWorkspace,
            sections: Set(WorkspaceTransferSection.allCases),
            modelContext: context,
            now: date(2026, 6, 3)
        )

        #expect(archive.workspace.name == "Personal")
        #expect(archive.cards.map(\.name) == ["Visa"])
        #expect(archive.categories.map(\.name) == ["Groceries"])
        #expect(archive.budgets.count == 1)
        #expect(archive.budgetCardLinks.count == 1)
        #expect(archive.budgetPresetLinks.count == 1)
        #expect(archive.budgetCategoryLimits.count == 1)
        #expect(archive.plannedExpenses.count == 1)
        #expect(archive.variableExpenses.count == 1)
        #expect(archive.allocationAccounts.count == 1)
        #expect(archive.expenseAllocations.count == 1)
        #expect(archive.allocationSettlements.count == 1)
        #expect(archive.savingsAccounts.count == 1)
        #expect(archive.savingsLedgerEntries.count == 1)
        #expect(archive.importMerchantRules.count == 1)
        #expect(archive.assistantAliasRules.count == 1)
        #expect(archive.incomeSeries.count == 1)
        #expect(archive.incomes.count == 1)

        let data = try WorkspaceArchiveCoding.encode(archive)
        let decoded = try WorkspaceArchiveCoding.decode(data)
        let imported = try WorkspaceImportService().importArchive(
            decoded,
            existingWorkspaces: try fetchAll(Workspace.self, in: context),
            modelContext: context
        )

        #expect(imported.id != sourceWorkspace.id)
        #expect(imported.name == "Personal (Imported)")

        let importedCards = try fetchAll(Card.self, in: context).filter { $0.workspace?.id == imported.id }
        let importedCard = try #require(importedCards.first)
        #expect(importedCard.id != source.card.id)
        #expect(importedCard.name == "Visa")

        let importedCategories = try fetchAll(Offshore.Category.self, in: context).filter { $0.workspace?.id == imported.id }
        let importedCategory = try #require(importedCategories.first)
        #expect(importedCategory.id != source.category.id)
        #expect(importedCategory.isArchived == false)

        let importedBudgets = try fetchAll(Budget.self, in: context).filter { $0.workspace?.id == imported.id }
        let importedBudget = try #require(importedBudgets.first)
        #expect(importedBudget.id != source.budget.id)

        let importedPresets = try fetchAll(Preset.self, in: context).filter { $0.workspace?.id == imported.id }
        let importedPreset = try #require(importedPresets.first)
        #expect(importedPreset.id != source.preset.id)
        #expect(importedPreset.defaultCard?.id == importedCard.id)
        #expect(importedPreset.defaultCategory?.id == importedCategory.id)

        let importedCardLinks = try fetchAll(BudgetCardLink.self, in: context).filter { $0.budget?.workspace?.id == imported.id }
        #expect(importedCardLinks.count == 1)
        #expect(importedCardLinks.first?.budget?.id == importedBudget.id)
        #expect(importedCardLinks.first?.card?.id == importedCard.id)

        let importedPresetLinks = try fetchAll(BudgetPresetLink.self, in: context).filter { $0.budget?.workspace?.id == imported.id }
        #expect(importedPresetLinks.count == 1)
        #expect(importedPresetLinks.first?.preset?.id == importedPreset.id)

        let importedLimits = try fetchAll(BudgetCategoryLimit.self, in: context).filter { $0.budget?.workspace?.id == imported.id }
        #expect(importedLimits.count == 1)
        #expect(importedLimits.first?.category?.id == importedCategory.id)

        let importedPlannedExpenses = try fetchAll(PlannedExpense.self, in: context).filter { $0.workspace?.id == imported.id }
        let importedPlanned = try #require(importedPlannedExpenses.first)
        #expect(importedPlanned.id != source.plannedExpense.id)
        #expect(importedPlanned.card?.id == importedCard.id)
        #expect(importedPlanned.category?.id == importedCategory.id)
        #expect(importedPlanned.sourcePresetID == importedPreset.id)
        #expect(importedPlanned.sourceBudgetID == importedBudget.id)

        let importedVariableExpenses = try fetchAll(VariableExpense.self, in: context).filter { $0.workspace?.id == imported.id }
        let importedVariable = try #require(importedVariableExpenses.first)
        #expect(importedVariable.id != source.variableExpense.id)
        #expect(importedVariable.card?.id == importedCard.id)
        #expect(importedVariable.category?.id == importedCategory.id)

        let importedAccounts = try fetchAll(AllocationAccount.self, in: context).filter { $0.workspace?.id == imported.id }
        let importedAccount = try #require(importedAccounts.first)
        let importedAllocations = try fetchAll(ExpenseAllocation.self, in: context).filter { $0.workspace?.id == imported.id }
        #expect(importedAllocations.count == 1)
        #expect(importedAllocations.first?.account?.id == importedAccount.id)
        #expect(importedAllocations.first?.expense?.id == importedVariable.id)

        let importedSettlements = try fetchAll(AllocationSettlement.self, in: context).filter { $0.workspace?.id == imported.id }
        let importedSettlement = try #require(importedSettlements.first)
        #expect(importedSettlement.account?.id == importedAccount.id)
        #expect(importedSettlement.plannedExpense?.id == importedPlanned.id)

        let importedSavingsAccounts = try fetchAll(SavingsAccount.self, in: context).filter { $0.workspace?.id == imported.id }
        let importedSavingsAccount = try #require(importedSavingsAccounts.first)
        let importedSavingsEntries = try fetchAll(SavingsLedgerEntry.self, in: context).filter { $0.workspace?.id == imported.id }
        let importedSavingsEntry = try #require(importedSavingsEntries.first)
        #expect(importedSavingsEntry.account?.id == importedSavingsAccount.id)
        #expect(importedSavingsEntry.variableExpense?.id == importedVariable.id)
        #expect(importedSavingsEntry.linkedAllocationSettlementID == importedSettlement.id)
        #expect(importedSavingsAccount.total == -12)

        let importedRules = try fetchAll(ImportMerchantRule.self, in: context).filter { $0.workspace?.id == imported.id }
        #expect(importedRules.first?.preferredCategory?.id == importedCategory.id)

        let importedAliases = try fetchAll(AssistantAliasRule.self, in: context).filter { $0.workspace?.id == imported.id }
        #expect(importedAliases.first?.entityType == .card)

        let importedIncomeSeries = try fetchAll(IncomeSeries.self, in: context).filter { $0.workspace?.id == imported.id }
        let importedSeries = try #require(importedIncomeSeries.first)
        let importedIncomes = try fetchAll(Income.self, in: context).filter { $0.workspace?.id == imported.id }
        #expect(importedIncomes.first?.series?.id == importedSeries.id)
        #expect(importedIncomes.first?.card?.id == importedCard.id)
    }

    @Test func export_skipsOtherWorkspaceRecords() throws {
        let context = try makeContext()
        let source = try seedTransferWorkspace(in: context)

        let archive = try WorkspaceExportService().exportArchive(
            for: source.workspace,
            sections: Set(WorkspaceTransferSection.allCases),
            modelContext: context
        )

        #expect(!archive.cards.contains { $0.name == "Other Visa" })
        #expect(!archive.categories.contains { $0.name == "Other Category" })
        #expect(!archive.budgets.contains { $0.name == "Other Budget" })
    }

    @Test func import_makesDuplicateWorkspaceNameUnique() throws {
        let context = try makeContext()
        let source = try seedTransferWorkspace(in: context)
        let existingImported = Workspace(name: "Personal (Imported)", hexColor: "#10B981")
        context.insert(existingImported)
        try context.save()

        let archive = try WorkspaceExportService().exportArchive(
            for: source.workspace,
            sections: Set(WorkspaceTransferSection.allCases),
            modelContext: context
        )

        let imported = try WorkspaceImportService().importArchive(
            archive,
            existingWorkspaces: try fetchAll(Workspace.self, in: context),
            modelContext: context
        )

        #expect(imported.name == "Personal (Imported 2)")
    }

    @Test func partialBudgetArchive_skipsLinksWhenTargetsAreOmitted() throws {
        let context = try makeContext()
        let source = try seedTransferWorkspace(in: context)

        let archive = try WorkspaceExportService().exportArchive(
            for: source.workspace,
            sections: [.budgets],
            modelContext: context
        )

        #expect(archive.budgets.count == 1)
        #expect(archive.cards.isEmpty)
        #expect(archive.categories.isEmpty)
        #expect(archive.presets.isEmpty)
        #expect(archive.budgetCardLinks.count == 1)
        #expect(archive.budgetPresetLinks.count == 1)
        #expect(archive.budgetCategoryLimits.count == 1)

        let imported = try WorkspaceImportService().importArchive(
            archive,
            existingWorkspaces: try fetchAll(Workspace.self, in: context),
            modelContext: context
        )

        let importedBudgets = try fetchAll(Budget.self, in: context).filter { $0.workspace?.id == imported.id }
        let importedCards = try fetchAll(Card.self, in: context).filter { $0.workspace?.id == imported.id }
        let importedCardLinks = try fetchAll(BudgetCardLink.self, in: context).filter { $0.budget?.workspace?.id == imported.id }
        let importedPresetLinks = try fetchAll(BudgetPresetLink.self, in: context).filter { $0.budget?.workspace?.id == imported.id }
        let importedLimits = try fetchAll(BudgetCategoryLimit.self, in: context).filter { $0.budget?.workspace?.id == imported.id }

        #expect(importedBudgets.count == 1)
        #expect(importedCards.isEmpty)
        #expect(importedCardLinks.isEmpty)
        #expect(importedPresetLinks.isEmpty)
        #expect(importedLimits.isEmpty)
    }

    @Test func invalidArchivesFailWithoutInsertingWorkspace() throws {
        let context = try makeContext()
        let existing = Workspace(name: "Existing", hexColor: "#3B82F6")
        context.insert(existing)
        try context.save()

        do {
            _ = try WorkspaceArchiveCoding.decode(Data("not json".utf8))
            Issue.record("Expected malformed JSON to fail decoding.")
        } catch {
            #expect(try fetchAll(Workspace.self, in: context).count == 1)
        }

        var unsupported = emptyArchive()
        unsupported.schemaVersion = 999
        do {
            _ = try WorkspaceImportService().importArchive(
                unsupported,
                existingWorkspaces: try fetchAll(Workspace.self, in: context),
                modelContext: context
            )
            Issue.record("Expected unsupported schema to fail.")
        } catch let error as WorkspaceImportService.ImportError {
            #expect(error == .unsupportedSchemaVersion(999))
            #expect(try fetchAll(Workspace.self, in: context).count == 1)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }

        var invalidMarker = emptyArchive()
        invalidMarker.marker = "not-offshore"
        do {
            _ = try WorkspaceImportService().importArchive(
                invalidMarker,
                existingWorkspaces: try fetchAll(Workspace.self, in: context),
                modelContext: context
            )
            Issue.record("Expected invalid marker to fail.")
        } catch let error as WorkspaceImportService.ImportError {
            #expect(error == .invalidArchive)
            #expect(try fetchAll(Workspace.self, in: context).count == 1)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    private func seedTransferWorkspace(in context: ModelContext) throws -> TransferSeed {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let otherWorkspace = Workspace(name: "Other", hexColor: "#14B8A6")

        let category = Offshore.Category(name: "Groceries", hexColor: "#22C55E", workspace: workspace)
        let card = Card(name: "Visa", theme: "ruby", effect: "plastic", workspace: workspace)
        let budget = Budget(
            name: "June",
            startDate: date(2026, 6, 1),
            endDate: date(2026, 6, 30),
            workspace: workspace
        )
        let preset = Preset(
            title: "Rent",
            plannedAmount: 1200,
            frequencyRaw: RecurrenceFrequency.monthly.rawValue,
            interval: 1,
            monthlyDayOfMonth: 5,
            workspace: workspace,
            defaultCard: card,
            defaultCategory: category
        )
        let budgetCardLink = BudgetCardLink(budget: budget, card: card)
        let budgetPresetLink = BudgetPresetLink(budget: budget, preset: preset)
        let categoryLimit = BudgetCategoryLimit(
            minAmount: 25,
            maxAmount: 500,
            budget: budget,
            category: category
        )
        let plannedExpense = PlannedExpense(
            title: "Rent",
            plannedAmount: 1200,
            actualAmount: 1195,
            expenseDate: date(2026, 6, 5),
            workspace: workspace,
            card: card,
            category: category,
            sourcePresetID: preset.id,
            sourceBudgetID: budget.id
        )
        let variableExpense = VariableExpense(
            descriptionText: "Coffee",
            amount: 12,
            kindRaw: VariableExpenseKind.debit.rawValue,
            transactionDate: date(2026, 6, 7),
            workspace: workspace,
            card: card,
            category: category
        )
        let allocationAccount = AllocationAccount(
            name: "Roommate",
            hexColor: "#F97316",
            workspace: workspace
        )
        let allocation = ExpenseAllocation(
            allocatedAmount: 4,
            preservesGrossAmount: true,
            createdAt: date(2026, 6, 7),
            updatedAt: date(2026, 6, 8),
            workspace: workspace,
            account: allocationAccount,
            expense: variableExpense
        )
        variableExpense.allocation = allocation

        let settlement = AllocationSettlement(
            date: date(2026, 6, 9),
            note: "Rent share",
            amount: 600,
            workspace: workspace,
            account: allocationAccount,
            plannedExpense: plannedExpense
        )
        plannedExpense.offsetSettlement = settlement

        let savingsAccount = SavingsAccount(
            name: "Primary Savings",
            total: 999,
            didBackfillHistory: true,
            autoCaptureThroughDate: date(2026, 5, 31),
            createdAt: date(2026, 1, 1),
            updatedAt: date(2026, 6, 1),
            workspace: workspace
        )
        let savingsEntry = SavingsLedgerEntry(
            date: date(2026, 6, 7),
            amount: -12,
            note: "Coffee offset",
            kindRaw: SavingsLedgerEntryKind.expenseOffset.rawValue,
            linkedAllocationSettlementID: settlement.id,
            periodStartDate: date(2026, 6, 1),
            periodEndDate: date(2026, 6, 30),
            createdAt: date(2026, 6, 7),
            updatedAt: date(2026, 6, 7),
            workspace: workspace,
            account: savingsAccount,
            variableExpense: variableExpense
        )
        variableExpense.savingsLedgerEntry = savingsEntry

        let series = IncomeSeries(
            source: "Paycheck",
            amount: 2000,
            isPlanned: true,
            frequencyRaw: RecurrenceFrequency.monthly.rawValue,
            interval: 1,
            weeklyWeekday: 6,
            monthlyDayOfMonth: 15,
            monthlyIsLastDay: false,
            yearlyMonth: 1,
            yearlyDayOfMonth: 15,
            startDate: date(2026, 1, 1),
            endDate: date(2026, 12, 31),
            workspace: workspace
        )
        let income = Income(
            source: "Paycheck",
            amount: 2000,
            date: date(2026, 6, 15),
            isPlanned: true,
            isException: true,
            workspace: workspace,
            series: series,
            card: card
        )
        let importRule = ImportMerchantRule(
            merchantKey: "coffee",
            preferredName: "Coffee Shop",
            preferredCategory: category,
            workspace: workspace,
            createdAt: date(2026, 6, 1),
            updatedAt: date(2026, 6, 2)
        )
        let alias = AssistantAliasRule(
            aliasKey: "main card",
            targetValue: "Visa",
            entityType: .card,
            workspace: workspace,
            createdAt: date(2026, 6, 1),
            updatedAt: date(2026, 6, 2)
        )

        let otherCard = Card(name: "Other Visa", workspace: otherWorkspace)
        let otherCategory = Offshore.Category(name: "Other Category", hexColor: "#111111", workspace: otherWorkspace)
        let otherBudget = Budget(
            name: "Other Budget",
            startDate: date(2026, 6, 1),
            endDate: date(2026, 6, 30),
            workspace: otherWorkspace
        )

        context.insert(workspace)
        context.insert(otherWorkspace)
        context.insert(category)
        context.insert(card)
        context.insert(budget)
        context.insert(preset)
        context.insert(budgetCardLink)
        context.insert(budgetPresetLink)
        context.insert(categoryLimit)
        context.insert(plannedExpense)
        context.insert(variableExpense)
        context.insert(allocationAccount)
        context.insert(allocation)
        context.insert(settlement)
        context.insert(savingsAccount)
        context.insert(savingsEntry)
        context.insert(series)
        context.insert(income)
        context.insert(importRule)
        context.insert(alias)
        context.insert(otherCard)
        context.insert(otherCategory)
        context.insert(otherBudget)
        try context.save()

        return TransferSeed(
            workspace: workspace,
            card: card,
            category: category,
            budget: budget,
            preset: preset,
            plannedExpense: plannedExpense,
            variableExpense: variableExpense
        )
    }

    private func emptyArchive() -> WorkspaceArchive {
        WorkspaceArchive(
            exportedAt: date(2026, 6, 3),
            sourceWorkspaceID: UUID(),
            selectedSections: [],
            workspace: WorkspacePayload(
                id: UUID(),
                name: "Empty",
                hexColor: "#3B82F6"
            )
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }
}

private struct TransferSeed {
    let workspace: Workspace
    let card: Card
    let category: Offshore.Category
    let budget: Budget
    let preset: Preset
    let plannedExpense: PlannedExpense
    let variableExpense: VariableExpense
}
