import Foundation
import Testing
@testable import Offshore

@MainActor
struct HomeViewModelTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private var today: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 13))! }
    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
    private func workspace() -> Workspace { Workspace(name: "Personal", hexColor: "#FFFFFF") }
    private func expense(_ title: String, _ offset: Int, _ workspace: Workspace, source: UUID? = nil) -> PlannedExpense {
        PlannedExpense(title: title, plannedAmount: 10, expenseDate: day(offset), workspace: workspace, sourceBudgetID: source)
    }
    private func data(_ workspace: Workspace, planned: [PlannedExpense] = [], variable: [VariableExpense] = [], budgets: [Budget] = [], excludePlanned: Bool = false, excludeVariable: Bool = false, start: Date? = nil, end: Date? = nil) -> HomeDashboardData {
        HomeDashboardData(workspaceID: workspace.id, budgets: budgets, plannedExpenses: planned, variableExpenses: variable,
                          startDate: start ?? day(-10), endDate: end ?? day(10),
                          excludeFuturePlannedExpenses: excludePlanned, excludeFutureVariableExpenses: excludeVariable)
    }
    private func active(_ token: Int = 1) -> AppTabActivationContext {
        AppTabActivationContext(sectionRawValue: AppSection.home.rawValue, phase: .active, token: token)
    }
    private func model(_ workspace: Workspace, gate: SleepGate? = nil) -> HomeViewModel {
        let fixedNow = today
        return HomeViewModel(workspaceID: workspace.id, now: { fixedNow }, calendar: calendar, sleep: { _ in
            guard let gate else { throw CancellationError() }
            await gate.wait()
        })
    }

    @Test func snapshotScopesWorkspaceAndExcludesOrphansWithoutDeletingRecords() {
        let personal = workspace()
        let other = workspace()
        let budget = Budget(name: "October", startDate: day(-10), endDate: day(10), workspace: personal)
        let valid = expense("Generated", 0, personal, source: budget.id)
        let manual = expense("Manual", 0, personal)
        let orphan = expense("Orphan", 0, personal, source: UUID())
        let foreign = expense("Other", 0, other)
        let ownVariable = VariableExpense(descriptionText: "Own", amount: 5, transactionDate: today, workspace: personal)
        let foreignVariable = VariableExpense(descriptionText: "Other", amount: 6, transactionDate: today, workspace: other)
        let input = data(personal, planned: [valid, manual, orphan, foreign], variable: [ownVariable, foreignVariable], budgets: [budget])
        let snapshot = model(personal).snapshot(for: input)
        #expect(snapshot.plannedExpensesForHome.map(\.id) == [valid.id, manual.id])
        #expect(snapshot.calculationVariableExpensesForHome.map(\.id) == [ownVariable.id])
        #expect(input.plannedExpenses.count == 4)
        #expect(orphan.sourceBudgetID != nil)
        #expect(model(other).snapshot(for: input).plannedExpensesForHome.isEmpty)
    }

    @Test func futureCalculationPoliciesRemainIndependentOfVisibilityAndNextExpense() {
        let personal = workspace()
        let past = expense("Past", -1, personal)
        let future = expense("Future", 1, personal)
        let futureVariable = VariableExpense(descriptionText: "Future", amount: 5, transactionDate: day(1), workspace: personal)
        let input = data(personal, planned: [past, future], variable: [futureVariable], excludePlanned: true)
        let snapshot = model(personal).snapshot(for: input)
        #expect(snapshot.plannedExpensesForHome.count == 2)
        #expect(snapshot.calculationPlannedExpensesForHome.map(\.id) == [past.id])
        #expect(snapshot.calculationVariableExpensesForHome.map(\.id) == [futureVariable.id])
        #expect(snapshot.nextPlannedExpense?.id == future.id)
        let visible = PlannedExpenseFuturePolicy.filteredForVisibility(snapshot.plannedExpensesForHome, hideFuture: true, now: today, calendar: calendar)
        #expect(visible.map(\.id) == [past.id])
        let reverse = model(personal).snapshot(for: data(personal, planned: [future], variable: [futureVariable], excludeVariable: true))
        #expect(reverse.calculationPlannedExpensesForHome.count == 1)
        #expect(reverse.calculationVariableExpensesForHome.isEmpty)
    }

    @Test func nextExpenseHonorsTodayAndInclusiveSelectedRange() {
        let personal = workspace()
        let past = expense("Past", -1, personal)
        let boundary = expense("Boundary", 2, personal)
        let outside = expense("Outside", 3, personal)
        let snapshot = model(personal).snapshot(for: data(personal, planned: [outside, past, boundary], start: today, end: day(2)))
        #expect(snapshot.nextPlannedExpense?.id == boundary.id)
    }

    @Test func appearanceReusesCachedSnapshotAndActiveInputChangesRefreshImmediately() {
        let personal = workspace()
        let first = expense("First", 0, personal)
        let second = expense("Second", 1, personal)
        let input = data(personal, planned: [first])
        let cache = DetailViewSnapshotCache()
        let cached = HomeDashboardSnapshot(plannedExpensesForHome: [second], calculationPlannedExpensesForHome: [second], calculationVariableExpensesForHome: [], nextPlannedExpense: second)
        cache.store(cached, for: input.cacheKey)
        let viewModel = model(personal)
        viewModel.appear(data: input, activation: active(), cache: cache)
        #expect(viewModel.hasLoadedDashboardSnapshot)
        #expect(viewModel.dashboardSnapshot.plannedExpensesForHome.map(\.id) == [second.id])
        let updated = data(personal, planned: [first, second])
        viewModel.update(data: updated)
        #expect(viewModel.dashboardSnapshot.plannedExpensesForHome.count == 2)
        #expect(!viewModel.needsDashboardSnapshotRefresh)
        let stored: HomeDashboardSnapshot? = cache.snapshot(for: updated.cacheKey)
        #expect(stored?.plannedExpensesForHome.count == 2)
        viewModel.disappear()
    }

    @Test func inactiveUpdatesWaitForActivationAndForeignInputsCannotReplaceState() {
        let personal = workspace()
        let other = workspace()
        let first = expense("First", 0, personal)
        let second = expense("Second", 1, personal)
        let viewModel = model(personal)
        viewModel.appear(data: data(personal, planned: [first]), activation: active(), cache: DetailViewSnapshotCache())
        viewModel.activationChanged(to: .inactive)
        viewModel.update(data: data(personal, planned: [first, second]))
        #expect(viewModel.needsDashboardSnapshotRefresh)
        #expect(viewModel.dashboardSnapshot.plannedExpensesForHome.count == 1)
        viewModel.update(data: data(other, planned: [expense("Foreign", 0, other)]))
        viewModel.activationChanged(to: active(2))
        #expect(viewModel.dashboardSnapshot.plannedExpensesForHome.map(\.id) == [first.id, second.id])
        viewModel.disappear()
    }

    @Test func cancelledEnrichmentCannotRefreshAfterDisappearanceOrObsoleteActivation() async {
        let personal = workspace()
        let gate = SleepGate()
        let first = expense("First", 0, personal)
        let second = expense("Second", 1, personal)
        let viewModel = model(personal, gate: gate)
        viewModel.appear(data: data(personal, planned: [first]), activation: active(), cache: DetailViewSnapshotCache())
        await drainTasks()
        #expect(gate.pendingCount == 1)
        viewModel.disappear()
        viewModel.update(data: data(personal, planned: [second]))
        viewModel.activationChanged(to: active(2))
        gate.releaseAll()
        await drainTasks()
        #expect(viewModel.dashboardSnapshot.plannedExpensesForHome.map(\.id) == [first.id])
        #expect(viewModel.needsDashboardSnapshotRefresh)
        viewModel.appear(data: data(personal, planned: [second]), activation: active(3), cache: DetailViewSnapshotCache())
        #expect(viewModel.dashboardSnapshot.plannedExpensesForHome.map(\.id) == [second.id])
        await drainTasks()
        viewModel.disappear()
        gate.releaseAll()
        await drainTasks()
    }

    private func drainTasks() async {
        for _ in 0..<10 { await Task.yield() }
    }
}

/// Deliberately ignores task cancellation so tests exercise the result-publication guards too.
@MainActor
private final class SleepGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    var pendingCount: Int { continuations.count }
    func wait() async { await withCheckedContinuation { continuations.append($0) } }
    func releaseAll() {
        let pending = continuations
        continuations.removeAll()
        for continuation in pending { continuation.resume() }
    }
}
