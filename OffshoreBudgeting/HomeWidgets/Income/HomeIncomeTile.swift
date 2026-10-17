//
//  HomeIncomeTile.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/26/26.
//

import SwiftUI

struct HomeIncomeTile: View {

    let workspace: Workspace
    let incomes: [Income]
    let startDate: Date
    let endDate: Date

    private var plannedTotal: Double {
        incomes
            .filter { $0.isPlanned && isInRange($0.date) }
            .reduce(0) { $0 + $1.amount }
    }

    private var actualTotal: Double {
        incomes
            .filter { !$0.isPlanned && isInRange($0.date) }
            .reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        NavigationLink {
            HomeIncomeMetricsView(
                workspace: workspace,
                incomes: incomes,
                startDate: startDate,
                endDate: endDate,
                initialPeriod: .period
            )
        } label: {
            HomeTileContainer(
                title: String(localized: "homeWidget.income", defaultValue: "Income", comment: "Pinned home widget title for income metrics."),
                subtitle: dateRangeSubtitle,
                accent: .blue,
                showsChevron: true
            ) {
                HomeIncomeProgressContent(actualTotal: actualTotal, plannedTotal: plannedTotal)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "homeWidget.income", defaultValue: "Income", comment: "Pinned home widget title for income metrics."))
        .accessibilityHint(String(localized: "homeWidget.income.accessibilityHint", defaultValue: "Opens income metrics", comment: "Accessibility hint for opening income widget details."))
    }

    // MARK: - UI Helpers

    private var dateRangeSubtitle: String {
        "\(formattedDate(startDate)) - \(formattedDate(endDate))"
    }

    private func formattedDate(_ date: Date) -> String {
        AppDateFormat.abbreviatedDate(date)
    }

    private func isInRange(_ date: Date) -> Bool {
        (date >= startDate) && (date <= endDate)
    }
}

#Preview("Home Income Tile") {
    let container = PreviewSeed.makeContainer()

    PreviewHost(container: container) { ws in
        NavigationStack {
            HomeIncomeTile(
                workspace: ws,
                incomes: [],
                startDate: Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1)) ?? .now,
                endDate: Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 31)) ?? .now
            )
            .padding()
        }
    }
}
