//
//  HomeCategoryAvailabilityTile.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/26/26.
//

import SwiftUI

struct HomeCategoryAvailabilityTile: View {

    let workspace: Workspace

    let budgets: [Budget]
    let categories: [Category]
    let plannedExpenses: [PlannedExpense]
    let variableExpenses: [VariableExpense]

    let startDate: Date
    let endDate: Date

    /// Later: drive from Settings
    var inclusionPolicy: HomeCategoryLimitsAggregator.CategoryInclusionPolicy = .allCategoriesInfinityWhenMissing

    /// Later: segmented filter
    @State private var scope: AvailabilityScope = .all
    @State private var pageIndex: Int = 0

    private let pageSize: Int = 5
    private let rowHeight: CGFloat = 76
    private let rowSpacing: CGFloat = 10


    @AppStorage("general_currencyCode")
    private var currencyCode: String = "USD"

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
            title: "Category Availability",
            subtitle: subtitleText,
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
                
                let reservedRowsHeight =
                    CGFloat(pageSize) * rowHeight + CGFloat(pageSize - 1) * rowSpacing

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        headerSummary(overCount: result.overCount, nearCount: result.nearCount)

                        Spacer(minLength: 0)
                        paginationControls(current: pageIndex, totalPages: totalPages)
                    }

                    Divider().opacity(0.35)

                    VStack(spacing: rowSpacing) {
                        ForEach(pageItems) { metric in
                            CategoryAvailabilityRowView(
                                metric: metric,
                                scope: scope,
                                currencyCode: currencyCode,
                                nearThreshold: HomeCategoryLimitsAggregator.defaultNearThreshold
                            )
                        }
                    }
                    .frame(
                        minHeight: reservedRowsHeight,
                        alignment: .top
                    )
                }
                .onChange(of: totalPages) { _, newValue in
                    // If data changes and we're beyond the last page, clamp.
                    pageIndex = min(pageIndex, max(0, newValue - 1))
                }
            }
        }
    }
    
    // MARK: - Pagination
    
    private func paginationControls(current: Int, totalPages: Int) -> some View {
        ZStack {
            // Centered page indicator
            Text("\(current + 1) of \(totalPages)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()

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
                .accessibilityLabel("Previous page")

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
                .accessibilityLabel("Next page")
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
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted))
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
            Text(title)
                .font(.caption.weight(.semibold))

            Text("\(count)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(backgroundColor, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(borderColor, lineWidth: 1)
        }
        .foregroundStyle(foregroundColor)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) categories")
        .accessibilityValue("\(count)")
    }

    private var backgroundColor: Color {
        switch style {
        case .over:
            return Color.red.opacity(0.14)
        case .near:
            return Color.orange.opacity(0.14)
        }
    }

    private var borderColor: Color {
        switch style {
        case .over:
            return Color.red.opacity(0.22)
        case .near:
            return Color.orange.opacity(0.22)
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .over:
            return .red
        case .near:
            return .orange
        }
    }
}
