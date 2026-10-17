import Foundation
import Testing
@testable import Offshore

struct MarinaEntityAdapterTests {
    private let catalog = MarinaEntityCatalog()
    private let registry = MarinaEntityAdapterRegistry()

    @Test func registryHasPhaseThreeAdapters() {
        for entity in phaseThreeEntities {
            #expect(registry.adapter(for: entity) != nil, "Missing adapter for \(entity.rawValue)")
        }
    }

    @Test func adapterRowsExposeOnlyCatalogDescribedFieldsAndRelationships() throws {
        let fixture = makeFixture()

        for entity in phaseThreeEntities {
            let adapter = try #require(registry.adapter(for: entity))
            let descriptor = try #require(catalog.descriptor(for: entity))
            let describedFields = Set(descriptor.fields.map(\.key))
            let describedRelationships = Set(descriptor.relationships.map(\.key))
            let rows = adapter.rows(from: fixture.snapshot)

            #expect(adapter.entity == entity)
            #expect(rows.isEmpty == false, "Expected fixture rows for \(entity.rawValue)")

            for row in rows {
                #expect(row.entity == entity)
                #expect(row.displayName.isEmpty == false)
                #expect(describedFields.isSuperset(of: row.fields.keys))
                #expect(describedRelationships.isSuperset(of: row.relationships.keys))
            }
        }
    }

    @Test func variableExpenseRowsExposeMerchantTextAndAmounts() throws {
        let fixture = makeFixture()
        let row = try row(for: .variableExpense, in: fixture.snapshot)

        #expect(row.fields[.descriptionText] == .text("Apple Store"))
        #expect(row.fields[.merchantText] == .text("Apple Store"))
        #expect(row.fields[.amount] == .money(42))
        #expect(row.fields[.budgetImpact] == .money(42))
        #expect(row.fields[.transactionDate] == .date(fixture.variableDate))
        #expect(row.relationships[.card]?.targetID == fixture.card.id)
        #expect(row.relationships[.category]?.targetID == fixture.category.id)
    }

    @Test func plannedExpenseRowsExposeSearchTextDateAmountsAndSourceLinks() throws {
        let fixture = makeFixture()
        let row = try row(for: .plannedExpense, in: fixture.snapshot)

        #expect(row.fields[.title] == .text("Internet Bill"))
        #expect(row.fields[.merchantText] == .text("Internet Bill"))
        #expect(row.fields[.plannedAmount] == .money(80))
        #expect(row.fields[.actualAmount] == .money(75))
        #expect(row.fields[.effectiveAmount] == .money(75))
        #expect(row.fields[.budgetImpact] == .money(75))
        #expect(row.fields[.expenseDate] == .date(fixture.plannedDate))
        #expect(row.relationships[.preset]?.targetID == fixture.preset.id)
        #expect(row.relationships[.budget]?.targetID == fixture.budget.id)
    }

    @Test func incomeRowsExposeSourceDateAmountAndPlannedState() throws {
        let fixture = makeFixture()
        let row = try row(for: .income, in: fixture.snapshot)

        #expect(row.fields[.source] == .text("Paycheck"))
        #expect(row.fields[.amount] == .money(2_000))
        #expect(row.fields[.incomeAmount] == .money(2_000))
        #expect(row.fields[.date] == .date(fixture.incomeDate))
        #expect(row.fields[.isPlanned] == .boolean(true))
        #expect(row.relationships[.incomeSource]?.displayName == "Paycheck")
        #expect(row.relationships[.card]?.targetID == fixture.card.id)
    }

    @Test func metadataRowsExposeOnlyCatalogBackedStoredFields() throws {
        let fixture = makeFixture()
        let categoryRow = try row(for: .category, in: fixture.snapshot)
        let cardRow = try row(for: .card, in: fixture.snapshot)
        let budgetRow = try row(for: .budget, in: fixture.snapshot)
        let presetRow = try row(for: .preset, in: fixture.snapshot)

        #expect(categoryRow.fields[.name] == .text("Bills"))
        #expect(categoryRow.fields[.color] == .colorHex("#00AA00"))

        #expect(cardRow.fields[.name] == .text("Apple Card"))
        #expect(cardRow.fields[.color] == nil)
        #expect(cardRow.fields[.budgetImpact] == nil)

        #expect(budgetRow.fields[.name] == .text("June"))
        #expect(budgetRow.fields[.startDate] == .date(fixture.budgetStart))
        #expect(budgetRow.fields[.endDate] == .date(fixture.budgetEnd))
        #expect(budgetRow.fields[.budgetImpact] == nil)

        #expect(presetRow.fields[.title] == .text("Internet"))
        #expect(presetRow.fields[.plannedAmount] == .money(80))
        #expect(presetRow.fields[.actualAmount] == nil)
    }

    @Test func incomePlannedStateIsCatalogDescribedAndFilterable() throws {
        let descriptor = try #require(catalog.descriptor(for: .income))
        let plannedField = try #require(descriptor.fields.first { $0.key == .isPlanned })

        #expect(plannedField.valueType == .boolean)
        #expect(plannedField.isFilterable)
        #expect(plannedField.isGroupable)
        #expect(plannedField.isSortable)
    }

    private var phaseThreeEntities: [MarinaSemanticEntity] {
        [
            .variableExpense,
            .plannedExpense,
            .income,
            .category,
            .card,
            .budget,
            .preset
        ]
    }

    private func row(
        for entity: MarinaSemanticEntity,
        in snapshot: MarinaWorkspaceSnapshot
    ) throws -> MarinaQueryableRow {
        let adapter = try #require(registry.adapter(for: entity))
        return try #require(adapter.rows(from: snapshot).first)
    }

    private func makeFixture() -> AdapterFixture {
        let budgetStart = Date(timeIntervalSince1970: 1_780_300_800)
        let budgetEnd = Date(timeIntervalSince1970: 1_782_892_800)
        let variableDate = Date(timeIntervalSince1970: 1_780_387_200)
        let plannedDate = Date(timeIntervalSince1970: 1_780_473_600)
        let incomeDate = Date(timeIntervalSince1970: 1_780_560_000)

        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let card = Card(name: "Apple Card", theme: "ruby", effect: "plastic", workspace: workspace)
        let category = Offshore.Category(name: "Bills", hexColor: "#00AA00", workspace: workspace)
        let budget = Budget(name: "June", startDate: budgetStart, endDate: budgetEnd, workspace: workspace)
        let preset = Preset(
            title: "Internet",
            plannedAmount: 80,
            workspace: workspace,
            defaultCard: card,
            defaultCategory: category
        )
        let variableExpense = VariableExpense(
            descriptionText: "Apple Store",
            amount: 42,
            transactionDate: variableDate,
            workspace: workspace,
            card: card,
            category: category
        )
        let plannedExpense = PlannedExpense(
            title: "Internet Bill",
            plannedAmount: 80,
            actualAmount: 75,
            expenseDate: plannedDate,
            workspace: workspace,
            card: card,
            category: category,
            sourcePresetID: preset.id,
            sourceBudgetID: budget.id
        )
        let income = Income(
            source: "Paycheck",
            amount: 2_000,
            date: incomeDate,
            isPlanned: true,
            workspace: workspace,
            card: card
        )

        let snapshot = MarinaWorkspaceSnapshot(
            workspace: workspace,
            budgets: [budget],
            cards: [card],
            categories: [category],
            presets: [preset],
            plannedExpenses: [plannedExpense],
            variableExpenses: [variableExpense],
            homePlannedExpenses: [plannedExpense],
            homeCalculationPlannedExpenses: [plannedExpense],
            homeCalculationVariableExpenses: [variableExpense],
            reconciliationAccounts: [],
            expenseAllocations: [],
            allocationSettlements: [],
            savingsAccounts: [],
            savingsEntries: [],
            incomes: [income]
        )

        return AdapterFixture(
            snapshot: snapshot,
            card: card,
            category: category,
            budget: budget,
            preset: preset,
            variableDate: variableDate,
            plannedDate: plannedDate,
            incomeDate: incomeDate,
            budgetStart: budgetStart,
            budgetEnd: budgetEnd
        )
    }
}

private struct AdapterFixture {
    let snapshot: MarinaWorkspaceSnapshot
    let card: Card
    let category: Offshore.Category
    let budget: Budget
    let preset: Preset
    let variableDate: Date
    let plannedDate: Date
    let incomeDate: Date
    let budgetStart: Date
    let budgetEnd: Date
}
