#if DEBUG
import SwiftUI

/// Uses immutable display values; no live workspace or financial store is touched by these previews.
/// Toggle Increase Contrast using the preview's accessibility environment controls.
struct SpendTrendsSatinAppPreviewGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(SpendTrendsSatinPreviewFixtures.appScenarios.indices, id: \.self) { scenarioIndex in
                    let scenario = SpendTrendsSatinPreviewFixtures.appScenarios[scenarioIndex]
                    let buckets = scenario.snapshot.buckets.map { bucket in
                        HomeSpendTrendBucket(
                            id: bucket.id, label: bucket.label, total: bucket.total,
                            slices: bucket.slices.map { HomeSpendTrendSlice(name: $0.name, hexColor: $0.hexColor, amount: $0.amount) }
                        )
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text(scenario.name).font(.headline)
                        Text("Home · existing 12-bucket coverage").font(.subheadline).foregroundStyle(.secondary)
                        HomeSpendTrendChart(buckets: Array(buckets.prefix(12)))
                        Text("Detail proportions · first bar selected").font(.subheadline).foregroundStyle(.secondary)
                        GeometryReader { geo in
                            let slotWidth = geo.size.width / CGFloat(max(5, buckets.count))
                            let maximum = max(1, buckets.map(\.total).max() ?? 1)
                            HStack(alignment: .bottom, spacing: 0) {
                                ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                                    if bucket.total > 0 {
                                        SpendTrendsSatinBar(
                                            segments: bucket.slices.map { slice in
                                                SpendTrendsBarSegment(amount: slice.amount, color: slice.hexColor.flatMap { Color(hex: $0) } ?? .secondary)
                                            },
                                            width: SpendTrendsBarStyle.detailWidth(slotWidth: slotWidth),
                                            height: max(2, 240 * CGFloat(bucket.total / maximum)),
                                            isSelected: index == 0
                                        )
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                                    } else {
                                        Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                                    }
                                }
                            }
                        }
                        .frame(height: 240)
                    }
                    .padding(16)
                    .background(.background, in: RoundedRectangle(cornerRadius: 20))
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Edge treatments").font(.headline)
                    HStack(alignment: .bottom, spacing: 32) {
                        VStack {
                            SpendTrendsSatinBar(segments: [.init(amount: 1, color: .secondary)], width: 24, height: 80)
                            Text("Uncategorized")
                        }
                        VStack {
                            SpendTrendsSatinBar(segments: [.init(amount: 0.75, color: .orange)], width: 24, height: 2)
                            Text("$0.75")
                        }
                        VStack {
                            SpendTrendsSatinBar(segments: [.init(amount: 8, color: .purple), .init(amount: 2, color: .orange)], width: 36, height: 100, isSelected: true)
                            Text("Selected")
                        }
                    }
                    .font(.caption)
                }
                .padding(16)
                .background(.background, in: RoundedRectangle(cornerRadius: 20))
            }
            .padding(16)
        }
        .background(.secondary.opacity(0.12))
    }
}

#Preview("Satin App Periods · Light") {
    SpendTrendsSatinAppPreviewGallery()
        .frame(width: 390, height: 1000)
        .preferredColorScheme(.light)
}

#Preview("Satin App Periods · Dark") {
    SpendTrendsSatinAppPreviewGallery()
        .frame(width: 390, height: 1000)
        .preferredColorScheme(.dark)
}

/// Runs the real metric chart, hit targets, and expense breakdown using detached preview models.
/// The models are never inserted into a ModelContext or persisted.
@MainActor
struct SpendTrendsSatinMetricPreview: View {
    private let workspace: Workspace
    private let cards: [Card]
    private let categories: [Category]
    private let expenses: [VariableExpense]
    private let startDate: Date
    private let endDate: Date

    init() {
        let workspace = Workspace(id: Self.id(1), name: "Personal Preview", hexColor: "#007D97")
        let card = Card(id: Self.id(2), name: "AmEx", theme: "aqua", effect: "plastic", workspace: workspace)
        let categoryValues = [
            ("Bills & Utilities", "#007D97"),
            ("Food & Drink", "#FF9500"),
            ("Subscriptions", "#FF88D8"),
            ("Shopping", "#9135FF"),
            ("Travel", "#397AFF")
        ]
        let categories = categoryValues.enumerated().map { index, value in
            Category(id: Self.id(10 + index), name: value.0, hexColor: value.1, workspace: workspace)
        }
        let amounts: [(day: Int, values: [Double])] = [
            (2, [1200, 200, 80, 40, 19.52]),
            (14, [600, 250, 180, 100, 50]),
            (21, [200, 440, 100, 300, 0]),
            (28, [240, 240, 80, 180, 40])
        ]
        var expenses: [VariableExpense] = []
        for (bucketIndex, bucket) in amounts.enumerated() {
            for (categoryIndex, amount) in bucket.values.enumerated() where amount > 0 {
                expenses.append(VariableExpense(
                    id: Self.id(100 + bucketIndex * 10 + categoryIndex),
                    descriptionText: "Preview \(categories[categoryIndex].name)",
                    amount: amount,
                    transactionDate: Self.date(bucket.day),
                    workspace: workspace,
                    card: card,
                    category: categories[categoryIndex]
                ))
            }
        }
        expenses.append(VariableExpense(
            id: Self.id(200), descriptionText: "Preview small purchase", amount: 0.75,
            transactionDate: Self.date(7), workspace: workspace, card: card, category: nil
        ))
        self.workspace = workspace
        self.cards = [card]
        self.categories = categories
        self.expenses = expenses
        self.startDate = Self.date(1)
        self.endDate = Self.date(31)
    }

    var body: some View {
        NavigationStack {
            HomeSpendTrendsMetricsView(
                workspace: workspace, cards: cards, categories: categories,
                plannedExpenses: [], variableExpenses: expenses,
                startDate: startDate, endDate: endDate, initialPeriod: .period
            )
        }
    }

    private static func date(_ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12))!
    }

    private static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}

#Preview("Satin Metric · Interactive Month Light") {
    SpendTrendsSatinMetricPreview()
        .preferredColorScheme(.light)
}

#Preview("Satin Metric · Interactive Month Dark") {
    SpendTrendsSatinMetricPreview()
        .preferredColorScheme(.dark)
}

#endif
