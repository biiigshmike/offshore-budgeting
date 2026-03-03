//
//  HomeWhatIfTile.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/25/26.
//

import SwiftUI

struct HomeWhatIfTile: View {
    @State private var pinnedRefreshTick: Int = 0


    let workspace: Workspace
    let budgets: [Budget]
    let categories: [Category]
    let incomes: [Income]
    let plannedExpenses: [PlannedExpense]
    let variableExpenses: [VariableExpense]
    let startDate: Date
    let endDate: Date
    let onOpenPlanner: (_ initialScenarioID: UUID?) -> Void

    // MARK: - Store (global scenarios)

    private var scenarioStore: WhatIfScenarioStore {
        WhatIfScenarioStore(workspaceID: workspace.id)
    }

    // MARK: - Totals (baseline)

    private var actualIncomeTotal: Double {
        incomes
            .filter { !$0.isPlanned && isInRange($0.date) }
            .reduce(0) { $0 + safeCurrencyValue($1.amount) }
    }

    private var plannedExpensesEffectiveTotal: Double {
        plannedExpenses
            .filter { isInRange($0.expenseDate) }
            .reduce(0) { $0 + safeCurrencyValue(SavingsMathService.plannedBudgetImpactAmount(for: $1)) }
    }

    private var variableExpensesTotal: Double {
        variableExpenses
            .filter { isInRange($0.transactionDate) }
            .reduce(0) { $0 + safeCurrencyValue(SavingsMathService.variableBudgetImpactAmount(for: $1)) }
    }

    private var actualSavings: Double {
        actualIncomeTotal - (plannedExpensesEffectiveTotal + variableExpensesTotal)
    }

    // MARK: - Scenario (pinned previews)

    private struct PinnedPreviewItem: Identifiable {
        let id: UUID
        let name: String
        let savings: Double
    }

    private var baselineBoundsByCategoryID: [UUID: WhatIfScenarioStore.WhatIfCategoryBounds] {
        buildBaselineBoundsByCategoryID()
    }

    private var pinnedPreviewItems: [PinnedPreviewItem] {
        _ = pinnedRefreshTick
        let pinnedIDs = Array(scenarioStore.loadPinnedGlobalScenarioIDs().prefix(3))
        guard pinnedIDs.isEmpty == false else { return [] }

        // Name lookup is cheap and avoids repeatedly sorting in the UI.
        let allInfos = scenarioStore.listGlobalScenarios()
        let ids = categories.map { $0.id }

        return pinnedIDs.compactMap { id in
            guard let info = allInfos.first(where: { $0.id == id }) else { return nil }
            guard let overrides = scenarioStore.loadGlobalScenario(scenarioID: id) else { return nil }

            let scenarioBoundsByCategoryID = scenarioStore.applyGlobalScenario(
                overrides: overrides.overridesByCategoryID,
                baselineByCategoryID: baselineBoundsByCategoryID,
                categories: ids
            )

            let spend = categories.reduce(0) { partial, category in
                let bounds = scenarioBoundsByCategoryID[category.id, default: .init(min: 0, max: 0)]
                return partial + safeCurrencyValue(bounds.resolvedScenarioSpend(fallback: bounds.midpoint))
            }
            let scenarioActualIncome = overrides.actualIncomeOverride ?? actualIncomeTotal
            let savings = safeCurrencyValue(scenarioActualIncome - spend)
            return PinnedPreviewItem(id: id, name: info.name, savings: savings)
        }
    }

    private var displayValue: Double {
        // Home headline stays “Actual Savings”. Pinned scenarios are previews underneath.
        actualSavings
    }

    private var valueColor: Color {
        displayValue >= 0 ? .green : .red
    }

    private var subtitleText: String {
        "\(formattedDate(startDate)) - \(formattedDate(endDate))"
    }

    var body: some View {
        HomeTileContainer(
            title: "What If?",
            subtitle: subtitleText,
            accent: valueColor,
            showsChevron: false,
            headerTrailing: AnyView(
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                    .padding(.leading, 8)
                    .padding(.bottom, 4)
                    .accessibilityHidden(true)
            )
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .center, spacing: 6) {
                        Text("Actual Savings")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(displayValue, format: CurrencyFormatter.currencyStyle())
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(valueColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    Spacer(minLength: 0)
                }

                pinnedPreviews
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture {
            onOpenPlanner(nil)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: WhatIfScenarioStore.pinnedGlobalScenariosDidChangeName(workspaceID: workspace.id)
            )
        ) { _ in
            pinnedRefreshTick += 1
        }
        .accessibilityLabel("What If?")
        .accessibilityValue(CurrencyFormatter.string(from: displayValue))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens What If planner")
    }

    @ViewBuilder
    private var pinnedPreviews: some View {
        let previews = pinnedPreviewItems

        if previews.isEmpty {
            Text("Pin up to 3 scenarios from inside the planner to preview them here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pinned")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(previews.prefix(3)) { item in
                    Button {
                        onOpenPlanner(item.id)
                    } label: {
                        HStack(spacing: 10) {
                            Text(item.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Spacer(minLength: 0)

                            Text(item.savings, format: CurrencyFormatter.currencyStyle())
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(item.savings >= 0 ? Color.green : Color.red)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }

        }
        
    }

    // MARK: - Helpers

    private func isInRange(_ date: Date) -> Bool {
        (date >= startDate) && (date <= endDate)
    }

    private func formattedDate(_ date: Date) -> String {
        AppDateFormat.abbreviatedDate(date)
    }

    private func buildBaselineBoundsByCategoryID() -> [UUID: WhatIfScenarioStore.WhatIfCategoryBounds] {
        let spentByCategoryID = buildBaselineSpendByCategoryID()
        let limitByCategoryID = buildLimitByCategoryID()

        var result: [UUID: WhatIfScenarioStore.WhatIfCategoryBounds] = [:]
        result.reserveCapacity(categories.count)

        for category in categories {
            let spent = spentByCategoryID[category.id, default: 0]
            let limit = limitByCategoryID[category.id]
            let minValue = limit?.minAmount ?? spent
            let maxValue = limit?.maxAmount ?? spent
            result[category.id] = .init(min: minValue, max: maxValue, scenarioSpend: spent)
        }

        return result
    }

    private func buildBaselineSpendByCategoryID() -> [UUID: Double] {
        var plannedByCategoryID: [UUID: Double] = [:]
        var variableByCategoryID: [UUID: Double] = [:]

        for expense in plannedExpenses {
            guard isInRange(expense.expenseDate), let category = expense.category else { continue }
            plannedByCategoryID[category.id, default: 0] += SavingsMathService.plannedBudgetImpactAmount(for: expense)
        }

        for expense in variableExpenses {
            guard isInRange(expense.transactionDate), let category = expense.category else { continue }
            variableByCategoryID[category.id, default: 0] += expense.amount
        }

        var result: [UUID: Double] = [:]
        result.reserveCapacity(categories.count)

        for category in categories {
            let planned = plannedByCategoryID[category.id, default: 0]
            let variable = variableByCategoryID[category.id, default: 0]
            result[category.id] = max(0, planned + variable)
        }

        return result
    }

    private func buildLimitByCategoryID() -> [UUID: BudgetCategoryLimit] {
        let range = DateRange(start: startDate, end: endDate, calendar: .current)
        let activeBudget = BudgetRangeOverlap.pickActiveBudget(from: budgets, for: range, calendar: .current)
        let limits = activeBudget?.categoryLimits ?? []

        var lookup: [UUID: BudgetCategoryLimit] = [:]
        lookup.reserveCapacity(limits.count)
        for limit in limits {
            guard let category = limit.category else { continue }
            lookup[category.id] = limit
        }
        return lookup
    }

    private func safeCurrencyValue(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return CurrencyFormatter.roundedToCurrency(value)
    }
}
