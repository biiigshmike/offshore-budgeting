import Foundation
import Testing
@testable import Offshore

@MainActor
struct HomeViewModelDateTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.firstWeekday = 2
        return value
    }
    private var today: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 13))! }
    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
    private func model(_ id: UUID, defaults: UserDefaults, period: BudgetingPeriod = .monthly) -> HomeViewModel {
        let fixedNow = today
        return HomeViewModel(workspaceID: id, defaults: defaults, defaultBudgetingPeriodRaw: period.rawValue,
                             now: { fixedNow }, calendar: calendar, sleep: { _ in throw CancellationError() })
    }
    private func seed(_ id: UUID, defaults: UserDefaults, start: Date, end: Date, period: String = "custom") {
        HomeViewBootstrap.saveAppliedRangeSeed(.init(start: start, end: end, lastSyncedDefaultBudgetingPeriodRaw: period), workspaceID: id, defaults: defaults)
    }
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "HomeViewModelDateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    @Test func storedCustomRangeSeedsUntilAppearanceResetsToCanonicalPeriod() {
        withDefaults { defaults in
            let id = UUID()
            seed(id, defaults: defaults, start: day(-50), end: day(-40))
            let viewModel = model(id, defaults: defaults)
            #expect(viewModel.appliedStartDate == day(-50))
            #expect(viewModel.appliedEndDate == day(-40))
            #expect(viewModel.lastSyncedDefaultBudgetingPeriodRaw == "custom")
            viewModel.synchronizeAppliedRangeForAppearance(defaultBudgetingPeriodRaw: BudgetingPeriod.monthly.rawValue)
            let expected = BudgetingPeriod.monthly.defaultRange(containing: today, calendar: calendar)
            #expect(viewModel.appliedStartDate == expected.start)
            #expect(viewModel.appliedEndDate == expected.end)
            #expect(defaults.double(forKey: "home_appliedStartTimestamp_\(id.uuidString)") == expected.start.timeIntervalSince1970)
            #expect(defaults.double(forKey: "home_appliedEndTimestamp_\(id.uuidString)") == expected.end.timeIntervalSince1970)
            #expect(defaults.string(forKey: "home_lastSyncedDefaultBudgetingPeriod_\(id.uuidString)") == BudgetingPeriod.monthly.rawValue)
        }
    }

    @Test func legacyRangeLoadsWithoutWritingThenAppearancePersistsWorkspaceKeys() {
        withDefaults { defaults in
            let id = UUID()
            defaults.set(day(-8).timeIntervalSince1970, forKey: "home_appliedStartTimestamp")
            defaults.set(day(-3).timeIntervalSince1970, forKey: "home_appliedEndTimestamp")
            let viewModel = model(id, defaults: defaults)
            #expect(viewModel.appliedStartDate == day(-8))
            #expect(viewModel.appliedEndDate == day(-3))
            #expect(defaults.object(forKey: "home_appliedStartTimestamp_\(id.uuidString)") == nil)
            viewModel.synchronizeAppliedRangeForAppearance(defaultBudgetingPeriodRaw: BudgetingPeriod.monthly.rawValue)
            #expect(defaults.double(forKey: "home_appliedStartTimestamp_\(id.uuidString)") == viewModel.appliedStartDate.timeIntervalSince1970)
            #expect(defaults.double(forKey: "home_appliedEndTimestamp_\(id.uuidString)") == viewModel.appliedEndDate.timeIntervalSince1970)
            #expect(defaults.double(forKey: "home_appliedStartTimestamp") == day(-8).timeIntervalSince1970)
        }
    }

    @Test func invalidDraftEndClampsToStartAndPersists() {
        withDefaults { defaults in
            let id = UUID()
            let viewModel = model(id, defaults: defaults)
            viewModel.applyRange(start: day(4), end: day(-4))
            #expect(viewModel.appliedStartDate == day(4))
            #expect(viewModel.appliedEndDate == day(4))
            #expect(HomeViewBootstrap.storedAppliedRangeSeed(workspaceID: id, defaults: defaults)?.end == day(4))
        }
    }

    @Test func defaultPeriodChangeUsesInjectedCalendarAndUpdatesMarker() {
        withDefaults { defaults in
            let id = UUID()
            let viewModel = model(id, defaults: defaults)
            viewModel.applyDefaultBudgetingPeriod(BudgetingPeriod.weekly.rawValue)
            let expected = BudgetingPeriod.weekly.defaultRange(containing: today, calendar: calendar)
            #expect(viewModel.appliedStartDate == expected.start)
            #expect(viewModel.appliedEndDate == expected.end)
            #expect(viewModel.lastSyncedDefaultBudgetingPeriodRaw == BudgetingPeriod.weekly.rawValue)
            #expect(HomeViewBootstrap.storedAppliedRangeSeed(workspaceID: id, defaults: defaults)?.lastSyncedDefaultBudgetingPeriodRaw == BudgetingPeriod.weekly.rawValue)
        }
    }

    @Test func externalDefaultsReloadRefreshesActiveSnapshotAndCacheWithoutWriteback() {
        withDefaults { defaults in
            let workspace = Workspace(name: "Personal", hexColor: "#FFFFFF")
            let viewModel = model(workspace.id, defaults: defaults)
            let near = PlannedExpense(title: "Near", plannedAmount: 5, expenseDate: day(1), workspace: workspace)
            let later = PlannedExpense(title: "Later", plannedAmount: 7, expenseDate: day(5), workspace: workspace)
            let cache = DetailViewSnapshotCache()
            let input = HomeDashboardData(workspaceID: workspace.id, budgets: [], plannedExpenses: [near, later], variableExpenses: [],
                startDate: viewModel.appliedStartDate, endDate: viewModel.appliedEndDate, excludeFuturePlannedExpenses: false, excludeFutureVariableExpenses: false)
            viewModel.appear(data: input, activation: .init(sectionRawValue: AppSection.home.rawValue, phase: .active, token: 1), cache: cache)
            #expect(viewModel.dashboardSnapshot.nextPlannedExpense?.id == near.id)
            seed(workspace.id, defaults: defaults, start: day(4), end: day(8), period: "externally synced")
            let before = defaults.dictionaryRepresentation() as NSDictionary
            viewModel.reloadAppliedRangeFromDefaults()
            #expect(viewModel.dashboardSnapshot.nextPlannedExpense?.id == later.id)
            #expect(viewModel.appliedStartDate == day(4))
            #expect(!viewModel.needsDashboardSnapshotRefresh)
            #expect(viewModel.lastSyncedDefaultBudgetingPeriodRaw == "externally synced")
            let updated = HomeDashboardData(workspaceID: workspace.id, budgets: [], plannedExpenses: [near, later], variableExpenses: [],
                startDate: day(4), endDate: day(8), excludeFuturePlannedExpenses: false, excludeFutureVariableExpenses: false)
            let stored: HomeDashboardSnapshot? = cache.snapshot(for: updated.cacheKey)
            #expect(stored?.nextPlannedExpense?.id == later.id)
            viewModel.reloadAppliedRangeFromDefaults()
            #expect(before.isEqual(to: defaults.dictionaryRepresentation()))
            viewModel.disappear()
        }
    }

    @Test func workspaceRangePreferencesStayIsolated() {
        withDefaults { defaults in
            let firstID = UUID()
            let secondID = UUID()
            let first = model(firstID, defaults: defaults)
            let second = model(secondID, defaults: defaults)
            first.applyRange(start: day(-2), end: day(2))
            second.applyRange(start: day(5), end: day(9))
            first.reloadAppliedRangeFromDefaults()
            #expect(first.appliedStartDate == day(-2))
            #expect(first.appliedEndDate == day(2))
            #expect(second.appliedStartDate == day(5))
            #expect(model(firstID, defaults: defaults).appliedStartDate == day(-2))
            #expect(model(secondID, defaults: defaults).appliedEndDate == day(9))
        }
    }
}
