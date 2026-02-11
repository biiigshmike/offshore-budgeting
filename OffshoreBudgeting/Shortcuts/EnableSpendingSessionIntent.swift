import AppIntents
import Foundation

// MARK: - SpendingSessionDuration

enum SpendingSessionDuration: Int, AppEnum {
    case oneHour = 1
    case twoHours = 2
    case fourHours = 4

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Spending Session Duration"

    static var caseDisplayRepresentations: [SpendingSessionDuration: DisplayRepresentation] = [
        .oneHour: "1 hour",
        .twoHours: "2 hours",
        .fourHours: "4 hours"
    ]

    var hours: Int { rawValue }
}

// MARK: - EnableSpendingSessionIntent

struct EnableSpendingSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Enable Spending Session"
    static var description = IntentDescription("Start a focused spending session for a fixed time.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Duration")
    var duration: SpendingSessionDuration

    init() {
        self.duration = .twoHours
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let expirationDate = await MainActor.run { () -> Date in
            SpendingSessionStore.activate(hours: duration.hours)
            return SpendingSessionStore.expirationDate() ?? Date.now
        }

        let timeText = expirationDate.formatted(date: .omitted, time: .shortened)
        return .result(dialog: IntentDialog(stringLiteral: "Spending session enabled until \(timeText)."))
    }
}
