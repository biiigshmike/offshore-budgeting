import Foundation

// MARK: - SpendingSessionStore

enum SpendingSessionStore {
    private enum Key {
        static let expiresAt = "spendingSession_expiresAt"
        static let startedAt = "spendingSession_startedAt"
        static let sessionID = "spendingSession_sessionID"
    }

    static func activate(hours: Int, now: Date = .now) {
        let clampedHours = min(max(1, hours), 12)
        let expiresAt = now.addingTimeInterval(TimeInterval(clampedHours * 3600))
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Key.startedAt)
        UserDefaults.standard.set(expiresAt.timeIntervalSince1970, forKey: Key.expiresAt)
        UserDefaults.standard.set(UUID().uuidString, forKey: Key.sessionID)
    }

    @discardableResult
    static func extend(minutes: Int, now: Date = .now) -> Date? {
        guard let currentExpiry = expirationDate(now: now) else { return nil }
        let clampedMinutes = min(max(1, minutes), 240)
        let newExpiry = currentExpiry.addingTimeInterval(TimeInterval(clampedMinutes * 60))
        UserDefaults.standard.set(newExpiry.timeIntervalSince1970, forKey: Key.expiresAt)
        return newExpiry
    }

    static func end() {
        UserDefaults.standard.removeObject(forKey: Key.expiresAt)
        UserDefaults.standard.removeObject(forKey: Key.startedAt)
        UserDefaults.standard.removeObject(forKey: Key.sessionID)
    }

    static func expirationDate(now: Date = .now) -> Date? {
        let raw = UserDefaults.standard.double(forKey: Key.expiresAt)
        guard raw > 0 else { return nil }

        let date = Date(timeIntervalSince1970: raw)
        guard date > now else {
            end()
            return nil
        }

        return date
    }

    static func isActive(now: Date = .now) -> Bool {
        expirationDate(now: now) != nil
    }

    static func startDate(now: Date = .now) -> Date? {
        guard expirationDate(now: now) != nil else { return nil }

        let raw = UserDefaults.standard.double(forKey: Key.startedAt)
        guard raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw)
    }

    static func sessionID(now: Date = .now) -> String? {
        guard expirationDate(now: now) != nil else { return nil }
        return UserDefaults.standard.string(forKey: Key.sessionID)
    }
}
