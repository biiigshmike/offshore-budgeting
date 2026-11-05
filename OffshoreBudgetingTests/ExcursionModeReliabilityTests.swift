import Foundation
import MapKit
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

    @Test func startupScoring_RouteDoesNotOverrideDistance() {
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

    @Test func scoringIgnoresStaleInsideStateAndCallbackOrder() {
        let near = makeMerchant(id: "near", name: "Near", latitude: 37.00082, longitude: -122, category: "Dining")
        let far = ShoppingModeMerchant(id: "far", name: "Far", latitude: 37.0029, longitude: -122,
                                       radiusMeters: 400, categoryHint: "Dining")
        let fix = CLLocation(latitude: 37, longitude: -122)
        for merchants in [[far, near], [near, far]] {
            let ranked = scorer.rankedCandidates(merchants: merchants, referenceLocation: fix,
                                                 insideRegionIDs: [scorer.regionIdentifier(for: far)])
            #expect(ranked.first?.merchant.id == "near")
        }
    }

    @Test func scoringRejectsOutsideRadiusEvenIfMarkedInside() {
        let far = makeMerchant(id: "far", name: "Far", latitude: 37.003, longitude: -122, category: "Dining")
        #expect(scorer.rankedCandidates(merchants: [far], referenceLocation: CLLocation(latitude: 37, longitude: -122),
                                       insideRegionIDs: [scorer.regionIdentifier(for: far)]).isEmpty)
    }

    @Test func notificationGateBlocksReturningMerchantAfterAnotherMerchant() {
        let now = Date.now
        let decision = policy.notificationDecision(
            merchantID: "a", currentLocation: CLLocation(latitude: 37.01, longitude: -122),
            lastGlobalFireAt: now.addingTimeInterval(-130), lastMerchantFireAt: now.addingTimeInterval(-300),
            lastDeliveredMerchantID: "b", lastDeliveredLocation: CLLocation(latitude: 37, longitude: -122),
            lastDeliveredStopLocation: CLLocation(latitude: 37, longitude: -122), now: now
        )
        #expect(!decision.isAllowed)
        #expect(decision.reason == .merchantCooldown)
    }

    @Test func notificationGate_BlocksGlobalCooldown() {
        let decision = policy.notificationDecision(
            merchantID: "merchant",
            currentLocation: CLLocation(latitude: 37.0, longitude: -122.0),
            lastGlobalFireAt: Date.now.addingTimeInterval(-60),
            lastMerchantFireAt: nil,
            lastDeliveredMerchantID: nil,
            lastDeliveredLocation: nil,
            lastDeliveredStopLocation: nil,
            now: .now
        )

        #expect(decision.isAllowed == false)
        #expect(decision.reason == .rapidRepeat)
    }

    @Test func notificationGate_BlocksSameMerchantDuringMerchantCooldown() {
        let decision = policy.notificationDecision(
            merchantID: "merchant",
            currentLocation: CLLocation(latitude: 37.0005, longitude: -122.0005),
            lastGlobalFireAt: Date.now.addingTimeInterval(-policy.globalNotificationCooldownSeconds - 1),
            lastMerchantFireAt: Date.now.addingTimeInterval(-240),
            lastDeliveredMerchantID: "merchant",
            lastDeliveredLocation: CLLocation(latitude: 37.0, longitude: -122.0),
            lastDeliveredStopLocation: CLLocation(latitude: 36.9990, longitude: -122.0),
            now: .now
        )

        #expect(decision.isAllowed == false)
        #expect(decision.reason == .merchantCooldown)
    }

    @Test func notificationGate_AllowsRearmedMerchantAtSameCoordinatesAfterCooldown() {
        let decision = policy.notificationDecision(
            merchantID: "merchant",
            currentLocation: CLLocation(latitude: 37.0003, longitude: -122.0),
            lastGlobalFireAt: Date.now.addingTimeInterval(-policy.perMerchantNotificationCooldownSeconds - 30),
            lastMerchantFireAt: Date.now.addingTimeInterval(-policy.perMerchantNotificationCooldownSeconds - 1),
            lastDeliveredMerchantID: "merchant",
            lastDeliveredLocation: CLLocation(latitude: 37.0, longitude: -122.0),
            lastDeliveredStopLocation: CLLocation(latitude: 36.9990, longitude: -122.0),
            now: .now
        )

        #expect(decision.isAllowed)
        #expect(decision.reason == nil)
    }

    @Test func notificationGate_AllowsDifferentMerchantAfterCooldownWithShortTravel() {
        let decision = policy.notificationDecision(
            merchantID: "merchant-b",
            currentLocation: CLLocation(latitude: 37.0002, longitude: -122.0),
            lastGlobalFireAt: Date.now.addingTimeInterval(-policy.globalNotificationCooldownSeconds - 1),
            lastMerchantFireAt: nil,
            lastDeliveredMerchantID: "merchant-a",
            lastDeliveredLocation: CLLocation(latitude: 37.0, longitude: -122.0),
            lastDeliveredStopLocation: CLLocation(latitude: 36.9990, longitude: -122.0),
            now: .now
        )

        #expect(decision.isAllowed)
        #expect(decision.reason == nil)
    }

    @Test func notificationGate_LeavesStopSuppressionToDwellTracker() {
        let decision = policy.notificationDecision(
            merchantID: "merchant-b",
            currentLocation: CLLocation(latitude: 37.0001, longitude: -122.0),
            lastGlobalFireAt: Date.now.addingTimeInterval(-policy.globalNotificationCooldownSeconds - 1),
            lastMerchantFireAt: nil,
            lastDeliveredMerchantID: "merchant-a",
            lastDeliveredLocation: CLLocation(latitude: 37.0, longitude: -122.0),
            lastDeliveredStopLocation: CLLocation(latitude: 37.0, longitude: -122.0),
            now: .now
        )

        #expect(decision.isAllowed)
        #expect(decision.reason == nil)
    }

    @Test func notificationGate_AllowsSameMerchantAfterCooldownAndMovement() {
        let decision = policy.notificationDecision(
            merchantID: "merchant",
            currentLocation: CLLocation(latitude: 37.0007, longitude: -122.0),
            lastGlobalFireAt: Date.now.addingTimeInterval(-policy.perMerchantNotificationCooldownSeconds - 30),
            lastMerchantFireAt: Date.now.addingTimeInterval(-policy.perMerchantNotificationCooldownSeconds - 1),
            lastDeliveredMerchantID: "merchant",
            lastDeliveredLocation: CLLocation(latitude: 37.0, longitude: -122.0),
            lastDeliveredStopLocation: CLLocation(latitude: 36.9990, longitude: -122.0),
            now: .now
        )

        #expect(decision.isAllowed)
        #expect(decision.reason == nil)
    }

    @Test func notificationGate_BlocksSameMerchantWithoutLocation() {
        let decision = policy.notificationDecision(
            merchantID: "merchant",
            currentLocation: nil,
            lastGlobalFireAt: Date.now.addingTimeInterval(-policy.perMerchantNotificationCooldownSeconds - 30),
            lastMerchantFireAt: Date.now.addingTimeInterval(-policy.perMerchantNotificationCooldownSeconds - 1),
            lastDeliveredMerchantID: "merchant",
            lastDeliveredLocation: CLLocation(latitude: 37.0, longitude: -122.0),
            lastDeliveredStopLocation: CLLocation(latitude: 36.9990, longitude: -122.0),
            now: .now
        )

        #expect(decision.isAllowed == false)
        #expect(decision.reason == .missingLocation)
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

    @Test func discoveryKeepsNearestTwentyDedupesAndSurvivesEmptySupplement() async {
        let center = CLLocationCoordinate2D(latitude: 33.8550064, longitude: -118.3528396)
        var queries: [String?] = []
        let resolver = ShoppingModePOIResolver { query, _, _ in
            queries.append(query)
            guard query == nil else { return [] }
            var items = (0..<25).map { index in
                let item = MKMapItem(location: CLLocation(
                    latitude: center.latitude + Double(index) * 0.0001, longitude: center.longitude), address: nil)
                item.name = "Merchant \(index)"
                return item
            }
            items.append(items[0])
            return Array(items.reversed())
        }
        let merchants = await resolver.discoverNearbyMerchants(around: center, searchRadiusMeters: 2500, maxResults: 50,
                                                               preferences: .init(mode: .all, categoryIDs: [], dwellSeconds: 45))
        #expect(merchants.count == 20)
        #expect(merchants.first?.name == "Merchant 0")
        #expect(merchants.last?.name == "Merchant 19")
        #expect(queries.first! == nil)
        #expect(!queries.contains("target") && !queries.contains("costco") && !queries.contains("starbucks"))
    }

    @Test func discoveryWithNoResultsReturnsNoCandidates() async {
        let resolver = ShoppingModePOIResolver { _, _, _ in [] }
        let merchants = await resolver.discoverNearbyMerchants(
            around: CLLocationCoordinate2D(latitude: 33.8550064, longitude: -118.3528396),
            searchRadiusMeters: 2500, maxResults: 20)
        #expect(merchants.isEmpty)
    }

    @Test func customDiscoveryFiltersBeforeDeduplicationAndRegionLimit() async {
        let center = CLLocationCoordinate2D(latitude: 33.8550064, longitude: -118.3528396)
        let selected = MKPointOfInterestCategory.store.rawValue
        let resolver = ShoppingModePOIResolver { query, _, _ in
            guard query == nil else { return [] }
            let excluded = (0..<25).map { index in
                self.makeMapItem(name: "Park \(index)", latitude: center.latitude + Double(index) * 0.00001,
                                 category: .park)
            }
            let eligible = (0..<22).map { index in
                self.makeMapItem(name: "Shop \(index)", latitude: center.latitude + 0.001 + Double(index) * 0.00001,
                                 category: .store)
            }
            // The same named result without metadata must not consume the eligible store's entry.
            let unknownDuplicate = self.makeMapItem(name: "Shop 0", latitude: center.latitude + 0.0009, category: nil)
            return excluded + [unknownDuplicate] + eligible
        }
        let merchants = await resolver.discoverNearbyMerchants(
            around: center, searchRadiusMeters: 2500, maxResults: 20,
            preferences: .init(mode: .custom, categoryIDs: [selected], dwellSeconds: 45))
        #expect(merchants.count == 20)
        #expect(merchants.first?.name == "Shop 0")
        #expect(merchants.first?.latitude == center.latitude + 0.001)
        #expect(merchants.last?.name == "Shop 19")
        #expect(merchants.allSatisfy { $0.poiCategoryID == selected })
    }

    @Test func queryHintsNeverSubstituteForActualMapKitCategory() async {
        let center = CLLocationCoordinate2D(latitude: 33.8550064, longitude: -118.3528396)
        let resolver = ShoppingModePOIResolver { query, _, _ in
            guard query == "restaurant" else { return [] }
            return [
                self.makeMapItem(name: "Unknown result", latitude: center.latitude, category: nil),
                self.makeMapItem(name: "Park result", latitude: center.latitude, category: .park),
                self.makeMapItem(name: "Actual restaurant", latitude: center.latitude, category: .restaurant)
            ]
        }
        let merchants = await resolver.discoverNearbyMerchants(
            around: center, searchRadiusMeters: 2500, maxResults: 20,
            preferences: .init(mode: .custom, categoryIDs: [MKPointOfInterestCategory.restaurant.rawValue], dwellSeconds: 45))
        #expect(merchants.map(\.name) == ["Actual restaurant"])
        #expect(merchants.first?.poiCategoryID == MKPointOfInterestCategory.restaurant.rawValue)
    }

    @Test func allCategoriesIncludesUnknownMetadataAndCustomRejectsUnknownIdentifiers() async {
        let center = CLLocationCoordinate2D(latitude: 33.8550064, longitude: -118.3528396)
        let resolver = ShoppingModePOIResolver { query, _, _ in
            guard query == nil else { return [] }
            return [self.makeMapItem(name: "Unknown", latitude: center.latitude, category: nil),
                    self.makeMapItem(name: "Future category", latitude: center.latitude,
                                     category: MKPointOfInterestCategory(rawValue: "future-category"))]
        }
        let all = await resolver.discoverNearbyMerchants(
            around: center, searchRadiusMeters: 2500, maxResults: 20,
            preferences: .init(mode: .all, categoryIDs: [], dwellSeconds: 45))
        #expect(all.count == 2)
        let custom = await resolver.discoverNearbyMerchants(
            around: center, searchRadiusMeters: 2500, maxResults: 20,
            preferences: .init(mode: .custom, categoryIDs: ["future-category"], dwellSeconds: 45))
        #expect(custom.isEmpty)
    }

    @Test func merchantCacheDecodesWithoutCategoryAndRoundTripsNewMetadata() throws {
        let legacy = Data(#"{"id":"legacy","name":"Legacy","latitude":37,"longitude":-122,"radiusMeters":150,"categoryHint":"Dining"}"#.utf8)
        let decoded = try JSONDecoder().decode(ShoppingModeMerchant.self, from: legacy)
        #expect(decoded.poiCategoryID == nil)
        let merchant = ShoppingModeMerchant(id: "shop", name: "Shop", latitude: 37, longitude: -122,
                                            radiusMeters: 150, categoryHint: "Dining",
                                            poiCategoryID: MKPointOfInterestCategory.restaurant.rawValue)
        #expect(try JSONDecoder().decode(ShoppingModeMerchant.self, from: JSONEncoder().encode(merchant)) == merchant)
    }

    private func makeMapItem(name: String, latitude: Double, category: MKPointOfInterestCategory?) -> MKMapItem {
        let item = MKMapItem(location: CLLocation(latitude: latitude, longitude: -118.3528396), address: nil)
        item.name = name
        item.pointOfInterestCategory = category
        return item
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
