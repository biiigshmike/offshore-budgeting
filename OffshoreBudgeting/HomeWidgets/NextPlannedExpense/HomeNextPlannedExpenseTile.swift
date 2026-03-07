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
        AppDateFormat.abbreviatedDate(expense.expenseDate)
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
                title: String(localized: "homeWidget.nextPlannedExpense", defaultValue: "Next Planned Expense", comment: "Pinned home widget title for next planned expense."),
                subtitle: dateRangeSubtitle,
                accent: .orange,
                showsChevron: true
            ) {
                HStack(alignment: .center, spacing: 14) {

                    CardVisualView(
                        title: card?.name ?? String(localized: "homeWidget.nextPlannedExpense.fallbackCardName", defaultValue: "Card", comment: "Fallback card name in next planned expense widget."),
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
                            metricRow(title: String(localized: "common.planned", defaultValue: "Planned", comment: "Common label for planned values."), value: plannedText, isEmphasized: false)
                            metricRow(title: String(localized: "common.actual", defaultValue: "Actual", comment: "Common label for actual values."), value: actualText, isEmphasized: false)
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
        .accessibilityHint(String(localized: "homeWidget.nextPlannedExpense.accessibilityHint", defaultValue: "Opens Presets and pins this expense at the top.", comment: "Accessibility hint for next planned expense widget."))
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
        AppDateFormat.abbreviatedDate(date)
    }

    private var accessibilityLabel: String {
        String(
            format: String(
                localized: "homeWidget.nextPlannedExpense.accessibilityLabelFormat",
                defaultValue: "Next planned expense. %1$@. Date %2$@. Planned %3$@. Actual %4$@.",
                comment: "Accessibility label format for next planned expense widget."
            ),
            locale: .current,
            expense.title,
            dateText,
            plannedText,
            actualText
        )
    }
}
