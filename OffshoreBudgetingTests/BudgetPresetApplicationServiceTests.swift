import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct BudgetPresetApplicationServiceTests {
    @Test func offerRequiresWorkspaceDefaultCardAndOccurrence() throws {
        let fixture = try Fixture()
        let boundary = fixture.budget("Boundary", startDay: 1, endDay: 15)
        let noOccurrence = fixture.budget("Too Short", startDay: 1, endDay: 14)
        let noCards = fixture.budget("No Cards", startDay: 1, endDay: 31, linkDefaultCard: false)
        let otherCard = Card(name: "Other Card", workspace: fixture.workspace)
        fixture.context.insert(otherCard)
        let wrongCard = fixture.budget("Wrong Card", startDay: 1, endDay: 31, linkDefaultCard: false)
        fixture.context.insert(BudgetCardLink(budget: wrongCard, card: otherCard))
        let foreignWorkspace = Workspace(name: "Other Workspace", hexColor: "#3B82F6")
        let foreignBudget = fixture.budget("Other Workspace", startDay: 1, endDay: 31)
        fixture.context.insert(foreignWorkspace)
        foreignBudget.workspace = foreignWorkspace
        try fixture.context.save()

        let budgets = [boundary, noOccurrence, noCards, wrongCard, foreignBudget]
        let eligible = budgets.filter {
            BudgetPresetApplicationService.isEligibleForOffer(fixture.preset, in: $0, workspace: fixture.workspace)
        }
        #expect(eligible.map(\.id) == [boundary.id])
        #expect(try fixture.apply(to: wrongCard) == .ineligible)
        #expect(try fixture.apply(to: noOccurrence) == .ineligible)
        #expect(try fixture.apply(to: foreignBudget) == .ineligible)
        #expect(try fixture.expenses().isEmpty)

        fixture.preset.frequencyRaw = RecurrenceFrequency.none.rawValue
        #expect(!BudgetPresetApplicationService.isEligibleForOffer(
            fixture.preset, in: boundary, workspace: fixture.workspace
        ))
    }

    @Test func repeatApplyAndExistingOccurrenceDoNotDuplicateBills() throws {
        let fixture = try Fixture()
        let first = fixture.budget("First", startDay: 1, endDay: 15)
        let overlapping = fixture.budget("Overlapping", startDay: 15, endDay: 31)
        let existing = PlannedExpense(
            title: "Recorded Rent", plannedAmount: 1_000, actualAmount: 950,
            expenseDate: fixture.date(day: 15).addingTimeInterval(3_600),
            workspace: fixture.workspace, card: fixture.card,
            sourcePresetID: fixture.preset.id, sourceBudgetID: first.id
        )
        fixture.context.insert(existing)
        try fixture.context.save()

        #expect(try fixture.apply(to: first) == .applied)
        #expect(try fixture.apply(to: first) == .alreadyLinked)
        #expect(first.presetLinks?.count == 1)
        #expect(try fixture.expenses().map(\.id) == [existing.id])
        #expect(existing.actualAmount == 950)
        #expect(!BudgetPresetApplicationService.isEligibleForOffer(
            fixture.preset, in: first, workspace: fixture.workspace
        ))
        #expect(overlapping.presetLinks?.isEmpty ?? true)

        #expect(try fixture.apply(to: overlapping, offer: false) == .applied)
        let expenses = try fixture.expenses()
        #expect(expenses.count == 2)
        let generated = try #require(expenses.first { $0.sourceBudgetID == overlapping.id })
        #expect(generated.expenseDate == fixture.date(day: 15))
        #expect(generated.sourcePresetID == fixture.preset.id)
        #expect(generated.card?.id == fixture.card.id)
    }

    @Test func manualApplicationCanLinkWithNoOccurrenceOrWithAnUnassignedCard() throws {
        let fixture = try Fixture()
        let shortBudget = fixture.budget("Short", startDay: 1, endDay: 14)
        let wrongCard = fixture.budget("Wrong Card", startDay: 1, endDay: 31, linkDefaultCard: false)
        let otherCard = Card(name: "Other Card", workspace: fixture.workspace)
        fixture.context.insert(otherCard)
        fixture.context.insert(BudgetCardLink(budget: wrongCard, card: otherCard))
        try fixture.context.save()

        #expect(try fixture.apply(to: shortBudget, offer: false) == .applied)
        #expect(shortBudget.presetLinks?.count == 1)
        #expect(try fixture.expenses().isEmpty)
        #expect(try fixture.apply(to: wrongCard, offer: false) == .applied)
        let expense = try #require(fixture.expenses().first)
        #expect(expense.sourceBudgetID == wrongCard.id)
        #expect(expense.card == nil)
    }

    @Test func failedApplyDiscardsOnlyAttemptAndCanBeRetried() throws {
        let fixture = try Fixture()
        let budget = fixture.budget("First", startDay: 1, endDay: 31)
        let overlapping = fixture.budget("Overlapping", startDay: 15, endDay: 31)
        try fixture.context.save()
        let unrelated = Category(name: "Unrelated Draft", hexColor: "#3B82F6", workspace: fixture.workspace)
        fixture.context.insert(unrelated)

        #expect(throws: SaveError.self) {
            try BudgetPresetApplicationService.apply(
                fixture.preset, to: [budget, overlapping], in: fixture.workspace, requiresMatchingCardAndDates: true,
                modelContext: fixture.context, save: { _ in throw SaveError.failed }
            )
        }
        #expect(!BudgetPresetApplicationService.isLinked(fixture.preset, to: budget))
        #expect(!BudgetPresetApplicationService.isLinked(fixture.preset, to: overlapping))
        #expect(try fixture.expenses().isEmpty)
        #expect(try fixture.context.fetch(FetchDescriptor<Offshore.Category>()).map(\.id) == [unrelated.id])
        #expect(try fixture.context.fetchCount(FetchDescriptor<Preset>()) == 1)
        #expect(try fixture.apply(to: [budget, overlapping]) == .applied)
        #expect(try fixture.apply(to: [budget, overlapping]) == .alreadyLinked)
        #expect(Set(try fixture.expenses().compactMap(\.sourceBudgetID)) == [budget.id, overlapping.id])
        #expect(try fixture.expenses().count == 2)
    }

    @Test func aStaleSelectionLeavesOtherBudgetsUnchanged() throws {
        let fixture = try Fixture()
        let valid = fixture.budget("Valid", startDay: 1, endDay: 31)
        let stale = fixture.budget("Stale", startDay: 1, endDay: 31)
        try fixture.context.save()
        stale.endDate = fixture.date(day: 14)

        #expect(try fixture.apply(to: [valid, stale]) == .ineligible)
        #expect(!BudgetPresetApplicationService.isLinked(fixture.preset, to: valid))
        #expect(try fixture.expenses().isEmpty)
    }

    private enum SaveError: Error { case failed }

    @MainActor
    private struct Fixture {
        let context: ModelContext
        let workspace: Workspace
        let card: Card
        let preset: Preset

        init() throws {
            let schema = OffshoreBudgetingApp.modelSchema
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            context = ModelContext(try ModelContainer(for: schema, configurations: configuration))
            workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
            card = Card(name: "Checking", workspace: workspace)
            preset = Preset(title: "Rent", plannedAmount: 1_000, workspace: workspace, defaultCard: card)
            context.insert(workspace)
            context.insert(card)
            context.insert(preset)
        }

        func date(day: Int) -> Date {
            Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: day))!
        }

        func budget(_ name: String, startDay: Int, endDay: Int, linkDefaultCard: Bool = true) -> Budget {
            let budget = Budget(name: name, startDate: date(day: startDay), endDate: date(day: endDay), workspace: workspace)
            context.insert(budget)
            if linkDefaultCard {
                context.insert(BudgetCardLink(budget: budget, card: card))
            }
            return budget
        }

        func apply(to budget: Budget, offer: Bool = true) throws -> BudgetPresetApplicationService.Result {
            try BudgetPresetApplicationService.apply(
                preset, to: budget, in: workspace, requiresMatchingCardAndDates: offer, modelContext: context
            )
        }

        func apply(to budgets: [Budget]) throws -> BudgetPresetApplicationService.Result {
            try BudgetPresetApplicationService.apply(
                preset, to: budgets, in: workspace, requiresMatchingCardAndDates: true, modelContext: context
            )
        }

        func expenses() throws -> [PlannedExpense] {
            try context.fetch(FetchDescriptor<PlannedExpense>())
        }
    }
}
