import Foundation
import CoreLocation
import MapKit
import Testing
@testable import Offshore

@MainActor
struct ExcursionLocationServiceTests {
    @MainActor
    private final class LocationClient: ExcursionLocationClient {
        var delegate: (any CLLocationManagerDelegate)?
        var accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy
        var maximumRegionMonitoringDistance: CLLocationDistance = 100_000
        var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
        var desiredAccuracy: CLLocationAccuracy = 0
        var distanceFilter: CLLocationDistance = 0
        var monitoredRegions: Set<CLRegion> = []
        var whenInUseRequests = 0
        var alwaysRequests = 0
        var standardStarts = 0
        var standardStops = 0
        var significantStarts = 0
        var backgroundUpdates = false
        var locationRequests = 0

        func requestWhenInUseAuthorization() { whenInUseRequests += 1 }
        func requestAlwaysAuthorization() { alwaysRequests += 1 }
        func requestLocation() { locationRequests += 1 }
        func startUpdatingLocation() { standardStarts += 1 }
        func stopUpdatingLocation() { standardStops += 1 }
        func startMonitoringSignificantLocationChanges() { significantStarts += 1 }
        func stopMonitoringSignificantLocationChanges() { }
        func startMonitoring(for region: CLRegion) { monitoredRegions.insert(region) }
        func stopMonitoring(for region: CLRegion) { monitoredRegions.remove(region) }
        func requestState(for region: CLRegion) { }
        func setExcursionBackgroundUpdates(_ enabled: Bool) { backgroundUpdates = enabled }
    }

    @MainActor
    private final class Session {
        var id: String? = "session-one"
    }

    @MainActor
    private final class Discovery {
        var result: CheckedContinuation<[ShoppingModeMerchant], Never>?
        var started: CheckedContinuation<Void, Never>?
        func search() async -> [ShoppingModeMerchant] {
            await withCheckedContinuation { continuation in
                result = continuation
                started?.resume()
                started = nil
            }
        }
        func waitUntilStarted() async {
            if result != nil { return }
            await withCheckedContinuation { started = $0 }
        }
    }

    private func withService(
        status: CLAuthorizationStatus = .authorizedWhenInUse,
        foreground: Bool = true,
        catalyst: Bool = false,
        discovery: ((CLLocation) async -> [ShoppingModeMerchant])? = nil,
        operation: (ShoppingModeLocationService, LocationClient, Session) async throws -> Void
    ) async rethrows {
        let name = "ExcursionLocationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let client = LocationClient()
        client.authorizationStatus = status
        let session = Session()
        let service = ShoppingModeLocationService(
            locationManager: client, defaults: defaults, isForeground: foreground,
            isMacCatalyst: catalyst, sessionIDProvider: { session.id },
            monitoringAvailable: { true }, discoverMerchants: discovery ?? { _ in [] },
            preferencesStore: ExcursionPreferencesStore(defaults: defaults)
        )
        defer { service.stopMonitoringAllRegions() }
        try await operation(service, client, session)
    }

    @Test func initialPermissionIsRequestedOnlyByUserAction() async {
        await withService(status: .notDetermined) { service, client, _ in
            service.startMonitoringIfPossible()
            #expect(client.whenInUseRequests == 0 && client.alwaysRequests == 0)
            service.requestAuthorizationForExcursionMode()
            #expect(client.whenInUseRequests == 1)
            client.authorizationStatus = .authorizedWhenInUse
            service.refreshAuthorizationState()
            #expect(client.alwaysRequests == 0)
            service.requestAuthorizationForExcursionMode()
            #expect(client.alwaysRequests == 1)
            service.startMonitoringIfPossible()
            service.refreshAuthorizationState()
            #expect(client.alwaysRequests == 1) // No automatic retry after Keep While Using / ignored upgrade.
        }
    }

    @Test func allowOnceExpirationDoesNotCreatePermissionLoop() async {
        await withService { service, client, _ in
            service.startMonitoringIfPossible()
            service.requestAuthorizationForExcursionMode()
            #expect(client.alwaysRequests == 1)
            client.authorizationStatus = .notDetermined
            service.setApplicationInForeground(false)
            service.setApplicationInForeground(true)
            #expect(service.capability == .needsPermission)
            #expect(!service.canProcessLocationEvents)
            #expect(client.whenInUseRequests == 0)
            service.requestAuthorizationForExcursionMode()
            #expect(client.whenInUseRequests == 1)
        }
    }

    @Test func limitedModePausesWithoutEndingSessionAndResumesWithNewLease() async {
        await withService { service, client, session in
            service.startMonitoringIfPossible()
            let original = service.deliveryValidation()
            #expect(service.capability == .foregroundOnly && original())
            #expect(client.standardStarts == 1 && client.significantStarts == 0)
            #expect(!client.backgroundUpdates)
            service.setApplicationInForeground(false)
            #expect(service.capability == .paused && !original())
            #expect(!service.canProcessLocationEvents)
            #expect(session.id == "session-one")
            service.setApplicationInForeground(true)
            #expect(client.standardStarts == 2)
            #expect(service.canProcessLocationEvents && !original())
            #expect(service.deliveryValidation()())
        }
    }

    @Test func alwaysAccessKeepsMonitoringInBackground() async {
        await withService(status: .authorizedAlways) { service, client, _ in
            service.startMonitoringIfPossible()
            let lease = service.deliveryValidation()
            service.setApplicationInForeground(false)
            #expect(service.capability == .background && lease())
            #expect(client.significantStarts == 1 && client.standardStarts == 0)
            #expect(client.backgroundUpdates)
        }
    }

    @Test func upgradeAndBackgroundDowngradeReplaceMonitoringSafely() async {
        await withService { service, client, _ in
            service.startMonitoringIfPossible()
            let foregroundLease = service.deliveryValidation()
            client.authorizationStatus = .authorizedAlways
            service.refreshAuthorizationState()
            #expect(service.capability == .background)
            #expect(!foregroundLease() && client.significantStarts == 1)
            let backgroundLease = service.deliveryValidation()
            service.setApplicationInForeground(false)
            client.authorizationStatus = .authorizedWhenInUse
            service.refreshAuthorizationState()
            #expect(service.capability == .paused && !backgroundLease())
            #expect(!client.backgroundUpdates && client.monitoredRegions.isEmpty)
        }
    }

    @Test(arguments: [CLAuthorizationStatus.denied, .restricted, .notDetermined])
    func lostPermissionStopsMonitoring(_ status: CLAuthorizationStatus) async {
        await withService { service, client, _ in
            service.startMonitoringIfPossible()
            let lease = service.deliveryValidation()
            client.authorizationStatus = status
            service.refreshAuthorizationState()
            #expect(!lease() && !service.canProcessLocationEvents)
            #expect(client.monitoredRegions.isEmpty && !client.backgroundUpdates)
        }
    }

    @Test func stoppedOrReplacedSessionInvalidatesPendingWork() async {
        await withService { service, _, session in
            service.startMonitoringIfPossible()
            let oldLease = service.deliveryValidation()
            session.id = "session-two"
            #expect(!oldLease())
            service.startMonitoringIfPossible()
            let newLease = service.deliveryValidation()
            #expect(newLease())
            session.id = nil // Also represents the authoritative session timer expiring.
            #expect(!newLease())
            service.startMonitoringIfPossible()
            #expect(!service.canProcessLocationEvents)
        }
    }

    @Test func catalystKeepsExistingPermissionEquivalence() async {
        await withService(foreground: false, catalyst: true) { service, client, _ in
            service.startMonitoringIfPossible()
            #expect(service.capability == .background && service.canProcessLocationEvents)
            #expect(client.significantStarts == 1)
            #expect(client.alwaysRequests == 0)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func discoveryReturningAfterBackgroundCannotRestoreRegions() async {
        let discovery = Discovery()
        await withService(discovery: { _ in await discovery.search() }) { service, client, _ in
            service.startMonitoringIfPossible()
            service.locationManager(CLLocationManager(), didUpdateLocations: [CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 37, longitude: -122), altitude: 0,
                horizontalAccuracy: 20, verticalAccuracy: 20, timestamp: .now
            )])
            await discovery.waitUntilStarted()
            service.setApplicationInForeground(false)
            discovery.result?.resume(returning: [ShoppingModeMerchant(
                id: "shop", name: "Shop", latitude: 37, longitude: -122, radiusMeters: 100, categoryHint: "Shopping"
            )])
            for _ in 0..<3 { await Task.yield() }
            #expect(client.monitoredRegions.isEmpty)
            #expect(!service.canProcessLocationEvents)
            #expect(client.locationRequests == 1)
        }
    }

    @MainActor
    private final class Replay {
        let epoch = Date(timeIntervalSince1970: 1_800_000_000)
        let workspaceID = UUID()
        var selectedWorkspaceID = UUID()
        var time: Date
        var sessionID: String? = "replay-session"
        var delivered: [ExcursionSuggestion] = []
        var attempts = 0
        var failsNextDelivery = false
        var authorizationDuringDelivery: CLAuthorizationStatus?
        var expireDuringDelivery = false
        var suspendDelivery = false
        var suspendedDelivery: CheckedContinuation<Void, Never>?

        let preferencesStore: ExcursionPreferencesStore
        init(defaults: UserDefaults) {
            time = epoch
            selectedWorkspaceID = workspaceID
            preferencesStore = ExcursionPreferencesStore(defaults: defaults)
            preferencesStore.update(ExcursionPreferences(mode: .all, categoryIDs: [], dwellSeconds: 120))
        }
    }

    private func withReplay(
        operation: (ShoppingModeLocationService, LocationClient, Replay) async -> Void
    ) async {
        let suite = "ExcursionReplay.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let replay = Replay(defaults: defaults)
        let client = LocationClient()
        client.authorizationStatus = .authorizedAlways
        let near = ShoppingModeMerchant(id: "near", name: "Nearby Merchant", latitude: 37.00082,
                                        longitude: -122, radiusMeters: 150, categoryHint: "Dining", poiCategoryID: MKPointOfInterestCategory.restaurant.rawValue)
        let far = ShoppingModeMerchant(id: "far", name: "Farther Merchant", latitude: 37.0029,
                                       longitude: -122, radiusMeters: 400, categoryHint: "Shopping", poiCategoryID: MKPointOfInterestCategory.store.rawValue)
        let service = ShoppingModeLocationService(
            locationManager: client, defaults: defaults, isForeground: true, isMacCatalyst: false,
            sessionIDProvider: { replay.sessionID }, monitoringAvailable: { true },
            discoverMerchants: { _ in [far, near] }, workspaceIDProvider: { replay.selectedWorkspaceID },
            now: { replay.time }, sendSuggestion: { suggestion, _, validation in
                replay.attempts += 1
                if replay.expireDuringDelivery { replay.sessionID = nil }
                if let authorization = replay.authorizationDuringDelivery { client.authorizationStatus = authorization }
                if replay.suspendDelivery {
                    await withCheckedContinuation { replay.suspendedDelivery = $0 }
                }
                await Task.yield()
                guard validation() else { return .suppressed }
                if replay.failsNextDelivery {
                    replay.failsNextDelivery = false
                    return .failed
                }
                replay.delivered.append(suggestion)
                return .scheduled(identifier: "notification-\(replay.attempts)")
            }, preferencesStore: replay.preferencesStore
        )
        defer { service.stopMonitoringAllRegions() }
        service.startMonitoringIfPossible()
        await operation(service, client, replay)
    }

    private func feed(_ seconds: Double, service: ShoppingModeLocationService, replay: Replay,
                      latitude: Double = 37, accuracy: Double = 20) async {
        replay.time = replay.epoch.addingTimeInterval(seconds)
        service.locationManager(CLLocationManager(), didUpdateLocations: [CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: -122), altitude: 0,
            horizontalAccuracy: accuracy, verticalAccuracy: 20, course: 0, speed: 0, timestamp: replay.time
        )])
        // Discovery and delivery run in main-actor tasks; allow those finite tasks to finish.
        for _ in 0..<20 { await Task.yield() }
    }

    @Test(arguments: [false, true])
    func dwellReplayIgnoresRegionCallbackOrder(_ reverse: Bool) async {
        await withReplay { service, client, replay in
            await feed(0, service: service, replay: replay)
            let regions = client.monitoredRegions.sorted { $0.identifier < $1.identifier }
            #expect(regions.count == 2)
            #expect(regions.allSatisfy { ($0 as? CLCircularRegion)?.notifyOnExit == true })
            for region in reverse ? Array(regions.reversed()) : regions {
                service.locationManager(CLLocationManager(), didEnterRegion: region)
                service.locationManager(CLLocationManager(), didDetermineState: .inside, for: region)
            }
            for time in [30.0, 60, 90] {
                await feed(time, service: service, replay: replay)
                #expect(replay.delivered.isEmpty)
            }
            await feed(120, service: service, replay: replay)
            #expect(replay.delivered.count == 1)
            #expect(replay.delivered.first?.candidates.first?.id == "near")
            #expect(replay.delivered.first?.workspaceID == replay.workspaceID)
            #expect(client.desiredAccuracy == kCLLocationAccuracyHundredMeters)
        }
    }

    @Test func deliveredStopDoesNotRepeatAndFreshDepartureRearms() async {
        await withReplay { service, _, replay in
            for time in [0.0, 30, 60, 90, 120, 150] { await feed(time, service: service, replay: replay) }
            #expect(replay.delivered.count == 1)
            await feed(180, service: service, replay: replay, latitude: 37.01)
            for time in [210.0, 240, 270, 300] { await feed(time, service: service, replay: replay) }
            #expect(replay.delivered.count == 1)
            await feed(330, service: service, replay: replay)
            #expect(replay.delivered.count == 2)
        }
    }

    @Test func failedSchedulingDoesNotConsumeStop() async {
        await withReplay { service, _, replay in
            replay.failsNextDelivery = true
            for time in [0.0, 30, 60, 90, 120] { await feed(time, service: service, replay: replay) }
            #expect(replay.attempts == 1)
            #expect(replay.delivered.isEmpty)
            await feed(130, service: service, replay: replay)
            #expect(replay.attempts == 2)
            #expect(replay.delivered.count == 1)
        }
    }

    @Test(arguments: [false, true])
    func sessionExpiryOrPermissionLossCancelsInFlightDelivery(_ expire: Bool) async {
        await withReplay { service, client, replay in
            for time in [0.0, 30, 60, 90] { await feed(time, service: service, replay: replay) }
            replay.expireDuringDelivery = expire
            replay.authorizationDuringDelivery = expire ? nil : .denied
            await feed(120, service: service, replay: replay)
            #expect(replay.attempts == 1 && replay.delivered.isEmpty)
            #expect(!service.canProcessLocationEvents)
            await feed(150, service: service, replay: replay)
            #expect(client.monitoredRegions.isEmpty && !client.backgroundUpdates)
        }
    }

    @Test func reducedAccuracyStopsActiveConfirmation() async {
        await withReplay { service, client, replay in
            await feed(0, service: service, replay: replay)
            #expect(client.desiredAccuracy == kCLLocationAccuracyNearestTenMeters)
            client.accuracyAuthorization = .reducedAccuracy
            service.refreshAuthorizationState()
            #expect(service.capability == .preciseLocationRequired)
            #expect(!service.canProcessLocationEvents)
            #expect(client.monitoredRegions.isEmpty && !client.backgroundUpdates)
            await feed(120, service: service, replay: replay)
            #expect(replay.attempts == 0)
        }
    }

    @Test func selectedWorkspaceChangesDoNotRetargetActiveSession() async {
        await withReplay { service, _, replay in
            await feed(0, service: service, replay: replay)
            replay.selectedWorkspaceID = UUID()
            for time in [30.0, 60, 90, 120] { await feed(time, service: service, replay: replay) }
            #expect(replay.delivered.first?.workspaceID == replay.workspaceID)
            #expect(replay.delivered.first?.workspaceID != replay.selectedWorkspaceID)
        }
    }


    @Test func incompleteDwellStopsAtThreeMinuteSamplingDeadline() async {
        await withReplay { service, client, replay in
            await feed(0, service: service, replay: replay)
            await feed(60, service: service, replay: replay)
            await feed(121, service: service, replay: replay) // Gap resets evidence.
            #expect(client.desiredAccuracy == kCLLocationAccuracyNearestTenMeters)
            await feed(180, service: service, replay: replay)
            #expect(replay.attempts == 0)
            #expect(client.desiredAccuracy == kCLLocationAccuracyHundredMeters)
        }
    }


    @Test func departureIntoAnotherMerchantCancelsSuspendedSuggestion() async {
        await withReplay { service, _, replay in
            replay.suspendDelivery = true
            for time in [0.0, 30, 60, 90, 120] { await feed(time, service: service, replay: replay) }
            #expect(replay.attempts == 1)
            #expect(replay.suspendedDelivery != nil)
            // Outside the near merchant, but still within the farther merchant's region.
            await feed(130, service: service, replay: replay, latitude: 37.004)
            replay.suspendDelivery = false
            replay.suspendedDelivery?.resume()
            replay.suspendedDelivery = nil
            for _ in 0..<20 { await Task.yield() }
            #expect(replay.delivered.isEmpty)
        }
    }

    @Test func coarseDiscoveryFixStartsAccurateSamplingWithoutCountingDwell() async {
        await withReplay { service, client, replay in
            await feed(0, service: service, replay: replay, accuracy: 100)
            #expect(client.desiredAccuracy == kCLLocationAccuracyNearestTenMeters)
            for time in [30.0, 60, 90, 120] { await feed(time, service: service, replay: replay) }
            #expect(replay.delivered.isEmpty)
            await feed(150, service: service, replay: replay)
            #expect(replay.delivered.count == 1)
        }
    }

    @Test func relaunchedSessionRetainsDeliveredStopAndOriginWorkspace() async {
        let suite = "ExcursionRelaunch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let replay = Replay(defaults: defaults)
        let merchant = ShoppingModeMerchant(id: "shop", name: "Shop", latitude: 37,
                                            longitude: -122, radiusMeters: 150, categoryHint: "Shopping")
        func makeService() -> ShoppingModeLocationService {
            let client = LocationClient()
            client.authorizationStatus = .authorizedAlways
            return ShoppingModeLocationService(
                locationManager: client, defaults: defaults, isForeground: true, isMacCatalyst: false,
                sessionIDProvider: { replay.sessionID }, monitoringAvailable: { true },
                discoverMerchants: { _ in [merchant] }, workspaceIDProvider: { replay.selectedWorkspaceID },
                now: { replay.time }, sendSuggestion: { suggestion, _, validation in
                    guard validation() else { return .suppressed }
                    replay.delivered.append(suggestion)
                    return .scheduled(identifier: UUID().uuidString)
                }, preferencesStore: replay.preferencesStore
            )
        }
        let first = makeService()
        first.startMonitoringIfPossible()
        for time in [0.0, 30, 60, 90, 120] { await feed(time, service: first, replay: replay) }
        #expect(replay.delivered.count == 1)
        first.stopMonitoringAllRegions()
        replay.selectedWorkspaceID = UUID()
        let restored = makeService()
        defer { restored.stopMonitoringAllRegions() }
        restored.startMonitoringIfPossible()
        for time in [150.0, 180, 210, 240, 270] { await feed(time, service: restored, replay: replay) }
        #expect(replay.delivered.count == 1)
        await feed(300, service: restored, replay: replay, latitude: 37.01)
        for time in [330.0, 360, 390, 420, 450] { await feed(time, service: restored, replay: replay) }
        #expect(replay.delivered.count == 2)
        #expect(replay.delivered.last?.workspaceID == replay.workspaceID)
    }

    @Test func defaultPreferencesDeliverAtFortyFiveSeconds() async {
        await withReplay { service, _, replay in
            replay.preferencesStore.restoreDefaults()
            for time in [0.0, 15, 30, 44] { await feed(time, service: service, replay: replay) }
            #expect(replay.delivered.isEmpty)
            await feed(45, service: service, replay: replay)
            #expect(replay.delivered.count == 1)
        }
    }

    @Test func changingTimingRestartsUnfinishedDwellWithoutChangingSession() async {
        await withReplay { service, _, replay in
            for time in [0.0, 30, 60] { await feed(time, service: service, replay: replay) }
            let previousLease = service.deliveryValidation()
            replay.preferencesStore.restoreDefaults()
            #expect(!previousLease())
            #expect(replay.sessionID == "replay-session")
            for time in [60.0, 75, 90, 104] { await feed(time, service: service, replay: replay) }
            #expect(replay.delivered.isEmpty)
            await feed(105, service: service, replay: replay)
            #expect(replay.delivered.first?.workspaceID == replay.workspaceID)
            #expect(replay.delivered.count == 1)
        }
    }

    @Test func changingCategoriesReplacesRegionsAndCandidatesImmediately() async {
        await withReplay { service, client, replay in
            await feed(0, service: service, replay: replay)
            #expect(client.monitoredRegions.count == 2)
            replay.preferencesStore.update(.init(mode: .custom,
                categoryIDs: [MKPointOfInterestCategory.store.rawValue], dwellSeconds: 45))
            #expect(client.monitoredRegions.isEmpty)
            for time in [15.0, 30, 45, 60] { await feed(time, service: service, replay: replay) }
            #expect(client.monitoredRegions.count == 1)
            #expect(replay.delivered.first?.candidates.map(\.id) == ["far"])
        }
    }

    @Test func noMatchingCategoriesCannotRestoreOldRegionsOrNotify() async {
        await withReplay { service, client, replay in
            await feed(0, service: service, replay: replay)
            replay.preferencesStore.update(.init(mode: .custom,
                categoryIDs: [MKPointOfInterestCategory.gasStation.rawValue], dwellSeconds: 45))
            for time in [15.0, 30, 45, 60, 90, 120] { await feed(time, service: service, replay: replay) }
            #expect(client.monitoredRegions.isEmpty)
            #expect(replay.delivered.isEmpty)
        }
    }

    @Test func preferencesDoNotRepeatAnAlreadyDeliveredStop() async {
        await withReplay { service, _, replay in
            for time in [0.0, 30, 60, 90, 120] { await feed(time, service: service, replay: replay) }
            #expect(replay.delivered.count == 1)
            replay.preferencesStore.update(.init(mode: .custom,
                categoryIDs: [MKPointOfInterestCategory.store.rawValue], dwellSeconds: 45))
            for time in [135.0, 150, 165, 180, 195] { await feed(time, service: service, replay: replay) }
            #expect(replay.delivered.count == 1)
            await feed(210, service: service, replay: replay, latitude: 37.01)
            for time in [225.0, 240, 255, 270] { await feed(time, service: service, replay: replay) }
            #expect(replay.delivered.count == 2)
            #expect(replay.delivered.last?.candidates.map(\.id) == ["far"])
        }
    }

    @Test func preferencesCancelAnInFlightSuggestion() async {
        await withReplay { service, _, replay in
            replay.suspendDelivery = true
            for time in [0.0, 30, 60, 90, 120] { await feed(time, service: service, replay: replay) }
            #expect(replay.suspendedDelivery != nil)
            replay.preferencesStore.update(.init(mode: .custom,
                categoryIDs: [MKPointOfInterestCategory.store.rawValue], dwellSeconds: 45))
            replay.suspendDelivery = false
            replay.suspendedDelivery?.resume()
            replay.suspendedDelivery = nil
            for time in [135.0, 150, 165] { await feed(time, service: service, replay: replay) }
            #expect(replay.delivered.isEmpty)
            await feed(180, service: service, replay: replay)
            #expect(replay.delivered.count == 1)
            #expect(replay.delivered.first?.candidates.map(\.id) == ["far"])
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func preferencesInvalidateAnOutstandingDiscovery() async {
        let suite = "ExcursionPreferencesDiscovery.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let replay = Replay(defaults: defaults)
        let client = LocationClient()
        client.authorizationStatus = .authorizedAlways
        let discovery = Discovery()
        var searches = 0
        let shop = ShoppingModeMerchant(id: "shop", name: "Shop", latitude: 37, longitude: -122,
            radiusMeters: 150, categoryHint: "Shopping", poiCategoryID: MKPointOfInterestCategory.store.rawValue)
        let service = ShoppingModeLocationService(locationManager: client, defaults: defaults,
            isForeground: true, sessionIDProvider: { replay.sessionID }, monitoringAvailable: { true },
            discoverMerchants: { _ in
                searches += 1
                if searches == 1 { return await discovery.search() }
                return [shop]
            }, now: { replay.time }, preferencesStore: replay.preferencesStore)
        defer { service.stopMonitoringAllRegions() }
        service.startMonitoringIfPossible()
        await feed(0, service: service, replay: replay)
        await discovery.waitUntilStarted()
        let stale = discovery.result
        replay.preferencesStore.update(.init(mode: .custom,
            categoryIDs: [MKPointOfInterestCategory.gasStation.rawValue], dwellSeconds: 45))
        await feed(15, service: service, replay: replay)
        stale?.resume(returning: [shop])
        for _ in 0..<20 { await Task.yield() }
        #expect(client.monitoredRegions.isEmpty)
        #expect(searches == 2)
    }

    @Test func departureStillRearmsWhenFiltersFindNoMerchants() async {
        await withReplay { service, _, replay in
            for time in [0.0, 30, 60, 90, 120] { await feed(time, service: service, replay: replay) }
            #expect(replay.delivered.count == 1)
            replay.preferencesStore.update(.init(mode: .custom,
                categoryIDs: [MKPointOfInterestCategory.gasStation.rawValue], dwellSeconds: 45))
            await feed(135, service: service, replay: replay, latitude: 37.01)
            await feed(150, service: service, replay: replay)
            replay.preferencesStore.restoreDefaults()
            for time in [165.0, 180, 195, 210] { await feed(time, service: service, replay: replay) }
            #expect(replay.delivered.count == 2)
        }
    }

}
