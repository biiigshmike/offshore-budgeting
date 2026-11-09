import Foundation
import Testing
@testable import Offshore

@MainActor
struct CategoryLimitWidgetSnapshotBuilderTests {
    @Test func changesBudgetAtMidnightAndDropsUnavailableLimits() throws {
        let fixture = Fixture()
        let first = fixture.budget(day: 1, maximum: 100)
        let second = fixture.budget(day: 2, maximum: 200)
        let third = fixture.budget(day: 3, maximum: 0)
        fixture.workspace.budgets = [first, second, third]
        fixture.workspace.variableExpenses = [
            fixture.expense(125, day: 1),
            fixture.expense(40, day: 2)
        ]

        let snapshots = fixture.snapshots()
        let current = try #require(snapshots.first)
        #expect(current.validUntil == fixture.date(day: 2))
        #expect(current.metrics.first?.id == fixture.category.id)
        #expect(current.metrics.first?.fractionUsed == 1.25)
        #expect(current.metrics.first?.limitAmount == 100)
        #expect(current.metrics.first?.spentAmount == 125)
        #expect(current.metrics.first?.remainingAmount == -25)
        #expect(snapshots.dropFirst().first?.metrics.first?.fractionUsed == 0.2)
        #expect(snapshots.dropFirst().first?.metrics.first?.limitAmount == 200)
        #expect(snapshots.dropFirst().first?.metrics.first?.spentAmount == 40)
        #expect(snapshots.dropFirst().first?.metrics.first?.remainingAmount == 160)
        #expect(snapshots.dropFirst(2).first?.metrics.isEmpty == true)
        #expect(snapshots.dropFirst(3).first?.metrics.isEmpty == true)
    }

    @Test func usesBudgetImpactAndAppliesFutureCalculationSettingsPerDay() throws {
        let fixture = Fixture()
        let budget = fixture.budget(day: 1, endDay: 2, maximum: 100)
        fixture.workspace.budgets = [budget]
        let planned = PlannedExpense(
            title: "Dinner",
            plannedAmount: 80,
            actualAmount: 100,
            expenseDate: fixture.date(day: 1),
            workspace: fixture.workspace,
            category: fixture.category
        )
        planned.allocation = ExpenseAllocation(
            allocatedAmount: 30,
            preservesGrossAmount: true,
            workspace: fixture.workspace,
            plannedExpense: planned
        )
        let futurePlanned = PlannedExpense(
            title: "Tomorrow’s dinner",
            plannedAmount: 20,
            expenseDate: fixture.date(day: 2),
            workspace: fixture.workspace,
            category: fixture.category
        )
        fixture.workspace.plannedExpenses = [planned, futurePlanned]
        let debit = fixture.expense(45, day: 1)
        debit.savingsLedgerEntry = SavingsLedgerEntry(
            date: fixture.date(day: 1),
            amount: -10,
            note: "From savings",
            kindRaw: SavingsLedgerEntryKind.expenseOffset.rawValue,
            workspace: fixture.workspace,
            variableExpense: debit
        )
        let refund = fixture.expense(5, day: 1)
        refund.kind = .credit
        let adjustment = fixture.expense(500, day: 1)
        adjustment.kind = .adjustment
        fixture.workspace.variableExpenses = [debit, refund, adjustment, fixture.expense(30, day: 2)]

        let snapshots = fixture.snapshots(excludeFutureVariable: true)
        #expect(snapshots.first?.metrics.first?.fractionUsed == 1)
        #expect(snapshots.first?.metrics.first?.limitAmount == 100)
        #expect(snapshots.first?.metrics.first?.spentAmount == 100)
        #expect(snapshots.first?.metrics.first?.remainingAmount == 0)
        #expect(snapshots.dropFirst().first?.metrics.first?.fractionUsed == 1.5)
        #expect(snapshots.dropFirst().first?.metrics.first?.spentAmount == 150)
        #expect(snapshots.dropFirst().first?.metrics.first?.remainingAmount == -50)
        let includingFutureVariable = fixture.snapshots().first?.metrics.first
        #expect(includingFutureVariable?.fractionUsed == 1.3)
        #expect(includingFutureVariable?.spentAmount == 130)
        #expect(includingFutureVariable?.remainingAmount == -30)
    }

    @Test func legacyFractionOnlySnapshotDecodesWithoutInventingMoneyValues() throws {
        let id = UUID()
        let legacy = Data("""
        {"days":[{"date":0,"validUntil":86400,"metrics":[{"id":"\(id.uuidString)","name":"Dining","fractionUsed":0.75}]}]}
        """.utf8)
        let snapshot = try JSONDecoder().decode(CategoryLimitWidgetSnapshotSet.self, from: legacy)
        let metric = try #require(snapshot.days.first?.metrics.first)
        #expect(metric.id == id)
        #expect(metric.fractionUsed == 0.75)
        #expect(metric.limitAmount == nil)
        #expect(metric.spentAmount == nil)
        #expect(metric.remainingAmount == nil)
    }

    @Test func snapshotMoneyValuesRoundTripWithoutLosingPrecision() throws {
        let metric = CategoryLimitWidgetMetric(
            id: UUID(), name: "Dining", fractionUsed: 1.25,
            limitAmount: 100.08, spentAmount: 125.10
        )
        let snapshot = CategoryLimitWidgetSnapshotSet(days: [
            CategoryLimitWidgetSnapshot(
                date: Date(timeIntervalSinceReferenceDate: 0),
                validUntil: Date(timeIntervalSinceReferenceDate: 86400),
                metrics: [metric]
            )
        ])
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(CategoryLimitWidgetSnapshotSet.self, from: data)
        #expect(decoded.days == snapshot.days)
        #expect(decoded.days.first?.metrics.first?.remainingAmount == 100.08 - 125.10)
    }

    @Test func equalFractionsWithDifferentMoneyValuesTriggerMetricChange() {
        let id = UUID()
        let before = CategoryLimitWidgetMetric(
            id: id, name: "Dining", fractionUsed: 0.5,
            limitAmount: 100, spentAmount: 50
        )
        let after = CategoryLimitWidgetMetric(
            id: id, name: "Dining", fractionUsed: 0.5,
            limitAmount: 200, spentAmount: 100
        )
        #expect(before.fractionUsed == after.fractionUsed)
        #expect(before != after)
        #expect(before.remainingAmount == 50)
        #expect(after.remainingAmount == 100)
    }

    @Test func remainingAmountRejectsUnavailableOrInvalidMoneyAndPreservesCredits() {
        let invalidValues: [(Double?, Double?)] = [
            (nil, 10), (100, nil), (0, 10), (-1, 10),
            (Double.infinity, 10), (100, Double.nan),
            (Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude)
        ]
        for (limit, spent) in invalidValues {
            let metric = CategoryLimitWidgetMetric(
                id: UUID(), name: "Dining", fractionUsed: 0.5,
                limitAmount: limit, spentAmount: spent
            )
            #expect(metric.remainingAmount == nil)
        }
        let credited = CategoryLimitWidgetMetric(
            id: UUID(), name: "Dining", fractionUsed: -0.2,
            limitAmount: 100, spentAmount: -20
        )
        #expect(credited.remainingAmount == 120)
    }

    @MainActor
    @Test func pickerUsesOnlyCurrentPositiveLimitsAndKeepsPinnedIdentity() {
        let fixture = Fixture()
        let otherCategory = Category(name: "Transit", hexColor: "#000000", workspace: fixture.workspace)
        fixture.workspace.categories = [fixture.category, otherCategory]
        let earlier = fixture.budget(day: 1, endDay: 5, maximum: 100)
        let later = fixture.budget(day: 3, endDay: 6, maximum: 0)
        later.categoryLimits = [
            BudgetCategoryLimit(maxAmount: 0, budget: later, category: fixture.category),
            BudgetCategoryLimit(minAmount: 15, budget: later, category: otherCategory)
        ]
        fixture.workspace.budgets = [earlier, later]

        let options = CategoryLimitWidgetSnapshotBuilder.makePickerOptions(
            workspace: fixture.workspace,
            calendar: fixture.calendar
        )

        #expect(options.eligibleCategoryIDs(asOf: fixture.date(day: 1)) == [fixture.category.id])
        #expect(options.eligibleCategoryIDs(asOf: fixture.date(day: 2)) == [fixture.category.id])
        #expect(options.eligibleCategoryIDs(asOf: fixture.date(day: 3)).isEmpty)
        #expect(options.eligibleCategoryIDs(asOf: fixture.date(day: 7)).isEmpty)
        #expect(options.categoryNames[fixture.category.id] == "Dining")
    }

    @MainActor
    private struct Fixture {
        let workspace: Workspace
        let category: Offshore.Category
        let calendar: Calendar

        init() {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .gmt
            self.calendar = calendar

            let workspace = Workspace(name: "Personal", hexColor: "#000000")
            self.workspace = workspace
            let category = Category(name: "Dining", hexColor: "#000000", workspace: workspace)
            self.category = category
            workspace.categories = [category]
        }

        func date(day: Int) -> Date {
            DateComponents(calendar: calendar, year: 2026, month: 1, day: day).date!
        }

        func budget(day: Int, endDay: Int? = nil, maximum: Double) -> Budget {
            let budget = Budget(
                name: "Budget",
                startDate: date(day: day),
                endDate: date(day: endDay ?? day),
                workspace: workspace
            )
            budget.categoryLimits = [BudgetCategoryLimit(maxAmount: maximum, budget: budget, category: category)]
            return budget
        }

        func expense(_ amount: Double, day: Int) -> VariableExpense {
            VariableExpense(
                descriptionText: "Dining",
                amount: amount,
                transactionDate: date(day: day),
                workspace: workspace,
                category: category
            )
        }

        func snapshots(excludeFutureVariable: Bool = false) -> [CategoryLimitWidgetSnapshot] {
            CategoryLimitWidgetSnapshotBuilder.makeSnapshots(
                workspace: workspace,
                now: date(day: 1),
                excludeFuturePlanned: true,
                excludeFutureVariable: excludeFutureVariable,
                calendar: calendar
            )
        }
    }
}
