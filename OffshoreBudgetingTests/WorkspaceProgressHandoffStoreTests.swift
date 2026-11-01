import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct WorkspaceProgressHandoffStoreTests {
    private func withStore(_ body: (WorkspaceProgressHandoffStore, UserDefaults) throws -> Void) throws {
        let suiteName = "WorkspaceProgressHandoffStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(WorkspaceProgressHandoffStore(defaults: defaults), defaults)
    }

    @Test func ordinaryLaunchHasNoPendingRequest() throws {
        try withStore { store, _ in
            #expect(store.pendingWorkspaceID == nil)
            #expect(!store.consume(workspaceID: UUID()))
        }
    }

    @Test func requestSurvivesStoreRecreationUntilPresentationClaimsIt() throws {
        try withStore { store, defaults in
            let workspaceID = UUID()
            store.enqueue(workspaceID: workspaceID)

            let reloaded = WorkspaceProgressHandoffStore(defaults: defaults)
            #expect(reloaded.pendingWorkspaceID == workspaceID)
            #expect(reloaded.consume(workspaceID: workspaceID))
            #expect(store.pendingWorkspaceID == nil)
            #expect(defaults.string(forKey: WorkspaceProgressHandoffStore.pendingWorkspaceIDKey) == nil)
        }
    }

    @Test func twoScenesCannotConsumeTheSameRequest() throws {
        try withStore { firstScene, defaults in
            let secondScene = WorkspaceProgressHandoffStore(defaults: defaults)
            let workspaceID = UUID()
            firstScene.enqueue(workspaceID: workspaceID)

            #expect(firstScene.consume(workspaceID: workspaceID))
            #expect(!secondScene.consume(workspaceID: workspaceID))
            #expect(secondScene.pendingWorkspaceID == nil)
        }
    }

    @Test func anotherWorkspaceCannotConsumeOrReplaceThePendingTarget() throws {
        try withStore { store, _ in
            let intendedWorkspaceID = UUID()
            store.enqueue(workspaceID: intendedWorkspaceID)

            #expect(!store.consume(workspaceID: UUID()))
            #expect(store.pendingWorkspaceID == intendedWorkspaceID)
        }
    }

    @Test func completionReplacesAnOlderUnpresentedRequest() throws {
        try withStore { store, _ in
            let olderWorkspaceID = UUID()
            let currentWorkspaceID = UUID()
            store.enqueue(workspaceID: olderWorkspaceID)
            store.enqueue(workspaceID: currentWorkspaceID)

            #expect(store.pendingWorkspaceID == currentWorkspaceID)
            #expect(!store.consume(workspaceID: olderWorkspaceID))
            #expect(store.consume(workspaceID: currentWorkspaceID))
        }
    }

    @Test func cancelLeavesUnrelatedPreferencesIntact() throws {
        try withStore { store, defaults in
            defaults.set(true, forKey: "general_hideWorkspaceProgress_some-workspace")
            defaults.set(true, forKey: OnboardingResetService.didChooseDataSourceKey)
            store.enqueue(workspaceID: UUID())
            store.cancel()

            #expect(store.pendingWorkspaceID == nil)
            #expect(defaults.bool(forKey: "general_hideWorkspaceProgress_some-workspace"))
            #expect(defaults.bool(forKey: OnboardingResetService.didChooseDataSourceKey))
        }
    }

    @Test func repeatOnboardingCancelsOldRequestAndCanQueueFreshCompletion() throws {
        try withStore { store, defaults in
            defaults.set(true, forKey: OnboardingResetService.didChooseDataSourceKey)
            defaults.set(true, forKey: OnboardingResetService.didCompleteOnboardingKey)
            store.enqueue(workspaceID: UUID())

            OnboardingResetService.repeatOnboarding(defaults: defaults)

            #expect(store.pendingWorkspaceID == nil)
            #expect(!defaults.bool(forKey: OnboardingResetService.didCompleteOnboardingKey))
            #expect(defaults.bool(forKey: OnboardingResetService.didChooseDataSourceKey))

            let workspaceID = UUID()
            store.enqueue(workspaceID: workspaceID)
            #expect(store.pendingWorkspaceID == workspaceID)
        }
    }

    @Test func invalidPersistedWorkspaceIdentifierDoesNotResolveToAnotherWorkspace() throws {
        try withStore { store, defaults in
            defaults.set("invalid-workspace-id", forKey: WorkspaceProgressHandoffStore.pendingWorkspaceIDKey)
            #expect(store.pendingWorkspaceID == nil)
            #expect(!store.consume(workspaceID: UUID()))
            store.cancel()
            #expect(defaults.string(forKey: WorkspaceProgressHandoffStore.pendingWorkspaceIDKey) == nil)
        }
    }

    @Test func coordinatorClaimsOneWindowAndConsumesItsRequestExactlyOnce() throws {
        try withStore { store, defaults in
            let coordinator = WorkspaceProgressHandoffCoordinator()
            let workspaceID = UUID()
            let ownerID = UUID()
            let competingOwnerID = UUID()
            store.enqueue(workspaceID: workspaceID)

            #expect(!coordinator.isPresenting)
            #expect(coordinator.claim(workspaceID: workspaceID, ownerID: ownerID, store: store))
            #expect(store.pendingWorkspaceID == nil)
            #expect(coordinator.isPresenting)
            #expect(coordinator.ownerID == ownerID)

            let competingStore = WorkspaceProgressHandoffStore(defaults: defaults)
            #expect(!coordinator.claim(workspaceID: workspaceID, ownerID: competingOwnerID, store: competingStore))
            #expect(coordinator.ownerID == ownerID)
        }
    }

    @Test func coordinatorDoesNotConsumeAnotherWorkspacesRequest() throws {
        try withStore { store, _ in
            let coordinator = WorkspaceProgressHandoffCoordinator()
            let intendedWorkspaceID = UUID()
            store.enqueue(workspaceID: intendedWorkspaceID)

            #expect(!coordinator.claim(workspaceID: UUID(), ownerID: UUID(), store: store))
            #expect(store.pendingWorkspaceID == intendedWorkspaceID)
            #expect(!coordinator.isPresenting)
            #expect(coordinator.ownerID == nil)
        }
    }

    @Test func onlyThePresentingOwnerCanReleaseItsReservation() throws {
        try withStore { store, _ in
            let coordinator = WorkspaceProgressHandoffCoordinator()
            let ownerID = UUID()
            let workspaceID = UUID()
            store.enqueue(workspaceID: workspaceID)
            #expect(coordinator.claim(workspaceID: workspaceID, ownerID: ownerID, store: store))

            coordinator.finish(ownerID: UUID())

            #expect(coordinator.isPresenting)
            #expect(coordinator.ownerID == ownerID)
            #expect(store.pendingWorkspaceID == nil)

            coordinator.finish(ownerID: ownerID)
            #expect(!coordinator.isPresenting)
            #expect(coordinator.ownerID == nil)
        }
    }

    @Test func dismissalAllowsALaterOnboardingRequestToBeClaimedByAnotherWindow() throws {
        try withStore { store, _ in
            let coordinator = WorkspaceProgressHandoffCoordinator()
            let workspaceID = UUID()
            let firstOwnerID = UUID()
            let nextOwnerID = UUID()
            store.enqueue(workspaceID: workspaceID)
            #expect(coordinator.claim(workspaceID: workspaceID, ownerID: firstOwnerID, store: store))

            store.enqueue(workspaceID: workspaceID)
            #expect(!coordinator.claim(workspaceID: workspaceID, ownerID: nextOwnerID, store: store))
            #expect(store.pendingWorkspaceID == workspaceID)
            #expect(coordinator.ownerID == firstOwnerID)

            coordinator.finish(ownerID: firstOwnerID)

            #expect(coordinator.claim(workspaceID: workspaceID, ownerID: nextOwnerID, store: store))
            #expect(coordinator.ownerID == nextOwnerID)
            #expect(store.pendingWorkspaceID == nil)
        }
    }

    @Test func successfulEraseClearsThePendingRequest() throws {
        try withStore { store, defaults in
            let schema = makeSchema()
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: configuration)
            let context = ModelContext(container)
            let workspace = Workspace(name: "Erase target", hexColor: "#3B82F6")
            context.insert(workspace)
            try context.save()
            store.enqueue(workspaceID: workspace.id)

            try AppResetService.eraseAllLocalData(modelContext: context, defaults: defaults)

            #expect(store.pendingWorkspaceID == nil)
            #expect(try context.fetch(FetchDescriptor<Workspace>()).isEmpty)
        }
    }

    @Test func failedErasePreservesThePendingRequestAndPersistedWorkspace() throws {
        try withStore { store, defaults in
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("HandoffReadOnlyErase-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("Local.store")
            let workspaceID = try seedWorkspace(at: url)
            store.enqueue(workspaceID: workspaceID)

            let schema = makeSchema()
            let configuration = ModelConfiguration(schema: schema, url: url, allowsSave: false, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: configuration)
            let context = ModelContext(container)
            context.autosaveEnabled = false

            #expect(throws: (any Error).self) {
                try AppResetService.eraseAllLocalData(modelContext: context, defaults: defaults)
            }

            #expect(store.pendingWorkspaceID == workspaceID)
            let persisted = try ModelContext(container).fetch(FetchDescriptor<Workspace>())
            #expect(persisted.map(\.id) == [workspaceID])
        }
    }

    private func seedWorkspace(at url: URL) throws -> UUID {
        let schema = makeSchema()
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(container)
        let workspace = Workspace(name: "Preserved workspace", hexColor: "#3B82F6")
        context.insert(workspace)
        try context.save()
        return workspace.id
    }

    private func makeSchema() -> Schema {
        Schema([
            Workspace.self, Budget.self, BudgetCategoryLimit.self, Card.self,
            BudgetCardLink.self, BudgetPresetLink.self, Offshore.Category.self, Preset.self,
            PlannedExpense.self, VariableExpense.self, AllocationAccount.self,
            ExpenseAllocation.self, AllocationSettlement.self, SavingsAccount.self,
            SavingsLedgerEntry.self, ImportMerchantRule.self, AssistantAliasRule.self,
            MarinaChatSession.self, IncomeSeries.self, Income.self
        ])
    }
}
