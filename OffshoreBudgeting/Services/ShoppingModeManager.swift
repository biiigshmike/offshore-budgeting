import Foundation
import Combine

#if canImport(ActivityKit)
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

    private init() {
        refreshIfExpired()
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

    func start(hours: Int) {
        SpendingSessionStore.activate(hours: hours)
        refreshIfExpired()
        ShoppingModeSuggestionService.shared.clearCooldownsIfSessionChanged(newSessionID: status.sessionID)
        ShoppingModeLocationService.shared.startMonitoringIfPossible()

        startOrRefreshLiveActivity()
    }

    func end() {
        SpendingSessionStore.end()
        ShoppingModeLocationService.shared.stopMonitoringAllRegions()
        ShoppingModeSuggestionService.shared.resetAllCooldowns()
        endLiveActivity()
        status = .inactive
    }

    func extendByThirtyMinutes() {
        guard SpendingSessionStore.extend(minutes: 30) != nil else { return }
        refreshIfExpired()
        ShoppingModeLocationService.shared.startMonitoringIfPossible()
    }

    func refreshIfExpired(now: Date = .now) {
        let expiresAt = SpendingSessionStore.expirationDate(now: now)
        guard let expiresAt else {
            let wasActive = status.isActive
            status = .inactive
            if wasActive {
                ShoppingModeLocationService.shared.stopMonitoringAllRegions()
                ShoppingModeSuggestionService.shared.resetAllCooldowns()
                endLiveActivity()
            }
            return
        }

        let startedAt = SpendingSessionStore.startDate(now: now)
        let sessionID = SpendingSessionStore.sessionID(now: now)
        let remaining = max(0, Int(expiresAt.timeIntervalSince(now)))

        status = ShoppingModeStatus(
            isActive: true,
            startedAt: startedAt,
            expiresAt: expiresAt,
            remainingSeconds: remaining,
            sessionID: sessionID
        )

        ShoppingModeSuggestionService.shared.clearCooldownsIfSessionChanged(newSessionID: sessionID)
        startOrRefreshLiveActivity()
    }

    // MARK: - Live Activity

    private func startOrRefreshLiveActivity() {
        #if canImport(ActivityKit)
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
                await existing.update(
                    ActivityContent(
                        state: state,
                        staleDate: expiresAt,
                        relevanceScore: Self.liveActivityRelevanceScore
                    )
                )
            } else {
                do {
                    _ = try Activity<ShoppingModeActivityAttributes>.request(
                        attributes: attributes,
                        content: ActivityContent(
                            state: state,
                            staleDate: expiresAt,
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
        #if canImport(ActivityKit)
        Task {
            for activity in Activity<ShoppingModeActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        #endif
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
    static let maxMonitoredRegions = 20
    static let searchRadiusMeters: Double = 12_000

    static let fallbackMerchants: [ShoppingModeMerchant] = [
        ShoppingModeMerchant(
            id: "starbucks_1",
            name: "Starbucks",
            latitude: 37.785834,
            longitude: -122.406417,
            radiusMeters: 120,
            categoryHint: "Coffee"
        ),
        ShoppingModeMerchant(
            id: "target_1",
            name: "Target",
            latitude: 37.784216,
            longitude: -122.407150,
            radiusMeters: 180,
            categoryHint: "Shopping"
        ),
        ShoppingModeMerchant(
            id: "costco_1",
            name: "Costco",
            latitude: 37.770367,
            longitude: -122.391302,
            radiusMeters: 220,
            categoryHint: "Groceries"
        )
    ]
}
