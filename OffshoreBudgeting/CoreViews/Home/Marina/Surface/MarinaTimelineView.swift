import SwiftUI

/// Home period bars are the default. Movement requests and cumulative savings use shared
/// line rendering, while all underlying values remain available through a collapsed table.
struct MarinaTimelineView: View {
    let presentation: MarinaPresentation

    private var series: [HomeFinancialChartSeries] {
        if let series = presentation.report?.series, !series.isEmpty {
            return series.map { item in
                .init(id: item.id, label: item.label, points: item.points.map {
                    .init(id: $0.id, label: $0.label, value: $0.value, date: $0.date)
                })
            }
        }
        return [.init(id: "amount", label: presentation.title, points: presentation.chartPoints.map {
            .init(id: $0.id, label: $0.label, value: $0.value, date: $0.date)
        })]
    }

    private var periods: [String] {
        var seen = Set<String>()
        return series.flatMap(\.points).map(\.id).filter { seen.insert($0).inserted }
    }

    private var spendingBuckets: [HomeSpendTrendBucket] {
        if !presentation.chartPoints.isEmpty {
            let points = presentation.chartPoints
            let ordered = points.allSatisfy({ $0.date != nil })
                ? points.sorted { ($0.date ?? "") < ($1.date ?? "") } : points
            return ordered.map { point in
                .init(id: point.id, label: point.label, total: point.value,
                    slices: point.slices?.map { .init(name: $0.name, hexColor: $0.colorHex, amount: $0.amount) }
                        ?? [.init(name: "Spending", hexColor: point.colorHex, amount: point.value)])
            }
        }
        return (series.first?.points ?? []).map {
            .init(id: $0.id, label: $0.label, total: $0.value,
                  slices: [.init(name: "Spending", hexColor: nil, amount: $0.value)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if presentation.report?.cumulative == true {
                Text("Cumulative amounts within this period")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            switch MarinaPresentationLayout.timelineStyle(for: presentation) {
            case .movementLines:
                HomeFinancialSeriesChart(series: series, style: .lines)
            case .spendingBars:
                HomeSpendTrendChart(buckets: spendingBuckets)
            case .pairedBars:
                HomeFinancialSeriesChart(series: series, style: .bars)
            }

            DisclosureGroup("Period values") {
                ForEach(periods, id: \.self) { period in
                    VStack(alignment: .leading, spacing: 6) {
                        if let point = series.lazy.flatMap(\.points).first(where: { $0.id == period }) {
                            Text(point.label).font(.subheadline.weight(.semibold))
                        }
                        ForEach(series) { item in
                            if let point = item.points.first(where: { $0.id == period }) {
                                LabeledContent(item.label, value: CurrencyFormatter.string(from: point.value))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
