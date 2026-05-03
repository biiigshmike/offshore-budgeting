import Foundation

struct MarinaCandidateTrace: Codable, Equatable {
    let interpreterSource: MarinaInterpreterSource?
    let operation: MarinaCandidateOperation?
    let measure: MarinaCandidateMeasure?
    let entityMentionSummaries: [String]
    let timeScopeSummaries: [String]
    let groupingSummary: String?
    let rankingSummary: String?
    let responseShapeHint: MarinaResponseShapeHint?
    let validatorOutcomeSummary: String?
    let executablePlanSummary: String?

    init(
        candidate: MarinaQueryPlanCandidate? = nil,
        validatorOutcomeSummary: String? = nil,
        executablePlanSummary: String? = nil
    ) {
        self.interpreterSource = candidate?.source
        self.operation = candidate?.operation
        self.measure = candidate?.measure
        self.entityMentionSummaries = candidate?.entityMentions.map(Self.entityMentionSummary) ?? []
        self.timeScopeSummaries = candidate?.timeScopes.map(Self.timeScopeSummary) ?? []
        self.groupingSummary = candidate?.grouping.map(Self.groupingSummary)
        self.rankingSummary = candidate?.ranking.map(Self.rankingSummary)
        self.responseShapeHint = candidate?.responseShapeHint
        self.validatorOutcomeSummary = validatorOutcomeSummary
        self.executablePlanSummary = executablePlanSummary
    }

    var compactSummary: String {
        [
            interpreterSource.map { "source=\($0.rawValue)" },
            operation.map { "operation=\($0.rawValue)" },
            measure.map { "measure=\($0.rawValue)" },
            entityMentionSummaries.isEmpty ? nil : "entities=\(entityMentionSummaries.joined(separator: ";"))",
            timeScopeSummaries.isEmpty ? nil : "timeScopes=\(timeScopeSummaries.joined(separator: ";"))",
            groupingSummary.map { "grouping=\($0)" },
            rankingSummary.map { "ranking=\($0)" },
            responseShapeHint.map { "responseHint=\($0.rawValue)" },
            validatorOutcomeSummary.map { "validator=\($0)" },
            executablePlanSummary.map { "plan=\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: ",")
    }

    nonisolated private static func entityMentionSummary(_ mention: MarinaUnresolvedEntityMention) -> String {
        [
            mention.role.rawValue,
            mention.typeHint?.rawValue ?? "unknown",
            mention.rawText ?? "nil",
            mention.confidence.rawValue
        ].joined(separator: ":")
    }

    nonisolated private static func timeScopeSummary(_ scope: MarinaUnresolvedTimeScope) -> String {
        [
            scope.role.rawValue,
            scope.rawText ?? "nil",
            scope.periodUnitHint?.rawValue ?? "none",
            scope.resolvedRangeHint.map(dateRangeSummary) ?? "unresolved"
        ].joined(separator: ":")
    }

    nonisolated private static func dateRangeSummary(_ range: HomeQueryDateRange) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return "\(formatter.string(from: range.startDate))...\(formatter.string(from: range.endDate))"
    }

    nonisolated private static func groupingSummary(_ grouping: MarinaGroupingCandidate) -> String {
        [grouping.dimension.rawValue, grouping.rawText ?? "nil"].joined(separator: ":")
    }

    nonisolated private static func rankingSummary(_ ranking: MarinaRankingCandidate) -> String {
        [
            ranking.direction.rawValue,
            ranking.limit.map(String.init) ?? "nil",
            ranking.rawText ?? "nil"
        ].joined(separator: ":")
    }
}
