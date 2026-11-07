#if DEBUG
import Combine
import CoreLocation
import MapKit

/// Test-only inputs and observations. Never substitutes location or notification delivery.
@MainActor
final class ExcursionUITestDiagnostics: ObservableObject {
    static let shared = ExcursionUITestDiagnostics()
    static var isEnabled: Bool {
        UITestSupport.isEnabled && ProcessInfo.processInfo.arguments.contains("-uiTestExcursionFiveStops")
    }

    struct Snapshot: Codable {
        var events: [String] = []
        var scheduledIDs: [String] = []
        var deliveredIDs: [String] = []
        var candidateIDs: [String] = []
        var sessionIDs: [String] = []
        var workspaceIDs: [String] = []
        var fixtureEnabled = false
        var fixCount = 0
    }

    @Published private(set) var snapshot = Snapshot()

    var encoded: String {
        var output = snapshot
        output.fixtureEnabled = Self.isEnabled
        guard let data = try? JSONEncoder().encode(output) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    func record(_ event: String) {
        guard Self.isEnabled else { return }
        snapshot.events.append("\(Date.now.ISO8601Format()) \(event)")
        snapshot.events = Array(snapshot.events.suffix(250))
    }

    func received(_ location: CLLocation) {
        guard Self.isEnabled else { return }
        snapshot.fixCount += 1
        record("fix \(location.coordinate.latitude),\(location.coordinate.longitude) accuracy=\(location.horizontalAccuracy) age=\(Date.now.timeIntervalSince(location.timestamp)) speed=\(location.speed)")
    }

    func candidates(_ suggestion: ExcursionSuggestion) {
        guard Self.isEnabled else { return }
        snapshot.candidateIDs = suggestion.candidates.map(\.id)
        snapshot.sessionIDs.append(suggestion.sessionID)
        snapshot.workspaceIDs.append(suggestion.workspaceID.uuidString)
        record("candidates=\(snapshot.candidateIDs) session=\(suggestion.sessionID) workspace=\(suggestion.workspaceID)")
    }

    func scheduled(_ identifier: String) {
        guard Self.isEnabled else { return }
        snapshot.scheduledIDs.append(identifier)
        record("scheduled \(identifier)")
    }

    func delivered(_ identifier: String) {
        guard Self.isEnabled else { return }
        snapshot.deliveredIDs.append(identifier)
        record("willPresent \(identifier); system banner still requires UI assertion")
    }

    static var merchants: [ShoppingModeMerchant] {
        ["A", "B", "C", "D", "E"].enumerated().flatMap { index, stop in
            let names = stop == "C" ? ["C1", "C2", "C3"] : [stop]
            return names.map { name in
                ShoppingModeMerchant(id: "route-\(name)", name: "Route \(name)",
                    latitude: 33.8550064 + Double(index) * 0.005, longitude: -118.3528396,
                    radiusMeters: 100, categoryHint: "Dining",
                    poiCategoryID: MKPointOfInterestCategory.restaurant.rawValue)
            }
        }
    }
}
#endif
