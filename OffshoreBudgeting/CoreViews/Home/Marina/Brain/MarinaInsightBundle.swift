import Foundation

struct MarinaInsightBundle: Codable, Equatable, Sendable {
    let headlineFact: String?
    let meaning: String?
    let signals: [MarinaInsightSignal]
    let followUps: [MarinaFollowUpSuggestion]

    init(
        headlineFact: String? = nil,
        meaning: String? = nil,
        signals: [MarinaInsightSignal] = [],
        followUps: [MarinaFollowUpSuggestion] = []
    ) {
        self.headlineFact = headlineFact
        self.meaning = meaning
        self.signals = signals
        self.followUps = followUps
    }

    var isEmpty: Bool {
        headlineFact == nil && meaning == nil && signals.isEmpty && followUps.isEmpty
    }
}

struct MarinaInsightSignal: Codable, Equatable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case opportunity
        case caution
        case celebration
        case context
    }

    let id: UUID
    let kind: Kind
    let title: String
    let detail: String

    init(
        id: UUID = UUID(),
        kind: Kind,
        title: String,
        detail: String
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
    }
}

struct MarinaFollowUpSuggestion: Codable, Equatable, Sendable, Identifiable {
    enum Reason: String, Codable, Sendable {
        case comparePreviousPeriod
        case inspectRows
        case breakdown
        case whatIf
        case forecast
        case nextDue
        case safeDailySpend
    }

    let id: UUID
    let title: String
    let prompt: String
    let reason: Reason
    let semanticRequest: MarinaSemanticRequest?

    init(
        id: UUID = UUID(),
        title: String,
        prompt: String,
        reason: Reason,
        semanticRequest: MarinaSemanticRequest? = nil
    ) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.reason = reason
        self.semanticRequest = semanticRequest
    }
}
