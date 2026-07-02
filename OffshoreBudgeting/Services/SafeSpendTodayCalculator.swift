import Foundation

enum SafeSpendTodayCalculator {
    struct Summary {
        let budgetingPeriod: BudgetingPeriod
        let rangeStart: Date
        let rangeEnd: Date
        let basePeriodRoom: Double
        let constrainedPeriodRoom: Double
        let periodRemainingRoom: Double
        let safeToSpendToday: Double
        let daysLeftInPeriod: Int
        let plannedSpendingForPeriod: Double
        let plannedSpendingRemaining: Double
        let actualSpendSoFar: Double
        let wasClampedToZero: Bool
        let categoryCapRemainingRoom: Double?
        let hasActivity: Bool

        var isDaily: Bool {
            budgetingPeriod == .daily
        }
    }

    static func calculate(
        workspace: Workspace,
        budgetingPeriod: BudgetingPeriod,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Summary {
        let resolvedRange = budgetingPeriod.defaultRange(containing: now, calendar: calendar)
        let rangeStart = calendar.startOfDay(for: resolvedRange.start)
        let rangeEnd = endOfDay(resolvedRange.end, calendar: calendar)

        let incomes = workspace.incomes ?? []
        let plannedExpenses = workspace.plannedExpenses ?? []
        let variableExpenses = workspace.variableExpenses ?? []
        let savingsEntries = (workspace.savingsAccounts ?? []).flatMap { $0.entries ?? [] }

        return calculate(
            budgetingPeriod: budgetingPeriod,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            budgets: workspace.budgets ?? [],
            categories: workspace.categories ?? [],
            incomes: incomes,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            savingsEntries: savingsEntries,
            now: now,
            calendar: calendar
        )
    }

    static func calculate(
        budgetingPeriod: BudgetingPeriod = .monthly,
        rangeStart: Date,
        rangeEnd: Date,
        budgets: [Budget],
        categories: [Category],
        incomes: [Income],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        savingsEntries: [SavingsLedgerEntry],
        now: Date = .now,
        calendar: Calendar = .current,
        virtualSpendAmount: Double = 0,
        virtualSpendCategoryID: UUID? = nil
    ) -> Summary {
        let rangeStart = calendar.startOfDay(for: rangeStart)
        let rangeEndDayStart = calendar.startOfDay(for: rangeEnd)
        let rangeEnd = endOfDay(rangeEnd, calendar: calendar)

        let todayStart = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now
        let toDateEnd = min(rangeEnd, endOfDay(now, calendar: calendar))
        let sanitizedVirtualSpend = max(0, virtualSpendAmount)

        let actualIncomeToDate = incomes
            .filter { !$0.isPlanned && $0.date >= rangeStart && $0.date < startOfTomorrow }
            .reduce(0.0) { $0 + $1.amount }

        let plannedIncomeRemaining = incomes
            .filter { $0.isPlanned && $0.date >= todayStart && $0.date <= rangeEnd }
            .reduce(0.0) { $0 + $1.amount }

        let plannedExpensesAlreadyConsumed = plannedExpenses
            .filter { $0.expenseDate >= rangeStart && $0.expenseDate < todayStart }
            .reduce(0.0) { $0 + SavingsMathService.plannedBudgetImpactAmount(for: $1) }

        let remainingPlannedExpenses = plannedExpenses
            .filter { $0.expenseDate >= todayStart && $0.expenseDate <= rangeEnd }
            .reduce(0.0) { $0 + SavingsMathService.plannedProjectedBudgetImpactAmount(for: $1) }

        let actualVariableExpensesToDate = variableExpenses
            .filter { $0.transactionDate >= rangeStart && $0.transactionDate < startOfTomorrow }
            .reduce(0.0) { $0 + SavingsMathService.variableBudgetImpactAmount(for: $1) }

        let actualSavingsAdjustmentsToDate = SavingsMathService.actualSavingsAdjustmentTotal(
            from: savingsEntries,
            startDate: rangeStart,
            endDate: toDateEnd
        )

        let periodRemainingRoom = actualIncomeToDate
            + plannedIncomeRemaining
            - plannedExpensesAlreadyConsumed
            - remainingPlannedExpenses
            - actualVariableExpensesToDate
            + actualSavingsAdjustmentsToDate
            - sanitizedVirtualSpend

        let categoryCapRemainingRoom = categoryCapRemainingRoom(
            budgets: budgets,
            categories: categories,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            virtualSpendAmount: sanitizedVirtualSpend,
            virtualSpendCategoryID: virtualSpendCategoryID,
            calendar: calendar
        )
        let constrainedRoom: Double
        if let categoryCapRemainingRoom {
            constrainedRoom = min(periodRemainingRoom, categoryCapRemainingRoom)
        } else {
            constrainedRoom = periodRemainingRoom
        }

        let clampedRoom = max(0, constrainedRoom)
        let wasClampedToZero = constrainedRoom < 0
        let daysLeftInPeriod = max(
            1,
            (calendar.dateComponents([.day], from: todayStart, to: rangeEndDayStart).day ?? 0) + 1
        )
        let plannedSpendingForPeriod = plannedExpensesAlreadyConsumed + remainingPlannedExpenses
        let actualSpendSoFar = plannedExpensesAlreadyConsumed + actualVariableExpensesToDate

        let safeToSpendToday: Double
        if budgetingPeriod == .daily {
            safeToSpendToday = clampedRoom
        } else {
            safeToSpendToday = clampedRoom / Double(daysLeftInPeriod)
        }

        let hasActivity = actualIncomeToDate != 0
            || plannedIncomeRemaining != 0
            || plannedExpensesAlreadyConsumed != 0
            || remainingPlannedExpenses != 0
            || actualVariableExpensesToDate != 0
            || actualSavingsAdjustmentsToDate != 0
            || sanitizedVirtualSpend != 0

        return Summary(
            budgetingPeriod: budgetingPeriod,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            basePeriodRoom: periodRemainingRoom,
            constrainedPeriodRoom: constrainedRoom,
            periodRemainingRoom: clampedRoom,
            safeToSpendToday: safeToSpendToday,
            daysLeftInPeriod: daysLeftInPeriod,
            plannedSpendingForPeriod: plannedSpendingForPeriod,
            plannedSpendingRemaining: remainingPlannedExpenses,
            actualSpendSoFar: actualSpendSoFar,
            wasClampedToZero: wasClampedToZero,
            categoryCapRemainingRoom: categoryCapRemainingRoom,
            hasActivity: hasActivity
        )
    }

    private static func endOfDay(_ date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }

    private static func categoryCapRemainingRoom(
        budgets: [Budget],
        categories: [Category],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        rangeStart: Date,
        rangeEnd: Date,
        virtualSpendAmount: Double,
        virtualSpendCategoryID: UUID?,
        calendar: Calendar
    ) -> Double? {
        let range = DateRange(start: rangeStart, end: rangeEnd, calendar: calendar)
        guard let activeBudget = BudgetRangeOverlap.pickActiveBudget(from: budgets, for: range, calendar: calendar) else {
            return nil
        }

        var maxAmountByCategoryID: [UUID: Double] = [:]
        let limits = activeBudget.categoryLimits ?? []
        for limit in limits {
            guard let category = limit.category, let maxAmount = limit.maxAmount else { continue }
            maxAmountByCategoryID[category.id] = maxAmount
        }
        guard maxAmountByCategoryID.isEmpty == false else { return nil }

        let knownCategoryIDs = Set(categories.map(\.id))
        for category in categories {
            guard maxAmountByCategoryID[category.id] != nil else { return nil }
        }

        var spendByCategoryID: [UUID: Double] = [:]
        for expense in plannedExpenses {
            guard
                expense.expenseDate >= range.start,
                expense.expenseDate <= range.end
            else { continue }
            guard let category = expense.category else { return nil }
            guard maxAmountByCategoryID[category.id] != nil else { return nil }
            guard knownCategoryIDs.isEmpty || knownCategoryIDs.contains(category.id) else { return nil }

            spendByCategoryID[category.id, default: 0] += SavingsMathService.plannedBudgetImpactAmount(for: expense)
        }

        for expense in variableExpenses {
            guard
                expense.transactionDate >= range.start,
                expense.transactionDate <= range.end
            else { continue }
            guard let category = expense.category else { return nil }
            guard maxAmountByCategoryID[category.id] != nil else { return nil }
            guard knownCategoryIDs.isEmpty || knownCategoryIDs.contains(category.id) else { return nil }

            spendByCategoryID[category.id, default: 0] += SavingsMathService.variableBudgetImpactAmount(for: expense)
        }

        var totalRemaining = 0.0
        let capCategoryIDs = knownCategoryIDs.isEmpty ? Set(maxAmountByCategoryID.keys) : knownCategoryIDs
        for categoryID in capCategoryIDs {
            guard let maxAmount = maxAmountByCategoryID[categoryID] else { return nil }
            let spend = max(0, spendByCategoryID[categoryID, default: 0])
            let virtualSpend = virtualSpendCategoryID == categoryID ? virtualSpendAmount : 0
            totalRemaining += max(0, maxAmount - spend - virtualSpend)
        }

        if virtualSpendCategoryID == nil {
            totalRemaining = max(0, totalRemaining - virtualSpendAmount)
        }

        return totalRemaining
    }
}
