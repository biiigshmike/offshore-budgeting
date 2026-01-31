//
//  PlannedExpense+EffectiveAmount.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/31/26.
//

import Foundation

extension PlannedExpense {

    // MARK: - Effective Amount

    /// Returns the amount Offshore should use for calculations:
    /// - If `actualAmount > 0`, we treat that as the real amount and use it.
    /// - Otherwise, we fall back to `plannedAmount`.
    func effectiveAmount() -> Double {
        if actualAmount > 0 {
            return actualAmount
        } else {
            return plannedAmount
        }
    }
}

