import Foundation
import Testing
@testable import Offshore

struct MarinaSavingsAdapterTests {
    private let catalog = MarinaEntityCatalog()
    private let registry = MarinaEntityAdapterRegistry()

    @Test func savingsAccountAdapterExistsInRegistry() {
        #expect(registry.adapter(for: .savingsAccount) != nil)
    }

    @Test func savingsAccountRowsPreserveEntityAndExposeDescribedFields() throws {
        let fixture = makeFixture()
        let adapter = try #require(registry.adapter(for: .savingsAccount))
        let descriptor = try #require(catalog.descriptor(for: .savingsAccount))
        let row = try #require(adapter.rows(from: fixture.snapshot).first)

        #expect(row.entity == .savingsAccount)
        #expect(row.displayName == "Emergency Fund")
        #expect(row.fields[.name] == .text("Emergency Fund"))
        #expect(row.fields[.date] == .date(fixture.accountCreatedAt))
        #expect(row.fields[.createdAt] == .date(fixture.accountCreatedAt))
        #expect(row.fields[.updatedAt] == .date(fixture.accountUpdatedAt))
        #expect(row.fields[.savingsTotal] == nil)
        #expect(row.relationships[.workspace]?.targetID == fixture.workspace.id)
        #expect(Set(descriptor.fields.map(\.key)).isSuperset(of: row.fields.keys))
        #expect(Set(descriptor.relationships.map(\.key)).isSuperset(of: row.relationships.keys))
    }

    @Test func savingsLedgerSurfaceRowsExposeDateAmountAndRelationships() throws {
        let fixture = makeFixture()
        let descriptor = try #require(catalog.descriptor(for: .savingsLedgerEntries))
        let row = try #require(registry.rows(for: .savingsLedgerEntries, from: fixture.snapshot)?.first)

        #expect(row.entity == .savingsAccount)
        #expect(row.displayName == "Emergency deposit")
        #expect(row.fields[.amount] == .money(125))
        #expect(row.fields[.date] == .date(fixture.ledgerDate))
        #expect(row.fields[.note] == .text("Emergency deposit"))
        #expect(row.fields[.kind] == .text(SavingsLedgerEntryKind.manualAdjustment.rawValue))
        #expect(row.relationships[.savingsAccount]?.targetID == fixture.account.id)
        #expect(row.relationships[.variableExpense]?.targetID == fixture.variableExpense.id)
        #expect(Set(descriptor.fields.map(\.key)).isSuperset(of: row.fields.keys))
        #expect(Set(descriptor.relationships.map(\.key)).isSuperset(of: row.relationships.keys))
    }

    private func makeFixture() -> SavingsAdapterFixture {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let accountCreatedAt = date(2026, 1, 1)
        let accountUpdatedAt = date(2026, 6, 1)
        let account = SavingsAccount(
            name: "Emergency Fund",
            total: 500,
            createdAt: accountCreatedAt,
            updatedAt: accountUpdatedAt,
            workspace: workspace
        )
        let variableExpense = VariableExpense(
            descriptionText: "Savings Offset",
            amount: 25,
            transactionDate: date(2026, 6, 4),
            workspace: workspace
        )
        let ledgerDate = date(2026, 6, 5)
        let entry = SavingsLedgerEntry(
            date: ledgerDate,
            amount: 125,
            note: "Emergency deposit",
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
            periodStartDate: date(2026, 6, 1),
            periodEndDate: date(2026, 6, 30),
            createdAt: date(2026, 6, 5),
            updatedAt: date(2026, 6, 6),
            workspace: workspace,
            account: account,
            variableExpense: variableExpense
        )

        let snapshot = MarinaWorkspaceSnapshot(
            workspace: workspace,
            budgets: [],
            cards: [],
            categories: [],
            presets: [],
            plannedExpenses: [],
            variableExpenses: [variableExpense],
            homePlannedExpenses: [],
            homeCalculationPlannedExpenses: [],
            homeCalculationVariableExpenses: [variableExpense],
            reconciliationAccounts: [],
            expenseAllocations: [],
            allocationSettlements: [],
            savingsAccounts: [account],
            savingsEntries: [entry],
            incomes: []
        )

        return SavingsAdapterFixture(
            snapshot: snapshot,
            workspace: workspace,
            account: account,
            variableExpense: variableExpense,
            ledgerDate: ledgerDate,
            accountCreatedAt: accountCreatedAt,
            accountUpdatedAt: accountUpdatedAt
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0), year: year, month: month, day: day).date!
    }
}

private struct SavingsAdapterFixture {
    let snapshot: MarinaWorkspaceSnapshot
    let workspace: Workspace
    let account: SavingsAccount
    let variableExpense: VariableExpense
    let ledgerDate: Date
    let accountCreatedAt: Date
    let accountUpdatedAt: Date
}
