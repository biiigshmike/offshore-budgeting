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
        canCloseAppProgrammatically ? String(localized: "Close App") : String(localized: "Got It")
    }

    static var nextButtonTitle: String {
        canCloseAppProgrammatically ? String(localized: "Close App") : String(localized: "Next")
    }

    static func restartRequiredMessage(
        debugMessage: LocalizedStringResource,
        appName: String = "Offshore",
        releaseExtraMessage: LocalizedStringResource? = nil
    ) -> String {
        #if DEBUG
        return String(localized: debugMessage)
        #else
        let message = String(localized: "This will take effect the next time you quit and relaunch \(appName).")
        guard let releaseExtraMessage else { return message }
        return message + "\n\n" + String(localized: releaseExtraMessage)
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
