import Foundation

@MainActor
enum CategoryGoalSuggestionCalculator {
    /// Uses the same category budget-impact math and historical card scoping as Budget Detail.
    /// This is a read-only preview; no financial records or saved goals are changed.
    static func calculate(
        workspaceID: UUID,
        budgets: [Budget],
        categories: [Category],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        startDate: Date,
        endDate: Date,
        historyCount: Int = 3,
        cushionPercent: Double = 0,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [UUID: CategoryGoalSuggestion] {
        guard startDate <= endDate else { return [:] }
        let startDay = calendar.startOfDay(for: startDate)
        let cutoff = min(startDay, calendar.startOfDay(for: now))
        let targetDays = inclusiveDays(startDate, endDate, calendar: calendar)
        let categoryIDs = Set(categories.filter { $0.workspace?.id == workspaceID }.map(\.id))
        guard !categoryIDs.isEmpty else { return [:] }

        let workspaceBudgets = budgets.filter { $0.workspace?.id == workspaceID }
        let candidates = workspaceBudgets.filter {
            $0.startDate <= $0.endDate
                && calendar.startOfDay(for: $0.endDate) < cutoff
                && comparable(inclusiveDays($0.startDate, $0.endDate, calendar: calendar), targetDays)
        }.sorted {
            let lhsEnd = calendar.startOfDay(for: $0.endDate)
            let rhsEnd = calendar.startOfDay(for: $1.endDate)
            if lhsEnd != rhsEnd { return lhsEnd > rhsEnd }
            let lhsStart = calendar.startOfDay(for: $0.startDate)
            let rhsStart = calendar.startOfDay(for: $1.startDate)
            if lhsStart != rhsStart { return lhsStart > rhsStart }
            return $0.id.uuidString < $1.id.uuidString
        }

        var selected: [Budget] = []
        var selectedRanges: [DateRange] = []
        for budget in candidates {
            let range = DateRange(start: budget.startDate, end: budget.endDate, calendar: calendar)
            // Compare directly to preserve the injected calendar throughout selection.
            guard !selectedRanges.contains(where: { $0.start <= range.end && range.start <= $0.end }) else { continue }
            selected.append(budget)
            selectedRanges.append(range)
            if selected.count == min(12, max(1, historyCount)) { break }
        }
        guard !selected.isEmpty else { return [:] }

        let workspacePlanned = plannedExpenses.filter {
            $0.workspace?.id == workspaceID && $0.category?.workspace?.id == workspaceID
                && $0.card?.workspace?.id == workspaceID
        }
        let workspaceVariable = variableExpenses.filter {
            $0.workspace?.id == workspaceID && $0.category?.workspace?.id == workspaceID
                && $0.card?.workspace?.id == workspaceID
        }

        // Category creation dates are unavailable. Earliest dated usage is the evidence
        // that lets subsequent empty periods count as zero without inventing older history.
        var firstEvidence: [UUID: Date] = [:]
        func recordEvidence(categoryID: UUID?, date: Date) {
            guard let categoryID, categoryIDs.contains(categoryID), date < cutoff else { return }
            firstEvidence[categoryID] = min(firstEvidence[categoryID] ?? date, date)
        }
        for expense in workspacePlanned {
            recordEvidence(categoryID: expense.category?.id, date: expense.expenseDate)
        }
        for expense in workspaceVariable {
            recordEvidence(categoryID: expense.category?.id, date: expense.transactionDate)
        }
        for budget in workspaceBudgets where budget.startDate <= budget.endDate {
            for goal in budget.categoryLimits ?? [] where goal.budget?.id == budget.id {
                guard goal.category?.workspace?.id == workspaceID else { continue }
                recordEvidence(categoryID: goal.category?.id, date: calendar.startOfDay(for: budget.startDate))
            }
        }

        var samplesByCategory: [UUID: [CategoryGoalHistorySample]] = [:]
        for (budget, range) in zip(selected, selectedRanges) {
            let cardIDs = Set((budget.cardLinks ?? []).compactMap { link -> UUID? in
                guard link.budget?.id == budget.id, link.card?.workspace?.id == workspaceID else { return nil }
                return link.card?.id
            })
            var totals: [UUID: Double] = [:]
            for expense in BudgetPlannedExpenseStore.plannedExpenses(
                workspacePlanned, budgetID: budget.id, linkedCardIDs: cardIDs, range: range
            ) {
                guard let categoryID = expense.category?.id, categoryIDs.contains(categoryID) else { continue }
                totals[categoryID, default: 0] += SavingsMathService.plannedBudgetImpactAmount(for: expense)
            }
            for expense in workspaceVariable {
                guard let cardID = expense.card?.id, cardIDs.contains(cardID),
                      range.start <= expense.transactionDate, expense.transactionDate <= range.end,
                      let categoryID = expense.category?.id, categoryIDs.contains(categoryID) else { continue }
                totals[categoryID, default: 0] += SavingsMathService.variableBudgetImpactAmount(for: expense)
            }
            for categoryID in categoryIDs {
                guard let evidence = firstEvidence[categoryID], evidence <= range.end else { continue }
                samplesByCategory[categoryID, default: []].append(CategoryGoalHistorySample(
                    budgetID: budget.id, name: budget.name,
                    startDate: budget.startDate, endDate: budget.endDate,
                    amount: totals[categoryID] ?? 0
                ))
            }
        }

        let cushion = cushionPercent.isFinite ? min(100, max(0, cushionPercent)) : 0
        var result: [UUID: CategoryGoalSuggestion] = [:]
        for (categoryID, samples) in samplesByCategory {
            let average = samples.reduce(0) { $0 + $1.amount } / Double(samples.count)
            guard average.isFinite else { continue }
            result[categoryID] = CategoryGoalSuggestion(averageAmount: average, cushionPercent: cushion, samples: samples)
        }
        return result
    }

    private static func inclusiveDays(_ start: Date, _ end: Date, calendar: Calendar) -> Int {
        (calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                 to: calendar.startOfDay(for: end)).day ?? 0) + 1
    }

    private static func comparable(_ lhs: Int, _ rhs: Int) -> Bool {
        lhs == rhs || [28...31, 90...92, 365...366].contains { $0.contains(lhs) && $0.contains(rhs) }
    }
}
