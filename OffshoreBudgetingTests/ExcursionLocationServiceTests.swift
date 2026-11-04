import Foundation
import CoreLocation
import Testing
@testable import Offshore

@MainActor
struct ExcursionLocationServiceTests {
    @MainActor
    private final class LocationClient: ExcursionLocationClient {
        var delegate: (any CLLocationManagerDelegate)?
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
            monitoringAvailable: { true }, discoverMerchants: discovery ?? { _ in [] }
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
            service.locationManager(CLLocationManager(), didUpdateLocations: [CLLocation(latitude: 37, longitude: -122)])
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
}
