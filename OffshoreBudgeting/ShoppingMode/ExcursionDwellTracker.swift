import CoreLocation
import Foundation

/// Evidence of proximity, not proof that someone entered a store or made a purchase.
struct ExcursionDwellTracker {
    private(set) var firstSampleAt: Date?
    private(set) var lastSampleAt: Date?
    private var latestObservedTimestamp: Date?
    private var stopCandidates: [ShoppingModeMerchant] = []
    private(set) var deliveredRegions: [ShoppingModeMerchant] = []
    private let scorer = ExcursionCandidateScorer()
    let dwellSeconds: TimeInterval

    init(dwellSeconds: Int = 45) {
        self.dwellSeconds = TimeInterval([45, 60, 120].contains(dwellSeconds) ? dwellSeconds : 45)
    }

    static func qualifies(_ location: CLLocation, now: Date) -> Bool {
        let age = now.timeIntervalSince(location.timestamp)
        return location.horizontalAccuracy > 0 && location.horizontalAccuracy <= 80
            && age >= 0 && age <= 30
    }

    mutating func evaluate(
        location: CLLocation, merchants: [ShoppingModeMerchant], now: Date
    ) -> [ShoppingModeMerchant] {
        guard Self.qualifies(location, now: now) else { return [] }
        // Cached fixes and out-of-order callbacks cannot add dwell time.
        if let latestObservedTimestamp, location.timestamp <= latestObservedTimestamp { return [] }
        latestObservedTimestamp = location.timestamp
        if !deliveredRegions.isEmpty {
            if deliveredRegions.contains(where: { Self.contains($0, location) }) { return [] }
            deliveredRegions = []
        }
        guard location.speed <= 8 else { resetDwell(); return [] }
        let ranked = scorer.rankedCandidates(
            merchants: merchants, referenceLocation: location, insideRegionIDs: []
        )
        guard let nearest = ranked.first else { resetDwell(); return [] }
        let candidates = ranked.filter {
            $0.distanceMeters - nearest.distanceMeters <= 2 * location.horizontalAccuracy
        }.prefix(5).map(\.merchant)
        let sameStop = stopCandidates.contains { previous in
            candidates.contains { $0.id == previous.id } && Self.contains(previous, location)
        }
        if !sameStop || lastSampleAt.map({ location.timestamp.timeIntervalSince($0) > dwellSeconds / 2 }) == true {
            firstSampleAt = location.timestamp
            stopCandidates = candidates
        } else {
            // Keep a continuous anchor; A/B -> B/C -> C/D is movement, not one dwell.
            stopCandidates = stopCandidates.filter { previous in candidates.contains { $0.id == previous.id } }
        }
        if firstSampleAt == nil { firstSampleAt = location.timestamp }
        lastSampleAt = location.timestamp
        guard let firstSampleAt, location.timestamp.timeIntervalSince(firstSampleAt) >= dwellSeconds else { return [] }
        return candidates
    }

    mutating func markDelivered(merchants: [ShoppingModeMerchant]) {
        deliveredRegions = merchants
        resetDwell()
    }

    mutating func reset() {
        deliveredRegions = []
        latestObservedTimestamp = nil
        resetDwell()
    }

    mutating func resetDwell() {
        firstSampleAt = nil
        lastSampleAt = nil
        stopCandidates = []
    }

    private static func contains(_ merchant: ShoppingModeMerchant, _ location: CLLocation) -> Bool {
        location.distance(from: CLLocation(latitude: merchant.latitude, longitude: merchant.longitude)) <= merchant.radiusMeters
    }
}
