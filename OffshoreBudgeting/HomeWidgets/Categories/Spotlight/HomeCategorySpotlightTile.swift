//
//  HomeCategorySpotlightTile.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/26/26.
//

import SwiftUI

struct HomeCategorySpotlightTile: View {

    let workspace: Workspace
    let categories: [Category]
    let plannedExpenses: [PlannedExpense]
    let variableExpenses: [VariableExpense]
    let startDate: Date
    let endDate: Date

    var topN: Int = 6

    private var metricsResult: HomeCategoryMetricsResult {
        HomeCategoryMetricsCalculator.calculate(
            categories: categories,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            rangeStart: startDate,
            rangeEnd: endDate
        )
    }

    private var topMetric: CategorySpendMetric? {
        metricsResult.metrics.first
    }

    private var slices: [DonutSlice] {
        DonutChartView.slicesFromCategoryMetrics(
            metricsResult.metrics,
            topN: topN,
            includeOther: false
        )
    }

    private var accentColor: Color {
        guard let topMetric else { return .blue }
        return topMetric.categoryColorHex.flatMap { Color(hex: $0) } ?? .blue
    }

    private var subtitle: String {
        "\(formattedDate(startDate)) - \(formattedDate(endDate))"
    }
    
    private func formattedDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted))
    }

    var body: some View {
        NavigationLink {
            CategorySpotlightDetailView(
                workspace: workspace,
                categories: categories,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                startDate: startDate,
                endDate: endDate,
                topN: topN
            )
        } label: {
            HomeTileContainer(
                title: "Category Spotlight",
                subtitle: subtitle,
                accent: accentColor,
                showsChevron: true
            ) {
                content
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens category spending breakdown")
    }

    @ViewBuilder
    private var content: some View {
        if metricsResult.metrics.isEmpty || metricsResult.totalSpent <= 0 {
            VStack(alignment: .leading, spacing: 6) {
                Text("No spending data found in this range.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .center, spacing: 14) {

                DonutChartView(
                    slices: slices,
                    innerRadiusRatio: 0.70,
                    centerTitle: nil,
                    centerValueText: topMetric.map { CurrencyFormatter.string(from: $0.totalSpent) },
                    showsLegend: false
                )
                .frame(width: 150, height: 150)
                .accessibilityLabel("Donut chart")

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total Spent")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(CurrencyFormatter.string(from: metricsResult.totalSpent))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }

                    Divider()
                        .opacity(0.25)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(metricsResult.metrics.prefix(3))) { metric in
                            let color = metric.categoryColorHex.flatMap { Color(hex: $0) } ?? .secondary

                            CategoryMetricRowView(
                                name: metric.categoryName,
                                color: color,
                                amountText: CurrencyFormatter.string(from: metric.totalSpent),
                                percentValue: metric.percentOfTotal,
                                showsProgressBar: false
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
