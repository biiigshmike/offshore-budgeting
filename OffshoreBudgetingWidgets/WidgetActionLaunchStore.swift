import Foundation

// MARK: - WidgetActionLaunchStore

enum WidgetActionLaunchStore {
    private static let appGroupID = "group.com.mb.offshore-budgeting"

    private enum Key {
        static let pendingURLString = "widget_pendingURLString"
    }

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func queue(_ url: URL) {
        sharedDefaults.set(url.absoluteString, forKey: Key.pendingURLString)
    }
}
