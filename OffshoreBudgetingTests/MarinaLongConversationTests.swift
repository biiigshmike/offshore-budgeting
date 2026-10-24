import Foundation
import SwiftData
import Testing
#if canImport(UIKit)
import UIKit
#endif
@testable import Offshore

#if canImport(FoundationModels) && DEBUG
/// Run separately from the other native-model suites, on each supported OS/device.
/// These opt-in evaluations test real inference; a skipped run is not a passing evaluation.
@MainActor
@Suite(.serialized)
struct MarinaLongConversationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MARINA_LONG_MODEL_EVALUATION"] == "1",
                   "Set MARINA_LONG_MODEL_EVALUATION=1 on an Apple Intelligence device."))
    func nativeCardDatesAndComparison() async throws {
        try requireAvailableModel()
        let fixture = try Fixture()
        let runtime = makeRuntime(capacity: nil)
        let chatID = UUID()
        var history: [HomeAnswer] = []
        var timings: [Timing] = []
        let current = try await ask("How much did I spend using my Apple Card this month? I mean the card, not the merchant.",
            runtime: runtime, fixture: fixture, chatID: chatID, history: &history, timings: &timings)
        expectCardRequest(runtime, card: fixture.card)
        expectTotal(30, in: current)
        let previous = try await ask("What about last month?", runtime: runtime, fixture: fixture,
            chatID: chatID, history: &history, timings: &timings)
        expectCardRequest(runtime, card: fixture.card)
        expectTotal(100, in: previous)
        let comparison = try await ask("Compare this month's spending on that card with last month.",
            runtime: runtime, fixture: fixture, chatID: chatID, history: &history, timings: &timings)
        #expect(runtime.toolRequests.contains {
            $0.tool == .expenses && $0.cardID == fixture.card.id.uuidString && $0.operation == .comparison
                && ($0.comparisonFilter?.cardID == fixture.card.id.uuidString)
        })
        #expect(comparison.presentations?.contains {
            $0.operation == .comparison && $0.metrics.contains { $0.label == "Total" && $0.value == 30 }
                && $0.metrics.contains { $0.label == "Comparison total" && $0.value == 100 }
        } == true)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MARINA_LONG_MODEL_EVALUATION"] == "1",
                   "Set MARINA_LONG_MODEL_EVALUATION=1 on an Apple Intelligence device."))
    func nativeSelectionsDatesAndClarificationSurviveRestoration() async throws {
        try requireAvailableModel()
        let fixture = try Fixture()
        // Identical names across account domains cannot be resolved by UUID shape or spelling.
        fixture.context.insert(AllocationAccount(name: "Rainy Day", workspace: fixture.workspace))
        let otherSavings = SavingsAccount(name: "Alex", total: 1_000, workspace: fixture.workspace)
        fixture.context.insert(otherSavings)
        fixture.context.insert(SavingsLedgerEntry(date: fixture.today, amount: 1_000, note: "Other account",
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue, workspace: fixture.workspace, account: otherSavings))
        try fixture.context.save()
        var runtime = makeRuntime(capacity: nil)
        let chatID = UUID()
        var history: [HomeAnswer] = []
        var timings: [Timing] = []

        let card = try await ask("How much did I spend using my Apple Card this month? I mean the card, not the merchant.",
            runtime: runtime, fixture: fixture, chatID: chatID, history: &history, timings: &timings)
        expectCardRequest(runtime, card: fixture.card)
        expectTotal(30, in: card)
        let previous = try await ask("What about last month?", runtime: runtime, fixture: fixture,
            chatID: chatID, history: &history, timings: &timings)
        expectCardRequest(runtime, card: fixture.card)
        expectTotal(100, in: previous)
        let biggest = try await ask("Which purchase was biggest in that month on that card?", runtime: runtime,
            fixture: fixture, chatID: chatID, history: &history, timings: &timings)
        expectCardRequest(runtime, card: fixture.card)
        #expect(biggest.presentations?.contains { $0.records.first?.id == fixture.biggest.id.uuidString } == true)

        let allCards = try await ask("How much did I spend this month across all cards?", runtime: runtime,
            fixture: fixture, chatID: chatID, history: &history, timings: &timings)
        let workspaceReads = runtime.toolRequests.filter { $0.tool == .expenses }
        #expect(!workspaceReads.isEmpty && workspaceReads.allSatisfy {
            $0.cardID == nil && $0.categoryID == nil && $0.budgetID == nil && $0.search == nil
        })
        expectTotal(350, in: allCards)
        let clarification = try await ask("How much did I spend at Apple last month?", runtime: runtime, fixture: fixture,
            chatID: chatID, history: &history, timings: &timings)
        #expect(!runtime.toolRequests.contains { $0.tool != .findRecords })
        #expect(clarification.explanation?.contains("“Apple Card” (card)") == true)
        #expect(clarification.explanation?.contains("“Apple” (merchant)") == true)
        let pending = try #require(runtime.memory)
        #expect(pending.pendingClarification != nil)
        runtime = makeRuntime()
        let merchant = try await ask("I mean the merchant, not Apple Card.", runtime: runtime, fixture: fixture,
            chatID: chatID, history: &history, timings: &timings, restoredMemory: pending)
        let merchantReads = runtime.toolRequests.filter { $0.tool == .expenses }
        #expect(!merchantReads.isEmpty && merchantReads.allSatisfy { $0.search == "Apple" && $0.cardID == nil })
        #expect(merchantReads.allSatisfy {
            $0.startDate == fixture.previousStart && $0.endDate == fixture.previousEnd
        })
        expectTotal(37, in: merchant)
        let merchantScope = try #require(merchant.presentations?.first?.scopeLabel)
        #expect(merchant.explanation?.contains(merchantScope) == true)

        let savings = try await ask("What is the current balance in my Rainy Day savings account?", runtime: runtime,
            fixture: fixture, chatID: chatID, history: &history, timings: &timings)
        let savingsReads = runtime.toolRequests.filter { $0.tool == .accounts }
        #expect(!savingsReads.isEmpty && savingsReads.allSatisfy { $0.accountID == fixture.savings.id.uuidString && $0.scope == .savings })
        expectMetric("Rainy Day current balance", value: 150, in: savings)
        let reconciliation = try await ask("What is my current reconciliation balance with Alex?", runtime: runtime,
            fixture: fixture, chatID: chatID, history: &history, timings: &timings)
        let reconciliationReads = runtime.toolRequests.filter { $0.tool == .accounts }
        #expect(!reconciliationReads.isEmpty && reconciliationReads.allSatisfy { $0.accountID == fixture.alex.id.uuidString && $0.scope == .reconciliation })
        expectMetric("Alex current reconciliation balance", value: 25, in: reconciliation)
        #expect(reconciliation.explanation?.contains("Money is owed to you.") == true)
        let allAccounts = try await ask("Show current balances of all my reconciliation accounts.", runtime: runtime,
            fixture: fixture, chatID: chatID, history: &history, timings: &timings)
        let accountReads = runtime.toolRequests.filter { $0.tool == .accounts }
        #expect(!accountReads.isEmpty && accountReads.allSatisfy { $0.accountID == nil && $0.scope == .reconciliation })
        #expect(allAccounts.presentations?.contains {
            $0.metrics.filter { $0.label.hasSuffix("current reconciliation balance") }.count == 10
        } == true)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MARINA_LONG_MODEL_EVALUATION"] == "1",
                   "Set MARINA_LONG_MODEL_EVALUATION=1 on an Apple Intelligence device."))
    func twentyTurnsRetainGroundedContextAcrossRenewals() async throws {
        try requireAvailableModel()
        let fixture = try Fixture()
        // Use the device's reported capacity; the restoration test separately forces a 4K budget.
        let runtime = makeRuntime(capacity: nil)
        let chatID = UUID()
        var history: [HomeAnswer] = []
        var timings: [Timing] = []

        let current = try await ask("How much did I spend using my Apple Card this month? I mean the card, not the merchant.",
            runtime: runtime, fixture: fixture, chatID: chatID, history: &history, timings: &timings)
        expectCardRequest(runtime, card: fixture.card)
        expectTotal(30, in: current)

        let previous = try await ask("What about last month?", runtime: runtime, fixture: fixture,
            chatID: chatID, history: &history, timings: &timings)
        #expect(runtime.toolRequests.contains {
            $0.tool == .expenses && $0.cardID == fixture.card.id.uuidString
                && ($0.relativePeriod == .previousMonth
                    || ($0.startDate == fixture.previousStart && $0.endDate == fixture.previousEnd))
        })
        expectTotal(100, in: previous)

        let biggest = try await ask("Which purchase was biggest in that month on that card?", runtime: runtime,
            fixture: fixture, chatID: chatID, history: &history, timings: &timings)
        expectCardRequest(runtime, card: fixture.card)
        #expect(biggest.presentations?.contains { $0.records.first?.id == fixture.biggest.id.uuidString } == true)

        let list = try await ask("Show me the purchases on that same card this month instead.", runtime: runtime,
            fixture: fixture, chatID: chatID, history: &history, timings: &timings)
        #expect(runtime.toolRequests.contains {
            $0.tool == .expenses && $0.cardID == fixture.card.id.uuidString && $0.operation == .transactions
        })
        #expect(list.presentations?.contains {
            $0.operation == .transactions && $0.records.count == 1 && $0.records.first?.amount == 30
        } == true)

        let comparison = try await ask("Compare this month's spending on that card with last month.",
            runtime: runtime, fixture: fixture, chatID: chatID, history: &history, timings: &timings)
        #expect(runtime.toolRequests.contains {
            $0.tool == .expenses && $0.cardID == fixture.card.id.uuidString && $0.operation == .comparison
                && $0.comparisonFilter?.cardID == fixture.card.id.uuidString
                && ($0.relativePeriod == .currentMonth
                    || ($0.startDate == fixture.currentStart && $0.endDate == fixture.currentEnd))
                && ($0.comparisonPeriod == .previousMonth
                    || ($0.comparisonStartDate == fixture.previousStart && $0.comparisonEndDate == fixture.previousEnd))
        })
        #expect(comparison.presentations?.contains {
            $0.operation == .comparison && $0.metrics.contains { $0.label == "Total" && $0.value == 30 }
                && $0.metrics.contains { $0.label == "Comparison total" && $0.value == 100 }
        } == true)

        let income = try await ask("How much actual income have I received this month across the whole workspace?",
            runtime: runtime, fixture: fixture, chatID: chatID, history: &history, timings: &timings)
        #expect(runtime.toolRequests.contains {
            $0.tool == .income && $0.state == .actual && $0.cardID == nil && $0.comparisonFilter == nil
        })
        expectTotal(500, in: income)

        let plannedIncome = try await ask("And how much income was planned for this month?", runtime: runtime,
            fixture: fixture, chatID: chatID, history: &history, timings: &timings)
        #expect(runtime.toolRequests.contains { $0.tool == .income && $0.state == .planned && $0.cardID == nil })
        expectTotal(800, in: plannedIncome)

        let progress = try await ask("Show my planned-to-actual income progress for that month.", runtime: runtime,
            fixture: fixture, chatID: chatID, history: &history, timings: &timings)
        #expect(progress.presentations?.contains {
            $0.incomeProgress?.actual == 500 && $0.incomeProgress?.planned == 800
        } == true)

        let budget = try await ask("Am I on track with my Monthly budget this month?", runtime: runtime,
            fixture: fixture, chatID: chatID, history: &history, timings: &timings)
        #expect(runtime.toolRequests.contains { $0.tool == .budgetSummary && $0.purpose == .budgetPace })
        #expect(budget.presentations?.contains { $0.budgetPace != nil } == true)

        let workspace = try await ask("How much did I spend this month across all cards?", runtime: runtime,
            fixture: fixture, chatID: chatID, history: &history, timings: &timings)
        #expect(runtime.toolRequests.contains {
            $0.tool == .expenses && $0.operation == .summary && $0.cardID == nil && $0.budgetID == nil
                && $0.categoryID == nil && $0.search == nil
                && ($0.relativePeriod == .currentMonth
                    || ($0.startDate == fixture.currentStart && $0.endDate == fixture.currentEnd))
        })
        expectTotal(350, in: workspace)

        let savings = try await ask("What is the current balance in my Rainy Day savings account?", runtime: runtime,
            fixture: fixture, chatID: chatID, history: &history, timings: &timings)
        #expect(runtime.toolRequests.contains { $0.tool == .accounts && $0.accountID == fixture.savings.id.uuidString })
        expectMetric("Rainy Day current balance", value: 150, in: savings)

        let savingsActivity = try await ask("Show the entries in that savings account this month.", runtime: runtime,
            fixture: fixture, chatID: chatID, history: &history, timings: &timings)
        #expect(runtime.toolRequests.contains {
            $0.tool == .accounts && $0.accountID == fixture.savings.id.uuidString
                && ($0.relativePeriod == .currentMonth
                    || ($0.startDate == fixture.currentStart && $0.endDate == fixture.currentEnd))
        })
        #expect(savingsActivity.presentations?.contains {
            $0.records.count == 2 && $0.records.compactMap(\.amount).sorted() == [-50, 200]
        } == true)
        // Saved answer rows retain activity metrics; the compact visual's metrics show balances.
        #expect(savingsActivity.rows.contains { $0.title == "Selected period activity total" && $0.amount == 150 })

        let reconciliation = try await ask("What is my current reconciliation balance with Alex?", runtime: runtime,
            fixture: fixture, chatID: chatID, history: &history, timings: &timings)
        #expect(runtime.toolRequests.contains { $0.tool == .accounts && $0.accountID == fixture.alex.id.uuidString })
        expectMetric("Alex current reconciliation balance", value: 25, in: reconciliation)

        let allAccounts = try await ask("Show the current balances of all my reconciliation accounts.", runtime: runtime,
            fixture: fixture, chatID: chatID, history: &history, timings: &timings)
        #expect(runtime.toolRequests.contains { $0.tool == .accounts && $0.scope == .reconciliation && $0.accountID == nil })
        // Model-facing facts may be bounded; the saved native presentation must remain complete.
        #expect(allAccounts.presentations?.contains {
            $0.metrics.filter { $0.label.hasSuffix("current reconciliation balance") }.count == 9
        } == true)

        let empty = try await ask("What did I spend in the Hair Care category this month?", runtime: runtime,
            fixture: fixture, chatID: chatID, history: &history, timings: &timings)
        #expect(runtime.toolRequests.contains {
            $0.tool == .expenses && $0.categoryID == fixture.emptyCategory.id.uuidString && $0.cardID == nil
        })
        #expect(empty.presentations?.contains { $0.isEmpty && $0.metrics.contains { $0.value == 0 } } == true)

        let unicode = try await ask("¿Cuánto gasté este mes en la categoría Café 🍵?", runtime: runtime,
            fixture: fixture, chatID: chatID, history: &history, timings: &timings)
        #expect(runtime.toolRequests.contains { $0.tool == .expenses && $0.categoryID == fixture.unicodeCategory.id.uuidString })
        expectTotal(10, in: unicode)

        _ = try await ask("How much did I spend at Apple this month?", runtime: runtime,
            fixture: fixture, chatID: chatID, history: &history, timings: &timings)
        #expect(runtime.toolRequests.contains { $0.tool == .findRecords })
        #expect(!runtime.toolRequests.contains { $0.tool == .expenses })

        let clarified = try await ask("I mean the merchant, not Apple Card.", runtime: runtime,
            fixture: fixture, chatID: chatID, history: &history, timings: &timings)
        #expect(runtime.toolRequests.contains { $0.tool == .expenses && $0.search == "Apple" && $0.cardID == nil })
        expectTotal(200, in: clarified)

        let fresh = VariableExpense(descriptionText: "New grocery purchase", amount: 15,
            transactionDate: fixture.today, workspace: fixture.workspace, card: fixture.card)
        fixture.context.insert(fresh)
        try fixture.context.save()
        let refreshed = try await ask("I just added a purchase. What is my Apple Card spending total this month now?",
            runtime: runtime, fixture: fixture, chatID: chatID, history: &history, timings: &timings)
        expectCardRequest(runtime, card: fixture.card)
        expectTotal(45, in: refreshed)

        let refreshedList = try await ask("Show the purchases behind that total.", runtime: runtime,
            fixture: fixture, chatID: chatID, history: &history, timings: &timings)
        #expect(runtime.toolRequests.contains {
            $0.tool == .expenses && $0.cardID == fixture.card.id.uuidString && $0.operation == .transactions
        })
        #expect(refreshedList.presentations?.contains { $0.records.contains { $0.id == fresh.id.uuidString } } == true)

        #expect(history.count == 20)
        #expect(Set(history.map(\.id)).count == 20)
        #expect(history.first == current)
        #expect(runtime.renewalCount >= 2)
        #expect(runtime.contextBoundaryRenewalCount >= 2)
        #expect(timings.contains { $0.phase == "warm" })
        #expect(timings.filter { $0.phase == "post-renewal" }.count >= 2)
        #expect(history.allSatisfy { $0.responseState == .complete && $0.contextStatus != .reached })
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MARINA_LONG_MODEL_EVALUATION"] == "1",
                   "Set MARINA_LONG_MODEL_EVALUATION=1 on an Apple Intelligence device."))
    func savedChatRestoresMemoryAndReadsFreshFacts() async throws {
        try requireAvailableModel()
        let fixture = try Fixture()
        let suiteName = "MarinaLongConversationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = MarinaChatSessionStore(userDefaults: defaults)
        let session = try store.createSession(workspace: fixture.workspace, modelContext: fixture.context)
        let runtime = makeRuntime()
        var history: [HomeAnswer] = []
        var timings: [Timing] = []
        _ = try await ask("What did I spend using my Apple Card this month? I mean the card.", runtime: runtime,
            fixture: fixture, chatID: session.id, history: &history, timings: &timings)
        _ = try await ask("And last month?", runtime: runtime, fixture: fixture, chatID: session.id,
            history: &history, timings: &timings)
        let memory = try #require(runtime.memory)
        try store.saveTranscript(history, sessionID: session.id, workspaceID: fixture.workspace.id,
            modelContext: fixture.context, memory: memory)
        #expect(!session.followUpContextData.isEmpty)

        // A second context forces the test through persisted transcript and memory decoding.
        let reopenedContext = ModelContext(fixture.container)
        let reopenedStore = MarinaChatSessionStore(userDefaults: defaults)
        let reopenedSession = try #require(reopenedStore.sessions(workspaceID: fixture.workspace.id,
            modelContext: reopenedContext).first { $0.id == session.id })
        let restoredMemory = try #require(reopenedStore.memory(for: reopenedSession))
        var restoredHistory = reopenedStore.visibleAnswers(for: reopenedSession)
        #expect(restoredHistory == history)

        let addition = VariableExpense(descriptionText: "Late recorded previous-month purchase", amount: 120,
            transactionDate: fixture.previousDay, workspace: fixture.workspace, card: fixture.card)
        fixture.context.insert(addition)
        try fixture.context.save()
        let reopened = makeRuntime()
        let largest = try await ask("Which purchase was biggest in that month on that card?", runtime: reopened,
            fixture: fixture, chatID: session.id, history: &restoredHistory, timings: &timings,
            restoredMemory: restoredMemory)
        expectCardRequest(reopened, card: fixture.card)
        #expect(largest.presentations?.contains { $0.records.first?.id == addition.id.uuidString } == true)
        #expect(restoredHistory.count == 3)
        #expect(Array(restoredHistory.prefix(2)) == history)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MARINA_LONG_MODEL_EVALUATION"] == "1",
                   "Set MARINA_LONG_MODEL_EVALUATION=1 on an Apple Intelligence device."))
    func oversizedPromptDoesNotLockTheChat() async throws {
        try requireAvailableModel()
        let fixture = try Fixture()
        let runtime = makeRuntime()
        let chatID = UUID()
        let oversizedID = UUID()
        let prompt = String(repeating: "Please consider this extra context. ", count: 4096)
        var latest: HomeAnswer?
        var identifiers: Set<UUID> = []
        await runtime.respond(prompt: prompt, history: [], workspace: fixture.workspace,
            modelContext: fixture.context, homeContext: nil, defaultBudgetingPeriod: .monthly,
            answerID: oversizedID, chatID: chatID) { answer in
                latest = answer
                identifiers.insert(answer.id)
            }
        let oversized = try #require(latest)
        #expect(identifiers == [oversizedID])
        #expect(oversized.responseState == .contextLimit)
        #expect(runtime.toolRequests.isEmpty)

        // Keep the failed prompt in visible history, as the app does. The next request must still work.
        var history = [oversized]
        var timings: [Timing] = []
        let recovered = try await ask("Which workspace am I using?", runtime: runtime, fixture: fixture,
            chatID: chatID, history: &history, timings: &timings)
        #expect(recovered.responseState == .complete)
        #expect(history.count == 2)
        #expect(history.first == oversized)
        #expect(runtime.memory?.workspaceID == fixture.workspace.id)
        #expect(runtime.memory?.chatID == chatID)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MARINA_LONG_MODEL_EVALUATION"] == "1",
                   "Set MARINA_LONG_MODEL_EVALUATION=1 on an Apple Intelligence device."))
    func cancellingAnActiveResponseAllowsRetryWithTheSameAnswerIdentity() async throws {
        try requireAvailableModel()
        let fixture = try Fixture()
        let runtime = makeRuntime()
        let chatID = UUID()
        let answerID = UUID()
        let prompt = "Which workspace am I using? Explain briefly how workspace boundaries affect my records."
        var activeTask: Task<Void, Never>?
        var didCancel = false
        var identifiers: Set<UUID> = []
        var callbacksAfterCancellation = 0
        var latest: HomeAnswer?
        activeTask = Task { @MainActor in
            await runtime.respond(prompt: prompt, history: [], workspace: fixture.workspace,
                modelContext: fixture.context, homeContext: nil, defaultBudgetingPeriod: .monthly,
                answerID: answerID, chatID: chatID) { answer in
                    if didCancel { callbacksAfterCancellation += 1 }
                    latest = answer
                    identifiers.insert(answer.id)
                    // Wait for actual streamed text, rather than cancelling during initial preparation.
                    if !didCancel, answer.responseState == .responding, answer.explanation?.isEmpty == false {
                        didCancel = true
                        activeTask?.cancel()
                    }
                }
        }
        await activeTask?.value
        try #require(didCancel, "The evaluation must cancel active streamed generation.")
        #expect(callbacksAfterCancellation == 0)
        #expect(identifiers == [answerID])
        #expect(latest?.responseState != .complete)

        var retryIDs: Set<UUID> = []
        var retry: HomeAnswer?
        await runtime.respond(prompt: prompt, history: [], workspace: fixture.workspace,
            modelContext: fixture.context, homeContext: nil, defaultBudgetingPeriod: .monthly,
            answerID: answerID, chatID: chatID) { answer in
                retry = answer
                retryIDs.insert(answer.id)
            }
        #expect(retryIDs == [answerID])
        #expect(retry?.responseState == .complete)
        #expect(retry?.contextStatus != .reached)
        #expect(runtime.lastErrorDescription == nil)
        #expect(runtime.memory?.chatID == chatID)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MARINA_LONG_MODEL_EVALUATION"] == "1",
                   "Set MARINA_LONG_MODEL_EVALUATION=1 on an Apple Intelligence device."))
    func rapidPreparationAndResponseSwitchesDoNotLeakCallbacksOrMemory() async throws {
        try requireAvailableModel()
        let original = try Fixture()
        let otherWorkspace = try Fixture()
        // Exercise a new chat in the same workspace, then a new chat in a different workspace.
        for destination in [original, otherWorkspace] {
            let controller = MarinaConversationController()
            let previousChatID = UUID()
            let nextChatID = UUID()
            var previousMemory = MarinaConversationMemory(workspaceID: original.workspace.id, chatID: previousChatID)
            let service = MarinaReadOnlyDataService(workspace: original.workspace, modelContext: original.context)
            let lookup = MarinaDataRequest(tool: .findRecords, search: "Checking")
            let result = try service.execute(lookup)
            previousMemory.record(request: lookup, result: result, answerID: UUID())
            try #require(!previousMemory.confirmedEntities.isEmpty)

            controller.prepare(history: [], workspace: original.workspace, homeContext: nil,
                defaultBudgetingPeriod: .monthly, chatID: previousChatID, restoredMemory: previousMemory)
            var switched = false
            var obsoleteCallbacks = 0
            let departing = Task { @MainActor in
                await controller.respond(prompt: "Which workspace am I using?", history: [],
                    workspace: original.workspace, modelContext: original.context, homeContext: nil,
                    defaultBudgetingPeriod: .monthly, chatID: previousChatID,
                    restoredMemory: previousMemory) { _ in
                        if switched { obsoleteCallbacks += 1 }
                    }
            }
            // Let preparation and response reach their first suspension, then switch immediately.
            await Task.yield()
            switched = true
            departing.cancel()
            controller.reset()
            controller.prepare(history: [], workspace: destination.workspace, homeContext: nil,
                defaultBudgetingPeriod: .monthly, chatID: nextChatID, restoredMemory: nil)
            let nextAnswerID = UUID()
            var nextAnswer: HomeAnswer?
            var nextIDs: Set<UUID> = []
            let entering = Task { @MainActor in
                await controller.respond(prompt: "Which workspace am I using?", answerID: nextAnswerID,
                    history: [], workspace: destination.workspace, modelContext: destination.context,
                    homeContext: nil, defaultBudgetingPeriod: .monthly, chatID: nextChatID) { answer in
                        nextAnswer = answer
                        nextIDs.insert(answer.id)
                    }
            }
            await departing.value
            await entering.value
            #expect(obsoleteCallbacks == 0)
            #expect(nextIDs == [nextAnswerID])
            #expect(nextAnswer?.responseState == .complete)
            #expect(!controller.isResponding)
            let memory = try #require(controller.memory)
            #expect(memory.workspaceID == destination.workspace.id)
            #expect(memory.chatID == nextChatID)
            #expect(memory.pendingClarification == nil)
            #expect(!memory.confirmedEntities.contains { entity in
                previousMemory.confirmedEntities.contains { $0.id == entity.id }
            })
            controller.reset()
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MARINA_LONG_MODEL_EVALUATION"] == "1",
                   "Set MARINA_LONG_MODEL_EVALUATION=1 on an Apple Intelligence device."))
    func faultInjectedOverflowsRetryOnceWithoutDuplicatingAnswersOrKeepingStaleVisuals() async throws {
        try requireAvailableModel()
        let fixture = try Fixture()
        for injected in [1, 2] {
            // This exercises the real runtime catch/retry path after a real financial read.
            // The error is deliberately injected; this is not evidence of device-capacity overflow.
            let runtime = makeRuntime(injectedContextOverflowsAfterRead: injected)
            let chatID = UUID()
            let answerID = UUID()
            var snapshots: [HomeAnswer] = []
            await runtime.respond(
                prompt: "How much actual income have I received this month across the whole workspace?",
                history: [], workspace: fixture.workspace, modelContext: fixture.context,
                homeContext: nil, defaultBudgetingPeriod: .monthly, answerID: answerID, chatID: chatID
            ) { snapshots.append($0) }

            let final = try #require(snapshots.last)
            if runtime.injectedContextOverflowCount != injected {
                print("MarinaFaultInjectedSetup expected=\(injected) actual=\(runtime.injectedContextOverflowCount) state=\(final.responseState?.rawValue ?? "none") error=\(runtime.lastErrorDescription ?? "none") tools=\(runtime.toolRequests.map { $0.tool.rawValue }) caption=\(final.explanation ?? "")")
                // This opt-in evaluation uses synthetic fixtures, never the user's workspace.
                print("MarinaFaultInjectedRequests \(String(decoding: try JSONEncoder().encode(runtime.toolRequests), as: UTF8.self))")
                print("MarinaFaultInjectedNotices \(final.rows.filter { $0.role == .assumption }.map(\.title))")
                print("MarinaFaultInjectedCalls \(runtime.diagnosticFailedToolCalls)")
            }
            #expect(Set(snapshots.map(\.id)) == [answerID])
            #expect(runtime.injectedContextOverflowCount == injected)
            let recoveries = snapshots.filter { $0.responseState == .recovering }
            #expect(recoveries.count == 1, "The runtime may retry an overflow only once.")
            let recoveryIndex = try #require(snapshots.firstIndex { $0.responseState == .recovering })
            #expect(snapshots.prefix(recoveryIndex).contains { answer in
                answer.rows.contains { $0.title == "Total" && $0.amount == 500 }
                    && answer.presentations?.isEmpty == false
            }, "Fault injection must happen after verified facts and a visual were published.")
            let retryThinking = try #require(snapshots.dropFirst(recoveryIndex + 1).first {
                $0.responseState == .thinking
            })
            #expect(retryThinking.presentations?.isEmpty != false)
            #expect(retryThinking.suppressedPresentationIDs?.isEmpty != false)
            #expect(retryThinking.rows.isEmpty)

            if injected == 1 {
                #expect(final.responseState == .complete)
                #expect(runtime.lastErrorDescription == nil)
                expectTotal(500, in: final)
                let presentations = try #require(final.presentations)
                #expect(presentations.count == 1)
                #expect(Set(presentations.map(\.id)).count == presentations.count)
                #expect(!snapshots.contains { $0.responseState == .contextLimit })
            } else {
                #expect(final.responseState == .contextLimit)
                #expect(runtime.lastErrorDescription != nil)
                var history = [final]
                var timings: [Timing] = []
                let next = try await ask("Which workspace am I using?", runtime: runtime,
                    fixture: fixture, chatID: chatID, history: &history, timings: &timings)
                #expect(next.responseState == .complete)
                #expect(history.count == 2)
                #expect(history.first == final)
                #expect(runtime.injectedContextOverflowCount == 2)
                #expect(runtime.memory?.chatID == chatID)
            }
            print("MarinaFaultInjectedOverflow injected_count=\(injected) recovery_count=\(recoveries.count) terminal_state=\(final.responseState?.rawValue ?? "none")")
        }
    }

    private func makeRuntime(capacity: Int? = 4096, injectedContextOverflowsAfterRead: Int = 0) -> MarinaConversationRuntime {
        let useDynamicProfile = ProcessInfo.processInfo.environment["MARINA_LONG_STATIC_SESSION"] != "1"
        return MarinaConversationRuntime(contextCapacityOverride: capacity, useDynamicProfile: useDynamicProfile,
            injectedContextOverflowsAfterRead: injectedContextOverflowsAfterRead)
    }

    private func requireAvailableModel() throws {
        if let reason = MarinaConversationRuntime.availabilityMessage { throw EvaluationError.unavailable(reason) }
    }

    private func ask(_ prompt: String, runtime: MarinaConversationRuntime, fixture: Fixture, chatID: UUID,
                     history: inout [HomeAnswer], timings: inout [Timing],
                     restoredMemory: MarinaConversationMemory? = nil) async throws -> HomeAnswer {
        let started = ContinuousClock.now
        let answerID = UUID()
        let originalHistory = history
        var latest: HomeAnswer?
        var streamedIDs: Set<UUID> = []
        var sawContextLimit = false
        var firstText: Duration?
        await runtime.respond(prompt: prompt, history: history, workspace: fixture.workspace,
            modelContext: fixture.context, homeContext: nil, defaultBudgetingPeriod: .monthly,
            answerID: answerID, chatID: chatID, restoredMemory: restoredMemory) { answer in
                latest = answer
                streamedIDs.insert(answer.id)
                sawContextLimit = sawContextLimit || answer.responseState == .contextLimit
                if firstText == nil, answer.explanation?.isEmpty == false { firstText = started.duration(to: .now) }
            }
        let phase = runtime.lastTurnContextPhase
        let timing = Timing(phase: phase, firstText: firstText, total: started.duration(to: .now))
        timings.append(timing)
        report(timing, turn: history.count + 1, renewals: runtime.renewalCount,
               contextBoundaryRenewals: runtime.contextBoundaryRenewalCount)
        let answer = try #require(latest)
        if ProcessInfo.processInfo.environment["MARINA_LONG_EVALUATION_VERBOSE"] == "1" {
            // Opt-in debugging for this synthetic, in-memory fixture only. Never use in app diagnostics.
            let calls = runtime.toolRequests.map { $0.tool.rawValue + ":" + $0.operation.rawValue }.joined(separator: ",")
            print("MarinaLongSynthetic turn=\(history.count + 1) calls=\(calls) explanation=\(String((answer.explanation ?? "").prefix(2000)))")
            if let error = runtime.lastErrorDescription { print("MarinaLongSynthetic error=\(error)") }
            if answer.responseState != .complete { print("MarinaLongSynthetic failed_calls=\(runtime.diagnosticFailedToolCalls)") }
            print("MarinaLongSynthetic notices=\(answer.rows.filter { $0.role == .assumption }.map(\.title))")
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            for request in runtime.toolRequests {
                let data = try encoder.encode(request)
                print("MarinaLongSynthetic request=\(String(decoding: data, as: UTF8.self))")
            }
            print("MarinaLongSynthetic retained_memory=\(runtime.diagnosticRetainedMemory)")
        }
        #expect(!sawContextLimit)
        #expect(streamedIDs == [answerID])
        #expect(history == originalHistory)
        // Continue subsequent turns after a failure to evaluate endurance. These
        // expectations still fail the suite; a completed script is not an accuracy pass.
        #expect(runtime.lastErrorDescription == nil, "Native model failed; inspect categorized runtime diagnostics.")
        #expect(answer.responseState == .complete, "Native model did not finish this evaluation turn.")
        #expect(answer.contextStatus != .reached)
        #expect(firstText != nil)
        // An unrelated workspace carries a sentinel transaction that must never enter any result.
        #expect(answer.presentations?.allSatisfy { presentation in
            !presentation.records.contains { $0.id == fixture.foreignExpense.id.uuidString }
                && !presentation.metrics.contains { $0.value >= 900_000 }
        } != false)
        history.append(answer)
        return answer
    }

    private func expectCardRequest(_ runtime: MarinaConversationRuntime, card: Card) {
        let expenses = runtime.toolRequests.filter { $0.tool == .expenses }
        #expect(!expenses.isEmpty)
        #expect(expenses.allSatisfy { $0.cardID == card.id.uuidString && $0.search == nil && $0.categoryID == nil })
    }

    private func expectTotal(_ value: Double, in answer: HomeAnswer) {
        #expect(answer.rows.contains { $0.title == "Total" && $0.amount == value })
    }

    private func expectMetric(_ label: String, value: Double, in answer: HomeAnswer) {
        #expect(answer.presentations?.contains { $0.metrics.contains { $0.label == label && $0.value == value } } == true)
    }

    private func report(_ timing: Timing, turn: Int, renewals: Int, contextBoundaryRenewals: Int) {
        #if targetEnvironment(macCatalyst)
        let platform = "macCatalyst"
        #elseif targetEnvironment(simulator)
        let platform = "simulator"
        #else
        let platform = "device"
        #endif
        #if canImport(UIKit)
        let device = UIDevice.current.model
        #else
        let device = "Mac"
        #endif
        func seconds(_ duration: Duration) -> String {
            let parts = duration.components
            return (Double(parts.seconds) + Double(parts.attoseconds) / 1e18)
                .formatted(.number.precision(.fractionLength(3)))
        }
        // Visible text may now be a verified caption published before model narration.
        // Deliberately omit prompts, names, IDs, tool payloads, and financial values.
        print("MarinaLongEvaluation os=\(ProcessInfo.processInfo.operatingSystemVersionString) platform=\(platform) device=\(device) turn=\(turn) phase=\(timing.phase) first_visible_text_s=\(timing.firstText.map(seconds) ?? "none") total_s=\(seconds(timing.total)) renewals=\(renewals) context_boundary_renewals=\(contextBoundaryRenewals)")
    }

    private struct Timing {
        let phase: String
        let firstText: Duration?
        let total: Duration
    }

    private enum EvaluationError: Error { case unavailable(String) }

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let workspace: Workspace
        let card: Card
        let biggest: VariableExpense
        let savings: SavingsAccount
        let alex: AllocationAccount
        let emptyCategory: Offshore.Category
        let unicodeCategory: Offshore.Category
        let foreignExpense: VariableExpense
        let today: Date
        let previousDay: Date
        let currentStart: String
        let currentEnd: String
        let previousStart: String
        let previousEnd: String

        init() throws {
            let schema = Schema([Workspace.self, Budget.self, BudgetCategoryLimit.self, Card.self,
                BudgetCardLink.self, BudgetPresetLink.self, Offshore.Category.self, Preset.self,
                PlannedExpense.self, VariableExpense.self, AllocationAccount.self, ExpenseAllocation.self,
                AllocationSettlement.self, SavingsAccount.self, SavingsLedgerEntry.self, ImportMerchantRule.self,
                AssistantAliasRule.self, MarinaChatSession.self, IncomeSeries.self, Income.self])
            container = try ModelContainer(for: schema, configurations: ModelConfiguration(
                "MarinaLongFixture-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
            context = ModelContext(container)
            let calendar = Calendar.current
            today = calendar.startOfDay(for: .now)
            let month = try #require(calendar.dateInterval(of: .month, for: today))
            previousDay = try #require(calendar.date(byAdding: .day, value: -1, to: month.start))
            let previousMonth = try #require(calendar.dateInterval(of: .month, for: previousDay))
            let style = Date.ISO8601FormatStyle(timeZone: calendar.timeZone).year().month().day().dateSeparator(.dash)
            currentStart = month.start.formatted(style)
            currentEnd = month.end.addingTimeInterval(-1).formatted(style)
            previousStart = previousMonth.start.formatted(style)
            previousEnd = previousDay.formatted(style)
            workspace = Workspace(name: "Conversation Evaluation", hexColor: "#3B82F6")
            card = Card(name: "Apple Card", workspace: workspace)
            let checking = Card(name: "Checking", workspace: workspace)
            emptyCategory = Offshore.Category(name: "Hair Care", hexColor: "#FF0000", workspace: workspace)
            unicodeCategory = Offshore.Category(name: "Café 🍵", hexColor: "#00FF00", workspace: workspace)
            biggest = VariableExpense(descriptionText: "Largest grocery purchase", amount: 70,
                transactionDate: previousDay, workspace: workspace, card: card)
            savings = SavingsAccount(name: "Rainy Day", total: 150, workspace: workspace)
            alex = AllocationAccount(name: "Alex", workspace: workspace)
            let otherWorkspace = Workspace(name: "Other Workspace", hexColor: "#654321")
            let otherCard = Card(name: "Apple Card", workspace: otherWorkspace)
            foreignExpense = VariableExpense(descriptionText: "Foreign sentinel", amount: 900_001,
                transactionDate: today, workspace: otherWorkspace, card: otherCard)
            context.insert(workspace)
            context.insert(card)
            context.insert(checking)
            context.insert(emptyCategory)
            context.insert(unicodeCategory)
            context.insert(biggest)
            context.insert(savings)
            context.insert(alex)
            context.insert(otherWorkspace)
            context.insert(otherCard)
            context.insert(foreignExpense)
            context.insert(VariableExpense(descriptionText: "Small grocery purchase", amount: 30,
                transactionDate: previousDay, workspace: workspace, card: card))
            context.insert(VariableExpense(descriptionText: "Coffee", amount: 30,
                transactionDate: today, workspace: workspace, card: card))
            context.insert(VariableExpense(descriptionText: "Apple", amount: 200,
                transactionDate: today, workspace: workspace, card: checking))
            // Wrong card/date selections must yield different answers in both periods.
            context.insert(VariableExpense(descriptionText: "Other card previous purchase", amount: 1_000,
                transactionDate: previousDay, workspace: workspace, card: checking))
            context.insert(VariableExpense(descriptionText: "Apple", amount: 37,
                transactionDate: previousDay, workspace: workspace, card: checking))
            context.insert(VariableExpense(descriptionText: "Espresso", amount: 10,
                transactionDate: today, workspace: workspace, card: checking, category: unicodeCategory))
            context.insert(Income(source: "Paycheck", amount: 500, date: today, isPlanned: false,
                workspace: workspace, card: checking))
            context.insert(Income(source: "Paycheck", amount: 800, date: today, isPlanned: true,
                workspace: workspace, card: checking))
            let budget = Budget(name: "Monthly", startDate: month.start,
                endDate: month.end.addingTimeInterval(-1), workspace: workspace)
            context.insert(budget)
            context.insert(BudgetCardLink(budget: budget, card: card))
            context.insert(BudgetCardLink(budget: budget, card: checking))
            context.insert(PlannedExpense(title: "Subscription", plannedAmount: 20, expenseDate: today,
                workspace: workspace, card: checking, sourceBudgetID: budget.id))
            for amount in [200.0, -50.0] {
                context.insert(SavingsLedgerEntry(date: today, amount: amount, note: "Fixture adjustment",
                    kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue, workspace: workspace, account: savings))
            }
            for amount in [5.0, -5.0] {
                context.insert(SavingsLedgerEntry(date: previousDay, amount: amount, note: "Prior-period adjustment",
                    kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue, workspace: workspace, account: savings))
            }
            let shared = VariableExpense(descriptionText: "Shared groceries", amount: 90,
                transactionDate: today, workspace: workspace, card: checking)
            context.insert(shared)
            context.insert(ExpenseAllocation(allocatedAmount: 40, workspace: workspace, account: alex, expense: shared))
            context.insert(AllocationSettlement(date: today, note: "Fixture payment", amount: -15,
                workspace: workspace, account: alex))
            for index in 1...8 {
                context.insert(AllocationAccount(name: "Shared account \(index)", workspace: workspace))
            }
            try context.save()
        }
    }
}
#endif
