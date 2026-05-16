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

extension MarinaClarificationChoice {
    func isEcho(of prompt: String) -> Bool {
        let prompt = Self.normalized(prompt)
        guard prompt.isEmpty == false else { return false }
        let candidates = [title, rawValue, subtitle].compactMap { $0 }.map(Self.normalized)
        return candidates.contains { value in
            value == prompt || value.contains(prompt) || prompt.contains(value)
        }
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
        switch kind {
        case .missingTarget:
            if choices.count == 1, choices[0].isEcho(of: originalPrompt) {
                return false
            }
            return choices.isEmpty == false || patchSlot != nil || pendingSemanticQuery != nil
        case .ambiguousTarget, .ambiguousDateRange:
            return choices.count > 1
        case .missingDateRange:
            return patchSlot != nil || choices.isEmpty == false
        case .unsupportedShape, .lowConfidence:
            return false
        }
    }

    var actionableChoices: [MarinaClarificationChoice] {
        guard let prompt = candidate?.rawPrompt else { return choices }
        return choices.filter { $0.isEcho(of: prompt) == false }
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
