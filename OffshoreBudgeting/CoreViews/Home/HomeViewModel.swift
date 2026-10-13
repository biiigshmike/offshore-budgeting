import Foundation
import Observation

/// Owns Home's workflows; SwiftUI rendering and live database queries remain in the view.
@MainActor
@Observable
final class HomeViewModel {
    let workspaceID: UUID
    private(set) var dashboardSnapshot: HomeDashboardSnapshot = .empty
    private(set) var hasLoadedDashboardSnapshot = false
    private(set) var needsDashboardSnapshotRefresh = false

    @ObservationIgnored private var data: HomeDashboardData?
    @ObservationIgnored private var inputSignature: HomeDashboardData.Signature?
    @ObservationIgnored private var snapshotCache: DetailViewSnapshotCache?
    @ObservationIgnored private var activation: AppTabActivationContext = .inactive
    @ObservationIgnored private var isVisible = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var enrichmentTask: Task<Void, Never>?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let sleep: (UInt64) async throws -> Void

    init(
        workspaceID: UUID,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        sleep: @escaping (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.workspaceID = workspaceID
        self.now = now
        self.calendar = calendar
        self.sleep = sleep
    }

    func snapshot(for data: HomeDashboardData) -> HomeDashboardSnapshot {
        guard data.workspaceID == workspaceID else { return .empty }
        if hasLoadedDashboardSnapshot { return dashboardSnapshot }
        return HomeDashboardSnapshot.prepare(from: data, now: now(), calendar: calendar)
    }

    func appear(data: HomeDashboardData, activation: AppTabActivationContext, cache: DetailViewSnapshotCache) {
        guard data.workspaceID == workspaceID else { return }
        isVisible = true
        self.activation = activation
        snapshotCache = cache
        accept(data)
        if !hasLoadedDashboardSnapshot {
            if let cached: HomeDashboardSnapshot = cache.snapshot(for: data.cacheKey) {
                dashboardSnapshot = cached
                hasLoadedDashboardSnapshot = true
                TabFlickerDiagnostics.markEvent("homeDashboardSnapshotHydrated")
            } else {
                rebuildDashboardSnapshot(reason: "onAppearInitial")
            }
            needsDashboardSnapshotRefresh = false
        } else if needsDashboardSnapshotRefresh {
            requestRefresh(reason: "onAppearRefresh")
        }
        scheduleActivationEnrichment(reason: "onAppear")
    }

    func update(data: HomeDashboardData) {
        guard data.workspaceID == workspaceID else { return }
        let changed = inputSignature != data.signature
        accept(data)
        guard changed else { return }
        cancelRefresh(reason: "inputsChanged")
        if isVisible && activation.phase == .active {
            requestRefresh(reason: "inputsChanged")
        } else {
            needsDashboardSnapshotRefresh = true
        }
    }

    func activationChanged(to context: AppTabActivationContext) {
        guard context != activation else { return }
        activation = context
        cancelPendingWork(reason: "tabPhaseChanged")
        guard isVisible, isHomeActive else { return }
        if needsDashboardSnapshotRefresh {
            requestRefresh(reason: "tabActivationSettled")
            scheduleActivationEnrichment(reason: "tabActivationSettled")
        }
    }

    func disappear() {
        isVisible = false
        cancelPendingWork(reason: "onDisappear")
    }

    private var isHomeActive: Bool {
        activation.sectionRawValue == AppSection.home.rawValue && activation.phase == .active
    }

    private func accept(_ data: HomeDashboardData) {
        if inputSignature != data.signature { needsDashboardSnapshotRefresh = true }
        self.data = data
        inputSignature = data.signature
    }

    private func rebuildDashboardSnapshot(reason: String) {
        guard let data else { return }
        let start = DispatchTime.now().uptimeNanoseconds
        dashboardSnapshot = RootActivationDiagnostics.measure(
            "homeRootDerived", metadata: ["phase": activation.phase.rawValue, "token": String(activation.token)]
        ) {
            HomeDashboardSnapshot.prepare(from: data, now: now(), calendar: calendar)
        }
        snapshotCache?.store(dashboardSnapshot, for: data.cacheKey)
        hasLoadedDashboardSnapshot = true
        needsDashboardSnapshotRefresh = false
        TabFlickerDiagnostics.markEvent("homeDashboardSnapshotFinished", metadata: [
            "reason": reason,
            "elapsedMs": String(format: "%.1f", Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        ])
    }

    private func requestRefresh(reason: String) {
        cancelRefresh(reason: "reschedule")
        TabFlickerDiagnostics.markEvent("homeDashboardSnapshotScheduled", metadata: [
            "reason": reason, "phase": activation.phase.rawValue, "token": String(activation.token)
        ])
        guard isVisible else { needsDashboardSnapshotRefresh = true; return }
        if isHomeActive {
            rebuildDashboardSnapshot(reason: reason)
            return
        }
        needsDashboardSnapshotRefresh = true
        let expectedGeneration = generation
        let expectedToken = activation.token
        let expectedSignature = inputSignature
        let sleep = sleep
        refreshTask = Task { [weak self] in
            do { try await sleep(220_000_000) } catch { return }
            guard !Task.isCancelled, let self,
                  self.isVisible, self.isHomeActive, self.generation == expectedGeneration,
                  self.activation.token == expectedToken, self.inputSignature == expectedSignature else { return }
            self.rebuildDashboardSnapshot(reason: reason)
            self.refreshTask = nil
        }
    }

    private func scheduleActivationEnrichment(reason: String) {
        enrichmentTask?.cancel()
        let expectedGeneration = generation
        let expectedToken = activation.token
        let sleep = sleep
        enrichmentTask = Task { [weak self] in
            do { try await sleep(170_000_000) } catch { return }
            guard !Task.isCancelled, let self,
                  self.isVisible, self.isHomeActive, self.generation == expectedGeneration,
                  self.activation.token == expectedToken else { return }
            if self.needsDashboardSnapshotRefresh { self.requestRefresh(reason: "postSettleEnrichment") }
            TabFlickerDiagnostics.markEvent("homeActivationEnrichmentFinished", metadata: ["reason": reason])
            self.enrichmentTask = nil
        }
    }

    private func cancelRefresh(reason: String) {
        generation += 1
        guard refreshTask != nil else { return }
        refreshTask?.cancel()
        refreshTask = nil
        TabFlickerDiagnostics.markEvent("homeDashboardSnapshotCancelled", metadata: ["reason": reason])
    }

    private func cancelPendingWork(reason: String) {
        cancelRefresh(reason: reason)
        enrichmentTask?.cancel()
        enrichmentTask = nil
    }
}
