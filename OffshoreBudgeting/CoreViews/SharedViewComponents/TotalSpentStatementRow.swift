import SwiftUI

struct TotalSpentStatementRow: View {
    let total: Double
    let heatMapStops: [Gradient.Stop]

    private let cornerRadius: CGFloat = 14

    var body: some View {
        ZStack(alignment: .leading) {

            // Background that fills the entire row
            HeatMapSpendingBar(stops: heatMapStops)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .accessibilityHidden(true)

            // Foreground content
            VStack(alignment: .leading, spacing: 6) {
                Text(total, format: CurrencyFormatter.currencyStyle())
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 72)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Total Spent")
        .accessibilityValue(Text(total, format: CurrencyFormatter.currencyStyle()))
    }
}

