import Foundation

#if canImport(CoreLocation)
import CoreLocation
#endif

struct ExcursionDetectionPolicy {
    struct MovementRefreshThreshold: Equatable {
        let distanceMeters: CLLocationDistance
        let minimumElapsedSeconds: TimeInterval
    }

    enum NotificationBlockReason: Equatable {
        case globalCooldown
        case merchantCooldown
        case insufficientMovement
        case missingLocation
    }

    struct NotificationDecision: Equatable {
        let isAllowed: Bool
        let reason: NotificationBlockReason?
    }

    let startupDesiredAccuracyMeters: CLLocationAccuracy = 80
    let startupLocationWindowSeconds: TimeInterval = 12
    let startupMaximumSamples = 3
    let startupMinimumStableSeconds: TimeInterval = 8
    let startupRequiredConsecutiveSamples = 2

    let recentFixMaximumAgeSeconds: TimeInterval = 60
    let recentFixDesiredAccuracyMeters: CLLocationAccuracy = 80

    let walkingRefreshThreshold = MovementRefreshThreshold(
        distanceMeters: 125,
        minimumElapsedSeconds: 45
    )
    let drivingRefreshThreshold = MovementRefreshThreshold(
        distanceMeters: 250,
        minimumElapsedSeconds: 90
    )
    let highSpeedThresholdMetersPerSecond: CLLocationSpeed = 8

    let retryIntervalsSeconds: [TimeInterval] = [30, 60]

    let globalNotificationCooldownSeconds: TimeInterval = 4 * 60
    let perMerchantNotificationCooldownSeconds: TimeInterval = 20 * 60
    let minimumMovementBetweenNotificationsMeters: CLLocationDistance = 150

    func movementRefreshThreshold(for speed: CLLocationSpeed) -> MovementRefreshThreshold {
        if speed > highSpeedThresholdMetersPerSecond {
            return drivingRefreshThreshold
        }
        return walkingRefreshThreshold
    }

    func shouldRefreshMovement(
        previousLocation: CLLocation,
        previousDate: Date,
        newLocation: CLLocation,
        now: Date = .now
    ) -> Bool {
        let threshold = movementRefreshThreshold(for: max(0, newLocation.speed))
        let elapsed = now.timeIntervalSince(previousDate)
        guard elapsed >= threshold.minimumElapsedSeconds else { return false }
        return newLocation.distance(from: previousLocation) >= threshold.distanceMeters
    }

    func retryDelay(forAttempt attempt: Int) -> TimeInterval? {
        guard attempt >= 1, attempt <= retryIntervalsSeconds.count else { return nil }
        return retryIntervalsSeconds[attempt - 1]
    }

    func shouldContinueStartupSampling(
        startedAt: Date,
        samplesCollected: Int,
        now: Date = .now
    ) -> Bool {
        guard samplesCollected < startupMaximumSamples else { return false }
        return now.timeIntervalSince(startedAt) < startupLocationWindowSeconds
    }

    func acceptsStartupCandidate(
        accuracyMeters: CLLocationAccuracy,
        stableDuration: TimeInterval,
        consecutiveMatches: Int
    ) -> Bool {
        guard accuracyMeters > 0, accuracyMeters <= startupDesiredAccuracyMeters else { return false }
        if consecutiveMatches >= startupRequiredConsecutiveSamples {
            return true
        }
        return stableDuration >= startupMinimumStableSeconds
    }

    func hasRecentHighConfidenceFix(
        timestamp: Date?,
        accuracyMeters: CLLocationAccuracy,
        now: Date = .now
    ) -> Bool {
        guard let timestamp else { return false }
        guard accuracyMeters > 0, accuracyMeters <= recentFixDesiredAccuracyMeters else { return false }
        return now.timeIntervalSince(timestamp) <= recentFixMaximumAgeSeconds
    }

    func notificationDecision(
        merchantID: String,
        currentLocation: CLLocation?,
        lastGlobalFireAt: Date?,
        lastMerchantFireAt: Date?,
        lastDeliveredMerchantID: String?,
        lastDeliveredLocation: CLLocation?,
        now: Date = .now
    ) -> NotificationDecision {
        if let lastGlobalFireAt,
           now.timeIntervalSince(lastGlobalFireAt) < globalNotificationCooldownSeconds {
            return NotificationDecision(isAllowed: false, reason: .globalCooldown)
        }

        if let lastMerchantFireAt,
           now.timeIntervalSince(lastMerchantFireAt) < perMerchantNotificationCooldownSeconds {
            return NotificationDecision(isAllowed: false, reason: .merchantCooldown)
        }

        if let lastDeliveredMerchantID,
           let lastDeliveredLocation,
           lastDeliveredMerchantID == merchantID {
            guard let currentLocation else {
                return NotificationDecision(isAllowed: false, reason: .missingLocation)
            }

            if currentLocation.distance(from: lastDeliveredLocation) < minimumMovementBetweenNotificationsMeters {
                return NotificationDecision(isAllowed: false, reason: .insufficientMovement)
            }
        }

        return NotificationDecision(isAllowed: true, reason: nil)
    }
}
