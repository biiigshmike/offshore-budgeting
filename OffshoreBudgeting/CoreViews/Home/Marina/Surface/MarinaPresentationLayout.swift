import Foundation

/// Choose the primary visual by the question's operation, not by incidental report metadata.
enum MarinaPresentationLayout: Equatable {
    enum TimelineStyle: Equatable { case spendingBars, pairedBars, movementLines }
    case cardSummary, incomeProgress, budgetPace, spendingPatterns, categoryAvailability
    case timeline, chart, records, metrics, empty

    static let overviewGroupLimit = 3

    static func timelineStyle(for presentation: MarinaPresentation) -> TimelineStyle {
        if presentation.chartIntent == .movementOverTime
            || (presentation.chartIntent == nil && presentation.report?.cumulative == true) {
            return .movementLines
        }
        if presentation.purpose == .spendingPatterns || presentation.topicKey?.hasPrefix("expenses:") == true {
            return .spendingBars
        }
        return .pairedBars
    }

    static func resolve(_ presentation: MarinaPresentation) -> Self {
        if presentation.incomeProgress != nil { return .incomeProgress }
        if presentation.budgetPace != nil { return .budgetPace }
        if presentation.purpose == .cardSummary, presentation.card != nil,
           ["Total", "Planned card spending", "Variable card spending"].allSatisfy({ label in
               presentation.metrics.contains { $0.label == label }
           }) { return .cardSummary }
        if presentation.purpose == .spendingPatterns { return .spendingPatterns }
        if presentation.purpose == .categoryAvailability { return .categoryAvailability }
        if presentation.isEmpty { return .empty }
        if [.ranking, .share, .comparison].contains(presentation.operation) { return .chart }
        if presentation.operation == .trend { return .timeline }
        if [.transactions, .inventory].contains(presentation.operation) { return .records }
        return .metrics
    }
}
