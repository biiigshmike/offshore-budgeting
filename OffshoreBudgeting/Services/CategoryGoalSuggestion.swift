import Foundation

struct CategoryGoalSuggestion: Equatable {
    let averageAmount: Double
    let cushionPercent: Double
    let samples: [CategoryGoalHistorySample]

    var minimum: Double? {
        guard let lowest = samples.map(\.amount).filter(\.isFinite).min() else { return nil }
        return CurrencyFormatter.roundedToCurrency(max(0, lowest))
    }

    func maximum(plannedMinimum: Double = 0, enteredMinimum: Double? = nil) -> Double {
        let estimate = averageAmount * (1 + cushionPercent / 100)
        let floor = max(0, plannedMinimum, enteredMinimum ?? 0)
        return max(CurrencyFormatter.roundedUpToCurrency(floor),
                   CurrencyFormatter.roundedToCurrency(max(0, estimate)))
    }
}
