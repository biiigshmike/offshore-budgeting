import Foundation

/// Builds the budget-scoped data and totals used by Budget Detail and other read-only consumers.
enum BudgetLensService {
    struct EmptyIntersection {
        let budgetRange: DateRange
        let requestedRange: DateRange
    }

    enum Outcome {
        case lens(Lens)
        case emptyIntersection(EmptyIntersection)

        var resolvedLens: Lens? {
            guard case .lens(let lens) = self else { return nil }
            return lens
        }
    }

    struct FutureCalculationPolicy {
        let excludeFuturePlannedExpenses: Bool
        let excludeFutureVariableExpenses: Bool
        let now: Date
    }

    struct Totals {
        let plannedIncomeTotal: Double
        let actualIncomeTotal: Double
        let plannedExpenseProjectedTotal: Double
        let plannedExpenseActualTotal: Double
        let plannedExpenseEffectiveTotal: Double
        let variableExpenseTotal: Double
        let unifiedExpenseTotal: Double
        let actualSavingsAdjustmentTotal: Double
        let maxSavings: Double
        let projectedSavings: Double
        let actualSavings: Double

        static let zero = Totals(
            plannedIncomeTotal: 0,
            actualIncomeTotal: 0,
            plannedExpenseProjectedTotal: 0,
            plannedExpenseActualTotal: 0,
            plannedExpenseEffectiveTotal: 0,
            variableExpenseTotal: 0,
            unifiedExpenseTotal: 0,
            actualSavingsAdjustmentTotal: 0,
            maxSavings: 0,
            projectedSavings: 0,
            actualSavings: 0
        )
    }

    struct Lens {
        let workspace: Workspace
        let budget: Budget
        let dateRange: DateRange
        let linkedCards: [Card]
        let linkedPresets: [Preset]
        let categoryLimits: [BudgetCategoryLimit]
        let categoriesInBudget: [Category]
        let incomesInBudget: [Income]
        let plannedExpensesInBudget: [PlannedExpense]
        let variableExpensesInBudget: [VariableExpense]
        let savingsEntriesInBudget: [SavingsLedgerEntry]
        let totals: Totals
    }

    static func makeLens(
        workspace: Workspace,
        budget: Budget,
        budgetCardLinks: [BudgetCardLink],
        budgetPresetLinks: [BudgetPresetLink],
        budgetCategoryLimits: [BudgetCategoryLimit],
        workspaceCategories: [Category],
        workspaceIncomes: [Income],
        workspacePlannedExpenses: [PlannedExpense],
        workspaceVariableExpenses: [VariableExpense],
        workspaceSavingsEntries: [SavingsLedgerEntry],
        requestedDateRange: DateRange?,
        futureCalculationPolicy: FutureCalculationPolicy,
        calendar: Calendar = .current
    ) -> Outcome {
        let budgetRange = DateRange(start: budget.startDate, end: budget.endDate, calendar: calendar)
        let range: DateRange
        if let requestedDateRange {
            guard let intersection = budgetRange.intersection(with: requestedDateRange) else {
                return .emptyIntersection(
                    EmptyIntersection(
                        budgetRange: budgetRange,
                        requestedRange: requestedDateRange
                    )
                )
            }
            range = intersection
        } else {
            range = budgetRange
        }
        let workspaceID = workspace.id
        let budgetID = budget.id

        guard budget.workspace?.id == workspaceID else {
            return .lens(Lens(
                workspace: workspace,
                budget: budget,
                dateRange: range,
                linkedCards: [],
                linkedPresets: [],
                categoryLimits: [],
                categoriesInBudget: [],
                incomesInBudget: [],
                plannedExpensesInBudget: [],
                variableExpensesInBudget: [],
                savingsEntriesInBudget: [],
                totals: .zero
            ))
        }

        let linkedCards = budgetCardLinks
            .filter { $0.budget?.id == budgetID }
            .compactMap(\.card)
            .filter { $0.workspace?.id == workspaceID }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let linkedCardIDs = Set(linkedCards.map(\.id))

        let linkedPresets = budgetPresetLinks
            .filter { $0.budget?.id == budgetID }
            .compactMap(\.preset)
            .filter { $0.workspace?.id == workspaceID }
            .sorted { $0.id.uuidString < $1.id.uuidString }

        let categoryLimits = budgetCategoryLimits.filter { limit in
            guard limit.budget?.id == budgetID else { return false }
            guard let category = limit.category else { return true }
            return category.workspace?.id == workspaceID
        }

        let incomesInBudget = workspaceIncomes
            .filter { $0.workspace?.id == workspaceID }
            .filter { range.start <= $0.date && $0.date <= range.end }
            .sorted { $0.date > $1.date }

        let plannedExpensesInBudget = BudgetPlannedExpenseStore.plannedExpenses(
            workspacePlannedExpenses.filter { $0.workspace?.id == workspaceID },
            budgetID: budgetID,
            linkedCardIDs: linkedCardIDs,
            range: range
        )

        let variableExpensesInBudget = workspaceVariableExpenses
            .filter { $0.workspace?.id == workspaceID }
            .filter { expense in
                guard let cardID = expense.card?.id else { return false }
                return linkedCardIDs.contains(cardID)
            }
            .filter { range.start <= $0.transactionDate && $0.transactionDate <= range.end }
            .sorted { $0.transactionDate > $1.transactionDate }

        let savingsEntriesInBudget = workspaceSavingsEntries
            .filter { $0.workspace?.id == workspaceID }
            .filter { range.start <= $0.date && $0.date <= range.end }
            .sorted { $0.date > $1.date }

        var categoriesByID: [UUID: Category] = [:]
        for category in workspaceCategories where category.workspace?.id == workspaceID {
            categoriesByID[category.id] = category
        }
        let attachedCategories = plannedExpensesInBudget.compactMap(\.category)
            + variableExpensesInBudget.compactMap(\.category)
        for category in attachedCategories where category.workspace?.id == workspaceID {
            categoriesByID[category.id] = category
        }
        let categoriesInBudget = categoriesByID.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        let totals = totals(
            incomesInBudget: incomesInBudget,
            plannedExpensesInBudget: plannedExpensesInBudget,
            variableExpensesInBudget: variableExpensesInBudget,
            savingsEntriesInBudget: savingsEntriesInBudget,
            futureCalculationPolicy: futureCalculationPolicy,
            calendar: calendar
        )

        return .lens(Lens(
            workspace: workspace,
            budget: budget,
            dateRange: range,
            linkedCards: linkedCards,
            linkedPresets: linkedPresets,
            categoryLimits: categoryLimits,
            categoriesInBudget: categoriesInBudget,
            incomesInBudget: incomesInBudget,
            plannedExpensesInBudget: plannedExpensesInBudget,
            variableExpensesInBudget: variableExpensesInBudget,
            savingsEntriesInBudget: savingsEntriesInBudget,
            totals: totals
        ))
    }

    static func totals(
        incomesInBudget: [Income],
        plannedExpensesInBudget: [PlannedExpense],
        variableExpensesInBudget: [VariableExpense],
        savingsEntriesInBudget: [SavingsLedgerEntry],
        futureCalculationPolicy: FutureCalculationPolicy,
        calendar: Calendar = .current
    ) -> Totals {
        let plannedIncomeTotal = incomesInBudget
            .filter(\.isPlanned)
            .reduce(0) { $0 + $1.amount }
        let actualIncomeTotal = incomesInBudget
            .filter { !$0.isPlanned }
            .reduce(0) { $0 + $1.amount }

        let plannedExpensesForCalculations = PlannedExpenseFuturePolicy.filteredForCalculations(
            plannedExpensesInBudget,
            excludeFuture: futureCalculationPolicy.excludeFuturePlannedExpenses,
            now: futureCalculationPolicy.now,
            calendar: calendar
        )
        let variableExpensesForCalculations = VariableExpenseFuturePolicy.filteredForCalculations(
            variableExpensesInBudget,
            excludeFuture: futureCalculationPolicy.excludeFutureVariableExpenses,
            now: futureCalculationPolicy.now,
            calendar: calendar
        )

        let plannedExpenseProjectedTotal = plannedExpensesForCalculations.reduce(0) {
            $0 + SavingsMathService.plannedProjectedBudgetImpactAmount(for: $1)
        }
        let plannedExpenseActualTotal = plannedExpensesForCalculations.reduce(0) {
            $0 + max(0, $1.actualAmount)
        }
        let plannedExpenseEffectiveTotal = plannedExpensesForCalculations.reduce(0) {
            $0 + SavingsMathService.plannedBudgetImpactAmount(for: $1)
        }
        let variableExpenseTotal = variableExpensesForCalculations.reduce(0) {
            $0 + SavingsMathService.variableBudgetImpactAmount(for: $1)
        }
        let unifiedExpenseTotal = plannedExpenseEffectiveTotal + variableExpenseTotal
        let actualSavingsAdjustmentTotal = savingsEntriesInBudget.reduce(0) {
            $0 + SavingsMathService.actualSavingsAdjustmentAmount(for: $1)
        }

        return Totals(
            plannedIncomeTotal: plannedIncomeTotal,
            actualIncomeTotal: actualIncomeTotal,
            plannedExpenseProjectedTotal: plannedExpenseProjectedTotal,
            plannedExpenseActualTotal: plannedExpenseActualTotal,
            plannedExpenseEffectiveTotal: plannedExpenseEffectiveTotal,
            variableExpenseTotal: variableExpenseTotal,
            unifiedExpenseTotal: unifiedExpenseTotal,
            actualSavingsAdjustmentTotal: actualSavingsAdjustmentTotal,
            maxSavings: plannedIncomeTotal - plannedExpenseEffectiveTotal,
            projectedSavings: plannedIncomeTotal - plannedExpenseProjectedTotal,
            actualSavings: actualIncomeTotal
                - plannedExpenseEffectiveTotal
                - variableExpenseTotal
                + actualSavingsAdjustmentTotal
        )
    }
}
