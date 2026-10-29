import Foundation
import SwiftData
import Testing
#if canImport(FoundationModels)
import FoundationModels
#endif
@testable import Offshore

@MainActor
final class MarinaPresentationTests {
    private var retainedContainers: [ModelContainer] = []

    private func fixture() throws -> (ModelContext, Workspace, Card, Offshore.Category) {
        let schema = Schema([Workspace.self, Budget.self, Card.self, BudgetCardLink.self, Offshore.Category.self, Preset.self, BudgetPresetLink.self, BudgetCategoryLimit.self, PlannedExpense.self, VariableExpense.self, AllocationAccount.self, ExpenseAllocation.self, AllocationSettlement.self, SavingsAccount.self, SavingsLedgerEntry.self, ImportMerchantRule.self, AssistantAliasRule.self, IncomeSeries.self, Income.self, MarinaChatSession.self])
        let configuration = ModelConfiguration("MarinaPresentationFixture-\(UUID().uuidString)", schema: schema,
                                               isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: configuration)
        retainedContainers.append(container)
        let context = ModelContext(container)
        let workspace = Workspace(name: "Personal", hexColor: "#FFFFFF")
        let card = Card(name: "Apple Card", workspace: workspace)
        let category = Offshore.Category(name: "Hair Care", hexColor: "#FF0000", workspace: workspace)
        context.insert(workspace); context.insert(card); context.insert(category)
        return (context, workspace, card, category)
    }
    private var today: Date { Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 12))! }

    @Test func summaryMemoryFreezesValidatedDatesWithoutCachingFinancialValues() throws {
        let (context, workspace, card, _) = try fixture()
        context.insert(VariableExpense(descriptionText: "Purchase", amount: 30, transactionDate: today,
            workspace: workspace, card: card))
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: today)
        let request = MarinaDataRequest(operation: .comparison, relativePeriod: .currentMonth,
            tool: .expenses, cardID: card.id.uuidString, comparisonPeriod: .previousMonth)
        let result = try service.execute(request)
        #expect(result.presentation?.pagination == nil)
        let resolved = try #require(result.resolvedRequest)
        #expect(resolved.cardID == card.id.uuidString)
        #expect(resolved.startDate == "2026-10-01" && resolved.endDate == "2026-10-31")
        #expect(resolved.comparisonStartDate == "2026-09-01" && resolved.comparisonEndDate == "2026-09-30")
        #expect(resolved.relativePeriod == nil && resolved.comparisonPeriod == nil)
        var memory = MarinaConversationMemory(workspaceID: workspace.id, chatID: UUID())
        memory.record(request: request, result: result, answerID: UUID())
        #expect(memory.recentQueries.last?.period.startDate == "2026-10-01")
        #expect(memory.recentQueries.last?.comparisonPeriod?.endDate == "2026-09-30")
        #expect(!memory.contextText(maxBytes: 2400).contains("metrics"))
        // The next read with these dates still observes edits made after the remembered result.
        context.insert(VariableExpense(descriptionText: "Late entry", amount: 5, transactionDate: today,
            workspace: workspace, card: card))
        try context.save()
        let fresh = try service.execute(resolved)
        #expect(fresh.metrics.first { $0.label == "Total" }?.value == 35)
        #expect(result.metrics.first { $0.label == "Total" }?.value == 30)
    }

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

    @Test func modelSummaryOmitsTransactionPreviewAndLookupIncludesBoundReferences() throws {
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
        var memory = MarinaConversationMemory(workspaceID: workspace.id, chatID: UUID())
        memory.record(request: lookup, result: found, answerID: UUID())
        let lookupJSON = found.modelFactsJSON(for: lookup) { memory.reference(forKind: $0, id: $1) }
        let lookupFacts = try #require(JSONSerialization.jsonObject(with: Data(lookupJSON.utf8)) as? [String: Any])
        let records = try #require(lookupFacts["records"] as? [[String: Any]])
        let ref = try #require(records.first?["selection"] as? String)
        #expect(memory.entity(forReference: ref)?.id == card.id.uuidString)
        #expect(!lookupJSON.contains(card.id.uuidString))
        #expect(records.first?["filter"] == nil)
        lookup.search = "Coffee"
        let merchant = try service.execute(lookup)
        memory.record(request: lookup, result: merchant, answerID: UUID())
        let merchantJSON = merchant.modelFactsJSON(for: lookup) { memory.reference(forKind: $0, id: $1) }
        let merchantFacts = try #require(JSONSerialization.jsonObject(with: Data(merchantJSON.utf8)) as? [String: Any])
        let merchants = try #require(merchantFacts["records"] as? [[String: Any]])
        let merchantRef = try #require(merchants.first?["selection"] as? String)
        #expect(memory.entity(forReference: merchantRef)?.name == "Coffee")
        #expect(memory.entity(forReference: merchantRef)?.kind == "merchant")
    }

    @Test func compactFactsKeepFinancialMeaningAndFullTotalsWithoutChangingSnapshots() throws {
        let (context, workspace, card, category) = try fixture()
        for index in 0..<8 {
            context.insert(VariableExpense(descriptionText: "Coffee \(index)", amount: 3.38,
                transactionDate: today, workspace: workspace, card: card, category: category))
        }
        try context.save()
        var request = MarinaDataRequest(tool: .expenses)
        request.operation = .transactions; request.limit = 5
        request.expenseMeasure = .ledger; request.cardID = card.id.uuidString
        let result = try MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: today).execute(request)
        let original = result
        let facts = try #require(JSONSerialization.jsonObject(with: Data(result.modelFactsJSON(for: request).utf8)) as? [String: Any])
        let metrics = try #require(facts["metrics"] as? [[String: Any]])
        #expect(metrics.first?["formatted"] as? String == CurrencyFormatter.string(from: 27.04))
        #expect(metrics.allSatisfy { $0["value"] == nil })
        let records = try #require(facts["records"] as? [[String: Any]])
        #expect(records.count == 5)
        #expect(records.allSatisfy { $0["id"] == nil && $0["amount"] == nil })
        #expect(records.first?["formattedAmount"] as? String == CurrencyFormatter.string(from: 3.38))
        #expect(facts["totalCount"] as? Int == 8)
        #expect(facts["nextOffset"] as? Int == 5)
        #expect((facts["qualifier"] as? String)?.contains("Ledger amounts") == true)
        #expect((facts["appliedFilters"] as? String)?.contains(card.name) == true)
        #expect((facts["scope"] as? String)?.contains("2026") == true)
        #expect(result == original)
        #expect(result.presentation?.records.first?.id.isEmpty == false)
        #expect(result.presentation?.records.first?.amount == 3.38)
    }

    @Test func incomeSummaryFactsIncludeOnlyRequestedStateTotalsAndPreserveFullResults() throws {
        let (context, workspace, card, _) = try fixture()
        context.insert(Income(source: "Salary", amount: 500.38, date: today, isPlanned: false,
                              workspace: workspace, card: card))
        context.insert(Income(source: "Salary", amount: 800.42, date: today, isPlanned: true,
                              workspace: workspace, card: card))
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: today)
        for (state, expectedTotal) in [(MarinaDataRequest.State.actual, 500.38), (.planned, 800.42), (.all, 1300.8)] {
            var request = MarinaDataRequest(tool: .income)
            request.state = state
            request.relativePeriod = .currentMonth
            request.cardID = card.id.uuidString
            let result = try service.execute(request)
            let original = result
            let facts = try #require(JSONSerialization.jsonObject(with: Data(result.modelFactsJSON(for: request).utf8)) as? [String: Any])
            let metrics = try #require(facts["metrics"] as? [[String: Any]])
            #expect(Set(metrics.compactMap { $0["label"] as? String }) == ["Total", "Count", "Average per record", "Average per calendar day"])
            let recordCount = state == .all ? 2.0 : 1.0
            #expect(metrics.first { $0["label"] as? String == "Average per record" }?["formatted"] as? String
                == CurrencyFormatter.string(from: expectedTotal / recordCount))
            #expect(metrics.first?["formatted"] as? String == CurrencyFormatter.string(from: expectedTotal))
            #expect((facts["explanation"] as? String)?.contains("Income state: \(state.rawValue)") == true)
            #expect((facts["explanation"] as? String)?.contains("all matching records") == true)
            #expect((facts["appliedFilters"] as? String)?.contains(card.name) == true)
            #expect(facts["totalCount"] as? Int == (state == .all ? 2 : 1))
            #expect(facts["records"] == nil)
            #expect(result == original)
            #expect(result.metrics.contains { $0.label == "Actual income" && $0.value == 500.38 })
            #expect(result.metrics.contains { $0.label == "Planned income" && $0.value == 800.42 })
        }
        var progress = MarinaDataRequest(tool: .income)
        progress.purpose = .incomeProgress
        let progressResult = try service.execute(progress)
        let progressFacts = try #require(JSONSerialization.jsonObject(with: Data(progressResult.modelFactsJSON(for: progress).utf8)) as? [String: Any])
        let progressMetrics = try #require(progressFacts["metrics"] as? [[String: Any]])
        #expect(Set(progressMetrics.compactMap { $0["label"] as? String }) == ["Actual income", "Planned income", "Income progress percent"])
    }

    @Test func accountFactsAreBoundedAndRetainPaginationAndBalanceDirection() throws {
        let (context, workspace, _, _) = try fixture()
        for index in 0..<12 { context.insert(AllocationAccount(name: "Account \(index)", workspace: workspace)) }
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: today)
        var request = MarinaDataRequest(tool: .accounts)
        request.scope = .reconciliation; request.limit = 5
        let result = try service.execute(request)
        var memory = MarinaConversationMemory(workspaceID: workspace.id, chatID: UUID())
        memory.record(request: request, result: result, answerID: UUID())
        let json = result.modelFactsJSON(for: request) { memory.reference(forKind: $0, id: $1) }
        let facts = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(result.metrics.count == 12)
        #expect((facts["metrics"] as? [[String: Any]])?.isEmpty == true)
        let records = try #require(facts["records"] as? [[String: Any]])
        #expect(records.count == 5)
        let ref = try #require(records.first?["selection"] as? String)
        #expect(memory.entity(forReference: ref)?.kind == "reconciliationAccount")
        #expect(memory.entity(forReference: ref)?.id == result.records.first?.id)
        #expect(facts["totalCount"] as? Int == 12)
        #expect(facts["nextOffset"] as? Int == 5)
        #expect((facts["explanation"] as? String)?.contains("a negative balance means you owe money") == true)
        request.offset = 100
        let emptyPage = try service.execute(request)
        let emptyFacts = try #require(JSONSerialization.jsonObject(with: Data(emptyPage.modelFactsJSON(for: request).utf8)) as? [String: Any])
        #expect((emptyFacts["metrics"] as? [[String: Any]])?.isEmpty == true)
        #expect(emptyFacts["totalCount"] as? Int == 12)
    }

    @Test func selectedAccountFactsKeepCurrentBalanceAndFullPeriodActivity() throws {
        let (context, workspace, _, _) = try fixture()
        let account = SavingsAccount(workspace: workspace)
        context.insert(account)
        for index in 0..<8 {
            context.insert(SavingsLedgerEntry(date: today, amount: 10, note: "Saved \(index)",
                kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue, workspace: workspace, account: account))
        }
        try context.save()
        var request = MarinaDataRequest(tool: .accounts)
        request.accountID = account.id.uuidString; request.limit = 5
        let result = try MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: today).execute(request)
        let facts = try #require(JSONSerialization.jsonObject(with: Data(result.modelFactsJSON(for: request).utf8)) as? [String: Any])
        let metrics = try #require(facts["metrics"] as? [[String: Any]])
        #expect(metrics.first?["formatted"] as? String == CurrencyFormatter.string(from: 80))
        #expect(metrics.contains { $0["label"] as? String == "Selected period activity total" && $0["formatted"] as? String == CurrencyFormatter.string(from: 80) })
        #expect(facts["totalCount"] as? Int == 8)
        #expect(facts["nextOffset"] as? Int == 5)
        #expect((facts["records"] as? [[String: Any]])?.count == 5)
    }

    @Test func paceFactsExcludeUnrelatedBudgetMetricsButPreserveCalculations() throws {
        let (context, workspace, _, _) = try fixture()
        var request = MarinaDataRequest(tool: .budgetSummary)
        request.purpose = .budgetPace
        let result = try MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: today).execute(request)
        let facts = try #require(JSONSerialization.jsonObject(with: Data(result.modelFactsJSON(for: request).utf8)) as? [String: Any])
        let metrics = try #require(facts["metrics"] as? [[String: Any]])
        #expect(metrics.count <= 7)
        #expect(metrics.contains { $0["label"] as? String == "Expected spending by now" })
        #expect(metrics.contains { $0["label"] as? String == "Pace actual spending" })
        #expect(!metrics.contains { $0["label"] as? String == "Actual income" })
        #expect(result.metrics.contains { $0.label == "Actual income" })
        #expect(facts["records"] == nil)
        #expect((facts["qualifier"] as? String)?.contains("unrecorded expenses due by today") == true)
    }

    @Test func comparisonFactsRetainBothScopesAndExactTotals() throws {
        let (context, workspace, card, _) = try fixture()
        context.insert(VariableExpense(descriptionText: "Coffee", amount: 3.38, transactionDate: today, workspace: workspace, card: card))
        try context.save()
        var request = MarinaDataRequest(tool: .expenses)
        request.operation = .comparison; request.relativePeriod = .currentMonth
        request.comparisonPeriod = .previousMonth
        let result = try MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: today).execute(request)
        let facts = try #require(JSONSerialization.jsonObject(with: Data(result.modelFactsJSON(for: request).utf8)) as? [String: Any])
        #expect(facts["comparisonScope"] as? String == result.presentation?.chartPoints.last?.label)
        #expect((facts["comparisonScope"] as? String)?.isEmpty == false)
        let metrics = try #require(facts["metrics"] as? [[String: Any]])
        #expect(metrics.contains { $0["label"] as? String == "Total" && $0["formatted"] as? String == CurrencyFormatter.string(from: 3.38) })
        #expect(metrics.contains { $0["label"] as? String == "Comparison total" && $0["formatted"] as? String == CurrencyFormatter.string(from: 0) })
        #expect(facts["records"] == nil)
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macCatalyst 26.0, *)
    @Test func compactDatesPreserveEveryDateSelectionAndRejectPartialRanges() async throws {
        let (context, workspace, _, _) = try fixture()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: today)
        let bridge = MarinaToolBridge()
        defer { bridge.end() }
        let tool = MarinaAccountsTool(bridge: bridge)
        let relatives: [(MarinaDateSelection, MarinaDataRequest.RelativePeriod)] = [
            (.selectedPeriod, .selectedPeriod), (.previousPeriod, .previousPeriod),
            (.currentMonth, .currentMonth), (.previousMonth, .previousMonth),
            (.yearToDate, .yearToDate), (.nextSevenDays, .nextSevenDays)
        ]
        for (dates, expected) in relatives {
            bridge.begin(service: service, onResult: {})
            _ = try await tool.call(arguments: .init(selection: .workspace, dates: dates))
            #expect(bridge.requests.last?.relativePeriod == expected)
            #expect(bridge.requests.last?.startDate == nil)
            #expect(bridge.requests.last?.allTime == false)
        }
        bridge.begin(service: service, onResult: {})
        _ = try await tool.call(arguments: .init(selection: .workspace, dates: .allTime))
        #expect(bridge.requests.last?.allTime == true)
        bridge.begin(service: service, onResult: {})
        _ = try await tool.call(arguments: .init(selection: .workspace, dates: .dates(start: "2026-10-01", end: "2026-10-31")))
        #expect(bridge.requests.last?.startDate == "2026-10-01")
        #expect(bridge.requests.last?.endDate == "2026-10-31")
        for dates in [MarinaDateSelection.dates(start: "2026-10-01", end: ""),
                      .dates(start: " ", end: "2026-10-31")] {
            bridge.begin(service: service, onResult: {})
            let feedback = try await tool.call(arguments: .init(selection: .workspace, dates: dates))
            try expectInvalidArguments(feedback, bridge: bridge)
        }
    }

    @available(iOS 26.0, macCatalyst 26.0, *)
    @Test func compactIncomeOperationsKeepAllRequestMappings() async throws {
        let (context, workspace, card, _) = try fixture()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: today)
        let bridge = MarinaToolBridge()
        defer { bridge.end() }
        var memory = MarinaConversationMemory(workspaceID: workspace.id, chatID: UUID())
        _ = memory.reference(for: .init(kind: "card", id: card.id.uuidString, name: card.name))
        _ = memory.reference(for: .init(kind: "incomeSource", id: "Salary", name: "Salary"))
        bridge.conversationMemory = { memory }
        let tool = MarinaIncomeTool(bridge: bridge)
        let operations: [MarinaIncomeOperation] = [.summary, .progress, .timeline, .transactions(order: .largest, offset: 5),
            .groups(by: .source, offset: 10), .periodTotals(unit: .week, offset: 15),
            .compareIncome(selection: .references(["r1", "r2"]), dates: .previousMonth)]
        for operation in operations {
            bridge.begin(service: service, onResult: {})
            _ = try await tool.call(arguments: .init(selection: .workspace, dates: .currentMonth, state: .actual, operation: operation))
            let request = try #require(bridge.requests.last)
            #expect(request.relativePeriod == .currentMonth)
            #expect(request.limit == 5)
            switch operation {
            case .summary: #expect(request.operation == .summary && request.state == .actual)
            case .progress: #expect(request.purpose == .incomeProgress && request.state == .all)
            case .timeline: #expect(request.purpose == .incomeTimeline && request.state == .all)
            case .transactions: #expect(request.operation == .transactions && request.sort == .largest && request.offset == 5)
            case .groups: #expect(request.operation == .ranking && request.grouping == .source && request.offset == 10)
            case .periodTotals: #expect(request.operation == .trend && request.periodUnit == .week && request.offset == 15)
            case .compareIncome:
                #expect(request.operation == .comparison && request.comparisonPeriod == .previousMonth)
                #expect(request.comparisonFilter?.search == "Salary")
                #expect(request.comparisonFilter?.cardID == card.id.uuidString)
            }
        }
        bridge.begin(service: service, onResult: {})
        let feedback = try await tool.call(arguments: .init(selection: .workspace, dates: .currentMonth, state: .actual,
                                                           operation: .groups(by: .none, offset: 0)))
        try expectInvalidArguments(feedback, bridge: bridge)
    }

    @available(iOS 26.0, macCatalyst 26.0, *)
    @Test func compactBudgetAndLookupOperationsKeepAllRequestMappings() async throws {
        let (context, workspace, _, _) = try fixture()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: today)
        let bridge = MarinaToolBridge()
        defer { bridge.end() }
        let budget = MarinaBudgetTool(bridge: bridge)
        for operation in [MarinaBudgetOperation.overview, .pace, .details, .categoryAvailability,
                          .savingsOutlook, .savingsTimeline, .linkedCards, .linkedPresets,
                          .savingsTrend(unit: .month, offset: 5)] {
            bridge.begin(service: service, onResult: {})
            _ = try await budget.call(arguments: .init(selection: .workspace, operation: operation, dates: .currentMonth))
            let request = try #require(bridge.requests.last)
            switch operation {
            case .overview: #expect(request.purpose == nil && request.periodUnit == nil)
            case .pace: #expect(request.purpose == .budgetPace)
            case .details: #expect(request.purpose == .budgetDetails)
            case .categoryAvailability: #expect(request.purpose == .categoryAvailability)
            case .savingsOutlook: #expect(request.purpose == .savingsOutlook)
            case .savingsTimeline: #expect(request.purpose == .savingsTimeline)
            case .linkedCards: #expect(request.purpose == .budgetCards)
            case .linkedPresets: #expect(request.purpose == .budgetPresets)
            case .savingsTrend: #expect(request.periodUnit == .month && request.offset == 5)
            }
        }
        let lookup = MarinaFindRecordsTool(bridge: bridge)
        bridge.begin(service: service, onResult: {})
        _ = try await lookup.call(arguments: .init(lookup: .resolveName(name: "Apple Card")))
        #expect(bridge.requests.last?.search == "Apple Card")
        bridge.begin(service: service, onResult: {})
        _ = try await lookup.call(arguments: .init(lookup: .inventory(kind: .category, offset: 5)))
        #expect(bridge.requests.last?.recordKind == "category")
        #expect(bridge.requests.last?.offset == 5)
        bridge.begin(service: service, onResult: {})
        let feedback = try await lookup.call(arguments: .init(lookup: .resolveName(name: " ")))
        try expectInvalidArguments(feedback, bridge: bridge)
    }

    @available(iOS 26.0, macCatalyst 26.0, *)
    @Test func compactSelectionsCannotSilentlyBroadenMalformedNamedFilters() async throws {
        let (context, workspace, card, _) = try fixture()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: today)
        let bridge = MarinaToolBridge()
        defer { bridge.end() }
        let tool = MarinaExpensesTool(bridge: bridge)
        var memory = MarinaConversationMemory(workspaceID: workspace.id, chatID: UUID())
        let merchant = memory.reference(for: .init(kind: "merchant", id: "Coffee", name: "Coffee"))
        let account = memory.reference(for: .init(kind: "savingsAccount", id: UUID().uuidString, name: "Savings"))
        bridge.conversationMemory = { memory }
        let selections: [MarinaSelection] = [
            .references([]), .references([""]), .references(["unknown"]),
            .references([card.id.uuidString]), .references([account])
        ]
        for selection in selections {
            bridge.begin(service: service, onResult: {})
            let feedback = try await tool.call(arguments: .init(selection: selection, dates: .currentMonth, operation: .summary))
            try expectInvalidArguments(feedback, bridge: bridge)
        }
        bridge.begin(service: service, onResult: {})
        _ = try await tool.call(arguments: .init(selection: .references([merchant]),
            dates: .currentMonth, operation: .compare(selection: .workspace,
                dates: .dates(start: "2026-09-01", end: "2026-09-30"))))
        #expect(bridge.requests.last?.merchantName == "Coffee")
        #expect(bridge.requests.last?.comparisonStartDate == "2026-09-01")
        #expect(bridge.requests.last?.comparisonEndDate == "2026-09-30")
        #expect(bridge.requests.last?.comparisonFilter?.search == nil)
        #expect(bridge.requests.last?.comparisonFilter?.merchantName == nil)
    }

    @available(iOS 26.0, macCatalyst 26.0, *)
    private func expectInvalidArguments(_ feedback: String, bridge: MarinaToolBridge, requestCount: Int = 0) throws {
        let object = try #require(JSONSerialization.jsonObject(with: Data(feedback.utf8)) as? [String: Any])
        #expect(object["status"] as? String == "invalidRequest")
        #expect((object["explanation"] as? String)?.isEmpty == false)
        #expect(bridge.hasInvalidRequest)
        #expect(bridge.requests.count == requestCount)
    }

    @available(iOS 26.0, macCatalyst 26.0, *)
    @Test func invalidArgumentFeedbackAllowsCorrectionWithoutReadingDataAndStillLimitsAttempts() async throws {
        let (context, workspace, card, _) = try fixture()
        context.insert(VariableExpense(descriptionText: "Coffee", amount: 3.38, transactionDate: today,
                                       workspace: workspace, card: card))
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: today)
        let bridge = MarinaToolBridge()
        bridge.begin(service: service, onResult: {})
        defer { bridge.end() }
        var reads = 0
        bridge.onValidatedResult = { _, _ in reads += 1 }
        let tool = MarinaExpensesTool(bridge: bridge)
        var memory = MarinaConversationMemory(workspaceID: workspace.id, chatID: UUID())
        let cardRef = memory.reference(for: .init(kind: "card", id: card.id.uuidString, name: card.name))
        bridge.conversationMemory = { memory }
        let malformed = MarinaSelection.references([])
        let feedback = try await tool.call(arguments: .init(selection: malformed, dates: .currentMonth, operation: .summary))
        try expectInvalidArguments(feedback, bridge: bridge)
        #expect(reads == 0)
        #expect(!bridge.hasResults && !bridge.hasFinancialResults)
        let failedAnswer = bridge.answer(id: UUID(), prompt: "Coffee?", narration: "")
        #expect(failedAnswer.presentations?.isEmpty == true)
        #expect(failedAnswer.rows.allSatisfy { $0.amount == nil })
        _ = try await tool.call(arguments: .init(selection: .references([cardRef]),
                                               dates: .currentMonth, operation: .summary))
        #expect(reads == 1)
        #expect(!bridge.hasInvalidRequest && bridge.hasFinancialResults)
        let corrected = bridge.answer(id: UUID(), prompt: "Coffee?", narration: "Found it.")
        #expect(corrected.presentations?.count == 1)
        #expect(corrected.rows.contains { $0.title == "Total" && $0.amount == 3.38 })
        #expect(!corrected.rows.contains { $0.title.contains("A matching expense selection requires") })

        // Two attempts were used above. Six more malformed calls exhaust the same turn budget.
        for _ in 0..<6 {
            let output = try await tool.call(arguments: .init(selection: malformed, dates: .currentMonth, operation: .summary))
            try expectInvalidArguments(output, bridge: bridge, requestCount: 1)
        }
        do {
            _ = try await tool.call(arguments: .init(selection: .workspace, dates: .currentMonth, operation: .summary))
            Issue.record("Valid and invalid tool attempts must share the eight-call limit.")
        } catch { #expect(reads == 1 && bridge.requests.count == 1) }
    }

    @available(iOS 26.0, macCatalyst 26.0, *)
    @Test func accountNamesCannotBeUsedAsIDsOrSilentlyBroadenARead() async throws {
        let (context, workspace, _, _) = try fixture()
        let account = AllocationAccount(name: "Alex", workspace: workspace)
        context.insert(account)
        try context.save()
        let bridge = MarinaToolBridge()
        bridge.begin(service: MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: today), onResult: {})
        defer { bridge.end() }
        var memory = MarinaConversationMemory(workspaceID: workspace.id, chatID: UUID())
        let ref = memory.reference(for: .init(kind: "reconciliationAccount", id: account.id.uuidString, name: account.name))
        bridge.conversationMemory = { memory }
        let tool = MarinaAccountsTool(bridge: bridge)
        let feedback = try await tool.call(arguments: .init(selection: .references(["Alex"]), scope: .reconciliation, dates: .currentMonth))
        try expectInvalidArguments(feedback, bridge: bridge)
        #expect(feedback.contains("findRecords"))
        #expect(!bridge.hasFinancialResults)
        _ = try await tool.call(arguments: .init(selection: .references([ref]), scope: .reconciliation, dates: .currentMonth))
        #expect(bridge.requests.count == 1)
        #expect(bridge.requests.first?.accountID == account.id.uuidString)
        #expect(bridge.hasFinancialResults && !bridge.hasInvalidRequest)
    }

    @available(iOS 26.0, macCatalyst 26.0, *)
    @Test func expenseFiltersPreserveCombinedScopeAndRejectDuplicateKinds() async throws {
        let (context, workspace, card, category) = try fixture()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: today)
        let bridge = MarinaToolBridge()
        bridge.begin(service: service, onResult: {})
        defer { bridge.end() }
        let tool = MarinaExpensesTool(bridge: bridge)
        var memory = MarinaConversationMemory(workspaceID: workspace.id, chatID: UUID())
        let cardRef = memory.reference(for: .init(kind: "card", id: card.id.uuidString, name: card.name))
        let categoryRef = memory.reference(for: .init(kind: "category", id: category.id.uuidString, name: category.name))
        bridge.conversationMemory = { memory }
        _ = try await tool.call(arguments: .init(selection: .references([cardRef, categoryRef]), dates: .currentMonth, operation: .summary))
        #expect(bridge.requests.last?.cardID == card.id.uuidString)
        #expect(bridge.requests.last?.categoryID == category.id.uuidString)
        let duplicate = try await tool.call(arguments: .init(selection: .references([cardRef, cardRef]), dates: .currentMonth, operation: .summary))
        try expectInvalidArguments(duplicate, bridge: bridge, requestCount: 1)
        let empty = try await tool.call(arguments: .init(selection: .references([]), dates: .currentMonth, operation: .summary))
        try expectInvalidArguments(empty, bridge: bridge, requestCount: 1)
        let matching = MarinaSelection.references([cardRef])
        let matchingJSON = try #require(JSONSerialization.jsonObject(with: Data(matching.generatedContent.jsonString.utf8), options: [.fragmentsAllowed]) as? String)
        #expect(matchingJSON == cardRef)
        let broader = try await tool.call(arguments: .init(selection: .workspace, dates: .currentMonth, operation: .summary))
        try expectInvalidArguments(broader, bridge: bridge, requestCount: 1)
        bridge.begin(service: service, prompt: "Start a new question across all cards.", onResult: {})
        _ = try await tool.call(arguments: .init(selection: .workspace, dates: .currentMonth, operation: .summary))
        #expect(bridge.requests.last?.cardID == nil)
        #expect(bridge.requests.last?.categoryID == nil)
    }
    #endif

}
