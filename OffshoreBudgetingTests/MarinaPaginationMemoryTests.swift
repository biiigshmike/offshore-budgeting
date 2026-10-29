import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaPaginationMemoryTests {
    @Test func pagingAnOlderReportPreservesTypedClarificationReferencesAndActiveFrame() throws {
        var memory = MarinaConversationMemory(workspaceID: UUID(), chatID: UUID())
        let olderAnswerID = UUID(), activeAnswerID = UUID()
        var older = MarinaDataRequest(operation: .transactions, tool: .expenses,
            startDate: "2026-06-01", endDate: "2026-06-30", cardID: UUID().uuidString, limit: 5)
        older.categoryIDs = (0..<12).map { _ in UUID().uuidString }
        var oldResult = MarinaDataResult(scope: "June", totalCount: 30, nextOffset: 5, resolvedRequest: older)
        oldResult.presentation = .init(id: "older-report", operation: .transactions, title: "Expenses", scopeLabel: "June")
        memory.record(request: older, result: oldResult, answerID: olderAnswerID)
        var active = MarinaDataRequest(operation: .transactions, tool: .expenses,
            startDate: "2026-10-01", endDate: "2026-10-31", cardID: UUID().uuidString,
            sort: .smallest, limit: 1)
        active.expenseMeasure = .spending; active.positiveOnly = true
        let activeResult = MarinaDataResult(scope: "October", resolvedRequest: active)
        memory.record(request: active, result: activeResult, answerID: activeAnswerID)
        let committed = memory.commitCompletedFrame(request: active, result: activeResult,
            answerID: activeAnswerID, prompt: "Smallest card purchase in October")
        let activeFrame = try #require(committed)
        let compilation = MarinaRequestCompiler.Compilation(capability: .smallestExpense,
            request: active, dateOrigin: .explicit, unresolvedTargets: [
                .init(id: "merchant", field: .merchant, name: "Market", isComparison: false, source: .userText("Market"))
            ])
        let candidates = (0..<12).map { MarinaDataResult.Record(id: "Market \($0)", kind: "merchant", title: "Market \($0)") }
        let saved = memory.saveCompiledClarification(compilation: compilation,
            result: .init(status: "candidates", scope: "Personal", records: candidates, totalCount: 12),
            answerID: UUID(), prompt: "Smallest Market purchase on this card in October", search: "Market")
        #expect(saved)
        let pending = try #require(memory.pendingClarification)
        let references = candidates.map { memory.reference(forKind: $0.kind, id: $0.id) }
        let activeQuery = memory.latestFinancialQuery
        older.limit = 10
        oldResult.resolvedRequest = older; oldResult.nextOffset = 10
        let paged = memory.recordUIRead(request: older, result: oldResult, answerID: olderAnswerID)
        #expect(paged)
        #expect(memory.pendingClarification == pending)
        #expect(memory.latestCompletedFrame == activeFrame)
        #expect(memory.latestFinancialQuery == activeQuery)
        #expect(memory.recentQueries.first { $0.answerID == olderAnswerID }?.limit == 10)
        #expect(memory.recentQueries.first { $0.answerID == olderAnswerID }?.nextOffset == 10)
        #expect(candidates.map { memory.reference(forKind: $0.kind, id: $0.id) } == references)
        let restored = try JSONDecoder().decode(MarinaConversationMemory.self, from: JSONEncoder().encode(memory))
        #expect(restored.pendingClarification?.compilation == compilation)
        #expect(restored.latestCompletedFrame == activeFrame)
        #expect(restored.pendingClarification?.pendingRequest?.startDate == "2026-10-01")
        #expect(restored.pendingClarification?.pendingRequest?.expenseMeasure == .spending)
    }

    @Test func pagingWithNoPendingQuestionKeepsLegacyPaginationMetadataBehavior() throws {
        var memory = MarinaConversationMemory(workspaceID: UUID(), chatID: UUID())
        let answerID = UUID()
        let request = MarinaDataRequest(operation: .transactions, tool: .expenses, sort: .oldest, limit: 5)
        memory.record(request: request, result: .init(scope: "Personal", totalCount: 15, nextOffset: 5), answerID: answerID)
        let resolved = MarinaDataRequest(operation: .transactions, tool: .expenses,
            startDate: "2026-10-01", endDate: "2026-10-31", sort: .oldest, limit: 10)
        let accepted = memory.recordUIRead(request: request,
            result: .init(scope: "Personal", totalCount: 15, nextOffset: 10, resolvedRequest: resolved), answerID: answerID)
        #expect(accepted)
        #expect(memory.latestFinancialQuery?.limit == 10)
        #expect(memory.latestFinancialQuery?.nextOffset == 10)
        #expect(memory.latestFinancialQuery?.period.endDate == "2026-10-31")
    }

    @Test func failedOrForeignUIReadsCannotChangeAnyPendingState() throws {
        var memory = MarinaConversationMemory(workspaceID: UUID(), chatID: UUID())
        let request = MarinaDataRequest(tool: .expenses)
        let compilation = MarinaRequestCompiler.Compilation(capability: .expenses, request: request,
            dateOrigin: .appDefault, unresolvedTargets: [
                .init(id: "merchant", field: .merchant, name: "Unknown", isComparison: false, source: .userText("Unknown"))
            ])
        let saved = memory.saveCompiledClarification(compilation: compilation,
            result: .init(status: "empty", scope: "Personal"), answerID: UUID(), prompt: "Unknown merchant spending", search: "Unknown")
        #expect(saved)
        let before = memory
        let failed = memory.recordUIRead(request: request, result: .init(status: "invalidRequest", scope: "Personal"), answerID: UUID())
        #expect(!failed && memory == before)
        var foreign = MarinaDataResult(scope: "Other workspace")
        foreign.presentation = .init(id: "foreign", identityKey: UUID().uuidString + ":request",
            operation: .transactions, title: "Expenses", scopeLabel: "Other workspace")
        let rejected = memory.recordUIRead(request: request, result: foreign, answerID: UUID())
        #expect(!rejected && memory == before)
    }
}
