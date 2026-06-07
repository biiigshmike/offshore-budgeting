import Foundation

enum MarinaFormulaMetricComponent: String, Codable, Equatable, Sendable {
    case spentSoFar
    case elapsedDays
    case averagePerDay
    case projectedTotal
    case expectedByNow
    case paceDifference
    case income
    case plannedExpenses
    case coveragePercent
    case difference
}

enum MarinaFormulaValueStyle: String, Codable, Equatable, Sendable {
    case automatic
    case money
    case integer
    case percent
    case deltaMoney
}

struct MarinaFormulaMetricDetail: Equatable, Sendable {
    let component: MarinaFormulaMetricComponent
    let value: MarinaValue
    let style: MarinaFormulaValueStyle

    init(
        _ component: MarinaFormulaMetricComponent,
        value: MarinaValue,
        style: MarinaFormulaValueStyle = .automatic
    ) {
        self.component = component
        self.value = value
        self.style = style
    }
}

struct MarinaBudgetFormulaProgress: Equatable, Sendable {
    let elapsedDays: Int
    let totalDays: Int
    let remainingDays: Int
    let elapsedPercent: Double
}

struct MarinaBudgetFormulaInputs: Equatable, Sendable {
    let progress: MarinaBudgetFormulaProgress
    let actualSpendToDate: Double
    let plannedSpend: Double
    let coverageIncome: Double
}

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

    static func inputs(
        snapshot: MarinaWorkspaceSnapshot,
        range: HomeQueryDateRange,
        now: Date,
        calendar: Calendar
    ) -> MarinaBudgetFormulaInputs {
        MarinaBudgetFormulaInputs(
            progress: dayProgress(for: range, now: now, calendar: calendar),
            actualSpendToDate: actualSpendToDate(snapshot: snapshot, range: range, now: now, calendar: calendar),
            plannedSpend: plannedExpenseTotal(snapshot: snapshot, range: range),
            coverageIncome: coverageIncome(snapshot: snapshot, range: range)
        )
    }

    static func actualSpendToDate(
        snapshot: MarinaWorkspaceSnapshot,
        range: HomeQueryDateRange,
        now: Date,
        calendar: Calendar
    ) -> Double {
        let rangeStart = calendar.startOfDay(for: range.startDate)
        let rangeEnd = calendar.startOfDay(for: range.endDate)
        let today = calendar.startOfDay(for: now)

        guard today >= rangeStart else { return 0 }

        let clampedEnd = min(today, rangeEnd)
        let spendRange = HomeQueryDateRange(startDate: range.startDate, endDate: endOfDay(clampedEnd, calendar: calendar))
        return totalSpend(snapshot: snapshot, range: spendRange)
    }

    static func totalSpend(
        snapshot: MarinaWorkspaceSnapshot,
        range: HomeQueryDateRange?
    ) -> Double {
        expenseRows(snapshot: snapshot, scope: .unified, range: range).reduce(0.0) { $0 + $1.budgetImpact }
    }

    static func plannedExpenseTotal(
        snapshot: MarinaWorkspaceSnapshot,
        range: HomeQueryDateRange?,
        recurringOnly: Bool = false
    ) -> Double {
        snapshot.homeCalculationPlannedExpenses
            .filter { contains($0.expenseDate, in: range) }
            .filter { recurringOnly == false || $0.sourcePresetID != nil }
            .reduce(0.0) { total, expense in
                total + SavingsMathService.plannedProjectedBudgetImpactAmount(for: expense)
            }
    }

    static func coverageIncome(
        snapshot: MarinaWorkspaceSnapshot,
        range: HomeQueryDateRange?
    ) -> Double {
        let actualIncome = incomeTotal(snapshot.incomes, range: range, state: .actual, source: nil)
        if actualIncome > 0 {
            return actualIncome
        }
        return incomeTotal(snapshot.incomes, range: range, state: .planned, source: nil)
    }

    static func dayProgress(
        for range: HomeQueryDateRange,
        now: Date,
        calendar: Calendar
    ) -> MarinaBudgetFormulaProgress {
        let start = calendar.startOfDay(for: range.startDate)
        let end = calendar.startOfDay(for: range.endDate)
        let today = calendar.startOfDay(for: now)
        let totalDays = inclusiveDayCount(from: start, through: end, calendar: calendar)

        let elapsedDays: Int
        if today < start {
            elapsedDays = 0
        } else if today > end {
            elapsedDays = totalDays
        } else {
            elapsedDays = inclusiveDayCount(from: start, through: today, calendar: calendar)
        }

        let remainingDays: Int
        if today < start {
            remainingDays = totalDays
        } else if today > end {
            remainingDays = 0
        } else {
            remainingDays = inclusiveDayCount(from: today, through: end, calendar: calendar)
        }

        let elapsedPercent = totalDays > 0 ? Double(elapsedDays) / Double(totalDays) : 0
        return MarinaBudgetFormulaProgress(
            elapsedDays: elapsedDays,
            totalDays: totalDays,
            remainingDays: remainingDays,
            elapsedPercent: elapsedPercent
        )
    }

    private static func expenseRows(
        snapshot: MarinaWorkspaceSnapshot,
        scope: MarinaSemanticExpenseScope,
        range: HomeQueryDateRange?
    ) -> [BudgetFormulaExpenseRow] {
        var rows: [BudgetFormulaExpenseRow] = []

        if scope == .planned || scope == .unified {
            for expense in snapshot.homeCalculationPlannedExpenses where contains(expense.expenseDate, in: range) {
                rows.append(
                    BudgetFormulaExpenseRow(
                        budgetImpact: SavingsMathService.plannedBudgetImpactAmount(for: expense)
                    )
                )
            }
        }

        if scope == .variable || scope == .unified {
            for expense in snapshot.homeCalculationVariableExpenses where contains(expense.transactionDate, in: range) {
                rows.append(
                    BudgetFormulaExpenseRow(
                        budgetImpact: SavingsMathService.variableBudgetImpactAmount(for: expense)
                    )
                )
            }
        }

        return rows
    }

    private static func incomeTotal(
        _ incomes: [Income],
        range: HomeQueryDateRange?,
        state: MarinaSemanticIncomeState,
        source: String?
    ) -> Double {
        incomes
            .filter { contains($0.date, in: range) }
            .filter { income in
                switch state {
                case .planned:
                    return income.isPlanned
                case .actual:
                    return income.isPlanned == false
                case .all:
                    return true
                }
            }
            .filter { income in
                guard let source else { return true }
                return normalize(income.source) == normalize(source)
            }
            .reduce(0.0) { $0 + $1.amount }
    }

    private static func contains(_ date: Date, in range: HomeQueryDateRange?) -> Bool {
        guard let range else { return true }
        return date >= range.startDate && date <= range.endDate
    }

    private static func inclusiveDayCount(from start: Date, through end: Date, calendar: Calendar) -> Int {
        guard end >= start else { return 0 }
        return (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
    }

    private static func endOfDay(_ date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

private struct BudgetFormulaExpenseRow {
    let budgetImpact: Double
}
