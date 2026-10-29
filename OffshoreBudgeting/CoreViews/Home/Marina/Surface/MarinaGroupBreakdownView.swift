import SwiftUI

/// Compact Home category rows by default; contribution detail is shown only on request.
struct MarinaGroupBreakdownView: View {
    let title: String?
    let groups: [MarinaReport.Group]
    var previewLimit: Int? = nil
    var showsDetails = false

    private var visibleGroups: [MarinaReport.Group] {
        previewLimit.map { Array(groups.prefix($0)) } ?? groups
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if visibleGroups.isEmpty {
                Text("No matching spending in this period.").foregroundStyle(.secondary)
            }
            ForEach(visibleGroups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    CategoryMetricRowView(name: group.title,
                        color: group.colorHex.flatMap { Color(hex: $0) } ?? .secondary,
                        amountText: CurrencyFormatter.string(from: group.amount),
                        percentValue: (group.sharePercent ?? 0) / 100,
                        showsProgressBar: false, showsPercentage: group.sharePercent != nil,
                        clampsPercentageText: false)
                    if showsDetails {
                        if let planned = group.plannedAmount, let variable = group.variableAmount {
                            LabeledContent("Planned", value: CurrencyFormatter.string(from: planned))
                            LabeledContent("Variable", value: CurrencyFormatter.string(from: variable))
                        }
                        if let count = group.count {
                            Text("\(count) \(count == 1 ? "transaction" : "transactions")")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                if group.id != visibleGroups.last?.id { Divider() }
            }
        }
    }
}
