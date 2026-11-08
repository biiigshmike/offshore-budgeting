//
//  HomeCategoryAvailabilityTile.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/26/26.
//

import SwiftUI

struct HomeCategoryAvailabilityTile: View {
    enum LayoutMode {
        case small
        case wide
    }

    private enum AvailabilitySlot: Identifiable {
        case metric(CategoryAvailabilityMetric)
        case placeholder(UUID)

        var id: String {
            switch self {
            case .metric(let metric):
                return metric.id.uuidString
            case .placeholder(let id):
                return id.uuidString
            }
        }
    }

    let workspace: Workspace

    let budgets: [Budget]
    let categories: [Category]
    let plannedExpenses: [PlannedExpense]
    let variableExpenses: [VariableExpense]

    let startDate: Date
    let endDate: Date
    var layoutMode: LayoutMode = .small

    var inclusionPolicy: HomeCategoryLimitsAggregator.CategoryInclusionPolicy = .allCategoriesInfinityWhenMissing

    private struct GoalEditorRoute: Identifiable {
        let budget: Budget
        let category: Category
        var id: UUID { category.id }
    }

    @State private var goalEditor: GoalEditorRoute?
    @State private var scope: AvailabilityScope = .all
    @State private var pageIndex: Int = 0
    @State private var measuredSmallRowHeight: CGFloat = 0
    @State private var measuredWideRowHeight: CGFloat = 0

    private let fallbackRowHeight: CGFloat = 76
    private let rowSpacing: CGFloat = 10
    private let pageSize: Int = 6
    private var rowsPerPage: Int {
        switch layoutMode {
        case .small:
            return 6
        case .wide:
            return 3
        }
    }
    private var effectiveRowHeight: CGFloat {
        let measured: CGFloat
        switch layoutMode {
        case .small:
            measured = measuredSmallRowHeight
        case .wide:
            measured = measuredWideRowHeight
        }
        return measured > 1 ? measured : fallbackRowHeight
    }


    var body: some View {
        let result = HomeCategoryLimitsAggregator.build(
            budgets: budgets,
            categories: categories,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            rangeStart: startDate,
            rangeEnd: endDate,
            inclusionPolicy: inclusionPolicy
        )

        HomeTileContainer(
            title: String(localized: "homeWidget.categoryAvailability", defaultValue: "Category Goals"),
            subtitle: result.activeBudget.map { "\($0.name) • \(subtitleText)" } ?? subtitleText,
            accent: accentColor(for: result),
            showsChevron: false
        ) {
            if result.activeBudget == nil {
                emptyState(
                    title: "No budget overlaps this range.",
                    subtitle: "Try adjusting your Home date range, or create a budget that covers these dates."
                )

            } else if result.metrics.isEmpty {
                emptyState(
                    title: "No categories found.",
                    subtitle: "Add categories to get started."
                )

            } else {
                let total = result.metrics.count
                let totalPages = max(1, Int(ceil(Double(total) / Double(pageSize))))

                let start = pageIndex * pageSize
                let end = min(start + pageSize, total)
                let pageItems: [CategoryAvailabilityMetric] = (start < end) ? Array(result.metrics[start..<end]) : []
                let slots = makeSlots(from: pageItems)
                
                let reservedRowsHeight =
                    CGFloat(rowsPerPage) * effectiveRowHeight + CGFloat(max(0, rowsPerPage - 1)) * rowSpacing

                VStack(alignment: .leading, spacing: 12) {
                    headerSummary(overCount: result.overCount, nearCount: result.nearCount)

                    Divider().opacity(0.35)

                    switch layoutMode {
                    case .small:
                        VStack(spacing: rowSpacing) {
                            ForEach(slots) { slot in
                                slotView(slot, budget: result.activeBudget)
                            }
                        }
                        .frame(
                            minHeight: reservedRowsHeight,
                            alignment: .top
                        )
                    case .wide:
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(minimum: 0), spacing: rowSpacing),
                                GridItem(.flexible(minimum: 0), spacing: rowSpacing)
                            ],
                            alignment: .leading,
                            spacing: rowSpacing
                        ) {
                            ForEach(slots) { slot in
                                slotView(slot, budget: result.activeBudget)
                            }
                        }
                        .frame(
                            minHeight: reservedRowsHeight,
                            alignment: .top
                        )
                    }
                    paginationControls(current: pageIndex, totalPages: totalPages)

                }
                .onChange(of: totalPages) { _, newValue in
                    // If data changes and is beyond the last page, clamp.
                    pageIndex = min(pageIndex, max(0, newValue - 1))
                }
                .onPreferenceChange(CategoryAvailabilityRowHeightPreferenceKey.self) { value in
                    guard value > 1 else { return }
                    switch layoutMode {
                    case .small:
                        if abs(measuredSmallRowHeight - value) > 0.5 {
                            measuredSmallRowHeight = value
                        }
                    case .wide:
                        if abs(measuredWideRowHeight - value) > 0.5 {
                            measuredWideRowHeight = value
                        }
                    }
                }
            }
        }
        .appSheet(item: $goalEditor) { route in
            EditCategoryLimitView(
                budget: route.budget,
                category: route.category,
                plannedContribution: plannedContribution(for: route),
                variableContribution: variableContribution(for: route)
            )
        }
    }

    private func plannedContribution(for route: GoalEditorRoute) -> Double {
        BudgetPlannedExpenseStore.plannedExpenses(in: workspace, for: route.budget)
            .filter { $0.workspace?.id == workspace.id && $0.card?.workspace?.id == workspace.id
                && $0.category?.id == route.category.id }
            .reduce(0) { $0 + SavingsMathService.plannedBudgetImpactAmount(for: $1) }
    }

    private func variableContribution(for route: GoalEditorRoute) -> Double {
        let cardIDs = BudgetPlannedExpenseStore.linkedCardIDs(for: route.budget)
        let range = DateRange(start: route.budget.startDate, end: route.budget.endDate)
        return (workspace.variableExpenses ?? []).filter {
            $0.workspace?.id == workspace.id && $0.card?.workspace?.id == workspace.id
                && $0.category?.id == route.category.id
                && $0.card.map { cardIDs.contains($0.id) } == true
                && $0.transactionDate >= range.start && $0.transactionDate <= range.end
        }.reduce(0) { $0 + SavingsMathService.variableBudgetImpactAmount(for: $1) }
    }

    // MARK: - Slots

    private func makeSlots(from pageItems: [CategoryAvailabilityMetric]) -> [AvailabilitySlot] {
        var slots = pageItems.prefix(pageSize).map(AvailabilitySlot.metric)
        while slots.count < pageSize {
            slots.append(.placeholder(UUID()))
        }
        return slots
    }

    @ViewBuilder
    private func slotView(_ slot: AvailabilitySlot, budget: Budget?) -> some View {
        switch slot {
        case .metric(let metric):
            Button {
                guard let budget, budget.workspace?.id == workspace.id,
                      let category = categories.first(where: { $0.id == metric.categoryID && $0.workspace?.id == workspace.id }) else { return }
                goalEditor = GoalEditorRoute(budget: budget, category: category)
            } label: {
                CategoryAvailabilityRowView(
                    metric: metric,
                    scope: scope,
                    currencyCode: CurrencyFormatter.currencyCode,
                    nearThreshold: HomeCategoryLimitsAggregator.defaultNearThreshold
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens category goals for this budget."))
            .accessibilityIdentifier("homeCategoryGoals.category.\(metric.categoryID.uuidString)")
            .background(rowHeightReader)
        case .placeholder:
            Color.clear
                .frame(height: effectiveRowHeight)
                .accessibilityHidden(true)
        }
    }

    private var rowHeightReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: CategoryAvailabilityRowHeightPreferenceKey.self,
                value: proxy.size.height
            )
        }
    }
    
    // MARK: - Pagination
    
    private func paginationControls(current: Int, totalPages: Int) -> some View {
        ZStack {
            // Centered page indicator
            Text("\(localizedInt(current + 1)) of \(localizedInt(totalPages))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            // Left / Right controls
            HStack {
                Button {
                    pageIndex = max(0, pageIndex - 1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.thinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(current == 0)
                .opacity(current == 0 ? 0.4 : 1.0)
                .accessibilityLabel(String(localized: "common.previousPage", defaultValue: "Previous page", comment: "Accessibility label for previous page control."))

                Spacer()

                Button {
                    pageIndex = min(totalPages - 1, pageIndex + 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.thinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(current >= totalPages - 1)
                .opacity(current >= totalPages - 1 ? 0.4 : 1.0)
                .accessibilityLabel(String(localized: "common.nextPage", defaultValue: "Next page", comment: "Accessibility label for next page control."))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Header

    private func headerSummary(overCount: Int, nearCount: Int) -> some View {
        HStack(spacing: 10) {
            AvailabilityCountPill(
                title: "Over",
                count: overCount,
                style: .over
            )

            AvailabilityCountPill(
                title: "Near",
                count: nearCount,
                style: .near
            )

            Spacer(minLength: 0)
        }
    }

    // MARK: - Empty state

    private func emptyState(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Formatting

    private var subtitleText: String {
        "\(formattedDate(startDate)) - \(formattedDate(endDate))"
    }

    private func formattedDate(_ date: Date) -> String {
        AppDateFormat.abbreviatedDate(date)
    }

    private func localizedInt(_ value: Int) -> String {
        AppNumberFormat.integer(value)
    }

    // MARK: - Accent

    private func accentColor(for result: HomeCategoryAvailabilityResult) -> Color {
        // Prefer a limited category that is over, then near, else workspace tint-ish.
        if let over = result.metrics.first(where: { $0.isLimited && $0.status(for: .all, nearThreshold: HomeCategoryLimitsAggregator.defaultNearThreshold) == .over }) {
            return Color(hex: over.colorHex) ?? .primary
        }

        if let near = result.metrics.first(where: { $0.isLimited && $0.status(for: .all, nearThreshold: HomeCategoryLimitsAggregator.defaultNearThreshold) == .near }) {
            return Color(hex: near.colorHex) ?? .primary
        }

        return .primary
    }
}

// MARK: - Count pill

private struct AvailabilityCountPill: View {

    enum PillStyle {
        case over
        case near
    }

    let title: String
    let count: Int
    let style: PillStyle

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(foregroundColor).frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(title)
            Text(localizedInt(count))
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) categories")
        .accessibilityValue(localizedInt(count))
    }

    private var foregroundColor: Color {
        switch style {
        case .over:
            return .red
        case .near:
            return .orange
        }
    }

    private func localizedInt(_ value: Int) -> String {
        AppNumberFormat.integer(value)
    }
}

private struct CategoryAvailabilityRowHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
