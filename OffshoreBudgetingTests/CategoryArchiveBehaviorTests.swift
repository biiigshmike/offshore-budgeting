import Foundation
import Testing
@testable import Offshore

struct CategoryArchiveBehaviorTests {
    @Test func homeAvailability_hidesUnrelatedArchivedCategoriesAndOutOfRangeHistory() {
        let active = Category(name: "Active", hexColor: "#00AA00")
        let archived = Category(name: "Archived", hexColor: "#FF0000", isArchived: true)
        let planned = PlannedExpense(title: "Old plan", plannedAmount: 20, expenseDate: date(3, 31), category: archived)
        let variable = VariableExpense(descriptionText: "Later expense", amount: 30, transactionDate: date(5, 1), category: archived)

        let result = HomeCategoryLimitsAggregator.build(
            budgets: [], categories: [active, archived],
            plannedExpenses: [planned], variableExpenses: [variable],
            rangeStart: date(4, 1), rangeEnd: date(4, 30)
        )

        #expect(result.metrics.map(\.categoryID) == [active.id])
    }

    @Test func homeAvailability_retainsArchivedExpenseReferencesAtInclusiveBoundaries() throws {
        let plannedCategory = Category(name: "Old plan", hexColor: "#00AA00", isArchived: true)
        let variableCategory = Category(name: "Old ledger", hexColor: "#FF0000", isArchived: true)
        let planned = PlannedExpense(title: "Plan", plannedAmount: 20, expenseDate: date(4, 1, hour: 0), category: plannedCategory)
        let variable = VariableExpense(
            descriptionText: "Adjustment", amount: 30,
            kindRaw: VariableExpenseKind.adjustment.rawValue,
            transactionDate: date(4, 30, hour: 23), category: variableCategory
        )

        let result = HomeCategoryLimitsAggregator.build(
            budgets: [], categories: [plannedCategory, variableCategory],
            plannedExpenses: [planned], variableExpenses: [variable],
            rangeStart: date(4, 1), rangeEnd: date(4, 30)
        )

        #expect(Set(result.metrics.map(\.categoryID)) == [plannedCategory.id, variableCategory.id])
        let plannedMetric = try #require(result.metrics.first { $0.categoryID == plannedCategory.id })
        let variableMetric = try #require(result.metrics.first { $0.categoryID == variableCategory.id })
        #expect(plannedMetric.spentPlanned == 20)
        #expect(variableMetric.spentVariable == 0)
    }

    @Test func homeAvailability_retainsOnlySelectedBudgetLimitReferences() throws {
        let retained = Category(name: "Historical limit", hexColor: "#00AA00", isArchived: true)
        let unrelated = Category(name: "Other budget", hexColor: "#FF0000", isArchived: true)
        let selected = Budget(name: "April", startDate: date(4, 1), endDate: date(4, 30))
        let other = Budget(name: "March", startDate: date(3, 1), endDate: date(3, 31))
        selected.categoryLimits = [BudgetCategoryLimit(maxAmount: 100, category: retained)]
        other.categoryLimits = [BudgetCategoryLimit(maxAmount: 50, category: unrelated)]

        for policy in [HomeCategoryLimitsAggregator.CategoryInclusionPolicy.allCategoriesInfinityWhenMissing, .limitsOnly] {
            let result = HomeCategoryLimitsAggregator.build(
                budgets: [other, selected], categories: [retained, unrelated],
                plannedExpenses: [], variableExpenses: [],
                rangeStart: date(4, 1), rangeEnd: date(4, 30), inclusionPolicy: policy
            )

            #expect(result.activeBudget?.id == selected.id)
            #expect(result.metrics.map(\.categoryID) == [retained.id])
            let metric = try #require(result.metrics.first)
            #expect(metric.maxAmount == 100)
            #expect(metric.spentTotal == 0)
        }
    }

    private func date(_ month: Int, _ day: Int, hour: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    @Test func importCategoryMatching_ignoresArchivedLearnedCategory() {
        let archivedCategory = Category(
            name: "Groceries",
            hexColor: "#00AA00",
            isArchived: true,
            archivedAt: Date()
        )
        let activeCategory = Category(name: "Dining", hexColor: "#FFAA00")
        let learnedRule = ImportMerchantRule(
            merchantKey: MerchantNormalizer.normalizeKey("Whole Foods"),
            preferredName: "Whole Foods",
            preferredCategory: archivedCategory
        )

        let suggestion = CategoryMatchingEngine.suggest(
            csvCategory: nil,
            merchant: "Whole Foods",
            availableCategories: [activeCategory],
            learnedRule: learnedRule
        )

        #expect(suggestion.category == nil)
    }
}
