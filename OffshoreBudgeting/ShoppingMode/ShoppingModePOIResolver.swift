import Foundation

#if canImport(CoreLocation)
import CoreLocation
#endif

#if canImport(MapKit)
import MapKit
#endif

// MARK: - ShoppingModePOIResolver

#if canImport(CoreLocation) && canImport(MapKit)
@MainActor
final class ShoppingModePOIResolver {
    private struct SearchSeed {
        let query: String
        let categoryHint: String
        let radiusMeters: Double
    }

    private struct Candidate {
        let merchant: ShoppingModeMerchant
        let distanceMeters: CLLocationDistance
    }

    private struct CandidateAccumulator {
        var name: String
        var normalizedName: String
        var coordinate: CLLocationCoordinate2D
        var radiusMeters: Double
        var categoryHint: String
        var poiCategoryID: String?
        var matchedSeedQueries: Set<String>
    }

    private let seeds: [SearchSeed] = [
        SearchSeed(query: "coffee", categoryHint: "Coffee", radiusMeters: 120),
        SearchSeed(query: "grocery store", categoryHint: "Groceries", radiusMeters: 180),
        SearchSeed(query: "supermarket", categoryHint: "Groceries", radiusMeters: 180),
        SearchSeed(query: "gas station", categoryHint: "Gas", radiusMeters: 180),
        SearchSeed(query: "restaurant", categoryHint: "Dining", radiusMeters: 150),
        SearchSeed(query: "pharmacy", categoryHint: "Health", radiusMeters: 150),
        SearchSeed(query: "department store", categoryHint: "Shopping", radiusMeters: 200),
        SearchSeed(query: "personal services", categoryHint: "General", radiusMeters: 140),
        SearchSeed(query: "entertainment", categoryHint: "General", radiusMeters: 140)
    ]

    private let dedupeClusterMeters: CLLocationDistance = 35
    private let searchOverride: ((String?, CLLocationCoordinate2D, Double) async -> [MKMapItem])?

    init(search: ((String?, CLLocationCoordinate2D, Double) async -> [MKMapItem])? = nil) {
        searchOverride = search
    }

    func discoverNearbyMerchants(
        around center: CLLocationCoordinate2D,
        searchRadiusMeters: Double,
        maxResults: Int,
        preferences: ExcursionPreferences? = nil
    ) async -> [ShoppingModeMerchant] {
        let preferences = preferences ?? .default
        var accumulators: [CandidateAccumulator] = []

        // Discover all nearby POI categories before supplementary category searches.
        let genericResponse = await runLocalSearch(
            query: nil,
            center: center,
            searchRadiusMeters: searchRadiusMeters,
            preferences: preferences
        )
        absorb(
            responseItems: genericResponse,
            into: &accumulators,
            seedQuery: nil,
            seedCategoryHint: "General",
            seedRadiusMeters: 140,
            preferences: preferences
        )

        for seed in seeds {
            let response = await runLocalSearch(
                query: seed.query,
                center: center,
                searchRadiusMeters: searchRadiusMeters,
                preferences: preferences
            )
            absorb(
                responseItems: response,
                into: &accumulators,
                seedQuery: seed.query,
                seedCategoryHint: seed.categoryHint,
                seedRadiusMeters: seed.radiusMeters,
                preferences: preferences
            )
        }

        let candidates = accumulators.map { accumulator in
            makeCandidate(from: accumulator, center: center)
        }.filter { $0.distanceMeters <= searchRadiusMeters }

        let sorted = sortCandidatesNearestFirst(candidates)

        for (index, candidate) in sorted.prefix(10).enumerated() {
            debugLog(
                "Rank \(index + 1) -> \(candidate.merchant.name) distance=\(Int(candidate.distanceMeters))m"
            )
        }

        return Array(sorted.prefix(max(0, min(maxResults, ShoppingModeTuning.maxMonitoredRegions))).map(\.merchant))
    }

    private func runLocalSearch(
        query: String?,
        center: CLLocationCoordinate2D,
        searchRadiusMeters: Double,
        preferences: ExcursionPreferences
    ) async -> [MKMapItem] {
        if let searchOverride { return await searchOverride(query, center, searchRadiusMeters) }
        let filter = pointOfInterestFilter(for: preferences)
        let search: MKLocalSearch
        if let query {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = .pointOfInterest
            request.pointOfInterestFilter = filter
            request.region = MKCoordinateRegion(
                center: center,
                latitudinalMeters: searchRadiusMeters * 2,
                longitudinalMeters: searchRadiusMeters * 2
            )
            search = MKLocalSearch(request: request)
        } else {
            let request = MKLocalPointsOfInterestRequest(center: center, radius: searchRadiusMeters)
            request.pointOfInterestFilter = filter
            search = MKLocalSearch(request: request)
        }
        guard let response = try? await search.start() else { return [] }

        return response.mapItems
    }

    private func pointOfInterestFilter(for preferences: ExcursionPreferences) -> MKPointOfInterestFilter {
        // Including uncategorized places requires a broad request, followed by local category filtering.
        if preferences.includeUncategorized { return .includingAll }
        let categories = preferences.categoryIDs
            .filter { preferences.allows(categoryID: $0) }
            .sorted()
            .map { MKPointOfInterestCategory(rawValue: $0) }
        return MKPointOfInterestFilter(including: categories)
    }

    private func absorb(
        responseItems: [MKMapItem],
        into accumulators: inout [CandidateAccumulator],
        seedQuery: String?,
        seedCategoryHint: String,
        seedRadiusMeters: Double,
        preferences: ExcursionPreferences
    ) {
        for item in responseItems {
            // Search categories are hints only. Filtering is based exclusively on MapKit metadata,
            // before deduplication and the region limit, even when a server result ignores its filter.
            let poiCategoryID = item.pointOfInterestCategory?.rawValue
            guard preferences.allows(categoryID: poiCategoryID) else { continue }
            let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { continue }

            let coordinate = item.placemark.coordinate
            guard CLLocationCoordinate2DIsValid(coordinate) else { continue }

            let normalizedName = normalizeName(name)
            if let idx = existingAccumulatorIndex(
                in: accumulators,
                normalizedName: normalizedName,
                coordinate: coordinate
            ) {
                if let seedQuery {
                    accumulators[idx].matchedSeedQueries.insert(seedQuery)
                }
                if accumulators[idx].poiCategoryID == nil {
                    accumulators[idx].poiCategoryID = poiCategoryID
                }
                if accumulators[idx].matchedSeedQueries.count == 1, seedQuery != nil {
                    accumulators[idx].radiusMeters = seedRadiusMeters
                } else if seedQuery != nil {
                    accumulators[idx].radiusMeters = min(accumulators[idx].radiusMeters, seedRadiusMeters)
                }
                accumulators[idx].categoryHint = preferredCategoryHint(
                    existing: accumulators[idx].categoryHint,
                    incoming: seedCategoryHint
                )
            } else {
                var matches: Set<String> = []
                if let seedQuery {
                    matches.insert(seedQuery)
                }

                accumulators.append(
                    CandidateAccumulator(
                        name: name,
                        normalizedName: normalizedName,
                        coordinate: coordinate,
                        radiusMeters: seedRadiusMeters,
                        categoryHint: seedCategoryHint,
                        poiCategoryID: poiCategoryID,
                        matchedSeedQueries: matches
                    )
                )
            }
        }
    }

    private func sortCandidatesNearestFirst(_ candidates: [Candidate]) -> [Candidate] {
        candidates.sorted { lhs, rhs in
            if lhs.distanceMeters != rhs.distanceMeters {
                return lhs.distanceMeters < rhs.distanceMeters
            }
            return lhs.merchant.id < rhs.merchant.id
        }
    }

    private func makeCandidate(
        from accumulator: CandidateAccumulator,
        center: CLLocationCoordinate2D
    ) -> Candidate {
        let merchant = ShoppingModeMerchant(
            id: makeMerchantID(
                name: accumulator.name,
                latitude: accumulator.coordinate.latitude,
                longitude: accumulator.coordinate.longitude
            ),
            name: accumulator.name,
            latitude: accumulator.coordinate.latitude,
            longitude: accumulator.coordinate.longitude,
            radiusMeters: accumulator.radiusMeters,
            categoryHint: accumulator.categoryHint,
            poiCategoryID: accumulator.poiCategoryID
        )

        let distance = distanceMeters(from: center, to: merchant)

        return Candidate(
            merchant: merchant,
            distanceMeters: distance
        )
    }

    private func existingAccumulatorIndex(
        in accumulators: [CandidateAccumulator],
        normalizedName: String,
        coordinate: CLLocationCoordinate2D
    ) -> Int? {
        for (index, accumulator) in accumulators.enumerated() {
            guard accumulator.normalizedName == normalizedName else { continue }

            let existingLocation = CLLocation(
                latitude: accumulator.coordinate.latitude,
                longitude: accumulator.coordinate.longitude
            )
            let incomingLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let separation = existingLocation.distance(from: incomingLocation)

            if separation <= dedupeClusterMeters {
                return index
            }
        }

        return nil
    }

    private func normalizeName(_ name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func preferredCategoryHint(existing: String, incoming: String) -> String {
        let existingScore = categoryRelevanceScore(for: existing)
        let incomingScore = categoryRelevanceScore(for: incoming)
        return incomingScore > existingScore ? incoming : existing
    }

    private func categoryRelevanceScore(for categoryHint: String) -> Double {
        switch categoryHint {
        case "Dining", "Groceries", "Coffee", "Health", "Gas":
            return 40
        case "Shopping":
            return 25
        default:
            return 10
        }
    }

    private func makeMerchantID(name: String, latitude: Double, longitude: Double) -> String {
        let slug = slugify(name)
        let latToken = String(format: "%.5f", latitude).replacingOccurrences(of: ".", with: "_")
        let lonToken = String(format: "%.5f", longitude).replacingOccurrences(of: ".", with: "_")
        return "\(slug)_\(latToken)_\(lonToken)"
    }

    private func slugify(_ text: String) -> String {
        let lower = text.lowercased()
        let allowed = CharacterSet.alphanumerics
        let scalars = lower.unicodeScalars.map { scalar -> Character in
            if allowed.contains(scalar) {
                return Character(scalar)
            }
            return "_"
        }

        let raw = String(scalars)
        return raw
            .replacingOccurrences(of: "__", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private func distanceMeters(from center: CLLocationCoordinate2D, to merchant: ShoppingModeMerchant) -> CLLocationDistance {
        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let merchantLocation = CLLocation(latitude: merchant.latitude, longitude: merchant.longitude)
        return centerLocation.distance(from: merchantLocation)
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[ShoppingModePOIResolver] \(message)")
        #endif
    }
}
#endif
