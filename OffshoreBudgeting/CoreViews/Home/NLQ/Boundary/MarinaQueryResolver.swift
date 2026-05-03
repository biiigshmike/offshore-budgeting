import Foundation

struct MarinaResolvedEntityMention: Equatable, Identifiable {
    let id: UUID
    let mention: MarinaUnresolvedEntityMention
    let role: MarinaResolvedTargetRole
    let entityType: MarinaCandidateEntityTypeHint
    let displayName: String
    let sourceID: UUID?
}

struct MarinaAmbiguousEntityMention: Equatable, Identifiable {
    let id: UUID
    let mention: MarinaUnresolvedEntityMention
    let choices: [MarinaClarificationChoice]

    init(
        id: UUID = UUID(),
        mention: MarinaUnresolvedEntityMention,
        choices: [MarinaClarificationChoice]
    ) {
        self.id = id
        self.mention = mention
        self.choices = choices
    }
}

struct MarinaResolvedQueryCandidate: Equatable {
    let candidate: MarinaQueryPlanCandidate
    let resolvedTargets: [MarinaResolvedEntityMention]
    let unresolvedMentions: [MarinaUnresolvedEntityMention]
    let ambiguousMentions: [MarinaAmbiguousEntityMention]
    let primaryDateRange: HomeQueryDateRange?
    let comparisonDateRange: HomeQueryDateRange?

    var hasResolutionProblems: Bool {
        unresolvedMentions.isEmpty == false || ambiguousMentions.isEmpty == false
    }
}

@MainActor
struct MarinaQueryResolver {
    private let extractor = MarinaNLQCandidateExtractor()

    func resolve(
        candidate: MarinaQueryPlanCandidate,
        provider: MarinaDataProvider
    ) -> MarinaResolvedQueryCandidate {
        var resolvedTargets: [MarinaResolvedEntityMention] = []
        var unresolvedMentions: [MarinaUnresolvedEntityMention] = []
        var ambiguousMentions: [MarinaAmbiguousEntityMention] = []

        for mention in candidate.entityMentions {
            guard let rawText = mention.rawText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  rawText.isEmpty == false else {
                unresolvedMentions.append(mention)
                continue
            }

            let extraction = extractor.extractCandidates(from: rawText, provider: provider)
            let matches = scopedMatches(
                extraction.matchesByType.flatMap(\.value),
                typeHint: mention.typeHint
            )

            switch representativeMatches(from: matches) {
            case .none:
                unresolvedMentions.append(mention)
            case .one(let match):
                resolvedTargets.append(
                    MarinaResolvedEntityMention(
                        id: mention.id,
                        mention: mention,
                        role: resolvedRole(from: mention.role),
                        entityType: candidateType(from: match.entityType),
                        displayName: match.displayValue,
                        sourceID: match.sourceID
                    )
                )
            case .many(let matches):
                ambiguousMentions.append(
                    MarinaAmbiguousEntityMention(
                        mention: mention,
                        choices: matches.map { match in
                            MarinaClarificationChoice(
                                title: match.displayValue,
                                entityRole: mention.role,
                                entityTypeHint: candidateType(from: match.entityType),
                                rawValue: match.displayValue
                            )
                        }
                    )
                )
            }
        }

        return MarinaResolvedQueryCandidate(
            candidate: candidate,
            resolvedTargets: resolvedTargets,
            unresolvedMentions: unresolvedMentions,
            ambiguousMentions: ambiguousMentions,
            primaryDateRange: candidate.timeScopes.first(where: { $0.role == .primary || $0.role == .lookbackWindow })?.resolvedRangeHint,
            comparisonDateRange: candidate.timeScopes.first(where: { $0.role == .comparison })?.resolvedRangeHint
        )
    }

    private enum RepresentativeMatchSet {
        case none
        case one(MarinaNLQCandidateMatch)
        case many([MarinaNLQCandidateMatch])
    }

    private func representativeMatches(from matches: [MarinaNLQCandidateMatch]) -> RepresentativeMatchSet {
        guard matches.isEmpty == false else { return .none }

        var bestByKey: [String: MarinaNLQCandidateMatch] = [:]
        for match in matches {
            let key = "\(match.entityType.rawValue)|\(match.normalizedValue)"
            if let existing = bestByKey[key] {
                if existing.matchType == .prefix && match.matchType == .exact {
                    bestByKey[key] = match
                }
            } else {
                bestByKey[key] = match
            }
        }

        let representatives = bestByKey.values.sorted { lhs, rhs in
            if lhs.entityType.rawValue == rhs.entityType.rawValue {
                return lhs.displayValue.localizedCaseInsensitiveCompare(rhs.displayValue) == .orderedAscending
            }
            return lhs.entityType.rawValue < rhs.entityType.rawValue
        }

        return representatives.count == 1 ? .one(representatives[0]) : .many(representatives)
    }

    private func scopedMatches(
        _ matches: [MarinaNLQCandidateMatch],
        typeHint: MarinaCandidateEntityTypeHint?
    ) -> [MarinaNLQCandidateMatch] {
        guard let typeHint,
              let nlqType = nlqType(from: typeHint) else {
            return matches
        }
        return matches.filter { $0.entityType == nlqType }
    }

    private func nlqType(from hint: MarinaCandidateEntityTypeHint) -> MarinaNLQTargetType? {
        switch hint {
        case .category:
            return .category
        case .merchant:
            return .merchant
        case .expense, .transaction:
            return .expense
        case .card:
            return .card
        case .budget:
            return .budget
        case .preset:
            return .preset
        case .incomeSource:
            return .incomeSource
        case .allocationAccount:
            return .allocationAccount
        case .savingsAccount:
            return .savingsAccount
        case .workspace:
            return nil
        }
    }

    private func candidateType(from targetType: MarinaNLQTargetType) -> MarinaCandidateEntityTypeHint {
        switch targetType {
        case .category:
            return .category
        case .merchant:
            return .merchant
        case .expense:
            return .expense
        case .card:
            return .card
        case .budget:
            return .budget
        case .preset:
            return .preset
        case .incomeSource:
            return .incomeSource
        case .allocationAccount:
            return .allocationAccount
        case .savingsAccount:
            return .savingsAccount
        }
    }

    private func resolvedRole(from role: MarinaEntityMentionRole) -> MarinaResolvedTargetRole {
        switch role {
        case .filter:
            return .filter
        case .primaryTarget:
            return .primaryTarget
        case .comparisonTarget:
            return .comparisonTarget
        case .groupingDimension:
            return .groupingDimension
        case .simulationInput:
            return .simulationInput
        case .simulationOutput:
            return .simulationOutput
        }
    }
}
