import AppIntents
import Foundation

// MARK: - SpendingSessionDuration

enum SpendingSessionDuration: Int, AppEnum {
    case oneHour = 1
    case twoHours = 2
    case fourHours = 4

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Excursion Mode Duration"

    static var caseDisplayRepresentations: [SpendingSessionDuration: DisplayRepresentation] = [
        .oneHour: "1 hour",
        .twoHours: "2 hours",
        .fourHours: "4 hours"
    ]

    var hours: Int { rawValue }
}

// MARK: - EnableSpendingSessionIntent

struct EnableSpendingSessionIntent: AppIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Start Excursion Mode"
    static var description = IntentDescription("Start a focused excursion mode session for a fixed time.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Duration")
    var duration: SpendingSessionDuration

    init() {
        self.duration = .twoHours
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let expirationDate = await MainActor.run { () -> Date in
            ShoppingModeManager.shared.start(hours: duration.hours)
            return ShoppingModeManager.shared.status.expiresAt ?? Date.now
        }

        let timeText = expirationDate.formatted(date: .omitted, time: .shortened)
        return .result(dialog: IntentDialog(stringLiteral: "Excursion mode is active until \(timeText)."))
    }
}
