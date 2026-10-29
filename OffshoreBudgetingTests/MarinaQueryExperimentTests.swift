import Foundation
import Testing
@testable import Offshore

#if DEBUG && canImport(FoundationModels)
import FoundationModels

@MainActor
struct MarinaQueryExperimentTests {
    @Test func experimentRequiresBothEvaluationAndAnExplicitSupportedMode() {
        typealias Mode = MarinaQueryExperiment.Mode
        #expect(Mode.configured(environment: [:]) == .production)
        #expect(Mode.configured(environment: ["MARINA_MODEL_EVALUATION": "1"]) == .production)
        for raw in ["fresh", "semanticTools"] {
            #expect(Mode.configured(environment: ["MARINA_QUERY_EXPERIMENT_MODE": raw]) == .production)
            #expect(Mode.configured(environment: ["MARINA_MODEL_EVALUATION": "0", "MARINA_QUERY_EXPERIMENT_MODE": raw]) == .production)
            #expect(Mode.configured(environment: ["MARINA_MODEL_EVALUATION": "1", "MARINA_QUERY_EXPERIMENT_MODE": raw]).rawValue == raw)
        }
        #expect(Mode.configured(environment: ["MARINA_MODEL_EVALUATION": "1", "MARINA_QUERY_EXPERIMENT_MODE": "unknown"]) == .production)
        #expect(!Mode.production.refreshesEachTurn)
        #expect(Mode.fresh.refreshesEachTurn && Mode.semanticTools.refreshesEachTurn)
    }

    @Test func semanticDomainsRetainLookupAndOnlyUseExistingToolImplementations() {
        let all = Set(MarinaConversationRuntime().diagnosticTools().map(\.name))
        #expect(all.count == 5)
        for domain in [MarinaQueryExperiment.Domain.expenses, .income, .budget, .accounts] {
            let names = domain.toolNames(requiresFreshRead: true) ?? []
            #expect(names.count == 2 && names.contains("findRecords"))
            #expect(names.isSubset(of: all))
        }
        #expect(MarinaQueryExperiment.Domain.expenses.toolNames(requiresFreshRead: true) == ["findRecords", "readExpenses"])
        #expect(MarinaQueryExperiment.Domain.income.toolNames(requiresFreshRead: true) == ["findRecords", "readIncome"])
        #expect(MarinaQueryExperiment.Domain.budget.toolNames(requiresFreshRead: true) == ["findRecords", "readBudgetSummary"])
        #expect(MarinaQueryExperiment.Domain.accounts.toolNames(requiresFreshRead: true) == ["findRecords", "readAccounts"])
        #expect(MarinaQueryExperiment.Domain.records.toolNames(requiresFreshRead: false) == ["findRecords"])
    }

    @Test func financialReadRequirementOverridesConversationalClassification() {
        #expect(MarinaQueryExperiment.Domain.conversation.toolNames(requiresFreshRead: false) == [])
        #expect(MarinaQueryExperiment.Domain.conversation.toolNames(requiresFreshRead: true) == nil)
        #expect(MarinaQueryExperiment.Domain.mixed.toolNames(requiresFreshRead: false) == nil)
        #expect(MarinaQueryExperiment.Domain.mixed.toolNames(requiresFreshRead: true) == nil)
    }

    @Test func pendingQuestionSurvivesCompactReferenceTrimmingAsQuotedData() throws {
        var memory = MarinaConversationMemory(workspaceID: UUID(), chatID: UUID())
        let original = "Show expenses for \"Parcel\".\n" + String(repeating: "Context ", count: 88)
        let candidate = String(repeating: "Parcel ", count: 32)
        memory.record(request: .init(tool: .findRecords, recordKind: "merchant", search: "Parcel"),
            result: .init(status: "candidates", scope: "Personal", records: [
                .init(id: UUID().uuidString, kind: "merchant", title: candidate)
            ], totalCount: 1), answerID: UUID(), prompt: original)
        #expect(memory.pendingClarification?.originatingPrompt == original)
        #expect(!memory.contextText(maxBytes: 1200).contains("originatingPrompt"))

        let input = try MarinaQueryExperiment.input(prompt: candidate, memory: memory)
        let label = "Pending question (quoted data): "
        let line = try #require(input.split(separator: "\n").first { $0.hasPrefix(label) })
        let encoded = String(line.dropFirst(label.count))
        #expect(try JSONDecoder().decode(String.self, from: Data(encoded.utf8)) == original)
    }
}
#endif
