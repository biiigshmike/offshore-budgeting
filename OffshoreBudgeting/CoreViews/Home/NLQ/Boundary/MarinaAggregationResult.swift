import Foundation

struct MarinaAggregationResultRow: Codable, Equatable, Identifiable {
    let id: UUID
    let label: String
    let renderedValue: String
    let amount: Double?
    let percentage: Double?

    init(
        id: UUID = UUID(),
        label: String,
        renderedValue: String,
        amount: Double? = nil,
        percentage: Double? = nil
    ) {
        self.id = id
        self.label = label
        self.renderedValue = renderedValue
        self.amount = amount
        self.percentage = percentage
    }
}

struct MarinaScalarAggregationResult: Codable, Equatable {
    let title: String
    let renderedValue: String?
    let amount: Double?
    let rows: [MarinaAggregationResultRow]
    let sourceAnswer: HomeAnswer
}

struct MarinaComparisonAggregationResult: Codable, Equatable {
    let title: String
    let primaryLabel: String
    let primaryRenderedValue: String
    let primaryAmount: Double?
    let comparisonLabel: String
    let comparisonRenderedValue: String
    let comparisonAmount: Double?
    let deltaRenderedValue: String?
    let sourceAnswer: HomeAnswer
}

struct MarinaListAggregationResult: Codable, Equatable {
    let title: String
    let primaryRenderedValue: String?
    let rows: [MarinaAggregationResultRow]
    let sourceAnswer: HomeAnswer
}

struct MarinaMessageAggregationResult: Codable, Equatable {
    let title: String
    let message: String?
    let sourceAnswer: HomeAnswer
}

enum MarinaAggregationResult: Codable, Equatable {
    case scalar(MarinaScalarAggregationResult)
    case comparison(MarinaComparisonAggregationResult)
    case rankedList(MarinaListAggregationResult)
    case groupedBreakdown(MarinaListAggregationResult)
    case message(MarinaMessageAggregationResult)
    case unsupported(MarinaTypedUnsupportedResponse)

    var sourceAnswer: HomeAnswer? {
        switch self {
        case .scalar(let result):
            return result.sourceAnswer
        case .comparison(let result):
            return result.sourceAnswer
        case .rankedList(let result), .groupedBreakdown(let result):
            return result.sourceAnswer
        case .message(let result):
            return result.sourceAnswer
        case .unsupported:
            return nil
        }
    }
}
