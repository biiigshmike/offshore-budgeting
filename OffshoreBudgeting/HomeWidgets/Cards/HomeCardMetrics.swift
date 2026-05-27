//
//  HomeCardMetrics.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/24/26.
//

import Foundation

struct HomeCardMetrics: Equatable {
    let plannedTotal: Double
    let variableTotal: Double
    let total: Double

    static let zero = HomeCardMetrics(plannedTotal: 0, variableTotal: 0, total: 0)
}

enum HomeCardMetricsCalculator {

    static func metrics(
        for card: Card,
        start: Date,
        end: Date,
        excludeFuturePlannedExpenses: Bool,
        excludeFutureVariableExpenses: Bool,
        now: Date = Date()
    ) -> HomeCardMetrics {
        metrics(
            for: card,
            plannedExpenses: card.plannedExpenses ?? [],
            variableExpenses: card.variableExpenses ?? [],
            start: start,
            end: end,
            excludeFuturePlannedExpenses: excludeFuturePlannedExpenses,
            excludeFutureVariableExpenses: excludeFutureVariableExpenses,
            now: now
        )
    }

    static func metrics(
        for card: Card,
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        start: Date,
        end: Date,
        excludeFuturePlannedExpenses: Bool,
        excludeFutureVariableExpenses: Bool,
        now: Date = Date()
    ) -> HomeCardMetrics {
        let s = normalizedStart(start)
        let e = normalizedEnd(end)

        let plannedInRange = plannedExpenses
            .filter { $0.card?.id == card.id }
            .filter { $0.expenseDate >= s && $0.expenseDate <= e }
        let plannedIncluded = PlannedExpenseFuturePolicy.filteredForCalculations(
            plannedInRange,
            excludeFuture: excludeFuturePlannedExpenses,
            now: now
        )

        let planned = plannedIncluded
            .reduce(0) { $0 + plannedEffectiveAmount($1) }

        let variableInRange = variableExpenses
            .filter { $0.card?.id == card.id }
            .filter { $0.transactionDate >= s && $0.transactionDate <= e }
        let variableIncluded = VariableExpenseFuturePolicy.filteredForCalculations(
            variableInRange,
            excludeFuture: excludeFutureVariableExpenses,
            now: now
        )

        let variable = variableIncluded
            .reduce(0) { $0 + $1.spendingAmount() }

        return HomeCardMetrics(
            plannedTotal: planned,
            variableTotal: variable,
            total: planned + variable
        )
    }

    private static func plannedEffectiveAmount(_ expense: PlannedExpense) -> Double {
        expense.effectiveAmount()
    }

    private static func normalizedStart(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private static func normalizedEnd(_ date: Date) -> Date {
        let start = Calendar.current.startOfDay(for: date)
        return Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }
}
