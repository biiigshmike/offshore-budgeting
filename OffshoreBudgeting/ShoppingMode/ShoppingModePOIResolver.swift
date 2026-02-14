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

    func discoverNearbyMerchants(
        around center: CLLocationCoordinate2D,
        searchRadiusMeters: Double,
        maxResults: Int
    ) async -> [ShoppingModeMerchant] {
        var resultsByKey: [String: ShoppingModeMerchant] = [:]

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

                let key = dedupeKey(name: name, latitude: coordinate.latitude, longitude: coordinate.longitude)
                guard resultsByKey[key] == nil else { continue }

                let merchant = ShoppingModeMerchant(
                    id: makeMerchantID(name: name, latitude: coordinate.latitude, longitude: coordinate.longitude),
                    name: name,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    radiusMeters: seed.radiusMeters,
                    categoryHint: seed.categoryHint
                )

                resultsByKey[key] = merchant
            }
        }

        let sorted = resultsByKey.values.sorted { lhs, rhs in
            let lhsDistance = distanceMeters(from: center, to: lhs)
            let rhsDistance = distanceMeters(from: center, to: rhs)
            return lhsDistance < rhsDistance
        }

        return Array(sorted.prefix(maxResults))
    }

    private func dedupeKey(name: String, latitude: Double, longitude: Double) -> String {
        let normalized = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let latToken = String(format: "%.4f", latitude)
        let lonToken = String(format: "%.4f", longitude)
        return "\(normalized)|\(latToken)|\(lonToken)"
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
}
#endif
