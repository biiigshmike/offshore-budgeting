import AppIntents
import Foundation

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit

@MainActor
private enum ExcursionStopIntentExecutor {
    static func execute() async {
        #if DEBUG
        print("[StopExcursionIntent] perform() invoked")
        #endif
        SpendingSessionStore.end()

        for activity in Activity<ShoppingModeActivityAttributes>.activities {
            #if DEBUG
            print("[StopExcursionIntent] ending activity id=\(activity.id)")
            #endif
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}

struct StopExcursionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Excursion Mode"
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        await ExcursionStopIntentExecutor.execute()
        return .result()
    }
}
#endif
