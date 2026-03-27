import Foundation

// MARK: - WidgetActionRequestStore

enum WidgetActionRequestStore {
    static let appGroupID = "group.com.mb.offshore-budgeting"

    private enum Key {
        static let pendingURLString = "widget_pendingURLString"
    }

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func consumePendingURL() -> URL? {
        guard let defaults = sharedDefaults else { return nil }
        let value = defaults.string(forKey: Key.pendingURLString)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard value.isEmpty == false, let url = URL(string: value) else {
            defaults.removeObject(forKey: Key.pendingURLString)
            return nil
        }

        defaults.removeObject(forKey: Key.pendingURLString)
        return url
    }
}
