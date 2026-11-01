import Foundation
import Testing
@testable import Offshore

@MainActor
struct CategoryAvailabilityStatusTests {
    @Test func zeroMaximumIsARealGoalAndClassifiesSpending() {
        let over = metric(maximum: 0, spending: 5)
        #expect(over.isLimited)
        #expect(over.status(for: .all, nearThreshold: 0.1) == .over)
        #expect(over.availableRaw(for: .all) == -5)
        #expect(over.percentUsed(for: .all) == nil)
        #expect(metric(maximum: 0, spending: 0).status(for: .all, nearThreshold: 0.1) == .ok)
        #expect(metric(maximum: 0, spending: -5).status(for: .all, nearThreshold: 0.1) == .ok)
    }

    @Test func explicitZeroMinimumAndMaximumWithNoSpendingAreOK() throws {
        let workspace = Workspace(name: "Personal", hexColor: "#000000")
        let now = Date.now
        let budget = Budget(name: "Current", startDate: now, endDate: now, workspace: workspace)
        let category = Offshore.Category(name: "Dining", hexColor: "#000000", workspace: workspace)
        let goal = BudgetCategoryLimit(minAmount: 0, maxAmount: 0, budget: budget, category: category)
        budget.categoryLimits = [goal]

        let result = HomeCategoryLimitsAggregator.build(
            budgets: [budget], categories: [category], plannedExpenses: [], variableExpenses: [],
            rangeStart: now, rangeEnd: now
        )
        let value = try #require(result.metrics.first)
        #expect(value.maxAmount == 0) // Explicit zero remains a goal, rather than Unlimited.
        #expect(value.isLimited)
        #expect(value.availableRaw(for: .all) == 0)
        for scope in AvailabilityScope.allCases {
            #expect(value.status(for: scope, nearThreshold: 0.1) == .ok)
        }
        #expect(result.nearCount == 0)
        #expect(result.overCount == 0)
    }

    @Test func positiveMaximumStillUsesTheExistingNearThreshold() {
        #expect(metric(maximum: 100, spending: 89).status(for: .all, nearThreshold: 0.1) == .ok)
        #expect(metric(maximum: 100, spending: 90).status(for: .all, nearThreshold: 0.1) == .near)
        #expect(metric(maximum: 100, spending: 100).status(for: .all, nearThreshold: 0.1) == .near)
    }

    @Test func unlimitedAndInvalidNegativeMaximumsStayUnclassified() {
        for maximum in [nil, -1.0] as [Double?] {
            let value = metric(maximum: maximum, spending: 50)
            #expect(!value.isLimited)
            #expect(value.status(for: .all, nearThreshold: 0.1) == .ok)
        }
    }

    @Test func headerCountsIncludeZeroMaximumGoals() {
        let workspace = Workspace(name: "Personal", hexColor: "#000000")
        let now = Date.now
        let budget = Budget(name: "Current", startDate: now, endDate: now, workspace: workspace)
        let category = Offshore.Category(name: "Dining", hexColor: "#000000", workspace: workspace)
        let goal = BudgetCategoryLimit(maxAmount: 0, budget: budget, category: category)
        budget.categoryLimits = [goal]
        let expense = VariableExpense(descriptionText: "Lunch", amount: 10, transactionDate: now,
                                      workspace: workspace, category: category)
        let result = HomeCategoryLimitsAggregator.build(
            budgets: [budget], categories: [category], plannedExpenses: [], variableExpenses: [expense],
            rangeStart: now, rangeEnd: now
        )
        #expect(result.overCount == 1)
        #expect(result.nearCount == 0)
    }

    private func metric(maximum: Double?, spending: Double) -> CategoryAvailabilityMetric {
        let id = UUID()
        return CategoryAvailabilityMetric(id: id, categoryID: id, name: "Dining", colorHex: "#000000",
                                          maxAmount: maximum, spentPlanned: 0, spentVariable: spending)
    }
}
