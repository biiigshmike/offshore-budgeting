//
//  CategorySpotlightDetailView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/26/26.
//

import SwiftUI

struct CategorySpotlightDetailView: View {

    let workspace: Workspace
    let categories: [Category]
    let plannedExpenses: [PlannedExpense]
    let variableExpenses: [VariableExpense]
    let startDate: Date
    let endDate: Date

    private var subtitle: String {
        let formatter = DateIntervalFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: startDate, to: endDate)
    }

    private var result: HomeCategoryMetricsResult {
        HomeCategoryMetricsCalculator.calculate(
            categories: categories,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            rangeStart: startDate,
            rangeEnd: endDate
        )
    }

    private var topMetric: CategorySpendMetric? {
        result.metrics.first
    }

    private var slices: [DonutSlice] {
        DonutChartView.slicesFromCategoryMetrics(
            result.metrics,
            topN: result.metrics.count,
            includeOther: false
        )
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    DonutChartView(
                        slices: slices,
                        innerRadiusRatio: 0.70,
                        centerTitle: nil,
                        centerValueText: topMetric.map { CurrencyFormatter.string(from: $0.totalSpent) },
                        showsLegend: false
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)

                    if let topMetric {
                        VStack(spacing: 4) {
                            Text(String(localized: "homeWidget.categorySpotlight.topCategory", defaultValue: "Top Category", comment: "Label for top category in detail view."))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(topMetric.categoryName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "homeWidget.categorySpotlight.totalSpentLowercase", defaultValue: "Total spent", comment: "Label for total spent in category spotlight detail view."))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(CurrencyFormatter.string(from: result.totalSpent))
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.primary)
                        }

                        Spacer()
                    }
                }
                .padding(.vertical, 6)
            }
            .listRowSeparator(.hidden)

            Section {
                Text("Category spending uses planned and variable expense budget impact for these dates. Shared splits and Pay From Savings reduce purchase impact; refunds reduce spending, and adjustments have no budget impact.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("The chart lists categories with positive totals. Refunds can reduce the overall Total Spent even when their category is not shown.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HelpTopicLink(topicID: "home-widgets", title: "How spending is calculated")
            }

            Section {
                ForEach(result.metrics) { metric in
                    let color = metric.categoryColorHex.flatMap { Color(hex: $0) } ?? .secondary

                    CategoryMetricRowView(
                        name: metric.categoryName,
                        color: color,
                        amountText: CurrencyFormatter.string(from: metric.totalSpent),
                        percentValue: metric.percentOfTotal,
                        showsProgressBar: true
                    )
                }
            } header: {
                Text(String(localized: "homeWidget.categorySpotlight.spendingByCategory", defaultValue: "Spending by Category", comment: "Section header for category spending list."))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(String(localized: "homeWidget.categorySpotlight", defaultValue: "Category Spotlight", comment: "Pinned home widget title for category spotlight."))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(String(localized: "homeWidget.categorySpotlight", defaultValue: "Category Spotlight", comment: "Pinned home widget title for category spotlight."))
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

}
