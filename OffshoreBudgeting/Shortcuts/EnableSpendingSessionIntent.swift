import AppIntents
import Foundation

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif

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

struct EnableSpendingSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Excursion Mode"
    static var description = IntentDescription("Start a focused excursion mode session for a fixed time.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Duration")
    var duration: SpendingSessionDuration

    init() {
        self.duration = .twoHours
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await ShoppingModeManager.shared.start(hours: duration.hours)
        switch result {
        case .started(let expiresAt):
            let timeText = expiresAt.formatted(date: .omitted, time: .shortened)
            return .result(dialog: IntentDialog(stringLiteral: "Excursion mode is active until \(timeText)."))
        case .blocked(let blockers):
            let details = blockers.map(\.message).joined(separator: " ")
            return .result(dialog: IntentDialog(stringLiteral: "Excursion mode could not start. \(details)"))
        }
    }
}

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
extension EnableSpendingSessionIntent: LiveActivityIntent { }
#endif
