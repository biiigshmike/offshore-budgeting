//
//  HomeSpendTrendsTile.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/26/26.
//

import SwiftUI

struct HomeSpendTrendsTile: View {

    let workspace: Workspace
    let cards: [Card]
    let categories: [Category]
    let plannedExpenses: [PlannedExpense]
    let variableExpenses: [VariableExpense]
    let startDate: Date
    let endDate: Date

    var body: some View {
        let result = HomeSpendTrendsAggregator.calculate(
            period: .period,
            categories: categories,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            rangeStart: startDate,
            rangeEnd: endDate,
            cardFilter: nil,
            topN: 3
        )

        NavigationLink {
            HomeSpendTrendsMetricsView(
                workspace: workspace,
                cards: cards,
                categories: categories,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                startDate: startDate,
                endDate: endDate,
                initialPeriod: .period
            )
        } label: {
            HomeTileContainer(
                title: String(
                    localized: "homeWidget.spendTrends.title",
                    defaultValue: "Spend Trends",
                    comment: "Widget title for the spend trends Home tile."
                ),
                subtitle: "\(formattedDate(startDate)) - \(formattedDate(endDate))",
                accent: .purple,
                showsChevron: true
            ) {
                VStack(alignment: .leading, spacing: 10) {

                    if result.buckets.allSatisfy({ $0.total <= 0 }) {
                        Text(
                            String(
                                localized: "homeWidget.spendTrends.noDataInRange",
                                defaultValue: "No spending data found in this range.",
                                comment: "Message shown when there is no spending data for the selected range."
                            )
                        )
                            .foregroundStyle(.secondary)
                    } else {
                        miniChart(result: result)
                        highestSummary(result: result)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            String(
                localized: "homeWidget.spendTrends.accessibilityLabel",
                defaultValue: "Spend Trends",
                comment: "Accessibility label for the spend trends widget tile."
            )
        )
        .accessibilityHint(
            String(
                localized: "homeWidget.spendTrends.accessibilityHint",
                defaultValue: "View spending trends for this period",
                comment: "Accessibility hint for opening spend trends details from the Home tile."
            )
        )
    }

    // MARK: - Mini chart

    private func miniChart(result: HomeSpendTrendsAggregator.Result) -> some View {
        HomeSpendTrendChart(buckets: result.buckets.prefix(12).map(HomeSpendTrendBucket.init))
    }

    // MARK: - Highest summary

    private func highestSummary(result: HomeSpendTrendsAggregator.Result) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let highest = result.highestBucket {
                Text(
                    String(
                        format: String(
                            localized: "homeWidget.spendTrends.highestSummaryFormat",
                            defaultValue: "Highest: %1$@ • %2$@",
                            comment: "Summary line showing highest spending bucket and amount."
                        ),
                        locale: .current,
                        highest.label,
                        highest.total.formatted(CurrencyFormatter.currencyStyle())
                    )
                )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let top = result.topCategoryInHighestBucket {
                Text(
                    String(
                        format: String(
                            localized: "homeWidget.spendTrends.topSummaryFormat",
                            defaultValue: "Top: %1$@ • %2$@",
                            comment: "Summary line showing the top category and amount in the highest bucket."
                        ),
                        locale: .current,
                        top.name,
                        top.amount.formatted(CurrencyFormatter.currencyStyle())
                    )
                )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        AppDateFormat.abbreviatedDate(date)
    }
}
