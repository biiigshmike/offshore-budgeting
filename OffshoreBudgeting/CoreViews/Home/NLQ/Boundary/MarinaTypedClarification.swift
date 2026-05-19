import Foundation

enum MarinaClarificationKind: String, Codable, Equatable {
    case missingTarget
    case ambiguousTarget
    case missingDateRange
    case ambiguousDateRange
    case unsupportedShape
    case lowConfidence
}

enum MarinaClarificationPatchSlot: String, Codable, Equatable, Sendable {
    case target
    case date
    case comparison
    case amount
    case simulation
}

struct MarinaClarificationChoice: Codable, Equatable, Identifiable {
    let id: UUID
    let title: String
    let subtitle: String?
    let entityRole: MarinaEntityMentionRole?
    let entityTypeHint: MarinaCandidateEntityTypeHint?
    let patchSlot: MarinaClarificationPatchSlot?
    let rawValue: String?
    let sourceID: UUID?
    let mentionID: UUID?

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String? = nil,
        entityRole: MarinaEntityMentionRole? = nil,
        entityTypeHint: MarinaCandidateEntityTypeHint? = nil,
        patchSlot: MarinaClarificationPatchSlot? = nil,
        rawValue: String? = nil,
        sourceID: UUID? = nil,
        mentionID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.entityRole = entityRole
        self.entityTypeHint = entityTypeHint
        self.patchSlot = patchSlot
        self.rawValue = rawValue
        self.sourceID = sourceID
        self.mentionID = mentionID
    }
}

struct MarinaTypedClarification: Codable, Equatable, Identifiable {
    let id: UUID
    let kind: MarinaClarificationKind
    let message: String
    let candidate: MarinaQueryPlanCandidate?
    let pendingSemanticQuery: MarinaSemanticQuery?
    let patchSlot: MarinaClarificationPatchSlot?
    let choices: [MarinaClarificationChoice]
    let canRunBestEffort: Bool

    init(
        id: UUID = UUID(),
        kind: MarinaClarificationKind,
        message: String,
        candidate: MarinaQueryPlanCandidate? = nil,
        pendingSemanticQuery: MarinaSemanticQuery? = nil,
        patchSlot: MarinaClarificationPatchSlot? = nil,
        choices: [MarinaClarificationChoice] = [],
        canRunBestEffort: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.message = message
        self.candidate = candidate
        self.pendingSemanticQuery = pendingSemanticQuery
        self.patchSlot = patchSlot
        self.choices = choices
        self.canRunBestEffort = canRunBestEffort
    }
}

enum MarinaClarificationChoiceResolution: Equatable {
    case resolved(MarinaClarificationChoice)
    case ambiguous([MarinaClarificationChoice])
    case unresolved
}

struct MarinaClarificationChoiceResolver {
    func resolve(
        reply: String,
        clarification: MarinaTypedClarification
    ) -> MarinaClarificationChoiceResolution {
        let key = Self.normalized(reply)
        guard key.isEmpty == false else { return .unresolved }

        let choices = clarification.actionableChoices
        guard choices.isEmpty == false else { return .unresolved }

        let matches = choices.filter { choice in
            lookupKeys(for: choice).contains(key)
        }

        if matches.count == 1, let match = matches.first {
            return .resolved(match)
        }
        if matches.count > 1 {
            return .ambiguous(matches)
        }
        return .unresolved
    }

    static func displayTitle(for choice: MarinaClarificationChoice) -> String {
        guard let type = choice.entityTypeHint else { return choice.title }
        return "\(choice.title) (\(type.rawValue))"
    }

    nonisolated static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func lookupKeys(for choice: MarinaClarificationChoice) -> Set<String> {
        var keys: Set<String> = [
            Self.displayTitle(for: choice),
            choice.title
        ]
        if let rawValue = choice.rawValue {
            keys.insert(rawValue)
        }
        if let type = choice.entityTypeHint {
            keys.insert(type.rawValue)
            keys.insert("\(choice.title) \(type.rawValue)")
            keys.insert("\(choice.title) (\(type.rawValue))")
            for alias in Self.typeAliases(for: type) {
                keys.insert(alias)
                keys.insert("\(choice.title) \(alias)")
                keys.insert("\(choice.title) (\(alias))")
            }
        }
        return Set(keys.map(Self.normalized).filter { $0.isEmpty == false })
    }

    private static func typeAliases(for type: MarinaCandidateEntityTypeHint) -> [String] {
        switch type {
        case .category:
            return ["category"]
        case .card:
            return ["card"]
        case .merchant:
            return ["merchant", "expense description", "description"]
        case .expense, .transaction:
            return ["expense", "transaction", "purchase"]
        case .budget:
            return ["budget"]
        case .preset:
            return ["preset"]
        case .incomeSource:
            return ["income source"]
        case .allocationAccount:
            return ["reconciliation", "reconciliation account", "shared balance"]
        case .savingsAccount:
            return ["savings", "savings account"]
        case .workspace:
            return ["workspace"]
        }
    }
}

extension MarinaClarificationChoice {
    func isEcho(of prompt: String) -> Bool {
        let prompt = Self.normalized(prompt)
        guard prompt.isEmpty == false else { return false }
        let candidates = [title, rawValue, subtitle].compactMap { $0 }.map(Self.normalized)
        return candidates.contains { value in
            value == prompt || value.contains(prompt) || prompt.contains(value)
        }
    }

    func isActionableChoice(for prompt: String) -> Bool {
        if isFullPromptEchoWithoutStableIdentity(of: prompt) {
            return false
        }
        if entityTypeHint != nil || sourceID != nil || patchSlot != nil || mentionID != nil {
            return true
        }
        return isEcho(of: prompt) == false
    }

    private func isFullPromptEchoWithoutStableIdentity(of prompt: String) -> Bool {
        let prompt = Self.normalized(prompt)
        guard prompt.isEmpty == false,
              sourceID == nil,
              mentionID == nil else {
            return false
        }
        return [title, rawValue]
            .compactMap { $0 }
            .map(Self.normalized)
            .contains(prompt)
    }

    nonisolated private static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension MarinaTypedClarification {
    func isActionable(for originalPrompt: String) -> Bool {
        let choices = actionableChoices(for: originalPrompt)
        switch kind {
        case .missingTarget:
            if choices.isEmpty == false {
                return true
            }
            return self.choices.isEmpty && (patchSlot != nil || pendingSemanticQuery != nil)
        case .ambiguousTarget, .ambiguousDateRange:
            return choices.count > 1
        case .missingDateRange:
            return patchSlot != nil || choices.isEmpty == false
        case .unsupportedShape, .lowConfidence:
            return false
        }
    }

    func actionableChoices(for originalPrompt: String) -> [MarinaClarificationChoice] {
        choices.filter { $0.isActionableChoice(for: originalPrompt) }
    }

    var actionableChoices: [MarinaClarificationChoice] {
        guard let prompt = candidate?.rawPrompt else { return choices }
        return actionableChoices(for: prompt)
    }
}

enum MarinaUnsupportedResponseKind: String, Codable, Equatable {
    case unsupportedOperation
    case unsupportedTargetType
    case unsupportedCombination
    case unsupportedSimulation
    case unsupportedDateShape
}

struct MarinaTypedUnsupportedResponse: Codable, Equatable, Identifiable {
    let id: UUID
    let kind: MarinaUnsupportedResponseKind
    let message: String
    let candidate: MarinaQueryPlanCandidate?

    init(
        id: UUID = UUID(),
        kind: MarinaUnsupportedResponseKind,
        message: String,
        candidate: MarinaQueryPlanCandidate? = nil
    ) {
        self.id = id
        self.kind = kind
        self.message = message
        self.candidate = candidate
    }
}

enum MarinaPlanValidationOutcome: Codable, Equatable {
    case executable(MarinaAggregationPlan)
    case clarification(MarinaTypedClarification)
    case unsupported(MarinaTypedUnsupportedResponse)
}
