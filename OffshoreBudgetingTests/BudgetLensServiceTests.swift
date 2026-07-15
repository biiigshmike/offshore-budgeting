import Foundation
import Testing
@testable import Offshore

@MainActor
struct BudgetLensServiceTests {
    @Test func lensScopesAttachmentsAndRowsToWorkspaceBudgetLinkedCardsAndInclusiveRange() throws {
        let calendar = fixedCalendar
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let otherWorkspace = Workspace(name: "Work", hexColor: "#AA0000")
        let budget = Budget(
            name: "January",
            startDate: date(2026, 1, 1),
            endDate: date(2026, 1, 31),
            workspace: workspace
        )
        let otherBudget = Budget(
            name: "Other",
            startDate: date(2026, 1, 1),
            endDate: date(2026, 1, 31),
            workspace: workspace
        )

        let linkedCard = Card(name: "Linked", workspace: workspace)
        let unlinkedCard = Card(name: "Unlinked", workspace: workspace)
        let foreignCard = Card(name: "Foreign", workspace: otherWorkspace)
        let cardLinks = [
            BudgetCardLink(budget: budget, card: linkedCard),
            BudgetCardLink(budget: otherBudget, card: unlinkedCard),
            BudgetCardLink(budget: budget, card: foreignCard)
        ]

        let linkedPreset = Preset(title: "Rent", plannedAmount: 500, workspace: workspace)
        let otherPreset = Preset(title: "Other", plannedAmount: 50, workspace: workspace)
        let foreignPreset = Preset(title: "Foreign", plannedAmount: 75, workspace: otherWorkspace)
        let presetLinks = [
            BudgetPresetLink(budget: budget, preset: linkedPreset),
            BudgetPresetLink(budget: otherBudget, preset: otherPreset),
            BudgetPresetLink(budget: budget, preset: foreignPreset)
        ]

        let category = Category(name: "Food", hexColor: "#00AA00", workspace: workspace)
        let attachedCategory = Category(name: "Housing", hexColor: "#0000AA", workspace: workspace)
        let foreignCategory = Category(name: "Foreign", hexColor: "#AA0000", workspace: otherWorkspace)
        let includedLimit = BudgetCategoryLimit(maxAmount: 300, budget: budget, category: category)
        let otherBudgetLimit = BudgetCategoryLimit(maxAmount: 200, budget: otherBudget, category: category)
        let foreignLimit = BudgetCategoryLimit(maxAmount: 100, budget: budget, category: foreignCategory)

        let incomeAtStart = Income(
            source: "Salary",
            amount: 1_000,
            date: date(2026, 1, 1),
            isPlanned: true,
            workspace: workspace
        )
        let incomeAtEnd = Income(
            source: "Bonus",
            amount: 250,
            date: date(2026, 1, 31, hour: 23, minute: 59),
            isPlanned: false,
            workspace: workspace
        )
        let outsideIncome = Income(
            source: "Outside",
            amount: 500,
            date: date(2026, 2, 1),
            isPlanned: false,
            workspace: workspace
        )
        let foreignIncome = Income(
            source: "Foreign",
            amount: 900,
            date: date(2026, 1, 15),
            isPlanned: false,
            workspace: otherWorkspace
        )

        let includedPlanned = PlannedExpense(
            title: "Included planned",
            plannedAmount: 100,
            expenseDate: date(2026, 1, 31, hour: 23, minute: 59),
            workspace: workspace,
            card: linkedCard,
            category: attachedCategory,
            sourceBudgetID: budget.id
        )
        let wrongBudgetPlanned = PlannedExpense(
            title: "Wrong budget",
            plannedAmount: 100,
            expenseDate: date(2026, 1, 15),
            workspace: workspace,
            card: linkedCard,
            sourceBudgetID: otherBudget.id
        )
        let wrongCardPlanned = PlannedExpense(
            title: "Wrong card",
            plannedAmount: 100,
            expenseDate: date(2026, 1, 15),
            workspace: workspace,
            card: unlinkedCard,
            sourceBudgetID: budget.id
        )
        let outsidePlanned = PlannedExpense(
            title: "Outside",
            plannedAmount: 100,
            expenseDate: date(2026, 2, 1),
            workspace: workspace,
            card: linkedCard,
            sourceBudgetID: budget.id
        )
        let foreignPlanned = PlannedExpense(
            title: "Foreign",
            plannedAmount: 100,
            expenseDate: date(2026, 1, 15),
            workspace: otherWorkspace,
            card: linkedCard,
            sourceBudgetID: budget.id
        )

        let includedVariable = VariableExpense(
            descriptionText: "Included variable",
            amount: 40,
            transactionDate: date(2026, 1, 31, hour: 23, minute: 59),
            workspace: workspace,
            card: linkedCard,
            category: category
        )
        let wrongCardVariable = VariableExpense(
            descriptionText: "Wrong card",
            amount: 50,
            transactionDate: date(2026, 1, 15),
            workspace: workspace,
            card: unlinkedCard
        )
        let outsideVariable = VariableExpense(
            descriptionText: "Outside",
            amount: 60,
            transactionDate: date(2026, 2, 1),
            workspace: workspace,
            card: linkedCard
        )
        let foreignVariable = VariableExpense(
            descriptionText: "Foreign",
            amount: 70,
            transactionDate: date(2026, 1, 15),
            workspace: otherWorkspace,
            card: linkedCard
        )

        let includedSavings = savingsEntry(
            date: date(2026, 1, 31, hour: 23, minute: 59),
            amount: 25,
            kind: .manualAdjustment,
            workspace: workspace
        )
        let outsideSavings = savingsEntry(
            date: date(2026, 2, 1),
            amount: 50,
            kind: .manualAdjustment,
            workspace: workspace
        )
        let foreignSavings = savingsEntry(
            date: date(2026, 1, 15),
            amount: 75,
            kind: .manualAdjustment,
            workspace: otherWorkspace
        )

        let outcome = BudgetLensService.makeLens(
            workspace: workspace,
            budget: budget,
            budgetCardLinks: cardLinks,
            budgetPresetLinks: presetLinks,
            budgetCategoryLimits: [includedLimit, otherBudgetLimit, foreignLimit],
            workspaceCategories: [category],
            workspaceIncomes: [outsideIncome, foreignIncome, incomeAtStart, incomeAtEnd],
            workspacePlannedExpenses: [
                wrongBudgetPlanned,
                wrongCardPlanned,
                outsidePlanned,
                foreignPlanned,
                includedPlanned
            ],
            workspaceVariableExpenses: [
                wrongCardVariable,
                outsideVariable,
                foreignVariable,
                includedVariable
            ],
            workspaceSavingsEntries: [outsideSavings, foreignSavings, includedSavings],
            requestedDateRange: nil,
            futureCalculationPolicy: policy(now: date(2026, 1, 15)),
            calendar: calendar
        )
        let lens = try #require(outcome.resolvedLens)

        #expect(lens.linkedCards.map(\.id) == [linkedCard.id])
        #expect(lens.linkedPresets.map(\.id) == [linkedPreset.id])
        #expect(lens.categoryLimits.map(\.id) == [includedLimit.id])
        #expect(Set(lens.categoriesInBudget.map(\.id)) == [category.id, attachedCategory.id])
        #expect(Set(lens.incomesInBudget.map(\.id)) == [incomeAtStart.id, incomeAtEnd.id])
        #expect(lens.plannedExpensesInBudget.map(\.id) == [includedPlanned.id])
        #expect(lens.variableExpensesInBudget.map(\.id) == [includedVariable.id])
        #expect(lens.savingsEntriesInBudget.map(\.id) == [includedSavings.id])
        #expect(lens.dateRange.start == date(2026, 1, 1))
        #expect(lens.dateRange.end >= date(2026, 1, 31, hour: 23, minute: 59))
    }

    @Test func totalsPreserveBudgetDetailFinancialFormulas() {
        let plannedIncome = Income(
            source: "Expected",
            amount: 1_000,
            date: date(2026, 1, 5),
            isPlanned: true
        )
        let actualIncome = Income(
            source: "Received",
            amount: 800,
            date: date(2026, 1, 5),
            isPlanned: false
        )
        let recordedPlanned = PlannedExpense(
            title: "Recorded",
            plannedAmount: 300,
            actualAmount: 250,
            expenseDate: date(2026, 1, 10)
        )
        let unrecordedPlanned = PlannedExpense(
            title: "Unrecorded",
            plannedAmount: 200,
            actualAmount: 0,
            expenseDate: date(2026, 1, 11)
        )
        let offset = savingsEntry(
            date: date(2026, 1, 11),
            amount: -50,
            kind: .expenseOffset,
            plannedExpense: unrecordedPlanned
        )
        unrecordedPlanned.savingsLedgerEntry = offset

        let debit = VariableExpense(
            descriptionText: "Debit",
            amount: 100,
            transactionDate: date(2026, 1, 12)
        )
        let credit = VariableExpense(
            descriptionText: "Credit",
            amount: 40,
            kindRaw: VariableExpenseKind.credit.rawValue,
            transactionDate: date(2026, 1, 13)
        )
        let adjustment = VariableExpense(
            descriptionText: "Adjustment",
            amount: 70,
            kindRaw: VariableExpenseKind.adjustment.rawValue,
            transactionDate: date(2026, 1, 14)
        )
        let manualAdjustment = savingsEntry(
            date: date(2026, 1, 15),
            amount: 25,
            kind: .manualAdjustment
        )
        let periodClose = savingsEntry(
            date: date(2026, 1, 15),
            amount: 999,
            kind: .periodClose
        )

        let totals = BudgetLensService.totals(
            incomesInBudget: [plannedIncome, actualIncome],
            plannedExpensesInBudget: [recordedPlanned, unrecordedPlanned],
            variableExpensesInBudget: [debit, credit, adjustment],
            savingsEntriesInBudget: [offset, manualAdjustment, periodClose],
            futureCalculationPolicy: policy(now: date(2026, 1, 20)),
            calendar: fixedCalendar
        )

        #expect(totals.plannedIncomeTotal == 1_000)
        #expect(totals.actualIncomeTotal == 800)
        #expect(totals.plannedExpenseProjectedTotal == 500)
        #expect(totals.plannedExpenseActualTotal == 250)
        #expect(totals.plannedExpenseEffectiveTotal == 400)
        #expect(totals.variableExpenseTotal == 60)
        #expect(totals.unifiedExpenseTotal == 460)
        #expect(totals.actualSavingsAdjustmentTotal == 25)
        #expect(totals.maxSavings == 600)
        #expect(totals.projectedSavings == 500)
        #expect(totals.actualSavings == 365)
    }

    @Test func futureCalculationPolicyChangesTotalsWithoutRemovingAttachedExpenses() throws {
        let calendar = fixedCalendar
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let budget = Budget(
            name: "February and March",
            startDate: date(2026, 2, 1),
            endDate: date(2026, 3, 31),
            workspace: workspace
        )
        let card = Card(name: "Card", workspace: workspace)
        let cardLink = BudgetCardLink(budget: budget, card: card)
        let income = Income(
            source: "Expected",
            amount: 1_000,
            date: date(2026, 2, 5),
            isPlanned: true,
            workspace: workspace
        )
        let currentPlanned = PlannedExpense(
            title: "Current planned",
            plannedAmount: 100,
            expenseDate: date(2026, 2, 10),
            workspace: workspace,
            card: card,
            sourceBudgetID: budget.id
        )
        let futurePlanned = PlannedExpense(
            title: "Future planned",
            plannedAmount: 200,
            expenseDate: date(2026, 3, 10),
            workspace: workspace,
            card: card,
            sourceBudgetID: budget.id
        )
        let currentVariable = VariableExpense(
            descriptionText: "Current variable",
            amount: 40,
            transactionDate: date(2026, 2, 10),
            workspace: workspace,
            card: card
        )
        let futureVariable = VariableExpense(
            descriptionText: "Future variable",
            amount: 60,
            transactionDate: date(2026, 3, 10),
            workspace: workspace,
            card: card
        )
        let now = date(2026, 2, 15, hour: 12)

        let included = try makeLens(
            workspace: workspace,
            budget: budget,
            cardLink: cardLink,
            income: income,
            plannedExpenses: [currentPlanned, futurePlanned],
            variableExpenses: [currentVariable, futureVariable],
            futurePolicy: policy(now: now),
            calendar: calendar
        )
        let excluded = try makeLens(
            workspace: workspace,
            budget: budget,
            cardLink: cardLink,
            income: income,
            plannedExpenses: [currentPlanned, futurePlanned],
            variableExpenses: [currentVariable, futureVariable],
            futurePolicy: policy(
                excludeFuturePlannedExpenses: true,
                excludeFutureVariableExpenses: true,
                now: now
            ),
            calendar: calendar
        )
        let plannedOnlyExcluded = try makeLens(
            workspace: workspace,
            budget: budget,
            cardLink: cardLink,
            income: income,
            plannedExpenses: [currentPlanned, futurePlanned],
            variableExpenses: [currentVariable, futureVariable],
            futurePolicy: policy(
                excludeFuturePlannedExpenses: true,
                excludeFutureVariableExpenses: false,
                now: now
            ),
            calendar: calendar
        )

        #expect(included.plannedExpensesInBudget.count == 2)
        #expect(included.variableExpensesInBudget.count == 2)
        #expect(excluded.plannedExpensesInBudget.count == 2)
        #expect(excluded.variableExpensesInBudget.count == 2)
        #expect(included.totals.plannedExpenseProjectedTotal == 300)
        #expect(included.totals.plannedExpenseEffectiveTotal == 300)
        #expect(included.totals.variableExpenseTotal == 100)
        #expect(included.totals.unifiedExpenseTotal == 400)
        #expect(excluded.totals.plannedExpenseProjectedTotal == 100)
        #expect(excluded.totals.plannedExpenseEffectiveTotal == 100)
        #expect(excluded.totals.variableExpenseTotal == 40)
        #expect(excluded.totals.unifiedExpenseTotal == 140)
        #expect(plannedOnlyExcluded.totals.plannedExpenseEffectiveTotal == 100)
        #expect(plannedOnlyExcluded.totals.variableExpenseTotal == 100)
        #expect(plannedOnlyExcluded.totals.unifiedExpenseTotal == 200)
    }

    @Test func requestedRangeIsIntersectedWithBudgetBeforeRowsAndTotalsAreBuilt() throws {
        let calendar = fixedCalendar
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let budget = Budget(
            name: "January",
            startDate: date(2026, 1, 1),
            endDate: date(2026, 1, 31),
            workspace: workspace
        )
        let card = Card(name: "Card", workspace: workspace)
        let includedIncome = Income(
            source: "Included",
            amount: 500,
            date: date(2026, 1, 15),
            isPlanned: true,
            workspace: workspace
        )
        let excludedIncome = Income(
            source: "Outside request",
            amount: 900,
            date: date(2026, 1, 5),
            isPlanned: true,
            workspace: workspace
        )
        let includedPlanned = PlannedExpense(
            title: "Included",
            plannedAmount: 100,
            expenseDate: date(2026, 1, 20, hour: 23, minute: 59),
            workspace: workspace,
            card: card,
            sourceBudgetID: budget.id
        )
        let excludedPlanned = PlannedExpense(
            title: "Outside request",
            plannedAmount: 200,
            expenseDate: date(2026, 1, 21),
            workspace: workspace,
            card: card,
            sourceBudgetID: budget.id
        )
        let requestedRange = DateRange(
            start: date(2026, 1, 10),
            end: date(2026, 1, 20),
            calendar: calendar
        )

        let outcome = BudgetLensService.makeLens(
            workspace: workspace,
            budget: budget,
            budgetCardLinks: [BudgetCardLink(budget: budget, card: card)],
            budgetPresetLinks: [],
            budgetCategoryLimits: [],
            workspaceCategories: [],
            workspaceIncomes: [excludedIncome, includedIncome],
            workspacePlannedExpenses: [excludedPlanned, includedPlanned],
            workspaceVariableExpenses: [],
            workspaceSavingsEntries: [],
            requestedDateRange: requestedRange,
            futureCalculationPolicy: policy(now: date(2026, 1, 15)),
            calendar: calendar
        )
        let lens = try #require(outcome.resolvedLens)

        #expect(lens.dateRange == requestedRange)
        #expect(lens.incomesInBudget.map(\.id) == [includedIncome.id])
        #expect(lens.plannedExpensesInBudget.map(\.id) == [includedPlanned.id])
        #expect(lens.totals.plannedIncomeTotal == 500)
        #expect(lens.totals.plannedExpenseEffectiveTotal == 100)
    }

    @Test func disjointRequestedRangeReturnsTypedEmptyIntersection() {
        let calendar = fixedCalendar
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let budget = Budget(
            name: "January",
            startDate: date(2026, 1, 1),
            endDate: date(2026, 1, 31),
            workspace: workspace
        )
        let requestedRange = DateRange(
            start: date(2026, 2, 1),
            end: date(2026, 2, 28),
            calendar: calendar
        )

        let outcome = BudgetLensService.makeLens(
            workspace: workspace,
            budget: budget,
            budgetCardLinks: [],
            budgetPresetLinks: [],
            budgetCategoryLimits: [],
            workspaceCategories: [],
            workspaceIncomes: [],
            workspacePlannedExpenses: [],
            workspaceVariableExpenses: [],
            workspaceSavingsEntries: [],
            requestedDateRange: requestedRange,
            futureCalculationPolicy: policy(now: date(2026, 1, 15)),
            calendar: calendar
        )

        switch outcome {
        case .emptyIntersection(let empty):
            #expect(empty.requestedRange == requestedRange)
            #expect(empty.budgetRange == DateRange(
                start: budget.startDate,
                end: budget.endDate,
                calendar: calendar
            ))
        case .lens:
            Issue.record("Expected a typed empty-intersection outcome.")
        }
    }

    private var fixedCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 0,
        minute: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return fixedCalendar.date(from: components) ?? .now
    }

    private func policy(
        excludeFuturePlannedExpenses: Bool = false,
        excludeFutureVariableExpenses: Bool = false,
        now: Date
    ) -> BudgetLensService.FutureCalculationPolicy {
        BudgetLensService.FutureCalculationPolicy(
            excludeFuturePlannedExpenses: excludeFuturePlannedExpenses,
            excludeFutureVariableExpenses: excludeFutureVariableExpenses,
            now: now
        )
    }

    private func savingsEntry(
        date: Date,
        amount: Double,
        kind: SavingsLedgerEntryKind,
        workspace: Workspace? = nil,
        plannedExpense: PlannedExpense? = nil
    ) -> SavingsLedgerEntry {
        SavingsLedgerEntry(
            date: date,
            amount: amount,
            note: kind.rawValue,
            kindRaw: kind.rawValue,
            workspace: workspace,
            plannedExpense: plannedExpense
        )
    }

    private func makeLens(
        workspace: Workspace,
        budget: Budget,
        cardLink: BudgetCardLink,
        income: Income,
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        futurePolicy: BudgetLensService.FutureCalculationPolicy,
        calendar: Calendar
    ) throws -> BudgetLensService.Lens {
        let outcome = BudgetLensService.makeLens(
            workspace: workspace,
            budget: budget,
            budgetCardLinks: [cardLink],
            budgetPresetLinks: [],
            budgetCategoryLimits: [],
            workspaceCategories: [],
            workspaceIncomes: [income],
            workspacePlannedExpenses: plannedExpenses,
            workspaceVariableExpenses: variableExpenses,
            workspaceSavingsEntries: [],
            requestedDateRange: nil,
            futureCalculationPolicy: futurePolicy,
            calendar: calendar
        )
        return try #require(outcome.resolvedLens)
    }
}
