//
//  CardSummaryPresentationView.swift
//  OffshoreBudgeting
//
//  Created by OpenAI Codex on 5/22/26.
//

import SwiftUI

struct CardSummaryPresentationView: View {
    let model: CardSummaryPresentationModel
    let showsChevron: Bool

    private var themeOption: CardThemeOption {
        CardThemeOption(rawValue: model.themeRaw) ?? .charcoal
    }

    private var effectOption: CardEffectOption {
        CardEffectOption(rawValue: model.effectRaw) ?? .plastic
    }

    var body: some View {
        HomeTileContainer(
            title: model.title,
            subtitle: model.dateRangeSubtitle,
            accent: .primary,
            showsChevron: showsChevron
        ) {
            HStack(alignment: .center, spacing: 14) {
                CardVisualView(
                    title: model.title,
                    theme: themeOption,
                    effect: effectOption,
                    minHeight: nil,
                    showsShadow: false,
                    titleFont: .headline.weight(.semibold),
                    titlePadding: 12,
                    titleOpacity: 0.85
                )
                .frame(width: 120)

                VStack(alignment: .leading, spacing: 8) {
                    metricRow(
                        title: String(localized: "common.total", defaultValue: "Total", comment: "Common label for totals."),
                        value: model.total
                    )
                    metricRow(
                        title: String(localized: "common.planned", defaultValue: "Planned", comment: "Common label for planned values."),
                        value: model.plannedTotal
                    )
                    metricRow(
                        title: String(localized: "common.variable", defaultValue: "Variable", comment: "Common label for variable values."),
                        value: model.variableTotal
                    )
                }

                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.title) card summary")
        .accessibilityValue(
            "\(model.dateRangeSubtitle), total \(CurrencyFormatter.string(from: model.total)), planned \(CurrencyFormatter.string(from: model.plannedTotal)), variable \(CurrencyFormatter.string(from: model.variableTotal))"
        )
    }

    private func metricRow(title: String, value: Double) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value, format: CurrencyFormatter.currencyStyle())
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
    }
}
