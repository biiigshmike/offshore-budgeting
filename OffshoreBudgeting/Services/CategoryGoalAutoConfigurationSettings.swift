import Foundation

/// Workspace defaults for suggestions; saved budget goals remain independent.
struct CategoryGoalAutoConfigurationSettings: Codable, Equatable {
    var suggestMaximums: Bool = true
    var historyCount: Int = 3
    var cushionPercent: Double = 0

    var normalized: Self {
        let finiteCushion = cushionPercent.isFinite ? cushionPercent : 0
        return Self(
            suggestMaximums: suggestMaximums,
            historyCount: min(12, max(1, historyCount)),
            cushionPercent: (min(100, max(0, finiteCushion)) / 5).rounded() * 5
        )
    }
}

extension Workspace {
    var categoryGoalAutoConfiguration: CategoryGoalAutoConfigurationSettings {
        get {
            CategoryGoalAutoConfigurationSettings(
                suggestMaximums: categoryGoalSuggestMaximums,
                historyCount: categoryGoalHistoryCount,
                cushionPercent: categoryGoalCushionPercent
            ).normalized
        }
        set {
            let settings = newValue.normalized
            categoryGoalSuggestMaximums = settings.suggestMaximums
            categoryGoalHistoryCount = settings.historyCount
            categoryGoalCushionPercent = settings.cushionPercent
        }
    }
}
