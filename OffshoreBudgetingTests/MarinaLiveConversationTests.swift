import Foundation
import SwiftData
import Testing
@testable import Offshore

#if canImport(FoundationModels)
/// Opt in on an Apple Intelligence device. An unavailable model is a failed evaluation,
/// not evidence that the real-model behavior passed.
@MainActor
@Suite(.serialized)
struct MarinaLiveConversationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MARINA_MODEL_EVALUATION"] == "1",
                   "Set MARINA_MODEL_EVALUATION=1 on an Apple Intelligence device."))
    func conversationRetrievesVerifiedFactsAndKeepsRelevantContext() async throws {
        try requireAvailableModel()
        let fixture = try Fixture()
        let runtime = MarinaConversationRuntime()
        var history: [HomeAnswer] = []

        let current = try await ask("How much did I spend using my Apple Card this month? I mean the card, not the merchant.", runtime: runtime, fixture: fixture, history: &history)
        #expect(runtime.toolRequests.contains { $0.tool == .expenses && $0.cardID == fixture.card.id.uuidString })
        expectTotal(30, in: current)

        let previous = try await ask("What about last month?", runtime: runtime, fixture: fixture, history: &history)
        #expect(runtime.toolRequests.contains {
            $0.tool == .expenses && $0.cardID == fixture.card.id.uuidString
                && ($0.relativePeriod == .previousMonth || ($0.startDate == fixture.previousStart && $0.endDate == fixture.previousEnd))
        })
        expectTotal(100, in: previous)

        let biggest = try await ask("Which purchase was biggest in that month on that card?", runtime: runtime, fixture: fixture, history: &history)
        #expect(runtime.toolRequests.contains { $0.tool == .expenses && $0.cardID == fixture.card.id.uuidString })
        #expect(biggest.rows.contains { $0.sourceID == fixture.biggest.id && $0.amount == 70 })
        #expect(biggest.presentations?.contains { $0.records.contains { $0.amount == 70 } } == true)

        let income = try await ask("How much actual income have I received this month across the whole workspace?", runtime: runtime, fixture: fixture, history: &history)
        #expect(runtime.toolRequests.contains {
            $0.tool == .income && $0.state == .actual && $0.cardID == nil
                && $0.operation == .summary && $0.comparisonFilter == nil
        })
        #expect(income.presentations?.contains { $0.operation == .summary } == true)
        expectTotal(500, in: income)

        fixture.context.insert(VariableExpense(descriptionText: "New grocery purchase", amount: 15,
                                               transactionDate: fixture.today, workspace: fixture.workspace,
                                               card: fixture.card))
        try fixture.context.save()
        let refreshed = try await ask("I just added a purchase. What is my Apple Card spending total this month now?", runtime: runtime, fixture: fixture, history: &history)
        #expect(runtime.toolRequests.contains { $0.tool == .expenses && $0.cardID == fixture.card.id.uuidString })
        expectTotal(45, in: refreshed)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MARINA_MODEL_EVALUATION"] == "1",
                   "Set MARINA_MODEL_EVALUATION=1 on an Apple Intelligence device."))
    func ambiguousAppleAsksBeforeFetchingSpending() async throws {
        try requireAvailableModel()
        let fixture = try Fixture()
        let runtime = MarinaConversationRuntime()
        var history: [HomeAnswer] = []

        let answer = try await ask("How much did I spend at Apple this month?", runtime: runtime, fixture: fixture, history: &history)

        #expect(runtime.toolRequests.contains { $0.tool == .findRecords })
        #expect(!runtime.toolRequests.contains { $0.tool == .expenses })
        let explanation = answer.explanation?.lowercased() ?? ""
        #expect(explanation.contains("?") && explanation.contains("card"))
        #expect(!answer.rows.contains { $0.title == "Total" })
        let clarified = try await ask("I mean the merchant, not Apple Card.", runtime: runtime, fixture: fixture, history: &history)
        #expect(runtime.toolRequests.contains { $0.tool == .expenses && $0.search == "Apple" && $0.cardID == nil })
        expectTotal(200, in: clarified)
    }

    private func requireAvailableModel() throws {
        if let reason = MarinaConversationRuntime.availabilityMessage {
            throw EvaluationError.unavailable(reason)
        }
    }

    private func ask(_ prompt: String, runtime: MarinaConversationRuntime, fixture: Fixture,
                     history: inout [HomeAnswer]) async throws -> HomeAnswer {
        var latest: HomeAnswer?
        await runtime.respond(prompt: prompt, history: history, workspace: fixture.workspace,
                              modelContext: fixture.context, homeContext: nil,
                              defaultBudgetingPeriod: .monthly, answerID: UUID()) { latest = $0 }
        let answer = try #require(latest)
        print("Marina evaluation prompt: \(prompt)")
        print("Marina evaluation requests: \(String(data: try JSONEncoder().encode(runtime.toolRequests), encoding: .utf8) ?? "")")
        print("Marina evaluation answer: \(answer.explanation ?? "")")
        try #require(runtime.lastErrorDescription == nil, "Model runtime failed: \(runtime.lastErrorDescription ?? "")")
        #expect(answer.explanation?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        #expect(answer.explanation?.contains("couldn’t finish") != true)
        history.append(answer)
        return answer
    }

    private func expectTotal(_ value: Double, in answer: HomeAnswer) {
        #expect(answer.rows.contains { $0.title == "Total" && $0.amount == value })
    }

    private enum EvaluationError: Error { case unavailable(String) }

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let workspace: Workspace
        let card: Card
        let biggest: VariableExpense
        let today: Date
        let previousStart: String
        let previousEnd: String

        init() throws {
            let schema = Schema([Workspace.self, Budget.self, BudgetCategoryLimit.self, Card.self,
                                 BudgetCardLink.self, BudgetPresetLink.self, Category.self, Preset.self,
                                 PlannedExpense.self, VariableExpense.self, AllocationAccount.self,
                                 ExpenseAllocation.self, AllocationSettlement.self, SavingsAccount.self,
                                 SavingsLedgerEntry.self, ImportMerchantRule.self, AssistantAliasRule.self,
                                 MarinaChatSession.self, IncomeSeries.self, Income.self])
            container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(
                    "MarinaLiveFixture-\(UUID())", schema: schema,
                    isStoredInMemoryOnly: true, cloudKitDatabase: .none
                )
            )
            context = ModelContext(container)
            let calendar = Calendar.current
            today = calendar.startOfDay(for: .now)
            let month = try #require(calendar.dateInterval(of: .month, for: today))
            let previousDay = try #require(calendar.date(byAdding: .day, value: -1, to: month.start))
            let previousMonth = try #require(calendar.dateInterval(of: .month, for: previousDay))
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            previousStart = formatter.string(from: previousMonth.start)
            previousEnd = formatter.string(from: previousDay)
            workspace = Workspace(name: "Evaluation", hexColor: "#3B82F6")
            card = Card(name: "Apple Card", workspace: workspace)
            let otherCard = Card(name: "Checking", workspace: workspace)
            biggest = VariableExpense(descriptionText: "Largest grocery purchase", amount: 70,
                                      transactionDate: previousDay, workspace: workspace, card: card)
            context.insert(workspace)
            context.insert(card)
            context.insert(otherCard)
            context.insert(biggest)
            context.insert(VariableExpense(descriptionText: "Small grocery purchase", amount: 30,
                                           transactionDate: previousDay, workspace: workspace, card: card))
            context.insert(VariableExpense(descriptionText: "Coffee", amount: 30,
                                           transactionDate: today, workspace: workspace, card: card))
            context.insert(VariableExpense(descriptionText: "Apple", amount: 200,
                                           transactionDate: today, workspace: workspace, card: otherCard))
            context.insert(Income(source: "Paycheck", amount: 500, date: today, isPlanned: false,
                                  workspace: workspace, card: otherCard))
            try context.save()
        }
    }
}
#endif
