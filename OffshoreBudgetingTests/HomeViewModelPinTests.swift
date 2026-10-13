import Foundation
import Testing
@testable import Offshore

@MainActor
struct HomeViewModelPinTests {
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "HomeViewModelPinTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }
    private func model(_ id: UUID, defaults: UserDefaults, fallback: [UUID] = [], pushed: PinPushRecorder? = nil, gate: PinSleepGate? = nil) -> HomeViewModel {
        let pushed = pushed ?? PinPushRecorder()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return HomeViewModel(workspaceID: id, defaults: defaults, fallbackCardIDs: fallback,
            pushHomeLayout: { pushed.ids.append($0) }, now: { Date(timeIntervalSince1970: 1_800_316_800) }, calendar: calendar,
            sleep: { _ in
                guard let gate else { throw CancellationError() }
                await gate.wait()
            })
    }
    private func appear(_ viewModel: HomeViewModel) {
        viewModel.appear(data: HomeDashboardData(workspaceID: viewModel.workspaceID, budgets: [], plannedExpenses: [], variableExpenses: [],
            startDate: viewModel.appliedStartDate, endDate: viewModel.appliedEndDate, excludeFuturePlannedExpenses: false, excludeFutureVariableExpenses: false),
            activation: .init(sectionRawValue: AppSection.home.rawValue, phase: .active, token: 1), cache: DetailViewSnapshotCache())
    }

    @Test func savedPinsTakePriorityOverLegacyAndFallback() {
        withDefaults { defaults in
            let id = UUID()
            let saved: [HomePinnedItem] = [.widget(.income, .wide), .card(UUID(), .small)]
            HomePinnedItemsStore(workspaceID: id, defaults: defaults).save(saved)
            HomePinnedWidgetsStore(workspaceID: id, defaults: defaults).save([.whatIf])
            let pushes = PinPushRecorder()
            let viewModel = model(id, defaults: defaults, fallback: [UUID()], pushed: pushes)
            #expect(viewModel.pinnedItems == saved)
            #expect(pushes.ids.isEmpty)
        }
    }

    @Test func legacyAndEmptyUnifiedLayoutsRetainExistingFallbackBehavior() {
        withDefaults { defaults in
            let id = UUID()
            let legacyCard = UUID()
            HomePinnedItemsStore(workspaceID: id, defaults: defaults).save([])
            HomePinnedWidgetsStore(workspaceID: id, defaults: defaults).save([.whatIf, .income])
            HomePinnedCardsStore(workspaceID: id, defaults: defaults).save([legacyCard])
            #expect(model(id, defaults: defaults, fallback: [UUID()]).pinnedItems == [.widget(.whatIf, .small), .widget(.income, .small), .card(legacyCard, .small)])
            let freshID = UUID()
            let fallback = UUID()
            let fresh = model(freshID, defaults: defaults, fallback: [fallback])
            #expect(fresh.pinnedItems.first == .widget(.income, .small))
            #expect(fresh.pinnedItems.last == .card(fallback, .small))
        }
    }

    @Test func localEditsPersistOrderingSizesAndNormalizeStoreDuplicates() {
        withDefaults { defaults in
            let id = UUID()
            let pushes = PinPushRecorder()
            let viewModel = model(id, defaults: defaults, pushed: pushes)
            let card = UUID()
            viewModel.pinnedItems = [.card(card, .wide), .widget(.income, .small), .card(card, .small)]
            let store = HomePinnedItemsStore(workspaceID: id, defaults: defaults)
            #expect(store.load() == [.card(card, .wide), .widget(.income, .small)])
            viewModel.pinnedItems = [.widget(.income, .wide), .card(card, .small)]
            #expect(store.load() == viewModel.pinnedItems)
            viewModel.pinnedItems.removeLast()
            #expect(store.load() == [.widget(.income, .wide)])
            #expect(pushes.ids == [id, id, id])
            let unchanged = viewModel.pinnedItems
            viewModel.pinnedItems = unchanged
            #expect(pushes.ids.count == 3)
        }
    }

    @Test func syncedReloadDoesNotEchoButSubsequentLocalEditPushes() {
        withDefaults { defaults in
            let id = UUID()
            let pushes = PinPushRecorder()
            let viewModel = model(id, defaults: defaults, pushed: pushes)
            let remote: [HomePinnedItem] = [.widget(.spendTrends, .wide)]
            let store = HomePinnedItemsStore(workspaceID: id, defaults: defaults)
            store.importSyncSnapshot(remote, postsNotification: false)
            viewModel.reloadSyncedPinnedItems()
            #expect(viewModel.pinnedItems == remote)
            #expect(pushes.ids.isEmpty)
            viewModel.reloadSyncedPinnedItems()
            #expect(pushes.ids.isEmpty)
            viewModel.pinnedItems.append(.widget(.income, .small))
            #expect(pushes.ids == [id])
            #expect(store.load() == viewModel.pinnedItems)
            store.importSyncSnapshot([], postsNotification: false)
            viewModel.reloadSyncedPinnedItems()
            #expect(viewModel.pinnedItems.isEmpty)
            #expect(pushes.ids == [id])
        }
    }

    @Test func pruningRemovesOnlyMissingOrForeignPinReferences() {
        withDefaults { defaults in
            let workspace = Workspace(name: "Personal", hexColor: "#FFFFFF")
            let other = Workspace(name: "Work", hexColor: "#FFFFFF")
            let own = Card(name: "Own", workspace: workspace)
            let foreign = Card(name: "Foreign", workspace: other)
            let pushes = PinPushRecorder()
            let viewModel = model(workspace.id, defaults: defaults, pushed: pushes)
            viewModel.pinnedItems = [.widget(.income, .wide), .card(own.id, .small), .card(foreign.id, .wide), .card(UUID(), .small)]
            viewModel.updateAvailableCards([own, foreign])
            #expect(viewModel.pinnedItems == [.widget(.income, .wide), .card(own.id, .small)])
            #expect(own.workspace?.id == workspace.id)
            #expect(foreign.workspace?.id == other.id)
            #expect(own.name == "Own")
            #expect(foreign.name == "Foreign")
            #expect(pushes.ids == [workspace.id, workspace.id])
        }
    }

    @Test func delayedHousekeepingMigratesWithoutCloudPush() async {
        let suite = "HomeViewModelPinTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let workspace = Workspace(name: "Personal", hexColor: "#FFFFFF")
        let card = Card(name: "Card", workspace: workspace)
        let pushes = PinPushRecorder()
        let gate = PinSleepGate()
        let viewModel = model(workspace.id, defaults: defaults, fallback: [card.id], pushed: pushes, gate: gate)
        viewModel.updateAvailableCards([card], prune: false)
        appear(viewModel)
        await drainTasks()
        let store = HomePinnedItemsStore(workspaceID: workspace.id, defaults: defaults)
        #expect(store.load().isEmpty)
        gate.releaseAll()
        await drainTasks()
        #expect(store.load() == viewModel.pinnedItems)
        #expect(!store.load().isEmpty)
        #expect(pushes.ids.isEmpty)
        viewModel.disappear()
    }

    @Test func disappearanceAndActivationChangeCancelHousekeeping() async {
        let suite = "HomeViewModelPinTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        for disappear in [true, false] {
            let id = UUID()
            let pushes = PinPushRecorder()
            let gate = PinSleepGate()
            let viewModel = model(id, defaults: defaults, fallback: [UUID()], pushed: pushes, gate: gate)
            let initial = viewModel.pinnedItems
            appear(viewModel)
            await drainTasks()
            #expect(gate.pendingCount > 0)
            if disappear { viewModel.disappear() } else { viewModel.activationChanged(to: .inactive) }
            gate.releaseAll()
            await drainTasks()
            #expect(HomePinnedItemsStore(workspaceID: id, defaults: defaults).load().isEmpty)
            #expect(viewModel.pinnedItems == initial)
            #expect(pushes.ids.isEmpty)
            viewModel.disappear()
        }
    }

    private func drainTasks() async { for _ in 0..<10 { await Task.yield() } }
}

@MainActor
private final class PinPushRecorder { var ids: [UUID] = [] }

/// Ignores cancellation so stale-work publication checks are exercised after release.
@MainActor
private final class PinSleepGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    var pendingCount: Int { continuations.count }
    func wait() async { await withCheckedContinuation { continuations.append($0) } }
    func releaseAll() {
        let pending = continuations
        continuations.removeAll()
        for continuation in pending { continuation.resume() }
    }
}
