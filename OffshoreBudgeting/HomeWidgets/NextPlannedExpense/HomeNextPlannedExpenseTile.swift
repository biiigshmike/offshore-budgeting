//
//  HomeNextPlannedExpenseTile.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/24/26.
//

import SwiftUI

struct HomeNextPlannedExpenseTile: View {

    let workspace: Workspace
    let expense: PlannedExpense
    let startDate: Date
    let endDate: Date

    private var card: Card? { expense.card }

    private var plannedText: String {
        expense.plannedAmount.formatted(CurrencyFormatter.currencyStyle())
    }

    private var actualText: String {
        HomeNextPlannedExpenseFinder.effectiveAmount(for: expense)
            .formatted(CurrencyFormatter.currencyStyle())
    }

    private var dateText: String {
        expense.expenseDate.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted))
    }

    private var themeOption: CardThemeOption {
        CardThemeOption(rawValue: card?.theme ?? "graphite") ?? .charcoal
    }

    private var effectOption: CardEffectOption {
        CardEffectOption(rawValue: card?.effect ?? "plastic") ?? .plastic
    }

    var body: some View {
        let presetID = expense.sourcePresetID

        NavigationLink {
            ManagePresetsView(workspace: workspace, highlightedPresetID: presetID)
        } label: {
            HomeTileContainer(
                title: "Next Planned Expense",
                subtitle: dateRangeSubtitle,
                accent: .orange,
                showsChevron: true
            ) {
                HStack(alignment: .center, spacing: 14) {

                    CardVisualView(
                        title: card?.name ?? "Card",
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
                        Text(expense.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(dateText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        VStack(spacing: 6) {
                            metricRow(title: "Planned", value: plannedText, isEmphasized: false)
                            metricRow(title: "Actual", value: actualText, isEmphasized: false)
                        }
                        .padding(.top, 2)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens Presets and pins this expense at the top.")
    }

    private func metricRow(title: String, value: String, isEmphasized: Bool) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(isEmphasized ? .headline.weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }

    private var dateRangeSubtitle: String {
        "\(formattedDate(startDate)) - \(formattedDate(endDate))"
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted))
    }

    private var accessibilityLabel: String {
        "Next planned expense. \(expense.title). Date \(dateText). Planned \(plannedText). Actual \(actualText)."
    }
}
