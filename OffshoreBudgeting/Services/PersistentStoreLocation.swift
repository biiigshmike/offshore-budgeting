import Foundation

/// Keep development databases (and their CloudKit metadata) away from installed releases.
/// Never migrate the legacy files: TestFlight and App Store builds still own those paths.
enum PersistentStoreLocation {
    static var isDevelopmentBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    static func directory(
        in applicationSupport: URL,
        isDevelopment: Bool = isDevelopmentBuild
    ) -> URL {
        isDevelopment
            ? applicationSupport.appendingPathComponent("Development", isDirectory: true)
            : applicationSupport
    }
}
