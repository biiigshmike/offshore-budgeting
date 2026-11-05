import CoreLocation

@MainActor
protocol ExcursionLocationClient: AnyObject {
    var delegate: (any CLLocationManagerDelegate)? { get set }
    var accuracyAuthorization: CLAccuracyAuthorization { get }
    var maximumRegionMonitoringDistance: CLLocationDistance { get }
    var authorizationStatus: CLAuthorizationStatus { get }
    var desiredAccuracy: CLLocationAccuracy { get set }
    var distanceFilter: CLLocationDistance { get set }
    var monitoredRegions: Set<CLRegion> { get }
    func requestWhenInUseAuthorization()
    func requestAlwaysAuthorization()
    func requestLocation()
    func startUpdatingLocation()
    func stopUpdatingLocation()
    func startMonitoringSignificantLocationChanges()
    func stopMonitoringSignificantLocationChanges()
    func startMonitoring(for region: CLRegion)
    func stopMonitoring(for region: CLRegion)
    func requestState(for region: CLRegion)
    func setExcursionBackgroundUpdates(_ enabled: Bool)
}

extension CLLocationManager: ExcursionLocationClient {
    func setExcursionBackgroundUpdates(_ enabled: Bool) {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        allowsBackgroundLocationUpdates = enabled
        #endif
    }
}
