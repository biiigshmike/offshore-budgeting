import Foundation

/// App and extension identity must agree without relying on launch arguments.
nonisolated enum OffshoreAppIdentity {
    #if OFFSHORE_SCREENSHOTS
    static let appGroupIdentifier = "group.com.mb.offshore-budgeting.screenshots"
    static let urlScheme = "offshore-screenshots"
    #else
    static let appGroupIdentifier = "group.com.mb.offshore-budgeting"
    static let urlScheme = "offshore"
    #endif
}
