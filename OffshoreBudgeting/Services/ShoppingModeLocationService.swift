import Foundation

#if canImport(CoreLocation)
import CoreLocation
#endif

// MARK: - ShoppingModeLocationService

#if canImport(CoreLocation)
@MainActor
final class ShoppingModeLocationService: NSObject, CLLocationManagerDelegate {
    static let shared = ShoppingModeLocationService()

    private enum Key {
        static let monitoredMerchantPayloads = "shoppingMode_monitoredMerchantPayloads"
    }

    private let locationManager = CLLocationManager()
    private let poiResolver = ShoppingModePOIResolver()
    private var requestedAlwaysUpgrade = false
    private var pendingLocationRefresh = false
    private var locationWaitTask: Task<Void, Never>? = nil
    private var cachedAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    private var monitoredMerchantsByRegionID: [String: ShoppingModeMerchant] = [:]
    private let defaults = UserDefaults.standard

    private let desiredStartupAccuracyMeters: CLLocationAccuracy = 120
    private let maxStartupLocationWaitSeconds: UInt64 = 20

    private override init() {
        super.init()
        locationManager.delegate = self
        cachedAuthorizationStatus = locationManager.authorizationStatus
        monitoredMerchantsByRegionID = loadPersistedMerchants()
        debugLog("Loaded persisted monitored merchants: \(monitoredMerchantsByRegionID.count)")
    }

    func startMonitoringIfPossible() {
        guard SpendingSessionStore.isActive() else {
            debugLog("Shopping Mode inactive, stopping all monitored regions")
            stopMonitoringAllRegions()
            return
        }

        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }

        let status = locationManager.authorizationStatus
        debugLog("Starting monitoring flow with authorization status: \(status.rawValue)")
        switch status {
        case .notDetermined:
            requestedAlwaysUpgrade = true
            debugLog("Requesting When In Use authorization")
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            if requestedAlwaysUpgrade == false {
                requestedAlwaysUpgrade = true
            }
            debugLog("Requesting Always authorization upgrade")
            locationManager.requestAlwaysAuthorization()
        case .authorizedAlways:
            requestedAlwaysUpgrade = false
            debugLog("Authorized Always. Refreshing nearby monitored merchants")
            refreshNearbyMonitoredMerchants()
        case .restricted, .denied:
            debugLog("Location authorization denied/restricted. Clearing monitored regions")
            stopMonitoringAllRegions()
        @unknown default:
            debugLog("Unknown location authorization status. Clearing monitored regions")
            stopMonitoringAllRegions()
        }
    }

    func stopMonitoringAllRegions() {
        debugLog("Stopping all monitored regions: \(locationManager.monitoredRegions.count)")
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        monitoredMerchantsByRegionID = [:]
        persistMerchants([:])
    }

    func currentAuthorizationStatus() -> CLAuthorizationStatus {
        cachedAuthorizationStatus
    }

    private func refreshNearbyMonitoredMerchants() {
        if let location = locationManager.location, hasGoodAccuracy(location) {
            let currentCoordinate = location.coordinate
            debugLog("Using current location to refresh regions: \(currentCoordinate.latitude), \(currentCoordinate.longitude)")
            Task {
                await monitorNearbyMerchants(around: currentCoordinate)
            }
            return
        }

        pendingLocationRefresh = true
        debugLog("Current location unavailable. Requesting one-shot location update")
        scheduleLocationWaitTimeout()
        locationManager.requestLocation()
    }

    private func monitorNearbyMerchants(around center: CLLocationCoordinate2D) async {
        let discovered = await poiResolver.discoverNearbyMerchants(
            around: center,
            searchRadiusMeters: ShoppingModeMerchantCatalog.searchRadiusMeters,
            maxResults: ShoppingModeMerchantCatalog.maxMonitoredRegions
        )
        debugLog("Discovered nearby MapKit POIs: \(discovered.count)")
        for merchant in discovered.prefix(10) {
            debugLog("POI -> \(merchant.name) @ \(merchant.latitude), \(merchant.longitude) radius=\(merchant.radiusMeters)")
        }

        let merchantsToMonitor: [ShoppingModeMerchant]
        if discovered.isEmpty {
            debugLog("No POIs discovered. Falling back to seeded merchants")
            merchantsToMonitor = nearestFallbackMerchants(around: center)
        } else {
            merchantsToMonitor = Array(discovered.prefix(ShoppingModeMerchantCatalog.maxMonitoredRegions))
        }

        applyMonitoredMerchants(merchantsToMonitor)
        sendStartupNudgeIfEligible(merchants: merchantsToMonitor, userCoordinate: center)
    }

    private func nearestFallbackMerchants(around center: CLLocationCoordinate2D) -> [ShoppingModeMerchant] {
        let sorted = ShoppingModeMerchantCatalog.fallbackMerchants.sorted { lhs, rhs in
            let lhsDistance = distanceMeters(from: center, to: lhs)
            let rhsDistance = distanceMeters(from: center, to: rhs)
            return lhsDistance < rhsDistance
        }

        return Array(sorted.prefix(ShoppingModeMerchantCatalog.maxMonitoredRegions))
    }

    private func applyMonitoredMerchants(_ merchants: [ShoppingModeMerchant]) {
        stopMonitoringAllRegions()
        debugLog("Applying monitored merchants count: \(merchants.count)")

        var map: [String: ShoppingModeMerchant] = [:]
        for merchant in merchants {
            let regionID = regionIdentifier(for: merchant)
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: merchant.latitude, longitude: merchant.longitude),
                radius: merchant.radiusMeters,
                identifier: regionID
            )
            region.notifyOnEntry = true
            region.notifyOnExit = false
            locationManager.startMonitoring(for: region)
            debugLog("Monitoring region -> \(merchant.name) id=\(regionID) radius=\(merchant.radiusMeters)")
            map[regionID] = merchant
        }

        monitoredMerchantsByRegionID = map
        persistMerchants(map)
    }

    private func sendStartupNudgeIfEligible(merchants: [ShoppingModeMerchant], userCoordinate: CLLocationCoordinate2D) {
        guard let sessionID = SpendingSessionStore.sessionID() else { return }
        let nudged = ShoppingModeSuggestionService.shared.sendStartupNudgeIfEligible(
            merchants: merchants,
            userCoordinate: userCoordinate,
            sessionID: sessionID
        )

        if let nudged {
            debugLog("Startup nudge sent for merchant: \(nudged.name)")
        } else {
            debugLog("No startup nudge candidate within threshold")
        }
    }

    private func regionIdentifier(for merchant: ShoppingModeMerchant) -> String {
        "shopping_mode.\(merchant.id)"
    }

    private func distanceMeters(from center: CLLocationCoordinate2D, to merchant: ShoppingModeMerchant) -> CLLocationDistance {
        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let merchantLocation = CLLocation(latitude: merchant.latitude, longitude: merchant.longitude)
        return centerLocation.distance(from: merchantLocation)
    }

    private func persistMerchants(_ merchants: [String: ShoppingModeMerchant]) {
        let payload = merchants.reduce(into: [String: String]()) { result, entry in
            result[entry.key] = "\(entry.value.id)||\(entry.value.name)"
        }
        defaults.set(payload, forKey: Key.monitoredMerchantPayloads)
    }

    private func loadPersistedMerchants() -> [String: ShoppingModeMerchant] {
        let payload = (defaults.dictionary(forKey: Key.monitoredMerchantPayloads) as? [String: String]) ?? [:]
        var restored: [String: ShoppingModeMerchant] = [:]

        for (regionID, raw) in payload {
            let parts = raw.components(separatedBy: "||")
            guard parts.count == 2 else { continue }
            restored[regionID] = ShoppingModeMerchant(
                id: parts[0],
                name: parts[1],
                latitude: 0,
                longitude: 0,
                radiusMeters: 120,
                categoryHint: "Shopping"
            )
        }

        return restored
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        cachedAuthorizationStatus = status
        debugLog("Authorization changed: \(status.rawValue)")

        if status == .authorizedWhenInUse && requestedAlwaysUpgrade {
            manager.requestAlwaysAuthorization()
            return
        }

        if status == .authorizedAlways {
            startMonitoringIfPossible()
            return
        }

        if status == .denied || status == .restricted {
            stopMonitoringAllRegions()
            return
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard pendingLocationRefresh else { return }
        pendingLocationRefresh = false
        locationWaitTask?.cancel()
        locationWaitTask = nil

        guard let latest = locations.last else {
            debugLog("Location update returned empty set. Using fallback merchants")
            applyMonitoredMerchants(Array(ShoppingModeMerchantCatalog.fallbackMerchants.prefix(ShoppingModeMerchantCatalog.maxMonitoredRegions)))
            return
        }
        debugLog("Received location update: \(latest.coordinate.latitude), \(latest.coordinate.longitude)")

        Task {
            await monitorNearbyMerchants(around: latest.coordinate)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard pendingLocationRefresh else { return }
        pendingLocationRefresh = false
        locationWaitTask?.cancel()
        locationWaitTask = nil
        debugLog("Location update failed: \(error.localizedDescription). Using fallback merchants")
        applyMonitoredMerchants(Array(ShoppingModeMerchantCatalog.fallbackMerchants.prefix(ShoppingModeMerchantCatalog.maxMonitoredRegions)))
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard SpendingSessionStore.isActive() else { return }
        guard let merchant = monitoredMerchantsByRegionID[region.identifier] ?? loadPersistedMerchants()[region.identifier] else { return }
        debugLog("Entered monitored region: \(region.identifier) merchant=\(merchant.name)")

        ShoppingModeSuggestionService.shared.handleRegionEntry(merchant: merchant)
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[ShoppingModeLocationService] \(message)")
        #endif
    }

    private func hasGoodAccuracy(_ location: CLLocation) -> Bool {
        location.horizontalAccuracy > 0 && location.horizontalAccuracy <= desiredStartupAccuracyMeters
    }

    private func scheduleLocationWaitTimeout() {
        locationWaitTask?.cancel()
        let waitNanoseconds = maxStartupLocationWaitSeconds * 1_000_000_000
        locationWaitTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: waitNanoseconds)
            await self?.handleLocationWaitTimeout()
        }
    }

    private func handleLocationWaitTimeout() async {
        guard pendingLocationRefresh else { return }
        pendingLocationRefresh = false
        locationWaitTask = nil

        if let location = locationManager.location {
            debugLog("Location wait timeout reached. Proceeding with best available fix: \(location.coordinate.latitude), \(location.coordinate.longitude) accuracy=\(location.horizontalAccuracy)")
            await monitorNearbyMerchants(around: location.coordinate)
            return
        }

        debugLog("Location wait timeout reached with no fix. Using fallback merchants")
        applyMonitoredMerchants(Array(ShoppingModeMerchantCatalog.fallbackMerchants.prefix(ShoppingModeMerchantCatalog.maxMonitoredRegions)))
    }
}
#endif
