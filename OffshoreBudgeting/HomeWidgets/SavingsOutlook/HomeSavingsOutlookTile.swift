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
    let startDate: Date
    let endDate: Date

    // MARK: - Totals

    private var plannedIncomeTotal: Double {
        incomes
            .filter { $0.isPlanned && isInRange($0.date) }
            .reduce(0) { $0 + $1.amount }
    }

    private var actualIncomeTotal: Double {
        incomes
            .filter { !$0.isPlanned && isInRange($0.date) }
            .reduce(0) { $0 + $1.amount }
    }

    private var plannedExpensesPlannedTotal: Double {
        plannedExpenses
            .filter { isInRange($0.expenseDate) }
            .reduce(0) { $0 + $1.plannedAmount }
    }

    private var plannedExpensesEffectiveActualTotal: Double {
        plannedExpenses
            .filter { isInRange($0.expenseDate) }
            .reduce(0) { $0 + $1.effectiveAmount() }
    }

    private var variableExpensesTotal: Double {
        variableExpenses
            .filter { isInRange($0.transactionDate) }
            .reduce(0) { $0 + $1.amount }
    }

    private var projectedSavings: Double {
        plannedIncomeTotal - plannedExpensesPlannedTotal
    }

    private var actualSavings: Double {
        actualIncomeTotal - (plannedExpensesEffectiveActualTotal + variableExpensesTotal)
    }

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

    private var fillProgress: Double {
        guard projectedSavings != 0 else { return 0 }

        if projectedSavings > 0 {
            let ratio = actualSavings / projectedSavings
            return min(max(ratio, 0), 1)
        }

        // Negative projection mode, progress to break-even (0).
        let progressToBreakeven = (actualSavings - projectedSavings) / abs(projectedSavings)
        return min(max(progressToBreakeven, 0), 1)
    }

    private var percentText: String {
        guard projectedSavings != 0 else { return "—" }

        if projectedSavings > 0 {
            let ratio = actualSavings / projectedSavings
            let clamped = min(max(ratio, 0), 1)
            return clamped.formatted(.percent.precision(.fractionLength(0)))
        }

        let raw = (actualSavings - projectedSavings) / abs(projectedSavings)
        let clamped = min(max(raw, 0), 1)
        return clamped.formatted(.percent.precision(.fractionLength(0)))
    }

    var body: some View {
        NavigationLink {
            HomeSavingsOutlookMetricsView(
                workspace: workspace,
                incomes: incomes,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                startDate: startDate,
                endDate: endDate,
                initialPeriod: .period
            )
        } label: {
            HomeTileContainer(
                title: "Savings Outlook",
                subtitle: dateRangeSubtitle,
                accent: accentColor,
                showsChevron: true
            ) {
                VStack(alignment: .leading, spacing: 12) {

                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        metricBlock(
                            title: "Projected Savings",
                            value: projectedSavings,
                            valueColor: .primary
                        )

                        Spacer(minLength: 0)

                        metricBlock(
                            title: "Actual Savings",
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
        .accessibilityLabel("Savings Outlook")
        .accessibilityHint("Opens savings metrics")
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
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted))
    }

    private func isInRange(_ date: Date) -> Bool {
        (date >= startDate) && (date <= endDate)
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
        .accessibilityLabel("Savings progress")
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
                startDate: Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1)) ?? .now,
                endDate: Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 31)) ?? .now
            )
            .padding()
        }
    }
}
