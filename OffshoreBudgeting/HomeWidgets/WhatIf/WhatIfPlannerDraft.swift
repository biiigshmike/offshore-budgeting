import Foundation

struct WhatIfPlannerDraft: Equatable {
    var categoryScenarioSpendByID: [UUID: Double]
    var plannedIncomeOverride: Double?
    var actualIncomeOverride: Double?
    var sourcePrompt: String?
    var summary: String?
}
