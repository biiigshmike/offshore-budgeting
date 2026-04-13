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
    static let authorizationDidChangeNotification = Notification.Name("ShoppingModeLocationService.authorizationDidChange")

    private enum Key {
        static let monitoredMerchantPayloads = "shoppingMode_monitoredMerchantPayloads"
    }

    private enum RefreshTrigger: String {
        case startup
        case distance
        case followUp
        case retry
    }

    private enum LocationRequestPurpose: Equatable {
        case refresh(RefreshTrigger)
        case startupConfirmation
        case regionConfirmation(merchantID: String)
    }

    private struct PersistedMerchantPayload: Codable {
        let id: String
        let name: String
        let latitude: Double
        let longitude: Double
        let radiusMeters: Double
        let categoryHint: String
    }

    private struct StartupConfirmationState {
        let startedAt: Date
        var samplesCollected: Int
        var topMerchantID: String?
        var firstTopMerchantAt: Date?
        var consecutiveMatches: Int
    }

    private struct StartupRouteScore {
        let merchant: ShoppingModeMerchant
        let routeMetrics: ExcursionCandidateScorer.RouteMetrics
    }

    private let locationManager = CLLocationManager()
    private let poiResolver = ShoppingModePOIResolver()
    private let detectionPolicy = ExcursionDetectionPolicy()
    private let candidateScorer = ExcursionCandidateScorer()
    private let defaults = UserDefaults.standard

    private var requestedAlwaysUpgrade = false
    private var cachedAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    private var monitoredMerchantsByRegionID: [String: ShoppingModeMerchant] = [:]
    private var currentInsideRegionIDs: Set<String> = []
    private var lastRefreshLocation: CLLocation?
    private var lastRefreshDate: Date?
    private var lastKnownLocation: CLLocation?
    private var lastKnownLocationDate: Date?
    private var pendingPOIRetryAttempts = 0
    private var poiRetryTask: Task<Void, Never>?
    private var locationWaitTask: Task<Void, Never>?
    private var followUpRefreshTask: Task<Void, Never>?
    private var activeLocationRequest: LocationRequestPurpose?
    private var startupConfirmationState: StartupConfirmationState?

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = kCLDistanceFilterNone
        cachedAuthorizationStatus = locationManager.authorizationStatus
        monitoredMerchantsByRegionID = loadPersistedMerchants()
        debugLog("Loaded persisted monitored merchants: \(monitoredMerchantsByRegionID.count)")
    }

    func requestAuthorizationForExcursionMode() {
        let status = locationManager.authorizationStatus
        cachedAuthorizationStatus = status

        switch status {
        case .notDetermined:
            requestedAlwaysUpgrade = false
            debugLog("Requesting initial When In Use authorization for Excursion Mode")
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            #if targetEnvironment(macCatalyst)
            requestedAlwaysUpgrade = false
            debugLog("Location already authorized for Excursion Mode on Mac Catalyst")
            #else
            requestedAlwaysUpgrade = true
            debugLog("Requesting Always authorization upgrade for Excursion Mode")
            locationManager.requestAlwaysAuthorization()
            #endif
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
            #if targetEnvironment(macCatalyst)
            requestedAlwaysUpgrade = false
            setBackgroundLocationUpdatesEnabled(true)
            locationManager.startMonitoringSignificantLocationChanges()
            debugLog("Authorized for Location on Mac Catalyst. Refreshing nearby monitored merchants")
            refreshNearbyMonitoredMerchants(trigger: .startup)
            #else
            if requestedAlwaysUpgrade {
                requestedAlwaysUpgrade = false
                debugLog("Requesting Always authorization upgrade")
                locationManager.requestAlwaysAuthorization()
            } else {
                debugLog("Authorized When In Use only. Waiting for App Settings upgrade to Always")
                stopMonitoringAllRegions()
            }
            #endif
        case .authorizedAlways:
            requestedAlwaysUpgrade = false
            setBackgroundLocationUpdatesEnabled(true)
            locationManager.startMonitoringSignificantLocationChanges()
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
        stopMonitoredRegionsOnly()
        currentInsideRegionIDs = []
        setBackgroundLocationUpdatesEnabled(false)
        locationManager.stopMonitoringSignificantLocationChanges()
        locationWaitTask?.cancel()
        locationWaitTask = nil
        poiRetryTask?.cancel()
        poiRetryTask = nil
        followUpRefreshTask?.cancel()
        followUpRefreshTask = nil
        activeLocationRequest = nil
        startupConfirmationState = nil
        pendingPOIRetryAttempts = 0
        lastRefreshLocation = nil
        lastRefreshDate = nil
        lastKnownLocation = nil
        lastKnownLocationDate = nil
        persistMerchants([:])
    }

    func currentAuthorizationStatus() -> CLAuthorizationStatus {
        cachedAuthorizationStatus = locationManager.authorizationStatus
        return cachedAuthorizationStatus
    }

    private func stopMonitoredRegionsOnly() {
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        monitoredMerchantsByRegionID = [:]
    }

    private func refreshNearbyMonitoredMerchants(trigger: RefreshTrigger) {
        cancelStartupConfirmationIfNeeded()
        beginLocationRequest(for: .refresh(trigger))
    }

    private func beginLocationRequest(for purpose: LocationRequestPurpose) {
        activeLocationRequest = purpose
        locationWaitTask?.cancel()
        let timeoutNanoseconds = UInt64(detectionPolicy.startupLocationWindowSeconds * 1_000_000_000)
        locationWaitTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            await self?.handleLocationWaitTimeout(for: purpose)
        }

        debugLog("Requesting location for purpose: \(purpose)")
        locationManager.requestLocation()
    }

    private func monitorNearbyMerchants(
        around location: CLLocation,
        trigger: RefreshTrigger
    ) async {
        let center = location.coordinate
        let discovered = await poiResolver.discoverNearbyMerchants(
            around: center,
            searchRadiusMeters: ShoppingModeMerchantCatalog.searchRadiusMeters,
            maxResults: ShoppingModeMerchantCatalog.maxMonitoredRegions
        )

        debugLog(
            "Discovered nearby MapKit POIs: \(discovered.count) [trigger=\(trigger.rawValue)] accuracy=\(Int(location.horizontalAccuracy))m"
        )
        for merchant in discovered.prefix(10) {
            debugLog("POI -> \(merchant.name) @ \(merchant.latitude), \(merchant.longitude) radius=\(merchant.radiusMeters)")
        }

        guard discovered.isEmpty == false else {
            debugLog("No POIs discovered for \(trigger.rawValue) refresh")
            schedulePOIRetryIfNeeded(reason: "No nearby POIs discovered")
            recordRefreshBaseline(using: location)
            return
        }

        pendingPOIRetryAttempts = 0
        poiRetryTask?.cancel()
        poiRetryTask = nil

        let merchantsToMonitor = Array(discovered.prefix(ShoppingModeMerchantCatalog.maxMonitoredRegions))
        applyMonitoredMerchants(merchantsToMonitor, trigger: trigger)
        recordRefreshBaseline(using: location)
    }

    private func applyMonitoredMerchants(_ merchants: [ShoppingModeMerchant], trigger: RefreshTrigger) {
        stopMonitoredRegionsOnly()
        currentInsideRegionIDs = []
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
            locationManager.requestState(for: region)
            debugLog("Monitoring region -> \(merchant.name) id=\(regionID) radius=\(Int(merchant.radiusMeters))")
            map[regionID] = merchant
        }

        monitoredMerchantsByRegionID = map
        persistMerchants(map)

        if trigger == .startup {
            startStartupConfirmation()
        }
    }

    private func startStartupConfirmation() {
        startupConfirmationState = StartupConfirmationState(
            startedAt: .now,
            samplesCollected: 0,
            topMerchantID: nil,
            firstTopMerchantAt: nil,
            consecutiveMatches: 0
        )
        debugLog("Starting startup confirmation window")
        beginLocationRequest(for: .startupConfirmation)
    }

    private func cancelStartupConfirmationIfNeeded() {
        startupConfirmationState = nil
        if activeLocationRequest == .startupConfirmation {
            activeLocationRequest = nil
            locationWaitTask?.cancel()
            locationWaitTask = nil
        }
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

        let threshold = detectionPolicy.movementRefreshThreshold(for: max(0, location.speed))
        let elapsed = now.timeIntervalSince(lastRefreshDate)
        let movedMeters = location.distance(from: previousLocation)

        guard detectionPolicy.shouldRefreshMovement(
            previousLocation: previousLocation,
            previousDate: lastRefreshDate,
            newLocation: location,
            now: now
        ) else {
            debugLog(
                "Movement refresh skipped: moved \(Int(movedMeters))m in \(Int(elapsed))s; threshold=\(Int(threshold.distanceMeters))m/\(Int(threshold.minimumElapsedSeconds))s"
            )
            return
        }

        debugLog(
            "Movement refresh triggered: moved \(Int(movedMeters))m in \(Int(elapsed))s at speed=\(Int(max(0, location.speed)))m/s"
        )
        Task {
            await monitorNearbyMerchants(around: location, trigger: .distance)
        }
    }

    private func recordRefreshBaseline(using location: CLLocation, now: Date = .now) {
        lastRefreshLocation = location
        lastRefreshDate = now
    }

    private func handleSuccessfulRegionEntryNotification(at location: CLLocation?) {
        guard let location else { return }
        recordRefreshBaseline(using: location)
        scheduleFollowUpRefreshIfNeeded(baselineDate: lastRefreshDate ?? .now)
    }

    private func scheduleFollowUpRefreshIfNeeded(baselineDate: Date) {
        followUpRefreshTask?.cancel()
        let delaySeconds: TimeInterval = 90
        followUpRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            await self?.performFollowUpRefreshIfNeeded(expectedBaselineDate: baselineDate)
        }
    }

    private func performFollowUpRefreshIfNeeded(expectedBaselineDate: Date) async {
        guard SpendingSessionStore.isActive() else { return }
        guard activeLocationRequest == nil else {
            debugLog("Follow-up refresh skipped: location request already in flight")
            return
        }
        guard let lastRefreshDate, lastRefreshDate == expectedBaselineDate else {
            debugLog("Follow-up refresh skipped: baseline changed before delayed re-evaluation")
            return
        }

        debugLog("Follow-up refresh requesting a delayed re-evaluation of nearby merchants")
        refreshNearbyMonitoredMerchants(trigger: .followUp)
    }

    private func regionIdentifier(for merchant: ShoppingModeMerchant) -> String {
        candidateScorer.regionIdentifier(for: merchant)
    }

    private func persistMerchants(_ merchants: [String: ShoppingModeMerchant]) {
        let payload = merchants.reduce(into: [String: PersistedMerchantPayload]()) { result, entry in
            result[entry.key] = PersistedMerchantPayload(
                id: entry.value.id,
                name: entry.value.name,
                latitude: entry.value.latitude,
                longitude: entry.value.longitude,
                radiusMeters: entry.value.radiusMeters,
                categoryHint: entry.value.categoryHint
            )
        }

        if let encoded = try? JSONEncoder().encode(payload) {
            defaults.set(encoded, forKey: Key.monitoredMerchantPayloads)
        }
    }

    private func loadPersistedMerchants() -> [String: ShoppingModeMerchant] {
        guard let encoded = defaults.data(forKey: Key.monitoredMerchantPayloads),
              let payload = try? JSONDecoder().decode([String: PersistedMerchantPayload].self, from: encoded) else {
            return [:]
        }

        return payload.reduce(into: [String: ShoppingModeMerchant]()) { result, entry in
            result[entry.key] = ShoppingModeMerchant(
                id: entry.value.id,
                name: entry.value.name,
                latitude: entry.value.latitude,
                longitude: entry.value.longitude,
                radiusMeters: entry.value.radiusMeters,
                categoryHint: entry.value.categoryHint
            )
        }
    }

    private func handleLocationWaitTimeout(for purpose: LocationRequestPurpose) async {
        guard activeLocationRequest == purpose else { return }
        locationWaitTask = nil

        switch purpose {
        case .refresh(let trigger):
            activeLocationRequest = nil
            if let lastKnownLocation {
                debugLog(
                    "Location wait timeout reached. Proceeding with best available fix for \(trigger.rawValue): accuracy=\(Int(lastKnownLocation.horizontalAccuracy))m"
                )
                await monitorNearbyMerchants(around: lastKnownLocation, trigger: trigger)
            } else {
                debugLog("Location wait timeout reached with no fix for \(trigger.rawValue)")
                schedulePOIRetryIfNeeded(reason: "Location wait timeout")
            }
        case .startupConfirmation:
            activeLocationRequest = nil
            debugLog("Startup confirmation timed out before a qualifying fix arrived")
            startupConfirmationState = nil
        case .regionConfirmation(let merchantID):
            activeLocationRequest = nil
            debugLog("Region confirmation timed out for merchant id=\(merchantID)")
        }
    }

    private func schedulePOIRetryIfNeeded(reason: String) {
        guard SpendingSessionStore.isActive() else { return }
        let nextAttempt = pendingPOIRetryAttempts + 1
        guard let delay = detectionPolicy.retryDelay(forAttempt: nextAttempt) else {
            debugLog("POI retry skipped: no more attempts [reason=\(reason)]")
            return
        }

        pendingPOIRetryAttempts = nextAttempt
        poiRetryTask?.cancel()
        debugLog("Scheduling POI retry attempt \(nextAttempt) in \(Int(delay))s [reason=\(reason)]")

        poiRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await self?.performPOIRetry(attempt: nextAttempt)
        }
    }

    private func performPOIRetry(attempt: Int) async {
        guard SpendingSessionStore.isActive() else { return }
        guard attempt == pendingPOIRetryAttempts else { return }
        debugLog("Executing POI retry attempt \(attempt)")
        refreshNearbyMonitoredMerchants(trigger: .retry)
    }

    private func isRecentHighConfidenceFix(_ location: CLLocation, now: Date = .now) -> Bool {
        detectionPolicy.hasRecentHighConfidenceFix(
            timestamp: lastKnownLocationDate,
            accuracyMeters: location.horizontalAccuracy,
            now: now
        )
    }

    private func isTopRankedCandidate(_ merchant: ShoppingModeMerchant, for location: CLLocation) -> Bool {
        let topCandidate = candidateScorer.topCandidate(
            merchants: Array(monitoredMerchantsByRegionID.values),
            referenceLocation: location,
            insideRegionIDs: currentInsideRegionIDs
        )
        let isTop = topCandidate?.merchant.id == merchant.id
        if let topCandidate {
            debugLog(
                "Top candidate at fix -> \(topCandidate.merchant.name) inside=\(topCandidate.isInsideRegion) distance=\(Int(topCandidate.distanceMeters))m"
            )
        }
        return isTop
    }

    private func processStartupConfirmationSample(_ location: CLLocation) async {
        guard var state = startupConfirmationState else { return }

        state.samplesCollected += 1
        let rankedCandidates = await rankedStartupCandidates(for: location)
        guard let topCandidate = rankedCandidates.first else {
            debugLog("Startup confirmation sample had no ranked candidates")
            startupConfirmationState = state
            await requestAdditionalStartupSampleIfNeeded(state: state)
            return
        }

        let now = Date.now
        if state.topMerchantID == topCandidate.merchant.id {
            state.consecutiveMatches += 1
        } else {
            state.topMerchantID = topCandidate.merchant.id
            state.firstTopMerchantAt = now
            state.consecutiveMatches = 1
        }

        let stableDuration = now.timeIntervalSince(state.firstTopMerchantAt ?? now)
        startupConfirmationState = state

        debugLog(
            "Startup candidate -> \(topCandidate.merchant.name) inside=\(topCandidate.isInsideRegion) distance=\(Int(topCandidate.distanceMeters))m accuracy=\(Int(location.horizontalAccuracy))m stable=\(Int(stableDuration))s consecutive=\(state.consecutiveMatches)"
        )

        if detectionPolicy.acceptsStartupCandidate(
            accuracyMeters: location.horizontalAccuracy,
            stableDuration: stableDuration,
            consecutiveMatches: state.consecutiveMatches
        ) {
            let didSend = ShoppingModeSuggestionService.shared.sendStartupNudge(
                merchant: topCandidate.merchant,
                sessionID: SpendingSessionStore.sessionID(),
                currentLocation: location
            )

            if didSend {
                debugLog("Startup confirmation accepted for merchant: \(topCandidate.merchant.name)")
            } else {
                debugLog("Startup confirmation passed but notification was blocked by cooldown/session guards")
            }
            startupConfirmationState = nil
            return
        }

        if location.horizontalAccuracy <= detectionPolicy.startupDesiredAccuracyMeters {
            debugLog("Startup candidate rejected: waiting for more stability")
        } else {
            debugLog("Startup candidate rejected: accuracy \(Int(location.horizontalAccuracy))m exceeds \(Int(detectionPolicy.startupDesiredAccuracyMeters))m")
        }

        await requestAdditionalStartupSampleIfNeeded(state: state)
    }

    private func requestAdditionalStartupSampleIfNeeded(state: StartupConfirmationState) async {
        guard detectionPolicy.shouldContinueStartupSampling(
            startedAt: state.startedAt,
            samplesCollected: state.samplesCollected
        ) else {
            debugLog("Startup confirmation ended without a qualifying candidate")
            startupConfirmationState = nil
            return
        }

        beginLocationRequest(for: .startupConfirmation)
    }

    private func rankedStartupCandidates(for location: CLLocation) async -> [ExcursionCandidateScorer.ScoredCandidate] {
        let merchants = Array(monitoredMerchantsByRegionID.values)
        guard merchants.isEmpty == false else { return [] }

        let shortlist = merchants.sorted {
            let lhs = CLLocation(latitude: $0.latitude, longitude: $0.longitude)
            let rhs = CLLocation(latitude: $1.latitude, longitude: $1.longitude)
            return location.distance(from: lhs) < location.distance(from: rhs)
        }
        .prefix(ShoppingModeTuning.startupRouteSelectionMaxCandidates)

        let routeMetrics = await startupRouteMetrics(
            merchants: Array(shortlist),
            from: location.coordinate
        )

        let ranked = candidateScorer.rankedCandidates(
            merchants: merchants,
            referenceLocation: location,
            insideRegionIDs: currentInsideRegionIDs,
            routeMetrics: routeMetrics
        )

        for candidate in ranked.prefix(5) {
            debugLog(
                "Startup rank -> \(candidate.merchant.name) inside=\(candidate.isInsideRegion) distance=\(Int(candidate.distanceMeters))m route=\(Int(candidate.routeDistanceMeters ?? -1))"
            )
        }

        return ranked
    }

    private func processRegionConfirmationSample(location: CLLocation, merchantID: String) {
        guard let merchant = monitoredMerchantsByRegionID.values.first(where: { $0.id == merchantID })
            ?? loadPersistedMerchants().values.first(where: { $0.id == merchantID }) else {
            debugLog("Region confirmation dropped: merchant not found id=\(merchantID)")
            return
        }

        guard location.horizontalAccuracy > 0,
              location.horizontalAccuracy <= detectionPolicy.recentFixDesiredAccuracyMeters else {
            debugLog("Region confirmation rejected for \(merchant.name): poor accuracy \(Int(location.horizontalAccuracy))m")
            return
        }

        guard isTopRankedCandidate(merchant, for: location) else {
            debugLog("Region confirmation rejected for \(merchant.name): candidate is no longer top-ranked")
            return
        }

        ShoppingModeSuggestionService.shared.handleRegionEntry(
            merchant: merchant,
            currentLocation: location,
            onSuccessfulNotification: { [weak self, location] in
                self?.handleSuccessfulRegionEntryNotification(at: location)
            }
        )
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        cachedAuthorizationStatus = status
        debugLog("Authorization changed: \(status.rawValue)")
        NotificationCenter.default.post(
            name: Self.authorizationDidChangeNotification,
            object: self,
            userInfo: ["status": status.rawValue]
        )

        #if !targetEnvironment(macCatalyst)
        if status == .authorizedWhenInUse && requestedAlwaysUpgrade {
            requestedAlwaysUpgrade = false
            manager.requestAlwaysAuthorization()
            return
        }
        #endif

        #if targetEnvironment(macCatalyst)
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            requestedAlwaysUpgrade = false
            startMonitoringIfPossible()
            return
        }
        #else
        if status == .authorizedAlways {
            startMonitoringIfPossible()
            return
        }
        #endif

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

        lastKnownLocation = latest
        lastKnownLocationDate = .now
        debugLog(
            "Received location update: \(latest.coordinate.latitude), \(latest.coordinate.longitude) accuracy=\(Int(latest.horizontalAccuracy))m speed=\(Int(max(0, latest.speed)))m/s"
        )

        guard let requestPurpose = activeLocationRequest else {
            maybeRefreshMonitoredMerchantsForMovement(latest)
            return
        }

        activeLocationRequest = nil
        locationWaitTask?.cancel()
        locationWaitTask = nil

        switch requestPurpose {
        case .refresh(let trigger):
            Task {
                await monitorNearbyMerchants(around: latest, trigger: trigger)
            }
        case .startupConfirmation:
            Task {
                await processStartupConfirmationSample(latest)
            }
        case .regionConfirmation(let merchantID):
            processRegionConfirmationSample(location: latest, merchantID: merchantID)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let purpose = activeLocationRequest else { return }
        activeLocationRequest = nil
        locationWaitTask?.cancel()
        locationWaitTask = nil
        debugLog("Location update failed for \(purpose): \(error.localizedDescription)")

        switch purpose {
        case .refresh:
            schedulePOIRetryIfNeeded(reason: "Location update failed")
        case .startupConfirmation:
            startupConfirmationState = nil
        case .regionConfirmation:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard SpendingSessionStore.isActive() else { return }
        currentInsideRegionIDs.insert(region.identifier)

        guard let merchant = monitoredMerchantsByRegionID[region.identifier] ?? loadPersistedMerchants()[region.identifier] else { return }
        debugLog("Entered monitored region: \(region.identifier) merchant=\(merchant.name)")

        if let lastKnownLocation,
           isRecentHighConfidenceFix(lastKnownLocation),
           isTopRankedCandidate(merchant, for: lastKnownLocation) {
            debugLog("Region entry notified immediately for \(merchant.name) using recent high-confidence fix")
            ShoppingModeSuggestionService.shared.handleRegionEntry(
                merchant: merchant,
                currentLocation: lastKnownLocation,
                onSuccessfulNotification: { [weak self, lastKnownLocation] in
                    self?.handleSuccessfulRegionEntryNotification(at: lastKnownLocation)
                }
            )
            return
        }

        debugLog("Region entry requires confirmation fix for \(merchant.name)")
        beginLocationRequest(for: .regionConfirmation(merchantID: merchant.id))
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard SpendingSessionStore.isActive() else { return }

        switch state {
        case .inside:
            currentInsideRegionIDs.insert(region.identifier)
        case .outside:
            currentInsideRegionIDs.remove(region.identifier)
        case .unknown:
            break
        }

        if state == .inside,
           let merchant = monitoredMerchantsByRegionID[region.identifier] ?? loadPersistedMerchants()[region.identifier] {
            debugLog("Region state inside: \(merchant.name) [region=\(region.identifier)]")
        }
    }

    private func debugLog(_ message: String) {
        #if DEBUG && !targetEnvironment(macCatalyst)
        print("[ShoppingModeLocationService] \(message)")
        #endif
    }

    private func setBackgroundLocationUpdatesEnabled(_ isEnabled: Bool) {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        locationManager.allowsBackgroundLocationUpdates = isEnabled
        #endif
    }

    #if canImport(MapKit)
    private func startupRouteMetrics(
        merchants: [ShoppingModeMerchant],
        from origin: CLLocationCoordinate2D
    ) async -> [String: ExcursionCandidateScorer.RouteMetrics] {
        guard merchants.isEmpty == false else { return [:] }
        let routeLookupTimeoutSeconds = ShoppingModeTuning.startupRouteLookupTimeoutSeconds
        let outlierCrowMultiplier = ShoppingModeTuning.startupRouteOutlierCrowMultiplier
        let outlierExtraMeters = ShoppingModeTuning.startupRouteOutlierExtraMeters

        return await withTaskGroup(
            of: StartupRouteScore.self,
            returning: [String: ExcursionCandidateScorer.RouteMetrics].self
        ) { group in
            for merchant in merchants {
                group.addTask {
                    let destination = CLLocationCoordinate2D(latitude: merchant.latitude, longitude: merchant.longitude)
                    let crowDistance = Self.distanceMeters(from: origin, to: destination)
                    let route = await Self.resolveWalkingRoute(
                        from: origin,
                        to: destination,
                        timeoutSeconds: routeLookupTimeoutSeconds
                    )

                    if let route {
                        if Self.isOutlierRoute(
                            routeDistance: route.distance,
                            crowDistance: crowDistance,
                            outlierCrowMultiplier: outlierCrowMultiplier,
                            outlierExtraMeters: outlierExtraMeters
                        ) {
                            return StartupRouteScore(
                                merchant: merchant,
                                routeMetrics: ExcursionCandidateScorer.RouteMetrics(
                                    distanceMeters: nil,
                                    expectedTravelTime: nil,
                                    status: .rejectedOutlier
                                )
                            )
                        }

                        return StartupRouteScore(
                            merchant: merchant,
                            routeMetrics: ExcursionCandidateScorer.RouteMetrics(
                                distanceMeters: route.distance,
                                expectedTravelTime: route.expectedTravelTime,
                                status: .valid
                            )
                        )
                    }

                    return StartupRouteScore(
                        merchant: merchant,
                        routeMetrics: ExcursionCandidateScorer.RouteMetrics(
                            distanceMeters: nil,
                            expectedTravelTime: nil,
                            status: .unavailable
                        )
                    )
                }
            }

            var result: [String: ExcursionCandidateScorer.RouteMetrics] = [:]
            for await score in group {
                result[score.merchant.id] = score.routeMetrics
            }
            return result
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
        return multiplier >= outlierCrowMultiplier && extraMeters >= outlierExtraMeters
    }
    #endif
}
#endif
