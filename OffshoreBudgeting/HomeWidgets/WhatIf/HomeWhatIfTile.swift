//
//  HomeWhatIfTile.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/25/26.
//

import SwiftUI

struct HomeWhatIfTile: View {
    @State private var cachedPinnedPreviewItems: [PinnedPreviewItem] = []
    @State private var hasLoadedPinnedPreviews: Bool = false


    let workspace: Workspace
    let budgets: [Budget]
    let categories: [Category]
    let incomes: [Income]
    let plannedExpenses: [PlannedExpense]
    let variableExpenses: [VariableExpense]
    let savingsEntries: [SavingsLedgerEntry]
    let startDate: Date
    let endDate: Date
    let onOpenPlanner: (_ initialScenarioID: UUID?) -> Void

    // MARK: - Store (global scenarios)

    private var scenarioStore: WhatIfScenarioStore {
        WhatIfScenarioStore(workspaceID: workspace.id)
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
        actualIncomeTotal
            - (plannedExpensesEffectiveTotal + variableExpensesTotal)
            + SavingsMathService.actualSavingsAdjustmentTotal(
                from: savingsEntries,
                startDate: startDate,
                endDate: endDate
            )
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

    private var refreshInputToken: Int {
        var hasher = Hasher()
        hasher.combine(startDate.timeIntervalSinceReferenceDate)
        hasher.combine(endDate.timeIntervalSinceReferenceDate)
        hasher.combine(budgets.count)
        hasher.combine(categories.count)
        hasher.combine(incomes.count)
        hasher.combine(plannedExpenses.count)
        hasher.combine(variableExpenses.count)
        return hasher.finalize()
    }

    var body: some View {
        HomeTileContainer(
            title: String(localized: "homeWidget.whatIf", defaultValue: "What If?", comment: "Pinned home widget title for what-if planner."),
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
                        Text(String(localized: "homeWidget.whatIf.actualSavings", defaultValue: "Actual Savings", comment: "Headline label for actual savings in What If tile."))
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
        .onAppear {
            refreshPinnedPreviews()
        }
        .onChange(of: refreshInputToken) { _, _ in
            refreshPinnedPreviews()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: WhatIfScenarioStore.pinnedGlobalScenariosDidChangeName(workspaceID: workspace.id)
            )
        ) { _ in
            refreshPinnedPreviews()
        }
        .accessibilityLabel(String(localized: "homeWidget.whatIf", defaultValue: "What If?", comment: "Pinned home widget title for what-if planner."))
        .accessibilityValue(CurrencyFormatter.string(from: displayValue))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(String(localized: "homeWidget.whatIf.accessibilityHint", defaultValue: "Opens What If planner", comment: "Accessibility hint for opening the What If planner."))
    }

    @ViewBuilder
    private var pinnedPreviews: some View {
        let previews = hasLoadedPinnedPreviews ? cachedPinnedPreviewItems : []

        if previews.isEmpty {
            Text(String(localized: "homeWidget.whatIf.emptyPinned", defaultValue: "Pin up to 3 scenarios from inside the planner to preview them here.", comment: "Empty-state helper text for What If pinned scenarios."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "homeWidget.whatIf.pinnedLabel", defaultValue: "Pinned", comment: "Label for pinned scenario preview section."))
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

    private func refreshPinnedPreviews() {
        let pinnedIDs = Array(scenarioStore.loadPinnedGlobalScenarioIDs().prefix(3))
        guard pinnedIDs.isEmpty == false else {
            cachedPinnedPreviewItems = []
            hasLoadedPinnedPreviews = true
            return
        }

        // I snapshot these once so each pinned scenario can reuse the same baseline work.
        let allInfos = scenarioStore.listGlobalScenarios()
        let categoryIDs = categories.map { $0.id }
        let baseline = baselineBoundsByCategoryID
        let baselineActualIncome = actualIncomeTotal

        var previews: [PinnedPreviewItem] = []
        previews.reserveCapacity(pinnedIDs.count)

        for id in pinnedIDs {
            guard let info = allInfos.first(where: { $0.id == id }) else { continue }
            guard let overrides = scenarioStore.loadGlobalScenario(scenarioID: id, touchAccessTime: false) else { continue }

            let scenarioBoundsByCategoryID = scenarioStore.applyGlobalScenario(
                overrides: overrides.overridesByCategoryID,
                baselineByCategoryID: baseline,
                categories: categoryIDs
            )

            let spend = categories.reduce(0) { partial, category in
                let bounds = scenarioBoundsByCategoryID[category.id, default: .init(min: 0, max: 0)]
                return partial + safeCurrencyValue(bounds.resolvedScenarioSpend(fallback: bounds.midpoint))
            }
            let scenarioActualIncome = overrides.actualIncomeOverride ?? baselineActualIncome
            let savings = safeCurrencyValue(scenarioActualIncome - spend)
            previews.append(PinnedPreviewItem(id: id, name: info.name, savings: savings))
        }

        cachedPinnedPreviewItems = previews
        hasLoadedPinnedPreviews = true
    }
}
