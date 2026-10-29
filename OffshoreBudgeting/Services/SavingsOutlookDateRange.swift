import Foundation

nonisolated struct SavingsOutlookDateRange: Codable, Equatable, Sendable {
    let startDate: Date
    let endDate: Date

    init(startDate: Date, endDate: Date) {
        if startDate <= endDate {
            self.startDate = startDate
            self.endDate = endDate
        } else {
            self.startDate = endDate
            self.endDate = startDate
        }
    }
}

