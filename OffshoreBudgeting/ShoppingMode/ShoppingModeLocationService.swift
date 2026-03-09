import Foundation

#if canImport(CoreLocation)
import CoreLocation
#endif

#if canImport(MapKit)
import MapKit
#endif

// MARK: - ShoppingModeLocationService

#if canImport(CoreLocation)
@MainActor
final class ShoppingModeLocationService: NSObject, CLLocationManagerDelegate {
    static let shared = ShoppingModeLocationService()

    private enum Key {
        static let monitoredMerchantPayloads = "shoppingMode_monitoredMerchantPayloads"
    }

    private enum RefreshTrigger: String {
        case startup
        case distance
        case retry
    }

    private struct StartupRouteScore {
        enum RouteStatus {
            case valid
            case unavailable
            case rejectedOutlier
        }

        let merchant: ShoppingModeMerchant
        let crowDistanceMeters: CLLocationDistance
        let walkingETASeconds: TimeInterval?
        let walkingDistanceMeters: CLLocationDistance?
        let routeStatus: RouteStatus
    }

    private let locationManager = CLLocationManager()
    private let poiResolver = ShoppingModePOIResolver()
    private var requestedAlwaysUpgrade = false
    private var pendingLocationRefresh = false
    private var locationWaitTask: Task<Void, Never>? = nil
    private var poiRetryTask: Task<Void, Never>? = nil
    private var cachedAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    private var monitoredMerchantsByRegionID: [String: ShoppingModeMerchant] = [:]
    private var pendingPOIRetryAttempts = 0
    private var startupInsideCandidatesByRegionID: [String: ShoppingModeMerchant] = [:]
    private var startupInsideCollectionTask: Task<Void, Never>? = nil
    private var isCollectingStartupInsideStates = false
    private let defaults = UserDefaults.standard

    private let desiredStartupAccuracyMeters: CLLocationAccuracy = 120
    private let maxStartupLocationWaitSeconds: UInt64 = 20

    private var lastRefreshLocation: CLLocation? = nil
    private var lastRefreshDate: Date? = nil

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 100
        cachedAuthorizationStatus = locationManager.authorizationStatus
        monitoredMerchantsByRegionID = loadPersistedMerchants()
        debugLog("Loaded persisted monitored merchants: \(monitoredMerchantsByRegionID.count)")
    }

    func requestAuthorizationForExcursionMode() {
        let status = locationManager.authorizationStatus
        cachedAuthorizationStatus = status

        switch status {
        case .notDetermined:
            requestedAlwaysUpgrade = true
            debugLog("Requesting initial When In Use authorization for Excursion Mode")
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            requestedAlwaysUpgrade = true
            debugLog("Requesting Always authorization upgrade for Excursion Mode")
            locationManager.requestAlwaysAuthorization()
        case .authorizedAlways, .restricted, .denied:
            break
        @unknown default:
            break
        }
    }

    func startMonitoringIfPossible() {
        guard SpendingSessionStore.isActive() else {
            debugLog("Shopping Mode inactive, stopping all monitored regions")
            stopMonitoringAllRegions()
            return
        }

        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }

        let status = locationManager.authorizationStatus
        cachedAuthorizationStatus = status
        debugLog("Starting monitoring flow with authorization status: \(status.rawValue)")
        switch status {
        case .notDetermined:
            requestAuthorizationForExcursionMode()
        case .authorizedWhenInUse:
            if requestedAlwaysUpgrade {
                requestedAlwaysUpgrade = false
                debugLog("Requesting Always authorization upgrade")
                locationManager.requestAlwaysAuthorization()
            } else {
                debugLog("Authorized When In Use only. Waiting for App Settings upgrade to Always")
                stopMonitoringAllRegions()
            }
        case .authorizedAlways:
            requestedAlwaysUpgrade = false
            setBackgroundLocationUpdatesEnabled(true)
            locationManager.startUpdatingLocation()
            debugLog("Authorized Always. Refreshing nearby monitored merchants")
            refreshNearbyMonitoredMerchants(trigger: .startup)
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
        setBackgroundLocationUpdatesEnabled(false)
        locationManager.stopUpdatingLocation()
        locationWaitTask?.cancel()
        locationWaitTask = nil
        poiRetryTask?.cancel()
        poiRetryTask = nil
        pendingLocationRefresh = false
        pendingPOIRetryAttempts = 0
        lastRefreshLocation = nil
        lastRefreshDate = nil
        monitoredMerchantsByRegionID = [:]
        startupInsideCandidatesByRegionID = [:]
        startupInsideCollectionTask?.cancel()
        startupInsideCollectionTask = nil
        isCollectingStartupInsideStates = false
        persistMerchants([:])
    }

    func currentAuthorizationStatus() -> CLAuthorizationStatus {
        cachedAuthorizationStatus = locationManager.authorizationStatus
        return cachedAuthorizationStatus
    }

    private func refreshNearbyMonitoredMerchants(trigger: RefreshTrigger) {
        if let location = locationManager.location, hasGoodAccuracy(location) {
            let currentCoordinate = location.coordinate
            debugLog("Using current location for \(trigger.rawValue) refresh: \(currentCoordinate.latitude), \(currentCoordinate.longitude)")
            Task {
                await monitorNearbyMerchants(around: currentCoordinate, trigger: trigger)
            }
            return
        }

        pendingLocationRefresh = true
        debugLog("Current location unavailable for \(trigger.rawValue). Requesting one-shot location update")
        scheduleLocationWaitTimeout()
        locationManager.requestLocation()
    }

    private func monitorNearbyMerchants(around center: CLLocationCoordinate2D, trigger: RefreshTrigger) async {
        let discovered = await poiResolver.discoverNearbyMerchants(
            around: center,
            searchRadiusMeters: ShoppingModeMerchantCatalog.searchRadiusMeters,
            maxResults: ShoppingModeMerchantCatalog.maxMonitoredRegions
        )
        debugLog("Discovered nearby MapKit POIs: \(discovered.count) [trigger=\(trigger.rawValue)]")
        for merchant in discovered.prefix(10) {
            debugLog("POI -> \(merchant.name) @ \(merchant.latitude), \(merchant.longitude) radius=\(merchant.radiusMeters)")
        }

        let merchantsToMonitor: [ShoppingModeMerchant]
        if discovered.isEmpty {
            debugLog("No POIs discovered for \(trigger.rawValue) refresh")
            schedulePOIRetryIfNeeded(reason: "No nearby POIs discovered")
            lastRefreshLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
            lastRefreshDate = .now
            return
        } else {
            merchantsToMonitor = Array(discovered.prefix(ShoppingModeMerchantCatalog.maxMonitoredRegions))
            pendingPOIRetryAttempts = 0
            poiRetryTask?.cancel()
            poiRetryTask = nil
        }

        applyMonitoredMerchants(merchantsToMonitor, trigger: trigger)
        lastRefreshLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        lastRefreshDate = .now
    }

    private func applyMonitoredMerchants(_ merchants: [ShoppingModeMerchant], trigger: RefreshTrigger) {
        stopMonitoringAllRegions()
        debugLog("Applying monitored merchants count: \(merchants.count)")

        startStartupInsideCollectionIfNeeded(trigger: trigger)

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
            locationManager.requestState(for: region)
            debugLog("Monitoring region -> \(merchant.name) id=\(regionID) radius=\(merchant.radiusMeters)")
            map[regionID] = merchant
        }

        monitoredMerchantsByRegionID = map
        persistMerchants(map)
        if SpendingSessionStore.isActive() {
            setBackgroundLocationUpdatesEnabled(true)
            locationManager.startUpdatingLocation()
        }
    }

    private func regionIdentifier(for merchant: ShoppingModeMerchant) -> String {
        "shopping_mode.\(merchant.id)"
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

    private func maybeRefreshMonitoredMerchantsForMovement(_ location: CLLocation, now: Date = .now) {
        guard SpendingSessionStore.isActive(now: now) else { return }
        guard location.horizontalAccuracy > 0 else {
            debugLog("Movement refresh skipped: invalid horizontal accuracy")
            return
        }

        guard let previousLocation = lastRefreshLocation, let lastRefreshDate else {
            debugLog("Movement refresh skipped: no baseline; waiting for startup refresh")
            return
        }

        let elapsed = now.timeIntervalSince(lastRefreshDate)
        if elapsed < ShoppingModeTuning.minimumRefreshIntervalSeconds {
            debugLog("Movement refresh skipped: interval \(Int(elapsed))s < \(Int(ShoppingModeTuning.minimumRefreshIntervalSeconds))s")
            return
        }

        let movedMeters = location.distance(from: previousLocation)
        if movedMeters < ShoppingModeTuning.refreshDistanceMeters {
            debugLog("Movement refresh skipped: moved \(Int(movedMeters))m < \(Int(ShoppingModeTuning.refreshDistanceMeters))m")
            return
        }

        debugLog("Movement refresh triggered: moved \(Int(movedMeters))m in \(Int(elapsed))s")
        Task {
            await monitorNearbyMerchants(around: location.coordinate, trigger: .distance)
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        cachedAuthorizationStatus = status
        debugLog("Authorization changed: \(status.rawValue)")

        if status == .authorizedWhenInUse && requestedAlwaysUpgrade {
            requestedAlwaysUpgrade = false
            manager.requestAlwaysAuthorization()
            return
        }

        if status == .authorizedAlways {
            startMonitoringIfPossible()
            return
        }

        if status == .denied || status == .restricted {
            requestedAlwaysUpgrade = false
            stopMonitoringAllRegions()
            return
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else {
            debugLog("Location update returned empty set")
            return
        }

        debugLog("Received location update: \(latest.coordinate.latitude), \(latest.coordinate.longitude) accuracy=\(latest.horizontalAccuracy)")

        if pendingLocationRefresh {
            pendingLocationRefresh = false
            locationWaitTask?.cancel()
            locationWaitTask = nil

            Task {
                await monitorNearbyMerchants(around: latest.coordinate, trigger: .startup)
            }
            return
        }

        maybeRefreshMonitoredMerchantsForMovement(latest)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard pendingLocationRefresh else { return }
        pendingLocationRefresh = false
        locationWaitTask?.cancel()
        locationWaitTask = nil
        debugLog("Location update failed: \(error.localizedDescription)")
        schedulePOIRetryIfNeeded(reason: "Location update failed")
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard SpendingSessionStore.isActive() else { return }
        guard let merchant = monitoredMerchantsByRegionID[region.identifier] ?? loadPersistedMerchants()[region.identifier] else { return }
        debugLog("Entered monitored region: \(region.identifier) merchant=\(merchant.name)")

        ShoppingModeSuggestionService.shared.handleRegionEntry(merchant: merchant)
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard SpendingSessionStore.isActive() else { return }
        guard state == .inside else { return }
        guard let merchant = monitoredMerchantsByRegionID[region.identifier] ?? loadPersistedMerchants()[region.identifier] else { return }

        guard isCollectingStartupInsideStates else { return }
        startupInsideCandidatesByRegionID[region.identifier] = merchant
        debugLog("Startup inside candidate captured: \(merchant.name) [region=\(region.identifier)]")
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[ShoppingModeLocationService] \(message)")
        #endif
    }

    private func setBackgroundLocationUpdatesEnabled(_ isEnabled: Bool) {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        locationManager.allowsBackgroundLocationUpdates = isEnabled
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
            await monitorNearbyMerchants(around: location.coordinate, trigger: .startup)
            return
        }

        debugLog("Location wait timeout reached with no fix")
        schedulePOIRetryIfNeeded(reason: "Location wait timeout")
    }

    private func schedulePOIRetryIfNeeded(reason: String) {
        guard SpendingSessionStore.isActive() else { return }
        guard pendingPOIRetryAttempts < ShoppingModeTuning.maxPOIRetryAttempts else {
            debugLog("POI retry skipped: max attempts reached (\(pendingPOIRetryAttempts)) [reason=\(reason)]")
            return
        }

        pendingPOIRetryAttempts += 1
        poiRetryTask?.cancel()
        let attempt = pendingPOIRetryAttempts
        let waitNanoseconds = UInt64(ShoppingModeTuning.poiRetryIntervalSeconds * 1_000_000_000)
        debugLog("Scheduling POI retry attempt \(attempt) in \(Int(ShoppingModeTuning.poiRetryIntervalSeconds))s [reason=\(reason)]")

        poiRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: waitNanoseconds)
            await self?.performPOIRetry(attempt: attempt)
        }
    }

    private func performPOIRetry(attempt: Int) async {
        guard SpendingSessionStore.isActive() else { return }
        guard attempt == pendingPOIRetryAttempts else { return }

        debugLog("Executing POI retry attempt \(attempt)")
        refreshNearbyMonitoredMerchants(trigger: .retry)
    }

    private func startStartupInsideCollectionIfNeeded(trigger: RefreshTrigger) {
        startupInsideCollectionTask?.cancel()
        startupInsideCollectionTask = nil
        startupInsideCandidatesByRegionID = [:]
        isCollectingStartupInsideStates = false

        guard trigger == .startup else { return }
        isCollectingStartupInsideStates = true
        let waitNanoseconds = UInt64(ShoppingModeTuning.startupInsideCollectionWindowSeconds * 1_000_000_000)
        startupInsideCollectionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: waitNanoseconds)
            await self?.finalizeStartupInsideSelection()
        }
    }

    private func finalizeStartupInsideSelection() async {
        guard isCollectingStartupInsideStates else { return }
        isCollectingStartupInsideStates = false
        startupInsideCollectionTask = nil

        let candidates = Array(startupInsideCandidatesByRegionID.values)
        startupInsideCandidatesByRegionID = [:]
        guard candidates.isEmpty == false else {
            debugLog("No startup inside candidates returned by region state callbacks")
            return
        }

        let referenceLocation = locationManager.location ?? lastRefreshLocation
        let selected = await selectStartupMerchant(from: candidates, referenceLocation: referenceLocation)
        guard let selected else { return }

        let didSend = ShoppingModeSuggestionService.shared.sendStartupNudge(
            merchant: selected,
            sessionID: SpendingSessionStore.sessionID()
        )

        if didSend {
            debugLog("Startup nearest-inside nudge sent for merchant: \(selected.name)")
        } else {
            debugLog("Startup nearest-inside nudge skipped due to cooldown/session guards")
        }
    }

    private func selectStartupMerchant(
        from merchants: [ShoppingModeMerchant],
        referenceLocation: CLLocation?
    ) async -> ShoppingModeMerchant? {
        guard merchants.isEmpty == false else { return nil }

        guard let referenceLocation else {
            return merchants.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }).first
        }

        let crowSorted = merchants.sorted { lhs, rhs in
            let lhsDistance = distanceMeters(from: referenceLocation.coordinate, to: lhs)
            let rhsDistance = distanceMeters(from: referenceLocation.coordinate, to: rhs)
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        let shortlist = Array(crowSorted.prefix(ShoppingModeTuning.startupRouteSelectionMaxCandidates))

        #if canImport(MapKit)
        let scoredCandidates = await scoreStartupCandidates(shortlist: shortlist, from: referenceLocation.coordinate)
        let sortedCandidates = scoredCandidates.sorted(by: startupRouteSort)

        for score in sortedCandidates {
            switch score.routeStatus {
            case .valid:
                debugLog(
                    "Startup route score -> \(score.merchant.name) status=valid walkDistance=\(Int(score.walkingDistanceMeters ?? 0))m eta=\(Int(score.walkingETASeconds ?? 0))s crow=\(Int(score.crowDistanceMeters))m"
                )
            case .unavailable:
                debugLog(
                    "Startup route score -> \(score.merchant.name) status=unavailable crow=\(Int(score.crowDistanceMeters))m"
                )
            case .rejectedOutlier:
                debugLog(
                    "Startup route score -> \(score.merchant.name) status=rejected_outlier crow=\(Int(score.crowDistanceMeters))m"
                )
            }
        }

        if let selected = sortedCandidates.first {
            let selectionReason: String
            switch selected.routeStatus {
            case .valid:
                selectionReason = "distance-first route"
            case .unavailable, .rejectedOutlier:
                selectionReason = "crow fallback"
            }
            debugLog(
                "Startup inside candidates=\(merchants.count); selected=\(selected.merchant.name) via \(selectionReason)"
            )
            return selected.merchant
        }
        #endif

        guard let fallback = crowSorted.first else { return nil }
        let fallbackDistance = distanceMeters(from: referenceLocation.coordinate, to: fallback)
        debugLog("Startup inside candidates=\(merchants.count); selected=\(fallback.name) via crow distance=\(Int(fallbackDistance))m")
        return fallback
    }

    private func distanceMeters(from center: CLLocationCoordinate2D, to merchant: ShoppingModeMerchant) -> CLLocationDistance {
        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let merchantLocation = CLLocation(latitude: merchant.latitude, longitude: merchant.longitude)
        return centerLocation.distance(from: merchantLocation)
    }

    #if canImport(MapKit)
    private func startupRouteSort(_ lhs: StartupRouteScore, _ rhs: StartupRouteScore) -> Bool {
        let lhsPriority = routeStatusPriority(lhs.routeStatus)
        let rhsPriority = routeStatusPriority(rhs.routeStatus)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }

        if lhs.routeStatus == .valid && rhs.routeStatus == .valid {
            let lhsWalkDistance = lhs.walkingDistanceMeters ?? .greatestFiniteMagnitude
            let rhsWalkDistance = rhs.walkingDistanceMeters ?? .greatestFiniteMagnitude
            if lhsWalkDistance != rhsWalkDistance {
                return lhsWalkDistance < rhsWalkDistance
            }
        }

        if lhs.crowDistanceMeters != rhs.crowDistanceMeters {
            return lhs.crowDistanceMeters < rhs.crowDistanceMeters
        }

        let lhsETA = lhs.walkingETASeconds ?? .greatestFiniteMagnitude
        let rhsETA = rhs.walkingETASeconds ?? .greatestFiniteMagnitude
        if lhsETA != rhsETA {
            return lhsETA < rhsETA
        }

        return lhs.merchant.name.localizedCaseInsensitiveCompare(rhs.merchant.name) == .orderedAscending
    }

    private func routeStatusPriority(_ status: StartupRouteScore.RouteStatus) -> Int {
        switch status {
        case .valid:
            return 0
        case .unavailable:
            return 1
        case .rejectedOutlier:
            return 2
        }
    }

    private func scoreStartupCandidates(
        shortlist: [ShoppingModeMerchant],
        from origin: CLLocationCoordinate2D
    ) async -> [StartupRouteScore] {
        guard shortlist.isEmpty == false else { return [] }

        let timeoutSeconds = ShoppingModeTuning.startupRouteLookupTimeoutSeconds
        let outlierCrowMultiplier = ShoppingModeTuning.startupRouteOutlierCrowMultiplier
        let outlierExtraMeters = ShoppingModeTuning.startupRouteOutlierExtraMeters
        return await withTaskGroup(of: StartupRouteScore.self, returning: [StartupRouteScore].self) { group in
            for merchant in shortlist {
                group.addTask {
                    let destination = CLLocationCoordinate2D(latitude: merchant.latitude, longitude: merchant.longitude)
                    let crowDistance = Self.distanceMeters(from: origin, to: destination)
                    let route = await Self.resolveWalkingRoute(
                        from: origin,
                        to: destination,
                        timeoutSeconds: timeoutSeconds
                    )

                    if let route {
                        let routeDistance = route.distance
                        if Self.isOutlierRoute(
                            routeDistance: routeDistance,
                            crowDistance: crowDistance,
                            outlierCrowMultiplier: outlierCrowMultiplier,
                            outlierExtraMeters: outlierExtraMeters
                        ) {
                            return StartupRouteScore(
                                merchant: merchant,
                                crowDistanceMeters: crowDistance,
                                walkingETASeconds: nil,
                                walkingDistanceMeters: nil,
                                routeStatus: .rejectedOutlier
                            )
                        }

                        return StartupRouteScore(
                            merchant: merchant,
                            crowDistanceMeters: crowDistance,
                            walkingETASeconds: route.expectedTravelTime,
                            walkingDistanceMeters: routeDistance,
                            routeStatus: .valid
                        )
                    }

                    return StartupRouteScore(
                        merchant: merchant,
                        crowDistanceMeters: crowDistance,
                        walkingETASeconds: nil,
                        walkingDistanceMeters: nil,
                        routeStatus: .unavailable
                    )
                }
            }

            var scores: [StartupRouteScore] = []
            for await score in group {
                scores.append(score)
            }
            return scores
        }
    }

    nonisolated private static func resolveWalkingRoute(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        timeoutSeconds: TimeInterval
    ) async -> MKRoute? {
        let timeoutNanoseconds = UInt64(max(timeoutSeconds, 0) * 1_000_000_000)
        return await withTaskGroup(of: MKRoute?.self, returning: MKRoute?.self) { group in
            group.addTask {
                await Self.calculateWalkingRoute(from: origin, to: destination)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return nil
            }

            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    nonisolated private static func distanceMeters(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        let originLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let destinationLocation = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        return originLocation.distance(from: destinationLocation)
    }

    nonisolated private static func isOutlierRoute(
        routeDistance: CLLocationDistance,
        crowDistance: CLLocationDistance,
        outlierCrowMultiplier: Double,
        outlierExtraMeters: Double
    ) -> Bool {
        guard crowDistance > 0 else { return false }
        let multiplier = routeDistance / crowDistance
        let extraMeters = routeDistance - crowDistance
        return multiplier >= outlierCrowMultiplier &&
            extraMeters >= outlierExtraMeters
    }

    nonisolated private static func calculateWalkingRoute(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async -> MKRoute? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .walking

        let directions = MKDirections(request: request)
        guard let response = try? await directions.calculate() else { return nil }
        return response.routes.first
    }
    #endif
}
#endif
