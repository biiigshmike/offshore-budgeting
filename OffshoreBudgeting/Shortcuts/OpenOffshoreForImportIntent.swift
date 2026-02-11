import AppIntents
import Foundation

// MARK: - OpenOffshoreForImportIntent

struct OpenOffshoreForImportIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Offshore"
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}
