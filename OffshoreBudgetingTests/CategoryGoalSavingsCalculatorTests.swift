import Foundation
import Testing
@testable import Offshore

@MainActor
struct CategoryGoalSavingsCalculatorTests {
    @Test(arguments: [0.0, 50, 100, 150])
    func allowanceReservesOnlyTheUnspentMaximum(spending: Double) throws {
        let fixture = Fixture()
        let result = try #require(fixture.calculate(
            variable: [fixture.variable(spending)], goals: [fixture.goal(maximum: 100)]
        ))

        #expect(result.currentExpenseImpact == spending)
        #expect(result.remainingCategoryAllowance == max(0, 100 - spending))
        #expect(result.estimatedSavings == 1_000 - max(100, spending))
    }

    @Test func exampleIncludesExistingExpensesAndOnlyRemainingAllowances() throws {
        let fixture = Fixture()
        let rent = fixture.planned(1_000)
        rent.category = nil
        let result = try #require(fixture.calculate(
            incomes: [fixture.income(3_000)], planned: [rent, fixture.planned(200)],
            goals: [fixture.goal(maximum: 700)]
        ))

        #expect(result.plannedIncome == 3_000)
        #expect(result.currentExpenseImpact == 1_200)
        #expect(result.remainingCategoryAllowance == 500)
        #expect(result.estimatedSavings == 1_300)
    }

    @Test func presetMinimumIsNotAnAdditionalExpense() throws {
        let fixture = Fixture()
        let planned = fixture.planned(200)
        planned.sourcePresetID = UUID()
        let result = try #require(fixture.calculate(
            planned: [planned], goals: [fixture.goal(minimum: 200, maximum: 600)]
        ))

        #expect(result.currentExpenseImpact == 200)
        #expect(result.remainingCategoryAllowance == 400)
        #expect(result.estimatedSavings == 400)
    }

    @Test func zeroMaximumShowsAScenarioButMissingAndMinimumOnlyGoalsDoNot() throws {
        let fixture = Fixture()
        #expect(fixture.calculate(goals: []) == nil)
        #expect(fixture.calculate(goals: [fixture.goal(minimum: 100)]) == nil)
        let result = try #require(fixture.calculate(goals: [fixture.goal(maximum: 0)]))
        #expect(result.remainingCategoryAllowance == 0)
        #expect(result.estimatedSavings == 1_000)
    }

    @Test(arguments: [0.0, 250])
    func recordedPlannedAmountReplacesOriginalAmount(actual: Double) throws {
        let fixture = Fixture()
        let planned = fixture.planned(200)
        planned.actualAmount = actual
        let impact = actual > 0 ? actual : 200
        let result = try #require(fixture.calculate(planned: [planned], goals: [fixture.goal(maximum: 100)]))

        #expect(result.currentExpenseImpact == impact)
        #expect(result.remainingCategoryAllowance == 0)
        #expect(result.estimatedSavings == 1_000 - impact)
    }

    @Test func unlimitedAndUncategorizedExpensesStillReduceSavings() throws {
        let fixture = Fixture()
        let unlimited = Category(name: "Other", hexColor: "#000000", workspace: fixture.workspace)
        let variable = fixture.variable(70)
        variable.category = unlimited
        let planned = fixture.planned(100)
        planned.category = nil
        let result = try #require(fixture.calculate(
            planned: [planned], variable: [variable], goals: [fixture.goal(maximum: 300)]
        ))

        #expect(result.currentExpenseImpact == 170)
        #expect(result.remainingCategoryAllowance == 300)
        #expect(result.estimatedSavings == 530)
    }

    @Test func splitsOffsetsRefundsAndLedgerAdjustmentsUseExistingBudgetImpactMath() throws {
        let fixture = Fixture()
        let sharedPlan = fixture.planned(400)
        sharedPlan.actualAmount = 300
        sharedPlan.allocation = ExpenseAllocation(
            allocatedAmount: 100, preservesGrossAmount: true, workspace: fixture.workspace,
            plannedExpense: sharedPlan
        )
        let savingsPlan = fixture.planned(100)
        savingsPlan.savingsLedgerEntry = SavingsLedgerEntry(
            date: fixture.now, amount: -50, note: "Pay from savings",
            kindRaw: SavingsLedgerEntryKind.expenseOffset.rawValue,
            workspace: fixture.workspace, plannedExpense: savingsPlan
        )
        let sharedExpense = fixture.variable(200)
        sharedExpense.allocation = ExpenseAllocation(
            allocatedAmount: 50, preservesGrossAmount: true, workspace: fixture.workspace,
            expense: sharedExpense
        )
        let savingsExpense = fixture.variable(100)
        savingsExpense.savingsLedgerEntry = SavingsLedgerEntry(
            date: fixture.now, amount: -30, note: "Pay from savings",
            kindRaw: SavingsLedgerEntryKind.expenseOffset.rawValue,
            workspace: fixture.workspace, variableExpense: savingsExpense
        )
        let refund = fixture.variable(20)
        refund.kind = .credit
        let adjustment = fixture.variable(500)
        adjustment.kind = .adjustment
        let result = try #require(fixture.calculate(
            planned: [sharedPlan, savingsPlan], variable: [sharedExpense, savingsExpense, refund, adjustment],
            goals: [fixture.goal(maximum: 600)]
        ))

        #expect(result.currentExpenseImpact == 450)
        #expect(result.remainingCategoryAllowance == 150)
        #expect(result.estimatedSavings == 400)
    }

    @Test func refundsCanReopenAnAllowanceWithoutIncreasingTheSavingsScenario() throws {
        let fixture = Fixture()
        let refund = fixture.variable(20)
        refund.kind = .credit
        let result = try #require(fixture.calculate(variable: [refund], goals: [fixture.goal(maximum: 100)]))

        #expect(result.currentExpenseImpact == -20)
        #expect(result.remainingCategoryAllowance == 120)
        #expect(result.estimatedSavings == 900)
    }

    @Test func overspendingAndNegativeSavingsAreNotClamped() throws {
        let fixture = Fixture()
        let result = try #require(fixture.calculate(
            variable: [fixture.variable(1_200)], goals: [fixture.goal(maximum: 100)]
        ))

        #expect(result.remainingCategoryAllowance == 0)
        #expect(result.estimatedSavings == -200)
    }

    @Test func expensesRequireMatchingWorkspaceCardBudgetAndInclusiveDates() throws {
        let fixture = Fixture()
        let otherWorkspace = Workspace(name: "Work", hexColor: "#000000")
        let foreignCard = Card(name: "Work", workspace: otherWorkspace)
        let unlinkedCard = Card(name: "Unlinked", workspace: fixture.workspace)
        let foreignVariable = fixture.variable(1_000)
        foreignVariable.workspace = otherWorkspace
        let foreignCardVariable = fixture.variable(1_000)
        foreignCardVariable.card = foreignCard
        let unlinkedVariable = fixture.variable(1_000)
        unlinkedVariable.card = unlinkedCard
        let noCardVariable = fixture.variable(1_000)
        noCardVariable.card = nil
        let outsideVariable = fixture.variable(1_000)
        outsideVariable.transactionDate = Self.date(1, month: 11)
        let foreignPlan = fixture.planned(1_000)
        foreignPlan.workspace = otherWorkspace
        let foreignCardPlan = fixture.planned(1_000)
        foreignCardPlan.card = foreignCard
        let unlinkedPlan = fixture.planned(1_000)
        unlinkedPlan.card = unlinkedCard
        let otherBudgetPlan = fixture.planned(1_000)
        otherBudgetPlan.sourceBudgetID = UUID()
        let noBudgetPlan = fixture.planned(1_000)
        noBudgetPlan.sourceBudgetID = nil
        let outsidePlan = fixture.planned(1_000)
        outsidePlan.expenseDate = Self.date(30, month: 9)
        let firstDay = fixture.planned(10)
        firstDay.expenseDate = Self.date(1)
        let lastDay = fixture.variable(20)
        lastDay.transactionDate = Self.date(31, hour: 23, minute: 59, second: 59)

        let result = try #require(CategoryGoalSavingsCalculator.calculate(
            for: fixture.budget, workspaceID: fixture.workspace.id,
            linkedCardIDs: [fixture.card.id, foreignCard.id], incomes: [fixture.income(1_000)],
            plannedExpenses: [firstDay, foreignPlan, foreignCardPlan, unlinkedPlan, otherBudgetPlan, noBudgetPlan, outsidePlan],
            variableExpenses: [lastDay, foreignVariable, foreignCardVariable, unlinkedVariable, noCardVariable, outsideVariable],
            categoryLimits: [fixture.goal(maximum: 100)], now: fixture.now, calendar: Self.calendar
        ))

        #expect(result.currentExpenseImpact == 30)
        #expect(result.remainingCategoryAllowance == 70)
        #expect(result.estimatedSavings == 900)
    }

    @Test func onlyPlannedIncomeInTheWorkspaceAndBudgetDatesIsIncluded() throws {
        let fixture = Fixture()
        let received = fixture.income(2_000)
        received.isPlanned = false
        let foreign = fixture.income(3_000)
        foreign.workspace = Workspace(name: "Work", hexColor: "#000000")
        let outside = fixture.income(4_000)
        outside.date = Self.date(1, month: 11)
        let firstDay = fixture.income(100)
        firstDay.date = Self.date(1)
        let lastDay = fixture.income(200)
        lastDay.date = Self.date(31, hour: 23, minute: 59, second: 59)
        let result = try #require(fixture.calculate(
            incomes: [received, foreign, outside, firstDay, lastDay], goals: [fixture.goal(maximum: 100)]
        ))

        #expect(result.plannedIncome == 300)
        #expect(result.estimatedSavings == 200)
    }

    @Test func goalsMustBelongToTheBudgetAndWorkspace() {
        let fixture = Fixture()
        let foreign = Fixture()
        let wrongBudget = fixture.goal(maximum: 100)
        wrongBudget.budget = foreign.budget
        let wrongCategory = fixture.goal(maximum: 100)
        wrongCategory.category = foreign.category
        #expect(fixture.calculate(goals: [wrongBudget, wrongCategory]) == nil)
        #expect(CategoryGoalSavingsCalculator.calculate(
            for: fixture.budget, workspaceID: foreign.workspace.id, linkedCardIDs: [fixture.card.id],
            incomes: [], plannedExpenses: [], variableExpenses: [], categoryLimits: [fixture.goal(maximum: 100)]
        ) == nil)
    }

    @Test(arguments: [-1.0, Double.infinity, Double.nan])
    func invalidStoredMaximumsDoNotProduceAnEstimate(maximum: Double) {
        let fixture = Fixture()
        #expect(fixture.calculate(goals: [fixture.goal(maximum: maximum)]) == nil)
    }

    @Test func separateFutureCalculationSettingsApplyWithoutChangingGoalMaximums() throws {
        let fixture = Fixture()
        let plannedToday = fixture.planned(10)
        let variableToday = fixture.variable(20)
        let plannedFuture = fixture.planned(30)
        plannedFuture.expenseDate = Self.date(16)
        let variableFuture = fixture.variable(40)
        variableFuture.transactionDate = Self.date(16)
        for expense in [plannedToday, plannedFuture] { expense.category = nil }
        for expense in [variableToday, variableFuture] { expense.category = nil }
        let goal = fixture.goal(maximum: 100)

        for excludePlanned in [false, true] {
            for excludeVariable in [false, true] {
                let result = try #require(fixture.calculate(
                    planned: [plannedToday, plannedFuture], variable: [variableToday, variableFuture], goals: [goal],
                    excludeFuturePlanned: excludePlanned, excludeFutureVariable: excludeVariable
                ))
                let expectedImpact = 30.0 + (excludePlanned ? 0 : 30) + (excludeVariable ? 0 : 40)
                #expect(result.currentExpenseImpact == expectedImpact)
                #expect(result.remainingCategoryAllowance == 100)
                #expect(result.estimatedSavings == 900 - expectedImpact)
            }
        }
    }

    @Test func savedGoalChangesAndRemovingTheLastMaximumRecalculateTheScenario() throws {
        let fixture = Fixture()
        let goal = fixture.goal(maximum: 100)
        #expect(try #require(fixture.calculate(goals: [goal])).estimatedSavings == 900)
        goal.maxAmount = 300
        #expect(try #require(fixture.calculate(goals: [goal])).estimatedSavings == 700)
        goal.minAmount = 100
        goal.maxAmount = nil
        #expect(fixture.calculate(goals: [goal]) == nil)
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func date(_ day: Int, month: Int = 10, hour: Int = 0, minute: Int = 0, second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    @MainActor
    private struct Fixture {
        let workspace: Workspace
        let budget: Budget
        let card: Card
        let category: Offshore.Category
        let now = CategoryGoalSavingsCalculatorTests.date(15, hour: 12)

        init() {
            let workspace = Workspace(name: "Personal", hexColor: "#000000")
            self.workspace = workspace
            budget = Budget(name: "October", startDate: CategoryGoalSavingsCalculatorTests.date(1),
                            endDate: CategoryGoalSavingsCalculatorTests.date(31), workspace: workspace)
            card = Card(name: "Debit", workspace: workspace)
            category = Category(name: "Groceries", hexColor: "#000000", workspace: workspace)
        }

        func income(_ amount: Double) -> Income {
            Income(source: "Expected", amount: amount, date: now, isPlanned: true, workspace: workspace)
        }

        func planned(_ amount: Double) -> PlannedExpense {
            PlannedExpense(title: "Plan", plannedAmount: amount, expenseDate: now, workspace: workspace,
                           card: card, category: category, sourceBudgetID: budget.id)
        }

        func variable(_ amount: Double) -> VariableExpense {
            VariableExpense(descriptionText: "Expense", amount: amount, transactionDate: now,
                            workspace: workspace, card: card, category: category)
        }

        func goal(minimum: Double? = nil, maximum: Double? = nil) -> BudgetCategoryLimit {
            BudgetCategoryLimit(minAmount: minimum, maxAmount: maximum, budget: budget, category: category)
        }

        func calculate(
            incomes: [Income]? = nil, planned: [PlannedExpense] = [], variable: [VariableExpense] = [],
            goals: [BudgetCategoryLimit], excludeFuturePlanned: Bool = false, excludeFutureVariable: Bool = false
        ) -> CategoryGoalSavingsCalculator.Summary? {
            CategoryGoalSavingsCalculator.calculate(
                for: budget, workspaceID: workspace.id, linkedCardIDs: [card.id],
                incomes: incomes ?? [income(1_000)], plannedExpenses: planned, variableExpenses: variable,
                categoryLimits: goals, excludeFuturePlannedExpenses: excludeFuturePlanned,
                excludeFutureVariableExpenses: excludeFutureVariable, now: now,
                calendar: CategoryGoalSavingsCalculatorTests.calendar
            )
        }
    }
}
