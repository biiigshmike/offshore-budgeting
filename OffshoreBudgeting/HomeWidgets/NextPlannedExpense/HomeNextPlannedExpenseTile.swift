//
//  HomeNextPlannedExpenseTile.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/24/26.
//

import SwiftUI
import SwiftData

struct HomeNextPlannedExpenseTile: View {
    let workspace: Workspace
    let expense: PlannedExpense
    let startDate: Date
    let endDate: Date

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var presets: [Preset]

    init(workspace: Workspace, expense: PlannedExpense, startDate: Date, endDate: Date) {
        self.workspace = workspace
        self.expense = expense
        self.startDate = startDate
        self.endDate = endDate
        let workspaceID = workspace.id
        _presets = Query(filter: #Predicate<Preset> { $0.workspace?.id == workspaceID })
    }

    private var sourcePreset: Preset? {
        Self.resolveSourcePreset(workspaceID: workspace.id, expense: expense, presets: presets)
    }

    /// Resolve by identity, including archived templates, and never cross workspace boundaries.
    static func resolveSourcePreset(workspaceID: UUID, expense: PlannedExpense, presets: [Preset]) -> Preset? {
        guard expense.workspace?.id == workspaceID, let presetID = expense.sourcePresetID else { return nil }
        return presets.first { $0.id == presetID && $0.workspace?.id == workspaceID }
    }

    private var card: Card? {
        guard let card = expense.card, card.workspace?.id == workspace.id else { return nil }
        return card
    }

    private var cardName: String {
        card?.name ?? String(localized: "homeWidget.nextPlannedExpense.fallbackCardName", defaultValue: "Card", comment: "Fallback card name in next planned expense widget.")
    }

    private var plannedText: String {
        expense.plannedAmount.formatted(CurrencyFormatter.currencyStyle())
    }

    private var actualText: String {
        expense.actualAmount > 0
            ? expense.actualAmount.formatted(CurrencyFormatter.currencyStyle())
            : String(localized: "Not recorded")
    }

    private var dateText: String {
        AppDateFormat.abbreviatedDate(expense.expenseDate)
    }

    private var themeOption: CardThemeOption {
        CardThemeOption(rawValue: card?.theme ?? CardThemeOption.charcoal.rawValue) ?? .charcoal
    }

    private var effectOption: CardEffectOption {
        CardEffectOption(rawValue: card?.effect ?? CardEffectOption.plastic.rawValue) ?? .plastic
    }

    var body: some View {
        NavigationLink {
            if let sourcePreset {
                PresetDetailView(workspace: workspace, preset: sourcePreset)
                    .equatable()
            } else {
                ManagePresetsView(workspace: workspace)
            }
        } label: {
            HomeTileContainer(
                title: String(localized: "Next Planned Expense", defaultValue: "Next Planned Expense", comment: "Pinned home widget title for next planned expense."),
                subtitle: dateRangeSubtitle,
                accent: .orange,
                showsChevron: true
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    expenseTitle

                    cardAndMetricsLayout {
                        CardVisualView(
                            title: cardName,
                            theme: themeOption,
                            effect: effectOption,
                            minHeight: nil,
                            showsShadow: false,
                            titleFont: .headline.weight(.semibold),
                            titlePadding: 12,
                            titleOpacity: 0.85
                        )
                        .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 120)
                        .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Due \(dateText)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            amountRow("Planned", value: plannedText)
                            amountRow("Actual", value: actualText, isPending: expense.actualAmount <= 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("home.nextPlannedExpense")
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(sourcePreset == nil
            ? String(localized: "Opens Manage Presets.")
            : String(localized: "Opens preset details and history."))
    }

    private var expenseTitle: some View {
        Text(expense.title)
            .font(.headline)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var cardAndMetricsLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
    }

    private func amountRow(_ title: LocalizedStringKey, value: String, isPending: Bool = false) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 10))
        return layout {
            Text(title)
                .foregroundStyle(.secondary)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            Text(value)
                .foregroundStyle(isPending ? .secondary : .primary)
                .bold(!isPending)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
    }

    private var dateRangeSubtitle: String {
        "\(AppDateFormat.abbreviatedDate(startDate)) – \(AppDateFormat.abbreviatedDate(endDate))"
    }

    private var accessibilityLabel: String {
        String(localized: "Next planned expense. \(expense.title). Card \(cardName). Due \(dateText). Planned \(plannedText). Actual \(actualText). \(dateRangeSubtitle).")
    }
}
