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
        if lhs.isInsideRegion != rhs.isInsideRegion {
            return lhs.isInsideRegion && !rhs.isInsideRegion
        }

        if lhs.distanceMeters != rhs.distanceMeters {
            return lhs.distanceMeters < rhs.distanceMeters
        }

        let lhsPriority = routePriority(lhs.routeStatus)
        let rhsPriority = routePriority(rhs.routeStatus)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }

        if lhs.routeStatus == .valid, rhs.routeStatus == .valid {
            let lhsDistance = lhs.routeDistanceMeters ?? .greatestFiniteMagnitude
            let rhsDistance = rhs.routeDistanceMeters ?? .greatestFiniteMagnitude
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }
        }

        if lhs.categoryScore != rhs.categoryScore {
            return lhs.categoryScore > rhs.categoryScore
        }

        return lhs.merchant.name.localizedCaseInsensitiveCompare(rhs.merchant.name) == .orderedAscending
    }

    private func routePriority(_ status: RouteMetrics.Status?) -> Int {
        switch status {
        case .some(.valid):
            return 0
        case .some(.unavailable), .none:
            return 1
        case .some(.rejectedOutlier):
            return 2
        }
    }

    private func categoryScore(for categoryHint: String) -> Double {
        switch categoryHint {
        case "Dining", "Groceries", "Coffee", "Health", "Gas":
            return 40
        case "Shopping":
            return 25
        default:
            return 10
        }
    }
}
