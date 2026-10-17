import AppIntents
import Foundation

// MARK: - DisableShoppingModeIntent

struct DisableShoppingModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Excursion Mode"
    static var description = IntentDescription("Stop the active excursion mode session.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run {
            ShoppingModeManager.shared.end()
        }

        return .result(dialog: IntentDialog(stringLiteral: "Excursion mode stopped."))
    }
}
