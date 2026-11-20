import Foundation
import SwiftData

#if DEBUG
enum DebugScreenshotMode {
    static let storeName = "Screenshots"

    static var isCompiledBuild: Bool {
        #if OFFSHORE_SCREENSHOTS
        true
        #else
        false
        #endif
    }

    // A launch argument or persisted preference cannot turn a normal build into
    // the screenshot app. Its bundle, app group, and URL scheme must be isolated too.
    static var isEnabled: Bool { isCompiledBuild }

    static var storeURL: URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return PersistentStoreLocation.directory(in: applicationSupport)
            .appendingPathComponent("\(storeName).store")
    }

    static func owns(_ configuration: ModelConfiguration) -> Bool {
        !configuration.isStoredInMemoryOnly
            && configuration.cloudKitContainerIdentifier == nil
            && configuration.name == storeName
            && configuration.url.standardizedFileURL == storeURL.standardizedFileURL
    }
}
#endif
