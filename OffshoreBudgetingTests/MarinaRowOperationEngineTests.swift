import Foundation
import Testing
@testable import Offshore

struct MarinaRowOperationEngineTests {
    private let catalog = MarinaEntityCatalog()
    private let engine = MarinaRowOperationEngine()
    private let registry = MarinaEntityAdapterRegistry()

    @Test func searchesVariableExpenseRowsByMerchantText() throws {
        let fixture = try makeFixture()
        let rows = engine.search(
            fixture.variableRows,
            clause: MarinaRowSearchClause(fields: [.merchantText], query: "Apple"),
            catalog: catalog
        )

        #expect(rowNames(rows) == ["Apple Store", "Apple Market"])
    }

    @Test func searchIsCaseInsensitive() throws {
        let fixture = try makeFixture()
        let rows = engine.search(
            fixture.variableRows,
            clause: MarinaRowSearchClause(fields: [.merchantText], query: "apple"),
            catalog: catalog
        )

        #expect(rowNames(rows) == ["Apple Store", "Apple Market"])
    }

    @Test func emptySearchQueryReturnsOriginalRows() throws {
        let fixture = try makeFixture()
        let rows = engine.search(
            fixture.variableRows,
            clause: MarinaRowSearchClause(fields: [.merchantText], query: "  "),
            catalog: catalog
        )

        #expect(rows == fixture.variableRows)
    }

    @Test func filtersVariableExpensesByCategoryRelationship() throws {
        let fixture = try makeFixture()
        let rows = engine.filter(
            fixture.variableRows,
            filters: [
                MarinaRowFilter(
                    target: .relationship(.category),
                    operation: .equals,
                    value: .text("Groceries")
                )
            ]
        )

        #expect(rowNames(rows) == ["Apple Market", "Kroger", "Trader Joe's"])
    }

    @Test func filtersVariableExpensesByCardRelationshipTargetID() throws {
        let fixture = try makeFixture()
        let rows = engine.filter(
            fixture.variableRows,
            filters: [
                MarinaRowFilter(
                    target: .relationship(.card),
                    operation: .equals,
                    value: .text(fixture.appleCard.id.uuidString)
                )
            ]
        )

        #expect(rowNames(rows) == ["Apple Store", "Apple Market", "Coffee Stand"])
    }

    @Test func filtersRowsByDateGreaterThanOrEqual() throws {
        let fixture = try makeFixture()
        let rows = engine.filter(
            fixture.variableRows,
            filters: [
                MarinaRowFilter(
                    target: .field(.transactionDate),
                    operation: .greaterThanOrEqual,
                    value: .date(fixture.thirdDate)
                )
            ]
        )

        #expect(rowNames(rows) == ["Kroger", "Trader Joe's", "Best Buy", "Coffee Stand"])
    }

    @Test func filtersRowsByMoneyGreaterThan() throws {
        let fixture = try makeFixture()
        let rows = engine.filter(
            fixture.variableRows,
            filters: [
                MarinaRowFilter(
                    target: .field(.budgetImpact),
                    operation: .greaterThan,
                    value: .money(60)
                )
            ]
        )

        #expect(rowNames(rows) == ["Apple Store", "Kroger", "Best Buy"])
    }

    @Test func sortsRowsByAmountDescending() throws {
        let fixture = try makeFixture()
        let rows = engine.sort(
            fixture.variableRows,
            sorts: [
                MarinaRowSort(target: .field(.amount), direction: .descending)
            ]
        )

        #expect(rowNames(rows) == ["Best Buy", "Apple Store", "Kroger", "Trader Joe's", "Apple Market", "Coffee Stand"])
    }

    @Test func sortsRowsByDateDescending() throws {
        let fixture = try makeFixture()
        let rows = engine.sort(
            fixture.variableRows,
            sorts: [
                MarinaRowSort(target: .field(.transactionDate), direction: .descending)
            ]
        )

        #expect(rowNames(rows) == ["Coffee Stand", "Best Buy", "Trader Joe's", "Kroger", "Apple Market", "Apple Store"])
    }

    @Test func sortsRowsByDisplayNameAscending() throws {
        let fixture = try makeFixture()
        let rows = engine.sort(
            fixture.variableRows,
            sorts: [
                MarinaRowSort(target: .field(.descriptionText), direction: .ascending)
            ]
        )

        #expect(rowNames(rows) == ["Apple Market", "Apple Store", "Best Buy", "Coffee Stand", "Kroger", "Trader Joe's"])
    }

    @Test func groupsVariableExpensesByCategoryRelationship() throws {
        let fixture = try makeFixture()
        let groups = engine.group(fixture.variableRows, by: .relationship(.category))

        #expect(groups.map(\.displayName) == ["Electronics", "Groceries", "Uncategorized"])
        #expect(groups.first { $0.displayName == "Groceries" }?.rows.count == 3)
    }

    @Test func groupsVariableExpensesByCardRelationship() throws {
        let fixture = try makeFixture()
        let groups = engine.group(fixture.variableRows, by: .relationship(.card))

        #expect(groups.map(\.displayName) == ["Apple Card", "Chase Card"])
        #expect(groups.first { $0.displayName == "Apple Card" }?.rows.count == 3)
        #expect(groups.first { $0.displayName == "Chase Card" }?.rows.count == 3)
    }

    @Test func groupsIncomeRowsBySourceRelationship() throws {
        let fixture = try makeFixture()
        let groups = engine.group(fixture.incomeRows, by: .relationship(.incomeSource))

        #expect(groups.map(\.displayName) == ["Freelance", "Paycheck"])
        #expect(groups.first { $0.displayName == "Paycheck" }?.rows.count == 2)
    }

    @Test func countReturnsRowCount() throws {
        let fixture = try makeFixture()

        #expect(engine.count(fixture.variableRows) == 6)
    }

    @Test func sumOverBudgetImpactReturnsExpectedTotal() throws {
        let fixture = try makeFixture()

        #expect(engine.sum(fixture.variableRows, field: .budgetImpact) == 563)
    }

    @Test func averageOverBudgetImpactReturnsExpectedAverage() throws {
        let fixture = try makeFixture()

        #expect(engine.average(fixture.variableRows, field: .budgetImpact) == 563.0 / 6.0)
    }

    @Test func averageReturnsNilWhenNoNumericRowsExist() throws {
        let fixture = try makeFixture()

        #expect(engine.average(fixture.variableRows, field: .merchantText) == nil)
    }

    @Test func limitReturnsFirstNRows() throws {
        let fixture = try makeFixture()
        let rows = engine.limit(fixture.variableRows, to: 2)

        #expect(rowNames(rows) == ["Apple Store", "Apple Market"])
    }

    @Test func limitNilReturnsOriginalRows() throws {
        let fixture = try makeFixture()

        #expect(engine.limit(fixture.variableRows, to: nil) == fixture.variableRows)
    }

    @Test func unsupportedFieldValueComparisonsDoNotCrash() throws {
        let fixture = try makeFixture()
        let textComparedToMoney = engine.filter(
            fixture.variableRows,
            filters: [
                MarinaRowFilter(
                    target: .field(.merchantText),
                    operation: .greaterThan,
                    value: .money(10)
                )
            ]
        )
        let relationshipComparedAsRange = engine.filter(
            fixture.variableRows,
            filters: [
                MarinaRowFilter(
                    target: .relationship(.card),
                    operation: .greaterThan,
                    value: .text("Apple Card")
                )
            ]
        )

        #expect(textComparedToMoney.isEmpty)
        #expect(relationshipComparedAsRange.isEmpty)
    }

    @Test func shadowMerchantSpendCanBeModeledWithSearchAndSum() throws {
        let fixture = try makeFixture()
        let rows = engine.search(
            fixture.variableRows,
            clause: MarinaRowSearchClause(fields: [.merchantText], query: "Apple"),
            catalog: catalog
        )

        #expect(engine.sum(rows, field: .budgetImpact) == 138)
    }

    @Test func shadowSpendingByCardCanBeModeledWithGroupSumAndSort() throws {
        let fixture = try makeFixture()
        let groupedTotals = engine.group(fixture.variableRows, by: .relationship(.card))
            .map { group in
                CardTotal(name: group.displayName, total: engine.sum(group.rows, field: .budgetImpact))
            }
            .sorted { $0.total > $1.total }

        #expect(groupedTotals == [
            CardTotal(name: "Chase Card", total: 416),
            CardTotal(name: "Apple Card", total: 147)
        ])
    }

    @Test func shadowBiggestGroceryPurchasesCanBeModeledWithFilterSortAndLimit() throws {
        let fixture = try makeFixture()
        let groceryRows = engine.filter(
            fixture.variableRows,
            filters: [
                MarinaRowFilter(
                    target: .relationship(.category),
                    operation: .equals,
                    value: .text("Groceries")
                )
            ]
        )
        let biggestRows = engine.limit(
            engine.sort(
                groceryRows,
                sorts: [
                    MarinaRowSort(target: .field(.budgetImpact), direction: .descending)
                ]
            ),
            to: 5
        )

        #expect(rowNames(biggestRows) == ["Kroger", "Trader Joe's", "Apple Market"])
    }

    @Test func shadowIncomeBySourceCanBeModeledWithGroupAndSum() throws {
        let fixture = try makeFixture()
        let groupedTotals = Dictionary(
            uniqueKeysWithValues: engine.group(fixture.incomeRows, by: .relationship(.incomeSource)).map { group in
                (group.displayName, engine.sum(group.rows, field: .incomeAmount))
            }
        )

        #expect(groupedTotals["Freelance"] == 650)
        #expect(groupedTotals["Paycheck"] == 4_100)
    }

    private func makeFixture() throws -> RowOperationFixture {
        let firstDate = Date(timeIntervalSince1970: 1_780_300_800)
        let secondDate = Date(timeIntervalSince1970: 1_780_387_200)
        let thirdDate = Date(timeIntervalSince1970: 1_780_473_600)
        let fourthDate = Date(timeIntervalSince1970: 1_780_560_000)
        let fifthDate = Date(timeIntervalSince1970: 1_780_646_400)
        let sixthDate = Date(timeIntervalSince1970: 1_780_732_800)

        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let appleCard = Card(name: "Apple Card", theme: "ruby", effect: "plastic", workspace: workspace)
        let chaseCard = Card(name: "Chase Card", theme: "sky", effect: "matte", workspace: workspace)
        let groceries = Offshore.Category(name: "Groceries", hexColor: "#22C55E", workspace: workspace)
        let electronics = Offshore.Category(name: "Electronics", hexColor: "#0EA5E9", workspace: workspace)

        let variableExpenses = [
            VariableExpense(
                descriptionText: "Apple Store",
                amount: 120,
                transactionDate: firstDate,
                workspace: workspace,
                card: appleCard,
                category: electronics
            ),
            VariableExpense(
                descriptionText: "Apple Market",
                amount: 18,
                transactionDate: secondDate,
                workspace: workspace,
                card: appleCard,
                category: groceries
            ),
            VariableExpense(
                descriptionText: "Kroger",
                amount: 64,
                transactionDate: thirdDate,
                workspace: workspace,
                card: chaseCard,
                category: groceries
            ),
            VariableExpense(
                descriptionText: "Trader Joe's",
                amount: 52,
                transactionDate: fourthDate,
                workspace: workspace,
                card: chaseCard,
                category: groceries
            ),
            VariableExpense(
                descriptionText: "Best Buy",
                amount: 300,
                transactionDate: fifthDate,
                workspace: workspace,
                card: chaseCard,
                category: electronics
            ),
            VariableExpense(
                descriptionText: "Coffee Stand",
                amount: 9,
                transactionDate: sixthDate,
                workspace: workspace,
                card: appleCard,
                category: nil
            )
        ]

        let incomes = [
            Income(
                source: "Paycheck",
                amount: 2_000,
                date: firstDate,
                isPlanned: false,
                workspace: workspace,
                card: appleCard
            ),
            Income(
                source: "Freelance",
                amount: 650,
                date: thirdDate,
                isPlanned: false,
                workspace: workspace,
                card: chaseCard
            ),
            Income(
                source: "Paycheck",
                amount: 2_100,
                date: fifthDate,
                isPlanned: true,
                workspace: workspace,
                card: appleCard
            )
        ]

        let snapshot = MarinaWorkspaceSnapshot(
            workspace: workspace,
            budgets: [],
            cards: [appleCard, chaseCard],
            categories: [groceries, electronics],
            presets: [],
            plannedExpenses: [],
            variableExpenses: variableExpenses,
            homePlannedExpenses: [],
            homeCalculationPlannedExpenses: [],
            homeCalculationVariableExpenses: variableExpenses,
            reconciliationAccounts: [],
            expenseAllocations: [],
            allocationSettlements: [],
            savingsAccounts: [],
            savingsEntries: [],
            incomes: incomes
        )

        return RowOperationFixture(
            variableRows: try rows(for: .variableExpense, in: snapshot),
            incomeRows: try rows(for: .income, in: snapshot),
            appleCard: appleCard,
            thirdDate: thirdDate
        )
    }

    private func rows(
        for entity: MarinaSemanticEntity,
        in snapshot: MarinaWorkspaceSnapshot
    ) throws -> [MarinaQueryableRow] {
        let adapter = try #require(registry.adapter(for: entity))
        return adapter.rows(from: snapshot)
    }

    private func rowNames(_ rows: [MarinaQueryableRow]) -> [String] {
        rows.map(\.displayName)
    }
}

private struct RowOperationFixture {
    let variableRows: [MarinaQueryableRow]
    let incomeRows: [MarinaQueryableRow]
    let appleCard: Card
    let thirdDate: Date
}

private struct CardTotal: Equatable {
    let name: String
    let total: Double
}
