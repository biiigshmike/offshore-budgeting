import Foundation
import Testing
@testable import Offshore

@MainActor
struct CategoryDetailCalculatorTests {
    private let workspace = Workspace(name: "Personal", hexColor: "#0099AA")

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 4, day: day, hour: hour))!
    }

    private func category(_ name: String = "Travel") -> Offshore.Category {
        Offshore.Category(name: name, hexColor: "#0066AA", workspace: workspace)
    }

    private func calculate(
        category: Offshore.Category,
        planned: [PlannedExpense] = [],
        variable: [VariableExpense] = [],
        start: Date? = nil,
        end: Date? = nil,
        search: String = "",
        scope: ExpenseScope = .unified,
        sort: CategoryDetailSortMode = .dateDesc,
        hidePlanned: Bool = false,
        excludePlanned: Bool = false,
        hideVariable: Bool = false,
        excludeVariable: Bool = false
    ) -> CategoryDetailCalculator.Result {
        CategoryDetailCalculator.calculate(
            workspaceID: workspace.id, categoryID: category.id,
            plannedExpenses: planned, variableExpenses: variable,
            startDate: start ?? date(1), endDate: end ?? date(30),
            searchText: search, scope: scope, sortMode: sort,
            hideFuturePlanned: hidePlanned, excludeFuturePlanned: excludePlanned,
            hideFutureVariable: hideVariable, excludeFutureVariable: excludeVariable,
            now: date(15), calendar: calendar
        )
    }

    @Test func includesAllCardsCardlessHistoryAndDifferentBudgetsWithinWorkspaceAndCategory() {
        let travel = category()
        let otherCategory = category("Food")
        let otherWorkspace = Workspace(name: "Work", hexColor: "#AA0000")
        let firstCard = Card(name: "First", workspace: workspace)
        let secondCard = Card(name: "Second", workspace: workspace)
        let plans = [
            PlannedExpense(title: "First budget", plannedAmount: 10, expenseDate: date(2), workspace: workspace,
                           card: firstCard, category: travel, sourceBudgetID: UUID()),
            PlannedExpense(title: "Second budget", plannedAmount: 20, expenseDate: date(20), workspace: workspace,
                           card: secondCard, category: travel, sourceBudgetID: UUID()),
            PlannedExpense(title: "Cardless plan", plannedAmount: 30, expenseDate: date(25), workspace: workspace,
                           category: travel),
            PlannedExpense(title: "Other category", plannedAmount: 100, expenseDate: date(5), workspace: workspace,
                           category: otherCategory),
            PlannedExpense(title: "Other workspace", plannedAmount: 200, expenseDate: date(5), workspace: otherWorkspace,
                           category: travel)
        ]
        let expenses = [
            VariableExpense(descriptionText: "First card", amount: 40, transactionDate: date(5), workspace: workspace,
                            card: firstCard, category: travel),
            VariableExpense(descriptionText: "Second card", amount: 50, transactionDate: date(10), workspace: workspace,
                            card: secondCard, category: travel),
            VariableExpense(descriptionText: "Cardless", amount: 60, transactionDate: date(15), workspace: workspace,
                            category: travel),
            VariableExpense(descriptionText: "Other workspace", amount: 300, transactionDate: date(5), workspace: otherWorkspace,
                            category: travel),
            VariableExpense(descriptionText: "Uncategorized", amount: 400, transactionDate: date(5), workspace: workspace)
        ]

        let result = calculate(category: travel, planned: plans, variable: expenses)

        #expect(result.items.count == 6)
        #expect(result.plannedTotal == 60)
        #expect(result.variableTotal == 150)
        #expect(result.displayTotal == 210)
    }

    @Test func dateRangeIncludesEntireBoundaryDaysAndExcludesAdjacentDays() {
        let travel = category()
        let dates = [date(9, hour: 23), date(10, hour: 0), date(12, hour: 0).addingTimeInterval(-0.25), date(12, hour: 0)]
        let plans = dates.enumerated().map { index, date in
            PlannedExpense(title: "Plan \(index)", plannedAmount: 10, expenseDate: date, workspace: workspace, category: travel)
        }
        let expenses = dates.enumerated().map { index, date in
            VariableExpense(descriptionText: "Expense \(index)", amount: 20, transactionDate: date,
                            workspace: workspace, category: travel)
        }

        let result = calculate(category: travel, planned: plans, variable: expenses, start: date(10), end: date(11))

        #expect(Set(result.items.map(\.title)) == ["Plan 1", "Plan 2", "Expense 1", "Expense 2"])
        #expect(result.displayTotal == 60)
    }

    @Test func searchMatchesTitleCategoryAndParsedDateWithinAppliedRange() {
        let travel = category()
        let plan = PlannedExpense(title: "Hotel", plannedAmount: 70, expenseDate: date(12), workspace: workspace, category: travel)
        let expense = VariableExpense(descriptionText: "Hotel booking", amount: 30, transactionDate: date(13),
                                      workspace: workspace, category: travel)

        #expect(calculate(category: travel, planned: [plan], variable: [expense], search: "hotel travel").displayTotal == 100)
        #expect(calculate(category: travel, planned: [plan], variable: [expense], search: "booking").displayTotal == 30)
        #expect(calculate(category: travel, planned: [plan], variable: [expense], search: "04/12/2026").items.map(\.title) == ["Hotel"])
        #expect(calculate(category: travel, planned: [plan], variable: [expense], start: date(13), search: "04/12/2026").items.isEmpty)
        #expect(calculate(category: travel, planned: [plan], variable: [expense], search: "missing").displayTotal == 0)
    }

    @Test func plannedFallbackAndTransactionKindsMatchCardDetailSpendingMath() {
        let travel = category()
        let plans = [
            PlannedExpense(title: "Unrecorded", plannedAmount: 100, expenseDate: date(10), workspace: workspace, category: travel),
            PlannedExpense(title: "Recorded", plannedAmount: 200, actualAmount: 80, expenseDate: date(11), workspace: workspace, category: travel)
        ]
        let expenses = [VariableExpenseKind.debit, .credit, .adjustment].map { kind in
            VariableExpense(descriptionText: kind.rawValue, amount: 50, kindRaw: kind.rawValue,
                            transactionDate: date(12), workspace: workspace, category: travel)
        }

        let combined = calculate(category: travel, planned: plans, variable: expenses)
        let planned = calculate(category: travel, planned: plans, variable: expenses, scope: .planned)
        let variable = calculate(category: travel, planned: plans, variable: expenses, scope: .variable)

        #expect(combined.displayTotal == 230)
        #expect(combined.items.count == 5)
        #expect(planned.displayTotal == 180)
        #expect(planned.items.count == 2)
        #expect(variable.displayTotal == 50)
        #expect(variable.items.count == 3)
    }

    @Test func sharedSplitsAndSavingsOffsetsDoNotReduceGrossTotals() {
        let travel = category()
        let plan = PlannedExpense(title: "Shared hotel", plannedAmount: 100, expenseDate: date(10), workspace: workspace, category: travel)
        let splitExpense = VariableExpense(descriptionText: "Shared dinner", amount: 60, transactionDate: date(11),
                                           workspace: workspace, category: travel)
        let savingsExpense = VariableExpense(descriptionText: "Savings purchase", amount: 40, transactionDate: date(12),
                                             workspace: workspace, category: travel)
        let planAllocation = ExpenseAllocation(allocatedAmount: 30, preservesGrossAmount: true, plannedExpense: plan)
        let variableAllocation = ExpenseAllocation(allocatedAmount: 20, preservesGrossAmount: true, expense: splitExpense)
        let savingsEntry = SavingsLedgerEntry(date: date(12), amount: -25, note: "Offset",
                                              kindRaw: SavingsLedgerEntryKind.expenseOffset.rawValue, variableExpense: savingsExpense)
        plan.allocation = planAllocation
        splitExpense.allocation = variableAllocation
        savingsExpense.savingsLedgerEntry = savingsEntry

        let result = calculate(category: travel, planned: [plan], variable: [splitExpense, savingsExpense])

        #expect(result.plannedTotal == 100)
        #expect(result.variableTotal == 100)
        #expect(result.displayTotal == 200)
    }

    @Test func allFutureVisibilityAndCalculationCombinationsRemainIndependent() {
        let travel = category()
        let plans = [
            PlannedExpense(title: "Today plan", plannedAmount: 10, expenseDate: date(15, hour: 23), workspace: workspace, category: travel),
            PlannedExpense(title: "Future plan", plannedAmount: 20, expenseDate: date(16), workspace: workspace, category: travel)
        ]
        let expenses = [
            VariableExpense(descriptionText: "Today expense", amount: 30, transactionDate: date(15, hour: 23), workspace: workspace, category: travel),
            VariableExpense(descriptionText: "Future expense", amount: 40, transactionDate: date(16), workspace: workspace, category: travel)
        ]

        for hidePlanned in [false, true] {
            for excludePlanned in [false, true] {
                for hideVariable in [false, true] {
                    for excludeVariable in [false, true] {
                        let result = calculate(
                            category: travel, planned: plans, variable: expenses,
                            hidePlanned: hidePlanned, excludePlanned: excludePlanned,
                            hideVariable: hideVariable, excludeVariable: excludeVariable
                        )
                        #expect(result.items.count == 4 - (hidePlanned ? 1 : 0) - (hideVariable ? 1 : 0))
                        #expect(result.hiddenFuturePlannedCount == (hidePlanned ? 1 : 0))
                        #expect(result.hiddenFutureVariableCount == (hideVariable ? 1 : 0))
                        #expect(result.plannedTotal == (excludePlanned ? 10 : 30))
                        #expect(result.variableTotal == (excludeVariable ? 30 : 70))
                    }
                }
            }
        }
    }

    @Test func allSortModesOrderMixedExpenseTypesWithoutChangingTotal() {
        let travel = category()
        let plan = PlannedExpense(title: "alpha", plannedAmount: 30, expenseDate: date(12), workspace: workspace, category: travel)
        let bravo = VariableExpense(descriptionText: "Bravo", amount: -10, kindRaw: VariableExpenseKind.credit.rawValue,
                                   transactionDate: date(11), workspace: workspace, category: travel)
        let charlie = VariableExpense(descriptionText: "Charlie", amount: 20, transactionDate: date(10),
                                     workspace: workspace, category: travel)
        let cases: [(CategoryDetailSortMode, [String])] = [
            (.az, ["alpha", "Bravo", "Charlie"]), (.za, ["Charlie", "Bravo", "alpha"]),
            (.amountAsc, ["Bravo", "Charlie", "alpha"]), (.amountDesc, ["alpha", "Charlie", "Bravo"]),
            (.dateAsc, ["Charlie", "Bravo", "alpha"]), (.dateDesc, ["alpha", "Bravo", "Charlie"])
        ]

        for (sort, expectedTitles) in cases {
            let result = calculate(category: travel, planned: [plan], variable: [bravo, charlie], sort: sort)
            #expect(result.items.map(\.title) == expectedTitles)
            #expect(result.displayTotal == 50)
        }
    }

    @Test func tiesAreStableAndSameUUIDAcrossExpenseTypesDoesNotCollide() {
        let travel = category()
        let id = UUID()
        let plan = PlannedExpense(id: id, title: "Same", plannedAmount: 10, expenseDate: date(10), workspace: workspace, category: travel)
        let expense = VariableExpense(id: id, descriptionText: "Same", amount: 10, transactionDate: date(10), workspace: workspace, category: travel)

        for sort in CategoryDetailSortMode.allCases {
            let result = calculate(category: travel, planned: [plan], variable: [expense], sort: sort)
            #expect(Set(result.items.map(\.id)).count == 2)
            #expect(result.items.map(\.id) == result.items.map(\.id).sorted())
        }
    }

    @Test func categoryReassignmentAndAmountEditsAreReflectedWhenRecalculated() {
        let travel = category()
        let food = category("Food")
        let expense = VariableExpense(descriptionText: "Purchase", amount: 25, transactionDate: date(10), workspace: workspace, category: travel)
        #expect(calculate(category: travel, variable: [expense]).displayTotal == 25)

        expense.amount = 40
        #expect(calculate(category: travel, variable: [expense]).displayTotal == 40)

        expense.category = food
        #expect(calculate(category: travel, variable: [expense]).items.isEmpty)
        #expect(calculate(category: food, variable: [expense]).displayTotal == 40)
    }
}
