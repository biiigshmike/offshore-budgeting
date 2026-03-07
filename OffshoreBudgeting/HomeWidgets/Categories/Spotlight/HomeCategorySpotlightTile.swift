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

    let topN: Int = 3

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
        AppDateFormat.abbreviatedDate(date)
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
                title: String(localized: "homeWidget.categorySpotlight", defaultValue: "Category Spotlight", comment: "Pinned home widget title for category spotlight."),
                subtitle: subtitle,
                accent: accentColor,
                showsChevron: true
            ) {
                content
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "homeWidget.categorySpotlight.accessibilityHint", defaultValue: "Opens category spending breakdown", comment: "Accessibility hint for opening category spotlight detail."))
    }

    @ViewBuilder
    private var content: some View {
        if metricsResult.metrics.isEmpty || metricsResult.totalSpent <= 0 {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "homeWidget.categorySpotlight.noDataInRange", defaultValue: "No spending data found in this range.", comment: "Message shown when no category spending data exists for selected range."))
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
                .accessibilityLabel(String(localized: "homeWidget.categorySpotlight.donutChartLabel", defaultValue: "Donut chart", comment: "Accessibility label for category spotlight donut chart."))

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "homeWidget.categorySpotlight.totalSpent", defaultValue: "Total Spent", comment: "Label for total spent in category spotlight widget."))
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
                        ForEach(Array(metricsResult.metrics.prefix(topN))) { metric in
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
