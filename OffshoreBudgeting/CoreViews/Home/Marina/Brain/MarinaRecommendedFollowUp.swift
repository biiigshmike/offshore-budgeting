import Foundation

enum MarinaRecommendedFollowUp {
    static func suggestion(from followUps: [MarinaFollowUpSuggestion]) -> MarinaFollowUpSuggestion? {
        suggestion(in: followUps, mode: .executable)
            ?? suggestion(in: followUps, mode: .clarificationRequired)
    }

    static func suggestion(
        from followUps: [MarinaFollowUpSuggestion],
        memory: MarinaFollowUpMemory
    ) -> MarinaFollowUpSuggestion? {
        suggestion(in: followUps, mode: .executable, memory: memory)
            ?? suggestion(in: followUps, mode: .clarificationRequired, memory: memory)
    }

    static func filteredFollowUps(
        from followUps: [MarinaFollowUpSuggestion],
        memory: MarinaFollowUpMemory
    ) -> [MarinaFollowUpSuggestion] {
        guard let selected = suggestion(from: followUps, memory: memory) else {
            return []
        }

        let selectedRank = reasonRank(selected.reason)
        return followUps.filter { followUp in
            guard memory.shouldSuppress(followUp) == false else { return false }
            guard followUp.id != selected.id else { return true }
            guard followUp.executionMode == selected.executionMode else {
                return selected.executionMode == .executable
            }
            return reasonRank(followUp.reason) >= selectedRank
        }
    }

    static func confirmationQuestion(for followUp: MarinaFollowUpSuggestion) -> String {
        guard followUp.executionMode == .executable else {
            return MarinaL10n.string("marina.followUp.confirmation.clarification", defaultValue: "Want to narrow that down?", comment: "Confirmation question for a clarification-required Marina follow-up.")
        }

        switch followUp.reason {
        case .comparePreviousPeriod:
            return comparisonQuestion(for: followUp)
        case .whatIf:
            return whatIfQuestion(for: followUp)
        case .safeDailySpend:
            return MarinaL10n.string("marina.followUp.confirmation.safeDailySpend", defaultValue: "Want to check what you can spend per day?", comment: "Confirmation question for safe daily spend follow-up.")
        case .breakdown:
            return breakdownQuestion(for: followUp)
        case .inspectRows:
            return MarinaL10n.string("marina.followUp.confirmation.inspectRows", defaultValue: "Want to see the biggest expenses behind this?", comment: "Confirmation question for expense row follow-up.")
        case .showMore:
            if let remaining = followUp.remainingResultCount, remaining > 0 {
                return MarinaL10n.format("marina.followUp.confirmation.showRemainingFormat", defaultValue: "Want to see the remaining %d?", comment: "Confirmation question for showing remaining rows.", remaining)
            }
            return MarinaL10n.string("marina.followUp.confirmation.showMore", defaultValue: "Want to see more rows?", comment: "Confirmation question for showing more rows.")
        case .searchAllTime:
            let target = targetName(in: followUp) ?? MarinaL10n.string("marina.followUp.confirmation.allExpensesFallback", defaultValue: "these", comment: "Fallback target for all-time expense search follow-up.")
            return MarinaL10n.format("marina.followUp.confirmation.searchAllTimeFormat", defaultValue: "Want me to search all %@ expenses instead?", comment: "Confirmation question for all-time expense search follow-up.", target)
        case .forecast:
            return forecastQuestion(for: followUp)
        case .nextDue:
            return MarinaL10n.string("marina.followUp.confirmation.nextDue", defaultValue: "Want to see what is due next?", comment: "Confirmation question for next due follow-up.")
        }
    }

    static func isAffirmative(_ prompt: String) -> Bool {
        affirmativeReplies.contains(normalized(prompt))
    }

    static func isNegative(_ prompt: String) -> Bool {
        negativeReplies.contains(normalized(prompt))
    }

    private static let affirmativeReplies: Set<String> = [
        "absolutely",
        "affirmative",
        "all right",
        "alright",
        "do it",
        "do that",
        "fine",
        "go ahead",
        "go for it",
        "i am in",
        "im in",
        "lets",
        "lets do it",
        "lets go",
        "of course",
        "ok",
        "okay",
        "please",
        "please do",
        "run it",
        "show me",
        "show me that",
        "sounds great",
        "sounds good",
        "sounds good to me",
        "sure",
        "sure thing",
        "that works",
        "totally",
        "works for me",
        "y",
        "yes",
        "yeah",
        "yep",
        "yes please",
        "yup"
    ]

    private static let negativeReplies: Set<String> = [
        "all set",
        "cancel",
        "cancel that",
        "do not",
        "do not do it",
        "dont",
        "dont do it",
        "i am good",
        "im good",
        "leave it",
        "maybe later",
        "n",
        "nah",
        "nah thanks",
        "never mind",
        "nevermind",
        "no",
        "no need",
        "no thank you",
        "no thanks",
        "no thats okay",
        "nope",
        "nope thanks",
        "not interested",
        "not necessary",
        "not needed",
        "not now",
        "not right now",
        "not this time",
        "not today",
        "pass",
        "skip",
        "skip it",
        "stop",
        "thanks but no"
    ]

    private static func suggestion(
        in followUps: [MarinaFollowUpSuggestion],
        mode: MarinaFollowUpExecutionMode
    ) -> MarinaFollowUpSuggestion? {
        followUps
            .enumerated()
            .filter { $0.element.executionMode == mode }
            .min { left, right in
                let leftRank = reasonRank(left.element.reason)
                let rightRank = reasonRank(right.element.reason)
                if leftRank != rightRank {
                    return leftRank < rightRank
                }
                return left.offset < right.offset
            }?
            .element
    }

    private static func suggestion(
        in followUps: [MarinaFollowUpSuggestion],
        mode: MarinaFollowUpExecutionMode,
        memory: MarinaFollowUpMemory
    ) -> MarinaFollowUpSuggestion? {
        followUps
            .enumerated()
            .filter { $0.element.executionMode == mode }
            .filter { memory.shouldSuppress($0.element) == false }
            .min { left, right in
                let leftScore = reasonRank(left.element.reason) + memory.scorePenalty(for: left.element)
                let rightScore = reasonRank(right.element.reason) + memory.scorePenalty(for: right.element)
                if leftScore != rightScore {
                    return leftScore < rightScore
                }
                return left.offset < right.offset
            }?
            .element
    }

    private static func reasonRank(_ reason: MarinaFollowUpSuggestion.Reason) -> Int {
        switch reason {
        case .whatIf:
            return 0
        case .safeDailySpend:
            return 1
        case .breakdown:
            return 2
        case .comparePreviousPeriod:
            return 3
        case .inspectRows:
            return 4
        case .showMore:
            return 5
        case .forecast:
            return 6
        case .nextDue:
            return 7
        case .searchAllTime:
            return 8
        }
    }

    private static func comparisonQuestion(for followUp: MarinaFollowUpSuggestion) -> String {
        let target = targetName(in: followUp)
        switch followUp.semanticRequest?.entity {
        case .some(.income):
            if let target {
                return MarinaL10n.format("marina.followUp.confirmation.compareIncomeTargetFormat", defaultValue: "Want to compare %@ income to last period?", comment: "Confirmation question for comparing a named income source to the last period.", target)
            }
            return MarinaL10n.string("marina.followUp.confirmation.compareIncome", defaultValue: "Want to compare your income to last period?", comment: "Confirmation question for comparing income to the last period.")
        case .some(.category):
            if let target {
                return MarinaL10n.format("marina.followUp.confirmation.compareTargetFormat", defaultValue: "Want to compare %@ to last period?", comment: "Confirmation question for comparing a named target to the last period.", target)
            }
            return MarinaL10n.string("marina.followUp.confirmation.compareCategory", defaultValue: "Want to compare this category to last period?", comment: "Confirmation question for comparing a category to the last period.")
        case .some(.card):
            if let target {
                return MarinaL10n.format("marina.followUp.confirmation.compareTargetFormat", defaultValue: "Want to compare %@ to last period?", comment: "Confirmation question for comparing a named target to the last period.", target)
            }
            return MarinaL10n.string("marina.followUp.confirmation.compareCard", defaultValue: "Want to compare this card to last period?", comment: "Confirmation question for comparing a card to the last period.")
        case .some(.budget):
            return MarinaL10n.string("marina.followUp.confirmation.compareBudget", defaultValue: "Want to compare this budget to last period?", comment: "Confirmation question for comparing a budget to the last period.")
        case .some(.workspace), .some(.plannedExpense), .some(.variableExpense), .some(.reconciliationAccount), .some(.savingsAccount), .some(.preset), .none:
            return MarinaL10n.string("marina.followUp.confirmation.compareGeneric", defaultValue: "Want to compare this to last period?", comment: "Generic confirmation question for a previous-period follow-up.")
        }
    }

    private static func whatIfQuestion(for followUp: MarinaFollowUpSuggestion) -> String {
        let amount = followUp.semanticRequest?.whatIfAmount ?? amountInPrompt(followUp.prompt)
        let amountPhrase = amount.map { shortCurrency($0) } ?? MarinaL10n.string("marina.followUp.confirmation.whatIfAmountFallback", defaultValue: "that amount", comment: "Fallback amount phrase for a what-if follow-up.")
        return MarinaL10n.format("marina.followUp.confirmation.whatIfFormat", defaultValue: "Want to see what happens if you spend %@?", comment: "Confirmation question for a what-if follow-up.", amountPhrase)
    }

    private static func breakdownQuestion(for followUp: MarinaFollowUpSuggestion) -> String {
        if followUp.semanticRequest?.measure == .categoryAvailability {
            return MarinaL10n.string("marina.followUp.confirmation.categoryRoom", defaultValue: "Want to see which categories still have room?", comment: "Confirmation question for category room follow-up.")
        }
        return MarinaL10n.string("marina.followUp.confirmation.categoryBreakdown", defaultValue: "Want to see the category breakdown?", comment: "Confirmation question for category breakdown follow-up.")
    }

    private static func forecastQuestion(for followUp: MarinaFollowUpSuggestion) -> String {
        if followUp.semanticRequest?.measure == .coverageRatio {
            return MarinaL10n.string("marina.followUp.confirmation.incomeCoverage", defaultValue: "Want to see whether your income covers planned expenses?", comment: "Confirmation question for income coverage follow-up.")
        }
        if followUp.semanticRequest?.entity == .income {
            return MarinaL10n.string("marina.followUp.confirmation.expectedIncome", defaultValue: "Want to see what income is still expected?", comment: "Confirmation question for expected income follow-up.")
        }
        return MarinaL10n.string("marina.followUp.confirmation.forecast", defaultValue: "Want to see the forecast?", comment: "Generic confirmation question for forecast follow-up.")
    }

    private static func targetName(in followUp: MarinaFollowUpSuggestion) -> String? {
        trimmed(followUp.semanticRequest?.targetDisplayName) ?? trimmed(followUp.semanticRequest?.targetName)
    }

    private static func trimmed(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func amountInPrompt(_ prompt: String) -> Double? {
        let pattern = #"(?<!\d)(\d+(?:\.\d+)?)(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: prompt, range: NSRange(prompt.startIndex..., in: prompt)),
              let range = Range(match.range(at: 1), in: prompt) else {
            return nil
        }
        return Double(prompt[range])
    }

    nonisolated private static func shortCurrency(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.0001 {
            return "$\(Int(value.rounded()))"
        }
        return "$\(String(format: "%.2f", value))"
    }

    private static func normalized(_ value: String) -> String {
        let folded = value
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "let's", with: "lets", options: .caseInsensitive)
            .replacingOccurrences(of: "don't", with: "dont", options: .caseInsensitive)
            .replacingOccurrences(of: "i'm", with: "im", options: .caseInsensitive)

        return folded
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?;:"))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }
}
