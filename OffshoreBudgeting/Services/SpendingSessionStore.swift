import Foundation

// MARK: - SpendingSessionStore

enum SpendingSessionStore {
    private enum Key {
        static let expiresAt = "spendingSession_expiresAt"
    }

    static func activate(hours: Int, now: Date = .now) {
        let clampedHours = min(max(1, hours), 12)
        let expiresAt = now.addingTimeInterval(TimeInterval(clampedHours * 3600))
        UserDefaults.standard.set(expiresAt.timeIntervalSince1970, forKey: Key.expiresAt)
    }

    static func end() {
        UserDefaults.standard.removeObject(forKey: Key.expiresAt)
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
}
