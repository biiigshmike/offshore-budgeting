import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct MarinaConversationTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Workspace.self, Budget.self, BudgetCategoryLimit.self, Card.self,
            BudgetCardLink.self, BudgetPresetLink.self, Offshore.Category.self,
            Preset.self, PlannedExpense.self, VariableExpense.self,
            AllocationAccount.self, ExpenseAllocation.self, AllocationSettlement.self,
            SavingsAccount.self, SavingsLedgerEntry.self, ImportMerchantRule.self,
            AssistantAliasRule.self, MarinaChatSession.self, IncomeSeries.self, Income.self
        ])
        return try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func controller(_ context: ModelContext, _ workspace: Workspace, _ client: MockClient) -> MarinaConversationController {
        MarinaConversationController(context: context, workspace: workspace,
            startDate: Date(timeIntervalSince1970: 0), endDate: .now, client: client)
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func finish(_ controller: MarinaConversationController) async throws {
        for _ in 0..<200 {
            if !controller.isResponding { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Marina did not finish its deterministic mock response")
    }

    @Test func historyRoundTripPreservesExactResultSnapshotsAndDates() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let date = Date(timeIntervalSince1970: 123456)
        let record = MarinaRecord(id: UUID(), domain: .expenses, title: "Coffee", date: date, amount: 12.5, subtitle: "Visa")
        let result = MarinaResult(id: "result-1", title: "Recorded spending", detail: "Applied range", createdAt: date,
            records: [record], points: [], total: 12.5, count: 1)
        let message = MarinaMessage(role: .assistant, text: "One transaction", date: date, results: [result])
        let data = try JSONEncoder().encode(MarinaHistoryPayload(messages: [message]))
        let restored = try MarinaHistoryPayload.decode(data)
        #expect(restored.messages.first?.id == message.id)
        #expect(restored.messages.first?.date == date)
        #expect(restored.messages.first?.results.first?.records.first?.amount == 12.5)
        #expect(restored.messages.first?.results.first?.createdAt == date)
        let followUp = MarinaFollowUpPayload(summary: "Expenses in September")
        #expect(try MarinaFollowUpPayload.decode(JSONEncoder().encode(followUp)).summary == followUp.summary)
    }

    @Test func unsupportedHistoryVersionsAreRejectedWithoutModifyingBytes() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let original = try JSONEncoder().encode(MarinaHistoryPayload(version: 99, messages: []))
        #expect(throws: MarinaHistoryError.self) { try MarinaHistoryPayload.decode(original) }
        #expect(try JSONDecoder().decode(MarinaHistoryPayload.self, from: original).version == 99)
        let context = try ModelContext(makeContainer())
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        context.insert(workspace)
        let session = MarinaChatSession(title: "Future format", visibleAnswersData: original, workspace: workspace)
        context.insert(session)
        try context.save()
        let subject = controller(context, workspace, MockClient())
        subject.open(session)
        #expect(subject.errorMessage != nil)
        #expect(session.visibleAnswersData == original)
    }

    @Test func unavailableModelKeepsHistoryReadableAndWorkspaceScoped() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = try ModelContext(makeContainer())
        let personal = Workspace(name: "Personal", hexColor: "#123456")
        let work = Workspace(name: "Work", hexColor: "#654321")
        context.insert(personal); context.insert(work)
        let bytes = try JSONEncoder().encode(MarinaHistoryPayload(messages: [MarinaMessage(role: .assistant, text: "Saved answer")]))
        let own = MarinaChatSession(title: "Personal chat", visibleAnswersData: bytes, workspace: personal)
        let other = MarinaChatSession(title: "Work chat", visibleAnswersData: bytes, workspace: work)
        context.insert(own); context.insert(other); try context.save()
        let client = MockClient(); client.availabilityMessage = "Model unavailable"
        let subject = controller(context, personal, client)
        #expect(subject.conversations.map(\.id) == [own.id])
        subject.open(own)
        #expect(subject.messages.last?.text == "Saved answer")
        #expect(subject.availabilityMessage != nil)
        subject.open(other)
        #expect(subject.currentConversationID != other.id)
        subject.delete(other)
        #expect(try context.fetchCount(FetchDescriptor<MarinaChatSession>()) == 2)
    }

    @Test func retryAndContextRecoveryDoNotDuplicateUserMessages() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = try ModelContext(makeContainer())
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        context.insert(workspace)
        try context.save()
        let client = MockClient(); client.failures = [.contextExceeded, .refused]
        let subject = controller(context, workspace, client)
        subject.send("Show my expenses")
        try await finish(subject)
        #expect(client.prompts.count == 2)
        #expect(subject.messages.filter { $0.role == .user }.count == 1)
        #expect(subject.errorMessage != nil)
        subject.retry()
        try await finish(subject)
        #expect(subject.messages.filter { $0.role == .user }.count == 1)
        #expect(subject.messages.filter { $0.role == .assistant }.count == 1)
        #expect(subject.errorMessage == nil)
    }

    @Test func cancellationRejectsLateResponseAfterNewChat() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = try ModelContext(makeContainer())
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        context.insert(workspace)
        try context.save()
        let client = MockClient(); client.holdResponse = true
        let subject = controller(context, workspace, client)
        subject.send("Show my expenses")
        for _ in 0..<100 {
            if client.pending != nil { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(client.pending != nil)
        subject.newConversation()
        client.pending?.resume(returning: MarinaReply(text: "Late answer", resultIDs: []))
        client.pending = nil
        try await Task.sleep(for: .milliseconds(20))
        #expect(subject.messages.isEmpty)
        #expect(!subject.isResponding)
    }

    @Test func responseDeadlineStopsWaitingAndRejectsLateCompletion() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = try ModelContext(makeContainer())
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        context.insert(workspace)
        try context.save()
        let client = MockClient(); client.holdResponse = true
        let subject = MarinaConversationController(context: context, workspace: workspace,
            startDate: Date(timeIntervalSince1970: 0), endDate: .now, client: client,
            responseTimeout: .milliseconds(20))
        subject.send("Find expenses")
        try await finish(subject)
        #expect(!subject.isResponding)
        #expect(subject.errorMessage != nil)
        #expect(subject.messages.count == 1)
        // Release a client that ignores cancellation, even if the deadline assertion fails.
        client.pending?.resume(returning: MarinaReply(text: "Late answer", resultIDs: []))
        client.pending = nil
        await Task.yield()
        #expect(subject.messages.count == 1)
        #expect(subject.messages.first?.role == .user)
    }

    @Test func toolCallLimitStopsNinthInvocationAndResetsForRecovery() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = try ModelContext(makeContainer())
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        context.insert(workspace)
        let queries = MarinaQueryService(context: context, workspaceID: workspace.id,
            startDate: Date(timeIntervalSince1970: 0), endDate: .now)
        for _ in 0..<8 { try queries.beginToolCall() }
        do {
            try queries.beginToolCall()
            Issue.record("A ninth tool call must be rejected")
        } catch MarinaQueryError.toolLimitExceeded { }
        queries.resetResults()
        try queries.beginToolCall()
    }

    @Test func toolAmbiguityOverridesModelNarrativeAndSuppressesCards() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = try ModelContext(makeContainer())
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        context.insert(workspace)
        context.insert(Card(name: "Visa", workspace: workspace))
        context.insert(Card(name: "Visa", workspace: workspace))
        try context.save()
        let client = MockClient(); client.resolveAmbiguousCard = true
        let subject = controller(context, workspace, client)
        subject.send("Show Visa expenses")
        try await finish(subject)
        let answer = try #require(subject.messages.last)
        #expect(answer.role == .assistant)
        #expect(answer.text.contains("Visa"))
        #expect(answer.text.contains("Which"))
        #expect(answer.kind == .clarification)
        #expect(!answer.text.contains("Guess"))
        #expect(answer.results.isEmpty)
    }

    @Test func inventedResultIDsCannotProduceFinancialCards() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = try ModelContext(makeContainer())
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        context.insert(workspace)
        try context.save()
        let client = MockClient(); client.replyIDs = ["invented-card"]
        let subject = controller(context, workspace, client)
        subject.send("What did I spend?")
        try await finish(subject)
        #expect(subject.messages.last?.role == .assistant)
        #expect(subject.messages.last?.results.isEmpty == true)
    }

    @Test func financialAnswerWithoutToolEvidenceIsRejected() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = try ModelContext(makeContainer())
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        context.insert(workspace)
        try context.save()
        let client = MockClient(); client.replyKind = .dataAnswer
        let subject = controller(context, workspace, client)
        subject.send("What did I spend?")
        try await finish(subject)
        #expect(subject.messages.count == 1)
        #expect(subject.messages.first?.role == .user)
        #expect(subject.errorMessage != nil)
    }

    @Test(arguments: [false, true]) func currentToolResultsRemainVisibleWhenModelOmitsOrInventsReferences(inventsReferences: Bool) async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = try ModelContext(makeContainer())
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        context.insert(workspace)
        let card = Card(name: "Visa", workspace: workspace)
        context.insert(card)
        context.insert(VariableExpense(descriptionText: "Coffee", amount: 12, transactionDate: .now, workspace: workspace, card: card))
        try context.save()
        let client = MockClient(); client.queryRecords = true; client.omitReferences = !inventsReferences
        if inventsReferences { client.replyIDs = ["invented-card"] }
        let subject = controller(context, workspace, client)
        subject.send("Find expenses")
        try await finish(subject)
        #expect(subject.messages.last?.results.first?.count == 1)
        #expect(subject.errorMessage == nil)
    }

    @Test func immediateCancellationPreventsClientInvocation() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = try ModelContext(makeContainer())
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        context.insert(workspace)
        try context.save()
        let client = MockClient()
        let subject = controller(context, workspace, client)
        subject.send("Find expenses")
        subject.newConversation()
        await Task.yield()
        #expect(client.prompts.isEmpty)
        #expect(subject.messages.isEmpty)
        #expect(!subject.isResponding)
    }

    @Test func savingConversationDoesNotSavePendingFinancialEdits() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let container = try makeContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let workspace = Workspace(name: "Original", hexColor: "#123456")
        context.insert(workspace)
        try context.save()
        workspace.name = "Pending rename"
        let subject = controller(context, workspace, MockClient())
        subject.send("Hello")
        try await finish(subject)
        #expect(context.hasChanges)
        #expect(workspace.name == "Pending rename")
        let verification = ModelContext(container)
        #expect(try verification.fetch(FetchDescriptor<Workspace>()).first?.name == "Original")
        #expect(try verification.fetchCount(FetchDescriptor<MarinaChatSession>()) == 1)
    }

    @Test func followUpUsesCurrentDataAndPersistedHistory() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = try ModelContext(makeContainer())
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        context.insert(workspace)
        let card = Card(name: "Visa", workspace: workspace); context.insert(card)
        context.insert(VariableExpense(descriptionText: "Coffee", amount: 12, transactionDate: .now, workspace: workspace, card: card))
        try context.save()
        let client = MockClient(); client.queryRecords = true
        let subject = controller(context, workspace, client)
        subject.send("Find expenses")
        try await finish(subject)
        #expect(subject.messages.last?.results.first?.count == 1)
        context.insert(VariableExpense(descriptionText: "Lunch", amount: 20, transactionDate: .now, workspace: workspace, card: card))
        subject.send("Check again")
        try await finish(subject)
        #expect(subject.messages.last?.results.first?.count == 2)
        let sessions = try context.fetch(FetchDescriptor<MarinaChatSession>())
        #expect(sessions.count == 1)
        let reopened = controller(context, workspace, MockClient())
        reopened.open(try #require(sessions.first))
        #expect(reopened.messages.count == 4)
        #expect(reopened.messages.last?.results.first?.count == 2)
    }
}

@available(iOS 26.0, macOS 26.0, *)
@MainActor
private final class MockClient: MarinaLanguageModelClient {
    var availabilityMessage: String?
    var failures: [MarinaModelFailure] = []
    var prompts: [String] = []
    var holdResponse = false
    var replyIDs: [String] = []
    var replyKind: MarinaReplyKind = .conversation
    var omitReferences = false
    var resolveAmbiguousCard = false
    var queryRecords = false
    var pending: CheckedContinuation<MarinaReply, Never>?

    func respond(to prompt: String, instructions: String, queries: MarinaQueryService) async throws -> MarinaReply {
        prompts.append(prompt)
        if !failures.isEmpty { throw failures.removeFirst() }
        if holdResponse { return await withCheckedContinuation { pending = $0 } }
        if resolveAmbiguousCard {
            // Even a later successful query cannot bypass an unresolved entity ambiguity.
            _ = try queries.resolve(MarinaEntityRequest(kind: .card, name: "Visa"))
            _ = try queries.find(MarinaQueryRequest(includeFuture: true))
            return MarinaReply(text: "Guess: use either Visa", resultIDs: queries.results.map(\.id))
        }
        if queryRecords {
            _ = try queries.find(MarinaQueryRequest(includeFuture: true))
            return MarinaReply(text: "Current records", resultIDs: omitReferences ? [] : (replyIDs.isEmpty ? queries.results.map(\.id) : replyIDs), kind: .dataAnswer)
        }
        return MarinaReply(text: "Answer", resultIDs: replyIDs, kind: replyKind)
    }
}
