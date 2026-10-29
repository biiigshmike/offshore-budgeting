import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Offshore

@MainActor
struct UncategorizedExpenseReviewTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Workspace.self, Budget.self, BudgetCategoryLimit.self, Card.self,
            BudgetCardLink.self, BudgetPresetLink.self, Offshore.Category.self, Preset.self,
            PlannedExpense.self, VariableExpense.self, AllocationAccount.self,
            ExpenseAllocation.self, AllocationSettlement.self, SavingsAccount.self,
            SavingsLedgerEntry.self, ImportMerchantRule.self, AssistantAliasRule.self,
            MarinaChatSession.self, IncomeSeries.self, Income.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    @Test func sessionStartsDisabledAndEnablingWaitsUntilNextForegroundSession() {
        let session = UncategorizedExpenseReviewSession()
        #expect(!session.isPending)
        #expect(session.generation == 0)

        session.update(phase: .active, enabled: false)
        #expect(!session.isPending)
        #expect(session.generation == 1)

        session.update(phase: .active, enabled: true)
        session.update(phase: .inactive, enabled: true)
        session.update(phase: .active, enabled: true)
        #expect(!session.isPending)
        #expect(session.generation == 1)

        session.update(phase: .background, enabled: true)
        session.update(phase: .inactive, enabled: true)
        session.update(phase: .active, enabled: true)
        #expect(session.isPending)
        #expect(session.generation == 2)
    }

    @Test func sessionConsumptionSurvivesTemporaryInactivityAndLockContentReconstruction() {
        let session = UncategorizedExpenseReviewSession()
        let workspaceID = UUID()
        session.update(phase: .active, enabled: true)
        session.selectWorkspace(workspaceID)
        #expect(session.isPending)
        session.consume()

        // The same owner outlives unlocked ContentView/AppRootView instances.
        let reconstructedContentSession = session
        reconstructedContentSession.update(phase: .inactive, enabled: true)
        reconstructedContentSession.update(phase: .active, enabled: true)
        reconstructedContentSession.selectWorkspace(workspaceID)
        #expect(!reconstructedContentSession.isPending)
        #expect(reconstructedContentSession.generation == 1)
        #expect(reconstructedContentSession.workspaceID == workspaceID)

        session.update(phase: .background, enabled: true)
        session.update(phase: .active, enabled: true)
        #expect(session.isPending)
        #expect(session.workspaceID == nil)
        #expect(session.generation == 2)
    }

    @Test func workspaceReadinessWaitsButSwitchingDoesNotOfferAnotherPrompt() {
        let session = UncategorizedExpenseReviewSession()
        let firstID = UUID()
        let secondID = UUID()
        session.update(phase: .active, enabled: true)
        session.selectWorkspace(nil)
        #expect(session.isPending)
        session.selectWorkspace(firstID)
        session.selectWorkspace(firstID)
        #expect(session.isPending)

        session.selectWorkspace(secondID)
        #expect(!session.isPending)
        session.selectWorkspace(firstID)
        #expect(!session.isPending)

        session.update(phase: .background, enabled: false)
        session.update(phase: .active, enabled: false)
        #expect(!session.isPending)
    }

    @Test func presentationReservationsRemainBusyUntilEveryPresenterReleases() {
        let activity = AppPresentationActivity()
        let formID = UUID()
        let tipID = UUID()
        #expect(!activity.isBusy)
        activity.setPresented(true, id: formID)
        activity.setPresented(true, id: formID)
        activity.setPresented(true, id: tipID)
        #expect(activity.reservations.count == 2)
        activity.setPresented(false, id: formID)
        #expect(activity.isBusy)
        #expect(activity.reservations == [tipID])
        activity.setPresented(false, id: UUID())
        #expect(activity.isBusy)
        activity.setPresented(false, id: tipID)
        #expect(!activity.isBusy)
    }

    @Test func expenseEligibilityScopesWorkspaceCategoryAndFutureVisibilityAcrossAllKinds() {
        let workspace = Workspace(name: "Personal", hexColor: "#000000")
        let otherWorkspace = Workspace(name: "Work", hexColor: "#FFFFFF")
        let category = Offshore.Category(name: "Food", hexColor: "#FF0000", workspace: workspace)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let todayStart = calendar.startOfDay(for: today)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: todayStart)!
        let debit = VariableExpense(descriptionText: "Debit", amount: 10, transactionDate: todayStart, workspace: workspace)
        let credit = VariableExpense(descriptionText: "Credit", amount: 20, kindRaw: VariableExpenseKind.credit.rawValue, transactionDate: todayStart.addingTimeInterval(1), workspace: workspace)
        let adjustment = VariableExpense(descriptionText: "Adjustment", amount: 30, kindRaw: VariableExpenseKind.adjustment.rawValue, transactionDate: todayStart.addingTimeInterval(2), workspace: workspace)
        let future = VariableExpense(descriptionText: "Future", amount: 40, transactionDate: tomorrow, workspace: workspace)
        let categorized = VariableExpense(descriptionText: "Categorized", amount: 50, transactionDate: todayStart, workspace: workspace, category: category)
        let foreign = VariableExpense(descriptionText: "Foreign", amount: 60, transactionDate: todayStart, workspace: otherWorkspace)
        let orphan = VariableExpense(descriptionText: "Orphan", amount: 70, transactionDate: todayStart)
        let expenses = [debit, foreign, future, categorized, adjustment, orphan, credit]

        let visible = UncategorizedExpenseReviewService.expenses(
            in: expenses, workspaceID: workspace.id, hideFuture: true, now: today, calendar: calendar
        )
        #expect(visible.map(\.id) == [adjustment.id, credit.id, debit.id])
        let includingFuture = UncategorizedExpenseReviewService.expenses(
            in: expenses, workspaceID: workspace.id, hideFuture: false, now: today, calendar: calendar
        )
        let expectedIDs: [UUID] = [future.id, adjustment.id, credit.id, debit.id]
        #expect(includingFuture.map(\.id) == expectedIDs)
        #expect(UncategorizedExpenseReviewService.expenses(in: [], workspaceID: workspace.id, hideFuture: false).isEmpty)
    }

    @Test func categoryEligibilityExcludesArchivedForeignAndUnownedCategories() {
        let workspace = Workspace(name: "Personal", hexColor: "#000000")
        let otherWorkspace = Workspace(name: "Work", hexColor: "#FFFFFF")
        let active = Offshore.Category(name: "Food", hexColor: "#FF0000", workspace: workspace)
        let archived = Offshore.Category(name: "Old", hexColor: "#FF0000", workspace: workspace, isArchived: true)
        let foreign = Offshore.Category(name: "Work", hexColor: "#FF0000", workspace: otherWorkspace)
        let unowned = Offshore.Category(name: "Unowned", hexColor: "#FF0000")
        let result = UncategorizedExpenseReviewService.categories(in: [archived, foreign, active, unowned], workspaceID: workspace.id)
        #expect(result.map(\.id) == [active.id])
        #expect(UncategorizedExpenseReviewService.categories(in: [archived], workspaceID: workspace.id).isEmpty)
    }

    @Test func saveUpdatesOnlySelectedCategoriesAndPersistsWithoutChangingTransactionDetails() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#000000")
        let card = Card(name: "Visa", workspace: workspace)
        let category = Offshore.Category(name: "Food", hexColor: "#FF0000", workspace: workspace)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let selected = VariableExpense(descriptionText: "Refund", amount: 32.50, kindRaw: VariableExpenseKind.credit.rawValue, transactionDate: date, workspace: workspace, card: card)
        let untouched = VariableExpense(descriptionText: "Later", amount: 99, transactionDate: date, workspace: workspace, card: card)
        context.insert(workspace)
        context.insert(card)
        context.insert(category)
        context.insert(selected)
        context.insert(untouched)
        try context.save()

        let count = try UncategorizedExpenseReviewService.save(selections: [selected.id: category.id], workspaceID: workspace.id, context: context)
        #expect(count == 1)
        #expect(selected.category?.id == category.id)
        #expect(untouched.category == nil)
        #expect(selected.descriptionText == "Refund")
        #expect(selected.amount == 32.50)
        #expect(selected.kind == .credit)
        #expect(selected.transactionDate == date)
        #expect(selected.workspace?.id == workspace.id)
        #expect(selected.card?.id == card.id)
        #expect(!context.hasChanges)

        let verificationContext = ModelContext(context.container)
        let selectedID = selected.id
        let persisted = try verificationContext.fetch(FetchDescriptor<VariableExpense>(predicate: #Predicate { $0.id == selectedID }))
        #expect(persisted.first?.category?.id == category.id)
    }

    @Test func saveRevalidatesDeletedCategorizedArchivedAndForeignSelections() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#000000")
        let otherWorkspace = Workspace(name: "Work", hexColor: "#FFFFFF")
        let active = Offshore.Category(name: "Food", hexColor: "#FF0000", workspace: workspace)
        let archived = Offshore.Category(name: "Old", hexColor: "#FF0000", workspace: workspace, isArchived: true)
        let foreignCategory = Offshore.Category(name: "Work", hexColor: "#FF0000", workspace: otherWorkspace)
        context.insert(workspace)
        context.insert(otherWorkspace)
        for category in [active, archived, foreignCategory] { context.insert(category) }
        let deleted = VariableExpense(descriptionText: "Deleted", amount: 1, transactionDate: .now, workspace: workspace)
        let categorized = VariableExpense(descriptionText: "Changed elsewhere", amount: 2, transactionDate: .now, workspace: workspace, category: active)
        let archivedSelection = VariableExpense(descriptionText: "Archived category", amount: 3, transactionDate: .now, workspace: workspace)
        let foreignSelection = VariableExpense(descriptionText: "Foreign category", amount: 4, transactionDate: .now, workspace: workspace)
        let foreignExpense = VariableExpense(descriptionText: "Foreign expense", amount: 5, transactionDate: .now, workspace: otherWorkspace)
        let missingCategory = VariableExpense(descriptionText: "Missing category", amount: 6, transactionDate: .now, workspace: workspace)
        for expense in [deleted, categorized, archivedSelection, foreignSelection, foreignExpense, missingCategory] { context.insert(expense) }
        try context.save()
        let deletedID = deleted.id
        context.delete(deleted)
        let selections = [
            deletedID: active.id, categorized.id: archived.id, archivedSelection.id: archived.id,
            foreignSelection.id: foreignCategory.id, foreignExpense.id: active.id,
            missingCategory.id: UUID(), UUID(): active.id
        ]
        var persistCalls = 0
        let count = try UncategorizedExpenseReviewService.save(
            selections: selections, workspaceID: workspace.id, context: context,
            persist: { persistCalls += 1 }
        )
        #expect(count == 0)
        #expect(persistCalls == 0)
        #expect(categorized.category?.id == active.id)
        #expect(archivedSelection.category == nil)
        #expect(foreignSelection.category == nil)
        #expect(foreignExpense.category == nil)
        #expect(missingCategory.category == nil)
    }

    @Test func emptySelectionsDoNotPersistOrMutate() throws {
        let context = try makeContext()
        var persistCalls = 0
        let count = try UncategorizedExpenseReviewService.save(
            selections: [:], workspaceID: UUID(), context: context,
            persist: { persistCalls += 1 }
        )
        #expect(count == 0)
        #expect(persistCalls == 0)
        #expect(!context.hasChanges)
    }

    @Test func failedSaveRestoresOnlyCategoriesAndStagedSelectionsCanBeRetried() throws {
        enum InjectedFailure: Error { case save }
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#000000")
        let category = Offshore.Category(name: "Food", hexColor: "#FF0000", workspace: workspace)
        let first = VariableExpense(descriptionText: "First", amount: 12, transactionDate: .now, workspace: workspace)
        let second = VariableExpense(descriptionText: "Second", amount: 24, transactionDate: .now, workspace: workspace)
        context.insert(workspace)
        context.insert(category)
        context.insert(first)
        context.insert(second)
        try context.save()
        workspace.name = "Unrelated pending edit"
        let selections = [first.id: category.id, second.id: category.id]
        var persistCalls = 0
        do {
            try UncategorizedExpenseReviewService.save(
                selections: selections, workspaceID: workspace.id, context: context,
                persist: {
                    persistCalls += 1
                    #expect(first.category?.id == category.id)
                    #expect(second.category?.id == category.id)
                    throw InjectedFailure.save
                }
            )
            Issue.record("The injected save failure should propagate")
        } catch InjectedFailure.save {
            #expect(first.category == nil)
            #expect(second.category == nil)
            #expect(workspace.name == "Unrelated pending edit")
            #expect(context.hasChanges)
        }
        #expect(persistCalls == 1)

        let count = try UncategorizedExpenseReviewService.save(selections: selections, workspaceID: workspace.id, context: context)
        #expect(count == 2)
        #expect(first.category?.id == category.id)
        #expect(second.category?.id == category.id)
        #expect(workspace.name == "Unrelated pending edit")
        #expect(!context.hasChanges)
    }
}
