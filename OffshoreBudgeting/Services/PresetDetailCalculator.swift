import Foundation

/// Read-only occurrence analytics. Inputs deliberately contain no SwiftData relationships.
enum PresetDetailCalculator {
    struct Occurrence: Identifiable {
        let id: UUID
        let workspaceID: UUID?
        let sourcePresetID: UUID?
        let sourceBudgetID: UUID?
        let date: Date
        let plannedAmount: Double
        let actualAmount: Double

        var recordedAmount: Double? { actualAmount > 0 ? actualAmount : nil }
        var variance: Double? { recordedAmount.map { $0 - plannedAmount } }

        func isAssumed(now: Date = .now, calendar: Calendar = .current) -> Bool {
            actualAmount == 0 && calendar.startOfDay(for: date) < calendar.startOfDay(for: now)
        }

        func effectiveAmount(now: Date = .now, calendar: Calendar = .current) -> Double? {
            recordedAmount ?? (isAssumed(now: now, calendar: calendar) ? plannedAmount : nil)
        }

        func effectiveVariance(now: Date = .now, calendar: Calendar = .current) -> Double? {
            effectiveAmount(now: now, calendar: calendar).map { $0 - plannedAmount }
        }
    }

    struct PeriodTotal: Identifiable {
        var id: Date { startDate }
        let startDate: Date
        let endDate: Date
        let plannedAmount: Double
        let effectiveAmount: Double
        let recordedCount: Int
        let assumedCount: Int
        var includedCount: Int { recordedCount + assumedCount }
    }

    struct Result {
        let history: [Occurrence]
        let periods: [PeriodTotal]
        let recordedCount: Int
        let assumedCount: Int
        var includedCount: Int { recordedCount + assumedCount }
        let plannedTotal: Double
        let effectiveTotal: Double
        let totalVariance: Double
        let averageEffectiveAmount: Double?
        let averageVariance: Double?
        let abovePlanCount: Int
        let belowPlanCount: Int
        let onPlanCount: Int
        let hiddenFutureCount: Int
    }

    /// A useful history window, extended only when all eligible history predates it.
    static func initialRange(
        workspaceID: UUID,
        presetID: UUID,
        occurrences: [Occurrence],
        grouping: BudgetingPeriod = .monthly,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        let today = calendar.startOfDay(for: now)
        let currentStart = grouping.defaultRange(containing: today, calendar: calendar).start
        let component: Calendar.Component
        let offset: Int
        switch grouping {
        case .daily: (component, offset) = (.day, -29)
        case .weekly: (component, offset) = (.weekOfYear, -11)
        case .monthly: (component, offset) = (.month, -11)
        case .quarterly: (component, offset) = (.month, -21)
        case .yearly: (component, offset) = (.year, -4)
        }
        let defaultStart = calendar.date(byAdding: component, value: offset, to: currentStart) ?? currentStart
        let eligible = occurrences.filter {
            $0.workspaceID == workspaceID && $0.sourcePresetID == presetID
                && !PlannedExpenseFuturePolicy.isFutureDate($0.date, now: now, calendar: calendar)
                && $0.effectiveAmount(now: now, calendar: calendar) != nil
        }
        guard !eligible.contains(where: { $0.date >= defaultStart }),
              let latestOlder = eligible.map(\.date).max() else {
            return (defaultStart, today)
        }
        let olderStart = grouping.defaultRange(containing: latestOlder, calendar: calendar).start
        return (olderStart, today)
    }

    static func calculate(
        workspaceID: UUID,
        presetID: UUID,
        occurrences: [Occurrence],
        startDate: Date,
        endDate: Date,
        grouping: BudgetingPeriod = .monthly,
        hideFuturePlanned: Bool = false,
        excludeFuturePlanned: Bool = false,
        currencyCode: String = "USD",
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Result {
        let start = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDate
        let scoped = occurrences.filter {
            $0.workspaceID == workspaceID && $0.sourcePresetID == presetID
                && $0.date >= start && $0.date < endExclusive
        }
        let visible = scoped.filter {
            !hideFuturePlanned || !PlannedExpenseFuturePolicy.isFutureDate($0.date, now: now, calendar: calendar)
        }
        let included = scoped.filter {
            $0.effectiveAmount(now: now, calendar: calendar) != nil
                && (!excludeFuturePlanned || !PlannedExpenseFuturePolicy.isFutureDate($0.date, now: now, calendar: calendar))
        }
        let recordedCount = included.filter { $0.recordedAmount != nil }.count
        let plannedTotal = included.reduce(0) { $0 + $1.plannedAmount }
        let effectiveTotal = included.reduce(0) { $0 + ($1.effectiveAmount(now: now, calendar: calendar) ?? 0) }
        let totalVariance = effectiveTotal - plannedTotal

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.currencyCode = currencyCode
        let factor = pow(10, Double(max(0, min(formatter.maximumFractionDigits, 6))))
        var above = 0
        var below = 0
        for occurrence in included {
            let planned = (occurrence.plannedAmount * factor).rounded()
            let actual = ((occurrence.effectiveAmount(now: now, calendar: calendar) ?? 0) * factor).rounded()
            if actual > planned { above += 1 }
            if actual < planned { below += 1 }
        }

        let grouped = Dictionary(grouping: included) {
            grouping.defaultRange(containing: $0.date, calendar: calendar).start
        }
        let periods = grouped.map { start, values in
            PeriodTotal(
                startDate: start,
                endDate: grouping.defaultRange(containing: start, calendar: calendar).end,
                plannedAmount: values.reduce(0) { $0 + $1.plannedAmount },
                effectiveAmount: values.reduce(0) { $0 + ($1.effectiveAmount(now: now, calendar: calendar) ?? 0) },
                recordedCount: values.filter { $0.recordedAmount != nil }.count,
                assumedCount: values.filter { $0.isAssumed(now: now, calendar: calendar) }.count
            )
        }.sorted { $0.startDate < $1.startDate }

        return Result(
            history: visible.sorted {
                if $0.date == $1.date { return $0.id.uuidString < $1.id.uuidString }
                return $0.date > $1.date
            },
            periods: periods,
            recordedCount: recordedCount,
            assumedCount: included.count - recordedCount,
            plannedTotal: plannedTotal,
            effectiveTotal: effectiveTotal,
            totalVariance: totalVariance,
            averageEffectiveAmount: included.isEmpty ? nil : effectiveTotal / Double(included.count),
            averageVariance: included.isEmpty ? nil : totalVariance / Double(included.count),
            abovePlanCount: above,
            belowPlanCount: below,
            onPlanCount: included.count - above - below,
            hiddenFutureCount: scoped.count - visible.count
        )
    }
}
