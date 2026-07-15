import Foundation
import Testing
@testable import Offshore

struct MarinaDataSurfaceExpansionTests {
    private let registry = MarinaEntityAdapterRegistry()
    private let baseDate = Date(timeIntervalSince1970: 1_783_036_800)

    @Test func workspaceAdapterExposesOnlySelectedWorkspaceMetadata() throws {
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        let snapshot = makeSnapshot(workspace: workspace)

        let row = try #require(registry.adapter(for: .workspace)?.rows(from: snapshot).first)

        #expect(row.id == workspace.id)
        #expect(row.entity == .workspace)
        #expect(row.fields[.name] == .text("Personal"))
        #expect(row.fields[.color] == .colorHex("#123456"))
        #expect(row.relationships.isEmpty)
    }

    @Test func variableExpenseExposesKindAndIndependentLedgerSemantics() throws {
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        let adjustment = VariableExpense(
            descriptionText: "Opening balance",
            amount: 45,
            kindRaw: VariableExpenseKind.adjustment.rawValue,
            transactionDate: baseDate,
            workspace: workspace
        )
        let snapshot = makeSnapshot(
            workspace: workspace,
            variableExpenses: [adjustment],
            calculationVariableExpenses: [adjustment]
        )

        let row = try #require(registry.adapter(for: .variableExpense)?.rows(from: snapshot).first)

        #expect(row.fields[.amount] == .money(45))
        #expect(row.fields[.kind] == .text(VariableExpenseKind.adjustment.rawValue))
        #expect(row.fields[.ledgerSignedAmount] == .money(45))
        #expect(row.fields[.budgetImpact] == .money(0))
    }

    @Test func presetRecurrenceAndLinkedBudgetsRejectForeignMembership() throws {
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        let foreignWorkspace = Workspace(name: "Work", hexColor: "#654321")
        let budget = Budget(
            name: "July",
            startDate: baseDate,
            endDate: baseDate.addingTimeInterval(86400 * 30),
            workspace: workspace
        )
        let foreignBudget = Budget(
            name: "Foreign",
            startDate: baseDate,
            endDate: baseDate.addingTimeInterval(86400 * 30),
            workspace: foreignWorkspace
        )
        let preset = Preset(
            title: "Rent",
            plannedAmount: 1_200,
            frequencyRaw: RecurrenceFrequency.yearly.rawValue,
            interval: 2,
            weeklyWeekday: 3,
            monthlyDayOfMonth: 28,
            monthlyIsLastDay: true,
            yearlyMonth: 7,
            yearlyDayOfMonth: 4,
            workspace: workspace
        )
        let selectedLink = BudgetPresetLink(budget: budget, preset: preset)
        let foreignLink = BudgetPresetLink(budget: foreignBudget, preset: preset)
        preset.budgetPresetLinks = [selectedLink, foreignLink]
        budget.presetLinks = [selectedLink]
        foreignBudget.presetLinks = [foreignLink]
        let snapshot = makeSnapshot(workspace: workspace, budgets: [budget], presets: [preset])

        let row = try #require(registry.adapter(for: .preset)?.rows(from: snapshot).first)
        let linkedBudgets = row.relationshipCollections[.budget] ?? []

        #expect(row.fields[.frequency] == .text(RecurrenceFrequency.yearly.rawValue))
        #expect(row.fields[.interval] == .integer(2))
        #expect(row.fields[.weeklyWeekday] == .integer(3))
        #expect(row.fields[.monthlyDayOfMonth] == .integer(28))
        #expect(row.fields[.monthlyIsLastDay] == .boolean(true))
        #expect(row.fields[.yearlyMonth] == .integer(7))
        #expect(row.fields[.yearlyDayOfMonth] == .integer(4))
        #expect(linkedBudgets.compactMap(\.targetID) == [budget.id])

        let plan = MarinaUniversalQueryPlan(
            entity: .preset,
            projection: .linkedBudgets,
            operation: .list,
            resolvedTarget: reference(.preset, id: preset.id, name: preset.title)
        )
        let rows = try #require(registry.rows(for: plan, from: snapshot))
        #expect(rows.map(\.id) == [budget.id])
    }

    @Test func incomeSeriesExposesRuleAndOnlySelectedWorkspaceOccurrences() throws {
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        let foreignWorkspace = Workspace(name: "Work", hexColor: "#654321")
        let series = IncomeSeries(
            source: "Salary",
            amount: 2_500,
            isPlanned: true,
            frequencyRaw: RecurrenceFrequency.weekly.rawValue,
            interval: 2,
            weeklyWeekday: 6,
            monthlyDayOfMonth: 15,
            monthlyIsLastDay: false,
            yearlyMonth: 1,
            yearlyDayOfMonth: 15,
            startDate: baseDate,
            endDate: baseDate.addingTimeInterval(86400 * 90),
            workspace: workspace
        )
        let foreignSeries = IncomeSeries(
            source: "Foreign Salary",
            amount: 10_000,
            isPlanned: true,
            frequencyRaw: RecurrenceFrequency.monthly.rawValue,
            interval: 1,
            weeklyWeekday: 6,
            monthlyDayOfMonth: 1,
            monthlyIsLastDay: false,
            yearlyMonth: 1,
            yearlyDayOfMonth: 1,
            startDate: baseDate,
            endDate: baseDate,
            workspace: foreignWorkspace
        )
        let occurrence = Income(
            source: "Salary",
            amount: 2_500,
            date: baseDate,
            isPlanned: true,
            isException: true,
            workspace: workspace,
            series: series
        )
        let malformedOccurrence = Income(
            source: "Foreign-linked",
            amount: 100,
            date: baseDate,
            isPlanned: true,
            workspace: workspace,
            series: foreignSeries
        )
        let snapshot = makeSnapshot(
            workspace: workspace,
            incomes: [occurrence, malformedOccurrence],
            incomeSeries: [series, foreignSeries]
        )

        let seriesRow = try #require(registry.adapter(for: .incomeSeries)?.rows(from: snapshot).first)
        let incomeRows = try #require(registry.adapter(for: .income)?.rows(from: snapshot))
        let occurrenceRow = try #require(incomeRows.first { $0.id == occurrence.id })
        let malformedRow = try #require(incomeRows.first { $0.id == malformedOccurrence.id })

        #expect(seriesRow.fields[.frequency] == .text(RecurrenceFrequency.weekly.rawValue))
        #expect(seriesRow.fields[.interval] == .integer(2))
        #expect(occurrenceRow.fields[.isException] == .boolean(true))
        #expect(occurrenceRow.relationships[.incomeSeries]?.targetID == series.id)
        #expect(malformedRow.relationships[.incomeSeries] == nil)

        let plan = MarinaUniversalQueryPlan(
            entity: .incomeSeries,
            projection: .occurrences,
            operation: .list,
            resolvedTarget: reference(.incomeSeries, id: series.id, name: series.source)
        )
        let rows = try #require(registry.rows(for: plan, from: snapshot))
        #expect(rows.map(\.id) == [occurrence.id])
    }

    @Test func activityProjectionsKeepLedgerModelsInternalAndValidateRelationships() throws {
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        let foreignWorkspace = Workspace(name: "Work", hexColor: "#654321")
        let savingsAccount = SavingsAccount(name: "Emergency", workspace: workspace)
        let foreignExpense = VariableExpense(
            descriptionText: "Foreign",
            amount: 10,
            transactionDate: baseDate,
            workspace: foreignWorkspace
        )
        let savingsEntry = SavingsLedgerEntry(
            date: baseDate,
            amount: 100,
            note: "Deposit",
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
            workspace: workspace,
            account: savingsAccount,
            variableExpense: foreignExpense
        )
        let reconciliationAccount = AllocationAccount(name: "Roommate", workspace: workspace)
        let settlement = AllocationSettlement(
            date: baseDate,
            note: "Paid",
            amount: -25,
            workspace: workspace,
            account: reconciliationAccount,
            expense: foreignExpense
        )
        let snapshot = makeSnapshot(
            workspace: workspace,
            reconciliationAccounts: [reconciliationAccount],
            allocationSettlements: [settlement],
            savingsAccounts: [savingsAccount],
            savingsEntries: [savingsEntry]
        )

        let savingsPlan = MarinaUniversalQueryPlan(
            surface: .savingsLedgerEntries,
            projection: .activity,
            operation: .list,
            resolvedTarget: reference(.savingsAccount, id: savingsAccount.id, name: savingsAccount.name)
        )
        let reconciliationPlan = MarinaUniversalQueryPlan(
            surface: .reconciliationLedgerEntries,
            projection: .activity,
            operation: .list,
            resolvedTarget: reference(
                .reconciliationAccount,
                id: reconciliationAccount.id,
                name: reconciliationAccount.name
            )
        )
        let savingsRow = try #require(registry.rows(for: savingsPlan, from: snapshot)?.first)
        let reconciliationRow = try #require(registry.rows(for: reconciliationPlan, from: snapshot)?.first)

        #expect(savingsRow.entity == .savingsAccount)
        #expect(savingsRow.relationships[.savingsAccount]?.targetID == savingsAccount.id)
        #expect(savingsRow.relationships[.variableExpense] == nil)
        #expect(reconciliationRow.entity == .reconciliationAccount)
        #expect(reconciliationRow.relationships[.reconciliationAccount]?.targetID == reconciliationAccount.id)
        #expect(reconciliationRow.relationships[.variableExpense] == nil)
    }

    @Test func malformedExpenseRelationshipsNeverExposeForeignObjects() throws {
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        let foreignWorkspace = Workspace(name: "Work", hexColor: "#654321")
        let foreignCard = Card(name: "Work Card", workspace: foreignWorkspace)
        let foreignCategory = Offshore.Category(name: "Work", hexColor: "#000000", workspace: foreignWorkspace)
        let foreignAllocationAccount = AllocationAccount(name: "Foreign Split", workspace: foreignWorkspace)
        let foreignSavingsAccount = SavingsAccount(name: "Foreign Savings", workspace: foreignWorkspace)
        let expense = VariableExpense(
            descriptionText: "Malformed",
            amount: 10,
            transactionDate: baseDate,
            workspace: workspace,
            card: foreignCard,
            category: foreignCategory
        )
        expense.allocation = ExpenseAllocation(
            allocatedAmount: 5,
            workspace: workspace,
            account: foreignAllocationAccount,
            expense: expense
        )
        expense.savingsLedgerEntry = SavingsLedgerEntry(
            date: baseDate,
            amount: -5,
            note: "Offset",
            kindRaw: SavingsLedgerEntryKind.expenseOffset.rawValue,
            workspace: workspace,
            account: foreignSavingsAccount,
            variableExpense: expense
        )
        let snapshot = makeSnapshot(workspace: workspace, variableExpenses: [expense])

        let row = try #require(registry.adapter(for: .variableExpense)?.rows(from: snapshot).first)

        #expect(row.relationships[.workspace]?.targetID == workspace.id)
        #expect(row.relationships[.card] == nil)
        #expect(row.relationships[.category] == nil)
        #expect(row.relationships[.reconciliationAccount] == nil)
        #expect(row.relationships[.savingsAccount] == nil)
    }

    @Test func unifiedExpenseRowsUseHomeCalculationArrays() throws {
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        let rawOnly = VariableExpense(
            descriptionText: "Raw only",
            amount: 999,
            transactionDate: baseDate,
            workspace: workspace
        )
        let calculationOnly = VariableExpense(
            descriptionText: "Calculation only",
            amount: 25,
            transactionDate: baseDate,
            workspace: workspace
        )
        let snapshot = makeSnapshot(
            workspace: workspace,
            variableExpenses: [rawOnly],
            calculationVariableExpenses: [calculationOnly]
        )

        let rows = try #require(registry.rows(for: .unifiedExpenses, from: snapshot))

        #expect(rows.map(\.id) == [calculationOnly.id])
    }

    @Test func budgetSummaryUsesBudgetLensAndHomeCalculationArrays() throws {
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        let budgetEnd = baseDate.addingTimeInterval(86400 * 30)
        let budget = Budget(name: "July", startDate: baseDate, endDate: budgetEnd, workspace: workspace)
        let card = Card(name: "Everyday", workspace: workspace)
        let cardLink = BudgetCardLink(budget: budget, card: card)
        budget.cardLinks = [cardLink]
        let preset = Preset(title: "Bill template", plannedAmount: 150, workspace: workspace, defaultCard: card)
        let presetLink = BudgetPresetLink(budget: budget, preset: preset)
        budget.presetLinks = [presetLink]
        preset.budgetPresetLinks = [presetLink]
        let plannedIncome = Income(
            source: "Planned",
            amount: 1_000,
            date: baseDate,
            isPlanned: true,
            workspace: workspace
        )
        let actualIncome = Income(
            source: "Actual",
            amount: 800,
            date: baseDate,
            isPlanned: false,
            workspace: workspace
        )
        let planned = PlannedExpense(
            title: "Bill",
            plannedAmount: 150,
            actualAmount: 100,
            expenseDate: baseDate,
            workspace: workspace,
            card: card,
            sourceBudgetID: budget.id
        )
        let variable = VariableExpense(
            descriptionText: "Groceries",
            amount: 50,
            transactionDate: baseDate,
            workspace: workspace,
            card: card
        )
        let rawOnly = VariableExpense(
            descriptionText: "Excluded raw row",
            amount: 999,
            transactionDate: baseDate,
            workspace: workspace,
            card: card
        )
        let calculationOutsideBudget = VariableExpense(
            descriptionText: "Unlinked calculation row",
            amount: 777,
            transactionDate: baseDate,
            workspace: workspace
        )
        let savingsEntry = SavingsLedgerEntry(
            date: baseDate,
            amount: 20,
            note: "Adjustment",
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
            workspace: workspace
        )
        let snapshot = makeSnapshot(
            workspace: workspace,
            budgets: [budget],
            cards: [card],
            presets: [preset],
            plannedExpenses: [planned],
            variableExpenses: [rawOnly],
            calculationPlannedExpenses: [planned],
            calculationVariableExpenses: [variable, calculationOutsideBudget],
            savingsEntries: [savingsEntry],
            incomes: [plannedIncome, actualIncome]
        )
        let plan = MarinaUniversalQueryPlan(
            entity: .budget,
            projection: .summary,
            operation: .list,
            resolvedTarget: reference(.budget, id: budget.id, name: budget.name),
            resolvedScope: .budget(budget.id)
        )

        let row = try #require(registry.rows(for: plan, from: snapshot)?.first)

        #expect(row.fields[.plannedIncomeTotal] == .money(1_000))
        #expect(row.fields[.actualIncomeTotal] == .money(800))
        #expect(row.fields[.plannedExpenseProjectedTotal] == .money(150))
        #expect(row.fields[.plannedExpenseActualTotal] == .money(100))
        #expect(row.fields[.plannedExpenseEffectiveTotal] == .money(100))
        #expect(row.fields[.variableExpenseTotal] == .money(50))
        #expect(row.fields[.unifiedExpenseTotal] == .money(150))
        #expect(row.fields[.maximumSavings] == .money(900))
        #expect(row.fields[.projectedSavings] == .money(850))
        #expect(row.fields[.actualSavings] == .money(670))

        let linkedCardRows = try #require(
            registry.rows(
                for: MarinaUniversalQueryPlan(
                    entity: .budget,
                    projection: .linkedCards,
                    operation: .list,
                    resolvedScope: .budget(budget.id)
                ),
                from: snapshot
            )
        )
        let linkedPresetRows = try #require(
            registry.rows(
                for: MarinaUniversalQueryPlan(
                    entity: .budget,
                    projection: .linkedPresets,
                    operation: .list,
                    resolvedScope: .budget(budget.id)
                ),
                from: snapshot
            )
        )
        let incomeRows = try #require(
            registry.rows(
                for: MarinaUniversalQueryPlan(
                    entity: .budget,
                    projection: .income,
                    operation: .list,
                    resolvedScope: .budget(budget.id)
                ),
                from: snapshot
            )
        )
        let expenseRows = try #require(
            registry.rows(
                for: MarinaUniversalQueryPlan(
                    entity: .budget,
                    projection: .expenses,
                    operation: .list,
                    resolvedScope: .budget(budget.id)
                ),
                from: snapshot
            )
        )
        let scopedUnifiedRows = try #require(
            registry.rows(
                for: MarinaUniversalQueryPlan(
                    surface: .unifiedExpenses,
                    operation: .list,
                    resolvedScope: .budget(budget.id)
                ),
                from: snapshot
            )
        )
        let scopedIncomeRows = try #require(
            registry.rows(
                for: MarinaUniversalQueryPlan(
                    entity: .income,
                    operation: .list,
                    resolvedScope: .budget(budget.id)
                ),
                from: snapshot
            )
        )
        let scopedPlannedRows = try #require(
            registry.rows(
                for: MarinaUniversalQueryPlan(
                    entity: .plannedExpense,
                    operation: .list,
                    resolvedScope: .budget(budget.id)
                ),
                from: snapshot
            )
        )
        let scopedVariableRows = try #require(
            registry.rows(
                for: MarinaUniversalQueryPlan(
                    entity: .variableExpense,
                    operation: .list,
                    resolvedScope: .budget(budget.id)
                ),
                from: snapshot
            )
        )

        #expect(linkedCardRows.map(\.id) == [card.id])
        #expect(linkedPresetRows.map(\.id) == [preset.id])
        #expect(Set(incomeRows.map(\.id)) == Set([plannedIncome.id, actualIncome.id]))
        #expect(Set(expenseRows.map(\.id)) == Set([planned.id, variable.id]))
        #expect(Set(scopedUnifiedRows.map(\.id)) == Set([planned.id, variable.id]))
        #expect(Set(scopedIncomeRows.map(\.id)) == Set([plannedIncome.id, actualIncome.id]))
        #expect(scopedPlannedRows.map(\.id) == [planned.id])
        #expect(scopedVariableRows.map(\.id) == [variable.id])

        let emptyIntersectionPlan = MarinaUniversalQueryPlan(
            entity: .budget,
            projection: .summary,
            operation: .list,
            dateRange: HomeQueryDateRange(
                startDate: budgetEnd.addingTimeInterval(86400 * 5),
                endDate: budgetEnd.addingTimeInterval(86400 * 6)
            ),
            dateRangeSource: .explicit,
            resolvedTarget: reference(.budget, id: budget.id, name: budget.name),
            resolvedScope: .budget(budget.id)
        )
        #expect(registry.rows(for: emptyIntersectionPlan, from: snapshot)?.isEmpty == true)

        let staleScopePlan = MarinaUniversalQueryPlan(
            entity: .income,
            operation: .list,
            resolvedScope: .budget(UUID())
        )
        let foreignWorkspacePlan = MarinaUniversalQueryPlan(
            entity: .workspace,
            operation: .list,
            resolvedScope: .workspace(UUID())
        )
        #expect(registry.rows(for: staleScopePlan, from: snapshot)?.isEmpty == true)
        #expect(registry.rows(for: foreignWorkspacePlan, from: snapshot)?.isEmpty == true)
    }

    private func reference(
        _ entity: MarinaSemanticEntity,
        id: UUID,
        name: String
    ) -> MarinaResolvedEntityReference {
        MarinaResolvedEntityReference(
            entity: entity,
            id: id,
            displayName: name,
            provenance: .candidateResolver
        )
    }

    private func makeSnapshot(
        workspace: Workspace,
        budgets: [Budget] = [],
        cards: [Card] = [],
        categories: [Offshore.Category] = [],
        presets: [Preset] = [],
        plannedExpenses: [PlannedExpense] = [],
        variableExpenses: [VariableExpense] = [],
        calculationPlannedExpenses: [PlannedExpense] = [],
        calculationVariableExpenses: [VariableExpense] = [],
        reconciliationAccounts: [AllocationAccount] = [],
        expenseAllocations: [ExpenseAllocation] = [],
        allocationSettlements: [AllocationSettlement] = [],
        savingsAccounts: [SavingsAccount] = [],
        savingsEntries: [SavingsLedgerEntry] = [],
        incomes: [Income] = [],
        incomeSeries: [IncomeSeries] = []
    ) -> MarinaWorkspaceSnapshot {
        MarinaWorkspaceSnapshot(
            workspace: workspace,
            budgets: budgets,
            cards: cards,
            categories: categories,
            presets: presets,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            homePlannedExpenses: plannedExpenses,
            homeCalculationPlannedExpenses: calculationPlannedExpenses,
            homeCalculationVariableExpenses: calculationVariableExpenses,
            reconciliationAccounts: reconciliationAccounts,
            expenseAllocations: expenseAllocations,
            allocationSettlements: allocationSettlements,
            savingsAccounts: savingsAccounts,
            savingsEntries: savingsEntries,
            incomes: incomes,
            incomeSeries: incomeSeries
        )
    }
}
