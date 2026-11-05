import Foundation
import Combine
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class ShoppingModeLocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = ShoppingModeLocationService()
    static let authorizationDidChangeNotification = Notification.Name("ShoppingModeLocationService.authorizationDidChange")

    private enum Key {
        static let merchants = "shoppingMode_monitoredMerchantPayloads_v2"
        static let session = "shoppingMode_detectionSession"
        static let workspace = "shoppingMode_detectionWorkspace"
        static let delivered = "shoppingMode_deliveredStop"
        static let preferences = "shoppingMode_detectionPreferences"
    }

    private let locationManager: any ExcursionLocationClient
    private let defaults: UserDefaults
    private let sessionIDProvider: () -> String?
    private let workspaceIDProvider: () -> UUID?
    private let discoverMerchants: (CLLocation, ExcursionPreferences) async -> [ShoppingModeMerchant]
    private let preferencesStore: ExcursionPreferencesStore
    private var preferences: ExcursionPreferences
    private var preferencesObserver: AnyCancellable?
    private let monitoringAvailable: () -> Bool
    private let isMacCatalyst: Bool
    private let now: () -> Date
    private let sendSuggestion: (ExcursionSuggestion, CLLocation, @escaping @MainActor @Sendable () -> Bool) async -> ShoppingModeSuggestionService.DeliveryResult
    private let policy = ExcursionDetectionPolicy()
    private let scorer = ExcursionCandidateScorer()
    private var dwell = ExcursionDwellTracker()
    private var monitoringGeneration = UUID()
    private var monitoringSessionID: String?
    private var workspaceID: UUID?
    private var runningCapability: ExcursionLocationCapability?
    private var merchants: [ShoppingModeMerchant] = []
    private var lastRefreshLocation: CLLocation?
    private var lastRefreshDate: Date?
    private var discoverySequence = 0
    private var discoveryInFlight = false
    private var requiresDiscovery = false
    private var retryAttempts = 0
    private var retryTask: Task<Void, Never>?
    private var locationTimeoutTask: Task<Void, Never>?
    private var confirmationTask: Task<Void, Never>?
    private var confirmationStartedAt: Date?
    private var delivering = false
    private var stopGeneration = UUID()
    private var pendingDeliveryCandidates: [ShoppingModeMerchant] = []
    private(set) var isForeground: Bool
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy

    init(
        locationManager: (any ExcursionLocationClient)? = nil,
        defaults: UserDefaults = .standard,
        isForeground: Bool? = nil,
        isMacCatalyst: Bool? = nil,
        sessionIDProvider: (() -> String?)? = nil,
        monitoringAvailable: (() -> Bool)? = nil,
        discoverMerchants: ((CLLocation) async -> [ShoppingModeMerchant])? = nil,
        workspaceIDProvider: (() -> UUID?)? = nil,
        now: @escaping () -> Date = { .now },
        sendSuggestion: ((ExcursionSuggestion, CLLocation, @escaping @MainActor @Sendable () -> Bool) async -> ShoppingModeSuggestionService.DeliveryResult)? = nil,
        preferencesStore: ExcursionPreferencesStore? = nil
    ) {
        self.locationManager = locationManager ?? CLLocationManager()
        self.defaults = defaults
        self.now = now
        let store = preferencesStore ?? ExcursionPreferencesStore.shared
        self.preferencesStore = store
        self.preferences = store.value
        self.dwell = ExcursionDwellTracker(dwellSeconds: store.value.dwellSeconds)
        #if targetEnvironment(macCatalyst)
        self.isMacCatalyst = isMacCatalyst ?? true
        #else
        self.isMacCatalyst = isMacCatalyst ?? false
        #endif
        #if canImport(UIKit)
        self.isForeground = isForeground ?? (UIApplication.shared.applicationState != .background)
        #else
        self.isForeground = isForeground ?? true
        #endif
        self.sessionIDProvider = sessionIDProvider ?? { SpendingSessionStore.sessionID() }
        self.workspaceIDProvider = workspaceIDProvider ?? {
            UserDefaults.standard.string(forKey: "selectedWorkspaceID").flatMap(UUID.init(uuidString:))
        }
        self.monitoringAvailable = monitoringAvailable ?? {
            CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self)
        }
        if let discoverMerchants { self.discoverMerchants = { location, _ in await discoverMerchants(location) } }
        else {
            let resolver = ShoppingModePOIResolver()
            self.discoverMerchants = { location, preferences in
                await resolver.discoverNearbyMerchants(
                    around: location.coordinate,
                    searchRadiusMeters: ShoppingModeMerchantCatalog.searchRadiusMeters,
                    maxResults: ShoppingModeMerchantCatalog.maxMonitoredRegions,
                    preferences: preferences
                )
            }
        }
        self.sendSuggestion = sendSuggestion ?? { suggestion, location, validation in
            await ShoppingModeSuggestionService.shared.send(
                suggestion: suggestion, currentLocation: location, isStillValid: validation
            )
        }
        super.init()
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        self.locationManager.distanceFilter = 50
        authorizationStatus = self.locationManager.authorizationStatus
        accuracyAuthorization = self.locationManager.accuracyAuthorization
        preferencesObserver = store.$value.dropFirst().sink { [weak self] value in
            self?.applyPreferences(value)
        }
    }

    var capability: ExcursionLocationCapability {
        .resolve(authorization: locationManager.authorizationStatus, isForeground: isForeground,
                 isMacCatalyst: isMacCatalyst, accuracy: locationManager.accuracyAuthorization)
    }

    var canProcessLocationEvents: Bool {
        capability.canMonitor && runningCapability == capability
            && monitoringSessionID != nil && monitoringSessionID == sessionIDProvider()
    }

    func deliveryValidation() -> @MainActor @Sendable () -> Bool {
        let generation = monitoringGeneration
        let session = monitoringSessionID
        return { [weak self] in
            guard let self else { return false }
            return self.canProcessLocationEvents && self.monitoringGeneration == generation
                && self.monitoringSessionID == session
        }
    }

    func requestAuthorizationForExcursionMode() {
        guard isForeground else { return }
        authorizationStatus = locationManager.authorizationStatus
        switch authorizationStatus {
        case .notDetermined: locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            if !isMacCatalyst { locationManager.requestAlwaysAuthorization() }
        default: break
        }
    }

    func currentAuthorizationStatus() -> CLAuthorizationStatus {
        authorizationStatus = locationManager.authorizationStatus
        return authorizationStatus
    }

    func refreshAuthorizationState() {
        authorizationStatus = locationManager.authorizationStatus
        accuracyAuthorization = locationManager.accuracyAuthorization
        startMonitoringIfPossible()
        NotificationCenter.default.post(name: Self.authorizationDidChangeNotification, object: self)
    }

    func setApplicationInForeground(_ foreground: Bool) {
        guard isForeground != foreground else { return }
        isForeground = foreground
        refreshAuthorizationState()
    }

    func startMonitoringIfPossible() {
        guard let session = sessionIDProvider(), capability.canMonitor else {
            stopMonitoringAllRegions()
            return
        }
        guard runningCapability != capability || monitoringSessionID != session else { return }
        // Persist only delivered-stop suppression, never an unfinished dwell interval.
        let sameSession = defaults.string(forKey: Key.session) == session
        let cachedPreferences = defaults.data(forKey: Key.preferences).flatMap {
            try? JSONDecoder().decode(ExcursionPreferences.self, from: $0)
        }
        let savedMerchants = sameSession && cachedPreferences == preferences
            ? decodeMerchants(Key.merchants).filter { preferences.allows(categoryID: $0.poiCategoryID) } : []
        let savedStop = sameSession ? decodeMerchants(Key.delivered) : []
        let savedWorkspace = sameSession ? defaults.string(forKey: Key.workspace).flatMap(UUID.init(uuidString:)) : nil
        stopMonitoringAllRegions()
        monitoringGeneration = UUID()
        monitoringSessionID = session
        runningCapability = capability
        workspaceID = savedWorkspace ?? workspaceIDProvider()
        persistPreferences()
        defaults.set(session, forKey: Key.session)
        defaults.set(workspaceID?.uuidString, forKey: Key.workspace)
        dwell.markDelivered(merchants: savedStop)
        persist(savedStop, key: Key.delivered)
        merchants = savedMerchants
        if runningCapability == .foregroundOnly {
            locationManager.setExcursionBackgroundUpdates(false)
            locationManager.startUpdatingLocation()
        } else {
            locationManager.setExcursionBackgroundUpdates(true)
            locationManager.startMonitoringSignificantLocationChanges()
            applyRegions()
        }
        requestDiscovery()
    }

    func stopMonitoringAllRegions() {
        ShoppingModeSuggestionService.shared.cancelPendingSuggestion()
        monitoringGeneration = UUID()
        monitoringSessionID = nil
        runningCapability = nil
        locationManager.stopUpdatingLocation()
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 50
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.setExcursionBackgroundUpdates(false)
        for region in locationManager.monitoredRegions where region.identifier.hasPrefix("shopping_mode.") {
            locationManager.stopMonitoring(for: region)
        }
        retryTask?.cancel(); retryTask = nil
        locationTimeoutTask?.cancel(); locationTimeoutTask = nil
        confirmationTask?.cancel(); confirmationTask = nil
        confirmationStartedAt = nil
        requiresDiscovery = false
        discoveryInFlight = false
        discoverySequence += 1
        retryAttempts = 0
        delivering = false
        stopGeneration = UUID()
        pendingDeliveryCandidates = []
        dwell.reset()
        merchants = []
        lastRefreshDate = nil
        lastRefreshLocation = nil
        if sessionIDProvider() == nil {
            for key in [Key.session, Key.workspace, Key.merchants, Key.delivered, Key.preferences] { defaults.removeObject(forKey: key) }
        }
    }

    private func applyPreferences(_ value: ExcursionPreferences) {
        guard value != preferences else { return }
        preferences = value
        let deliveredStop = dwell.deliveredRegions
        // Invalidate all work before replacing regions. A late search or queued
        // notification from the previous selection cannot reintroduce excluded POIs.
        monitoringGeneration = UUID()
        stopGeneration = UUID()
        discoverySequence += 1
        discoveryInFlight = false
        delivering = false
        pendingDeliveryCandidates = []
        requiresDiscovery = false
        retryTask?.cancel(); retryTask = nil
        retryAttempts = 0
        locationTimeoutTask?.cancel(); locationTimeoutTask = nil
        endConfirmation(resetDwell: true)
        ShoppingModeSuggestionService.shared.cancelPendingSuggestion()
        dwell = ExcursionDwellTracker(dwellSeconds: value.dwellSeconds)
        dwell.markDelivered(merchants: deliveredStop)
        merchants = []
        persist([], key: Key.merchants)
        persistPreferences()
        lastRefreshLocation = nil
        lastRefreshDate = nil
        for region in locationManager.monitoredRegions where region.identifier.hasPrefix("shopping_mode.") {
            locationManager.stopMonitoring(for: region)
        }
        trace("preferences changed: dwell=\(value.dwellSeconds)s; refreshing eligible places")
        if canProcessLocationEvents { requestDiscovery() }
    }

    private func persistPreferences() {
        if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: Key.preferences) }
    }

    private func requestDiscovery() {
        guard canProcessLocationEvents else { return }
        requiresDiscovery = true
        locationManager.requestLocation()
        locationTimeoutTask?.cancel()
        let validation = deliveryValidation()
        locationTimeoutTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(12)) } catch { return }
            guard let self, validation(), self.requiresDiscovery else { return }
            self.requiresDiscovery = false
            self.scheduleRetry()
        }
    }

    private func discover(at location: CLLocation) {
        guard !discoveryInFlight else { return }
        requiresDiscovery = false
        locationTimeoutTask?.cancel(); locationTimeoutTask = nil
        discoveryInFlight = true
        discoverySequence += 1
        let sequence = discoverySequence
        let requestedPreferences = preferences
        let validation = deliveryValidation()
        Task { [weak self] in
            guard let self else { return }
            let discovered = await self.discoverMerchants(location, requestedPreferences)
            let found = discovered.filter { requestedPreferences.allows(categoryID: $0.poiCategoryID) }
            guard validation(), sequence == self.discoverySequence else { return }
            self.discoveryInFlight = false
            guard !found.isEmpty else {
                self.merchants = []
                self.persist([], key: Key.merchants)
                self.applyRegions()
                self.lastRefreshLocation = location
                self.lastRefreshDate = self.now()
                self.endConfirmation(resetDwell: true)
                self.trace("no matching places; no fallback to excluded categories")
                self.scheduleRetry()
                return
            }
            self.retryAttempts = 0
            self.retryTask?.cancel(); self.retryTask = nil
            self.merchants = Array(found.prefix(ShoppingModeMerchantCatalog.maxMonitoredRegions))
            self.persist(self.merchants, key: Key.merchants)
            self.applyRegions()
            self.lastRefreshLocation = location
            self.lastRefreshDate = self.now()
            self.process(location)
            if self.confirmationStartedAt == nil { self.locationManager.requestLocation() }
        }
    }

    private func applyRegions() {
        guard runningCapability == .background, monitoringAvailable() else { return }
        let identifiers = Set(merchants.map { scorer.regionIdentifier(for: $0) })
        for region in locationManager.monitoredRegions where region.identifier.hasPrefix("shopping_mode.") && !identifiers.contains(region.identifier) {
            locationManager.stopMonitoring(for: region)
        }
        for merchant in merchants {
            let identifier = scorer.regionIdentifier(for: merchant)
            guard !locationManager.monitoredRegions.contains(where: { $0.identifier == identifier }) else { continue }
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: merchant.latitude, longitude: merchant.longitude),
                radius: min(merchant.radiusMeters, locationManager.maximumRegionMonitoringDistance), identifier: identifier
            )
            region.notifyOnEntry = true
            region.notifyOnExit = true
            locationManager.startMonitoring(for: region)
            locationManager.requestState(for: region)
        }
    }

    private func scheduleRetry() {
        guard canProcessLocationEvents, let delay = policy.retryDelay(forAttempt: retryAttempts + 1) else { return }
        retryAttempts += 1
        retryTask?.cancel()
        let validation = deliveryValidation()
        retryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard validation() else { return }
            self?.requestDiscovery()
        }
    }

    private func beginConfirmation() {
        guard confirmationStartedAt == nil, canProcessLocationEvents else { return }
        confirmationStartedAt = now()
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.startUpdatingLocation()
        let validation = deliveryValidation()
        confirmationTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(180)) } catch { return }
            guard validation() else { return }
            self?.endConfirmation(resetDwell: true)
        }
    }

    private func endConfirmation(resetDwell: Bool) {
        confirmationTask?.cancel(); confirmationTask = nil
        confirmationStartedAt = nil
        locationManager.stopUpdatingLocation()
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 50
        // When-in-use cannot use region monitoring: coarse foreground movement is its wake-up source.
        if runningCapability == .foregroundOnly && canProcessLocationEvents { locationManager.startUpdatingLocation() }
        if resetDwell {
            stopGeneration = UUID()
            dwell.resetDwell()
        }
    }

    private func process(_ location: CLLocation) {
        guard !merchants.isEmpty else {
            // A filtered search may find nothing, but fresh movement must still
            // clear an already-delivered stop after departure.
            if !dwell.deliveredRegions.isEmpty {
                _ = dwell.evaluate(location: location, merchants: [], now: now())
                persist(dwell.deliveredRegions, key: Key.delivered)
            }
            return
        }
        let currentTime = now()
        if let started = confirmationStartedAt, currentTime.timeIntervalSince(started) >= 180 {
            endConfirmation(resetDwell: true)
            return
        }
        let ranked = scorer.rankedCandidates(merchants: merchants, referenceLocation: location, insideRegionIDs: [])
        // A fresh coarse discovery fix can start accurate sampling, but cannot count toward dwell.
        let age = currentTime.timeIntervalSince(location.timestamp)
        if !ranked.isEmpty, dwell.deliveredRegions.isEmpty, location.speed <= 8,
           location.horizontalAccuracy > 0, age >= 0, age <= 30 {
            beginConfirmation()
        }
        guard ExcursionDwellTracker.qualifies(location, now: currentTime) else {
            trace("fix rejected: stale or inaccurate")
            return
        }
        trace("accuracy=\(Int(location.horizontalAccuracy))m age=\(Int(currentTime.timeIntervalSince(location.timestamp)))s candidates=" + ranked.prefix(5).map { "\($0.merchant.name):\(Int($0.distanceMeters))m" }.joined(separator: ", "))
        if !pendingDeliveryCandidates.isEmpty,
           !pendingDeliveryCandidates.contains(where: {
               location.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) <= $0.radiusMeters
           }) {
            stopGeneration = UUID()
            pendingDeliveryCandidates = []
        }
        let candidates = dwell.evaluate(location: location, merchants: merchants, now: currentTime)
        persist(dwell.deliveredRegions, key: Key.delivered)
        if ranked.isEmpty || location.speed > 8 {
            stopGeneration = UUID()
            if confirmationStartedAt != nil { endConfirmation(resetDwell: true) }
            return
        }
        guard dwell.deliveredRegions.isEmpty else { return }
        beginConfirmation()
        guard !candidates.isEmpty, !delivering, let session = monitoringSessionID, let workspaceID else { return }
        delivering = true
        pendingDeliveryCandidates = candidates
        let sessionValidation = deliveryValidation()
        let stop = stopGeneration
        let validation: @MainActor @Sendable () -> Bool = { [weak self] in
            guard let self else { return false }
            return sessionValidation() && self.stopGeneration == stop
        }
        let suggestion = ExcursionSuggestion(
            candidates: candidates.map { .init(id: $0.id, name: $0.name) },
            workspaceID: workspaceID, sessionID: session
        )
        Task { [weak self] in
            guard let self else { return }
            let result = await self.sendSuggestion(suggestion, location, validation)
            guard sessionValidation() else { return }
            self.delivering = false
            self.pendingDeliveryCandidates = []
            guard validation() else { return }
            switch result {
            case .scheduled:
                self.dwell.markDelivered(merchants: candidates)
                self.persist(candidates, key: Key.delivered)
                self.endConfirmation(resetDwell: false)
                self.trace("notification scheduled")
            case .suppressed: self.trace("notification suppressed")
            case .failed: self.trace("notification scheduling failed")
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { refreshAuthorizationState() }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard canProcessLocationEvents else {
            if monitoringSessionID != nil { stopMonitoringAllRegions() }
            return
        }
        guard let latest = locations.max(by: { $0.timestamp < $1.timestamp }) else { return }
        // Discovery may use a coarser fresh fix; it must never establish dwell.
        let age = now().timeIntervalSince(latest.timestamp)
        guard latest.horizontalAccuracy > 0, age >= 0, age <= 30 else { return }
        if requiresDiscovery { discover(at: latest) }
        else if let baseline = lastRefreshLocation, let date = lastRefreshDate,
                policy.shouldRefreshMovement(previousLocation: baseline, previousDate: date, newLocation: latest, now: now()) {
            discover(at: latest)
        }
        process(latest)
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) { reevaluate(region) }
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) { reevaluate(region) }
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        if state != .unknown { reevaluate(region) }
    }

    private func reevaluate(_ region: CLRegion) {
        guard canProcessLocationEvents, region.identifier.hasPrefix("shopping_mode.") else { return }
        // Every callback requests the same evaluation, never a merchant-specific pending request.
        locationManager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        trace("location error: \(error.localizedDescription)")
        if requiresDiscovery { requiresDiscovery = false; scheduleRetry() }
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        trace("region monitoring failed: \(error.localizedDescription)")
    }

    private func persist(_ values: [ShoppingModeMerchant], key: String) {
        if let encoded = try? JSONEncoder().encode(values) { defaults.set(encoded, forKey: key) }
    }

    private func decodeMerchants(_ key: String) -> [ShoppingModeMerchant] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ShoppingModeMerchant].self, from: data)) ?? []
    }

    private func trace(_ message: String) {
        #if DEBUG
        let key = "debug_excursionDetectionTrace"
        var entries = defaults.stringArray(forKey: key) ?? []
        entries.append("\(now().ISO8601Format()) \(message)")
        defaults.set(Array(entries.suffix(100)), forKey: key)
        print("[ExcursionDetection] \(message)")
        #endif
    }
}
