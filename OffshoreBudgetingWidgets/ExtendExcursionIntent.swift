import AppIntents
import Foundation

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit

@MainActor
private enum ExtendExcursionIntentExecutor {
    static let addedMinutes: Int = 30
    static let relevanceScore: Double = 80

    static func execute() async {
        let sessionID = SpendingSessionStore.sessionID()
        let newExpiry = SpendingSessionStore.extend(minutes: addedMinutes)

        guard let sessionID, let newExpiry else {
            #if DEBUG
            print("[ExtendExcursionIntent] no active session to extend")
            #endif
            return
        }

        let state = ShoppingModeActivityAttributes.ContentState(
            endDate: newExpiry,
            statusText: "Excursion mode active"
        )

        #if DEBUG
        print("[ExtendExcursionIntent] perform() invoked sessionID=\(sessionID) newExpiry=\(newExpiry)")
        #endif

        for activity in Activity<ShoppingModeActivityAttributes>.activities where activity.attributes.sessionID == sessionID {
            #if DEBUG
            print("[ExtendExcursionIntent] updating activity id=\(activity.id)")
            #endif
            await activity.update(
                ActivityContent(
                    state: state,
                    staleDate: newExpiry,
                    relevanceScore: relevanceScore
                )
            )
        }
    }
}

struct ExtendExcursionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Extend Excursion Mode"
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        await ExtendExcursionIntentExecutor.execute()
        return .result()
    }
}
#endif
