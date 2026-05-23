//
//  MarinaPolishedAttachmentViews.swift
//  OffshoreBudgeting
//
//  Created by OpenAI Codex on 5/22/26.
//

import SwiftUI
import Charts

struct MarinaMetricSummaryAttachmentView: View {
    let model: MarinaMetricSummaryPresentationModel
    var accessibilityPrefix: String = "marina.metricSummary"

    var body: some View {
        MarinaPolishedShell(
            title: model.title,
            subtitle: model.subtitle,
            systemImage: model.systemImage,
            tint: tint
        ) {
            if let primaryValue = model.primaryValue {
                Text(primaryValue)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }

            MarinaDisplayRowsView(rows: model.rows, tint: tint, showsProgress: false, accessibilityPrefix: accessibilityPrefix)
        }
        .accessibilityIdentifier("marina.metricSummary")
    }

    private var tint: Color {
        model.tintHex.flatMap { Color(hex: $0) } ?? .blue
    }
}

struct MarinaComparisonSummaryAttachmentView: View {
    let model: MarinaComparisonSummaryPresentationModel
    var accessibilityPrefix: String = "marina.comparisonSummary"

    var body: some View {
        MarinaPolishedShell(
            title: model.title,
            subtitle: model.subtitle,
            systemImage: "arrow.left.arrow.right",
            tint: .indigo
        ) {
            HStack(alignment: .top, spacing: 10) {
                comparisonMetric(model.primaryLabel, model.primaryValue)
                comparisonMetric(model.comparisonLabel, model.comparisonValue)
            }

            if let deltaLabel = model.deltaLabel, let deltaValue = model.deltaValue {
                HStack {
                    Text(deltaLabel)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(deltaValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(deltaTint(deltaValue))
                        .multilineTextAlignment(.trailing)
                }
            }

            MarinaDisplayRowsView(rows: model.rows, tint: .indigo, showsProgress: false, accessibilityPrefix: accessibilityPrefix)
        }
        .accessibilityIdentifier("marina.comparisonSummary")
    }

    private func comparisonMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func deltaTint(_ value: String) -> Color {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("-") {
            return .green
        }
        if value.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("+") || value.localizedCaseInsensitiveContains("up") {
            return .red
        }
        return .primary
    }
}

struct MarinaBreakdownListAttachmentView: View {
    let model: MarinaBreakdownListPresentationModel
    var accessibilityPrefix: String = "marina.breakdownList"

    var body: some View {
        MarinaPolishedShell(
            title: model.title,
            subtitle: model.subtitle,
            systemImage: "list.bullet.rectangle.fill",
            tint: .teal
        ) {
            if let primaryValue = model.primaryValue {
                Text(primaryValue)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }

            MarinaDisplayRowsView(rows: model.rows, tint: .teal, showsProgress: true, accessibilityPrefix: accessibilityPrefix)
        }
        .accessibilityIdentifier("marina.breakdownList")
    }
}

struct MarinaTrendChartAttachmentView: View {
    let model: MarinaTrendChartPresentationModel

    var body: some View {
        MarinaPolishedShell(
            title: model.title,
            subtitle: model.subtitle,
            systemImage: "chart.xyaxis.line",
            tint: .cyan
        ) {
            Chart(model.points) { point in
                BarMark(
                    x: .value("Row", point.label),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(.cyan)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: min(model.points.count, 4))) {
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) {
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel()
                }
            }
            .frame(height: 160)
        }
        .accessibilityIdentifier("marina.trendChart")
    }
}

struct MarinaFormulaContractAttachmentView: View {
    let model: MarinaFormulaContractPresentationModel
    var accessibilityPrefix: String = "marina.formulaContract"

    var body: some View {
        MarinaPolishedShell(
            title: model.title,
            subtitle: model.subtitle,
            systemImage: "doc.text.magnifyingglass",
            tint: .orange
        ) {
            if let status = model.status {
                Text(status)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }

            MarinaDisplayRowsView(rows: model.rows, tint: .orange, showsProgress: false, accessibilityPrefix: accessibilityPrefix)
        }
        .accessibilityIdentifier("marina.formulaContract")
    }
}

struct MarinaClarificationAttachmentView: View {
    let model: MarinaClarificationPresentationModel
    var accessibilityPrefix: String = "marina.clarification"

    var body: some View {
        MarinaPolishedShell(
            title: model.title,
            subtitle: model.subtitle,
            systemImage: model.systemImage,
            tint: tint
        ) {
            MarinaDisplayRowsView(rows: model.rows, tint: tint, showsProgress: false, accessibilityPrefix: accessibilityPrefix)
        }
        .accessibilityIdentifier("marina.clarification")
    }

    private var tint: Color {
        model.tintHex.flatMap { Color(hex: $0) } ?? .indigo
    }
}

struct MarinaDeadEndAttachmentView: View {
    let model: MarinaDeadEndPresentationModel
    var accessibilityPrefix: String = "marina.deadEnd"

    var body: some View {
        MarinaPolishedShell(
            title: model.title,
            subtitle: model.subtitle,
            systemImage: model.systemImage,
            tint: tint
        ) {
            MarinaDisplayRowsView(rows: model.rows, tint: tint, showsProgress: false, accessibilityPrefix: accessibilityPrefix)
        }
        .accessibilityIdentifier("marina.deadEnd")
    }

    private var tint: Color {
        model.tintHex.flatMap { Color(hex: $0) } ?? .orange
    }
}

struct MarinaGenericSummaryAttachmentView: View {
    let model: MarinaGenericSummaryPresentationModel
    var accessibilityPrefix: String = "marina.genericSummary"

    var body: some View {
        MarinaPolishedShell(
            title: model.title,
            subtitle: model.subtitle,
            systemImage: "text.justify.left",
            tint: .blue
        ) {
            if let primaryValue = model.primaryValue {
                Text(primaryValue)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }

            MarinaDisplayRowsView(rows: model.rows, tint: .blue, showsProgress: false, accessibilityPrefix: accessibilityPrefix)
        }
        .accessibilityIdentifier("marina.genericSummary")
    }
}

private struct MarinaPolishedShell<Content: View>: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: Color
    let content: Content

    init(
        title: String,
        subtitle: String?,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.16))

                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)
            }

            content
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct MarinaDisplayRowsView: View {
    let rows: [MarinaDisplayRow]
    let tint: Color
    let showsProgress: Bool
    let accessibilityPrefix: String

    private var maxMagnitude: Double {
        max(rows.compactMap { $0.amount.map(abs) }.max() ?? 0, 0)
    }

    var body: some View {
        if rows.isEmpty == false {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    rowView(row, index: index)
                        .padding(.vertical, 7)
                        .accessibilityIdentifier("\(accessibilityPrefix).row.\(index)")

                    if index < rows.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private func rowView(_ row: MarinaDisplayRow, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(row.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .accessibilityIdentifier("\(accessibilityPrefix).row.\(index).title")

                Spacer(minLength: 8)

                Text(row.value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(valueTint(row))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .accessibilityIdentifier("\(accessibilityPrefix).row.\(index).value")
            }

            if showsProgress, maxMagnitude > 0, let amount = row.amount {
                ProgressView(value: min(abs(amount) / maxMagnitude, 1))
                    .progressViewStyle(.linear)
                    .tint(tint)
                    .accessibilityHidden(true)
            }
        }
    }

    private func valueTint(_ row: MarinaDisplayRow) -> Color {
        guard let amount = row.amount else { return .secondary }
        if amount < 0 { return .green }
        return .primary
    }
}
