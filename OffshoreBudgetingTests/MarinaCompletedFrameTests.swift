import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaCompletedFrameTests {
    @Test func compiledUnknownNameCreatesDurablePendingIntentWithoutCandidatesOrLegacyRecording() throws {
        var memory = MarinaConversationMemory(workspaceID: UUID(), chatID: UUID())
        var request = MarinaDataRequest(operation: .transactions, tool: .expenses,
            startDate: "2026-06-01", endDate: "2026-06-30", cardID: UUID().uuidString,
            sort: .smallest, limit: 1)
        request.metric = .total; request.expenseMeasure = .spending; request.positiveOnly = true
        let compilation = MarinaRequestCompiler.Compilation(capability: .smallestExpense, request: request,
            dateOrigin: .explicit, unresolvedTargets: [
                .init(id: "merchant", field: .merchant, name: "Unlisted Market", isComparison: false,
                      source: .userText("Unlisted Market"))
            ])
        let rootQuestion = "Smallest Unlisted Market expense on this card in June?"
        let accepted = memory.saveCompiledClarification(compilation: compilation,
            result: .init(status: "empty", scope: "Personal"), answerID: UUID(),
            prompt: rootQuestion, search: "Unlisted Market")
        #expect(accepted)
        memory = try JSONDecoder().decode(MarinaConversationMemory.self, from: JSONEncoder().encode(memory))
        #expect(memory.pendingClarification?.candidates.isEmpty == true)
        #expect(memory.pendingClarification?.reason == "empty")
        #expect(memory.pendingClarification?.originatingPrompt == rootQuestion)
        #expect(memory.pendingClarification?.pendingRequest == request)
        #expect(memory.pendingClarification?.period?.startDate == "2026-06-01")
        #expect(memory.pendingClarification?.compilation == compilation)
        #expect(memory.pendingClarification?.dateOrigin == .explicit)
        #expect(memory.latestCompletedFrame == nil)
    }

    @Test func compiledClarificationPreservesItsRootAcrossEmptyAndNarrowedRepliesUntilExplicitTopicChange() throws {
        var memory = MarinaConversationMemory(workspaceID: UUID(), chatID: UUID())
        let request = MarinaDataRequest(operation: .transactions, tool: .expenses,
            startDate: "2026-06-01", endDate: "2026-06-30", sort: .smallest, limit: 1)
        let compilation = MarinaRequestCompiler.Compilation(capability: .smallestExpense, request: request,
            dateOrigin: .explicit, unresolvedTargets: [
                .init(id: "merchant", field: .merchant, name: "Market", isComparison: false, source: .userText("Market"))
            ])
        let result = MarinaDataResult(status: "candidates", scope: "Personal", records: [
            .init(id: "Market, Inc.", kind: "merchant", title: "Market, Inc."),
            .init(id: "Market Delivery", kind: "merchant", title: "Market Delivery")
        ], totalCount: 2)
        // An incidental legacy callback cannot replace the caller's authoritative root question.
        memory.record(request: .init(tool: .findRecords, search: "Market"), result: result,
                      answerID: UUID(), prompt: "The merchant")
        let root = "What was the smallest Market expense in June?"
        let initial = memory.saveCompiledClarification(compilation: compilation, result: result,
            answerID: UUID(), prompt: root, search: "Market")
        #expect(initial)
        let narrowed = memory.saveCompiledClarification(compilation: compilation, result: result,
            answerID: UUID(), prompt: "The merchant", search: "Market")
        #expect(narrowed)
        #expect(memory.pendingClarification?.originatingPrompt == root)
        #expect(memory.pendingClarification?.candidates.allSatisfy {
            memory.reference(forKind: $0.kind, id: $0.id) != nil
        } == true)
        memory.discardPendingClarification()
        let newQuestion = memory.saveCompiledClarification(compilation: compilation, result: result,
            answerID: UUID(), prompt: "A new root question", search: "Market")
        #expect(newQuestion)
        #expect(memory.pendingClarification?.originatingPrompt == "A new root question")
    }

    @Test func compiledDateChoiceKeepsBudgetRoleAndFailedSavesAreAtomic() throws {
        var memory = MarinaConversationMemory(workspaceID: UUID(), chatID: UUID())
        let request = MarinaDataRequest(relativePeriod: .selectedPeriod, tool: .expenses, grouping: .card)
        let compilation = MarinaRequestCompiler.Compilation(capability: .rankedSpending, request: request,
                                                            dateOrigin: .appDefault)
        let result = MarinaDataResult(status: "needsPeriodChoice", scope: "Personal", records: [
            .init(id: UUID().uuidString, kind: "budget", title: "June"),
            .init(id: UUID().uuidString, kind: "budget", title: "Summer")
        ], totalCount: 2)
        let accepted = memory.saveCompiledClarification(compilation: compilation, result: result,
            answerID: UUID(), prompt: "Expenses by card", search: nil)
        #expect(accepted)
        #expect(memory.pendingClarification?.recordKind == "periodBudget")
        #expect(memory.pendingClarification?.candidates.allSatisfy { $0.kind == "periodBudget" } == true)
        #expect(memory.pendingClarification?.pendingRequest?.budgetID == nil)
        #expect(memory.pendingClarification?.dateOrigin == .appDefault)
        let before = memory
        let invalid = MarinaDataResult(status: "candidates", scope: "Personal", records: [
            .init(id: UUID().uuidString, kind: "card", title: String(repeating: "x", count: 257))
        ], totalCount: 1)
        let rejected = memory.saveCompiledClarification(compilation: compilation, result: invalid,
            answerID: UUID(), prompt: "Expenses by card", search: nil)
        #expect(!rejected)
        #expect(memory == before)
        let failed = memory.saveCompiledClarification(compilation: compilation,
            result: .init(status: "invalidRequest", scope: "Personal"), answerID: UUID(),
            prompt: "Expenses by card", search: nil)
        #expect(!failed && memory == before)
    }

    @Test func pendingCompilationKeepsEveryUnresolvedTargetAndTheOriginalRequestAcrossRestore() throws {
        var memory = MarinaConversationMemory(workspaceID: UUID(), chatID: UUID())
        var request = MarinaDataRequest(operation: .transactions, tool: .expenses,
            startDate: "2026-06-01", endDate: "2026-06-30", sort: .smallest, limit: 1)
        request.metric = .total; request.expenseMeasure = .spending; request.positiveOnly = true
        let candidates = MarinaDataResult(status: "candidates", scope: "Personal", records: [
            .init(id: UUID().uuidString, kind: "card", title: "Apple"),
            .init(id: UUID().uuidString, kind: "card", title: "Apple Card")
        ], totalCount: 2)
        memory.record(request: .init(tool: .findRecords, search: "Apple"), result: candidates,
                      answerID: UUID(), prompt: "Smallest Market purchase on Apple in June")
        let compilation = MarinaRequestCompiler.Compilation(capability: .smallestExpense, request: request,
            dateOrigin: .explicit, unresolvedTargets: [
                .init(id: "card-target", field: .card, name: "Apple", isComparison: false, source: .userText("Apple")),
                .init(id: "merchant-target", field: .merchant, name: "Market", isComparison: false, source: .userText("Market"))
            ])
        let accepted = memory.setPendingCompilation(compilation)
        #expect(accepted)
        let restored = try JSONDecoder().decode(MarinaConversationMemory.self, from: JSONEncoder().encode(memory))
        #expect(restored.pendingClarification?.compilation == compilation)
        #expect(restored.pendingClarification?.pendingRequest == request)
        #expect(restored.pendingClarification?.period?.startDate == "2026-06-01")
        #expect(restored.pendingClarification?.dateOrigin == .explicit)
        #expect(restored.pendingClarification?.originatingPrompt == "Smallest Market purchase on Apple in June")
        #expect(restored.pendingClarification?.compilation?.unresolvedTargets.map(\.field) == [.card, .merchant])
        var oversized = compilation
        oversized.unresolvedTargets = (0..<12).map { index in
            .init(id: "target-\(index)", field: .categories, name: "Category \(index)", isComparison: false,
                  source: .userText(String(repeating: "q", count: 768)))
        }
        let acceptedOversized = memory.setPendingCompilation(oversized)
        #expect(!acceptedOversized)
        #expect(memory.pendingClarification?.compilation == compilation)
        let original = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(memory)) as? [String: Any])
        var malformed = original
        var pending = try #require(malformed["pendingClarification"] as? [String: Any])
        pending["compilation"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(oversized))
        malformed["pendingClarification"] = pending
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(MarinaConversationMemory.self, from: JSONSerialization.data(withJSONObject: malformed))
        }
    }

    @Test func onlyExplicitlyCommittedAnswersAdvanceTheAuthoritativeFrame() throws {
        var memory = MarinaConversationMemory(workspaceID: UUID(), chatID: UUID())
        var request = MarinaDataRequest(operation: .transactions, tool: .expenses,
            startDate: "2026-10-01", endDate: "2026-10-31", cardID: UUID().uuidString,
            sort: .largest, limit: 1)
        request.expenseMeasure = .spending
        request.positiveOnly = true
        let committed = memory.commitCompletedFrame(request: request,
            result: result(request), answerID: UUID(), prompt: "Largest purchase on my card?", dateOrigin: .explicit)
        let chosen = try #require(committed)
        for _ in 0..<20 {
            memory.record(request: .init(tool: .income), result: .init(scope: "Personal"), answerID: UUID())
        }
        #expect(memory.latestCompletedFrame == chosen)
        #expect(memory.latestFinancialQuery?.tool == .income)
        let failed = memory.commitCompletedFrame(request: request, result: .init(status: "invalidRequest", scope: "Personal"),
                                                answerID: UUID())
        let discovery = memory.commitCompletedFrame(request: .init(tool: .findRecords), result: .init(scope: "Personal"),
                                                   answerID: UUID())
        #expect(failed == nil)
        #expect(discovery == nil)
        #expect(memory.latestCompletedFrame == chosen)
        let committedUpdate = memory.commitCompletedFrame(request: request, result: result(request),
            answerID: chosen.answerID, prompt: "Retry", dateOrigin: .explicit)
        let updated = try #require(committedUpdate)
        #expect(updated.reference == chosen.reference)
        #expect(memory.completedFrames.count == 1)
    }

    @Test func canonicalRequestAndDateProvenanceSurviveWithoutSavingFinancialResults() throws {
        var memory = MarinaConversationMemory(workspaceID: UUID(), chatID: UUID())
        var requested = MarinaDataRequest(operation: .comparison, relativePeriod: .currentMonth, tool: .expenses)
        requested.metric = .total; requested.chartIntent = .movementOverTime
        requested.cardID = UUID().uuidString; requested.categoryIDs = [UUID().uuidString, "uncategorized"]
        requested.merchantName = "Market, Inc."; requested.expenseMeasure = .ledger
        requested.transactionFilter = .credit; requested.grouping = .category
        requested.compareLeaders = true; requested.includeFuture = true
        requested.comparisonStartDate = "2026-06-01"; requested.comparisonEndDate = "2026-06-30"
        requested.comparisonFilter = .init(cardID: UUID().uuidString, merchantName: "Another merchant")
        var resolved = requested
        resolved.relativePeriod = nil; resolved.startDate = "2026-10-01"; resolved.endDate = "2026-10-31"
        resolved.offset = 5; resolved.forcePresentation = true
        let financial = MarinaDataResult(scope: "Personal", metrics: [.init(label: "Total", value: 987654.32)],
            records: [.init(id: UUID().uuidString, kind: "variableExpense", title: "Private transaction", amount: 987654.32)],
            resolvedRequest: resolved)
        let committed = memory.commitCompletedFrame(request: requested, result: financial,
            answerID: UUID(), prompt: "Compare those periods", dateOrigin: .appDefault)
        let frame = try #require(committed)
        resolved.offset = 0; resolved.forcePresentation = nil
        #expect(frame.request == resolved)
        #expect(frame.dateOrigin == .appDefault)
        let data = try JSONEncoder().encode(memory)
        #expect(!String(decoding: data, as: UTF8.self).contains("987654"))
        #expect(!String(decoding: data, as: UTF8.self).contains("Private transaction"))
        let restored = try JSONDecoder().decode(MarinaConversationMemory.self, from: data)
        #expect(restored == memory)
        let context = restored.completedFrameContext(maxBytes: 1_200)
        #expect(context.contains("2026-06-30"))
        #expect(context.contains("ledger"))
        #expect(!context.contains(requested.cardID!))
        #expect(!context.contains(memory.workspaceID.uuidString))
        #expect(!context.contains("987654"))
    }

    @Test func answerHistoryRecoversOlderTopicsBeyondTheBoundedCache() throws {
        let workspaceID = UUID(), chatID = UUID()
        var memory = MarinaConversationMemory(workspaceID: workspaceID, chatID: chatID)
        var history: [HomeAnswer] = []
        var firstRequest: MarinaDataRequest?
        for index in 1...30 {
            var request = MarinaDataRequest(tool: index.isMultiple(of: 2) ? .income : .expenses,
                startDate: "2026-10-01", endDate: "2026-10-31", cardID: UUID().uuidString)
            request.metric = index == 1 ? .average : .total
            if index == 1 { firstRequest = request }
            let answerID = UUID()
            let committed = memory.commitCompletedFrame(request: request, result: result(request),
                answerID: answerID, prompt: "Topic \(index)", dateOrigin: .explicit)
            let frame = try #require(committed)
            var answer = HomeAnswer(id: answerID, queryID: UUID(), kind: .message,
                                    userPrompt: "Topic \(index)", title: "", explanation: "Verified result")
            answer.completedFrame = frame
            history.append(answer)
        }
        #expect(memory.completedFrames.count == MarinaConversationMemory.maxCompletedFrames)
        #expect(memory.completedFrame(reference: "t1") == nil)
        history = try JSONDecoder().decode([HomeAnswer].self, from: JSONEncoder().encode(history))
        var restored = MarinaConversationMemory(workspaceID: workspaceID, chatID: chatID)
        restored.restoreCompletedFrames(from: history)
        #expect(restored.completedFrame(reference: "t1", history: history)?.request == firstRequest)
        #expect(restored.latestCompletedFrame?.reference == "t30")
        #expect(restored.completedFrameDescriptors(history: history).count == 30)
        let committedNext = restored.commitCompletedFrame(request: .init(tool: .income),
            result: .init(scope: "Personal"), answerID: UUID())
        let next = try #require(committedNext)
        #expect(next.reference == "t31")
        let compact = restored.completedFrameContext(maxBytes: 500, history: history)
        #expect(compact.utf8.count <= 500 && compact.contains("t31"))
        #expect(restored.completedFrameContext(maxBytes: 10, history: history).isEmpty)
        #expect(restored.completedFrame(reference: "t1", history: history) != nil)
    }

    @Test func foreignOrConflictingHistoryFramesCannotResolve() throws {
        let workspaceID = UUID(), chatID = UUID()
        var memory = MarinaConversationMemory(workspaceID: workspaceID, chatID: chatID)
        let answerID = UUID()
        let committed = memory.commitCompletedFrame(request: .init(tool: .expenses),
            result: .init(scope: "Personal"), answerID: answerID)
        let frame = try #require(committed)
        func answer(_ value: MarinaConversationMemory.CompletedFrame, id: UUID? = nil) -> HomeAnswer {
            var answer = HomeAnswer(id: id ?? value.answerID, queryID: UUID(), kind: .message, title: "")
            answer.completedFrame = value
            return answer
        }
        var otherWorkspace = MarinaConversationMemory(workspaceID: UUID(), chatID: chatID)
        otherWorkspace.restoreCompletedFrames(from: [answer(frame)])
        #expect(otherWorkspace.completedFrames.isEmpty)
        var otherChat = MarinaConversationMemory(workspaceID: workspaceID, chatID: UUID())
        otherChat.restoreCompletedFrames(from: [answer(frame)])
        #expect(otherChat.completedFrames.isEmpty)
        var sameChat = MarinaConversationMemory(workspaceID: workspaceID, chatID: chatID)
        sameChat.restoreCompletedFrames(from: [answer(frame, id: UUID())])
        #expect(sameChat.completedFrames.isEmpty)
        let collision = MarinaConversationMemory.CompletedFrame(reference: frame.reference,
            workspaceID: workspaceID, chatID: chatID, answerID: UUID(), resultID: nil,
            request: .init(tool: .income), prompt: nil, scopeLabel: nil)
        #expect(memory.completedFrame(reference: frame.reference, history: [answer(collision)]) == nil)
    }

    @Test func olderMemoryAndAnswersDecodeWithoutInventingCompletedFrames() throws {
        var memory = MarinaConversationMemory(workspaceID: UUID(), chatID: UUID())
        var request = MarinaDataRequest(operation: .transactions, tool: .expenses,
            startDate: "2026-06-01", endDate: "2026-06-30", cardID: UUID().uuidString,
            sort: .smallest, limit: 1)
        request.expenseMeasure = .spending; request.positiveOnly = true; request.metric = .total
        memory.record(request: request, result: result(request), answerID: UUID())
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(memory)) as? [String: Any])
        json.removeValue(forKey: "completedFrames"); json.removeValue(forKey: "nextFrameNumber")
        let restored = try JSONDecoder().decode(MarinaConversationMemory.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(restored.completedFrames.isEmpty)
        #expect(restored.latestFinancialQuery?.request == request)
        let old = HomeAnswer(queryID: UUID(), kind: .message, title: "Old answer")
        let answer = try JSONDecoder().decode(HomeAnswer.self, from: JSONEncoder().encode(old))
        #expect(answer.completedFrame == nil)
    }

    @Test func storageAndModelContextHaveIndependentBoundsAndNeverReuseReferences() throws {
        let workspaceID = UUID(), chatID = UUID()
        var memory = MarinaConversationMemory(workspaceID: workspaceID, chatID: chatID)
        let longPrompt = String(repeating: "旅", count: 250)
        for index in 1...40 {
            var request = MarinaDataRequest(tool: .expenses, startDate: "2026-10-01", endDate: "2026-10-31")
            request.categoryIDs = (0..<12).map { _ in UUID().uuidString }
            request.merchantName = String(repeating: "m", count: 200)
            request.comparisonFilter = .init(categoryIDs: (0..<12).map { _ in UUID().uuidString },
                                             merchantName: String(repeating: "n", count: 200))
            let committed = memory.commitCompletedFrame(request: request,
                result: .init(scope: longPrompt, resolvedRequest: request), answerID: UUID(), prompt: longPrompt)
            let frame = try #require(committed)
            #expect(frame.reference == "t\(index)")
        }
        #expect(memory.completedFrames.count <= MarinaConversationMemory.maxCompletedFrames)
        let data = try JSONEncoder().encode(memory)
        #expect(data.count <= MarinaConversationMemory.maxStoredBytes)
        let before = memory.completedFrames
        let compact = memory.completedFrameContext(maxBytes: 1_200)
        #expect(compact.utf8.count <= 1_200)
        #expect(!compact.contains("\n"))
        #expect(memory.completedFrames == before)
        memory = try JSONDecoder().decode(MarinaConversationMemory.self, from: data)
        let committedNext = memory.commitCompletedFrame(request: .init(tool: .income),
            result: .init(scope: "Personal"), answerID: UUID())
        let next = try #require(committedNext)
        #expect(next.reference == "t41")
    }

    @Test func invalidSavedFrameReferencesAndForeignScopeFailClosed() throws {
        var memory = MarinaConversationMemory(workspaceID: UUID(), chatID: UUID())
        let committed = memory.commitCompletedFrame(request: .init(tool: .expenses),
            result: .init(scope: "Personal"), answerID: UUID())
        _ = try #require(committed)
        let original = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(memory)) as? [String: Any])
        for reference in ["t0", "t01", "t-1", "t١", "r1"] {
            var json = original
            var frames = try #require(json["completedFrames"] as? [[String: Any]])
            frames[0]["reference"] = reference; json["completedFrames"] = frames
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(MarinaConversationMemory.self, from: JSONSerialization.data(withJSONObject: json))
            }
        }
        var foreign = original
        var frames = try #require(foreign["completedFrames"] as? [[String: Any]])
        frames[0]["workspaceID"] = UUID().uuidString; foreign["completedFrames"] = frames
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(MarinaConversationMemory.self, from: JSONSerialization.data(withJSONObject: foreign))
        }
    }

    private func result(_ request: MarinaDataRequest) -> MarinaDataResult {
        .init(scope: "Personal", resolvedRequest: request)
    }
}
