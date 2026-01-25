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
    let topN: Int

    @State private var showsAll: Bool = false

    private var subtitle: String {
        "\(startDate.formatted(.dateTime.month().day().year())) - \(endDate.formatted(.dateTime.month().day().year()))"
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
            topN: topN,
            includeOther: true
        )
    }

    private var showAllButtonTitle: String {
        if showsAll {
            return "Hide All Categories"
        } else {
            return "Show All Categories (\(result.metrics.count))"
        }
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    DonutChartView(
                        slices: slices,
                        innerRadiusRatio: 0.70,
                        centerTitle: topMetric.map { "Top: \($0.categoryName)" },
                        centerValueText: topMetric.map { CurrencyFormatter.string(from: $0.totalSpent) },
                        showsLegend: false
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total spent")
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
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        showsAll.toggle()
                    }
                } label: {
                    HStack {
                        Text(showAllButtonTitle)
                            .font(.subheadline.weight(.semibold))

                        Spacer()

                        Image(systemName: showsAll ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }

            Section {
                let visible = showsAll ? result.metrics : Array(result.metrics.prefix(topN))

                ForEach(visible) { metric in
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
                Text("Spending by Category")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Category Spotlight")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("Category Spotlight")
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
