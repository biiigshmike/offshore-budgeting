import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
final class MarinaChatSessionStoreTests {
    // ModelContext does not keep its container's store connection alive on every platform.
    private var retainedContainers: [ModelContainer] = []

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Workspace.self,
            Budget.self,
            BudgetCategoryLimit.self,
            Card.self,
            BudgetCardLink.self,
            BudgetPresetLink.self,
            Category.self,
            Preset.self,
            PlannedExpense.self,
            VariableExpense.self,
            AllocationAccount.self,
            ExpenseAllocation.self,
            AllocationSettlement.self,
            SavingsAccount.self,
            SavingsLedgerEntry.self,
            ImportMerchantRule.self,
            AssistantAliasRule.self,
            MarinaChatSession.self,
            IncomeSeries.self,
            Income.self
        ])

        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: config)
        retainedContainers.append(container)
        return ModelContext(container)
    }

    @Test func ensureActiveSession_createsWorkspaceScopedEmptySession() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        context.insert(workspace)
        try context.save()

        let store = MarinaChatSessionStore()
        let session = try store.ensureActiveSession(
            for: workspace,
            modelContext: context,
            now: date(2026, 6, 1)
        )

        #expect(session.workspace?.id == workspace.id)
        #expect(session.title == MarinaChatSessionStore.defaultTitle)
        #expect(store.visibleAnswers(for: session).isEmpty)
        #expect(session.followUpContextData.isEmpty)
        #expect(try store.sessions(workspaceID: workspace.id, modelContext: context).count == 1)
    }

    @Test func saveTranscript_generatesTitleWithoutSemanticFollowUpState() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        context.insert(workspace)
        try context.save()

        let store = MarinaChatSessionStore()
        let session = try store.createSession(workspace: workspace, modelContext: context)
        let answer = HomeAnswer(
            queryID: UUID(),
            kind: .metric,
            userPrompt: "What is my safe spend today?",
            title: "Safe Spend Today",
            primaryValue: "$42.00"
        )

        try store.saveTranscript(
            [answer],
            sessionID: session.id,
            workspaceID: workspace.id,
            modelContext: context,
            now: date(2026, 6, 2)
        )

        #expect(session.title == "What is my safe spend today?")
        #expect(store.visibleAnswers(for: session).first?.userPrompt == "What is my safe spend today?")
        #expect(session.followUpContextData.isEmpty)
    }

    @Test func saveTranscript_preservesFullHistoryAndLegacyStateWithoutInterpretingIt() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        context.insert(workspace)
        let store = MarinaChatSessionStore()
        let session = try store.createSession(workspace: workspace, modelContext: context)
        let legacyState = Data("opaque legacy semantic state".utf8)
        session.followUpContextData = legacyState
        let answers = (0..<75).map { index in
            HomeAnswer(queryID: UUID(), kind: .message, userPrompt: "Question \(index)", title: "Answer \(index)")
        }

        try store.saveTranscript(answers, sessionID: session.id, workspaceID: workspace.id, modelContext: context)

        #expect(store.visibleAnswers(for: session) == answers)
        #expect(session.followUpContextData == legacyState)
    }

    @Test func saveTranscript_cannotWriteAnotherWorkspaceSession() throws {
        let context = try makeContext()
        let personal = Workspace(name: "Personal", hexColor: "#3B82F6")
        let work = Workspace(name: "Work", hexColor: "#3B82F6")
        context.insert(personal)
        context.insert(work)
        let store = MarinaChatSessionStore()
        let session = try store.createSession(workspace: personal, modelContext: context)
        let answer = HomeAnswer(queryID: UUID(), kind: .message, title: "Private answer")

        try store.saveTranscript([answer], sessionID: session.id, workspaceID: work.id, modelContext: context)

        #expect(store.visibleAnswers(for: session).isEmpty)
    }

    @Test func memory_roundTripsOnlyWithinItsWorkspaceAndChat() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        context.insert(workspace)
        let store = MarinaChatSessionStore()
        let session = try store.createSession(workspace: workspace, modelContext: context)
        let otherChat = try store.createSession(workspace: workspace, modelContext: context)
        let answer = HomeAnswer(queryID: UUID(), kind: .message, userPrompt: "This month?", title: "Spending")
        var memory = MarinaConversationMemory(workspaceID: workspace.id, chatID: session.id)
        memory.record(request: .init(relativePeriod: .currentMonth, tool: .expenses), result: .init(scope: "Personal"), answerID: answer.id)

        try store.saveTranscript([answer], sessionID: session.id, workspaceID: workspace.id, modelContext: context, memory: memory)
        #expect(store.memory(for: session) == memory)
        #expect(store.visibleAnswers(for: session) == [answer])
        try store.saveTranscript([], sessionID: otherChat.id, workspaceID: workspace.id, modelContext: context, memory: memory)
        #expect(otherChat.followUpContextData.isEmpty)
        otherChat.followUpContextData = session.followUpContextData
        #expect(store.memory(for: otherChat) == nil)

        let foreign = MarinaConversationMemory(workspaceID: UUID(), chatID: session.id)
        try store.saveTranscript([answer], sessionID: session.id, workspaceID: workspace.id, modelContext: context, memory: foreign)
        #expect(store.memory(for: session) == memory)
        session.followUpContextData = try JSONEncoder().encode(foreign)
        #expect(store.memory(for: session) == nil)
    }

    @Test func memory_rejectsMalformedUnknownAndOversizedStateWithoutHidingAnswers() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        context.insert(workspace)
        let store = MarinaChatSessionStore()
        let answers = [HomeAnswer(queryID: UUID(), kind: .message, title: "Saved answer")]
        let session = try store.createSession(workspace: workspace, answers: answers, modelContext: context)
        let memory = MarinaConversationMemory(workspaceID: workspace.id, chatID: session.id)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(memory)) as? [String: Any])
        json["version"] = 999
        let payloads = [
            Data("opaque legacy state".utf8), Data("{".utf8),
            try JSONSerialization.data(withJSONObject: json),
            Data(repeating: 65, count: MarinaConversationMemory.maxStoredBytes + 1)
        ]
        for payload in payloads {
            session.followUpContextData = payload
            #expect(store.memory(for: session) == nil)
            try store.saveTranscript(answers, sessionID: session.id, workspaceID: workspace.id, modelContext: context)
            #expect(session.followUpContextData == payload)
            #expect(store.visibleAnswers(for: session) == answers)
        }
    }

    @Test func clearSession_removesNewMemoryAsWellAsVisibleHistory() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        context.insert(workspace)
        let store = MarinaChatSessionStore()
        let session = try store.createSession(workspace: workspace, modelContext: context)
        let memory = MarinaConversationMemory(workspaceID: workspace.id, chatID: session.id)
        try store.saveTranscript([HomeAnswer(queryID: UUID(), kind: .message, title: "Saved answer")],
                                 sessionID: session.id, workspaceID: workspace.id, modelContext: context, memory: memory)
        #expect(store.memory(for: session) != nil)
        _ = try store.clearSession(id: session.id, workspaceID: workspace.id, modelContext: context)
        #expect(store.memory(for: session) == nil)
        #expect(store.visibleAnswers(for: session).isEmpty)
    }

    @Test func renameAndClear_preservesCustomTitleAndResetsGeneratedTitle() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        context.insert(workspace)
        try context.save()

        let store = MarinaChatSessionStore()
        let custom = try store.createSession(workspace: workspace, modelContext: context)
        _ = try store.renameSession(
            id: custom.id,
            title: "Budget Deep Dive",
            workspaceID: workspace.id,
            modelContext: context
        )
        // Legacy semantic state remains schema-compatible, but the rebuilt chat never reads it.
        custom.followUpContextData = Data("legacy-context".utf8)

        _ = try store.clearSession(id: custom.id, workspaceID: workspace.id, modelContext: context)
        #expect(custom.title == "Budget Deep Dive")
        #expect(store.visibleAnswers(for: custom).isEmpty)
        #expect(custom.followUpContextData.isEmpty)

        let generated = try store.createSession(
            workspace: workspace,
            answers: [
                HomeAnswer(
                    queryID: UUID(),
                    kind: .metric,
                    userPrompt: "Summarize my Apple Card.",
                    title: "Apple Card Spend"
                )
            ],
            modelContext: context
        )

        _ = try store.clearSession(id: generated.id, workspaceID: workspace.id, modelContext: context)
        #expect(generated.title == MarinaChatSessionStore.defaultTitle)
    }

    @Test func deleteSession_selectsNewestRemainingSessionOrCreatesReplacement() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        context.insert(workspace)
        try context.save()

        let store = MarinaChatSessionStore()
        let older = try store.createSession(
            workspace: workspace,
            title: "Older",
            modelContext: context,
            now: date(2026, 6, 1)
        )
        let newer = try store.createSession(
            workspace: workspace,
            title: "Newer",
            modelContext: context,
            now: date(2026, 6, 2)
        )

        let fallback = try store.deleteSession(
            id: newer.id,
            workspace: workspace,
            modelContext: context,
            now: date(2026, 6, 3)
        )
        #expect(fallback.id == older.id)

        let replacement = try store.deleteSession(
            id: older.id,
            workspace: workspace,
            modelContext: context,
            now: date(2026, 6, 4)
        )
        #expect(replacement.id != older.id)
        #expect(replacement.title == MarinaChatSessionStore.defaultTitle)
        #expect(try store.sessions(workspaceID: workspace.id, modelContext: context).count == 1)
    }

    @Test func legacyAnswers_migrateOnceAndDoNotReappearAfterDeletion() throws {
        let suiteName = "MarinaChatSessionStoreTests.legacyMigration"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        context.insert(workspace)
        try context.save()

        let legacyStore = MarinaConversationStore(
            userDefaults: defaults,
            storageKeyPrefix: "tests.marina.legacy"
        )
        legacyStore.saveAnswers([
            HomeAnswer(
                queryID: UUID(),
                kind: .metric,
                userPrompt: "How is income progress?",
                title: "Income Progress"
            )
        ], workspaceID: workspace.id)

        let store = MarinaChatSessionStore(
            userDefaults: defaults,
            legacyConversationStore: legacyStore
        )
        let migrated = try store.ensureActiveSession(for: workspace, modelContext: context)
        #expect(store.visibleAnswers(for: migrated).first?.title == "Income Progress")

        let replacement = try store.deleteSession(
            id: migrated.id,
            workspace: workspace,
            modelContext: context
        )
        #expect(store.visibleAnswers(for: replacement).isEmpty)

        let ensuredAgain = try store.ensureActiveSession(for: workspace, modelContext: context)
        #expect(ensuredAgain.id == replacement.id)
        #expect(store.visibleAnswers(for: ensuredAgain).isEmpty)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
