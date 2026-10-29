import SwiftUI

/// A bounded overview of the verified report; supporting datasets stay in the snapshot.
struct MarinaSpendingPatternsView: View {
    let presentation: MarinaPresentation
    var onPeakTransactions: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let metric = presentation.metrics.first {
                MarinaMetricView(metric: metric, prominent: true)
            }
            MarinaTimelineView(presentation: presentation)
            if let report = presentation.report {
                if let peak = report.peak {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Highest spending period")
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(periodLabel(for: peak))
                            .font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(CurrencyFormatter.string(from: peak.amount))
                            .font(.headline).monospacedDigit()
                        if let category = peak.leadingCategory, let amount = peak.leadingCategoryAmount {
                            Text("\(category) contributed \(CurrencyFormatter.string(from: amount)).")
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    if peak.drilldownRequest != nil, let onPeakTransactions {
                        Button("View peak period transactions", action: onPeakTransactions)
                            .buttonStyle(.bordered)
                            .accessibilityHint("Reads current expenses for this period without changing the saved report")
                    }
                }
                if let groups = report.groups, !groups.isEmpty {
                    MarinaGroupBreakdownView(title: "Leading categories", groups: groups,
                                             previewLimit: MarinaPresentationLayout.overviewGroupLimit)
                }
                if let merchants = report.merchants, !merchants.isEmpty {
                    MarinaGroupBreakdownView(title: "Leading merchants", groups: merchants,
                                             previewLimit: MarinaPresentationLayout.overviewGroupLimit)
                }
                MarinaReportView(report: report, purpose: presentation.purpose)
            }
        }
    }

    private func periodLabel(for peak: MarinaReport.Peak) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        func label(_ value: String) -> String {
            formatter.date(from: value)?.formatted(date: .abbreviated, time: .omitted) ?? value
        }
        if peak.startDate == peak.endDate { return label(peak.startDate) }
        return "\(label(peak.startDate)) through \(label(peak.endDate))"
    }
}
