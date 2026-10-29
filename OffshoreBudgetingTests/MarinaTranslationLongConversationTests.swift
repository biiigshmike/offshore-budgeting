import Foundation
import SwiftData
import Testing
@testable import Offshore

#if DEBUG && canImport(FoundationModels)
@MainActor
@Suite(.serialized)
struct MarinaTranslationLongConversationTests {
    private typealias Support = MarinaTranslationTestSupport
    private nonisolated static var enabled: Bool { MarinaTranslationTestSupport.longEnabled }

    /// Forced budgeting exercises the app's 4K policy on the current host; it is not
    /// evidence of model accuracy or latency on a physical 4K-context device.
    @Test(.enabled(if: enabled, "Set MARINA_MODEL_EVALUATION=1, MARINA_QUERY_EXPERIMENT_MODE=compiled and MARINA_TRANSLATION_LONG_EVALUATION=1."))
    func twentyTurnsRestoreAnEarlyReportAndReadChangedDataWithinFourK() async throws {
        try Support.requireAvailableModel()
        let fixture = try Support.Fixture()
        try fixture.addSecondCard()
        let suiteName = "MarinaTranslationLongTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = MarinaChatSessionStore(userDefaults: defaults)
        let savedChat = try store.createSession(workspace: fixture.workspace, modelContext: fixture.context)
        let runtime = Support.runtime(fixture, capacity: 4096)
        var history: [HomeAnswer] = []

        let turns: [MarinaCapabilityScenarios.Turn] = [
            .init(id: "first-june-card-report", prompt: "Summarize my Apple Card for June 2026.", tool: .expenses, purpose: .cardSummary, operation: .summary),
            .init(id: "june-highest", prompt: "What was the highest expense on that card in June?", tool: .expenses, operation: .transactions, sort: .largest, positiveOnly: true, limit: 1),
            .init(id: "june-lowest", prompt: "And the lowest?", tool: .expenses, operation: .transactions, sort: .smallest, positiveOnly: true, limit: 1),
            .init(id: "june-merchant", prompt: "Which merchant received most of my spending on that card in that month?", tool: .expenses, operation: .ranking, grouping: .merchant),
            .init(id: "october-received", prompt: "How much income have I received across the workspace in October 2026?", tool: .income, operation: .summary),
            .init(id: "october-planned", prompt: "How much income was planned for that month?", tool: .income, operation: .summary),
            .init(id: "october-income-progress", prompt: "Show planned versus received income progress for October 2026.", tool: .income, purpose: .incomeProgress),
            MarinaCapabilityScenarios.categoryAvailability.turns[0],
            MarinaCapabilityScenarios.categoryComparison.turns[0],
            MarinaCapabilityScenarios.categoryComparison.turns[1],
            .init(id: "greeting-detour", prompt: "Thanks, Marina!", requiresFinancialRead: false),
            MarinaCapabilityScenarios.cardGrouping.turns[0],
            MarinaCapabilityScenarios.cardFollowUps.turns[0],
            MarinaCapabilityScenarios.cardFollowUps.turns[1],
            MarinaCapabilityScenarios.cardFollowUps.turns[2],
            .init(id: "income-topic-change-again", prompt: "How much income have I received in October 2026?", tool: .income, operation: .summary),
            MarinaCapabilityScenarios.categoryWarnings.turns[0],
            .init(id: "spending-pattern-detour", prompt: "Show my spending patterns in October 2026.", tool: .expenses, purpose: .spendingPatterns),
            .init(id: "last-income-detour", prompt: "What was my received income for October 2026?", tool: .income, operation: .summary)
        ]

        for (index, turn) in turns.enumerated() {
            let answer = try await Support.ask(turn, runtime: runtime, fixture: fixture,
                chatID: savedChat.id, history: &history)
            switch index {
            case 0, 1, 2, 3:
                Support.expectCardScope(runtime, fixture: fixture, month: 6)
                Support.expectMoney([900.0, 800, 100, 800][index], in: answer)
            case 4, 15, 18:
                #expect(runtime.toolRequests.contains { $0.tool == .income && $0.state == .actual && $0.cardID == nil })
                #expect(runtime.memory?.latestFinancialQuery?.selection == nil)
                Support.expectPeriod(runtime, month: 10)
                Support.expectMoney(1000, in: answer)
            case 5:
                #expect(runtime.toolRequests.contains { $0.tool == .income && $0.state == .planned && $0.cardID == nil })
                Support.expectMoney(1200, in: answer)
            case 6:
                #expect(answer.presentations?.contains { $0.incomeProgress?.actual == 1000 && $0.incomeProgress?.planned == 1200 } == true)
            case 7: Support.expectAvailability(answer, warningsOnly: false)
            case 8:
                Support.expectWords(["Dining"], in: answer)
                Support.expectMoney(530, in: answer)
            case 9: Support.expectLeaders(answer, runtime: runtime)
            case 11: Support.expectCardGroups(answer, runtime: runtime)
            case 12, 13, 14:
                Support.expectCardScope(runtime, fixture: fixture)
                Support.expectMoney([785.0, 400, 5][index - 12], in: answer)
            case 16: Support.expectAvailability(answer, warningsOnly: true)
            case 17:
                #expect(answer.presentations?.count == 1)
                #expect(answer.presentations?.first?.report?.peak != nil)
            default: break
            }
        }

        let memory = try #require(runtime.memory)
        try store.saveTranscript(history, sessionID: savedChat.id, workspaceID: fixture.workspace.id,
            modelContext: fixture.context, memory: memory)
        let reopenedContext = ModelContext(fixture.container)
        let reopenedStore = MarinaChatSessionStore(userDefaults: defaults)
        let reopenedChat = try #require(reopenedStore.sessions(workspaceID: fixture.workspace.id,
            modelContext: reopenedContext).first { $0.id == savedChat.id })
        let restoredMemory = try #require(reopenedStore.memory(for: reopenedChat))
        var restoredHistory = reopenedStore.visibleAnswers(for: reopenedChat)
        #expect(restoredHistory == history)
        #expect(restoredHistory.count == 19)

        // The active topic is October income and recent card work concerned October.
        // Returning to the first report must recover June, then re-read its changed data.
        let lateExpense = VariableExpense(descriptionText: "Late June micro purchase", amount: 1,
            transactionDate: Support.Fixture.date(month: 6, day: 28), workspace: fixture.workspace, card: fixture.card)
        fixture.context.insert(lateExpense)
        try fixture.context.save()
        let resumed = Support.runtime(fixture, capacity: 4096)
        let answer = try await Support.ask("Back to the first card summary in this chat: what is its cheapest purchase now?",
            id: "restored-earliest-report", runtime: resumed, fixture: fixture, chatID: savedChat.id,
            history: &restoredHistory, restoredMemory: restoredMemory)
        Support.expectCardScope(resumed, fixture: fixture, month: 6)
        #expect(resumed.toolRequests.contains { $0.tool == .expenses && $0.operation == .transactions
            && $0.sort == .smallest && $0.positiveOnly == true && $0.limit == 1 })
        #expect(answer.presentations?.contains { $0.records.first?.id == lateExpense.id.uuidString } == true)
        Support.expectWords(["Late June micro purchase"], in: answer)
        Support.expectMoney(1, in: answer)
        #expect(restoredHistory.count == 20)
        #expect(Array(restoredHistory.prefix(19)) == history)
        print("MarinaTranslationScenario long-restoration attempted_turns=20 forced_capacity=4096")
    }
}
#endif
