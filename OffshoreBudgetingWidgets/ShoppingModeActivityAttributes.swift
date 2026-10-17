import Foundation

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit

// MARK: - ShoppingModeActivityAttributes

struct ShoppingModeActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let endDate: Date
        let statusText: String
    }

    let sessionID: String
    let startDate: Date
    let endDate: Date
}
#endif
