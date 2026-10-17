import Foundation

struct HomeSpendTrendBucket: Identifiable {
    let id: String
    let label: String
    let total: Double
    let slices: [HomeSpendTrendSlice]

    init(id: String, label: String, total: Double, slices: [HomeSpendTrendSlice]) {
        self.id = id
        self.label = label
        self.total = total
        self.slices = slices
    }

    init(_ bucket: HomeSpendTrendsAggregator.Bucket) {
        self.init(id: bucket.id, label: bucket.label, total: bucket.total,
                  slices: bucket.slices.map { HomeSpendTrendSlice(name: $0.name, hexColor: $0.hexColor, amount: $0.amount) })
    }
}
