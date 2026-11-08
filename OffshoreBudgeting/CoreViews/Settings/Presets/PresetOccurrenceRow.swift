import SwiftUI

struct PresetOccurrenceRow: View {
    let occurrence: PresetDetailCalculator.Occurrence
    let budgetName: String?
    let now: Date
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            layout {
                Text(occurrence.date, format: .dateTime.month(.abbreviated).day().year())
                    .font(.headline)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                if let effective = occurrence.effectiveAmount(now: now) {
                    Text(effective, format: CurrencyFormatter.currencyStyle())
                } else {
                    Text("Not recorded").foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
            if occurrence.isAssumed(now: now) {
                Text("Assumed as planned").foregroundStyle(.secondary)
            } else if occurrence.recordedAmount != nil {
                Text("Recorded").foregroundStyle(.secondary)
            }
            Text(budgetName ?? String(localized: "Budget unavailable"))
                .foregroundStyle(.secondary)
            LabeledContent("Planned") {
                Text(occurrence.plannedAmount, format: CurrencyFormatter.currencyStyle())
            }
            if let variance = occurrence.effectiveVariance(now: now) {
                LabeledContent("Variance") {
                    Text(variance, format: CurrencyFormatter.currencyStyle())
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(.primary)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
