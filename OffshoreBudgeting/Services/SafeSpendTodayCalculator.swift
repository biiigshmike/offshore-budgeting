import Foundation

@MainActor
enum SafeSpendTodayCalculator {
    struct Summary {
        let budgetingPeriod: BudgetingPeriod
        let rangeStart: Date
        let rangeEnd: Date
        let periodRemainingRoom: Double
        let safeToSpendToday: Double
        let daysLeftInPeriod: Int

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
        let rangeEndDayStart = calendar.startOfDay(for: resolvedRange.end)
        let rangeEnd = endOfDay(resolvedRange.end, calendar: calendar)

        let todayStart = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now
        let toDateEnd = min(rangeEnd, endOfDay(now, calendar: calendar))

        let incomes = workspace.incomes ?? []
        let plannedExpenses = workspace.plannedExpenses ?? []
        let variableExpenses = workspace.variableExpenses ?? []
        let savingsEntries = (workspace.savingsAccounts ?? []).flatMap { $0.entries ?? [] }

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

        let clampedRoom = max(0, periodRemainingRoom)
        let daysLeftInPeriod = max(
            1,
            (calendar.dateComponents([.day], from: todayStart, to: rangeEndDayStart).day ?? 0) + 1
        )

        let safeToSpendToday: Double
        if budgetingPeriod == .daily {
            safeToSpendToday = clampedRoom
        } else {
            safeToSpendToday = clampedRoom / Double(daysLeftInPeriod)
        }

        return Summary(
            budgetingPeriod: budgetingPeriod,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            periodRemainingRoom: clampedRoom,
            safeToSpendToday: safeToSpendToday,
            daysLeftInPeriod: daysLeftInPeriod
        )
    }

    private static func endOfDay(_ date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }
}
