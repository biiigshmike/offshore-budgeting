import Foundation

struct MarinaQueryRecoveryPolicy {
    func unsupportedTitle(for unsupported: MarinaTypedUnsupportedResponse) -> String {
        switch unsupported.kind {
        case .unsupportedOperation:
            return "I can answer this a different way"
        case .unsupportedTargetType, .unsupportedCombination, .unsupportedSimulation, .unsupportedDateShape:
            return "I need a narrower query"
        }
    }

    func selectionRank(for evaluation: CandidateEvaluation) -> Int {
        if evaluation.isExecutableHandled {
            if evaluation.candidate.semanticCommand != nil { return 0 }
            if evaluation.operationPreserved { return 1 }
            return 2
        }

        switch evaluation.validationOutcome {
        case .clarification:
            return evaluation.operationPreserved ? 3 : 4
        case .unsupported:
            return evaluation.operationPreserved ? 5 : 6
        case .executable:
            return evaluation.operationPreserved ? 7 : 8
        }
    }

    func rejectedReason(
        selected: CandidateEvaluation,
        other: CandidateEvaluation?
    ) -> String? {
        guard let other else { return nil }

        if selected.isExecutableHandled, other.isExecutableHandled == false {
            return "\(other.candidate.source.rawValue) was not executable"
        }

        if selected.operationPreserved, other.operationPreserved == false {
            return "\(other.candidate.source.rawValue) changed the requested operation"
        }

        if selected.candidate.semanticCommand != nil, other.candidate.semanticCommand == nil {
            return "\(other.candidate.source.rawValue) was less specific than semantic command"
        }

        if selectionRank(for: selected) < selectionRank(for: other) {
            return "\(other.candidate.source.rawValue) ranked lower for query recovery"
        }

        return nil
    }

    func operationPreserved(candidate: MarinaQueryPlanCandidate) -> Bool {
        let prompt = normalized(candidate.rawPrompt)

        if prompt.contains("average") || prompt.contains("usually spend") {
            return candidate.operation == .average
        }

        if prompt.contains("most recent")
            || prompt.contains("newest")
            || prompt.contains("latest")
            || prompt.hasPrefix("list ")
            || prompt.hasPrefix("show ")
            || prompt.contains(" list ")
            || prompt.contains(" last ") {
            return candidate.operation == .listRows
                || candidate.ranking?.direction == .newest
        }

        if prompt.contains("largest")
            || prompt.contains("biggest")
            || prompt.contains("top ")
            || prompt.contains("most expensive") {
            return candidate.operation == .rank
        }

        if prompt.contains("compare")
            || prompt.contains(" versus ")
            || prompt.contains(" vs ")
            || prompt.contains("higher than")
            || prompt.contains("lower than") {
            return candidate.operation == .compare
        }

        if prompt.contains("spend")
            || prompt.contains("spent")
            || prompt.contains("total") {
            return candidate.operation == .sum
                || candidate.operation == .compare
                || candidate.operation == .average
        }

        return true
    }

    private func normalized(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s&]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
