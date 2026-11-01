import Foundation

/// A full-budget spending scenario, independent of expense-list search and category filters.
/// This is a flow estimate, not a savings-account balance or a ledger mutation.
enum CategoryGoalSavingsCalculator {
    struct Summary: Equatable, Sendable {
        let plannedIncome: Double
        let currentExpenseImpact: Double
        let remainingCategoryAllowance: Double
        var estimatedSavings: Double { plannedIncome - currentExpenseImpact - remainingCategoryAllowance }
    }

    static func calculate(
        for budget: Budget,
        workspaceID: UUID,
        linkedCardIDs: Set<UUID>,
        incomes: [Income],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        categoryLimits: [BudgetCategoryLimit],
        excludeFuturePlannedExpenses: Bool = false,
        excludeFutureVariableExpenses: Bool = false,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Summary? {
        guard budget.workspace?.id == workspaceID else { return nil }

        // Match the first goal per category used by the existing goal editor.
        var seenCategoryIDs = Set<UUID>()
        var maximumByCategoryID: [UUID: Double] = [:]
        for goal in categoryLimits {
            guard goal.budget?.id == budget.id,
                  let category = goal.category, category.workspace?.id == workspaceID,
                  seenCategoryIDs.insert(category.id).inserted else { continue }
            if let maximum = goal.maxAmount, maximum.isFinite, maximum >= 0 {
                maximumByCategoryID[category.id] = maximum
            }
        }
        guard !maximumByCategoryID.isEmpty else { return nil }

        let range = DateRange(start: budget.startDate, end: budget.endDate, calendar: calendar)
        let planned = PlannedExpenseFuturePolicy.filteredForCalculations(
            BudgetPlannedExpenseStore.plannedExpenses(
                plannedExpenses.filter { $0.workspace?.id == workspaceID && $0.card?.workspace?.id == workspaceID },
                budgetID: budget.id, linkedCardIDs: linkedCardIDs, range: range
            ),
            excludeFuture: excludeFuturePlannedExpenses, now: now, calendar: calendar
        )
        let variable = VariableExpenseFuturePolicy.filteredForCalculations(
            variableExpenses.filter { expense in
                guard expense.workspace?.id == workspaceID,
                      let card = expense.card, card.workspace?.id == workspaceID,
                      linkedCardIDs.contains(card.id) else { return false }
                return expense.transactionDate >= range.start && expense.transactionDate <= range.end
            },
            excludeFuture: excludeFutureVariableExpenses, now: now, calendar: calendar
        )
        let plannedIncome = incomes.filter {
            $0.workspace?.id == workspaceID && $0.isPlanned && $0.date >= range.start && $0.date <= range.end
        }.reduce(0) { $0 + $1.amount }

        var currentExpenseImpact = 0.0
        var impactByCategoryID: [UUID: Double] = [:]
        for expense in planned {
            let impact = SavingsMathService.plannedBudgetImpactAmount(for: expense)
            currentExpenseImpact += impact
            if let category = expense.category, category.workspace?.id == workspaceID {
                impactByCategoryID[category.id, default: 0] += impact
            }
        }
        for expense in variable {
            let impact = SavingsMathService.variableBudgetImpactAmount(for: expense)
            currentExpenseImpact += impact
            if let category = expense.category, category.workspace?.id == workspaceID {
                impactByCategoryID[category.id, default: 0] += impact
            }
        }

        // Reserve only the unused part of each maximum; never reduce an existing cost to its goal.
        let allowance = maximumByCategoryID.reduce(0.0) { total, item in
            total + max(0, item.value - impactByCategoryID[item.key, default: 0])
        }
        return Summary(plannedIncome: plannedIncome, currentExpenseImpact: currentExpenseImpact,
                       remainingCategoryAllowance: allowance)
    }
}
