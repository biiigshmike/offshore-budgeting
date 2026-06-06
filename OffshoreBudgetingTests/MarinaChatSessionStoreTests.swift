import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct MarinaChatSessionStoreTests {
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

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
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
        #expect(store.followUpContext(for: session) == .empty)
        #expect(try store.sessions(workspaceID: workspace.id, modelContext: context).count == 1)
    }

    @Test func saveTranscript_generatesTitleAndPersistsSeparateFollowUpContext() throws {
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

        let savedContext = try store.saveTranscript(
            [answer],
            sessionID: session.id,
            workspaceID: workspace.id,
            modelContext: context,
            now: date(2026, 6, 2)
        )

        #expect(session.title == "What is my safe spend today?")
        #expect(store.visibleAnswers(for: session).first?.userPrompt == "What is my safe spend today?")
        #expect(store.followUpContext(for: session) == savedContext)
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
        _ = try store.saveFollowUpContext(
            MarinaConversationContext(recentTurns: [
                MarinaConversationTurn(
                    title: "Apple Card Spend",
                    kind: .metric,
                    subtitle: nil,
                    primaryValue: "$100.00",
                    rowTitles: [],
                    semanticContext: nil,
                    recommendedFollowUp: nil
                )
            ]),
            sessionID: custom.id,
            workspaceID: workspace.id,
            modelContext: context
        )

        _ = try store.clearSession(id: custom.id, workspaceID: workspace.id, modelContext: context)
        #expect(custom.title == "Budget Deep Dive")
        #expect(store.visibleAnswers(for: custom).isEmpty)
        #expect(store.followUpContext(for: custom) == .empty)

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
