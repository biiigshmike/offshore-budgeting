import Foundation
import Darwin

enum AppRestartService {
    static var canCloseAppProgrammatically: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static var closeAppButtonTitle: String {
        canCloseAppProgrammatically ? "Close App" : "Got It"
    }

    static func restartRequiredMessage(
        debugMessage: String,
        appName: String = "Offshore",
        releaseExtraMessage: String? = nil
    ) -> String {
        #if DEBUG
        return debugMessage
        #else
        if let releaseExtraMessage {
            return "Please close \(appName) from the app switcher, then reopen to apply this change.\n\n\(releaseExtraMessage)"
        } else {
            return "Please close \(appName) from the app switcher, then reopen to apply this change."
        }
        #endif
    }

    static func closeAppOrDismiss(_ dismiss: () -> Void) {
        #if DEBUG
        UserDefaults.standard.synchronize()
        exit(0)
        #else
        dismiss()
        #endif
    }

    static func closeApp() {
        #if DEBUG
        UserDefaults.standard.synchronize()
        exit(0)
        #else
        // Intentionally no-op in release builds. iOS apps should not quit programmatically.
        #endif
    }
}
