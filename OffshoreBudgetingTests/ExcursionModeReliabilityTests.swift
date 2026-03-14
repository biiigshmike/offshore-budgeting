import Foundation
import Testing

#if canImport(CoreLocation)
import CoreLocation
#endif

@testable import Offshore

@MainActor
struct ExcursionModeReliabilityTests {
    private let policy = ExcursionDetectionPolicy()
    private let scorer = ExcursionCandidateScorer()

    @Test func startupScoring_PrefersNearestCandidate() {
        let near = makeMerchant(id: "near", name: "Near Coffee", latitude: 37.7749, longitude: -122.4194, category: "Coffee")
        let far = makeMerchant(id: "far", name: "Far Coffee", latitude: 37.7795, longitude: -122.4194, category: "Coffee")
        let location = CLLocation(latitude: 37.7750, longitude: -122.4194)

        let ranked = scorer.rankedCandidates(
            merchants: [far, near],
            referenceLocation: location,
            insideRegionIDs: []
        )

        #expect(ranked.first?.merchant.id == near.id)
    }

    @Test func startupScoring_RouteOnlyBreaksTies() {
        let close = makeMerchant(id: "close", name: "Close Shop", latitude: 37.7750, longitude: -122.4194, category: "Shopping")
        let farther = makeMerchant(id: "farther", name: "Farther Shop", latitude: 37.7765, longitude: -122.4194, category: "Shopping")
        let location = CLLocation(latitude: 37.7749, longitude: -122.4194)

        let ranked = scorer.rankedCandidates(
            merchants: [close, farther],
            referenceLocation: location,
            insideRegionIDs: [],
            routeMetrics: [
                close.id: .init(distanceMeters: 900, expectedTravelTime: 600, status: .valid),
                farther.id: .init(distanceMeters: 100, expectedTravelTime: 60, status: .valid)
            ]
        )

        #expect(ranked.first?.merchant.id == close.id)
    }

    @Test func startupPolicy_RejectsPoorAccuracy() {
        let accepted = policy.acceptsStartupCandidate(
            accuracyMeters: 120,
            stableDuration: 12,
            consecutiveMatches: 3
        )

        #expect(accepted == false)
    }

    @Test func startupPolicy_AcceptsAfterTwoStableSamples() {
        let accepted = policy.acceptsStartupCandidate(
            accuracyMeters: 35,
            stableDuration: 4,
            consecutiveMatches: 2
        )

        #expect(accepted)
    }

    @Test func notificationGate_BlocksGlobalCooldown() {
        let decision = policy.notificationDecision(
            merchantID: "merchant",
            currentLocation: CLLocation(latitude: 37.0, longitude: -122.0),
            lastGlobalFireAt: Date.now.addingTimeInterval(-60),
            lastMerchantFireAt: nil,
            lastDeliveredMerchantID: nil,
            lastDeliveredLocation: nil,
            now: .now
        )

        #expect(decision.isAllowed == false)
        #expect(decision.reason == .globalCooldown)
    }

    @Test func notificationGate_BlocksSameMerchantWithoutEnoughMovement() {
        let decision = policy.notificationDecision(
            merchantID: "merchant",
            currentLocation: CLLocation(latitude: 37.0005, longitude: -122.0005),
            lastGlobalFireAt: Date.now.addingTimeInterval(-policy.globalNotificationCooldownSeconds - 1),
            lastMerchantFireAt: Date.now.addingTimeInterval(-policy.perMerchantNotificationCooldownSeconds - 1),
            lastDeliveredMerchantID: "merchant",
            lastDeliveredLocation: CLLocation(latitude: 37.0, longitude: -122.0),
            now: .now
        )

        #expect(decision.isAllowed == false)
        #expect(decision.reason == .insufficientMovement)
    }

    @Test func notificationGate_AllowsDifferentMerchantAfterCooldown() {
        let decision = policy.notificationDecision(
            merchantID: "merchant-b",
            currentLocation: CLLocation(latitude: 37.0015, longitude: -122.0015),
            lastGlobalFireAt: Date.now.addingTimeInterval(-policy.globalNotificationCooldownSeconds - 1),
            lastMerchantFireAt: nil,
            lastDeliveredMerchantID: "merchant-a",
            lastDeliveredLocation: CLLocation(latitude: 37.0, longitude: -122.0),
            now: .now
        )

        #expect(decision.isAllowed)
        #expect(decision.reason == nil)
    }

    @Test func movementRefreshPolicy_UsesWalkingThreshold() {
        let previous = CLLocation(latitude: 37.0, longitude: -122.0)
        let next = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.0012, longitude: -122.0),
            altitude: 0,
            horizontalAccuracy: 20,
            verticalAccuracy: 20,
            course: 0,
            speed: 1,
            timestamp: .now
        )
        let shouldRefresh = policy.shouldRefreshMovement(
            previousLocation: previous,
            previousDate: Date.now.addingTimeInterval(-50),
            newLocation: next,
            now: .now
        )

        #expect(shouldRefresh)
    }

    @Test func movementRefreshPolicy_RejectsShortDistance() {
        let previous = CLLocation(latitude: 37.0, longitude: -122.0)
        let next = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.0003, longitude: -122.0),
            altitude: 0,
            horizontalAccuracy: 20,
            verticalAccuracy: 20,
            course: 0,
            speed: 1,
            timestamp: .now
        )
        let shouldRefresh = policy.shouldRefreshMovement(
            previousLocation: previous,
            previousDate: Date.now.addingTimeInterval(-50),
            newLocation: next,
            now: .now
        )

        #expect(shouldRefresh == false)
    }

    @Test func movementRefreshPolicy_UsesDrivingThreshold() {
        let previous = CLLocation(latitude: 37.0, longitude: -122.0)
        let next = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.0025, longitude: -122.0),
            altitude: 0,
            horizontalAccuracy: 20,
            verticalAccuracy: 20,
            course: 0,
            speed: 12,
            timestamp: .now
        )
        let shouldRefresh = policy.shouldRefreshMovement(
            previousLocation: previous,
            previousDate: Date.now.addingTimeInterval(-95),
            newLocation: next,
            now: .now
        )

        #expect(shouldRefresh)
    }

    private func makeMerchant(
        id: String,
        name: String,
        latitude: Double,
        longitude: Double,
        category: String
    ) -> ShoppingModeMerchant {
        ShoppingModeMerchant(
            id: id,
            name: name,
            latitude: latitude,
            longitude: longitude,
            radiusMeters: 120,
            categoryHint: category
        )
    }
}
