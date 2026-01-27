//
//  HomeCategoryMetrics.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/26/26.
//

import Foundation

// MARK: - Output models for Category widgets

struct CategorySpendMetric: Identifiable, Equatable {
    let id: UUID
    let categoryID: UUID
    let categoryName: String
    let categoryColorHex: String?

    let totalSpent: Double
    let plannedSpent: Double
    let variableSpent: Double

    /// 0.0 to 1.0
    let percentOfTotal: Double

    init(
        id: UUID = UUID(),
        categoryID: UUID,
        categoryName: String,
        categoryColorHex: String?,
        totalSpent: Double,
        plannedSpent: Double,
        variableSpent: Double,
        percentOfTotal: Double
    ) {
        self.id = id
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.categoryColorHex = categoryColorHex
        self.totalSpent = totalSpent
        self.plannedSpent = plannedSpent
        self.variableSpent = variableSpent
        self.percentOfTotal = percentOfTotal
    }
}

struct HomeCategoryMetricsResult: Equatable {
    let metrics: [CategorySpendMetric]
    let totalSpent: Double
}
