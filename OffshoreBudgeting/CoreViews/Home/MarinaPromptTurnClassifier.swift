import Foundation

enum MarinaPromptTurnClassification: String, Codable, Equatable, Sendable {
    case freshQuestion
    case followUp
    case clarificationAnswer
    case command
}

struct MarinaPromptTurnClassifier {
    private let commandGuard: HomeAssistantSharedPipelineCommandGuard
    private let parser: HomeAssistantTextParser

    init(
        commandGuard: HomeAssistantSharedPipelineCommandGuard = HomeAssistantSharedPipelineCommandGuard(),
        parser: HomeAssistantTextParser = HomeAssistantTextParser()
    ) {
        self.commandGuard = commandGuard
        self.parser = parser
    }

    func classify(
        _ prompt: String,
        defaultPeriodUnit: HomeQueryPeriodUnit,
        hasActiveClarification: Bool = false
    ) -> MarinaPromptTurnClassification {
        let normalized = Self.normalized(prompt)
        guard normalized.isEmpty == false else { return .freshQuestion }

        if commandGuard.command(for: prompt, defaultPeriodUnit: defaultPeriodUnit) != nil {
            return .command
        }

        if isDependentFollowUp(normalized) {
            return .followUp
        }

        if parser.parsePlan(prompt, defaultPeriodUnit: defaultPeriodUnit) != nil || isSelfContainedQuestion(normalized) {
            return .freshQuestion
        }

        if hasActiveClarification, isShortClarificationAnswer(normalized) {
            return .clarificationAnswer
        }

        return hasActiveClarification ? .clarificationAnswer : .freshQuestion
    }

    func shouldTreatAsFreshPrompt(
        _ prompt: String,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> Bool {
        let classification = classify(
            prompt,
            defaultPeriodUnit: defaultPeriodUnit,
            hasActiveClarification: true
        )
        return classification == .freshQuestion || classification == .command
    }

    private func isSelfContainedQuestion(_ normalized: String) -> Bool {
        let starts = [
            "what ", "when ", "where ", "which ", "who ", "how ",
            "did ", "do ", "does ", "can ", "show ", "list ",
            "compare ", "break down ", "if ", "what if "
        ]
        return starts.contains { normalized.hasPrefix($0) }
    }

    private func isShortClarificationAnswer(_ normalized: String) -> Bool {
        normalized.split(separator: " ").count <= 4 && isSelfContainedQuestion(normalized) == false
    }

    private func isDependentFollowUp(_ normalized: String) -> Bool {
        let prefixes = [
            "what about ",
            "how about ",
            "same for ",
            "same with ",
            "and ",
            "also ",
            "compare that",
            "compare it",
            "what if "
        ]
        if prefixes.contains(where: { normalized.hasPrefix($0) }) {
            return true
        }

        return normalized == "last month"
            || normalized == "last week"
            || normalized == "this month"
            || normalized == "this week"
            || normalized.hasPrefix("that ")
            || normalized.hasPrefix("those ")
    }

    private static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s$]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
