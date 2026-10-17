import SwiftUI

/// The common expense layout accepts display values so saved conversations do not
/// depend on live SwiftData records or change when an expense is edited later.
struct SharedExpenseRowContent: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let subtitle: String
    let amount: String
    var categoryColorHex: String?
    var isCredit = false
    var indicatorSymbolName: String?
    var indicatorAccessibilityLabel = ""
    var secondaryAmountSummary: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                Circle()
                    .fill(categoryColorHex.flatMap { Color(hex: $0) } ?? Color.secondary.opacity(0.35))
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                if let indicatorSymbolName {
                    Image(systemName: indicatorSymbolName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(indicatorAccessibilityLabel)
                }
            }
            .frame(width: 12)
            .padding(.top, 6)

            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            layout {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
                    Text(amount)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(isCredit ? .green : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let secondaryAmountSummary {
                        Text(secondaryAmountSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
