import SwiftUI

/// Presentation only: callers decide whether the row navigates (onboarding does not).
struct PresetRowContent: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let plannedAmount: Double
    let scheduleText: String
    let assignedBudgetsCount: Int
    var dueDate: Date? = nil
    var occurrenceAmount: Double? = nil

    private var primaryLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            primaryLayout {
                Text(title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                Text(plannedAmount, format: CurrencyFormatter.currencyStyle())
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.primary)

            Text(scheduleText)
                .fixedSize(horizontal: false, vertical: true)
            Text("Assigned Budgets: \(assignedBudgetsCount)")

            if let dueDate {
                Text("Due \(AppDateFormat.abbreviatedDate(dueDate))")
                if let occurrenceAmount {
                    Text(occurrenceAmount, format: CurrencyFormatter.currencyStyle())
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
