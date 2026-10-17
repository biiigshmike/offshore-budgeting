import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaBudgetFormulaCalculatorTests {
    @Test func budgetFormulaCalculator_returnsExpectedValuesAndNilForInvalidInputs() throws {
        #expect(MarinaBudgetFormulaCalculator.burnRate(actualSpend: 1_715, elapsedDays: 20) == 85.75)
        #expect(MarinaBudgetFormulaCalculator.burnRate(actualSpend: 1_715, elapsedDays: 0) == nil)

        #expect(MarinaBudgetFormulaCalculator.currentPaceProjection(burnRate: 85.75, totalDays: 30) == 2_572.5)
        #expect(MarinaBudgetFormulaCalculator.currentPaceProjection(burnRate: 85.75, totalDays: 0) == nil)

        let safeDailySpend = try #require(MarinaBudgetFormulaCalculator.safeDailySpend(remainingRoom: 1_295, remainingDays: 11))
        #expect(abs(safeDailySpend - 117.72727272727273) < 0.0001)
        #expect(MarinaBudgetFormulaCalculator.safeDailySpend(remainingRoom: 1_295, remainingDays: 0) == nil)

        let paceDifference = try #require(MarinaBudgetFormulaCalculator.paceDifference(actualSpend: 1_715, plannedSpend: 1_490, elapsedPercent: 20.0 / 30.0))
        #expect(abs(paceDifference - 721.6666666666667) < 0.0001)
        #expect(MarinaBudgetFormulaCalculator.paceDifference(actualSpend: 1_715, plannedSpend: 1_490, elapsedPercent: -0.1) == nil)

        let coverageRatio = try #require(MarinaBudgetFormulaCalculator.coverageRatio(income: 3_000, plannedExpenses: 1_490))
        #expect(abs(coverageRatio - 2.0134228187919465) < 0.0001)
        #expect(MarinaBudgetFormulaCalculator.coverageRatio(income: 3_000, plannedExpenses: 0) == nil)

        #expect(MarinaBudgetFormulaCalculator.recurringBurden(recurringTotal: 1_490, plannedExpenseTotal: 1_490) == 1)
        #expect(MarinaBudgetFormulaCalculator.recurringBurden(recurringTotal: 1_490, plannedExpenseTotal: 0) == nil)

        let concentration = try #require(MarinaBudgetFormulaCalculator.concentration(partTotal: 1_590, wholeTotal: 1_805))
        #expect(abs(concentration - 0.8808864265927978) < 0.0001)
        #expect(MarinaBudgetFormulaCalculator.concentration(partTotal: 1_590, wholeTotal: 0) == nil)
    }

}
