import Foundation

enum MarinaClarificationKind: String, Codable, Equatable {
    case missingTarget
    case ambiguousTarget
    case missingDateRange
    case ambiguousDateRange
    case unsupportedShape
    case lowConfidence
}

struct MarinaClarificationChoice: Codable, Equatable, Identifiable {
    let id: UUID
    let title: String
    let entityRole: MarinaEntityMentionRole?
    let entityTypeHint: MarinaCandidateEntityTypeHint?
    let rawValue: String?

    init(
        id: UUID = UUID(),
        title: String,
        entityRole: MarinaEntityMentionRole? = nil,
        entityTypeHint: MarinaCandidateEntityTypeHint? = nil,
        rawValue: String? = nil
    ) {
        self.id = id
        self.title = title
        self.entityRole = entityRole
        self.entityTypeHint = entityTypeHint
        self.rawValue = rawValue
    }
}

struct MarinaTypedClarification: Codable, Equatable, Identifiable {
    let id: UUID
    let kind: MarinaClarificationKind
    let message: String
    let candidate: MarinaQueryPlanCandidate?
    let choices: [MarinaClarificationChoice]
    let canRunBestEffort: Bool

    init(
        id: UUID = UUID(),
        kind: MarinaClarificationKind,
        message: String,
        candidate: MarinaQueryPlanCandidate? = nil,
        choices: [MarinaClarificationChoice] = [],
        canRunBestEffort: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.message = message
        self.candidate = candidate
        self.choices = choices
        self.canRunBestEffort = canRunBestEffort
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
