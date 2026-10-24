import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
final class MarinaAnalyticalPresentationTests {
    private var retainedContainers: [ModelContainer] = []
    private func fixture() throws -> (ModelContext, Workspace, Card) {
        let schema = Schema([Workspace.self, Budget.self, Card.self, BudgetCardLink.self, Offshore.Category.self, Preset.self, BudgetPresetLink.self, BudgetCategoryLimit.self, PlannedExpense.self, VariableExpense.self, AllocationAccount.self, ExpenseAllocation.self, AllocationSettlement.self, SavingsAccount.self, SavingsLedgerEntry.self, ImportMerchantRule.self, AssistantAliasRule.self, IncomeSeries.self, Income.self, MarinaChatSession.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(
            "MarinaAnalyticalFixture-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        retainedContainers.append(container)
        let context = ModelContext(container)
        let workspace = Workspace(name: "Personal", hexColor: "#FFFFFF")
        let card = Card(name: "Debit", workspace: workspace)
        context.insert(workspace); context.insert(card)
        return (context, workspace, card)
    }
    private func date(_ day: Int) -> Date { Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12))! }

    @Test func upcomingPresetsUseExistingUnrecordedOccurrencesAndFrozenPages() throws {
        let (context, workspace, card) = try fixture()
        let preset = Preset(title: "Archived subscription", plannedAmount: 10.38, workspace: workspace, isArchived: true)
        context.insert(preset)
        for day in 16...24 {
            context.insert(PlannedExpense(title: "Subscription", plannedAmount: 10.38, expenseDate: date(day), workspace: workspace, card: card, sourcePresetID: preset.id))
        }
        context.insert(PlannedExpense(title: "Already paid", plannedAmount: 100, actualAmount: 100, expenseDate: date(18), workspace: workspace, card: card, sourcePresetID: preset.id))
        context.insert(PlannedExpense(title: "Manual", plannedAmount: 100, expenseDate: date(18), workspace: workspace, card: card))
        let foreign = Workspace(name: "Other", hexColor: "#000000"); context.insert(foreign)
        context.insert(PlannedExpense(title: "Other workspace", plannedAmount: 999, expenseDate: date(18), workspace: foreign, sourcePresetID: preset.id))
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: date(17))
        var request = MarinaDataRequest(tool: .expenses); request.purpose = .upcomingPresets; request.limit = 5
        let first = try #require(service.execute(request).presentation)
        #expect(first.totalCount == 7)
        #expect(first.records.count == 5)
        #expect(first.records.first?.date == "2026-10-17")
        #expect(first.records.first?.preset?.title == "Archived subscription")
        #expect(first.pagination?.request.endDate == "2026-10-23")
        var ordinary = request
        ordinary.purpose = nil; ordinary.scope = .planned; ordinary.operation = .transactions; ordinary.includeFuture = true
        ordinary.startDate = "2026-10-17"; ordinary.endDate = "2026-10-23"
        let expenseRows = try #require(service.execute(ordinary).presentation)
        #expect(expenseRows.records.allSatisfy { $0.preset == nil })
        let saved = try JSONEncoder().encode(first)
        preset.title = "Renamed"
        try context.save()
        let more = try #require(service.loadMore(presentation: first).presentation)
        #expect(more.records.count == 7)
        #expect(more.records.last?.date == "2026-10-23")
        #expect(more.isUpdated)
        #expect(more.identityKey == first.identityKey)
        #expect(try JSONDecoder().decode(MarinaPresentation.self, from: saved).records.first?.preset?.title == "Archived subscription")
    }

    @Test func incomeProgressUsesBothStatesAndSelectedCardWithoutClamping() throws {
        let (context, workspace, card) = try fixture()
        context.insert(Income(source: "Pay", amount: 150.38, date: date(17), isPlanned: false, workspace: workspace, card: card))
        context.insert(Income(source: "Pay", amount: 100, date: date(17), isPlanned: true, workspace: workspace, card: card))
        context.insert(Income(source: "Other", amount: 999, date: date(17), isPlanned: false, workspace: workspace))
        try context.save()
        var request = MarinaDataRequest(tool: .income); request.purpose = .incomeProgress; request.cardID = card.id.uuidString; request.state = .actual
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: date(17))
        let result = try #require(service.execute(request).presentation)
        #expect(result.incomeProgress?.actual == 150.38)
        #expect(result.incomeProgress?.planned == 100)
        var changed = request; changed.forcePresentation = true; changed.limit = 5
        #expect(try service.execute(changed).presentation?.identityKey == result.identityKey)
        changed.cardID = nil
        #expect(try service.execute(changed).presentation?.identityKey != result.identityKey)
    }

    @Test func paceRejectsAmbiguousBudgetsAndRepresentsMissingBaseline() throws {
        let (context, workspace, _) = try fixture()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: date(17))
        var request = MarinaDataRequest(tool: .budgetSummary); request.purpose = .budgetPace
        #expect(try service.execute(request).presentation?.budgetPace?.planned == 0)
        for name in ["First", "Second"] { context.insert(Budget(name: name, startDate: date(1), endDate: date(31), workspace: workspace)) }
        try context.save()
        #expect(try service.execute(request).status == "invalidRequest")
    }
    @Test func trendSlicesPreserveSelectedMeasureColorsAndExactBucketTotals() throws {
        let (context, workspace, card) = try fixture()
        let category = Offshore.Category(name: "Food", hexColor: "#FF0000", workspace: workspace)
        context.insert(category)
        context.insert(VariableExpense(descriptionText: "Meal", amount: 20.38, transactionDate: date(17), workspace: workspace, card: card, category: category))
        context.insert(VariableExpense(descriptionText: "Other card", amount: 900, transactionDate: date(17), workspace: workspace, category: category))
        context.insert(VariableExpense(descriptionText: "Uncategorized", amount: 10, transactionDate: date(18), workspace: workspace, card: card))
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: date(17))
        var request = MarinaDataRequest(tool: .expenses)
        request.operation = .trend; request.periodUnit = .day; request.startDate = "2026-10-17"; request.endDate = "2026-10-18"
        request.cardID = card.id.uuidString
        let result = try #require(service.execute(request).presentation)
        #expect(result.chartPoints.count == 2)
        #expect(result.chartPoints[0].slices?.first?.name == "Food")
        #expect(result.chartPoints[0].slices?.first?.colorHex == "#FF0000")
        #expect(result.chartPoints[0].slices?.first?.amount == 20.38)
        for point in result.chartPoints { #expect(point.slices?.reduce(0) { $0 + $1.amount } == point.value) }
        var paged = request; paged.limit = 1
        let firstPage = try #require(service.execute(paged).presentation)
        category.hexColor = "#0000FF"
        try context.save()
        let refreshed = try #require(service.loadMore(presentation: firstPage).presentation)
        #expect(refreshed.isUpdated)
        #expect(refreshed.chartPoints.first?.slices?.first?.colorHex == "#0000FF")
        let alternate = MarinaReadOnlyDataService(workspace: workspace, modelContext: context,
            homeContext: .init(dateRange: nil, excludeFuturePlannedExpensesFromCalculations: true, excludeFutureVariableExpensesFromCalculations: true), now: date(17))
        #expect(try alternate.execute(request).presentation?.identityKey != result.identityKey)
    }

}
