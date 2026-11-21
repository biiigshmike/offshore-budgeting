import SwiftUI

struct PresetGalleryContent: View {
    let preset: Preset
    let assignedBudgetsCount: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(preset.title)
                .font(.headline)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .accessibilityLabel(Text(preset.title))
            Text(preset.plannedAmount, format: CurrencyFormatter.currencyStyle())
                .font(.title3.bold())
                .fixedSize(horizontal: false, vertical: true)
            Text(PresetScheduleFormatter.humanReadableSchedule(for: preset))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Group {
                if assignedBudgetsCount == 1 {
                    Text("1 budget")
                } else {
                    Text("\(assignedBudgetsCount) budgets")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .combine)
    }
}
