import Foundation
import SwiftData
import XCTest
@testable import Offshore

#if DEBUG
@MainActor
final class ScreenshotStartupCoordinatorTests: XCTestCase {
    private enum SetupFailure: Error { case open, prepare }

    private func makeContainer() throws -> ModelContainer {
        let schema = OffshoreBudgetingApp.modelSchema
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    func testAppStorePaydayStoryHasExactTotalsWithoutHistoricalActivityLeakingIn() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        try DebugSeeder.seedAppStoreRefreshData(context: context)
        try context.save()
        let budget = try XCTUnwrap(context.fetch(FetchDescriptor<Budget>()).first { $0.name == "November 27 Payday" })
        let workspaceID = try XCTUnwrap(budget.workspace?.id)
        let range = DateRange(start: budget.startDate, end: budget.endDate, calendar: .current)
        let income = try context.fetch(FetchDescriptor<Income>()).filter {
            $0.workspace?.id == workspaceID && $0.isPlanned && $0.date >= range.start && $0.date <= range.end
        }.reduce(0) { $0 + $1.amount }
        let planned = BudgetPlannedExpenseStore.plannedExpenses(
            try context.fetch(FetchDescriptor<PlannedExpense>()),
            budgetID: budget.id,
            linkedCardIDs: Set((budget.cardLinks ?? []).compactMap { $0.card?.id }),
            range: range
        )
        XCTAssertEqual(income, 3500, accuracy: 0.001)
        XCTAssertEqual(planned.count, 7)
        XCTAssertEqual(planned.first(where: { $0.title == "Rent" })?.plannedAmount, 1000)
        XCTAssertEqual(Set(planned.compactMap { $0.category?.id }).count, 6)
        XCTAssertEqual(planned.reduce(0) { $0 + $1.plannedAmount }, 1660, accuracy: 0.001)
        XCTAssertEqual(income - planned.reduce(0) { $0 + $1.plannedAmount }, 1840, accuracy: 0.001)
        XCTAssertEqual(Calendar.current.component(.month, from: budget.startDate), 11)
        XCTAssertEqual(Calendar.current.component(.day, from: budget.startDate), 27)
        XCTAssertEqual(Calendar.current.component(.month, from: budget.endDate), 12)
        XCTAssertEqual(Calendar.current.component(.day, from: budget.endDate), 10)
        let futureTransactions = try context.fetch(FetchDescriptor<VariableExpense>()).filter {
            $0.workspace?.id == workspaceID && $0.transactionDate >= range.start && $0.transactionDate <= range.end
        }
        XCTAssertTrue(futureTransactions.isEmpty)
        let allIncomes = try context.fetch(FetchDescriptor<Income>()).filter { $0.workspace?.id == workspaceID }
        let allPlanned = try context.fetch(FetchDescriptor<PlannedExpense>()).filter { $0.workspace?.id == workspaceID }
        let allVariable = try context.fetch(FetchDescriptor<VariableExpense>()).filter { $0.workspace?.id == workspaceID }
        let received = allIncomes.filter { !$0.isPlanned }.reduce(0) { $0 + $1.amount }
        let spending = allPlanned.reduce(0) { $0 + SavingsMathService.plannedBudgetImpactAmount(for: $1) }
            + allVariable.reduce(0) { $0 + SavingsMathService.variableBudgetImpactAmount(for: $1) }
        XCTAssertGreaterThan(received - spending, 0, "The full dashboard range must retain positive actual savings")
        XCTAssertGreaterThanOrEqual(Set(allVariable.compactMap { $0.category?.id }).count, 6)
    }

    func testOpenFailureDoesNotPrepareOrPublishContainer() {
        var didPrepare = false
        let coordinator = ScreenshotStartupCoordinator(
            open: { throw SetupFailure.open },
            prepare: { _ in didPrepare = true }
        )
        XCTAssertNil(coordinator.container)
        XCTAssertNotNil(coordinator.failureMessage)
        XCTAssertFalse(didPrepare)
        XCTAssertThrowsError(try coordinator.requireContainer())
    }

    func testSeedOrValidationFailureDoesNotPublishOpenedContainer() throws {
        let candidate = try makeContainer()
        let coordinator = ScreenshotStartupCoordinator(
            open: { candidate },
            prepare: { _ in throw SetupFailure.prepare }
        )
        XCTAssertNil(coordinator.container)
        XCTAssertNotNil(coordinator.failureMessage)
        XCTAssertThrowsError(try coordinator.requireContainer())
    }

    func testRetryCanRecoverAfterPreparationFailure() throws {
        class ShouldFailBox {
            var value: Bool
            init(value: Bool) {
                self.value = value
            }
        }
        let candidate = try makeContainer()
        let shouldFailBox = ShouldFailBox(value: true)
        var preparations = 0
        let coordinator = ScreenshotStartupCoordinator(open: { candidate }, prepare: { container in
            XCTAssertTrue(container === candidate)
            preparations += 1
            if shouldFailBox.value { throw SetupFailure.prepare }
        })
        XCTAssertNil(coordinator.container)
        shouldFailBox.value = false
        coordinator.retry()
        XCTAssertTrue(try coordinator.requireContainer() === candidate)
        XCTAssertNil(coordinator.failureMessage)
        XCTAssertEqual(preparations, 2)
    }

    func testRetryClearsPreviouslyReadyContainerBeforePreparation() throws {
        let candidate = try makeContainer()
        var coordinator: ScreenshotStartupCoordinator?
        var wasClearedDuringRetry = false
        coordinator = ScreenshotStartupCoordinator(open: { candidate }, prepare: { _ in
            if let coordinator {
                wasClearedDuringRetry = coordinator.container == nil
            }
        })
        XCTAssertTrue(try XCTUnwrap(coordinator).requireContainer() === candidate)
        coordinator?.retry()
        XCTAssertTrue(wasClearedDuringRetry)
        XCTAssertTrue(try XCTUnwrap(coordinator).requireContainer() === candidate)
    }

    func testValidationRejectsNonScreenshotContainer() throws {
        let container = try makeContainer()
        XCTAssertThrowsError(try ScreenshotStartupCoordinator.validate(container: container))
    }

    func testSeedResetRefusesNonScreenshotContainerAndPreservesRecords() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let workspace = Workspace(name: "Preserve historical data", hexColor: "#123456")
        context.insert(workspace)
        try context.save()
        var attemptedSave = false
        XCTAssertThrowsError(try DebugSeeder.runIfNeeded(container: container, forceReset: true, beforeSave: {
            attemptedSave = true
        }))
        XCTAssertFalse(attemptedSave)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Workspace>()), 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Workspace>()).first?.id, workspace.id)
    }

    func testFirstSetupInitializesScreenshotPreferencesAndSelectsSeededWorkspace() throws {
        try withIsolatedDefaults { defaults in
            defaults.set(true, forKey: "icloud_useCloud")
            defaults.set(true, forKey: "icloud_activeUseCloud")
            defaults.set(UUID().uuidString, forKey: "selectedWorkspaceID")
            let workspaceID = UUID()
            ScreenshotStartupCoordinator.configurePreferences(workspaceID: workspaceID, defaults: defaults)
            XCTAssertEqual(defaults.string(forKey: "selectedWorkspaceID"), workspaceID.uuidString)
            XCTAssertTrue(defaults.bool(forKey: "didCompleteOnboarding"))
            XCTAssertTrue(defaults.bool(forKey: "onboarding_didChooseDataSource"))
            XCTAssertTrue(defaults.bool(forKey: "debug_screenshotInitialized"))
            XCTAssertTrue(defaults.bool(forKey: "didSeedDefaultWorkspaces"))
            XCTAssertFalse(defaults.bool(forKey: "icloud_useCloud"))
            XCTAssertFalse(defaults.bool(forKey: "icloud_activeUseCloud"))
            XCTAssertEqual(defaults.double(forKey: "icloud_bootstrapStartedAt"), 0)
        }
    }

    func testSubsequentSetupPreservesOnboardingReplayAndReplacesStaleWorkspaceSelection() throws {
        try withIsolatedDefaults { defaults in
            ScreenshotStartupCoordinator.configurePreferences(workspaceID: UUID(), defaults: defaults)
            OnboardingResetService.repeatOnboarding(defaults: defaults)
            let newWorkspaceID = UUID()
            ScreenshotStartupCoordinator.configurePreferences(workspaceID: newWorkspaceID, defaults: defaults)
            XCTAssertFalse(defaults.bool(forKey: "didCompleteOnboarding"))
            XCTAssertFalse(defaults.bool(forKey: "onboarding_didPressGetStarted"))
            XCTAssertEqual(defaults.integer(forKey: "onboarding_step"), 0)
            XCTAssertEqual(defaults.string(forKey: "selectedWorkspaceID"), newWorkspaceID.uuidString)
        }
    }

    func testExplicitResetRestoresCompletedOnboardingAfterInterruptedReplay() throws {
        try withIsolatedDefaults { defaults in
            ScreenshotStartupCoordinator.configurePreferences(workspaceID: UUID(), defaults: defaults)
            OnboardingResetService.repeatOnboarding(defaults: defaults)
            XCTAssertFalse(defaults.bool(forKey: "didCompleteOnboarding"))
            let newWorkspaceID = UUID()
            ScreenshotStartupCoordinator.configurePreferences(
                workspaceID: newWorkspaceID,
                defaults: defaults,
                resetOnboarding: true
            )
            XCTAssertTrue(defaults.bool(forKey: "didCompleteOnboarding"))
            XCTAssertTrue(defaults.bool(forKey: "onboarding_didChooseDataSource"))
            XCTAssertTrue(defaults.bool(forKey: "onboarding_didPressGetStarted"))
            XCTAssertEqual(defaults.integer(forKey: "onboarding_step"), 1)
            XCTAssertEqual(defaults.string(forKey: "selectedWorkspaceID"), newWorkspaceID.uuidString)
        }
    }

    private func withIsolatedDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "ScreenshotStartupCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}
#endif

