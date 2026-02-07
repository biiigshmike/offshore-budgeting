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

    private var rawRatio: Double? {
        guard plannedTotal > 0 else { return nil }
        return actualTotal / plannedTotal
    }

    private var fillProgress: Double {
        guard let rawRatio else { return 0 }
        return min(max(rawRatio, 0), 1)
    }

    private var percentText: String {
        guard let rawRatio else { return "—" }
        return rawRatio.formatted(.percent.precision(.fractionLength(0)))
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
                title: "Income",
                subtitle: dateRangeSubtitle,
                accent: .blue,
                showsChevron: true
            ) {
                VStack(alignment: .leading, spacing: 12) {

                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        metricBlock(
                            title: "Actual Income",
                            value: actualTotal,
                            isEmphasized: false
                        )

                        Spacer(minLength: 0)

                        metricBlock(
                            title: "Planned Income",
                            value: plannedTotal,
                            isEmphasized: false
                        )
                    }

                    HomeIncomeGaugeRow(
                        percentText: percentText,
                        fillProgress: fillProgress
                    )
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Income")
        .accessibilityHint("Opens income metrics")
    }

    // MARK: - UI Helpers

    private func metricBlock(title: String, value: Double, isEmphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(value, format: CurrencyFormatter.currencyStyle())
                .font(isEmphasized ? .title3.weight(.semibold) : .headline.weight(.semibold))
                .foregroundStyle(.primary)
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

private struct HomeIncomeGaugeRow: View {

    let percentText: String
    let fillProgress: Double

    private let barHeight: CGFloat = 12
    
    var body: some View {
        HStack(spacing: 10) {
            Text(percentText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 40, alignment: .leading)

            HomeIncomeGaugeBar(
                progress: fillProgress,
                barHeight: barHeight
            )
            .frame(height: barHeight)

            Text(1.0, format: .percent.precision(.fractionLength(0)))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Income progress")
        .accessibilityValue("\(percentText) of planned")
    }
}

private struct HomeIncomeGaugeBar: View {

    let progress: Double
    let barHeight: CGFloat

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
                    .fill(Color.blue.opacity(0.85))
                    .frame(width: fillWidth, height: barHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: barHeight)
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
