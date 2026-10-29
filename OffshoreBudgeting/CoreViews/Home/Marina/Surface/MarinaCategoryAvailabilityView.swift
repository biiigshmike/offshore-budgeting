import SwiftUI

struct MarinaCategoryAvailabilityView: View {
    let categories: [MarinaReport.CategoryAvailability]
    let budgetName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let budgetName {
                Text("Limits from \(budgetName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No budget supplies category limits for this period.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if categories.isEmpty {
                Text("No categories match the requested status.")
                    .foregroundStyle(.secondary)
            }
            ForEach(categories) { category in
                VStack(alignment: .leading, spacing: 6) {
                    CategoryAvailabilityRowView(
                        metric: .init(id: UUID(uuidString: category.id) ?? CategorySpendMetric.uncategorizedID,
                            categoryID: UUID(uuidString: category.id) ?? CategorySpendMetric.uncategorizedID,
                            name: category.name, colorHex: category.colorHex, maxAmount: category.maximum,
                            spentPlanned: category.planned, spentVariable: category.variable),
                        scope: .all, currencyCode: CurrencyFormatter.currencyCode,
                        nearThreshold: HomeCategoryLimitsAggregator.defaultNearThreshold)
                    DisclosureGroup("Category details") {
                        VStack(alignment: .leading, spacing: 8) {
                            if let minimum = category.minimum {
                                LabeledContent("Minimum goal", value: CurrencyFormatter.string(from: minimum))
                            }
                            if let percent = category.percentUsed {
                                LabeledContent("Limit used", value: (percent / 100).formatted(.percent.precision(.fractionLength(0...1))))
                            }
                            LabeledContent("Planned contribution", value: CurrencyFormatter.string(from: category.planned))
                            LabeledContent("Variable contribution", value: CurrencyFormatter.string(from: category.variable))
                        }
                    }
                    .accessibilityLabel("Details for \(category.name)")
                }
            }
        }
    }
}
