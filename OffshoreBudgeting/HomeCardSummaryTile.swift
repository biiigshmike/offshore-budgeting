//
//  HomeCardSummaryTile.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/24/26.
//

import SwiftUI

struct HomeCardSummaryTile: View {

    let workspace: Workspace
    let card: Card
    let startDate: Date
    let endDate: Date

    private var metrics: HomeCardMetrics {
        HomeCardMetricsCalculator.metrics(for: card, start: startDate, end: endDate)
    }

    private var themeOption: CardThemeOption {
        CardThemeOption(rawValue: card.theme) ?? .graphite
    }

    private var effectOption: CardEffectOption {
        CardEffectOption(rawValue: card.effect) ?? .plastic
    }

    var body: some View {
        NavigationLink {
            CardDetailView(workspace: workspace, card: card)
        } label: {
            HomeTileContainer(
                title: card.name,
                subtitle: dateRangeSubtitle,
                accent: .primary,
                showsChevron: true
            ) {
                HStack(alignment: .center, spacing: 14) {

                    CardVisualView(
                        title: card.name,
                        theme: themeOption,
                        effect: effectOption,
                        minHeight: nil,
                        showsShadow: false,
                        titleFont: .headline.weight(.semibold),
                        titlePadding: 12,
                        titleOpacity: 0.85
                    )
                    .frame(width: 120)

                    VStack(alignment: .leading, spacing: 8) {
                        metricRow(title: "Total", value: metrics.total, isEmphasized: true)
                        metricRow(title: "Planned", value: metrics.plannedTotal, isEmphasized: false)
                        metricRow(title: "Variable", value: metrics.variableTotal, isEmphasized: false)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(card.name) summary")
        .accessibilityHint("Opens card details")
    }

    private func metricRow(title: String, value: Double, isEmphasized: Bool) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value, format: CurrencyFormatter.currencyStyle())
                .font(isEmphasized ? .headline.weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }

    private var dateRangeSubtitle: String {
        "\(formattedDate(startDate)) - \(formattedDate(endDate))"
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted))
    }
}
