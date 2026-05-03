import Foundation

struct MarinaAggregationResponseBridge {
    func responseCompatibleAnswer(from result: MarinaAggregationResult) -> HomeAnswer {
        switch result {
        case .scalar(let result):
            return result.sourceAnswer
        case .comparison(let result):
            return result.sourceAnswer
        case .rankedList(let result), .groupedBreakdown(let result):
            return result.sourceAnswer
        case .message(let result):
            return result.sourceAnswer
        case .unsupported(let unsupported):
            return HomeAnswer(
                queryID: unsupported.id,
                kind: .message,
                title: "Unsupported Marina Query",
                subtitle: unsupported.message,
                primaryValue: nil,
                rows: [
                    HomeAnswerRow(title: "Reason", value: unsupported.kind.rawValue)
                ]
            )
        }
    }

    func summary(from result: MarinaAggregationResult) -> String {
        let answer = responseCompatibleAnswer(from: result)
        let primary = answer.primaryValue.map { " primary=\($0)" } ?? ""
        let rows = answer.rows.isEmpty ? "" : " rows=\(answer.rows.count)"
        return "\(answer.kind.rawValue): \(answer.title)\(primary)\(rows)"
    }
}
