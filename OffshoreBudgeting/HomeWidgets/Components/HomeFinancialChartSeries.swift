import Foundation

/// Immutable chart values shared by financial summary surfaces.
struct HomeFinancialChartSeries: Identifiable {
    struct Point: Identifiable {
        let id: String
        let label: String
        let value: Double
        /// ISO calendar date supplied by the calculation; never inferred from the label.
        var date: String? = nil
    }

    let id: String
    let label: String
    let points: [Point]

    init(id: String, label: String, points: [Point]) {
        self.id = id
        self.label = label
        if points.allSatisfy({ $0.date != nil }) {
            self.points = points.enumerated().sorted { lhs, rhs in
                let left = lhs.element.date ?? "", right = rhs.element.date ?? ""
                return left == right ? lhs.offset < rhs.offset : left < right
            }.map(\.element)
        } else {
            // Older saved charts contain labels only; their existing order is authoritative.
            self.points = points
        }
    }
}
