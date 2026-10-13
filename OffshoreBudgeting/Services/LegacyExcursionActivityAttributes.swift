import Foundation

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit

// Retained only to end Live Activities created by older app versions.
// Preserve the original type name and Codable fields for ActivityKit compatibility.

nonisolated struct ShoppingModeActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        let endDate: Date
        let statusText: String
    }

    let sessionID: String
    let startDate: Date
    let endDate: Date
}
#endif
