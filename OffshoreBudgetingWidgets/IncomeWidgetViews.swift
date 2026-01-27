//
//  MetricValueView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/27/26.
//


import SwiftUI

// MARK: - Helpers

private extension IncomeWidgetSnapshot {
    var rangeText: String {
        let start = rangeStart.formatted(.dateTime.month(.abbreviated).day())
        let end = rangeEnd.formatted(.dateTime.month(.abbreviated).day())
        return "\(start)–\(end)"
    }

    var delta: Double { actualTotal - plannedTotal }
    var percent: Double? { plannedTotal > 0 ? actualTotal / plannedTotal : nil }
}

private struct MetricValueView: View {
    let title: String
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct GraphPlaceholderView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.secondary.opacity(0.15))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.secondary.opacity(0.18), lineWidth: 1)
            }
    }
}

// MARK: - Small

struct IncomeWidgetSmallView: View {
    let snapshot: IncomeWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeaderView(
                title: snapshot.title,
                periodToken: snapshot.periodToken,
                rangeText: snapshot.rangeText
            )

            GraphPlaceholderView()
                .frame(maxWidth: .infinity)
                .frame(height: 84)

            HStack(spacing: 10) {
                MetricValueView(title: "Actual", value: snapshot.actualTotal)
                Spacer(minLength: 0)
            }
        }
        .padding(14)
    }
}

// MARK: - Medium

struct IncomeWidgetMediumView: View {
    let snapshot: IncomeWidgetSnapshot

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                WidgetHeaderView(
                    title: snapshot.title,
                    periodToken: snapshot.periodToken,
                    rangeText: snapshot.rangeText
                )

                GraphPlaceholderView()
                    .frame(height: 84)
            }

            VStack(alignment: .leading, spacing: 10) {
                MetricValueView(title: "Planned", value: snapshot.plannedTotal)
                MetricValueView(title: "Actual", value: snapshot.actualTotal)

                if let pct = snapshot.percent {
                    Text("Progress \(Int((pct * 100).rounded()))%")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Progress —")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .frame(width: 140, alignment: .leading)
        }
        .padding(14)
    }
}

// MARK: - Large

struct IncomeWidgetLargeView: View {
    let snapshot: IncomeWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WidgetHeaderView(
                title: snapshot.title,
                periodToken: snapshot.periodToken,
                rangeText: snapshot.rangeText
            )

            GraphPlaceholderView()
                .frame(maxWidth: .infinity)
                .frame(height: 150)

            HStack(spacing: 12) {
                MetricValueView(title: "Planned", value: snapshot.plannedTotal)
                MetricValueView(title: "Actual", value: snapshot.actualTotal)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Delta")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(snapshot.delta, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(14)
    }
}

// MARK: - Extra Large

struct IncomeWidgetExtraLargeView: View {
    let snapshot: IncomeWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WidgetHeaderView(
                title: snapshot.title,
                periodToken: snapshot.periodToken,
                rangeText: snapshot.rangeText
            )

            GraphPlaceholderView()
                .frame(maxWidth: .infinity)
                .frame(height: 170)

            HStack(spacing: 12) {
                MetricValueView(title: "Planned", value: snapshot.plannedTotal)
                MetricValueView(title: "Actual", value: snapshot.actualTotal)
                Spacer(minLength: 0)
            }

            if let items = snapshot.recentItems, !items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 10) {
                            Text(item.source)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Spacer(minLength: 0)

                            Text(item.amount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                    }
                }
            } else {
                Text("No recent income entries.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
    }
}
