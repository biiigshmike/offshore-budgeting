import Foundation
import Testing
@testable import Offshore

struct MarinaReconciliationAdapterTests {
    private let catalog = MarinaEntityCatalog()
    private let registry = MarinaEntityAdapterRegistry()

    @Test func reconciliationAccountAdapterExistsInRegistry() {
        #expect(registry.adapter(for: .reconciliationAccount) != nil)
    }

    @Test func reconciliationAccountRowsPreserveEntityAndExposeDescribedFields() throws {
        let fixture = makeFixture()
        let adapter = try #require(registry.adapter(for: .reconciliationAccount))
        let descriptor = try #require(catalog.descriptor(for: .reconciliationAccount))
        let row = try #require(adapter.rows(from: fixture.snapshot).first)

        #expect(row.entity == .reconciliationAccount)
        #expect(row.displayName == "Roommate")
        #expect(row.fields[.name] == .text("Roommate"))
        #expect(row.fields[.color] == .colorHex("#14B8A6"))
        #expect(row.fields[.archivedState] == .boolean(false))
        #expect(row.fields[.reconciliationBalance] == nil)
        #expect(row.relationships[.workspace]?.targetID == fixture.workspace.id)
        #expect(Set(descriptor.fields.map(\.key)).isSuperset(of: row.fields.keys))
        #expect(Set(descriptor.relationships.map(\.key)).isSuperset(of: row.relationships.keys))
    }

    @Test func reconciliationLedgerSurfaceRowsExposeAllocationAndSettlementActivity() throws {
        let fixture = makeFixture()
        let descriptor = try #require(catalog.descriptor(for: .reconciliationLedgerEntries))
        let rows = try #require(registry.rows(for: .reconciliationLedgerEntries, from: fixture.snapshot))
        let allocationRow = try #require(rows.first { $0.fields[.kind] == .text("allocation") })
        let settlementRow = try #require(rows.first { $0.fields[.kind] == .text("settlement") })

        #expect(allocationRow.entity == .reconciliationAccount)
        #expect(allocationRow.fields[.amount] == .money(40))
        #expect(allocationRow.fields[.date] == .date(fixture.expenseDate))
        #expect(allocationRow.fields[.note] == .text("Apple Store"))
        #expect(allocationRow.relationships[.reconciliationAccount]?.targetID == fixture.account.id)
        #expect(allocationRow.relationships[.variableExpense]?.targetID == fixture.variableExpense.id)
        #expect(allocationRow.relationships[.card]?.targetID == fixture.card.id)
        #expect(allocationRow.relationships[.category]?.targetID == fixture.category.id)

        #expect(settlementRow.fields[.amount] == .money(-15))
        #expect(settlementRow.fields[.date] == .date(fixture.settlementDate))
        #expect(settlementRow.fields[.note] == .text("Paid back"))
        #expect(settlementRow.relationships[.reconciliationAccount]?.targetID == fixture.account.id)

        for row in rows {
            #expect(Set(descriptor.fields.map(\.key)).isSuperset(of: row.fields.keys))
            #expect(Set(descriptor.relationships.map(\.key)).isSuperset(of: row.relationships.keys))
        }
    }

    private func makeFixture() -> ReconciliationAdapterFixture {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let account = AllocationAccount(name: "Roommate", hexColor: "#14B8A6", workspace: workspace)
        let card = Card(name: "Apple Card", theme: "ruby", effect: "plastic", workspace: workspace)
        let category = Offshore.Category(name: "Electronics", hexColor: "#22C55E", workspace: workspace)
        let expenseDate = date(2026, 6, 5)
        let settlementDate = date(2026, 6, 8)
        let variableExpense = VariableExpense(
            descriptionText: "Apple Store",
            amount: 90,
            transactionDate: expenseDate,
            workspace: workspace,
            card: card,
            category: category
        )
        let allocation = ExpenseAllocation(
            allocatedAmount: 40,
            createdAt: date(2026, 6, 6),
            updatedAt: date(2026, 6, 7),
            workspace: workspace,
            account: account,
            expense: variableExpense
        )
        let settlement = AllocationSettlement(
            date: settlementDate,
            note: "Paid back",
            amount: -15,
            workspace: workspace,
            account: account
        )

        let snapshot = MarinaWorkspaceSnapshot(
            workspace: workspace,
            budgets: [],
            cards: [card],
            categories: [category],
            presets: [],
            plannedExpenses: [],
            variableExpenses: [variableExpense],
            homePlannedExpenses: [],
            homeCalculationPlannedExpenses: [],
            homeCalculationVariableExpenses: [variableExpense],
            reconciliationAccounts: [account],
            expenseAllocations: [allocation],
            allocationSettlements: [settlement],
            savingsAccounts: [],
            savingsEntries: [],
            incomes: []
        )

        return ReconciliationAdapterFixture(
            snapshot: snapshot,
            workspace: workspace,
            account: account,
            card: card,
            category: category,
            variableExpense: variableExpense,
            expenseDate: expenseDate,
            settlementDate: settlementDate
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0), year: year, month: month, day: day).date!
    }
}

private struct ReconciliationAdapterFixture {
    let snapshot: MarinaWorkspaceSnapshot
    let workspace: Workspace
    let account: AllocationAccount
    let card: Card
    let category: Offshore.Category
    let variableExpense: VariableExpense
    let expenseDate: Date
    let settlementDate: Date
}
