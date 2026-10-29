import SwiftUI

/// A saved result uses the same financial visual components as Home.
struct MarinaPresentationView: View {
    let presentation: MarinaPresentation
    var onPeakTransactions: (() -> Void)? = nil
    var onShowMore: () -> Void

    private var layout: MarinaPresentationLayout { .resolve(presentation) }
    private var chartPoints: [MarinaPresentation.ChartPoint] {
        guard let leaders = presentation.report?.leaders else { return presentation.chartPoints }
        return leaders.enumerated().compactMap { index, leader in
            guard let name = leader.title, let amount = leader.amount else { return nil }
            return .init(id: "leader-\(index)", label: "\(name) · \(leader.scope)", value: amount)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.title).font(.headline).accessibilityAddTraits(.isHeader)
                Text(presentation.scopeLabel).font(.subheadline).foregroundStyle(.secondary)
                if presentation.isUpdated {
                    Label("Updated with your latest records", systemImage: "arrow.clockwise")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            switch layout {
            case .incomeProgress:
                if let income = presentation.incomeProgress {
                    HomeIncomeProgressContent(actualTotal: income.actual, plannedTotal: income.planned)
                }
            case .budgetPace:
                if let pace = presentation.budgetPace { MarinaBudgetPaceView(pace: pace) }
            case .cardSummary:
                if let card = presentation.card,
                   let total = presentation.metrics.first(where: { $0.label == "Total" })?.value,
                   let planned = presentation.metrics.first(where: { $0.label == "Planned card spending" })?.value,
                   let variable = presentation.metrics.first(where: { $0.label == "Variable card spending" })?.value {
                    CardSummaryContentView(title: card.name, themeRaw: card.theme, effectRaw: card.effect,
                                           total: total, planned: planned, variable: variable)
                }
            case .spendingPatterns:
                MarinaSpendingPatternsView(presentation: presentation, onPeakTransactions: onPeakTransactions)
            case .categoryAvailability:
                ForEach(presentation.metrics.indices, id: \.self) { index in
                    LabeledContent(presentation.metrics[index].label, value: presentation.metrics[index].formatted)
                }
                if let report = presentation.report, let categories = report.categories {
                    MarinaCategoryAvailabilityView(categories: categories, budgetName: report.budgetName)
                }
            case .timeline:
                ForEach(presentation.metrics.indices, id: \.self) { index in
                    MarinaMetricView(metric: presentation.metrics[index], prominent: index == 0)
                }
                MarinaTimelineView(presentation: presentation)
            case .chart:
                MarinaPresentationChartView(operation: presentation.operation, points: chartPoints,
                                            chartIntent: presentation.chartIntent)
                if presentation.operation == .comparison {
                    ForEach(presentation.metrics.filter { $0.label == "Difference" || $0.label == "Change percent" }, id: \.label) { metric in
                        LabeledContent(metric.label, value: metric.formatted)
                    }
                    if let leaders = presentation.report?.leaders {
                        ForEach(Array(leaders.enumerated()), id: \.offset) { _, leader in
                            if leader.amount == nil {
                                Text("No matching spending for \(leader.scope).")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            } else if leader.tiedCount > 1, let title = leader.title {
                                Text("\(title) is tied with \(leader.tiedCount - 1) other \(leader.tiedCount == 2 ? "result" : "results").")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            case .records:
                if presentation.topicKey?.hasPrefix("accounts:") == true
                    || [.budgetCards, .budgetPresets].contains(presentation.purpose) {
                    ForEach(presentation.metrics.indices, id: \.self) { index in
                        MarinaMetricView(metric: presentation.metrics[index], prominent: index == 0)
                    }
                }
                MarinaPresentationRecordsView(records: presentation.records,
                                               transactions: presentation.report?.transactions ?? [])
            case .empty:
                Text("No matching records for this period.").foregroundStyle(.secondary)
                if let metric = presentation.metrics.first { MarinaMetricView(metric: metric, prominent: true) }
            case .metrics:
                if let card = presentation.card, presentation.operation == .summary {
                    CardVisualView(title: card.name, theme: CardThemeOption(rawValue: card.theme) ?? .ruby,
                                   effect: CardEffectOption(rawValue: card.effect) ?? .plastic,
                                   minHeight: nil, showsShadow: false)
                        .frame(maxWidth: 300)
                }
                ForEach(presentation.metrics.indices, id: \.self) { index in
                    MarinaMetricView(metric: presentation.metrics[index], prominent: index == 0)
                }
            }

            if [.chart, .timeline, .metrics].contains(layout), let report = presentation.report {
                MarinaReportView(report: report, purpose: presentation.purpose)
            }
            if let qualifier = presentation.qualifier, !qualifier.isEmpty {
                Text(qualifier).font(.footnote).foregroundStyle(.secondary)
            }
            if let policy = presentation.report?.policy,
               policy.excludedPlannedCount > 0 || policy.excludedVariableCount > 0 {
                Text("This calculation excludes \(policy.excludedPlannedCount) future planned and \(policy.excludedVariableCount) future variable expenses.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            if (presentation.pagination != nil || [.transactions, .inventory, .ranking, .share, .trend].contains(presentation.operation)), presentation.totalCount > 0 {
                let shown = presentation.report?.categories?.count ?? presentation.report?.series?.first?.points.count
                    ?? presentation.report?.groups?.count
                    ?? ([.ranking, .share, .trend].contains(presentation.operation)
                        ? presentation.chartPoints.filter { $0.id != "remaining-groups" }.count : presentation.records.count)
                if presentation.pagination != nil || shown < presentation.totalCount {
                    let unit = presentation.operation == .trend ? "periods" : layout == .categoryAvailability ? "categories" : "results"
                    Text("Showing \(shown) of \(presentation.totalCount) \(unit)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if presentation.pagination != nil {
                Button(presentation.operation == .trend ? "Show more periods" : "Show more", action: onShowMore)
                    .buttonStyle(.bordered)
                    .accessibilityHint(presentation.operation == .trend ? "Loads five more periods" : "Loads five more matching results")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}
