import Foundation
import SwiftData
import Testing
@testable import Offshore

#if canImport(FoundationModels)
import FoundationModels

@MainActor
struct MarinaCompiledDatePreparationTests {
    @Test func comparisonBudgetClarificationKeepsPrimaryMonthAcrossMonthBoundary() async throws {
        let fixture = try Fixture()
        let june = fixture.budget("Holiday June", month: 6, endDay: 30)
        _ = fixture.budget("Holiday July", month: 7, endDay: 31)
        try fixture.context.save()
        var request = fixture.comparison
        request.relativePeriod = .selectedPeriod
        let prepared = try fixture.service(month: 10).prepareCompiledDates(request, deferringBudgetSides: [.comparison])
        let frozen = try #require(prepared.result.resolvedRequest)
        #expect(prepared.result.status == "ready" && prepared.pendingDateSide == nil)
        #expect(frozen.startDate == "2026-10-01" && frozen.endDate == "2026-10-31")
        #expect(frozen.comparisonStartDate == nil && frozen.comparisonEndDate == nil)
        let compilation = MarinaRequestCompiler.Compilation(capability: .spendingComparison, request: frozen, dateOrigin: .appDefault,
            unresolvedTargets: [.init(id: "other.budget.0", field: .budget, name: "Holiday", isComparison: true, source: .userText("Holiday"))])
        let lookup = try fixture.service(month: 10).execute(.init(tool: .findRecords, allTime: true, search: "Holiday"))
        let memory = try fixture.pending(compilation: compilation, result: lookup)
        let outcome = await fixture.turn(memory: memory, prompt: june.name, month: 11).run()
        let frame = try #require(outcome.answer.completedFrame)
        #expect(outcome.error == nil)
        #expect(frame.request.startDate == "2026-10-01" && frame.request.endDate == "2026-10-31")
        #expect(frame.request.comparisonStartDate == "2026-06-01" && frame.request.comparisonEndDate == "2026-06-30")
        #expect(frame.request.budgetID == nil && frame.request.comparisonFilter?.budgetID == june.id.uuidString)
    }

    @Test func primaryBudgetDeferralStillFreezesIndependentComparisonMonth() throws {
        let fixture = try Fixture()
        var request = fixture.comparison
        request.comparisonPeriod = .previousMonth
        let prepared = try fixture.service(month: 10).prepareCompiledDates(request, deferringBudgetSides: [.primary])
        let frozen = try #require(prepared.result.resolvedRequest)
        #expect(prepared.result.status == "ready" && prepared.pendingDateSide == nil)
        #expect(frozen.startDate == nil && frozen.endDate == nil)
        #expect(frozen.comparisonStartDate == "2026-09-01" && frozen.comparisonEndDate == "2026-09-30")
        #expect(frozen.comparisonPeriod == nil && frozen.comparisonFilter == request.comparisonFilter)
    }

    @Test func comparisonInheritingAnUnresolvedPrimaryWindowWaitsForThatBudget() throws {
        let fixture = try Fixture()
        let july = fixture.budget("July", month: 7, endDay: 31)
        try fixture.context.save()
        let deferred = try fixture.service(month: 10).prepareCompiledDates(fixture.comparison, deferringBudgetSides: [.primary])
        var request = try #require(deferred.result.resolvedRequest)
        #expect(request.startDate == nil && request.comparisonStartDate == nil)
        request.budgetID = july.id.uuidString
        let prepared = try fixture.service(month: 11).prepareCompiledDates(request)
        let frozen = try #require(prepared.resolvedRequest)
        #expect(frozen.startDate == "2026-07-01" && frozen.endDate == "2026-07-31")
        #expect(frozen.comparisonStartDate == "2026-07-01" && frozen.comparisonEndDate == "2026-07-31")
        #expect(frozen.comparisonFilter == fixture.comparison.comparisonFilter)
    }

    @Test(arguments: [MarinaDataRequest.RelativePeriod.selectedPeriod, .previousPeriod])
    func comparisonDateChoiceChangesOnlyItsOwnSide(period: MarinaDataRequest.RelativePeriod) async throws {
        let fixture = try Fixture()
        let chosen = fixture.budget("October A", month: 10, endDay: 31)
        _ = fixture.budget("October B", month: 10, endDay: 31)
        try fixture.context.save()
        var request = fixture.comparison
        request.startDate = "2026-06-01"; request.endDate = "2026-06-30"
        request.comparisonPeriod = period
        let prepared = try fixture.service(month: 10).prepareCompiledDates(request, deferringBudgetSides: [])
        #expect(prepared.result.status == "needsPeriodChoice" && prepared.pendingDateSide == .comparison)
        let frozen = try #require(prepared.result.resolvedRequest)
        var compilation = MarinaRequestCompiler.Compilation(capability: .spendingComparison, request: frozen, dateOrigin: .explicit)
        compilation.pendingDateSide = prepared.pendingDateSide
        let memory = try fixture.pending(compilation: compilation, result: prepared.result)
        let outcome = await fixture.turn(memory: memory, prompt: chosen.name, month: 11).run()
        let frame = try #require(outcome.answer.completedFrame)
        #expect(outcome.error == nil)
        #expect(frame.request.startDate == "2026-06-01" && frame.request.endDate == "2026-06-30")
        #expect(frame.request.comparisonStartDate == (period == .previousPeriod ? "2026-09-01" : "2026-10-01"))
        #expect(frame.request.comparisonEndDate == (period == .previousPeriod ? "2026-09-30" : "2026-10-31"))
        #expect(frame.request.budgetID == nil && frame.request.periodBudgetID == nil)
        #expect(frame.request.comparisonFilter == request.comparisonFilter)
        #expect(outcome.memory?.pendingClarification == nil)
    }

    @Test func primaryDateChoiceRetainsFrozenComparisonDates() async throws {
        let fixture = try Fixture()
        let chosen = fixture.budget("October A", month: 10, endDay: 31)
        _ = fixture.budget("October B", month: 10, endDay: 31)
        try fixture.context.save()
        var request = fixture.comparison
        request.comparisonPeriod = .previousMonth
        let prepared = try fixture.service(month: 10).prepareCompiledDates(request, deferringBudgetSides: [])
        #expect(prepared.result.status == "needsPeriodChoice" && prepared.pendingDateSide == .primary)
        let frozen = try #require(prepared.result.resolvedRequest)
        #expect(frozen.comparisonStartDate == "2026-09-01" && frozen.comparisonEndDate == "2026-09-30")
        var compilation = MarinaRequestCompiler.Compilation(capability: .spendingComparison, request: frozen, dateOrigin: .appDefault)
        compilation.pendingDateSide = prepared.pendingDateSide
        let memory = try fixture.pending(compilation: compilation, result: prepared.result)
        let outcome = await fixture.turn(memory: memory, prompt: chosen.name, month: 11).run()
        let frame = try #require(outcome.answer.completedFrame)
        #expect(frame.request.startDate == "2026-10-01" && frame.request.endDate == "2026-10-31")
        #expect(frame.request.comparisonStartDate == "2026-09-01" && frame.request.comparisonEndDate == "2026-09-30")
        #expect(frame.request.budgetID == nil && frame.request.periodBudgetID == chosen.id.uuidString)
    }

    @Test func optionalPendingDateSideRoundTripsAndOldCompilationStillDecodes() throws {
        let fixture = try Fixture()
        var compilation = MarinaRequestCompiler.Compilation(capability: .spendingComparison, request: fixture.comparison, dateOrigin: .explicit)
        compilation.pendingDateSide = .comparison
        let data = try JSONEncoder().encode(compilation)
        #expect(try JSONDecoder().decode(MarinaRequestCompiler.Compilation.self, from: data) == compilation)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "pendingDateSide")
        let legacy = try JSONDecoder().decode(MarinaRequestCompiler.Compilation.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.pendingDateSide == nil && legacy.request == compilation.request)
    }

    @MainActor
    private final class Fixture {
        let container: ModelContainer
        let context: ModelContext
        let workspace: Workspace
        let firstCard: Card
        let secondCard: Card
        var comparison: MarinaDataRequest {
            var request = MarinaDataRequest(operation: .comparison, tool: .expenses, expenseMeasure: .spending,
                cardID: firstCard.id.uuidString, scope: .variable)
            request.comparisonFilter = .init(cardID: secondCard.id.uuidString)
            return request
        }
        init() throws {
            let schema = Schema([Workspace.self, Budget.self, Card.self, BudgetCardLink.self, Category.self, Preset.self,
                BudgetPresetLink.self, BudgetCategoryLimit.self, PlannedExpense.self, VariableExpense.self,
                AllocationAccount.self, ExpenseAllocation.self, AllocationSettlement.self, SavingsAccount.self,
                SavingsLedgerEntry.self, ImportMerchantRule.self, AssistantAliasRule.self, IncomeSeries.self,
                Income.self, MarinaChatSession.self])
            container = try ModelContainer(for: schema, configurations: ModelConfiguration(
                "MarinaCompiledDates-\(UUID().uuidString)", isStoredInMemoryOnly: true, cloudKitDatabase: .none))
            context = ModelContext(container)
            workspace = Workspace(name: "Personal", hexColor: "#FFFFFF")
            firstCard = Card(name: "First", workspace: workspace)
            secondCard = Card(name: "Second", workspace: workspace)
            context.insert(workspace); context.insert(firstCard); context.insert(secondCard)
            try context.save()
        }
        func budget(_ name: String, month: Int, endDay: Int) -> Budget {
            let budget = Budget(name: name, startDate: Self.date(month: month, day: 1),
                endDate: Self.date(month: month, day: endDay), workspace: workspace)
            context.insert(budget)
            return budget
        }
        func service(month: Int) -> MarinaReadOnlyDataService {
            MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: Self.date(month: month, day: 23))
        }
        func pending(compilation: MarinaRequestCompiler.Compilation, result: MarinaDataResult) throws -> MarinaConversationMemory {
            var memory = MarinaConversationMemory(workspaceID: workspace.id, chatID: UUID())
            let saved = memory.saveCompiledClarification(compilation: compilation, result: result,
                answerID: UUID(), prompt: "Compare First and Second spending across their selected periods.", search: nil)
            #expect(saved)
            return try JSONDecoder().decode(MarinaConversationMemory.self, from: JSONEncoder().encode(memory))
        }
        func turn(memory: MarinaConversationMemory, prompt: String, month: Int) -> MarinaCompiledTurn {
            MarinaCompiledTurn(service: service(month: month), bridge: MarinaToolBridge(), memory: memory,
                history: [], prompt: prompt, answerID: UUID(), now: Self.date(month: month, day: 23),
                budget: .init(capacity: 4096), onUpdate: { _ in }) { act, _, _ in
                    .init(act: act, introduction: "", claims: [], question: "")
                }
        }
        static func date(month: Int, day: Int) -> Date {
            Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day))!
        }
    }
}
#endif
