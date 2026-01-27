//
//  HomeCategoryLimitsAggregator.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/26/26.
//

import Foundation

// MARK: - Availability scope

enum AvailabilityScope: String, CaseIterable, Identifiable {
    case all
    case planned
    case variable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .planned: return "Planned"
        case .variable: return "Variable"
        }
    }
}

// MARK: - Status

enum CategoryAvailabilityStatus: Equatable {
    case over
    case near
    case ok
}

// MARK: - Metric model

struct CategoryAvailabilityMetric: Identifiable, Equatable {

    // Identity
    let id: UUID
    let categoryID: UUID
    let name: String
    let colorHex: String

    // Limit
    /// nil means “∞”
    let maxAmount: Double?

    // Spend
    let spentPlanned: Double
    let spentVariable: Double

    // MARK: - Derived

    var spentTotal: Double { spentPlanned + spentVariable }

    func spent(for scope: AvailabilityScope) -> Double {
        switch scope {
        case .all: return spentTotal
        case .planned: return spentPlanned
        case .variable: return spentVariable
        }
    }

    /// Returns nil when maxAmount is nil (∞).
    func availableRaw(for scope: AvailabilityScope) -> Double? {
        guard let maxAmount else { return nil }
        return maxAmount - spent(for: scope)
    }

    /// Convenience for UI display: ∞ stays nil, otherwise clamps to 0+.
    func availableClamped(for scope: AvailabilityScope) -> Double? {
        guard let raw = availableRaw(for: scope) else { return nil }
        return max(0, raw)
    }

    /// nil when max is ∞ or max <= 0.
    func percentUsed(for scope: AvailabilityScope) -> Double? {
        guard let maxAmount, maxAmount > 0 else { return nil }
        return spent(for: scope) / maxAmount
    }

    func status(for scope: AvailabilityScope, nearThreshold: Double) -> CategoryAvailabilityStatus {
        guard let maxAmount, maxAmount > 0 else { return .ok }

        let spentValue = spent(for: scope)
        if spentValue > maxAmount {
            return .over
        }

        let available = maxAmount - spentValue
        let ratio = available / maxAmount

        if ratio <= nearThreshold {
            return .near
        }

        return .ok
    }

    /// True only when category has a real max (not ∞) and can be classified as over/near.
    var isLimited: Bool {
        if let maxAmount, maxAmount > 0 { return true }
        return false
    }
}

// MARK: - Result model

struct HomeCategoryAvailabilityResult: Equatable {
    let activeBudget: Budget?
    let metrics: [CategoryAvailabilityMetric]
    let overCount: Int
    let nearCount: Int
}

// MARK: - Aggregator

struct HomeCategoryLimitsAggregator {

    /// Default “Near” threshold = within 10% remaining.
    static let defaultNearThreshold: Double = 0.10

    /// Controls whether we include categories without limits (as ∞).
    /// This is the exact hook we’ll later drive from Settings.
    enum CategoryInclusionPolicy: Equatable {
        case limitsOnly
        case allCategoriesInfinityWhenMissing
    }

    static func build(
        budgets: [Budget],
        categories: [Category],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        rangeStart: Date,
        rangeEnd: Date,
        inclusionPolicy: CategoryInclusionPolicy = .allCategoriesInfinityWhenMissing,
        nearThreshold: Double = defaultNearThreshold,
        calendar: Calendar = .current
    ) -> HomeCategoryAvailabilityResult {

        let range = DateRange(start: rangeStart, end: rangeEnd, calendar: calendar)

        // 1) Pick active budget
        let activeBudget = BudgetRangeOverlap.pickActiveBudget(from: budgets, for: range, calendar: calendar)

        // 2) Build limits lookup for the active budget
        let limits: [BudgetCategoryLimit] = activeBudget?.categoryLimits ?? []
        var limitByCategoryID: [UUID: BudgetCategoryLimit] = [:]
        limitByCategoryID.reserveCapacity(limits.count)

        for limit in limits {
            guard let category = limit.category else { continue }
            limitByCategoryID[category.id] = limit
        }

        // 3) Decide which categories participate
        let participatingCategories: [Category]
        switch inclusionPolicy {
        case .limitsOnly:
            let limitedIDs = Set(limitByCategoryID.keys)
            participatingCategories = categories.filter { limitedIDs.contains($0.id) }

        case .allCategoriesInfinityWhenMissing:
            participatingCategories = categories
        }

        // If there is no budget or no categories, still return a valid result
        guard !participatingCategories.isEmpty else {
            return HomeCategoryAvailabilityResult(
                activeBudget: activeBudget,
                metrics: [],
                overCount: 0,
                nearCount: 0
            )
        }

        let participatingIDs = Set(participatingCategories.map { $0.id })

        // 4) Compute spend for participating categories
        var plannedByCategoryID: [UUID: Double] = [:]
        var variableByCategoryID: [UUID: Double] = [:]
        plannedByCategoryID.reserveCapacity(participatingIDs.count)
        variableByCategoryID.reserveCapacity(participatingIDs.count)

        for expense in plannedExpenses {
            guard
                expense.expenseDate >= range.start,
                expense.expenseDate <= range.end,
                let category = expense.category,
                participatingIDs.contains(category.id)
            else { continue }

            let effectiveAmount: Double = (expense.actualAmount > 0) ? expense.actualAmount : expense.plannedAmount
            plannedByCategoryID[category.id, default: 0] += effectiveAmount
        }

        for expense in variableExpenses {
            guard
                expense.transactionDate >= range.start,
                expense.transactionDate <= range.end,
                let category = expense.category,
                participatingIDs.contains(category.id)
            else { continue }

            variableByCategoryID[category.id, default: 0] += expense.amount
        }

        // 5) Build metrics in category name order (we’ll sort after status)
        var metrics: [CategoryAvailabilityMetric] = []
        metrics.reserveCapacity(participatingCategories.count)

        for category in participatingCategories {
            let limit = limitByCategoryID[category.id]
            let planned = plannedByCategoryID[category.id, default: 0]
            let variable = variableByCategoryID[category.id, default: 0]

            metrics.append(
                CategoryAvailabilityMetric(
                    id: category.id,
                    categoryID: category.id,
                    name: category.name,
                    colorHex: category.hexColor,
                    maxAmount: limit?.maxAmount, // nil => ∞
                    spentPlanned: planned,
                    spentVariable: variable
                )
            )
        }

        // 6) Counts (only categories with real max participate)
        let overCount = metrics.filter {
            $0.isLimited && $0.status(for: .all, nearThreshold: nearThreshold) == .over
        }.count

        let nearCount = metrics.filter {
            $0.isLimited && $0.status(for: .all, nearThreshold: nearThreshold) == .near
        }.count

        // 7) Sorting:
        // - Over first, then Near, then limited high % used, then unlimited, then name
        metrics.sort { lhs, rhs in
            let lhsLimited = lhs.isLimited
            let rhsLimited = rhs.isLimited

            let lhsStatus = lhs.status(for: .all, nearThreshold: nearThreshold)
            let rhsStatus = rhs.status(for: .all, nearThreshold: nearThreshold)

            func rank(_ s: CategoryAvailabilityStatus) -> Int {
                switch s {
                case .over: return 0
                case .near: return 1
                case .ok: return 2
                }
            }

            // Status ordering matters only for limited categories
            if lhsLimited && rhsLimited {
                let lhsRank = rank(lhsStatus)
                let rhsRank = rank(rhsStatus)
                if lhsRank != rhsRank { return lhsRank < rhsRank }

                let lp = lhs.percentUsed(for: .all) ?? -1
                let rp = rhs.percentUsed(for: .all) ?? -1
                if lp != rp { return lp > rp }

                if lhs.spentTotal != rhs.spentTotal { return lhs.spentTotal > rhs.spentTotal }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

            // Limited categories come before unlimited categories
            if lhsLimited != rhsLimited {
                return lhsLimited && !rhsLimited
            }

            // Both unlimited (∞): show highest spent first, then name
            if lhs.spentTotal != rhs.spentTotal { return lhs.spentTotal > rhs.spentTotal }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        return HomeCategoryAvailabilityResult(
            activeBudget: activeBudget,
            metrics: metrics,
            overCount: overCount,
            nearCount: nearCount
        )
    }
}
