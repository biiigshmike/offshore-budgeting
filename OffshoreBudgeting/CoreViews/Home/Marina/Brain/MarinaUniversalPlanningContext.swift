import Foundation

struct MarinaUniversalPlanningContext: Equatable, Sendable {
    let ambientDateRange: HomeQueryDateRange?
    let defaultBudgetingPeriod: BudgetingPeriod
    let now: Date
    let calendar: Calendar

    init(
        ambientDateRange: HomeQueryDateRange? = nil,
        defaultBudgetingPeriod: BudgetingPeriod = .monthly,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.ambientDateRange = ambientDateRange
        self.defaultBudgetingPeriod = defaultBudgetingPeriod
        self.now = now
        self.calendar = calendar
    }
}
