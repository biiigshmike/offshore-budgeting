import SwiftUI

/// A result is rendered from the executed tool's operation and immutable values.
/// Navigation and editing intentionally remain outside the conversation visuals.
struct MarinaPresentationView: View {
    let presentation: MarinaPresentation
    var onShowMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(presentation.scopeLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if presentation.isUpdated {
                    Label("Updated with your latest records", systemImage: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let card = presentation.card, presentation.operation == .summary {
                CardVisualView(
                    title: card.name,
                    theme: CardThemeOption(rawValue: card.theme) ?? .ruby,
                    effect: CardEffectOption(rawValue: card.effect) ?? .plastic,
                    minHeight: nil,
                    showsShadow: false
                )
                .frame(maxWidth: 300)
            }

            if let income = presentation.incomeProgress {
                HomeIncomeProgressContent(actualTotal: income.actual, plannedTotal: income.planned)
            } else if let pace = presentation.budgetPace {
                MarinaBudgetPaceView(pace: pace)
            } else if presentation.isEmpty {
                Text("No matching records for this period.")
                    .foregroundStyle(.secondary)
                if let metric = presentation.metrics.first {
                    MarinaMetricView(metric: metric, prominent: true)
                }
            } else {
                switch presentation.operation {
                case .summary:
                    ForEach(presentation.metrics.indices, id: \.self) { index in
                        MarinaMetricView(metric: presentation.metrics[index], prominent: index == 0)
                    }
                case .transactions, .inventory:
                    MarinaPresentationRecordsView(records: presentation.records)
                case .ranking, .comparison, .trend, .share:
                    if presentation.operation == .trend, presentation.topicKey?.hasPrefix("expenses:") == true {
                        HomeSpendTrendChart(buckets: presentation.chartPoints.map { point in
                            HomeSpendTrendBucket(id: point.id, label: point.label, total: point.value,
                                slices: point.slices?.map { HomeSpendTrendSlice(name: $0.name, hexColor: $0.colorHex, amount: $0.amount) }
                                    ?? [HomeSpendTrendSlice(name: presentation.title, hexColor: point.colorHex, amount: point.value)])
                        }, showsValues: true)
                    } else {
                        MarinaPresentationChartView(operation: presentation.operation, points: presentation.chartPoints)
                    }
                    if presentation.operation == .comparison {
                        ForEach(presentation.metrics.filter { $0.label == "Difference" || $0.label == "Change percent" }, id: \.label) { metric in
                            MarinaMetricView(metric: metric)
                        }
                    }
                }
            }

            if let qualifier = presentation.qualifier, !qualifier.isEmpty {
                Text(qualifier)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if [.transactions, .inventory, .ranking, .share, .trend].contains(presentation.operation), presentation.totalCount > 0 {
                let shown = [.ranking, .share, .trend].contains(presentation.operation)
                    ? presentation.chartPoints.filter { $0.id != "remaining-groups" }.count : presentation.records.count
                if presentation.pagination != nil || shown < presentation.totalCount {
                    Text("Showing \(shown) of \(presentation.totalCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if presentation.pagination != nil {
                Button("Show more", action: onShowMore)
                    .buttonStyle(.bordered)
                    .accessibilityHint("Loads five more matching results")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}
