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

    private var visibleMetrics: [CategorySpendMetric] {
        showsAll ? result.metrics : Array(result.metrics.prefix(topN))
    }

    private var slices: [DonutSlice] {
        DonutChartView.slicesFromCategoryMetrics(
            visibleMetrics,
            topN: visibleMetrics.count,
            includeOther: false
        )
    }

    private var showAllButtonTitle: String {
        if showsAll {
            return "Hide All Categories"
        } else {
            return "Show All Categories (\(localizedInt(result.metrics.count)))"
        }
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
                            Text("Top Category")
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
                showAllCategoriesButton
                    .listRowBackground(Color.clear)
            }

            Section {
                ForEach(visibleMetrics) { metric in
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

    private func localizedInt(_ value: Int) -> String {
        AppNumberFormat.integer(value)
    }

    @ViewBuilder
    private var showAllCategoriesButton: some View {
        if #available(iOS 26.0, *) {
            baseShowAllCategoriesButton
                .buttonStyle(.glassProminent)
                .tint(Color("AccentColor"))
        } else {
            baseShowAllCategoriesButton
                .buttonStyle(.borderedProminent)
                .tint(Color("AccentColor"))
        }
    }

    private var baseShowAllCategoriesButton: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                showsAll.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Text(showAllButtonTitle)
                    .font(.subheadline.weight(.semibold))

                Image(systemName: showsAll ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .multilineTextAlignment(.center)
        }
    }
}
