import Foundation
import Testing
@testable import Offshore

#if DEBUG && canImport(FoundationModels)
import FoundationModels

/// Isolates the experimental domain classifier from tool selection and narration.
/// These held-out questions use no financial store. Passing routing does not establish
/// that the subsequent query or explanation is correct.
@MainActor
@Suite(.serialized)
struct MarinaQueryRoutingLiveTests {
    private nonisolated static var enabled: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["MARINA_MODEL_EVALUATION"] == "1"
            && environment["MARINA_QUERY_ROUTING_EVALUATION"] == "1"
    }

    nonisolated struct RoutingCase: Sendable, CustomStringConvertible {
        let id: String
        let question: String
        let expected: String
        var description: String { id }
    }

    private nonisolated static let cases: [RoutingCase] = [
        .init(id: "category-ranking", question: "Rank the categories by dollars spent in October.", expected: "expenses"),
        .init(id: "category-share", question: "Which spending category accounted for the smallest share?", expected: "expenses"),
        .init(id: "merchant-ranking", question: "Which merchants collected most of my money this quarter?", expected: "expenses"),
        .init(id: "card-grouping", question: "Break October's expenses down by payment card.", expected: "expenses"),
        .init(id: "purchase-extremum", question: "What was the priciest purchase on Sapphire in September?", expected: "expenses"),
        .init(id: "expense-average", question: "How much did an average grocery transaction cost?", expected: "expenses"),
        .init(id: "expense-count", question: "How many purchases did I record in May?", expected: "expenses"),
        .init(id: "spending-pattern", question: "Graph weekly outgoings and identify the busiest week.", expected: "expenses"),
        .init(id: "planned-expense", question: "Which scheduled charge happens next?", expected: "expenses"),
        .init(id: "transaction-details", question: "Explain the refund and shared portion of that purchase.", expected: "expenses"),
        .init(id: "category-comparison", question: "Compare the leading spending category for July with August.", expected: "expenses"),
        .init(id: "card-summary", question: "Give me a complete expense summary for Sapphire.", expected: "expenses"),
        .init(id: "category-availability", question: "Which categories have the least room left in their caps?", expected: "budget"),
        .init(id: "category-status", question: "Are any category caps exceeded or nearly used up?", expected: "budget"),
        .init(id: "minimum-goals", question: "Show the minimum targets on my June budget.", expected: "budget"),
        .init(id: "safe-spend", question: "What could I safely spend today?", expected: "budget"),
        .init(id: "actual-savings", question: "How much have I actually saved during the spring budget?", expected: "budget"),
        .init(id: "maximum-savings", question: "What's the maximum savings for my annual plan?", expected: "budget"),
        .init(id: "savings-timeline", question: "Compare accumulated actual savings with the projection this quarter.", expected: "budget"),
        .init(id: "budget-components", question: "Give me the full October budget breakdown, including income and expenses.", expected: "budget"),
        .init(id: "linked-cards", question: "Which cards participate in the summer budget?", expected: "budget"),
        .init(id: "linked-presets", question: "Show the recurring templates attached to the holiday budget.", expected: "budget"),
        .init(id: "card-inventory", question: "List every card set up here.", expected: "records"),
        .init(id: "preset-inventory", question: "Show all recurring templates in this workspace.", expected: "records"),
        .init(id: "category-inventory", question: "Which spending categories have I created?", expected: "records"),
        .init(id: "received-income", question: "How much money has arrived from work this month?", expected: "income"),
        .init(id: "income-timeline", question: "Show expected and received income as separate weekly lines.", expected: "income"),
        .init(id: "income-count", question: "How many income payments were received in May?", expected: "income"),
        .init(id: "income-ranking", question: "Which income source contributed the most?", expected: "income"),
        .init(id: "savings-balance", question: "What is the balance in my savings account?", expected: "accounts"),
        .init(id: "savings-ledger", question: "Show the recent manual adjustments in my savings ledger.", expected: "accounts"),
        .init(id: "reconciliation-activity", question: "What is Jamie's current reconciliation balance and settlement activity?", expected: "accounts"),
        .init(id: "greeting", question: "Morning, Marina.", expected: "conversation"),
        .init(id: "capability-help", question: "What sorts of questions can I ask you?", expected: "conversation"),
        .init(id: "broad-focus", question: "How are things looking?", expected: "conversation"),
        .init(id: "spending-and-accounts", question: "Give me my top merchants and the balance in my reconciliation account.", expected: "mixed"),
        .init(id: "spending-and-income-entries", question: "List my recent purchases and received income payments side by side.", expected: "mixed")
    ]

    @Test(.enabled(if: enabled, "Set MARINA_MODEL_EVALUATION=1 and MARINA_QUERY_ROUTING_EVALUATION=1."),
          arguments: cases, [1, 2, 3])
    func routesTheRequestedAnswerDomain(_ scenario: RoutingCase, _ repetition: Int) async throws {
        try await expectDomain(scenario.expected, question: scenario.question,
            scenario: scenario.id, repetition: repetition)
    }

    @Test(.enabled(if: enabled, "Set MARINA_MODEL_EVALUATION=1 and MARINA_QUERY_ROUTING_EVALUATION=1."), arguments: [1, 2, 3])
    func narrowingKeepsThePendingDomainAndExplicitTopicChangesOverrideIt(_ repetition: Int) async throws {
        var memory = MarinaConversationMemory(workspaceID: UUID(), chatID: UUID())
        memory.record(request: .init(tool: .findRecords, recordKind: "merchant", search: "Cedar"),
            result: .init(status: "candidates", scope: "Personal", records: [
                .init(id: UUID().uuidString, kind: "merchant", title: "Cedar Market"),
                .init(id: UUID().uuidString, kind: "merchant", title: "Cedar Cafe")
            ], totalCount: 2), answerID: UUID(), prompt: "How much did I spend at Cedar in August?")
        try await expectDomain("expenses", question: "Cedar Market", memory: memory,
            scenario: "pending-merchant-choice", repetition: repetition)
        try await expectDomain("income", question: "Instead, show the wages I received in August.", memory: memory,
            scenario: "explicit-topic-change", repetition: repetition)
    }

    private func expectDomain(_ expected: String, question: String, memory: MarinaConversationMemory? = nil,
                              scenario: String, repetition: Int) async throws {
        if let reason = MarinaConversationRuntime.availabilityMessage { throw EvaluationError.unavailable(reason) }
        let budget = MarinaContextBudget(capacity: SystemLanguageModel.default.contextSize)
        let start = Date.timeIntervalSinceReferenceDate
        let result = try await MarinaQueryExperiment.select(prompt: question, memory: memory, budget: budget)
        let latency = String(format: "%.3f", Date.timeIntervalSinceReferenceDate - start)
        print("MarinaQueryRouting scenario=\(scenario) repetition=\(repetition) expected=\(expected) actual=\(result.domain.rawValue) latency=\(latency) input_tokens=\(result.inputTokens) schema_tokens=\(result.schemaTokens) os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
        #expect(result.domain.rawValue == expected)
        #expect(result.schemaTokens > 0 && budget.fits(result.inputTokens))
    }

    private enum EvaluationError: Error { case unavailable(String) }
}
#endif
