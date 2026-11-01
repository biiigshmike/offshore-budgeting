import Foundation

enum CategoryDetailCalculator {
    struct Result {
        let items: [CategoryDetailExpenseItem]
        let plannedTotal: Double
        let variableTotal: Double
        let displayTotal: Double
        let hiddenFuturePlannedCount: Int
        let hiddenFutureVariableCount: Int
    }

    static func calculate(
        workspaceID: UUID,
        categoryID: UUID,
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        startDate: Date,
        endDate: Date,
        searchText: String = "",
        scope: ExpenseScope = .unified,
        sortMode: CategoryDetailSortMode = .dateDesc,
        hideFuturePlanned: Bool = false,
        excludeFuturePlanned: Bool = false,
        hideFutureVariable: Bool = false,
        excludeFutureVariable: Bool = false,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Result {
        let start = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDate
        let query = SearchQueryParser.parse(searchText)

        let planned = plannedExpenses.filter { expense in
            expense.workspace?.id == workspaceID && expense.category?.id == categoryID
                && expense.expenseDate >= start && expense.expenseDate < endExclusive
                && SearchMatch.matchesDateRange(query, date: expense.expenseDate)
                && SearchMatch.matchesTextTerms(query, in: [expense.title, expense.category?.name])
        }
        let variable = variableExpenses.filter { expense in
            expense.workspace?.id == workspaceID && expense.category?.id == categoryID
                && expense.transactionDate >= start && expense.transactionDate < endExclusive
                && SearchMatch.matchesDateRange(query, date: expense.transactionDate)
                && SearchMatch.matchesTextTerms(query, in: [expense.descriptionText, expense.category?.name])
        }

        let visiblePlanned = PlannedExpenseFuturePolicy.filteredForVisibility(
            planned, hideFuture: hideFuturePlanned, now: now, calendar: calendar
        )
        let visibleVariable = VariableExpenseFuturePolicy.filteredForVisibility(
            variable, hideFuture: hideFutureVariable, now: now, calendar: calendar
        )
        let plannedTotal = PlannedExpenseFuturePolicy.filteredForCalculations(
            planned, excludeFuture: excludeFuturePlanned, now: now, calendar: calendar
        ).reduce(0) { $0 + $1.effectiveAmount() }
        let variableTotal = VariableExpenseFuturePolicy.filteredForCalculations(
            variable, excludeFuture: excludeFutureVariable, now: now, calendar: calendar
        ).reduce(0) { $0 + $1.spendingAmount() }

        let items: [CategoryDetailExpenseItem]
        let displayTotal: Double
        switch scope {
        case .planned:
            items = visiblePlanned.map(CategoryDetailExpenseItem.planned)
            displayTotal = plannedTotal
        case .variable:
            items = visibleVariable.map(CategoryDetailExpenseItem.variable)
            displayTotal = variableTotal
        case .unified:
            items = visiblePlanned.map(CategoryDetailExpenseItem.planned)
                + visibleVariable.map(CategoryDetailExpenseItem.variable)
            displayTotal = plannedTotal + variableTotal
        }

        return Result(
            items: sorted(items, by: sortMode),
            plannedTotal: plannedTotal,
            variableTotal: variableTotal,
            displayTotal: displayTotal,
            hiddenFuturePlannedCount: planned.count - visiblePlanned.count,
            hiddenFutureVariableCount: variable.count - visibleVariable.count
        )
    }

    private static func sorted(
        _ items: [CategoryDetailExpenseItem], by mode: CategoryDetailSortMode
    ) -> [CategoryDetailExpenseItem] {
        items.sorted { lhs, rhs in
            switch mode {
            case .az, .za:
                let comparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                if comparison == .orderedSame { return lhs.id < rhs.id }
                return comparison == (mode == .az ? .orderedAscending : .orderedDescending)
            case .amountAsc, .amountDesc:
                if lhs.sortAmount == rhs.sortAmount { return lhs.id < rhs.id }
                return mode == .amountAsc ? lhs.sortAmount < rhs.sortAmount : lhs.sortAmount > rhs.sortAmount
            case .dateAsc, .dateDesc:
                if lhs.date == rhs.date { return lhs.id < rhs.id }
                return mode == .dateAsc ? lhs.date < rhs.date : lhs.date > rhs.date
            }
        }
    }
}
