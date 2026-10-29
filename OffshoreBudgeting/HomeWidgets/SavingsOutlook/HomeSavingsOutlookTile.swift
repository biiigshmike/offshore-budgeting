//
//  HomeSavingsOutlookTile.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/26/26.
//

import SwiftUI

struct HomeSavingsOutlookTile: View {

    let workspace: Workspace
    let incomes: [Income]
    let plannedExpenses: [PlannedExpense]
    let variableExpenses: [VariableExpense]
    let savingsEntries: [SavingsLedgerEntry]
    let startDate: Date
    let endDate: Date

    // MARK: - Totals

    private var outlook: SavingsOutlookCalculator.Summary {
        SavingsOutlookCalculator.totals(incomes: incomes, plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses, savingsEntries: savingsEntries,
            startDate: startDate, endDate: endDate)
    }

    private var projectedSavings: Double { outlook.projected }
    private var actualSavings: Double { outlook.actual }

    // MARK: - Styling

    private var accentColor: Color {
        if projectedSavings == 0 { return .secondary }
        return projectedSavings > 0 ? .green : .red
    }

    private var actualValueColor: Color {
        if actualSavings >= 0 { return .green }
        if projectedSavings < 0 { return .orange }
        return .red
    }

    // MARK: - Gauge

    private var gaugeRightLabel: String {
        if projectedSavings < 0 {
            return CurrencyFormatter.string(from: 0)
        }
        return 1.0.formatted(.percent.precision(.fractionLength(0)))
    }

    private var progress: SavingsOutlookCalculator.Progress {
        SavingsOutlookCalculator.progress(projected: projectedSavings, actual: actualSavings)
    }

    private var fillProgress: Double { progress.gaugeValue }
    private var percentText: String { progress.formatted }

    var body: some View {
        NavigationLink {
            HomeSavingsOutlookMetricsView(
                workspace: workspace,
                incomes: incomes,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                savingsEntries: savingsEntries,
                startDate: startDate,
                endDate: endDate,
                initialPeriod: .period
            )
        } label: {
            HomeTileContainer(
                title: String(localized: "homeWidget.savingsOutlook", defaultValue: "Savings Outlook", comment: "Pinned home widget title for savings outlook."),
                subtitle: dateRangeSubtitle,
                accent: accentColor,
                showsChevron: true
            ) {
                VStack(alignment: .leading, spacing: 12) {

                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        metricBlock(
                            title: String(localized: "budgetDetail.summary.projectedSavings", defaultValue: "Projected Savings", comment: "Budget detail summary row for projected savings."),
                            value: projectedSavings,
                            valueColor: .primary
                        )

                        Spacer(minLength: 0)

                        metricBlock(
                            title: String(localized: "budgetDetail.summary.actualSavings", defaultValue: "Actual Savings", comment: "Budget detail summary row for actual savings."),
                            value: actualSavings,
                            valueColor: actualValueColor
                        )
                    }

                    HomeSavingsGaugeRow(
                        percentText: percentText,
                        fillProgress: fillProgress,
                        fillColor: accentColor,
                        rightLabel: gaugeRightLabel,
                        projectedSavings: projectedSavings
                    )
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "homeWidget.savingsOutlook", defaultValue: "Savings Outlook", comment: "Pinned home widget title for savings outlook."))
        .accessibilityHint(String(localized: "homeSavingsOutlook.openHint", defaultValue: "Opens savings metrics", comment: "Accessibility hint for opening savings outlook metrics."))
    }

    // MARK: - UI Helpers

    private func metricBlock(title: String, value: Double, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(value, format: CurrencyFormatter.currencyStyle())
                .font(.headline.weight(.semibold))
                .foregroundStyle(valueColor)
        }
    }

    private var dateRangeSubtitle: String {
        "\(formattedDate(startDate)) - \(formattedDate(endDate))"
    }

    private func formattedDate(_ date: Date) -> String {
        AppDateFormat.abbreviatedDate(date)
    }

}

// MARK: - Gauge Row

private struct HomeSavingsGaugeRow: View {

    let percentText: String
    let fillProgress: Double
    let fillColor: Color
    let rightLabel: String
    let projectedSavings: Double

    private let barHeight: CGFloat = 12

    var body: some View {
        HStack(spacing: 10) {
            Text(percentText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 40, alignment: .leading)

            HomeSavingsGaugeBar(
                progress: fillProgress,
                barHeight: barHeight,
                fillColor: fillColor
            )
            .frame(height: barHeight)

            Text(rightLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .trailing)
                .minimumScaleFactor(0.75)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "homeSavingsOutlook.progress", defaultValue: "Savings progress", comment: "Accessibility label for savings progress gauge."))
        .accessibilityValue(accessibilityValueText)
    }

    private var accessibilityValueText: String {
        if projectedSavings < 0 {
            return "\(percentText) toward break-even"
        }
        return "\(percentText)"
    }
}

private struct HomeSavingsGaugeBar: View {

    let progress: Double
    let barHeight: CGFloat
    let fillColor: Color

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let clamped = min(max(progress, 0), 1)
            let fillWidth = width * clamped

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.secondary.opacity(0.22))
                    .frame(height: barHeight)

                Capsule(style: .continuous)
                    .fill(fillColor.opacity(0.85))
                    .frame(width: fillWidth, height: barHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: barHeight)
    }
}

#Preview("Home Savings Outlook Tile") {
    let container = PreviewSeed.makeContainer()

    PreviewHost(container: container) { ws in
        NavigationStack {
            HomeSavingsOutlookTile(
                workspace: ws,
                incomes: ws.incomes ?? [],
                plannedExpenses: ws.plannedExpenses ?? [],
                variableExpenses: ws.variableExpenses ?? [],
                savingsEntries: (ws.savingsAccounts ?? []).flatMap { $0.entries ?? [] },
                startDate: Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1)) ?? .now,
                endDate: Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 31)) ?? .now
            )
            .padding()
        }
    }
}
