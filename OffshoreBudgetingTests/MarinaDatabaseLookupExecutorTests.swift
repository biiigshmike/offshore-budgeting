import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct MarinaDatabaseLookupExecutorTests {
    @Test func exactMatch_returnsSingleBestTransactionResult() throws {
        let fixture = try makeLookupFixture()
        let response = MarinaDatabaseLookupExecutor().execute(
            MarinaDatabaseLookupRequest(
                rawPrompt: "When did I purchase Litter Robot?",
                searchText: "Litter Robot",
                objectTypes: [.variableExpense, .plannedExpense],
                dateRange: nil,
                limit: 5,
                requestedDetail: .date
            ),
            provider: fixture.provider
        )

        #expect(response.results.count == 1)
        #expect(response.results.first?.title == "Litter Robot")
        #expect(response.results.first?.objectType == .variableExpense)
        #expect(response.results.first?.cardName == "Apple Card")
        #expect(response.results.first?.categoryName == "Pets")
    }

    @Test func containsMatch_returnsMatchingResult() throws {
        let fixture = try makeLookupFixture()
        let response = MarinaDatabaseLookupExecutor().execute(
            request(searchText: "Warranty", objectTypes: [.variableExpense]),
            provider: fixture.provider
        )

        #expect(response.results.map(\.title) == ["Litter Robot Warranty"])
    }

    @Test func multipleResults_returnsSmallListWithoutAmbiguityFailure() throws {
        let fixture = try makeLookupFixture()
        let response = MarinaDatabaseLookupExecutor().execute(
            request(searchText: "Litter Robot", objectTypes: [.variableExpense], limit: 5),
            provider: fixture.provider
        )

        #expect(response.results.count == 2)
        #expect(response.results.map(\.title).contains("Litter Robot"))
        #expect(response.results.map(\.title).contains("Litter Robot Warranty"))
    }

    @Test func objectTypeClue_filtersResults() throws {
        let fixture = try makeLookupFixture()
        let response = MarinaDatabaseLookupExecutor().execute(
            request(searchText: "Apple Card", objectTypes: [.card]),
            provider: fixture.provider
        )

        #expect(response.results.count == 1)
        #expect(response.results.first?.objectType == .card)
        #expect(response.results.first?.title == "Apple Card")
    }

    @Test func noMatch_isEmptySuccessfulLookupResponse() throws {
        let fixture = try makeLookupFixture()
        let response = MarinaDatabaseLookupExecutor().execute(
            request(searchText: "Not Here", objectTypes: [.variableExpense, .plannedExpense]),
            provider: fixture.provider
        )

        #expect(response.results.isEmpty)
        let answer = MarinaDatabaseLookupResponseBuilder().responseCompatibleAnswer(from: response)
        #expect(answer.title == "No Matching Offshore Data")
        #expect(answer.subtitle?.contains("clearer budgeting prompt") == false)
    }

    @Test func workspaceScoping_ignoresOtherWorkspaceMatches() throws {
        let fixture = try makeLookupFixture()
        let otherWorkspace = Workspace(name: "Other", hexColor: "#111111")
        let otherExpense = VariableExpense(
            descriptionText: "Litter Robot Other",
            amount: 1,
            transactionDate: date(2026, 1, 15),
            workspace: otherWorkspace
        )
        fixture.context.insert(otherWorkspace)
        fixture.context.insert(otherExpense)
        try fixture.context.save()

        let response = MarinaDatabaseLookupExecutor().execute(
            request(searchText: "Other", objectTypes: [.variableExpense]),
            provider: fixture.provider
        )

        #expect(response.results.isEmpty)
    }

    @Test func responseBuilder_formatsDateDetailForSingleTransaction() throws {
        let fixture = try makeLookupFixture()
        let response = MarinaDatabaseLookupExecutor().execute(
            MarinaDatabaseLookupRequest(
                rawPrompt: "When did I purchase Litter Robot?",
                searchText: "Litter Robot",
                objectTypes: [.variableExpense, .plannedExpense],
                dateRange: nil,
                limit: 5,
                requestedDetail: .date
            ),
            provider: fixture.provider
        )
        let answer = MarinaDatabaseLookupResponseBuilder().responseCompatibleAnswer(from: response)

        #expect(answer.title.contains("Litter Robot"))
        #expect(answer.primaryValue?.contains("Jan") == true)
        #expect(answer.rows.contains { $0.title == "Card" && $0.value == "Apple Card" })
    }

    @Test func ambiguousLookup_acrossObjectTypesAsksForClarification() throws {
        let fixture = try makeLookupFixture()
        let response = MarinaDatabaseLookupExecutor().execute(
            request(searchText: "Rent", objectTypes: [.unknown]),
            provider: fixture.provider
        )
        let answer = MarinaDatabaseLookupResponseBuilder().responseCompatibleAnswer(from: response)

        #expect(response.needsClarification)
        #expect(response.ambiguityChoices.map(\.objectType).contains(.preset))
        #expect(response.ambiguityChoices.map(\.objectType).contains(.plannedExpense))
        #expect(answer.title.contains("Rent"))
        #expect(answer.subtitle?.contains("more than one kind") == true)
    }

    private func request(
        searchText: String,
        objectTypes: [MarinaLookupObjectType],
        limit: Int = 5
    ) -> MarinaDatabaseLookupRequest {
        MarinaDatabaseLookupRequest(
            rawPrompt: "Find \(searchText)",
            searchText: searchText,
            objectTypes: objectTypes,
            dateRange: nil,
            limit: limit,
            requestedDetail: .general
        )
    }

    private struct Fixture {
        let context: ModelContext
        let provider: MarinaDataProvider
    }

    private func makeLookupFixture() throws -> Fixture {
        let schema = Schema([
            Workspace.self,
            Budget.self,
            Card.self,
            BudgetCardLink.self,
            Offshore.Category.self,
            Preset.self,
            BudgetPresetLink.self,
            BudgetCategoryLimit.self,
            PlannedExpense.self,
            VariableExpense.self,
            AllocationAccount.self,
            ExpenseAllocation.self,
            AllocationSettlement.self,
            IncomeSeries.self,
            ImportMerchantRule.self,
            Income.self,
            SavingsAccount.self,
            SavingsLedgerEntry.self
        ])
        let config = ModelConfiguration(UUID().uuidString, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)
        let workspace = Workspace(name: "Lookup Workspace", hexColor: "#3B82F6")
        let appleCard = Card(name: "Apple Card", workspace: workspace)
        let pets = Offshore.Category(name: "Pets", hexColor: "#8844AA", workspace: workspace)
        let marchBudget = Budget(
            name: "March 2026",
            startDate: date(2026, 3, 1),
            endDate: date(2026, 3, 31),
            workspace: workspace
        )
        let rentPreset = Preset(
            title: "Rent",
            plannedAmount: 2000,
            workspace: workspace,
            defaultCard: appleCard
        )
        let paycheck = Income(
            source: "Paycheck",
            amount: 3000,
            date: date(2026, 1, 5),
            isPlanned: false,
            workspace: workspace
        )
        let litterRobot = VariableExpense(
            descriptionText: "Litter Robot",
            amount: 699,
            transactionDate: date(2026, 1, 14),
            workspace: workspace,
            card: appleCard,
            category: pets
        )
        let warranty = VariableExpense(
            descriptionText: "Litter Robot Warranty",
            amount: 99,
            transactionDate: date(2026, 1, 14),
            workspace: workspace,
            card: appleCard,
            category: pets
        )
        let rent = PlannedExpense(
            title: "Rent",
            plannedAmount: 2000,
            expenseDate: date(2026, 3, 1),
            workspace: workspace,
            card: appleCard
        )
        let savings = SavingsAccount(name: "True Savings", total: 500, workspace: workspace)
        let reconciliation = AllocationAccount(name: "Roommate Reconciliation", workspace: workspace)

        context.insert(workspace)
        context.insert(appleCard)
        context.insert(pets)
        context.insert(marchBudget)
        context.insert(rentPreset)
        context.insert(paycheck)
        context.insert(litterRobot)
        context.insert(warranty)
        context.insert(rent)
        context.insert(savings)
        context.insert(reconciliation)
        try context.save()

        return Fixture(
            context: context,
            provider: MarinaDataProvider(modelContext: context, workspaceID: workspace.id)
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }
}
