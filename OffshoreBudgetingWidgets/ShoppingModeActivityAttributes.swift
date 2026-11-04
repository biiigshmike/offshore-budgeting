import Foundation

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit

// MARK: - ShoppingModeActivityAttributes

nonisolated struct ShoppingModeActivityAttributes: ActivityAttributes, Sendable {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        let endDate: Date
        let statusText: String?
    }

    let sessionID: String
    let startDate: Date
    let endDate: Date
}
#endif
