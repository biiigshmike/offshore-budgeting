import SwiftUI

struct PresetRowContent: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var rowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
    }

    let title: String
    let plannedAmount: Double
    let scheduleText: String
    let assignedBudgetsCount: Int
    var dueDate: Date? = nil
    var occurrenceAmount: Double? = nil

    private var plannedText: String {
        plannedAmount.formatted(CurrencyFormatter.currencyStyle())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            rowLayout {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)

                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }

                HStack(spacing: 10) {
                    Text("Assigned Budgets")
                        .fixedSize(horizontal: false, vertical: true)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(localizedInt(assignedBudgetsCount))
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.secondary.opacity(0.18)))
                        .accessibilityHidden(true)
                }
            }

            rowLayout {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PLANNED")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(plannedText)
                        .font(.body.weight(.semibold))
                }

                if !dynamicTypeSize.isAccessibilitySize { Spacer() }

                VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 4) {
                    Text("SCHEDULE")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(scheduleText)
                        .font(.body.weight(.semibold))
                }
            }
            if let dueDate {
                rowLayout {
                    Text("Due \(AppDateFormat.abbreviatedDate(dueDate))")
                    if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                    if let occurrenceAmount {
                        Text(occurrenceAmount, format: CurrencyFormatter.currencyStyle())
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let budgetPhrase = assignedBudgetsCount == 1 ? "one budget" : "\(localizedInt(assignedBudgetsCount)) budgets"
        let dueText = dueDate.map { " Due \(AppDateFormat.abbreviatedDate($0))." } ?? ""
        let amountText = occurrenceAmount.map { " Scheduled amount \($0.formatted(CurrencyFormatter.currencyStyle()))." } ?? ""
        return "\(title) preset. Planned \(plannedText). Runs \(scheduleText). Assigned to \(budgetPhrase)." + dueText + amountText
    }

    private func localizedInt(_ value: Int) -> String {
        AppNumberFormat.integer(value)
    }
}

