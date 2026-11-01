import Foundation
import Testing
@testable import Offshore

@MainActor
struct CategoryGoalSuggestionCalculatorTests {
    @Test func averagesComparableMonthsAndExplainsSamplesWithoutScaling() throws {
        let workspace = Workspace(name: "Personal", hexColor: "#000000")
        let category = Category(name: "Food", hexColor: "#000000", workspace: workspace)
        let card = Card(name: "Debit", workspace: workspace)
        let budgets = [budget("January", 1, 1, 1, 31, workspace, card),
                       budget("February", 2, 1, 2, 28, workspace, card),
                       budget("March", 3, 1, 3, 31, workspace, card)]
        let expenses = [variable(400, budgets[0].startDate, workspace, card, category),
                        variable(500, budgets[1].startDate, workspace, card, category),
                        variable(450, budgets[2].startDate, workspace, card, category)]
        let result = calculate(workspace, [category], budgets, variable: expenses, cushion: 10)
        let suggestion = try #require(result[category.id])
        #expect(suggestion.averageAmount == 450)
        #expect(suggestion.maximum() == CurrencyFormatter.roundedToCurrency(495))
        #expect(suggestion.maximum(plannedMinimum: 600) == 600)
        #expect(suggestion.maximum(plannedMinimum: 300, enteredMinimum: 650) == 650)
        #expect(suggestion.samples.map(\.name) == ["March", "February", "January"])
        #expect(suggestion.samples.map(\.amount) == [450, 500, 400])
        #expect(suggestion.samples.first?.startDate == budgets[2].startDate)
        #expect(suggestion.samples.first?.endDate == budgets[2].endDate)
    }

    @Test func sparseHistoryUsesAvailableSamplesAndNoHistoryStaysAbsent() throws {
        let workspace = Workspace(name: "Personal", hexColor: "#000000")
        let category = Category(name: "Food", hexColor: "#000000", workspace: workspace)
        let card = Card(name: "Debit", workspace: workspace)
        let march = budget("March", 3, 1, 3, 31, workspace, card)
        let expense = variable(123, date(3, 5), workspace, card, category)
        let suggestion = try #require(calculate(workspace, [category], [march], variable: [expense])[category.id])
        #expect(suggestion.samples.count == 1)
        #expect(suggestion.averageAmount == 123)
        #expect(calculate(workspace, [category], [march]).isEmpty)
        #expect(calculate(workspace, [category], []).isEmpty)
    }

    @Test func zerosCountAfterEvidenceAndNewCategoriesDoNotInheritOlderZeros() throws {
        let workspace = Workspace(name: "Personal", hexColor: "#000000")
        let card = Card(name: "Debit", workspace: workspace)
        let established = Category(name: "Established", hexColor: "#000000", workspace: workspace)
        let recent = Category(name: "New", hexColor: "#000000", workspace: workspace)
        let unused = Category(name: "Unused", hexColor: "#000000", workspace: workspace)
        let goalOnly = Category(name: "Goal", hexColor: "#000000", workspace: workspace)
        let january = budget("January", 1, 1, 1, 31, workspace, card)
        let february = budget("February", 2, 1, 2, 28, workspace, card)
        let march = budget("March", 3, 1, 3, 31, workspace, card)
        january.categoryLimits = [BudgetCategoryLimit(maxAmount: 20, budget: january, category: goalOnly)]
        let expenses = [variable(90, date(1, 15), workspace, card, established),
                        variable(60, date(3, 15), workspace, card, recent)]
        let result = calculate(workspace, [established, recent, unused, goalOnly],
                               [january, february, march], variable: expenses)
        #expect(result[established.id]?.samples.count == 3)
        #expect(result[established.id]?.averageAmount == 30)
        #expect(result[recent.id]?.samples.count == 1)
        #expect(result[recent.id]?.averageAmount == 60)
        #expect(result[goalOnly.id]?.samples.count == 3)
        #expect(result[goalOnly.id]?.maximum() == 0)
        #expect(result[unused.id] == nil)

        let recentOnly = calculate(workspace, [established], [january, february, march],
                                   variable: expenses, count: 2)
        #expect(recentOnly[established.id]?.samples.count == 2)
        #expect(recentOnly[established.id]?.averageAmount == 0)
    }

    @Test func ongoingBudgetGoalEstablishesHistoryWithoutBecomingASample() {
        let workspace = Workspace(name: "Personal", hexColor: "#000000")
        let category = Category(name: "Food", hexColor: "#000000", workspace: workspace)
        let card = Card(name: "Debit", workspace: workspace)
        let ongoing = budget("Annual", 1, 1, 12, 31, workspace, card)
        ongoing.categoryLimits = [BudgetCategoryLimit(maxAmount: 500, budget: ongoing, category: category)]
        let march = budget("March", 3, 1, 3, 31, workspace, card)
        let result = calculate(workspace, [category], [ongoing, march])
        #expect(result[category.id]?.samples.map(\.name) == ["March"])
        #expect(result[category.id]?.averageAmount == 0)
    }

    @Test func filtersForeignInvalidOngoingAndTargetOverlappingBudgets() throws {
        let workspace = Workspace(name: "Personal", hexColor: "#000000")
        let other = Workspace(name: "Work", hexColor: "#000000")
        let category = Category(name: "Food", hexColor: "#000000", workspace: workspace)
        let card = Card(name: "Debit", workspace: workspace)
        let march = budget("March", 3, 1, 3, 31, workspace, card)
        let ongoing = budget("Ongoing", 4, 1, 4, 30, workspace, card)
        let afterTarget = budget("After target", 5, 1, 5, 31, workspace, card)
        let foreign = budget("Work", 2, 1, 2, 28, other, card)
        let invalid = budget("Invalid", 2, 28, 2, 1, workspace, card)
        let weekly = budget("Week", 2, 1, 2, 7, workspace, card)
        let expenses = [variable(30, date(3, 1), workspace, card, category)]
        let result = CategoryGoalSuggestionCalculator.calculate(
            workspaceID: workspace.id, budgets: [ongoing, afterTarget, foreign, invalid, weekly, march],
            categories: [category], plannedExpenses: [], variableExpenses: expenses,
            startDate: date(5, 1), endDate: date(5, 31), now: date(4, 30, 12), calendar: calendar
        )
        #expect(result[category.id]?.samples.map(\.name) == ["March"])

        let beforeTarget = CategoryGoalSuggestionCalculator.calculate(
            workspaceID: workspace.id, budgets: [march, ongoing], categories: [category],
            plannedExpenses: [], variableExpenses: expenses,
            startDate: date(3, 31), endDate: date(4, 30), now: date(6, 1), calendar: calendar
        )
        #expect(beforeTarget.isEmpty)
    }

    @Test func overlappingWindowsAreSkippedAndSelectionContinuesToOlderHistory() throws {
        let workspace = Workspace(name: "Personal", hexColor: "#000000")
        let category = Category(name: "Food", hexColor: "#000000", workspace: workspace)
        let card = Card(name: "Debit", workspace: workspace)
        let january = budget("January", 1, 1, 1, 31, workspace, card)
        let shifted = budget("Shifted", 1, 15, 2, 14, workspace, card)
        let march = budget("March", 3, 1, 3, 31, workspace, card)
        let expenses = [variable(100, date(1, 20), workspace, card, category),
                        variable(200, date(3, 20), workspace, card, category)]
        let result = calculate(workspace, [category], [january, shifted, march], variable: expenses)
        #expect(result[category.id]?.samples.map(\.name) == ["March", "Shifted"])
        #expect(result[category.id]?.averageAmount == 150)
    }

    @Test func selectionTiesUseNewestStartThenStableBudgetID() throws {
        let workspace = Workspace(name: "Personal", hexColor: "#000000")
        let category = Category(name: "Food", hexColor: "#000000", workspace: workspace)
        let card = Card(name: "Debit", workspace: workspace)
        let earlierStart = budget("Earlier start", 1, 1, 1, 31, workspace, card)
        let higherID = budget("Higher ID", 1, 2, 1, 31, workspace, card)
        let lowerID = budget("Lower ID", 1, 2, 1, 31, workspace, card)
        higherID.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        lowerID.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let expense = variable(25, date(1, 15), workspace, card, category)
        for budgets in [[earlierStart, higherID, lowerID], [lowerID, higherID, earlierStart]] {
            let result = calculate(workspace, [category], budgets, variable: [expense])
            #expect(result[category.id]?.samples.map(\.name) == ["Lower ID"])
        }
    }

    @Test func matchingDurationGroupsIncludeLeapYearsAndCustomRangesRequireExactDays() {
        let workspace = Workspace(name: "Personal", hexColor: "#000000")
        let category = Category(name: "Food", hexColor: "#000000", workspace: workspace)
        let card = Card(name: "Debit", workspace: workspace)
        for (pastDays, targetDays, expected) in [(28, 31, true), (90, 92, true), (365, 366, true),
                                                 (14, 14, true), (13, 14, false), (7, 31, false),
                                                 (32, 31, false), (89, 90, false)] {
            let pastStart = date(1, 1, year: 2024)
            let pastEnd = calendar.date(byAdding: .day, value: pastDays - 1, to: pastStart)!
            let past = Budget(name: "Past", startDate: pastStart, endDate: pastEnd, workspace: workspace)
            past.cardLinks = [BudgetCardLink(budget: past, card: card)]
            let targetStart = date(1, 1, year: 2026)
            let targetEnd = calendar.date(byAdding: .day, value: targetDays - 1, to: targetStart)!
            let result = CategoryGoalSuggestionCalculator.calculate(
                workspaceID: workspace.id, budgets: [past], categories: [category], plannedExpenses: [],
                variableExpenses: [variable(100, pastStart, workspace, card, category)],
                startDate: targetStart, endDate: targetEnd, now: date(1, 1, year: 2027), calendar: calendar
            )
            #expect((result[category.id] != nil) == expected)
        }
    }

    @Test func inclusiveDaysAndExpenseBoundariesRemainCorrectAcrossDST() throws {
        let workspace = Workspace(name: "Personal", hexColor: "#000000")
        let category = Category(name: "Food", hexColor: "#000000", workspace: workspace)
        let card = Card(name: "Debit", workspace: workspace)
        let past = budget("DST week", 3, 6, 3, 12, workspace, card)
        let lastSecond = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: date(3, 12))!
        let expenses = [variable(10, past.startDate, workspace, card, category),
                        variable(20, lastSecond, workspace, card, category),
                        variable(100, date(3, 5, 23), workspace, card, category),
                        variable(100, date(3, 13), workspace, card, category)]
        let result = CategoryGoalSuggestionCalculator.calculate(
            workspaceID: workspace.id, budgets: [past], categories: [category], plannedExpenses: [],
            variableExpenses: expenses, startDate: date(3, 13), endDate: date(3, 19),
            now: date(4, 1), calendar: calendar
        )
        #expect(result[category.id]?.averageAmount == 30)
        #expect(result[category.id]?.samples.count == 1)
    }

    @Test func categoryTotalsReuseRecordedFallbackSplitOffsetCreditAndAdjustmentMath() throws {
        let workspace = Workspace(name: "Personal", hexColor: "#000000")
        let category = Category(name: "Food", hexColor: "#000000", workspace: workspace)
        let card = Card(name: "Debit", workspace: workspace)
        let march = budget("March", 3, 1, 3, 31, workspace, card)
        let planned = PlannedExpense(title: "Recorded", plannedAmount: 500, actualAmount: 100,
                                     expenseDate: date(3, 5), workspace: workspace, card: card,
                                     category: category, sourceBudgetID: march.id)
        planned.allocation = ExpenseAllocation(allocatedAmount: 30, preservesGrossAmount: true, plannedExpense: planned)
        planned.savingsLedgerEntry = offset(-10, workspace, planned: planned)
        let fallback = PlannedExpense(title: "Unrecorded", plannedAmount: 50, expenseDate: date(3, 6),
                                      workspace: workspace, card: card, category: category, sourceBudgetID: march.id)
        let split = variable(100, date(3, 7), workspace, card, category)
        split.allocation = ExpenseAllocation(allocatedAmount: 40, preservesGrossAmount: true, expense: split)
        let savings = variable(100, date(3, 8), workspace, card, category)
        savings.savingsLedgerEntry = offset(-25, workspace, variable: savings)
        let credit = variable(20, date(3, 9), workspace, card, category)
        credit.kind = .credit
        let adjustment = variable(999, date(3, 10), workspace, card, category)
        adjustment.kind = .adjustment
        let result = calculate(workspace, [category], [march], planned: [planned, fallback],
                               variable: [split, savings, credit, adjustment])
        #expect(result[category.id]?.averageAmount == 225)
        #expect(planned.actualAmount == 100)
        #expect(split.amount == 100)
    }

    @Test func historicalCardAndBudgetOwnershipAreRespectedEvenWithMalformedCrossWorkspaceReferences() throws {
        let workspace = Workspace(name: "Personal", hexColor: "#000000")
        let other = Workspace(name: "Work", hexColor: "#000000")
        let category = Category(name: "Food", hexColor: "#000000", workspace: workspace)
        let foreignCategory = Category(name: "Food", hexColor: "#000000", workspace: other)
        let card = Card(name: "Historical card", workspace: workspace)
        let unlinked = Card(name: "Not linked", workspace: workspace)
        let foreignCard = Card(name: "Work card", workspace: other)
        let march = budget("March", 3, 1, 3, 31, workspace, card)
        march.cardLinks?.append(BudgetCardLink(budget: march, card: foreignCard))
        let included = variable(10, date(3, 10), workspace, card, category)
        let expenses = [included,
                        variable(100, date(3, 10), workspace, unlinked, category),
                        variable(100, date(3, 10), other, card, category),
                        variable(100, date(3, 10), workspace, card, foreignCategory),
                        variable(100, date(3, 10), workspace, foreignCard, category)]
        let wrongBudget = PlannedExpense(title: "Wrong budget", plannedAmount: 100, expenseDate: date(3, 10),
                                         workspace: workspace, card: card, category: category, sourceBudgetID: UUID())
        let wrongCard = PlannedExpense(title: "Wrong card", plannedAmount: 100, expenseDate: date(3, 10),
                                       workspace: workspace, card: unlinked, category: category, sourceBudgetID: march.id)
        let result = calculate(workspace, [category, foreignCategory], [march],
                               planned: [wrongBudget, wrongCard], variable: expenses)
        #expect(result[category.id]?.averageAmount == 10)
        #expect(result[foreignCategory.id] == nil)
    }

    @Test func signedCreditsAreAveragedBeforeClampingAndMaximumUsesCurrencyRounding() throws {
        let workspace = Workspace(name: "Personal", hexColor: "#000000")
        let category = Category(name: "Food", hexColor: "#000000", workspace: workspace)
        let card = Card(name: "Debit", workspace: workspace)
        let january = budget("January", 1, 1, 1, 31, workspace, card)
        let march = budget("March", 3, 1, 3, 31, workspace, card)
        let debit = variable(100, date(1, 5), workspace, card, category)
        let credit = variable(200, date(3, 5), workspace, card, category)
        credit.kind = .credit
        let result = try #require(calculate(workspace, [category], [january, march],
                                            variable: [debit, credit])[category.id])
        #expect(result.averageAmount == -50)
        #expect(result.maximum() == 0)
        #expect(result.maximum(plannedMinimum: 25) == 25)
        let fractional = CategoryGoalSuggestion(averageAmount: 12.34567, cushionPercent: 5, samples: [])
        #expect(fractional.maximum() == CurrencyFormatter.roundedToCurrency(12.34567 * 1.05))
    }

    @Test func extraPrecisionMinimumsRoundUpWithoutAddingACentForArithmeticResidue() {
        let suggestion = CategoryGoalSuggestion(averageAmount: 0, cushionPercent: 0, samples: [])
        let minimum = 100.0000001
        let fromPlanned = suggestion.maximum(plannedMinimum: minimum)
        let fromEntered = suggestion.maximum(enteredMinimum: minimum)
        #expect(fromPlanned >= minimum)
        #expect(fromEntered >= minimum)
        #expect(fromPlanned == CurrencyFormatter.roundedToCurrency(fromPlanned))
        #expect(fromEntered == CurrencyFormatter.roundedToCurrency(fromEntered))
        #expect(CurrencyFormatter.roundedUpToCurrency(100.0 + 0.1 + 0.2)
                == CurrencyFormatter.roundedUpToCurrency(100.3))
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int = 0, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func budget(_ name: String, _ startMonth: Int, _ startDay: Int,
                        _ endMonth: Int, _ endDay: Int, _ workspace: Workspace, _ card: Card) -> Budget {
        let budget = Budget(name: name, startDate: date(startMonth, startDay),
                            endDate: date(endMonth, endDay), workspace: workspace)
        budget.cardLinks = [BudgetCardLink(budget: budget, card: card)]
        return budget
    }

    private func variable(_ amount: Double, _ date: Date, _ workspace: Workspace,
                          _ card: Card, _ category: Offshore.Category) -> VariableExpense {
        VariableExpense(descriptionText: "Expense", amount: amount, transactionDate: date,
                        workspace: workspace, card: card, category: category)
    }

    private func offset(_ amount: Double, _ workspace: Workspace,
                        planned: PlannedExpense? = nil, variable: VariableExpense? = nil) -> SavingsLedgerEntry {
        SavingsLedgerEntry(date: date(3, 10), amount: amount, note: "Offset",
                           kindRaw: SavingsLedgerEntryKind.expenseOffset.rawValue,
                           workspace: workspace, variableExpense: variable, plannedExpense: planned)
    }

    private func calculate(_ workspace: Workspace, _ categories: [Offshore.Category], _ budgets: [Budget],
                           planned: [PlannedExpense] = [], variable: [VariableExpense] = [],
                           count: Int = 3, cushion: Double = 0) -> [UUID: CategoryGoalSuggestion] {
        CategoryGoalSuggestionCalculator.calculate(
            workspaceID: workspace.id, budgets: budgets, categories: categories,
            plannedExpenses: planned, variableExpenses: variable,
            startDate: date(4, 1), endDate: date(4, 30), historyCount: count,
            cushionPercent: cushion, now: date(5, 1), calendar: calendar
        )
    }
}
