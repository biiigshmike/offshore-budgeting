import CoreLocation
import Foundation
import Testing
@testable import Offshore

@MainActor
struct ExcursionDwellTrackerTests {
    private let epoch = Date(timeIntervalSince1970: 1_800_000_000)
    private let shop = ShoppingModeMerchant(id: "shop", name: "Shop", latitude: 33.8550064,
                                           longitude: -118.3528396, radiusMeters: 150, categoryHint: "Shopping")

    private func fix(_ seconds: Double, accuracy: Double = 20, speed: Double = 0,
                     latitude: Double = 33.8550064) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: -118.3528396),
                   altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 10,
                   course: 0, speed: speed, timestamp: epoch.addingTimeInterval(seconds))
    }

    private func sample(_ tracker: inout ExcursionDwellTracker, _ seconds: Double,
                        accuracy: Double = 20, speed: Double = 0, latitude: Double = 33.8550064,
                        merchants: [ShoppingModeMerchant]? = nil) -> [ShoppingModeMerchant] {
        tracker.evaluate(location: fix(seconds, accuracy: accuracy, speed: speed, latitude: latitude),
                         merchants: merchants ?? [shop], now: epoch.addingTimeInterval(seconds))
    }

    @Test func initialStopNeedsTwoMinutesOfFreshEvidence() {
        var tracker = ExcursionDwellTracker(dwellSeconds: 120)
        for time in [0.0, 30, 60, 90, 119] { #expect(sample(&tracker, time).isEmpty) }
        #expect(sample(&tracker, 120).map(\.id) == [shop.id])
    }

    @Test func repeatedAndStaleFixesDoNotAdvanceDwell() {
        var tracker = ExcursionDwellTracker(dwellSeconds: 120)
        #expect(sample(&tracker, 0).isEmpty)
        for receipt in [30.0, 60, 120] {
            #expect(tracker.evaluate(location: fix(0), merchants: [shop],
                                      now: epoch.addingTimeInterval(receipt)).isEmpty)
        }
        #expect(sample(&tracker, 121).isEmpty)
    }

    @Test func missingSamplesResetContinuity() {
        var tracker = ExcursionDwellTracker(dwellSeconds: 120)
        #expect(sample(&tracker, 0).isEmpty)
        #expect(sample(&tracker, 61).isEmpty)
        #expect(sample(&tracker, 121).isEmpty)
        #expect(sample(&tracker, 181).map(\.id) == [shop.id])
    }

    @Test func poorAccuracyCannotCompleteDwell() {
        var tracker = ExcursionDwellTracker(dwellSeconds: 120)
        for time in [0.0, 30, 60, 90] { _ = sample(&tracker, time) }
        #expect(sample(&tracker, 120, accuracy: 81).isEmpty)
        #expect(sample(&tracker, 151).isEmpty)
    }

    @Test func drivingAndDepartureRequireNewDwell() {
        var tracker = ExcursionDwellTracker(dwellSeconds: 120)
        for time in [0.0, 30, 60, 90] { _ = sample(&tracker, time) }
        #expect(sample(&tracker, 120, speed: 12).isEmpty)
        #expect(sample(&tracker, 150).isEmpty)
        #expect(sample(&tracker, 180, latitude: 33.86).isEmpty)
        #expect(sample(&tracker, 210).isEmpty)
    }

    @Test func oneReminderPerStopUntilFreshDeparture() {
        var tracker = ExcursionDwellTracker(dwellSeconds: 120)
        for time in [0.0, 30, 60, 90] { _ = sample(&tracker, time) }
        let ready = sample(&tracker, 120)
        #expect(!ready.isEmpty)
        tracker.markDelivered(merchants: ready)
        #expect(sample(&tracker, 150).isEmpty)
        #expect(sample(&tracker, 180, latitude: 33.86).isEmpty)
        for time in [210.0, 240, 270, 300] { #expect(sample(&tracker, time).isEmpty) }
        #expect(sample(&tracker, 330).map(\.id) == [shop.id])
    }

    @Test func ambiguousNeighborsAreOrderedAndCappedAtFive() {
        var tracker = ExcursionDwellTracker(dwellSeconds: 120)
        let merchants = (0..<7).map { index in
            ShoppingModeMerchant(id: "shop-\(index)", name: "Shop \(index)",
                                 latitude: shop.latitude + Double(index) * 0.00003,
                                 longitude: shop.longitude, radiusMeters: 150, categoryHint: "Shopping")
        }
        for time in [0.0, 30, 60, 90] { _ = sample(&tracker, time, merchants: Array(merchants.reversed())) }
        #expect(sample(&tracker, 120, merchants: merchants).map(\.id) == Array(merchants.prefix(5)).map(\.id))
    }

    @Test func noDiscoveredMerchantsCannotProduceReminder() {
        var tracker = ExcursionDwellTracker(dwellSeconds: 120)
        for time in [0.0, 30, 60, 90, 120] { #expect(sample(&tracker, time, merchants: []).isEmpty) }
    }

    @Test func walkingAcrossOverlappingMerchantsCannotAccumulateOneContinuousDwell() {
        var tracker = ExcursionDwellTracker(dwellSeconds: 120)
        let metersPerLatitudeDegree = 111_000.0
        let merchants = (0..<5).map { index in
            ShoppingModeMerchant(id: "chain-\(index)", name: "Chain \(index)",
                                 latitude: shop.latitude + Double(index) * 60 / metersPerLatitudeDegree,
                                 longitude: shop.longitude, radiusMeters: 100, categoryHint: "Shopping")
        }
        // Neighboring ambiguity sets overlap pairwise, but no merchant remains
        // continuously eligible over the entire two-minute walk.
        for index in 0..<5 {
            let result = sample(&tracker, Double(index) * 30, accuracy: 35,
                                latitude: shop.latitude + Double(index) * 60 / metersPerLatitudeDegree,
                                merchants: merchants)
            #expect(result.isEmpty)
        }
    }

    @Test(arguments: [45, 60, 120])
    func selectedDurationRequiresFullInterval(_ seconds: Int) {
        var tracker = ExcursionDwellTracker(dwellSeconds: seconds)
        let duration = Double(seconds)
        for time in [0, duration / 3, duration * 2 / 3, duration - 0.1] {
            #expect(sample(&tracker, time).isEmpty)
        }
        #expect(sample(&tracker, duration).map(\.id) == [shop.id])
    }

    @Test(arguments: [45, 60, 120])
    func maximumGapIsHalfSelectedDuration(_ seconds: Int) {
        var tracker = ExcursionDwellTracker(dwellSeconds: seconds)
        let half = Double(seconds) / 2
        _ = sample(&tracker, 0)
        #expect(sample(&tracker, half + 0.1).isEmpty)
        #expect(tracker.firstSampleAt == epoch.addingTimeInterval(half + 0.1))
        #expect(sample(&tracker, half * 2 + 0.1).isEmpty)
        #expect(!sample(&tracker, half * 3 + 0.1).isEmpty)
    }

    @Test func defaultDurationIsFortyFiveSeconds() {
        let tracker = ExcursionDwellTracker()
        #expect(tracker.dwellSeconds == 45)
    }

}
