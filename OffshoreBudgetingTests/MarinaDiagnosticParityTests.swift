#if DEBUG && canImport(FoundationModels)
import Foundation
import FoundationModels
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct MarinaDiagnosticParityTests {
    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let workspace: Workspace
        let card: Card
        let now: Date
    }

    private func fixture() throws -> Fixture {
        let schema = Schema([Workspace.self, Budget.self, Card.self, BudgetCardLink.self, Offshore.Category.self, Preset.self, BudgetPresetLink.self, BudgetCategoryLimit.self, PlannedExpense.self, VariableExpense.self, AllocationAccount.self, ExpenseAllocation.self, AllocationSettlement.self, SavingsAccount.self, SavingsLedgerEntry.self, ImportMerchantRule.self, AssistantAliasRule.self, IncomeSeries.self, Income.self, MarinaChatSession.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = ModelContext(container)
        let workspace = Workspace(name: "PRIVATE_WORKSPACE_SENTINEL", hexColor: "#FFFFFF")
        let card = Card(name: "PRIVATE_CARD_SENTINEL", workspace: workspace)
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 12))!
        context.insert(workspace)
        context.insert(card)
        context.insert(VariableExpense(descriptionText: "PRIVATE_PURCHASE_SENTINEL", amount: 9876.54, transactionDate: now, workspace: workspace, card: card))
        try context.save()
        return Fixture(container: container, context: context, workspace: workspace, card: card, now: now)
    }

    // Row/presentation UUIDs and creation time are independently generated display bookkeeping.
    // Preserve every persisted financial, scope, presentation, and conversation field.
    private func comparableSavedAnswer(_ answer: HomeAnswer) throws -> Data {
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(answer)) as? [String: Any])
        json.removeValue(forKey: "generatedAt")
        if let rows = json["rows"] as? [[String: Any]] {
            json["rows"] = rows.map { row in var copy = row; copy.removeValue(forKey: "id"); return copy }
        }
        if let presentations = json["presentations"] as? [[String: Any]] {
            json["presentations"] = presentations.map { presentation in
                var copy = presentation
                copy.removeValue(forKey: "id")
                return copy
            }
        }
        return try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    }

    @Test func diagnosticsPreserveExactOutputRequestsAndSavedAnswer() async throws {
        let fixture = try fixture()
        defer { withExtendedLifetime(fixture.container) {} }
        let service = MarinaReadOnlyDataService(workspace: fixture.workspace, modelContext: fixture.context, now: fixture.now)
        let answerID = UUID()
        var reports: [String] = []
        let diagnostics = MarinaTokenDiagnostics(sessionID: UUID(), rebuilt: true, historyCount: 0,
            initial: [], instructions: "PRIVATE_INSTRUCTIONS_SENTINEL", tools: [], prompt: "PRIVATE_QUESTION_SENTINEL",
            preparation: .zero, measure: false, enabled: true, onReport: { reports.append($0) })
        let plain = MarinaToolBridge()
        let observed = MarinaToolBridge()
        observed.diagnostics = diagnostics
        plain.begin(service: service, onResult: {})
        observed.begin(service: service, onResult: {})
        defer { plain.end(); observed.end() }
        var memory = MarinaConversationMemory(workspaceID: fixture.workspace.id, chatID: UUID())
        let ref = memory.reference(for: .init(kind: "card", id: fixture.card.id.uuidString, name: fixture.card.name))
        plain.conversationMemory = { memory }
        observed.conversationMemory = { memory }
        let args = MarinaExpensesTool.Arguments(selection: .references([ref]), dates: .currentMonth, operation: .summary)
        let plainOutput = try await MarinaExpensesTool(bridge: plain).call(arguments: args)
        let observedOutput = try await MarinaExpensesTool(bridge: observed).call(arguments: args)
        #expect(plainOutput == observedOutput)
        #expect(observedOutput.contains("visualPresentation"))
        #expect(plain.requests == observed.requests)
        let plainAnswer = plain.answer(id: answerID, prompt: "PRIVATE_QUESTION_SENTINEL", narration: "Verified result")
        let observedAnswer = observed.answer(id: answerID, prompt: "PRIVATE_QUESTION_SENTINEL", narration: "Verified result")
        #expect(try comparableSavedAnswer(plainAnswer) == comparableSavedAnswer(observedAnswer))
        #expect(try JSONDecoder().decode(HomeAnswer.self, from: JSONEncoder().encode(observedAnswer)) == observedAnswer)
        #expect(MarinaContextStatus.measured(tokens: 6143, capacity: 8192) == nil)
        #expect(MarinaContextStatus.measured(tokens: 6144, capacity: 8192) == .approaching)
        #expect(MarinaContextStatus.measured(tokens: 8192, capacity: 8192) == .reached)
        diagnostics.warning("final", MarinaContextStatus.status(in: [observedAnswer]))
        diagnostics.finish(entries: [], outcome: "complete", reset: false)
        await MarinaTokenDiagnostics.flushReports()
        let report = try #require(reports.first)
        #expect(reports.count == 1)
        #expect(report.contains("attempt_count=1 database_execution_count=1"))
        for sentinel in ["PRIVATE_WORKSPACE_SENTINEL", "PRIVATE_CARD_SENTINEL", "PRIVATE_PURCHASE_SENTINEL", "PRIVATE_QUESTION_SENTINEL", "PRIVATE_INSTRUCTIONS_SENTINEL", fixture.workspace.id.uuidString, fixture.card.id.uuidString, "9876.54", "2026-10-17"] {
            #expect(!report.contains(sentinel))
        }
    }

    @Test func clarificationEarlyReturnRemainsIdenticalWithDiagnostics() async throws {
        let fixture = try fixture()
        defer { withExtendedLifetime(fixture.container) {} }
        fixture.context.insert(Card(name: fixture.card.name, workspace: fixture.workspace))
        try fixture.context.save()
        let service = MarinaReadOnlyDataService(workspace: fixture.workspace, modelContext: fixture.context, now: fixture.now)
        var reports: [String] = []
        let diagnostics = MarinaTokenDiagnostics(sessionID: UUID(), rebuilt: true, historyCount: 0,
            initial: [], instructions: "", tools: [], prompt: "", preparation: .zero,
            measure: false, enabled: true, onReport: { reports.append($0) })
        let plain = MarinaToolBridge()
        let observed = MarinaToolBridge()
        observed.diagnostics = diagnostics
        plain.begin(service: service, onResult: {})
        observed.begin(service: service, onResult: {})
        defer { plain.end(); observed.end() }
        let lookup = MarinaFindRecordsTool.Arguments(lookup: .resolveName(name: fixture.card.name))
        let plainLookup = try await MarinaFindRecordsTool(bridge: plain).call(arguments: lookup)
        let observedLookup = try await MarinaFindRecordsTool(bridge: observed).call(arguments: lookup)
        #expect(plainLookup == observedLookup)
        let summary = MarinaExpensesTool.Arguments(selection: .workspace, dates: .currentMonth, operation: .summary)
        let plainOutput = try await MarinaExpensesTool(bridge: plain).call(arguments: summary)
        let observedOutput = try await MarinaExpensesTool(bridge: observed).call(arguments: summary)
        #expect(plainOutput == observedOutput)
        #expect(observedOutput.contains("needsClarification"))
        #expect(plain.requests == observed.requests)
        #expect(observed.requests.count == 1)
        diagnostics.finish(entries: [], outcome: "complete", reset: false)
        await MarinaTokenDiagnostics.flushReports()
        let report = try #require(reports.first)
        #expect(report.contains("attempt_count=2 database_execution_count=1"))
        #expect(report.contains("stage=returned status=needsClarification"))
    }
}
#endif
