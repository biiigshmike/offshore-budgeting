import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaUniversalPresentationTests {
    @Test func unifiedCategoryGroupMatchesManualFixtureMath() throws {
        let fixture = try makeCategoryAndIncomeFixture()
        let request = semanticRequest(
            entity: .variableExpense,
            operation: .group,
            measure: .budgetImpact,
            dimensions: [.category],
            dateRangeToken: .currentMonth,
            expenseScope: .unified
        )

        let presented = fixture.presentedResult(request: request)
        let rows = presented.rows.sorted { $0.title < $1.title }

        #expect(presented.kind == .list)
        #expect(rows.map(\.title) == ["Electronics", "Groceries", "Uncategorized"])
        #expect(rows.map(\.amount) == [575, 38, 1_200])
    }

    @Test func incomeBySourceMatchesManualFixtureMath() throws {
        let fixture = try makeCategoryAndIncomeFixture()
        let request = semanticRequest(
            entity: .income,
            operation: .group,
            measure: .incomeAmount,
            dimensions: [.incomeSource],
            dateRangeToken: .currentPeriod,
            incomeState: .all
        )

        let presented = fixture.presentedResult(
            request: request,
            ambientDateRange: fixture.currentPeriod
        )
        let rows = presented.rows.sorted { $0.title < $1.title }

        #expect(presented.kind == .list)
        #expect(presented.title == "Income by Source")
        #expect(rows.map(\.title) == ["Freelance", "Paycheck"])
        #expect(rows.map(\.amount) == [650, 2_000])
    }

    @Test func unifiedCardGroupIncludesUnassignedRowsAndMatchesManualFixtureMath() throws {
        let fixture = try makeCardFixture()
        let request = semanticRequest(
            entity: .variableExpense,
            operation: .group,
            measure: .budgetImpact,
            dimensions: [.card],
            dateRangeToken: .currentMonth,
            expenseScope: .unified
        )

        let presented = fixture.presentedResult(request: request)
        let rows = presented.rows.sorted { $0.title < $1.title }

        #expect(presented.kind == .list)
        #expect(presented.title == "Spending by Card")
        #expect(rows.map(\.title) == ["Apple Card", "Chase Card", "Unassigned"])
        #expect(rows.map(\.amount) == [200, 30, 107])
    }

    private func makeCategoryAndIncomeFixture() throws -> UniversalPresentationFixture {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let appleCard = Card(name: "Apple Card", theme: "ruby", effect: "plastic", workspace: workspace)
        let chaseCard = Card(name: "Chase Card", theme: "sky", effect: "matte", workspace: workspace)
        let groceries = Offshore.Category(name: "Groceries", hexColor: "#22C55E", workspace: workspace)
        let electronics = Offshore.Category(name: "Electronics", hexColor: "#0EA5E9", workspace: workspace)
        let budget = Budget(
            name: "June",
            startDate: try date(2026, 6, 1),
            endDate: try date(2026, 6, 30),
            workspace: workspace
        )

        let appleStore = VariableExpense(
            descriptionText: "Apple Store",
            amount: 120,
            transactionDate: try date(2026, 6, 5),
            workspace: workspace,
            card: appleCard,
            category: electronics
        )
        let appleMarket = VariableExpense(
            descriptionText: "Apple Market",
            amount: 18,
            transactionDate: try date(2026, 6, 20),
            workspace: workspace,
            card: appleCard,
            category: groceries
        )
        let kroger = VariableExpense(
            descriptionText: "Kroger",
            amount: 30,
            transactionDate: try date(2026, 6, 10),
            workspace: workspace,
            card: chaseCard,
            category: groceries
        )
        let bestBuy = VariableExpense(
            descriptionText: "Best Buy",
            amount: 300,
            transactionDate: try date(2026, 6, 12),
            workspace: workspace,
            card: chaseCard,
            category: electronics
        )

        let phoneBill = PlannedExpense(
            title: "Phone Bill",
            plannedAmount: 80,
            expenseDate: try date(2026, 6, 16),
            workspace: workspace,
            card: appleCard,
            category: electronics,
            sourceBudgetID: budget.id
        )
        let internetBill = PlannedExpense(
            title: "Internet Bill",
            plannedAmount: 100,
            actualAmount: 75,
            expenseDate: try date(2026, 6, 18),
            workspace: workspace,
            card: appleCard,
            category: electronics,
            sourceBudgetID: budget.id
        )
        let rent = PlannedExpense(
            title: "Rent",
            plannedAmount: 1_200,
            expenseDate: try date(2026, 6, 25),
            workspace: workspace,
            card: chaseCard,
            sourceBudgetID: budget.id
        )

        let reconciliationAccount = AllocationAccount(name: "Alejandro", workspace: workspace)
        let groceryAllocation = ExpenseAllocation(
            allocatedAmount: 10,
            preservesGrossAmount: true,
            workspace: workspace,
            account: reconciliationAccount,
            expense: kroger
        )
        kroger.allocation = groceryAllocation
        reconciliationAccount.expenseAllocations = [groceryAllocation]

        let actualPaycheck = Income(
            source: "Paycheck",
            amount: 2_000,
            date: try date(2026, 6, 11),
            isPlanned: false,
            workspace: workspace,
            card: appleCard
        )
        let freelance = Income(
            source: "Freelance",
            amount: 650,
            date: try date(2026, 6, 19),
            isPlanned: false,
            workspace: workspace,
            card: chaseCard
        )
        let plannedPaycheck = Income(
            source: "Paycheck",
            amount: 2_100,
            date: try date(2026, 6, 25),
            isPlanned: true,
            workspace: workspace,
            card: appleCard
        )

        let plannedExpenses = [phoneBill, internetBill, rent]
        let variableExpenses = [appleStore, appleMarket, kroger, bestBuy]
        return UniversalPresentationFixture(
            snapshot: MarinaWorkspaceSnapshot(
                workspace: workspace,
                budgets: [budget],
                cards: [appleCard, chaseCard],
                categories: [groceries, electronics],
                presets: [],
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                homePlannedExpenses: plannedExpenses,
                homeCalculationPlannedExpenses: plannedExpenses,
                homeCalculationVariableExpenses: variableExpenses,
                reconciliationAccounts: [reconciliationAccount],
                expenseAllocations: [groceryAllocation],
                allocationSettlements: [],
                savingsAccounts: [],
                savingsEntries: [],
                incomes: [actualPaycheck, freelance, plannedPaycheck]
            ),
            currentPeriod: HomeQueryDateRange(
                startDate: try date(2026, 6, 10),
                endDate: try date(2026, 6, 20)
            ),
            now: try date(2026, 6, 15),
            calendar: calendar
        )
    }

    private func makeCardFixture() throws -> UniversalPresentationFixture {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let appleCard = Card(name: "Apple Card", theme: "ruby", effect: "plastic", workspace: workspace)
        let chaseCard = Card(name: "Chase Card", theme: "sky", effect: "matte", workspace: workspace)
        let budget = Budget(
            name: "June",
            startDate: try date(2026, 6, 1),
            endDate: try date(2026, 6, 30),
            workspace: workspace
        )
        let plannedExpenses = [
            PlannedExpense(
                title: "Phone Bill",
                plannedAmount: 80,
                expenseDate: try date(2026, 6, 16),
                workspace: workspace,
                card: appleCard,
                sourceBudgetID: budget.id
            ),
            PlannedExpense(
                title: "Cash Plan",
                plannedAmount: 100,
                expenseDate: try date(2026, 6, 20),
                workspace: workspace,
                sourceBudgetID: budget.id
            )
        ]
        let variableExpenses = [
            VariableExpense(
                descriptionText: "Apple Store",
                amount: 120,
                transactionDate: try date(2026, 6, 5),
                workspace: workspace,
                card: appleCard
            ),
            VariableExpense(
                descriptionText: "Kroger",
                amount: 30,
                transactionDate: try date(2026, 6, 10),
                workspace: workspace,
                card: chaseCard
            ),
            VariableExpense(
                descriptionText: "Cash Coffee",
                amount: 7,
                transactionDate: try date(2026, 6, 11),
                workspace: workspace
            )
        ]

        return UniversalPresentationFixture(
            snapshot: MarinaWorkspaceSnapshot(
                workspace: workspace,
                budgets: [budget],
                cards: [appleCard, chaseCard],
                categories: [],
                presets: [],
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                homePlannedExpenses: plannedExpenses,
                homeCalculationPlannedExpenses: plannedExpenses,
                homeCalculationVariableExpenses: variableExpenses,
                reconciliationAccounts: [],
                expenseAllocations: [],
                allocationSettlements: [],
                savingsAccounts: [],
                savingsEntries: [],
                incomes: []
            ),
            currentPeriod: HomeQueryDateRange(
                startDate: try date(2026, 6, 1),
                endDate: try date(2026, 6, 30)
            ),
            now: try date(2026, 6, 15),
            calendar: calendar
        )
    }

    private func semanticRequest(
        entity: MarinaSemanticEntity,
        operation: MarinaSemanticOperation,
        measure: MarinaSemanticMeasure,
        dimensions: [MarinaSemanticDimension],
        dateRangeToken: MarinaSemanticDateRangeToken,
        expenseScope: MarinaSemanticExpenseScope? = nil,
        incomeState: MarinaSemanticIncomeState? = nil
    ) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: entity,
            operation: operation,
            measure: measure,
            dimensions: dimensions,
            dateRangeToken: dateRangeToken,
            expenseScope: expenseScope,
            incomeState: incomeState,
            expectedAnswerShape: .list
        )
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try #require(
            calendar.date(from: DateComponents(year: year, month: month, day: day))
        )
    }
}

@MainActor
private struct UniversalPresentationFixture {
    let snapshot: MarinaWorkspaceSnapshot
    let currentPeriod: HomeQueryDateRange
    let now: Date
    let calendar: Calendar

    func presentedResult(
        request: MarinaSemanticRequest,
        ambientDateRange: HomeQueryDateRange? = nil
    ) -> MarinaExecutionResult {
        let planningContext = MarinaUniversalPlanningContext(
            ambientDateRange: ambientDateRange,
            defaultBudgetingPeriod: .monthly,
            now: now,
            calendar: calendar
        )
        let formulaRegistry = MarinaFormulaRegistry(now: now, calendar: calendar)
        let bridge = MarinaSemanticUniversalPlanBridge(formulaRegistry: formulaRegistry)
        let runner = MarinaUniversalQueryRunner(formulaRegistry: formulaRegistry)
        let presenter = MarinaUniversalResultPresenter()

        switch bridge.makePlan(from: request, planningContext: planningContext) {
        case let .plan(plan):
            let result = runner.runFormulaAware(plan: plan, snapshot: snapshot)
            return presenter.presentationResult(
                for: result,
                plan: plan,
                context: MarinaUniversalPresentationContext(
                    dateRange: plan.dateRange,
                    comparisonDateRange: plan.comparisonDateRange,
                    semanticRequest: request,
                    now: now,
                    calendar: calendar
                )
            )
        case let .unsupported(reason):
            return presenter.capabilityUnsupportedResult(reason)
        }
    }
}
