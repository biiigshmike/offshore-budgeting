import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct MarinaCompletedFramePersistenceTests {
    @Test func savedAnswerFramesOutliveTheMemoryCacheAndLargerCacheStillHasAHardLimit() throws {
        let schema = Schema([Workspace.self, Budget.self, BudgetCategoryLimit.self, Card.self,
            BudgetCardLink.self, BudgetPresetLink.self, Offshore.Category.self, Preset.self,
            PlannedExpense.self, VariableExpense.self, AllocationAccount.self, ExpenseAllocation.self,
            AllocationSettlement.self, SavingsAccount.self, SavingsLedgerEntry.self,
            ImportMerchantRule.self, AssistantAliasRule.self, MarinaChatSession.self,
            IncomeSeries.self, Income.self])
        let container = try ModelContainer(for: schema, configurations:
            ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = ModelContext(container)
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        context.insert(workspace)
        let suite = "MarinaCompletedFramePersistence-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MarinaChatSessionStore(userDefaults: defaults)
        let session = try store.createSession(workspace: workspace, modelContext: context)
        var memory = MarinaConversationMemory(workspaceID: workspace.id, chatID: session.id)
        var answers: [HomeAnswer] = []
        for index in 1...25 {
            var request = MarinaDataRequest(tool: .expenses, startDate: "2026-10-01", endDate: "2026-10-31")
            request.categoryIDs = (0..<12).map { _ in UUID().uuidString }
            request.merchantName = String(repeating: "Merchant", count: 25)
            let question = "Question \(index) " + String(repeating: "detail ", count: 80)
            let scope = String(repeating: "Category ", count: 70)
            let answerID = UUID()
            var answer = HomeAnswer(id: answerID, queryID: UUID(), kind: .message,
                                    userPrompt: question, title: "Saved report")
            let committed = memory.commitCompletedFrame(request: request,
                result: .init(scope: scope, resolvedRequest: request), answerID: answerID, prompt: question)
            answer.completedFrame = try #require(committed)
            answers.append(answer)
        }
        let encodedMemory = try JSONEncoder().encode(memory)
        #expect(encodedMemory.count > 12_288)
        #expect(encodedMemory.count <= MarinaConversationMemory.maxStoredBytes)
        try store.saveTranscript(answers, sessionID: session.id, workspaceID: workspace.id,
                                 modelContext: context, memory: memory)
        let restoredAnswers = store.visibleAnswers(for: session)
        let restoredMemory = try #require(store.memory(for: session))
        #expect(restoredAnswers.count == 25)
        #expect(restoredMemory.completedFrames.count <= MarinaConversationMemory.maxCompletedFrames)
        #expect(restoredMemory.completedFrame(reference: "t1") == nil)
        #expect(restoredMemory.completedFrame(reference: "t1", history: restoredAnswers)?.answerID == answers[0].id)
        session.followUpContextData = Data(repeating: 65, count: MarinaConversationMemory.maxStoredBytes + 1)
        #expect(store.memory(for: session) == nil)
        #expect(store.visibleAnswers(for: session) == restoredAnswers)
        withExtendedLifetime(container) {}
    }
}
