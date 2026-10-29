import Foundation

/// Sources are verified by the compiler. A quoted span proves provenance, not that
/// the model's interpretation of that span is correct.
nonisolated enum MarinaPatchSource: Codable, Equatable, Sendable {
    case userText(String)
    case contextReference(String)
}

nonisolated enum MarinaFieldPatch<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    case keep
    case set(Value, MarinaPatchSource)
    case clear(MarinaPatchSource)
}

nonisolated struct MarinaTurnPatch: Codable, Equatable, Sendable {
    enum Base: Codable, Equatable, Sendable { case newQuestion, active, earlier(String), pending }
    enum TargetField: String, Codable, CaseIterable, Sendable {
        case card, categories, budget, preset, merchant, incomeSource, account, periodBudget
    }
    enum Target: Codable, Equatable, Sendable { case reference(String), name(String) }
    struct TargetChange: Codable, Equatable, Sendable {
        var field: TargetField
        var change: MarinaFieldPatch<[Target]>
    }
    enum DateIntent: Codable, Equatable, Sendable {
        case relative(MarinaDataRequest.RelativePeriod)
        case range(start: String, end: String)
        case month(year: Int?, month: Int)
        case year(Int)
        case allTime
        case query(String)
        case budget(String)
    }

    var base: Base
    var capability: MarinaFieldPatch<MarinaCapability> = .keep
    var targets: [TargetChange] = []
    var comparisonTargets: [TargetChange] = []
    var dates: MarinaFieldPatch<DateIntent> = .keep
    var comparisonDates: MarinaFieldPatch<DateIntent> = .keep
    var metric: MarinaFieldPatch<MarinaDataRequest.MetricFocus> = .keep
    var measure: MarinaFieldPatch<MarinaDataRequest.ExpenseMeasure> = .keep
    var scope: MarinaFieldPatch<MarinaDataRequest.Scope> = .keep
    var state: MarinaFieldPatch<MarinaDataRequest.State> = .keep
    var grouping: MarinaFieldPatch<MarinaDataRequest.Grouping> = .keep
    var sort: MarinaFieldPatch<MarinaDataRequest.Sort> = .keep
    var limit: MarinaFieldPatch<Int> = .keep
    var periodUnit: MarinaFieldPatch<MarinaDataRequest.PeriodUnit> = .keep
    var chartIntent: MarinaFieldPatch<MarinaDataRequest.ChartIntent> = .keep
    var transactionFilter: MarinaFieldPatch<MarinaDataRequest.TransactionFilter> = .keep
    var availabilityFilter: MarinaFieldPatch<MarinaDataRequest.AvailabilityFilter> = .keep
    var includeFuture: MarinaFieldPatch<Bool> = .keep
    var recordKind: MarinaFieldPatch<String> = .keep
}
