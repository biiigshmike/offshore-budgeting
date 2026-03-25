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
        case rapidRepeat
        case globalCooldown
        case merchantCooldown
        case sameStopCooldown
        case insufficientMovement
        case missingLocation
    }

    struct NotificationDecision: Equatable {
        let isAllowed: Bool
        let reason: NotificationBlockReason?
        let secondsSinceLastGlobalFire: TimeInterval?
        let secondsSinceLastMerchantFire: TimeInterval?
        let distanceFromLastDeliveredLocation: CLLocationDistance?
        let distanceFromLastStopLocation: CLLocationDistance?
        let isSameStopCluster: Bool
    }

    let startupDesiredAccuracyMeters: CLLocationAccuracy = 80
    let startupLocationWindowSeconds: TimeInterval = 12
    let startupMaximumSamples = 3
    let startupMinimumStableSeconds: TimeInterval = 8
    let startupRequiredConsecutiveSamples = 2

    let recentFixMaximumAgeSeconds: TimeInterval = 60
    let recentFixDesiredAccuracyMeters: CLLocationAccuracy = 80

    let walkingRefreshThreshold = MovementRefreshThreshold(
        distanceMeters: 60,
        minimumElapsedSeconds: 25
    )
    let drivingRefreshThreshold = MovementRefreshThreshold(
        distanceMeters: 180,
        minimumElapsedSeconds: 60
    )
    let highSpeedThresholdMetersPerSecond: CLLocationSpeed = 8

    let retryIntervalsSeconds: [TimeInterval] = [30, 60]

    let rapidRepeatGuardSeconds: TimeInterval = 75
    let globalNotificationCooldownSeconds: TimeInterval = 2 * 60
    let perMerchantNotificationCooldownSeconds: TimeInterval = 8 * 60
    let minimumMovementBetweenNotificationsMeters: CLLocationDistance = 60
    let sameStopClusterMeters: CLLocationDistance = 40

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
        lastDeliveredStopLocation: CLLocation?,
        now: Date = .now
    ) -> NotificationDecision {
        let secondsSinceLastGlobalFire = lastGlobalFireAt.map { now.timeIntervalSince($0) }
        let secondsSinceLastMerchantFire = lastMerchantFireAt.map { now.timeIntervalSince($0) }
        let distanceFromLastDeliveredLocation = distance(from: currentLocation, to: lastDeliveredLocation)
        let distanceFromLastStopLocation = distance(from: currentLocation, to: lastDeliveredStopLocation)
        let isSameStopCluster = distanceFromLastStopLocation.map { $0 < sameStopClusterMeters } ?? false

        if let secondsSinceLastGlobalFire,
           secondsSinceLastGlobalFire < rapidRepeatGuardSeconds {
            return NotificationDecision(
                isAllowed: false,
                reason: .rapidRepeat,
                secondsSinceLastGlobalFire: secondsSinceLastGlobalFire,
                secondsSinceLastMerchantFire: secondsSinceLastMerchantFire,
                distanceFromLastDeliveredLocation: distanceFromLastDeliveredLocation,
                distanceFromLastStopLocation: distanceFromLastStopLocation,
                isSameStopCluster: isSameStopCluster
            )
        }

        if let secondsSinceLastGlobalFire,
           secondsSinceLastGlobalFire < globalNotificationCooldownSeconds {
            return NotificationDecision(
                isAllowed: false,
                reason: .globalCooldown,
                secondsSinceLastGlobalFire: secondsSinceLastGlobalFire,
                secondsSinceLastMerchantFire: secondsSinceLastMerchantFire,
                distanceFromLastDeliveredLocation: distanceFromLastDeliveredLocation,
                distanceFromLastStopLocation: distanceFromLastStopLocation,
                isSameStopCluster: isSameStopCluster
            )
        }

        if isSameStopCluster,
           let secondsSinceLastGlobalFire,
           secondsSinceLastGlobalFire < perMerchantNotificationCooldownSeconds {
            return NotificationDecision(
                isAllowed: false,
                reason: .sameStopCooldown,
                secondsSinceLastGlobalFire: secondsSinceLastGlobalFire,
                secondsSinceLastMerchantFire: secondsSinceLastMerchantFire,
                distanceFromLastDeliveredLocation: distanceFromLastDeliveredLocation,
                distanceFromLastStopLocation: distanceFromLastStopLocation,
                isSameStopCluster: isSameStopCluster
            )
        }

        if let lastDeliveredMerchantID,
           lastDeliveredMerchantID == merchantID {
            guard let currentLocation else {
                return NotificationDecision(
                    isAllowed: false,
                    reason: .missingLocation,
                    secondsSinceLastGlobalFire: secondsSinceLastGlobalFire,
                    secondsSinceLastMerchantFire: secondsSinceLastMerchantFire,
                    distanceFromLastDeliveredLocation: distanceFromLastDeliveredLocation,
                    distanceFromLastStopLocation: distanceFromLastStopLocation,
                    isSameStopCluster: isSameStopCluster
                )
            }

            if let secondsSinceLastMerchantFire,
               secondsSinceLastMerchantFire < perMerchantNotificationCooldownSeconds {
                return NotificationDecision(
                    isAllowed: false,
                    reason: .merchantCooldown,
                    secondsSinceLastGlobalFire: secondsSinceLastGlobalFire,
                    secondsSinceLastMerchantFire: secondsSinceLastMerchantFire,
                    distanceFromLastDeliveredLocation: distanceFromLastDeliveredLocation,
                    distanceFromLastStopLocation: distanceFromLastStopLocation,
                    isSameStopCluster: isSameStopCluster
                )
            }

            if let lastDeliveredLocation,
               currentLocation.distance(from: lastDeliveredLocation) < minimumMovementBetweenNotificationsMeters {
                return NotificationDecision(
                    isAllowed: false,
                    reason: .insufficientMovement,
                    secondsSinceLastGlobalFire: secondsSinceLastGlobalFire,
                    secondsSinceLastMerchantFire: secondsSinceLastMerchantFire,
                    distanceFromLastDeliveredLocation: distanceFromLastDeliveredLocation,
                    distanceFromLastStopLocation: distanceFromLastStopLocation,
                    isSameStopCluster: isSameStopCluster
                )
            }
        }

        return NotificationDecision(
            isAllowed: true,
            reason: nil,
            secondsSinceLastGlobalFire: secondsSinceLastGlobalFire,
            secondsSinceLastMerchantFire: secondsSinceLastMerchantFire,
            distanceFromLastDeliveredLocation: distanceFromLastDeliveredLocation,
            distanceFromLastStopLocation: distanceFromLastStopLocation,
            isSameStopCluster: isSameStopCluster
        )
    }

    private func distance(from currentLocation: CLLocation?, to priorLocation: CLLocation?) -> CLLocationDistance? {
        guard let currentLocation, let priorLocation else { return nil }
        return currentLocation.distance(from: priorLocation)
    }
}
