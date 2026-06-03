import Foundation

enum MarinaBudgetFormulaCalculator {
    static func burnRate(actualSpend: Double, elapsedDays: Int) -> Double? {
        guard elapsedDays > 0 else { return nil }
        return actualSpend / Double(elapsedDays)
    }

    static func projectedSpend(burnRate: Double, totalDays: Int) -> Double? {
        guard totalDays > 0 else { return nil }
        return burnRate * Double(totalDays)
    }

    static func safeDailySpend(remainingRoom: Double, remainingDays: Int) -> Double? {
        guard remainingDays > 0 else { return nil }
        return remainingRoom / Double(remainingDays)
    }

    static func paceDifference(actualSpend: Double, plannedSpend: Double, elapsedPercent: Double) -> Double? {
        guard elapsedPercent.isFinite, elapsedPercent >= 0 else { return nil }
        return actualSpend - (plannedSpend * elapsedPercent)
    }

    static func coverageRatio(income: Double, plannedExpenses: Double) -> Double? {
        guard plannedExpenses > 0 else { return nil }
        return income / plannedExpenses
    }

    static func recurringBurden(recurringTotal: Double, plannedExpenseTotal: Double) -> Double? {
        guard plannedExpenseTotal > 0 else { return nil }
        return recurringTotal / plannedExpenseTotal
    }

    static func concentration(partTotal: Double, wholeTotal: Double) -> Double? {
        guard wholeTotal > 0 else { return nil }
        return partTotal / wholeTotal
    }
}
