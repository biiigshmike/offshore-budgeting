import Foundation
import SwiftData
import Testing
#if canImport(FoundationModels)
import FoundationModels
#endif
@testable import Offshore

@MainActor
struct MarinaPresentationTests {
    private func fixture() throws -> (ModelContext, Workspace, Card, Offshore.Category) {
        let schema = Schema([Workspace.self, Budget.self, Card.self, BudgetCardLink.self, Offshore.Category.self, Preset.self, BudgetPresetLink.self, BudgetCategoryLimit.self, PlannedExpense.self, VariableExpense.self, AllocationAccount.self, ExpenseAllocation.self, AllocationSettlement.self, SavingsAccount.self, SavingsLedgerEntry.self, ImportMerchantRule.self, AssistantAliasRule.self, IncomeSeries.self, Income.self, MarinaChatSession.self])
        let context = ModelContext(try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let workspace = Workspace(name: "Personal", hexColor: "#FFFFFF")
        let card = Card(name: "Apple Card", workspace: workspace)
        let category = Offshore.Category(name: "Hair Care", hexColor: "#FF0000", workspace: workspace)
        context.insert(workspace); context.insert(card); context.insert(category)
        return (context, workspace, card, category)
    }
    private var today: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 12))! }

    @Test func summaryAndEmptyCategoryHaveFocusedScopedPresentation() throws {
        let (context, workspace, card, category) = try fixture()
        context.insert(VariableExpense(descriptionText: "Purchase", amount: 3177.38, transactionDate: today, workspace: workspace, card: card))
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: today)
        var request = MarinaDataRequest(tool: .expenses)
        request.cardID = card.id.uuidString
        let result = try service.execute(request)
        let presentation = try #require(result.presentation)
        #expect(presentation.metrics.count == 1)
        #expect(presentation.metrics.first?.value == 3177.38)
        #expect(presentation.records.isEmpty)
        #expect(presentation.scopeLabel.contains("Apple Card"))
        #expect(presentation.card?.theme == card.theme)
        #expect(result.modelFactsJSON.contains(CurrencyFormatter.string(from: 3177.38)))
        #expect(!result.modelFactsJSON.contains("pagination"))
        request.categoryID = category.id.uuidString
        let empty = try service.execute(request)
        #expect(empty.status == "empty")
        #expect(empty.presentation?.isEmpty == true)
        #expect(empty.presentation?.metrics.first?.value == 0)
    }

    @Test func paginationRefreshesOnePrefixAndPreservesSnapshots() throws {
        let (context, workspace, card, category) = try fixture()
        for index in 0..<12 {
            context.insert(VariableExpense(descriptionText: "Purchase \(index)", amount: Double(index + 1), transactionDate: today.addingTimeInterval(Double(index)), workspace: workspace, card: card, category: category))
        }
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: today.addingTimeInterval(60))
        var request = MarinaDataRequest(tool: .expenses)
        request.operation = .transactions; request.limit = 5; request.relativePeriod = .currentMonth
        let first = try #require(service.execute(request).presentation)
        #expect(first.records.count == 5)
        #expect(first.pagination?.request.relativePeriod == nil)
        #expect(first.pagination?.request.startDate == "2026-10-01")
        let encoded = try JSONEncoder().encode(first)
        card.name = "Renamed"
        context.insert(VariableExpense(descriptionText: "New purchase", amount: 50, transactionDate: today.addingTimeInterval(30), workspace: workspace, card: card, category: category))
        try context.save()
        let more = try #require(service.loadMore(presentation: first).presentation)
        #expect(more.records.count == 10)
        #expect(more.totalCount == 13)
        #expect(Set(more.records.map(\.id)).count == 10)
        #expect(more.isUpdated)
        #expect(more.metrics.first?.value == 128)
        let saved = try JSONDecoder().decode(MarinaPresentation.self, from: encoded)
        #expect(saved == first)
        #expect(saved.records.first?.cardName == "Apple Card")
        let other = Workspace(name: "Work", hexColor: "#FFFFFF")
        context.insert(other)
        let wrongWorkspace = MarinaReadOnlyDataService(workspace: other, modelContext: context, now: today)
        #expect(try wrongWorkspace.loadMore(presentation: first).status == "invalidRequest")
    }

    @Test func categoryRankingUsesGroupedValuesAndColors() throws {
        let (context, workspace, card, category) = try fixture()
        let rent = Offshore.Category(name: "Rent", hexColor: "#00FF00", workspace: workspace)
        context.insert(rent)
        context.insert(VariableExpense(descriptionText: "Salon", amount: 20.38, transactionDate: today, workspace: workspace, card: card, category: category))
        context.insert(VariableExpense(descriptionText: "Rent", amount: 1200, transactionDate: today, workspace: workspace, card: card, category: rent))
        try context.save()
        var request = MarinaDataRequest(tool: .expenses)
        request.operation = .ranking; request.grouping = .category
        let presentation = try #require(MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: today).execute(request).presentation)
        #expect(presentation.chartPoints.first?.label == "Rent")
        #expect(presentation.chartPoints.first?.value == 1200)
        #expect(presentation.chartPoints.first?.colorHex == "#00FF00")
    }
    @Test func paginationKeepsOriginalFutureExpensePolicy() throws {
        let (context, workspace, card, _) = try fixture()
        for index in 0..<6 {
            context.insert(VariableExpense(descriptionText: "Current \(index)", amount: 10, transactionDate: today, workspace: workspace, card: card))
        }
        context.insert(VariableExpense(descriptionText: "Future", amount: 1000, transactionDate: today.addingTimeInterval(86400), workspace: workspace, card: card))
        try context.save()
        let policy = MarinaPanelHomeContext(dateRange: nil, excludeFutureVariableExpensesFromCalculations: true)
        let original = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, homeContext: policy, now: today)
        var request = MarinaDataRequest(tool: .expenses)
        request.operation = .transactions; request.limit = 5
        let first = try #require(original.execute(request).presentation)
        let later = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: today.addingTimeInterval(172800))
        let refreshed = try #require(later.loadMore(presentation: first).presentation)
        #expect(refreshed.records.count == 6)
        #expect(refreshed.metrics.first?.value == 60)
        #expect(!refreshed.isUpdated)
    }

    @Test func modelSummaryOmitsTransactionPreviewAndLookupIncludesResolvedFilters() throws {
        let (context, workspace, card, category) = try fixture()
        context.insert(VariableExpense(descriptionText: "Coffee", amount: 3.38, transactionDate: today, workspace: workspace, card: card, category: category))
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: today)
        let summary = try service.execute(MarinaDataRequest(tool: .expenses))
        let facts = try #require(JSONSerialization.jsonObject(with: Data(summary.modelFactsJSON.utf8)) as? [String: Any])
        #expect(facts["records"] == nil)
        #expect(facts["nextOffset"] == nil)
        #expect((facts["metrics"] as? [[String: Any]])?.isEmpty == false)
        var lookup = MarinaDataRequest(tool: .findRecords)
        lookup.search = "Apple Card"
        let found = try service.execute(lookup)
        let lookupFacts = try #require(JSONSerialization.jsonObject(with: Data(found.modelFactsJSON.utf8)) as? [String: Any])
        let records = try #require(lookupFacts["records"] as? [[String: Any]])
        let selection = try #require(records.first?["selection"] as? [String: Any])
        #expect(selection["type"] as? String == "expenseMatching")
        #expect(selection["filters"] as? [[String: String]] == [["type": "expenseCard", "id": card.id.uuidString]])
        #expect(records.first?["filter"] == nil)
        lookup.search = "Coffee"
        let merchant = try service.execute(lookup)
        let merchantFacts = try #require(JSONSerialization.jsonObject(with: Data(merchant.modelFactsJSON.utf8)) as? [String: Any])
        let merchants = try #require(merchantFacts["records"] as? [[String: Any]])
        let merchantSelection = try #require(merchants.first?["selection"] as? [String: Any])
        #expect(merchantSelection["type"] as? String == "expenseMatching")
        #expect(merchantSelection["filters"] as? [[String: String]] == [["type": "expenseMerchant", "name": "Coffee"]])
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macCatalyst 26.0, *)
    @Test func expenseFiltersPreserveCombinedScopeAndRejectDuplicateKinds() async throws {
        let (context, workspace, card, category) = try fixture()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: today)
        let bridge = MarinaToolBridge()
        bridge.begin(service: service, onResult: {})
        defer { bridge.end() }
        let tool = MarinaExpensesTool(bridge: bridge)
        let filter = MarinaExpenseFilter.expenseCard(id: card.id.uuidString)
        let generated = try #require(JSONSerialization.jsonObject(with: Data(filter.generatedContent.jsonString.utf8)) as? [String: String])
        #expect(generated == ["type": "expenseCard", "id": card.id.uuidString])
        _ = try await tool.call(arguments: .init(selection: .expenseMatching(filters: [filter, .expenseCategory(id: category.id.uuidString)]), dates: .currentMonth, operation: .summary))
        #expect(bridge.requests.last?.cardID == card.id.uuidString)
        #expect(bridge.requests.last?.categoryID == category.id.uuidString)
        do {
            _ = try await tool.call(arguments: .init(selection: .expenseMatching(filters: [filter, filter]), dates: .currentMonth, operation: .summary))
            Issue.record("Duplicate expense filter kinds must be rejected before execution.")
        } catch {
            #expect(bridge.requests.count == 1)
        }
        do {
            _ = try await tool.call(arguments: .init(selection: .expenseMatching(filters: []), dates: .currentMonth, operation: .summary))
            Issue.record("Empty matching selections must be rejected before execution.")
        } catch {
            #expect(bridge.requests.count == 1)
        }
        let matching = MarinaExpenseSelection.expenseMatching(filters: [filter])
        let matchingJSON = try #require(JSONSerialization.jsonObject(with: Data(matching.generatedContent.jsonString.utf8)) as? [String: Any])
        #expect(matchingJSON["type"] as? String == "expenseMatching")
        #expect(matchingJSON["filters"] as? [[String: String]] == [generated])
        _ = try await tool.call(arguments: .init(selection: .expenseWorkspace, dates: .currentMonth, operation: .summary))
        #expect(bridge.requests.last?.cardID == nil)
        #expect(bridge.requests.last?.categoryID == nil)
    }
    #endif

}
