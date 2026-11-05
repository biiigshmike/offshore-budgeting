import Foundation

#if canImport(CoreLocation)
import CoreLocation
#endif

struct ExcursionCandidateScorer {
    struct RouteMetrics: Equatable {
        enum Status: Equatable {
            case valid
            case unavailable
            case rejectedOutlier
        }

        let distanceMeters: CLLocationDistance?
        let expectedTravelTime: TimeInterval?
        let status: Status
    }

    struct ScoredCandidate: Equatable {
        let merchant: ShoppingModeMerchant
        let isInsideRegion: Bool
        let distanceMeters: CLLocationDistance
        let routeDistanceMeters: CLLocationDistance?
        let routeStatus: RouteMetrics.Status?
        let categoryScore: Double
    }

    func rankedCandidates(
        merchants: [ShoppingModeMerchant],
        referenceLocation: CLLocation,
        insideRegionIDs: Set<String>,
        routeMetrics: [String: RouteMetrics] = [:]
    ) -> [ScoredCandidate] {
        merchants
            .map { merchant in
                let location = CLLocation(latitude: merchant.latitude, longitude: merchant.longitude)
                let route = routeMetrics[merchant.id]
                return ScoredCandidate(
                    merchant: merchant,
                    isInsideRegion: insideRegionIDs.contains(regionIdentifier(for: merchant)),
                    distanceMeters: referenceLocation.distance(from: location),
                    routeDistanceMeters: route?.distanceMeters,
                    routeStatus: route?.status,
                    categoryScore: categoryScore(for: merchant.categoryHint)
                )
            }
            .filter { $0.distanceMeters <= $0.merchant.radiusMeters }
            .sorted(by: sort)
    }

    func topCandidate(
        merchants: [ShoppingModeMerchant],
        referenceLocation: CLLocation,
        insideRegionIDs: Set<String>,
        routeMetrics: [String: RouteMetrics] = [:]
    ) -> ScoredCandidate? {
        rankedCandidates(
            merchants: merchants,
            referenceLocation: referenceLocation,
            insideRegionIDs: insideRegionIDs,
            routeMetrics: routeMetrics
        ).first
    }

    func regionIdentifier(for merchant: ShoppingModeMerchant) -> String {
        "shopping_mode.\(merchant.id)"
    }

    private func sort(_ lhs: ScoredCandidate, _ rhs: ScoredCandidate) -> Bool {
        if lhs.distanceMeters != rhs.distanceMeters {
            return lhs.distanceMeters < rhs.distanceMeters
        }
        let nameOrder = lhs.merchant.name.compare(rhs.merchant.name, options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return lhs.merchant.id < rhs.merchant.id
    }

    private func categoryScore(for categoryHint: String) -> Double { 0 }
}
