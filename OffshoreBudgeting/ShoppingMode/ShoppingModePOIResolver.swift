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
        let score: Double
        let seedHits: Int
        let categoryBonus: Double
    }

    private struct CandidateAccumulator {
        var name: String
        var normalizedName: String
        var coordinate: CLLocationCoordinate2D
        var radiusMeters: Double
        var categoryHint: String
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
        SearchSeed(query: "target", categoryHint: "Shopping", radiusMeters: 200),
        SearchSeed(query: "costco", categoryHint: "Groceries", radiusMeters: 220),
        SearchSeed(query: "starbucks", categoryHint: "Coffee", radiusMeters: 120)
    ]

    private let dedupeClusterMeters: CLLocationDistance = 35

    func discoverNearbyMerchants(
        around center: CLLocationCoordinate2D,
        searchRadiusMeters: Double,
        maxResults: Int
    ) async -> [ShoppingModeMerchant] {
        var accumulators: [CandidateAccumulator] = []

        for seed in seeds {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = seed.query
            request.resultTypes = .pointOfInterest
            request.region = MKCoordinateRegion(
                center: center,
                latitudinalMeters: searchRadiusMeters,
                longitudinalMeters: searchRadiusMeters
            )

            guard let response = try? await MKLocalSearch(request: request).start() else {
                continue
            }

            for item in response.mapItems {
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
                    accumulators[idx].matchedSeedQueries.insert(seed.query)
                    accumulators[idx].radiusMeters = min(accumulators[idx].radiusMeters, seed.radiusMeters)
                    accumulators[idx].categoryHint = preferredCategoryHint(
                        existing: accumulators[idx].categoryHint,
                        incoming: seed.categoryHint
                    )
                } else {
                    accumulators.append(
                        CandidateAccumulator(
                            name: name,
                            normalizedName: normalizedName,
                            coordinate: coordinate,
                            radiusMeters: seed.radiusMeters,
                            categoryHint: seed.categoryHint,
                            matchedSeedQueries: [seed.query]
                        )
                    )
                }
            }
        }

        let candidates = accumulators.map { accumulator in
            makeCandidate(from: accumulator, center: center, searchRadiusMeters: searchRadiusMeters)
        }

        let sorted = candidates.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.distanceMeters < rhs.distanceMeters
            }
            return lhs.score > rhs.score
        }

        for candidate in sorted.prefix(10) {
            debugLog(
                "Candidate -> \(candidate.merchant.name) distance=\(Int(candidate.distanceMeters))m score=\(String(format: "%.1f", candidate.score)) seedHits=\(candidate.seedHits) categoryBonus=\(Int(candidate.categoryBonus))"
            )
        }

        return Array(sorted.prefix(maxResults).map(\.merchant))
    }

    private func makeCandidate(
        from accumulator: CandidateAccumulator,
        center: CLLocationCoordinate2D,
        searchRadiusMeters: Double
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
            categoryHint: accumulator.categoryHint
        )

        let distance = distanceMeters(from: center, to: merchant)
        let categoryBonus = categoryRelevanceScore(for: accumulator.categoryHint)
        let seedHitBonus = min(Double(max(0, accumulator.matchedSeedQueries.count - 1)) * 12, 24)

        let normalizedDistance = min(max(distance / max(searchRadiusMeters, 1), 0), 1)
        let distanceScore = (1 - normalizedDistance) * 100
        let finalScore = distanceScore + categoryBonus + seedHitBonus

        return Candidate(
            merchant: merchant,
            distanceMeters: distance,
            score: finalScore,
            seedHits: accumulator.matchedSeedQueries.count,
            categoryBonus: categoryBonus
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
