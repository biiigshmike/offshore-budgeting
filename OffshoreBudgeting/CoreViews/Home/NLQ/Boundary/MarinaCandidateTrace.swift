import Foundation

struct MarinaCandidateTrace: Codable, Equatable {
    let requestFamily: MarinaRequestFamily?
    let requestShape: MarinaRequestShape?
    let interpreterSource: MarinaInterpreterSource?
    let operation: MarinaCandidateOperation?
    let measure: MarinaCandidateMeasure?
    let entityMentionSummaries: [String]
    let timeScopeSummaries: [String]
    let groupingSummary: String?
    let rankingSummary: String?
    let semanticCommandSummary: String?
    let responseShapeHint: MarinaResponseShapeHint?
    let validatorOutcomeSummary: String?
    let executablePlanSummary: String?
    let selectionRank: Int?
    let rejectedReason: String?
    let operationPreserved: Bool?

    init(
        candidate: MarinaQueryPlanCandidate? = nil,
        validatorOutcomeSummary: String? = nil,
        executablePlanSummary: String? = nil,
        selectionRank: Int? = nil,
        rejectedReason: String? = nil,
        operationPreserved: Bool? = nil
    ) {
        self.requestFamily = candidate?.requestFamily
        self.requestShape = candidate.flatMap(Self.requestShape)
        self.interpreterSource = candidate?.source
        self.operation = candidate?.operation
        self.measure = candidate?.measure
        self.entityMentionSummaries = candidate?.entityMentions.map(Self.entityMentionSummary) ?? []
        self.timeScopeSummaries = candidate?.timeScopes.map(Self.timeScopeSummary) ?? []
        self.groupingSummary = candidate?.grouping.map(Self.groupingSummary)
        self.rankingSummary = candidate?.ranking.map(Self.rankingSummary)
        self.semanticCommandSummary = candidate?.semanticCommand.map(Self.semanticCommandSummary)
        self.responseShapeHint = candidate?.responseShapeHint
        self.validatorOutcomeSummary = validatorOutcomeSummary
        self.executablePlanSummary = executablePlanSummary
        self.selectionRank = selectionRank
        self.rejectedReason = rejectedReason
        self.operationPreserved = operationPreserved
    }

    var compactSummary: String {
        [
            requestFamily.map { "family=\($0.rawValue)" },
            requestShape.map { "requestShape=\($0.rawValue)" },
            interpreterSource.map { "source=\($0.rawValue)" },
            operation.map { "operation=\($0.rawValue)" },
            measure.map { "measure=\($0.rawValue)" },
            entityMentionSummaries.isEmpty ? nil : "entities=\(entityMentionSummaries.joined(separator: ";"))",
            timeScopeSummaries.isEmpty ? nil : "timeScopes=\(timeScopeSummaries.joined(separator: ";"))",
            groupingSummary.map { "grouping=\($0)" },
            rankingSummary.map { "ranking=\($0)" },
            semanticCommandSummary.map { "semantic=\($0)" },
            responseShapeHint.map { "responseHint=\($0.rawValue)" },
            validatorOutcomeSummary.map { "validator=\($0)" },
            executablePlanSummary.map { "plan=\($0)" },
            selectionRank.map { "selectionRank=\($0)" },
            rejectedReason.map { "rejected=\($0)" },
            operationPreserved.map { "operationPreserved=\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: ",")
    }

    nonisolated private static func entityMentionSummary(_ mention: MarinaUnresolvedEntityMention) -> String {
        [
            mention.role.rawValue,
            mention.allowedTypeHints?.map(\.rawValue).joined(separator: "|") ?? mention.typeHint?.rawValue ?? "unknown",
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

    nonisolated private static func semanticCommandSummary(_ command: MarinaSemanticCommand) -> String {
        [
            command.action.rawValue,
            command.datasets.map(\.rawValue).joined(separator: "|"),
            command.sort?.rawValue ?? "nil",
            command.limit.map(String.init) ?? "nil"
        ].joined(separator: ":")
    }

    nonisolated private static func requestShape(_ candidate: MarinaQueryPlanCandidate) -> MarinaRequestShape? {
        if let requestShape = candidate.requestShape {
            return requestShape
        }

        if candidate.requestFamily == .databaseLookup {
            let hasSearch = candidate.databaseLookupRequest?.searchText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty == false
            return hasSearch ? .objectDetails : .objectInventoryList
        }

        if candidate.operation == .listRows
            || candidate.measure == .savingsMovement
            || candidate.grouping?.dimension == .savingsLedgerEntry {
            return .ledgerRowList
        }

        if candidate.operation == .lookupDetails {
            switch candidate.semanticCommand?.requestedDetail {
            case .linkedCards, .linkedPresets, .categoryLimits, .membership:
                return .relationshipList
            default:
                return .objectDetails
            }
        }

        if candidate.operation != nil {
            return .aggregateMetric
        }

        return nil
    }
}
