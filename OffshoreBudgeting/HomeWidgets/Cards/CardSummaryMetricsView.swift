import SwiftUI

struct CardSummaryMetricsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let total: Double
    let planned: Double
    let variable: Double

    private var rows: [(String, Double)] {
        [(String(localized: "common.total", defaultValue: "Total"), total),
         (String(localized: "common.planned", defaultValue: "Planned"), planned),
         (String(localized: "common.variable", defaultValue: "Variable"), variable)]
    }

    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 10))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows.indices, id: \.self) { index in
                layout {
                    Text(rows[index].0).font(.subheadline).foregroundStyle(.secondary)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                    Text(rows[index].1, format: CurrencyFormatter.currencyStyle())
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .minimumScaleFactor(0.82)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
