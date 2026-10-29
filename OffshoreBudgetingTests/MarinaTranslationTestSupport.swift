import Foundation
import SwiftData
import Testing
@testable import Offshore

#if DEBUG && canImport(FoundationModels)
/// Synthetic fixtures shared only by the compiled-query evaluations. Existing native
/// suites retain their original fixtures so their baseline remains reproducible.
@MainActor
enum MarinaTranslationTestSupport {
    nonisolated static var enabled: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["MARINA_MODEL_EVALUATION"] == "1"
            && environment["MARINA_QUERY_EXPERIMENT_MODE"] == "compiled"
    }

    nonisolated static var longEnabled: Bool {
        enabled && ProcessInfo.processInfo.environment["MARINA_TRANSLATION_LONG_EVALUATION"] == "1"
    }

    static func requireAvailableModel() throws {
        if let reason = MarinaConversationRuntime.availabilityMessage { throw EvaluationError.unavailable(reason) }
    }

    static func runtime(_ fixture: Fixture, capacity: Int? = nil) -> MarinaConversationRuntime {
        MarinaConversationRuntime(contextCapacityOverride: capacity, now: { fixture.now })
    }

    @discardableResult
    static func ask(_ prompt: String, id: String, runtime: MarinaConversationRuntime, fixture: Fixture,
                    chatID: UUID, history: inout [HomeAnswer], restoredMemory: MarinaConversationMemory? = nil) async throws -> HomeAnswer {
        let started = ContinuousClock.now
        let answerID = UUID()
        let originalHistory = history
        var latest: HomeAnswer?
        var streamedIDs: Set<UUID> = []
        var firstText: Duration?
        await runtime.respond(prompt: prompt, history: history, workspace: fixture.workspace,
            modelContext: fixture.context, homeContext: nil, defaultBudgetingPeriod: .monthly,
            answerID: answerID, chatID: chatID, restoredMemory: restoredMemory) { answer in
                latest = answer
                streamedIDs.insert(answer.id)
                if firstText == nil, answer.explanation?.isEmpty == false { firstText = started.duration(to: .now) }
            }
        let answer = try #require(latest)
        let duration = started.duration(to: .now)
        print("MarinaTranslationAcceptance scenario=\(id) turn=\(history.count + 1) completed=\(answer.responseState == .complete) requests=\(runtime.toolRequests.count) first_visible_text=\(firstText.map { String(describing: $0) } ?? "none") total=\(duration) narration_fallback=\(runtime.diagnosticNarrationUsedFallback) narration_reason=\(runtime.diagnosticNarrationFallbackReason ?? "none") os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
        if ProcessInfo.processInfo.environment["MARINA_LONG_EVALUATION_VERBOSE"] == "1" {
            print("MarinaTranslationSynthetic prompt=\(prompt) error=\(runtime.lastErrorDescription ?? "none")")
            print("MarinaTranslationSynthetic requests=\(runtime.toolRequests)")
            print("MarinaTranslationSynthetic answer=\(answer.explanation ?? "")")
        }
        // Record failures without aborting the remaining conversation. Successful later
        // recovery does not erase this turn's failed expectations.
        #expect(runtime.lastErrorDescription == nil, "Inspect this turn's native translation diagnostics.")
        #expect(answer.responseState == .complete)
        #expect(answer.contextStatus != .reached)
        #expect(streamedIDs == [answerID])
        #expect(history == originalHistory)
        #expect(answer.explanation?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        #expect(!(answer.explanation ?? "").contains("{{"))
        #expect(!(answer.explanation ?? "").contains("——"))
        #expect(answer.presentations?.allSatisfy { presentation in
            !presentation.records.contains { $0.id == fixture.foreignExpense.id.uuidString }
                && !presentation.metrics.contains { $0.value >= 900_000 }
        } != false)
        #expect(runtime.memory?.workspaceID == fixture.workspace.id)
        #expect(runtime.memory?.chatID == chatID)
        history.append(answer)
        return answer
    }

    @discardableResult
    static func ask(_ turn: MarinaCapabilityScenarios.Turn, runtime: MarinaConversationRuntime,
                    fixture: Fixture, chatID: UUID, history: inout [HomeAnswer],
                    restoredMemory: MarinaConversationMemory? = nil) async throws -> HomeAnswer {
        let answer = try await ask(turn.prompt, id: turn.id, runtime: runtime, fixture: fixture,
            chatID: chatID, history: &history, restoredMemory: restoredMemory)
        if turn.requiresFinancialRead {
            #expect(runtime.toolRequests.contains(where: turn.matches), "The translated request must satisfy the shared scenario contract.")
        } else {
            #expect(!runtime.toolRequests.contains { $0.tool != .findRecords })
        }
        if turn.requiresClarification { #expect(answer.explanation?.contains("?") == true) }
        return answer
    }

    static func expectMoney(_ value: Double, in answer: HomeAnswer) {
        #expect((answer.explanation ?? "").contains(CurrencyFormatter.string(from: value)))
    }

    static func expectWords(_ words: [String], in answer: HomeAnswer) {
        for word in words { #expect((answer.explanation ?? "").localizedCaseInsensitiveContains(word)) }
    }

    static func expectCardScope(_ runtime: MarinaConversationRuntime, fixture: Fixture, month: Int = 10) {
        let reads = runtime.toolRequests.filter { $0.tool == .expenses }
        #expect(!reads.isEmpty && reads.allSatisfy { $0.cardID == fixture.card.id.uuidString })
        #expect(runtime.memory?.latestFinancialQuery?.selection?.cardID == fixture.card.id.uuidString)
        expectPeriod(runtime, month: month)
    }

    static func expectPeriod(_ runtime: MarinaConversationRuntime, month: Int) {
        let start = month == 6 ? "2026-06-01" : "2026-10-01"
        let end = month == 6 ? "2026-06-30" : "2026-10-31"
        #expect(runtime.memory?.latestFinancialQuery?.period.startDate == start)
        #expect(runtime.memory?.latestFinancialQuery?.period.endDate == end)
    }

    static func expectLeaders(_ answer: HomeAnswer, runtime: MarinaConversationRuntime) {
        #expect(runtime.toolRequests.contains { $0.tool == .expenses && $0.operation == .comparison
            && $0.compareLeaders == true && $0.grouping == .category })
        let leaders = answer.presentations?.compactMap(\.report).compactMap(\.leaders).last ?? []
        #expect(leaders.count == 2)
        #expect(leaders.first?.title == "Dining" && leaders.first?.amount == 530)
        #expect(leaders.last?.title == "Travel" && leaders.last?.amount == 800)
        #expect(runtime.memory?.latestFinancialQuery?.period.startDate == "2026-10-01")
        #expect(runtime.memory?.latestFinancialQuery?.period.endDate == "2026-10-31")
        #expect(runtime.memory?.latestFinancialQuery?.comparisonPeriod?.startDate == "2026-06-01")
        #expect(runtime.memory?.latestFinancialQuery?.comparisonPeriod?.endDate == "2026-06-30")
        expectWords(["Dining", "Travel"], in: answer)
        expectMoney(530, in: answer)
        expectMoney(800, in: answer)
    }

    static func expectAvailability(_ answer: HomeAnswer, warningsOnly: Bool) {
        let categories = answer.presentations?.compactMap(\.report).compactMap(\.categories).last ?? []
        #expect(categories.contains { $0.name == "Dining" && $0.status == "over" })
        #expect(categories.contains { $0.name == "Groceries" && $0.status == "near" })
        if warningsOnly { #expect(Set(categories.map(\.name)) == ["Dining", "Groceries"]) }
    }

    static func expectCardGroups(_ answer: HomeAnswer, runtime: MarinaConversationRuntime) {
        #expect(runtime.toolRequests.contains { $0.tool == .expenses && $0.operation == .ranking
            && $0.grouping == .card && $0.cardID == nil && $0.purpose != .cardSummary })
        let labels = answer.presentations?.flatMap { $0.chartPoints.map(\.label) } ?? []
        #expect(labels.contains("Apple Card") && labels.contains("Travel Card"))
        #expect(answer.presentations?.count == 1)
    }

    struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let workspace: Workspace
        let card: Card
        let foreignExpense: VariableExpense
        let now = Self.date(month: 10, day: 17)

        static func date(month: Int, day: Int) -> Date {
            Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
        }

        init() throws {
            let schema = Schema([Workspace.self, Budget.self, BudgetCategoryLimit.self, Card.self,
                BudgetCardLink.self, BudgetPresetLink.self, Category.self, Preset.self, PlannedExpense.self,
                VariableExpense.self, AllocationAccount.self, ExpenseAllocation.self, AllocationSettlement.self,
                SavingsAccount.self, SavingsLedgerEntry.self, ImportMerchantRule.self, AssistantAliasRule.self,
                MarinaChatSession.self, IncomeSeries.self, Income.self])
            container = try ModelContainer(for: schema, configurations: ModelConfiguration(
                "MarinaTranslationFixture-\(UUID())", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
            context = ModelContext(container)
            workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
            card = Card(name: "Apple Card", workspace: workspace)
            let dining = Category(name: "Dining", hexColor: "#AA3366", workspace: workspace)
            let groceries = Category(name: "Groceries", hexColor: "#339966", workspace: workspace)
            let travel = Category(name: "Travel", hexColor: "#3366AA", workspace: workspace)
            let budget = Budget(name: "October", startDate: Self.date(month: 10, day: 1), endDate: Self.date(month: 10, day: 31), workspace: workspace)
            let june = Budget(name: "June", startDate: Self.date(month: 6, day: 1), endDate: Self.date(month: 6, day: 30), workspace: workspace)
            let preset = Preset(title: "Meal plan", plannedAmount: 80, workspace: workspace, defaultCard: card, defaultCategory: dining)
            context.insert(workspace); context.insert(card); context.insert(dining); context.insert(groceries); context.insert(travel)
            context.insert(budget); context.insert(june); context.insert(preset)
            context.insert(BudgetCardLink(budget: budget, card: card)); context.insert(BudgetCardLink(budget: june, card: card))
            context.insert(BudgetPresetLink(budget: budget, preset: preset))
            context.insert(BudgetCategoryLimit(minAmount: 100, maxAmount: 500, budget: budget, category: dining))
            context.insert(BudgetCategoryLimit(maxAmount: 180, budget: budget, category: groceries))
            let restaurant = VariableExpense(descriptionText: "Restaurant", amount: 400, transactionDate: Self.date(month: 10, day: 8), workspace: workspace, card: card, category: dining)
            context.insert(restaurant)
            let account = AllocationAccount(name: "Household", workspace: workspace)
            context.insert(account)
            context.insert(ExpenseAllocation(allocatedAmount: 50, preservesGrossAmount: true, workspace: workspace, account: account, expense: restaurant))
            for (title, amount, day, category) in [("Cafe", 100.0, 12, dining), ("Grocery market", 200.0, 14, groceries), ("Corner shop", 5.0, 16, groceries)] {
                context.insert(VariableExpense(descriptionText: title, amount: amount, transactionDate: Self.date(month: 10, day: day), workspace: workspace, card: card, category: category))
            }
            context.insert(VariableExpense(descriptionText: "Refund", amount: 40, kindRaw: VariableExpenseKind.credit.rawValue,
                transactionDate: Self.date(month: 10, day: 16), workspace: workspace, card: card, category: groceries))
            context.insert(PlannedExpense(title: "Meal plan", plannedAmount: 80, expenseDate: Self.date(month: 10, day: 20), workspace: workspace, card: card, category: dining, sourcePresetID: preset.id, sourceBudgetID: budget.id))
            context.insert(VariableExpense(descriptionText: "Hotel", amount: 800, transactionDate: Self.date(month: 6, day: 10), workspace: workspace, card: card, category: travel))
            context.insert(VariableExpense(descriptionText: "June cafe", amount: 100, transactionDate: Self.date(month: 6, day: 11), workspace: workspace, card: card, category: dining))
            context.insert(Income(source: "Salary", amount: 1200, date: Self.date(month: 10, day: 1), isPlanned: true, workspace: workspace))
            context.insert(Income(source: "Salary", amount: 1000, date: Self.date(month: 10, day: 15), isPlanned: false, workspace: workspace))
            context.insert(SavingsLedgerEntry(date: Self.date(month: 10, day: 16), amount: 25, note: "Manual savings",
                kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue, workspace: workspace))
            let otherWorkspace = Workspace(name: "Work", hexColor: "#887766")
            let foreignCard = Card(name: "Apple Card", workspace: otherWorkspace)
            foreignExpense = VariableExpense(descriptionText: "Foreign sentinel", amount: 900_001,
                transactionDate: Self.date(month: 10, day: 8), workspace: otherWorkspace, card: foreignCard)
            context.insert(otherWorkspace); context.insert(foreignCard); context.insert(foreignExpense)
            try context.save()
        }

        func addSecondCard() throws {
            let other = Card(name: "Travel Card", workspace: workspace)
            context.insert(other)
            context.insert(VariableExpense(descriptionText: "Train", amount: 42,
                transactionDate: Self.date(month: 10, day: 9), workspace: workspace, card: other))
            try context.save()
        }
    }

    private enum EvaluationError: Error { case unavailable(String) }
}
#endif
