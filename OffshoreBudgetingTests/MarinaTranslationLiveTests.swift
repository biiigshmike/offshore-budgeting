import Foundation
import Testing
@testable import Offshore

#if DEBUG && canImport(FoundationModels)
@MainActor
@Suite(.serialized)
struct MarinaTranslationLiveTests {
    private typealias Support = MarinaTranslationTestSupport
    private nonisolated static var enabled: Bool { MarinaTranslationTestSupport.enabled }

    @Test(.enabled(if: enabled, "Set MARINA_MODEL_EVALUATION=1 and MARINA_QUERY_EXPERIMENT_MODE=compiled."), arguments: [1, 2, 3])
    func categoryComparison(_ repetition: Int) async throws {
        try Support.requireAvailableModel()
        let fixture = try Support.Fixture()
        let runtime = Support.runtime(fixture)
        let chatID = UUID()
        var history: [HomeAnswer] = []
        let turns = MarinaCapabilityScenarios.categoryComparison.turns
        let first = try await Support.ask(turns[0], runtime: runtime, fixture: fixture, chatID: chatID, history: &history)
        Support.expectWords(["Dining"], in: first)
        Support.expectMoney(530, in: first)
        #expect(runtime.memory?.latestFinancialQuery?.selection == nil)
        let compared = try await Support.ask(turns[1], runtime: runtime, fixture: fixture, chatID: chatID, history: &history)
        Support.expectLeaders(compared, runtime: runtime)
        #expect(history.count == 2)
        print("MarinaTranslationScenario category-comparison repetition=\(repetition) attempted_turns=2")
    }

    @Test(.enabled(if: enabled, "Set MARINA_MODEL_EVALUATION=1 and MARINA_QUERY_EXPERIMENT_MODE=compiled."), arguments: [1, 2, 3])
    func cardExtremaMerchantAndTopicSwitch(_ repetition: Int) async throws {
        try Support.requireAvailableModel()
        let fixture = try Support.Fixture()
        let runtime = Support.runtime(fixture)
        let chatID = UUID()
        var history: [HomeAnswer] = []
        let turns = MarinaCapabilityScenarios.cardFollowUps.turns
        for (index, amount, subject) in [(0, 785.0, "Apple Card"), (1, 400.0, "Restaurant"), (2, 5.0, "Corner shop"), (3, 400.0, "Restaurant")] {
            let answer = try await Support.ask(turns[index], runtime: runtime, fixture: fixture, chatID: chatID, history: &history)
            Support.expectCardScope(runtime, fixture: fixture)
            Support.expectMoney(amount, in: answer)
            Support.expectWords([subject], in: answer)
            #expect(runtime.memory?.latestFinancialQuery?.measure == .spending)
            #expect(!runtime.toolRequests.contains { $0.operation == .comparison })
        }
        let income = try await Support.ask("How much income have I received this month?", id: "income-topic-switch",
            runtime: runtime, fixture: fixture, chatID: chatID, history: &history)
        #expect(runtime.toolRequests.contains { $0.tool == .income && $0.state == .actual
            && $0.cardID == nil && $0.categoryID == nil && $0.search == nil && $0.comparisonFilter == nil })
        #expect(runtime.memory?.latestFinancialQuery?.selection == nil)
        Support.expectPeriod(runtime, month: 10)
        Support.expectMoney(1000, in: income)
        print("MarinaTranslationScenario card-sequence-topic-switch repetition=\(repetition) attempted_turns=5")
    }

    @Test(.enabled(if: enabled, "Set MARINA_MODEL_EVALUATION=1 and MARINA_QUERY_EXPERIMENT_MODE=compiled."), arguments: [1, 2, 3])
    func categoryAvailability(_ repetition: Int) async throws {
        try Support.requireAvailableModel()
        for (scenario, warningsOnly) in [(MarinaCapabilityScenarios.categoryAvailability, false), (MarinaCapabilityScenarios.categoryWarnings, true)] {
            let fixture = try Support.Fixture()
            let runtime = Support.runtime(fixture)
            var history: [HomeAnswer] = []
            let answer = try await Support.ask(scenario.turns[0], runtime: runtime, fixture: fixture,
                chatID: UUID(), history: &history)
            Support.expectAvailability(answer, warningsOnly: warningsOnly)
            #expect(runtime.toolRequests.contains { $0.tool == .budgetSummary && $0.purpose == .categoryAvailability })
        }
        print("MarinaTranslationScenario category-availability repetition=\(repetition) attempted_chats=2")
    }

    @Test(.enabled(if: enabled, "Set MARINA_MODEL_EVALUATION=1 and MARINA_QUERY_EXPERIMENT_MODE=compiled."), arguments: [1, 2, 3])
    func cardGrouping(_ repetition: Int) async throws {
        try Support.requireAvailableModel()
        let fixture = try Support.Fixture()
        try fixture.addSecondCard()
        let runtime = Support.runtime(fixture)
        var history: [HomeAnswer] = []
        let answer = try await Support.ask(MarinaCapabilityScenarios.cardGrouping.turns[0], runtime: runtime,
            fixture: fixture, chatID: UUID(), history: &history)
        Support.expectCardGroups(answer, runtime: runtime)
        print("MarinaTranslationScenario card-grouping repetition=\(repetition) attempted_turns=1")
    }

    @Test(.enabled(if: enabled, "Set MARINA_MODEL_EVALUATION=1 and MARINA_QUERY_EXPERIMENT_MODE=compiled."), arguments: [1, 2, 3])
    func heldOutParaphrases(_ repetition: Int) async throws {
        try Support.requireAvailableModel()
        let turns: [MarinaCapabilityScenarios.Turn] = [
            .init(id: "held-out-lowest", prompt: "Find the least expensive purchase on Apple Card in October 2026.", tool: .expenses,
                operation: .transactions, sort: .smallest, positiveOnly: true, limit: 1),
            .init(id: "held-out-availability", prompt: "Which categories are almost out of room or beyond their caps for October 2026?", tool: .budgetSummary,
                purpose: .categoryAvailability, availabilityFilter: .overOrNear),
            .init(id: "held-out-card-grouping", prompt: "Show October 2026 expense totals for each payment card.", tool: .expenses,
                operation: .ranking, grouping: .card)
        ]
        for turn in turns {
            let fixture = try Support.Fixture()
            if turn.grouping == .card { try fixture.addSecondCard() }
            let runtime = Support.runtime(fixture)
            var history: [HomeAnswer] = []
            let answer = try await Support.ask(turn, runtime: runtime, fixture: fixture, chatID: UUID(), history: &history)
            switch turn.id {
            case "held-out-lowest":
                Support.expectCardScope(runtime, fixture: fixture)
                Support.expectWords(["Corner shop"], in: answer)
                Support.expectMoney(5, in: answer)
            case "held-out-availability": Support.expectAvailability(answer, warningsOnly: true)
            default: Support.expectCardGroups(answer, runtime: runtime)
            }
        }
        let fixture = try Support.Fixture()
        let runtime = Support.runtime(fixture)
        let chatID = UUID()
        var history: [HomeAnswer] = []
        let first = try await Support.ask("Which category absorbed the largest amount in October 2026?", id: "held-out-category",
            runtime: runtime, fixture: fixture, chatID: chatID, history: &history)
        Support.expectWords(["Dining"], in: first)
        Support.expectMoney(530, in: first)
        let compared = try await Support.ask("Set that against the leading category in June 2026.", id: "held-out-comparison",
            runtime: runtime, fixture: fixture, chatID: chatID, history: &history)
        Support.expectLeaders(compared, runtime: runtime)
        print("MarinaTranslationScenario held-out repetition=\(repetition) attempted_chats=4 attempted_turns=5")
    }

    @Test(.enabled(if: enabled, "Set MARINA_MODEL_EVALUATION=1 and MARINA_QUERY_EXPERIMENT_MODE=compiled."), arguments: [1, 2, 3])
    func compoundRequestAnswersBothPartsOrClarifies(_ repetition: Int) async throws {
        try Support.requireAvailableModel()
        let fixture = try Support.Fixture()
        let runtime = Support.runtime(fixture)
        var history: [HomeAnswer] = []
        let answer = try await Support.ask("How much income have I received this month, and what was my largest purchase on Apple Card?",
            id: "compound-income-and-expense", runtime: runtime, fixture: fixture, chatID: UUID(), history: &history)
        let reads = runtime.toolRequests.filter { $0.tool != .findRecords }
        if reads.isEmpty {
            #expect(answer.presentations?.isEmpty != false)
            #expect(answer.explanation?.contains("?") == true, "A bounded implementation may clarify, but cannot silently choose one clause.")
        } else {
            #expect(reads.contains { $0.tool == .income && $0.state == .actual && $0.cardID == nil })
            #expect(reads.contains { $0.tool == .expenses && $0.operation == .transactions
                && $0.sort == .largest && $0.limit == 1 && $0.cardID == fixture.card.id.uuidString })
            Support.expectMoney(1000, in: answer)
            Support.expectMoney(400, in: answer)
            Support.expectWords(["Restaurant"], in: answer)
        }
        print("MarinaTranslationScenario compound-request repetition=\(repetition) financial_reads=\(reads.count)")
    }
}
#endif
