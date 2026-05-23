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
            request(searchText: "Apple Card", objectTypes: [.card], lookupMode: .entityDetail),
            provider: fixture.provider
        )

        #expect(response.results.count == 1)
        #expect(response.results.first?.objectType == .card)
        #expect(response.results.first?.title == "Apple Card")
    }

    @Test func entityDetailMode_doesNotRouteCardNameToLinkedPlannedExpense() throws {
        let fixture = try makeLookupFixture()
        let response = MarinaDatabaseLookupExecutor().execute(
            request(
                searchText: "Apple Card",
                objectTypes: [.card, .plannedExpense],
                lookupMode: .entityDetail
            ),
            provider: fixture.provider
        )

        #expect(response.results.map(\.objectType) == [.card])
        #expect(response.results.first?.title == "Apple Card")
        #expect(response.traceSummary.contains("lookupMode=entityDetail"))
        #expect(response.traceSummary.contains("selectedResultTypes=card"))
    }

    @Test func entityDetailMode_handlesDebitCardCollisionWithPlannedExpense() throws {
        let fixture = try makeLookupFixture()
        let debit = Card(name: "Debit Card", workspace: fixture.workspace)
        let billCategory = Category(name: "Bills & Utilities", hexColor: "#345678", workspace: fixture.workspace)
        let bill = PlannedExpense(
            title: "T-Mobile",
            plannedAmount: 96.20,
            expenseDate: date(2026, 5, 19),
            workspace: fixture.workspace,
            card: debit,
            category: billCategory
        )
        fixture.context.insert(debit)
        fixture.context.insert(billCategory)
        fixture.context.insert(bill)
        try fixture.context.save()

        let response = MarinaDatabaseLookupExecutor().execute(
            request(
                searchText: "Debit Card",
                objectTypes: [.card, .plannedExpense],
                lookupMode: .entityDetail
            ),
            provider: fixture.provider
        )

        #expect(response.results.map(\.objectType) == [.card])
        #expect(response.results.first?.title == "Debit Card")
    }

    @Test func entityDetailMode_doesNotRouteCategoryNameToCategorizedExpense() throws {
        let fixture = try makeLookupFixture()
        let groceries = Category(name: "Groceries", hexColor: "#00AA00", workspace: fixture.workspace)
        let card = Card(name: "Grocery Card", workspace: fixture.workspace)
        let expense = VariableExpense(
            descriptionText: "Market",
            amount: 42,
            transactionDate: date(2026, 5, 12),
            workspace: fixture.workspace,
            card: card,
            category: groceries
        )
        fixture.context.insert(groceries)
        fixture.context.insert(card)
        fixture.context.insert(expense)
        try fixture.context.save()

        let response = MarinaDatabaseLookupExecutor().execute(
            request(
                searchText: "Groceries",
                objectTypes: [.category, .variableExpense],
                lookupMode: .entityDetail
            ),
            provider: fixture.provider
        )

        #expect(response.results.map(\.objectType) == [.category])
        #expect(response.results.first?.title == "Groceries")
    }

    @Test func entityDetailMode_keepsPresetAndAccountsConstrainedToTheirEntityType() throws {
        let fixture = try makeLookupFixture()

        let preset = MarinaDatabaseLookupExecutor().execute(
            request(searchText: "Rent", objectTypes: [.preset], lookupMode: .entityDetail),
            provider: fixture.provider
        )
        let savings = MarinaDatabaseLookupExecutor().execute(
            request(searchText: "True Savings", objectTypes: [.savingsAccount], lookupMode: .entityDetail),
            provider: fixture.provider
        )
        let reconciliation = MarinaDatabaseLookupExecutor().execute(
            request(searchText: "Roommate Reconciliation", objectTypes: [.reconciliationAccount], lookupMode: .entityDetail),
            provider: fixture.provider
        )

        #expect(preset.results.first?.objectType == .preset)
        #expect(savings.results.first?.objectType == .savingsAccount)
        #expect(reconciliation.results.first?.objectType == .reconciliationAccount)
    }

    @Test func relatedRowsMode_stillAllowsRelationshipFieldMatches() throws {
        let fixture = try makeLookupFixture()
        let response = MarinaDatabaseLookupExecutor().execute(
            request(
                searchText: "Apple Card",
                objectTypes: [.variableExpense, .plannedExpense],
                lookupMode: .relatedRows,
                limit: 10
            ),
            provider: fixture.provider
        )

        #expect(response.results.map(\.objectType).contains(.plannedExpense))
        #expect(response.results.map(\.objectType).contains(.variableExpense))
        #expect(response.results.allSatisfy { $0.cardName == "Apple Card" })
    }

    @Test func broadSearchClarifiesExactEntityAndRelatedRowCollision() throws {
        let fixture = try makeLookupFixture()
        let response = MarinaDatabaseLookupExecutor().execute(
            request(
                searchText: "Apple Card",
                objectTypes: MarinaLookupObjectType.safeDefaultSearchTypes,
                lookupMode: .broadSearch
            ),
            provider: fixture.provider
        )

        #expect(response.needsClarification)
        #expect(response.ambiguityChoices.map(\.objectType).contains(.card))
        #expect(response.ambiguityChoices.map(\.objectType).contains(.plannedExpense))
    }

    @Test func lookupRequestCodable_defaultsMissingModeToBroadSearch() throws {
        let json = """
        {
          "rawPrompt": "Find Apple Card",
          "searchText": "Apple Card",
          "objectTypes": ["card"],
          "limit": 1,
          "requestedDetail": "general"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(MarinaDatabaseLookupRequest.self, from: json)
        #expect(decoded.lookupMode == .broadSearch)

        let encoded = try JSONEncoder().encode(decoded)
        let encodedText = String(data: encoded, encoding: .utf8) ?? ""
        #expect(encodedText.contains("\"lookupMode\""))
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

    @Test func responseBuilder_workspaceLookupUsesDirectConfidentCopy() throws {
        let fixture = try makeLookupFixture()
        let response = MarinaDatabaseLookupExecutor().execute(
            MarinaDatabaseLookupRequest(
                rawPrompt: "What workspace am I in?",
                searchText: "",
                objectTypes: [.workspace],
                dateRange: nil,
                limit: 5,
                requestedDetail: .general
            ),
            provider: fixture.provider
        )

        let answer = MarinaDatabaseLookupResponseBuilder().responseCompatibleAnswer(from: response)

        #expect(answer.title == "You are in Lookup Workspace.")
        #expect(answer.subtitle?.localizedCaseInsensitiveContains("waiting on") != true)
        #expect(answer.rows.contains { $0.title == "Type" && $0.value == "Workspace" })
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

    @Test func responseBuilder_singleResultRowsPreserveSourceMetadata() throws {
        let resultID = UUID()
        let resultDate = date(2026, 5, 12)
        let response = MarinaDatabaseLookupResponse(
            request: request(searchText: "Coffee", objectTypes: [.variableExpense]),
            results: [
                MarinaDatabaseLookupResult(
                    id: resultID,
                    objectType: .variableExpense,
                    title: "Coffee",
                    subtitle: "Apple Card",
                    date: resultDate,
                    amount: 6.5,
                    cardName: "Apple Card",
                    categoryName: nil,
                    accountName: nil,
                    workspaceName: nil,
                    detailRows: [
                        .init(label: "Type", value: "Variable expense"),
                        .init(label: "Amount", value: "$6.50")
                    ]
                )
            ]
        )

        let answer = MarinaDatabaseLookupResponseBuilder().responseCompatibleAnswer(from: response)

        #expect(answer.rows.allSatisfy { $0.sourceID == resultID })
        #expect(answer.rows.allSatisfy { $0.objectType == .variableExpense })
        #expect(answer.rows.allSatisfy { $0.amount == 6.5 })
        #expect(answer.rows.allSatisfy { $0.date == resultDate })
    }

    @Test func responseBuilder_listAndAmbiguityRowsPreserveSourceMetadata() throws {
        let categoryID = UUID()
        let expenseID = UUID()
        let categoryResult = MarinaDatabaseLookupResult(
            id: categoryID,
            objectType: .category,
            title: "Groceries",
            subtitle: "Category",
            date: nil,
            amount: nil,
            cardName: nil,
            categoryName: nil,
            accountName: nil,
            workspaceName: nil,
            detailRows: []
        )
        let expenseResult = MarinaDatabaseLookupResult(
            id: expenseID,
            objectType: .variableExpense,
            title: "Groceries",
            subtitle: "Apple Card",
            date: date(2026, 5, 12),
            amount: 42,
            cardName: "Apple Card",
            categoryName: "Groceries",
            accountName: nil,
            workspaceName: nil,
            detailRows: []
        )

        let listAnswer = MarinaDatabaseLookupResponseBuilder().responseCompatibleAnswer(
            from: MarinaDatabaseLookupResponse(
                request: request(searchText: "Groceries", objectTypes: [.category, .variableExpense]),
                results: [categoryResult, expenseResult]
            )
        )
        let clarificationAnswer = MarinaDatabaseLookupResponseBuilder().responseCompatibleAnswer(
            from: MarinaDatabaseLookupResponse(
                request: request(searchText: "Groceries", objectTypes: [.category, .variableExpense]),
                results: [],
                ambiguityChoices: [categoryResult, expenseResult]
            )
        )

        #expect(listAnswer.rows.map(\.sourceID) == [categoryID, expenseID])
        #expect(listAnswer.rows.map(\.objectType) == [.category, .variableExpense])
        #expect(clarificationAnswer.rows.map(\.sourceID) == [categoryID, expenseID])
        #expect(clarificationAnswer.rows.map(\.objectType) == [.category, .variableExpense])
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

    @Test func ambiguousLookup_defaultBroadSearchClarifiesExactCategoryAndExpenseCollision() throws {
        let fixture = try makeLookupFixture()
        let groceries = Category(name: "Groceries", hexColor: "#00AA00", workspace: fixture.workspace)
        let card = Card(name: "Grocery Card", workspace: fixture.workspace)
        fixture.context.insert(groceries)
        fixture.context.insert(card)
        fixture.context.insert(VariableExpense(
            descriptionText: "Groceries",
            amount: 42,
            transactionDate: date(2026, 5, 12),
            workspace: fixture.workspace,
            card: card,
            category: groceries
        ))
        try fixture.context.save()

        let response = MarinaDatabaseLookupExecutor().execute(
            request(searchText: "Groceries", objectTypes: MarinaLookupObjectType.safeDefaultSearchTypes),
            provider: fixture.provider
        )
        let answer = MarinaDatabaseLookupResponseBuilder().responseCompatibleAnswer(from: response)

        #expect(response.needsClarification)
        #expect(response.ambiguityChoices.map(\.objectType).contains(.category))
        #expect(response.ambiguityChoices.map(\.objectType).contains(.variableExpense))
        #expect(answer.rows.contains { $0.title == "Groceries" && $0.value.contains("Category") })
        #expect(answer.rows.contains { $0.title == "Groceries" && $0.value.contains("$42.00") && $0.value.contains("Grocery Card") })
    }

    @Test func supportObjectLookup_returnsRulesAliasesSeriesAndAllocations() throws {
        let fixture = try makeLookupFixture()

        let cases: [(String, [MarinaLookupObjectType], MarinaLookupObjectType)] = [
            ("Paycheck Series", [.incomeSeries], .incomeSeries),
            ("litter", [.importMerchantRule], .importMerchantRule),
            ("pets", [.assistantAliasRule], .assistantAliasRule),
            ("Litter Robot", [.expenseAllocation], .expenseAllocation)
        ]

        for (searchText, objectTypes, expectedType) in cases {
            let response = MarinaDatabaseLookupExecutor().execute(
                request(searchText: searchText, objectTypes: objectTypes),
                provider: fixture.provider
            )

            #expect(response.results.first?.objectType == expectedType)
        }
    }

    private func request(
        searchText: String,
        objectTypes: [MarinaLookupObjectType],
        lookupMode: MarinaLookupMode = .broadSearch,
        limit: Int = 5
    ) -> MarinaDatabaseLookupRequest {
        MarinaDatabaseLookupRequest(
            rawPrompt: "Find \(searchText)",
            searchText: searchText,
            objectTypes: objectTypes,
            dateRange: nil,
            limit: limit,
            requestedDetail: .general,
            lookupMode: lookupMode
        )
    }

    private struct Fixture {
        let context: ModelContext
        let workspace: Workspace
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
            AssistantAliasRule.self,
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
        let incomeSeries = IncomeSeries(
            source: "Paycheck Series",
            amount: 3000,
            isPlanned: true,
            frequencyRaw: RecurrenceFrequency.monthly.rawValue,
            interval: 1,
            weeklyWeekday: 6,
            monthlyDayOfMonth: 1,
            monthlyIsLastDay: false,
            yearlyMonth: 1,
            yearlyDayOfMonth: 1,
            startDate: date(2026, 1, 1),
            endDate: date(2026, 12, 31),
            workspace: workspace
        )
        let importRule = ImportMerchantRule(
            merchantKey: "litter",
            preferredName: "Litter Robot",
            preferredCategory: pets,
            workspace: workspace
        )
        let aliasRule = AssistantAliasRule(
            aliasKey: "pets",
            targetValue: "Pets",
            entityType: .category,
            workspace: workspace
        )
        let allocation = ExpenseAllocation(
            allocatedAmount: 100,
            workspace: workspace,
            account: reconciliation,
            expense: litterRobot
        )

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
        context.insert(incomeSeries)
        context.insert(importRule)
        context.insert(aliasRule)
        context.insert(allocation)
        try context.save()

        return Fixture(
            context: context,
            workspace: workspace,
            provider: MarinaDataProvider(modelContext: context, workspaceID: workspace.id)
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }
}
