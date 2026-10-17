import Foundation
import Testing
@testable import Offshore

struct MarinaUnifiedExpenseAdapterTests {
    private let catalog = MarinaEntityCatalog()
    private let adapter = MarinaUnifiedExpenseAdapter()
    private let rowEngine = MarinaRowOperationEngine()

    @Test func unifiedExpenseRowsIncludeVariableAndPlannedRows() {
        let fixture = makeFixture()
        let rows = adapter.rows(from: fixture.snapshot)

        #expect(rowNames(rows) == ["Apple Store", "Coffee Stand", "AppleCare Plan", "Rent"])
    }

    @Test func unifiedExpenseRowsPreserveOriginalRowEntity() throws {
        let fixture = makeFixture()
        let rows = adapter.rows(from: fixture.snapshot)

        #expect(try #require(row(named: "Apple Store", in: rows)).entity == .variableExpense)
        #expect(try #require(row(named: "Coffee Stand", in: rows)).entity == .variableExpense)
        #expect(try #require(row(named: "AppleCare Plan", in: rows)).entity == .plannedExpense)
        #expect(try #require(row(named: "Rent", in: rows)).entity == .plannedExpense)
    }

    @Test func unifiedRowsExposeCatalogDescribedSharedSearchableFields() throws {
        let fixture = makeFixture()
        let descriptor = try #require(catalog.descriptor(for: .unifiedExpenses))
        let fields = Dictionary(uniqueKeysWithValues: descriptor.fields.map { ($0.key, $0) })
        let rows = adapter.rows(from: fixture.snapshot)

        #expect(fields[.merchantText]?.isSearchable == true)
        #expect(fields[.merchantText]?.isFilterable == true)
        #expect(fields[.budgetImpact]?.isAggregatable == true)
        #expect(fields[.date]?.isFilterable == true)
        #expect(fields[.date]?.isSortable == true)

        for row in rows {
            #expect(row.fields[.merchantText] != nil)
            #expect(row.fields[.budgetImpact] != nil)
            #expect(row.fields[.date] != nil)
        }
    }

    @Test func unifiedRowsExposeBudgetImpactAndSharedDate() throws {
        let fixture = makeFixture()
        let rows = adapter.rows(from: fixture.snapshot)

        let variableRow = try #require(row(named: "Apple Store", in: rows))
        let plannedRow = try #require(row(named: "AppleCare Plan", in: rows))

        #expect(variableRow.fields[.budgetImpact] == .money(42))
        #expect(variableRow.fields[.date] == .date(fixture.variableDate))
        #expect(variableRow.fields[.transactionDate] == .date(fixture.variableDate))

        #expect(plannedRow.fields[.budgetImpact] == .money(75))
        #expect(plannedRow.fields[.date] == .date(fixture.plannedDate))
        #expect(plannedRow.fields[.expenseDate] == .date(fixture.plannedDate))
    }

    @Test func unifiedRowsExposeAvailableRelationships() throws {
        let fixture = makeFixture()
        let rows = adapter.rows(from: fixture.snapshot)

        let variableRow = try #require(row(named: "Apple Store", in: rows))
        let plannedRow = try #require(row(named: "AppleCare Plan", in: rows))

        #expect(variableRow.relationships[.card]?.targetID == fixture.card.id)
        #expect(variableRow.relationships[.category]?.targetID == fixture.category.id)
        #expect(plannedRow.relationships[.card]?.targetID == fixture.card.id)
        #expect(plannedRow.relationships[.category]?.targetID == fixture.category.id)
        #expect(plannedRow.relationships[.preset]?.targetID == fixture.preset.id)
        #expect(plannedRow.relationships[.budget]?.targetID == fixture.budget.id)
    }

    @Test func missingCategoryGroupsAsUncategorized() {
        let fixture = makeFixture()
        let groups = rowEngine.group(adapter.rows(from: fixture.snapshot), by: .relationship(.category))

        #expect(groupNames(groups) == ["Bills", "Uncategorized"])
    }

    @Test func missingCardPresetAndBudgetGroupAsUnassigned() {
        let fixture = makeFixture()
        let rows = adapter.rows(from: fixture.snapshot)

        #expect(groupNames(rowEngine.group(rows, by: .relationship(.card))) == ["Apple Card", "Unassigned"])
        #expect(groupNames(rowEngine.group(rows, by: .relationship(.preset))) == ["AppleCare", "Unassigned"])
        #expect(groupNames(rowEngine.group(rows, by: .relationship(.budget))) == ["June", "Unassigned"])
    }

    private func makeFixture() -> UnifiedAdapterFixture {
        let variableDate = date(2026, 6, 5)
        let plannedDate = date(2026, 6, 16)

        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let card = Card(name: "Apple Card", theme: "ruby", effect: "plastic", workspace: workspace)
        let category = Offshore.Category(name: "Bills", hexColor: "#22C55E", workspace: workspace)
        let budget = Budget(name: "June", startDate: date(2026, 6, 1), endDate: date(2026, 6, 30), workspace: workspace)
        let preset = Preset(title: "AppleCare", plannedAmount: 80, workspace: workspace, defaultCard: card, defaultCategory: category)
        let variableExpense = VariableExpense(
            descriptionText: "Apple Store",
            amount: 42,
            transactionDate: variableDate,
            workspace: workspace,
            card: card,
            category: category
        )
        let uncategorizedVariableExpense = VariableExpense(
            descriptionText: "Coffee Stand",
            amount: 9,
            transactionDate: date(2026, 6, 7),
            workspace: workspace,
            card: nil,
            category: nil
        )
        let plannedExpense = PlannedExpense(
            title: "AppleCare Plan",
            plannedAmount: 80,
            actualAmount: 75,
            expenseDate: plannedDate,
            workspace: workspace,
            card: card,
            category: category,
            sourcePresetID: preset.id,
            sourceBudgetID: budget.id
        )
        let unassignedPlannedExpense = PlannedExpense(
            title: "Rent",
            plannedAmount: 1_200,
            expenseDate: date(2026, 6, 20),
            workspace: workspace,
            card: nil,
            category: nil
        )

        let snapshot = MarinaWorkspaceSnapshot(
            workspace: workspace,
            budgets: [budget],
            cards: [card],
            categories: [category],
            presets: [preset],
            plannedExpenses: [plannedExpense, unassignedPlannedExpense],
            variableExpenses: [variableExpense, uncategorizedVariableExpense],
            homePlannedExpenses: [plannedExpense, unassignedPlannedExpense],
            homeCalculationPlannedExpenses: [plannedExpense, unassignedPlannedExpense],
            homeCalculationVariableExpenses: [variableExpense, uncategorizedVariableExpense],
            reconciliationAccounts: [],
            expenseAllocations: [],
            allocationSettlements: [],
            savingsAccounts: [],
            savingsEntries: [],
            incomes: []
        )

        return UnifiedAdapterFixture(
            snapshot: snapshot,
            card: card,
            category: category,
            budget: budget,
            preset: preset,
            variableDate: variableDate,
            plannedDate: plannedDate
        )
    }

    private func row(named name: String, in rows: [MarinaQueryableRow]) -> MarinaQueryableRow? {
        rows.first { $0.displayName == name }
    }

    private func rowNames(_ rows: [MarinaQueryableRow]) -> [String] {
        rows.map(\.displayName)
    }

    private func groupNames(_ groups: [MarinaGroupedRows]) -> [String] {
        groups.map(\.displayName)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = TimeZone(secondsFromGMT: 0)

        return calendar.date(from: components) ?? .distantPast
    }
}

private struct UnifiedAdapterFixture {
    let snapshot: MarinaWorkspaceSnapshot
    let card: Card
    let category: Offshore.Category
    let budget: Budget
    let preset: Preset
    let variableDate: Date
    let plannedDate: Date
}
