import Foundation
@testable import Offshore

/// Shared conversational contracts. Each scenario starts a new chat; only its turns share context.
/// Deterministic bridges and native evaluations assert the same intent without matching prose verbatim.
enum MarinaCapabilityScenarios {
    struct Turn: Sendable {
        var id: String
        var prompt: String
        var tool: MarinaDataRequest.Tool? = nil
        var purpose: MarinaDataRequest.Purpose? = nil
        var operation: MarinaDataRequest.Operation? = nil
        var grouping: MarinaDataRequest.Grouping? = nil
        var metric: MarinaDataRequest.MetricFocus? = nil
        var sort: MarinaDataRequest.Sort? = nil
        var availabilityFilter: MarinaDataRequest.AvailabilityFilter? = nil
        var compareLeaders: Bool? = nil
        var positiveOnly: Bool? = nil
        var limit: Int? = nil
        var requiresFinancialRead = true
        var requiresClarification = false

        func matches(_ request: MarinaDataRequest) -> Bool {
            (tool == nil || request.tool == tool)
                && (purpose == nil || request.purpose == purpose)
                && (operation == nil || request.operation == operation)
                && (grouping == nil || request.grouping == grouping)
                && (metric == nil || request.metric == metric)
                && (sort == nil || request.sort == sort)
                && (availabilityFilter == nil || request.availabilityFilter == availabilityFilter)
                && (compareLeaders == nil || request.compareLeaders == compareLeaders)
                && (positiveOnly == nil || request.positiveOnly == positiveOnly)
                && (limit == nil || request.limit == limit)
        }
    }

    struct Scenario: Sendable {
        var id: String
        var label: String
        var turns: [Turn]
    }

    static let categoryComparison = Scenario(id: "category-comparison", label: "Top category and June follow-up", turns: [
        Turn(id: "top-category", prompt: "What is my top category this period?", tool: .expenses,
             operation: .ranking, grouping: .category),
        Turn(id: "compare-june", prompt: "What about in June? Can you compare?", tool: .expenses,
             operation: .comparison, grouping: .category, compareLeaders: true)
    ])

    static let cardFollowUps = Scenario(id: "card-follow-ups", label: "Card summary, extrema, and merchant", turns: [
        Turn(id: "card-summary", prompt: "Summarize my Apple Card for this month.", tool: .expenses,
             purpose: .cardSummary, operation: .summary),
        Turn(id: "highest-expense", prompt: "What was the highest expense on the card this month?", tool: .expenses,
             operation: .transactions, sort: .largest, positiveOnly: true, limit: 1),
        Turn(id: "lowest-expense", prompt: "And the lowest?", tool: .expenses,
             operation: .transactions, sort: .smallest, positiveOnly: true, limit: 1),
        Turn(id: "top-merchant", prompt: "Where do I spend the most money on my Apple Card?", tool: .expenses,
             operation: .ranking, grouping: .merchant)
    ])

    static let spendingPatterns = Scenario(id: "spending-patterns", label: "Spending patterns", turns: [
        Turn(id: "patterns", prompt: "What are my spend trends?", tool: .expenses, purpose: .spendingPatterns)
    ])

    static let categoryWarnings = Scenario(id: "category-warnings", label: "Categories over or near limits", turns: [
        Turn(id: "category-warnings", prompt: "What categories are over their limit or nearing their limit for this month?",
             tool: .budgetSummary, purpose: .categoryAvailability, operation: .summary, availabilityFilter: .overOrNear)
    ])

    static let categoryAvailability = Scenario(id: "category-availability", label: "Direct category availability", turns: [
        Turn(id: "category-availability", prompt: "Show category availability", tool: .budgetSummary,
             purpose: .categoryAvailability, operation: .summary)
    ])

    static let broadAssessment = Scenario(id: "broad-assessment", label: "Broad assessment and clarified focus", turns: [
        Turn(id: "overall-clarifier", prompt: "How am I doing this month overall?",
             requiresFinancialRead: false, requiresClarification: true),
        Turn(id: "chosen-patterns", prompt: "Spending patterns, please.", tool: .expenses, purpose: .spendingPatterns)
    ])

    static let greetingAndWorkspace = Scenario(id: "greeting-workspace", label: "Greeting and workspace summary", turns: [
        Turn(id: "greeting", prompt: "Hey, Marina!", requiresFinancialRead: false),
        Turn(id: "workspace-summary", prompt: "Summarize my Personal workspace.", tool: .budgetSummary, operation: .summary)
    ])

    static let merchantClarification = Scenario(id: "merchant-clarification", label: "Select an offered punctuated merchant", turns: [
        Turn(id: "merchant-discovery", prompt: "Show DoorDash expenses on Apple Card for October 2026.",
             requiresFinancialRead: false, requiresClarification: true),
        Turn(id: "merchant-kind", prompt: "The merchant, please.",
             requiresFinancialRead: false, requiresClarification: true),
        Turn(id: "merchant-choice", prompt: "DoorDash - BevMo!", tool: .expenses, operation: .transactions)
    ])

    static let cardGrouping = Scenario(id: "card-grouping", label: "Expense totals grouped by card", turns: [
        Turn(id: "card-totals", prompt: "Break down my October 2026 spending by card.", tool: .expenses,
             grouping: .card)
    ])

    static let movementOverTime = Scenario(id: "movement-over-time", label: "Spending movement over time", turns: [
        Turn(id: "spending-movement", prompt: "Plot how my Apple Card spending changed week by week in October 2026.",
             tool: .expenses)
    ])

    static let all = [categoryComparison, spendingPatterns, cardFollowUps, categoryWarnings,
                      categoryAvailability, broadAssessment, greetingAndWorkspace,
                      merchantClarification, cardGrouping, movementOverTime]
}
