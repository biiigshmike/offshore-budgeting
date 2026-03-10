import Foundation
import Combine

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif

#if canImport(UIKit)
import UIKit
#endif

// MARK: - ShoppingModeStatus

struct ShoppingModeStatus: Equatable {
    let isActive: Bool
    let startedAt: Date?
    let expiresAt: Date?
    let remainingSeconds: Int
    let sessionID: String?

    static let inactive = ShoppingModeStatus(
        isActive: false,
        startedAt: nil,
        expiresAt: nil,
        remainingSeconds: 0,
        sessionID: nil
    )
}

// MARK: - ShoppingModeManager

@MainActor
final class ShoppingModeManager: ObservableObject {
    static let shared = ShoppingModeManager()
    private static let liveActivityRelevanceScore: Double = 80

    @Published private(set) var status: ShoppingModeStatus = .inactive
    private var expiryTask: Task<Void, Never>?

    private enum SessionEndReason: String {
        case manual
        case refreshDetectedExpired
        case invalidSession
        case expiryTask
    }

    private init() {
        refreshIfExpired()
    }

    deinit {
        expiryTask?.cancel()
    }

    enum DeepLink {
        static let scheme = "offshore"
        static let stopPath = "/excursion/stop"
        static let extendThirtyPath = "/excursion/extend30"

        static var stopURL: URL? {
            URL(string: "\(scheme)://action\(stopPath)")
        }

        static var extendThirtyURL: URL? {
            URL(string: "\(scheme)://action\(extendThirtyPath)")
        }
    }

    func start(hours: Int) async -> ShoppingModeStartResult {
        await startSession(durationLabel: "\(hours) hour") {
            SpendingSessionStore.activate(hours: hours)
        }
    }

    private func startSession(
        durationLabel: String,
        activate: () -> Void
    ) async -> ShoppingModeStartResult {
        let blockers = await ShoppingModeReadinessEvaluator.shared.evaluate()
        guard blockers.isEmpty else {
            return .blocked(blockers)
        }

        activate()
        refreshIfExpired()
        ShoppingModeSuggestionService.shared.clearCooldownsIfSessionChanged(newSessionID: status.sessionID)
        ShoppingModeLocationService.shared.startMonitoringIfPossible()

        startOrRefreshLiveActivity()
        #if DEBUG
        if let sessionID = status.sessionID, let expiresAt = status.expiresAt {
            debugLog(
                "Started \(durationLabel) session id=\(sessionID) expiresAt=\(debugTimestamp(expiresAt))"
            )
        }
        #endif
        return .started(expiresAt: status.expiresAt ?? .now)
    }

    func end() {
        finishSession(reason: .manual)
    }

    func extendByThirtyMinutes() {
        guard SpendingSessionStore.extend(minutes: 30) != nil else { return }
        refreshIfExpired()
        ShoppingModeLocationService.shared.startMonitoringIfPossible()
    }

    func refreshIfExpired(now: Date = .now) {
        let expiresAt = SpendingSessionStore.expirationDate(now: now)
        guard let expiresAt else {
            cancelExpiryTask()
            #if DEBUG
            if status.isActive {
                debugLog("refreshIfExpired detected an expired session at \(debugTimestamp(now))")
            }
            #endif
            status = .inactive
            ShoppingModeLocationService.shared.stopMonitoringAllRegions()
            ShoppingModeSuggestionService.shared.resetAllCooldowns()
            endLiveActivity()
            return
        }

        let startedAt = SpendingSessionStore.startDate(now: now)
        guard let sessionID = SpendingSessionStore.sessionID(now: now) else {
            finishSession(reason: .invalidSession)
            return
        }
        let remaining = max(0, Int(expiresAt.timeIntervalSince(now)))

        status = ShoppingModeStatus(
            isActive: true,
            startedAt: startedAt,
            expiresAt: expiresAt,
            remainingSeconds: remaining,
            sessionID: sessionID
        )

        scheduleExpiryTask(sessionID: sessionID, expiresAt: expiresAt)
        ShoppingModeSuggestionService.shared.clearCooldownsIfSessionChanged(newSessionID: sessionID)
        startOrRefreshLiveActivity()
    }

    // MARK: - Live Activity

    private func startOrRefreshLiveActivity() {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        guard status.isActive, let expiresAt = status.expiresAt, let sessionID = status.sessionID else {
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard Self.shouldUseLiveActivitySurface else { return }

        let attributes = ShoppingModeActivityAttributes(
            sessionID: sessionID,
            startDate: status.startedAt ?? .now,
            endDate: expiresAt
        )

        let state = ShoppingModeActivityAttributes.ContentState(
            endDate: expiresAt,
            statusText: "Excursion mode active"
        )

        Task {
            for activity in Activity<ShoppingModeActivityAttributes>.activities {
                if activity.attributes.sessionID != sessionID {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }

            if let existing = Activity<ShoppingModeActivityAttributes>.activities.first(where: { $0.attributes.sessionID == sessionID }) {
                #if DEBUG
                debugLog("Updating Live Activity id=\(sessionID) endDate=\(debugTimestamp(expiresAt))")
                #endif
                await existing.update(
                    ActivityContent(
                        state: state,
                        staleDate: nil,
                        relevanceScore: Self.liveActivityRelevanceScore
                    )
                )
            } else {
                do {
                    #if DEBUG
                    debugLog("Requesting Live Activity id=\(sessionID) endDate=\(debugTimestamp(expiresAt))")
                    #endif
                    _ = try Activity<ShoppingModeActivityAttributes>.request(
                        attributes: attributes,
                        content: ActivityContent(
                            state: state,
                            staleDate: nil,
                            relevanceScore: Self.liveActivityRelevanceScore
                        )
                    )
                } catch {
                    print("[ShoppingModeManager] Live Activity request failed: \(error.localizedDescription)")
                }
            }
        }
        #endif
    }

    private func endLiveActivity() {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        Task {
            #if DEBUG
            let requestedAt = Date.now
            debugLog("Calling endLiveActivity at \(debugTimestamp(requestedAt))")
            #endif
            for activity in Activity<ShoppingModeActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        #endif
    }

    private func finishSession(reason: SessionEndReason) {
        cancelExpiryTask()
        #if DEBUG
        if let expiresAt = status.expiresAt {
            let now = Date.now
            let delta = now.timeIntervalSince(expiresAt)
            debugLog(
                "finishSession reason=\(reason.rawValue) at \(debugTimestamp(now)) deltaFromExpiry=\(String(format: "%.2f", delta))s"
            )
        } else {
            debugLog("finishSession reason=\(reason.rawValue) with no active expiry")
        }
        #endif
        SpendingSessionStore.end()
        ShoppingModeLocationService.shared.stopMonitoringAllRegions()
        ShoppingModeSuggestionService.shared.resetAllCooldowns()
        endLiveActivity()
        status = .inactive
    }

    private func scheduleExpiryTask(sessionID: String, expiresAt: Date) {
        cancelExpiryTask()
        #if DEBUG
        debugLog("Scheduling expiry task id=\(sessionID) target=\(debugTimestamp(expiresAt))")
        #endif

        expiryTask = Task { [weak self] in
            let delay = max(0, expiresAt.timeIntervalSinceNow)
            if delay > 0 {
                let duration = Duration.seconds(delay)
                try? await Task.sleep(for: duration)
            }

            guard Task.isCancelled == false else { return }

            await MainActor.run {
                guard let self else { return }
                guard self.status.isActive, self.status.sessionID == sessionID else { return }
                guard let currentExpiry = self.status.expiresAt, currentExpiry <= .now else { return }
                #if DEBUG
                self.debugLog(
                    "Expiry task woke for id=\(sessionID) at \(self.debugTimestamp(.now))"
                )
                #endif
                self.finishSession(reason: .expiryTask)
            }
        }
    }

    private func cancelExpiryTask() {
        expiryTask?.cancel()
        expiryTask = nil
    }

    private static var shouldUseLiveActivitySurface: Bool {
        #if canImport(UIKit)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    @discardableResult
    func handleDeepLink(_ url: URL) -> Bool {
        guard url.scheme == DeepLink.scheme else { return false }

        let path: String
        if url.host == "action" {
            path = url.path
        } else {
            path = url.host.map { "/\($0)\(url.path)" } ?? url.path
        }

        switch path {
        case DeepLink.stopPath:
            end()
            return true
        case DeepLink.extendThirtyPath:
            extendByThirtyMinutes()
            return true
        default:
            return false
        }
    }

    #if DEBUG
    private func debugLog(_ message: String) {
        print("[ShoppingModeManager] \(message)")
    }

    private func debugTimestamp(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .standard)
    }
    #endif
}

// MARK: - ShoppingModeMerchant

struct ShoppingModeMerchant: Equatable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let radiusMeters: Double
    let categoryHint: String
}

// MARK: - ShoppingModeMerchantCatalog

enum ShoppingModeMerchantCatalog {
    static let maxMonitoredRegions = ShoppingModeTuning.maxMonitoredRegions
    static let searchRadiusMeters: Double = ShoppingModeTuning.localSearchRadiusMeters
}

// MARK: - ShoppingModeTuning

enum ShoppingModeTuning {
    static let maxMonitoredRegions = 20
    static let localSearchRadiusMeters: Double = 2_500
    static let refreshDistanceMeters: Double = 250
    static let minimumRefreshIntervalSeconds: TimeInterval = 120
    static let poiRetryIntervalSeconds: TimeInterval = 60
    static let maxPOIRetryAttempts = 3
    static let startupInsideCollectionWindowSeconds: TimeInterval = 1
    static let startupRouteSelectionMaxCandidates = 5
    static let startupRouteLookupTimeoutSeconds: TimeInterval = 2
    static let startupRouteOutlierCrowMultiplier: Double = 4
    static let startupRouteOutlierExtraMeters: Double = 300
    static let globalNotificationCooldownSeconds: TimeInterval = 10 * 60
    static let perMerchantNotificationCooldownSeconds: TimeInterval = 15 * 60
}
