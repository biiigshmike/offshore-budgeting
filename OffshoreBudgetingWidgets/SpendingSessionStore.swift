import Foundation

// MARK: - SpendingSessionStore

enum SpendingSessionStore {
    private static let appGroupID = "group.com.mb.offshore-budgeting"

    private enum Key {
        static let expiresAt = "spendingSession_expiresAt"
        static let startedAt = "spendingSession_startedAt"
        static let sessionID = "spendingSession_sessionID"
    }

    private static var sharedDefaults: UserDefaults {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            return .standard
        }
        migrateLegacyValuesIfNeeded(to: defaults)
        return defaults
    }

    static func end() {
        let defaults = sharedDefaults
        defaults.removeObject(forKey: Key.expiresAt)
        defaults.removeObject(forKey: Key.startedAt)
        defaults.removeObject(forKey: Key.sessionID)
    }

    @discardableResult
    static func extend(minutes: Int, now: Date = .now) -> Date? {
        guard let currentExpiry = expirationDate(now: now) else { return nil }
        let clampedMinutes = min(max(1, minutes), 240)
        let newExpiry = currentExpiry.addingTimeInterval(TimeInterval(clampedMinutes * 60))
        sharedDefaults.set(newExpiry.timeIntervalSince1970, forKey: Key.expiresAt)
        return newExpiry
    }

    static func sessionID(now: Date = .now) -> String? {
        guard expirationDate(now: now) != nil else { return nil }
        return sharedDefaults.string(forKey: Key.sessionID)
    }

    private static func expirationDate(now: Date = .now) -> Date? {
        let defaults = sharedDefaults
        let raw = defaults.double(forKey: Key.expiresAt)
        guard raw > 0 else { return nil }

        let date = Date(timeIntervalSince1970: raw)
        guard date > now else {
            end()
            return nil
        }

        return date
    }

    private static func migrateLegacyValuesIfNeeded(to defaults: UserDefaults) {
        guard defaults.object(forKey: Key.expiresAt) == nil else { return }

        let legacyDefaults = UserDefaults.standard
        guard legacyDefaults.object(forKey: Key.expiresAt) != nil else { return }

        defaults.set(legacyDefaults.double(forKey: Key.expiresAt), forKey: Key.expiresAt)
        defaults.set(legacyDefaults.double(forKey: Key.startedAt), forKey: Key.startedAt)
        defaults.set(legacyDefaults.string(forKey: Key.sessionID), forKey: Key.sessionID)
    }
}
