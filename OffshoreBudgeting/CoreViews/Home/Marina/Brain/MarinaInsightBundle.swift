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

enum MarinaFollowUpExecutionMode: String, Codable, Equatable, Sendable {
    case executable
    case clarificationRequired
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
        case showMore
    }

    let id: UUID
    let title: String
    let prompt: String
    let reason: Reason
    let executionMode: MarinaFollowUpExecutionMode
    let semanticRequest: MarinaSemanticRequest?

    init(
        id: UUID = UUID(),
        title: String,
        prompt: String,
        reason: Reason,
        executionMode: MarinaFollowUpExecutionMode? = nil,
        semanticRequest: MarinaSemanticRequest? = nil
    ) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.reason = reason
        self.executionMode = executionMode ?? (semanticRequest == nil ? .clarificationRequired : .executable)
        self.semanticRequest = semanticRequest
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case prompt
        case reason
        case executionMode
        case semanticRequest
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        prompt = try container.decode(String.self, forKey: .prompt)
        reason = try container.decode(Reason.self, forKey: .reason)
        semanticRequest = try container.decodeIfPresent(MarinaSemanticRequest.self, forKey: .semanticRequest)
        executionMode = try container.decodeIfPresent(MarinaFollowUpExecutionMode.self, forKey: .executionMode)
            ?? (semanticRequest == nil ? .clarificationRequired : .executable)
    }
}
