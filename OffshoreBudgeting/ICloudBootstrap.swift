import Foundation

enum ICloudBootstrap {
    static let maxWaitSeconds: TimeInterval = 8

    static func isBootstrapping(useICloud: Bool, startedAt: Double, now: Date = .now) -> Bool {
        guard useICloud, startedAt > 0 else { return false }
        return (now.timeIntervalSince1970 - startedAt) < maxWaitSeconds
    }
}

