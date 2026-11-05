import Foundation
import CoreLocation

/// Location availability is separate from the session's countdown.
nonisolated enum ExcursionLocationCapability: Equatable {
    case foregroundOnly
    case background
    case paused
    case needsPermission
    case denied
    case restricted
    case preciseLocationRequired

    static func resolve(authorization: CLAuthorizationStatus, isForeground: Bool, isMacCatalyst: Bool = false, accuracy: CLAccuracyAuthorization = .fullAccuracy) -> Self {
        if (authorization == .authorizedAlways || authorization == .authorizedWhenInUse), accuracy == .reducedAccuracy {
            return .preciseLocationRequired
        }
        switch authorization {
        case .authorizedAlways: return .background
        case .authorizedWhenInUse:
            return isMacCatalyst ? .background : (isForeground ? .foregroundOnly : .paused)
        case .notDetermined: return .needsPermission
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .needsPermission
        }
    }

    var canMonitor: Bool { self == .foregroundOnly || self == .background }

    var statusText: String {
        switch self {
        case .foregroundOnly: return String(localized: "Works while Offshore is open.")
        case .background: return String(localized: "Nearby reminders can work with Offshore closed.")
        case .paused: return String(localized: "Open Offshore to get nearby reminders.")
        case .needsPermission: return String(localized: "Allow location access to get nearby reminders.")
        case .denied: return String(localized: "Location access is off. You can allow it in Settings.")
        case .preciseLocationRequired: return String(localized: "Enable Precise Location in Settings for nearby reminders.")
        case .restricted: return String(localized: "Location access is restricted on this device.")
        }
    }
}
