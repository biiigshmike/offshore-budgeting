import Foundation
import SwiftData
import Testing
@testable import Offshore

#if canImport(FoundationModels)
@MainActor
@Suite(.serialized)
struct MarinaPresentationLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MARINA_MODEL_EVALUATION"] == "1",
                   "Set MARINA_MODEL_EVALUATION=1 on an Apple Intelligence device."))
    func screenshotConversationUsesScopedNativePresentations() async throws {
        if let message = MarinaConversationRuntime.availabilityMessage { throw EvaluationError.unavailable(message) }
        let fixture = try Fixture()
        let runtime = MarinaConversationRuntime()
        var history: [HomeAnswer] = []
        let total = try await ask("How much have I spent this month?", runtime: runtime, fixture: fixture, history: &history)
        #expect(total.presentations?.contains { $0.operation == .summary && $0.metrics.contains { abs($0.value - 3177.38) < 0.001 } } == true)

        let card = try await ask("And how much of that was on my Apple Card card?", runtime: runtime, fixture: fixture, history: &history)
        #expect(runtime.toolRequests.contains { $0.tool == .expenses && $0.cardID == fixture.card.id.uuidString })
        #expect(card.presentations?.contains { $0.card?.id == fixture.card.id.uuidString && $0.metrics.contains { abs($0.value - 602.40) < 0.001 } } == true)

        let list = try await ask("Show me the expenses included in that total.", runtime: runtime, fixture: fixture, history: &history)
        #expect(runtime.toolRequests.contains { $0.tool == .expenses && $0.cardID == fixture.card.id.uuidString && $0.operation == .transactions })
        let expenses = try #require(list.presentations?.last { $0.operation == .transactions })
        #expect(expenses.records.count == 2)
        #expect(expenses.records.allSatisfy { $0.cardName == "Apple Card" })

        let biggest = try await ask("Which purchase was the biggest?", runtime: runtime, fixture: fixture, history: &history)
        #expect(runtime.toolRequests.contains { $0.tool == .expenses && $0.cardID == fixture.card.id.uuidString && $0.sort == .largest })
        #expect(biggest.presentations?.contains { $0.operation == .transactions && $0.records.first?.id == fixture.biggest.id.uuidString } == true)

        let ranking = try await ask("Which category did I spend the most in this month across all my cards?", runtime: runtime, fixture: fixture, history: &history)
        #expect(runtime.toolRequests.contains { $0.tool == .expenses && $0.grouping == .category && $0.cardID == nil })
        #expect(ranking.presentations?.contains { $0.operation == .ranking && $0.chartPoints.first?.label == "Bills & Utilities" && abs(($0.chartPoints.first?.value ?? 0) - 2574.98) < 0.001 } == true)

        let empty = try await ask("What did I spend on Hair Care this month?", runtime: runtime, fixture: fixture, history: &history)
        #expect(runtime.toolRequests.contains { $0.tool == .expenses && $0.categoryID == fixture.hair.id.uuidString })
        #expect(empty.presentations?.contains { $0.isEmpty && $0.metrics.first?.value == 0 } == true)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MARINA_MODEL_EVALUATION"] == "1",
                   "Set MARINA_MODEL_EVALUATION=1 on an Apple Intelligence device."))
    func freshChatCategoryParaphrasesReturnGroupedTotalsAndSuccessfulZero() async throws {
        if let message = MarinaConversationRuntime.availabilityMessage { throw EvaluationError.unavailable(message) }
        let fixture = try Fixture()
        for prompt in ["Which category has the highest spending this month?", "What did I spend on Hair Care this month?"] {
            let runtime = MarinaConversationRuntime()
            var history: [HomeAnswer] = []
            let answer = try await ask(prompt, runtime: runtime, fixture: fixture, history: &history)
            if prompt.hasPrefix("Which") {
                #expect(runtime.toolRequests.contains { $0.tool == .expenses && $0.grouping == .category })
                #expect(answer.presentations?.contains { $0.chartPoints.first?.label == "Bills & Utilities" } == true)
            } else {
                #expect(answer.presentations?.contains { $0.isEmpty && $0.metrics.first?.value == 0 } == true)
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MARINA_MODEL_EVALUATION"] == "1",
                   "Set MARINA_MODEL_EVALUATION=1 on an Apple Intelligence device."))
    func sharedVisualTopicsFollowBudgetIncomeAndPresets() async throws {
        if let message = MarinaConversationRuntime.availabilityMessage { throw EvaluationError.unavailable(message) }
        let fixture = try Fixture()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let month = try #require(calendar.dateInterval(of: .month, for: today))
        let budget = Budget(name: "Monthly", startDate: month.start, endDate: month.end.addingTimeInterval(-1), workspace: fixture.workspace)
        fixture.context.insert(budget)
        fixture.context.insert(BudgetCardLink(budget: budget, card: fixture.card))
        fixture.context.insert(Income(source: "Salary", amount: 4000, date: today, isPlanned: true, workspace: fixture.workspace))
        fixture.context.insert(Income(source: "Salary", amount: 3000.38, date: today, isPlanned: false, workspace: fixture.workspace))
        let preset = Preset(title: "Music subscription", plannedAmount: 10.38, workspace: fixture.workspace)
        fixture.context.insert(preset)
        fixture.context.insert(PlannedExpense(title: "Music subscription", plannedAmount: 10.38,
            expenseDate: today, workspace: fixture.workspace, card: fixture.card,
            sourcePresetID: preset.id, sourceBudgetID: budget.id))
        try fixture.context.save()
        let runtime = MarinaConversationRuntime()
        var history: [HomeAnswer] = []
        let pace = try await ask("Am I on track with my budget this month?", runtime: runtime, fixture: fixture, history: &history)
        #expect(pace.presentations?.contains { $0.budgetPace != nil } == true)
        let income = try await ask("And how about my income? What is my planned to actual progress?", runtime: runtime, fixture: fixture, history: &history)
        #expect(income.presentations?.contains { $0.incomeProgress?.actual == 3000.38 && $0.incomeProgress?.planned == 4000 } == true)
        let upcoming = try await ask("Oh, and what about my presets? Do I have any due soon?", runtime: runtime, fixture: fixture, history: &history)
        #expect(upcoming.presentations?.contains { $0.purpose == .upcomingPresets && $0.records.contains { $0.preset?.id == preset.id.uuidString } } == true)
        let request = try #require(runtime.toolRequests.last { $0.purpose == .upcomingPresets })
        let dateStyle = Date.ISO8601FormatStyle(timeZone: .current).year().month().day().dateSeparator(.dash)
        let lastDay = try #require(calendar.date(byAdding: .day, value: 6, to: today))
        #expect(request.relativePeriod == .nextSevenDays || (request.startDate == today.formatted(dateStyle) && request.endDate == lastDay.formatted(dateStyle)))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MARINA_MODEL_EVALUATION"] == "1",
                   "Set MARINA_MODEL_EVALUATION=1 on an Apple Intelligence device."))
    func sharedVisualParaphrasesSelectAnalyticalPurposes() async throws {
        if let message = MarinaConversationRuntime.availabilityMessage { throw EvaluationError.unavailable(message) }
        let fixture = try Fixture()
        for (prompt, purpose) in [
            ("How is my spending tracking against the plan this month?", MarinaDataRequest.Purpose.budgetPace),
            ("What percentage of my planned income have I received this month?", .incomeProgress),
            ("Show my upcoming preset expenses for the next seven days.", .upcomingPresets)
        ] {
            let runtime = MarinaConversationRuntime()
            var history: [HomeAnswer] = []
            let answer = try await ask(prompt, runtime: runtime, fixture: fixture, history: &history)
            #expect(answer.presentations?.contains { $0.purpose == purpose } == true)
            if purpose == .upcomingPresets {
                let request = try #require(runtime.toolRequests.last { $0.purpose == purpose })
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: .now)
                let end = try #require(calendar.date(byAdding: .day, value: 6, to: today))
                let style = Date.ISO8601FormatStyle(timeZone: .current).year().month().day().dateSeparator(.dash)
                #expect(request.relativePeriod == .nextSevenDays || (request.startDate == today.formatted(style) && request.endDate == end.formatted(style)))
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MARINA_MODEL_EVALUATION"] == "1",
                   "Set MARINA_MODEL_EVALUATION=1 on an Apple Intelligence device."))
    func repeatedBaselineConversations() async throws {
        if let message = MarinaConversationRuntime.availabilityMessage { throw EvaluationError.unavailable(message) }
        let questions = Array(repeating: "How much have I spent this month?", count: 3) + [
            "What did I spend this month?", "What is my total spending for this month?"]
        for (index, question) in questions.enumerated() {
            print("MarinaBaseline sequence=\(index + 1)")
            let fixture = try Fixture()
            let runtime = MarinaConversationRuntime()
            var history: [HomeAnswer] = []
            do {
                let total = try await ask(question, runtime: runtime, fixture: fixture, history: &history)
                #expect(total.presentations?.contains { $0.operation == .summary && $0.metrics.contains { abs($0.value - 3177.38) < 0.001 } } == true)
                let card = try await ask("And how much of that was on my Apple Card?", runtime: runtime, fixture: fixture, history: &history)
                #expect(runtime.toolRequests.contains { $0.tool == .expenses && $0.operation == .summary && $0.cardID == fixture.card.id.uuidString })
                #expect(card.presentations?.contains { $0.operation == .summary && $0.card?.id == fixture.card.id.uuidString && $0.metrics.contains { abs($0.value - 602.40) < 0.001 } } == true)
                let list = try await ask("Show me the expenses included in that total.", runtime: runtime, fixture: fixture, history: &history)
                #expect(runtime.toolRequests.contains { $0.tool == .expenses && $0.operation == .transactions && $0.cardID == fixture.card.id.uuidString })
                #expect(list.presentations?.contains { $0.operation == .transactions && $0.records.count == 2 && $0.records.allSatisfy { $0.cardName == "Apple Card" } } == true)
                let largest = try await ask("Which purchase was the biggest?", runtime: runtime, fixture: fixture, history: &history)
                #expect(runtime.toolRequests.contains { $0.tool == .expenses && $0.sort == .largest && $0.cardID == fixture.card.id.uuidString })
                #expect(largest.presentations?.contains { $0.records.first?.id == fixture.biggest.id.uuidString } == true)
            } catch {
                Issue.record("Baseline sequence \(index + 1) could not complete; inspect fixed diagnostic outcome.")
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MARINA_MODEL_EVALUATION"] == "1",
                   "Set MARINA_MODEL_EVALUATION=1 on an Apple Intelligence device."))
    func workspaceTimingAndNamedRecordSafety() async throws {
        if let message = MarinaConversationRuntime.availabilityMessage { throw EvaluationError.unavailable(message) }
        let fixture = try Fixture()
        let runtime = MarinaConversationRuntime()
        var history: [HomeAnswer] = []
        _ = try await ask("What workspace am I in?", runtime: runtime, fixture: fixture, history: &history)
        #expect(runtime.toolRequests.isEmpty)
        _ = try await ask("And which workspace are we using now?", runtime: runtime, fixture: fixture, history: &history)
        #expect(runtime.toolRequests.isEmpty)
        for scenario in 0..<4 {
            let local = try Fixture()
            if scenario == 1 {
                local.context.insert(Card(name: "Apple Card", workspace: local.workspace))
            }
            let other = Workspace(name: "Other Workspace", hexColor: "#654321")
            local.context.insert(other)
            let otherCard = Card(name: "Foreign Card", workspace: other)
            local.context.insert(otherCard)
            local.context.insert(VariableExpense(descriptionText: "Foreign expense", amount: 99123,
                transactionDate: .now, workspace: other, card: otherCard))
            try local.context.save()
            var restored: [HomeAnswer] = []
            if scenario == 3 {
                let first = MarinaConversationRuntime()
                _ = try await ask("How much have I spent this month?", runtime: first, fixture: local, history: &restored)
                // Exercise saved-answer decoding before rebuilding the native session.
                restored = try JSONDecoder().decode([HomeAnswer].self, from: JSONEncoder().encode(restored))
            }
            let next = MarinaConversationRuntime()
            let prompt = scenario == 0 ? "How much did I spend on Missing Fixture Card this month?"
                : scenario == 1 ? "How much did I spend on Apple Card this month?"
                : scenario == 2 ? "How much did I spend on Foreign Card this month?"
                : "And how much of that was on Debit Card?"
            do {
                _ = try await ask(prompt, runtime: next, fixture: local, history: &restored)
                if scenario < 3 {
                    #expect(!next.toolRequests.contains { $0.tool == .expenses })
                } else {
                    #expect(next.toolRequests.contains { $0.tool == .expenses && $0.operation == .summary && $0.cardID == local.debit.id.uuidString })
                }
            } catch {
                Issue.record("Named-record baseline scenario \(scenario) failed; inspect fixed diagnostic outcome.")
            }
        }
    }

    private func ask(_ prompt: String, runtime: MarinaConversationRuntime, fixture: Fixture, history: inout [HomeAnswer]) async throws -> HomeAnswer {
        var latest: HomeAnswer?
        await runtime.respond(prompt: prompt, history: history, workspace: fixture.workspace,
                              modelContext: fixture.context, homeContext: nil,
                              defaultBudgetingPeriod: .monthly, answerID: UUID()) { latest = $0 }
        let answer = try #require(latest)
        #if DEBUG
        await MarinaTokenDiagnostics.flushReports()
        #endif
        print("MarinaBaseline turn=\(history.count + 1) query_count=\(runtime.toolRequests.count) failed=\(runtime.lastErrorDescription != nil)")
        for request in runtime.toolRequests {
            print("MarinaBaseline tool=\(request.tool.rawValue) operation=\(request.operation.rawValue) card_present=\(request.cardID != nil) category_present=\(request.categoryID != nil)")
        }
        try #require(runtime.lastErrorDescription == nil, "Native baseline turn failed; inspect categorized diagnostics.")
        history.append(answer)
        return answer
    }
    private enum EvaluationError: Error { case unavailable(String) }

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let workspace: Workspace
        let card: Card
        let debit: Card
        let hair: Offshore.Category
        let biggest: VariableExpense
        init() throws {
            let schema = Schema([Workspace.self, Budget.self, BudgetCategoryLimit.self, Card.self, BudgetCardLink.self, BudgetPresetLink.self, Offshore.Category.self, Preset.self, PlannedExpense.self, VariableExpense.self, AllocationAccount.self, ExpenseAllocation.self, AllocationSettlement.self, SavingsAccount.self, SavingsLedgerEntry.self, ImportMerchantRule.self, AssistantAliasRule.self, MarinaChatSession.self, IncomeSeries.self, Income.self])
            container = try ModelContainer(for: schema, configurations: ModelConfiguration("MarinaVisualFixture-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
            context = ModelContext(container)
            workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
            card = Card(name: "Apple Card", workspace: workspace)
            debit = Card(name: "Debit Card", workspace: workspace)
            hair = Offshore.Category(name: "Hair Care", hexColor: "#FF0000", workspace: workspace)
            let bills = Offshore.Category(name: "Bills & Utilities", hexColor: "#00FF00", workspace: workspace)
            let shopping = Offshore.Category(name: "Shopping", hexColor: "#0000FF", workspace: workspace)
            context.insert(workspace); context.insert(card); context.insert(debit)
            context.insert(hair); context.insert(bills); context.insert(shopping)
            let today = Calendar.current.startOfDay(for: .now)
            biggest = VariableExpense(descriptionText: "Appliance", amount: 369.15, transactionDate: today, workspace: workspace, card: card, category: shopping)
            context.insert(biggest)
            context.insert(VariableExpense(descriptionText: "MacBook Pro", amount: 233.25, transactionDate: today, workspace: workspace, card: card, category: shopping))
            context.insert(VariableExpense(descriptionText: "Rent", amount: 1200, transactionDate: today, workspace: workspace, card: debit, category: bills))
            context.insert(VariableExpense(descriptionText: "Utilities", amount: 1374.98, transactionDate: today, workspace: workspace, card: debit, category: bills))
            try context.save()
        }
    }
}
#endif
