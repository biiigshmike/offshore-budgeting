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
                mention: mention
            )

            switch representativeMatches(from: matches, mention: mention) {
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
                                subtitle: match.entityType.rawValue,
                                entityRole: mention.role,
                                entityTypeHint: candidateType(from: match.entityType),
                                rawValue: match.displayValue,
                                sourceID: match.sourceID,
                                mentionID: mention.id
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

    private func representativeMatches(
        from matches: [MarinaNLQCandidateMatch],
        mention: MarinaUnresolvedEntityMention
    ) -> RepresentativeMatchSet {
        guard matches.isEmpty == false else { return .none }

        let exactMatches = matches.filter { $0.matchType == .exact }
        let storedExactMatches = exactMatches.filter { match in
            switch match.entityType {
            case .merchant, .expense:
                return false
            case .category, .card, .budget, .preset, .incomeSource, .allocationAccount, .savingsAccount:
                return true
            }
        }
        let hasSingleTypeHint = mention.typeHint != nil || mention.allowedTypeHints?.count == 1
        let exactEntityTypes = Set(exactMatches.map(\.entityType))
        let shouldPreferExactCategory = hasSingleTypeHint == false
            && Set(storedExactMatches.map(\.entityType)) == [.category]
            && exactEntityTypes.isSubset(of: [.category, .merchant, .expense])
        let shouldPreserveCrossFamilyExactMatches = hasSingleTypeHint == false
            && exactEntityTypes.count > 1
            && shouldPreferExactCategory == false
        let preferredMatches = shouldPreserveCrossFamilyExactMatches
            ? matches
            : (storedExactMatches.isEmpty == false ? storedExactMatches : matches)
        let equivalenceCollapsed = collapseEquivalentMatches(preferredMatches)
        var bestByKey: [String: MarinaNLQCandidateMatch] = [:]
        for match in equivalenceCollapsed {
            let key = canonicalIdentityKey(for: match)
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

    private func collapseEquivalentMatches(_ matches: [MarinaNLQCandidateMatch]) -> [MarinaNLQCandidateMatch] {
        guard matches.count > 1 else { return matches }

        // Merchant candidates are extracted from variable expense text and can duplicate
        // the same visible target as expense candidates. Prefer merchant in those pairs.
        let groupedByNormalizedDisplay = Dictionary(grouping: matches, by: {
            normalizeDisplay($0.displayValue)
        })
        var collapsed: [MarinaNLQCandidateMatch] = []

        for bucket in groupedByNormalizedDisplay.values {
            let hasMerchant = bucket.contains(where: { $0.entityType == .merchant })
            if hasMerchant {
                let filtered = bucket.filter { $0.entityType != .expense }
                collapsed.append(contentsOf: filtered.isEmpty ? bucket : filtered)
            } else {
                collapsed.append(contentsOf: bucket)
            }
        }

        return collapsed
    }

    private func canonicalIdentityKey(for match: MarinaNLQCandidateMatch) -> String {
        switch match.entityType {
        case .merchant:
            // Merchant source IDs are variable-expense row IDs, not stable merchant IDs.
            return "\(match.entityType.rawValue)|\(match.normalizedValue)"
        default:
            let normalizedDisplay = normalizeDisplay(match.displayValue)
            return "\(match.entityType.rawValue)|\(match.sourceID.uuidString.lowercased())|\(match.normalizedValue)|\(normalizedDisplay)"
        }
    }

    private func normalizeDisplay(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s&]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func scopedMatches(
        _ matches: [MarinaNLQCandidateMatch],
        mention: MarinaUnresolvedEntityMention
    ) -> [MarinaNLQCandidateMatch] {
        let allowedTypes = mention.allowedTypeHints?.isEmpty == false
            ? mention.allowedTypeHints
            : mention.typeHint.map { [$0] }

        guard let allowedTypes else {
            return matches
        }
        let nlqTypes = allowedTypes.compactMap(nlqType)
        guard nlqTypes.isEmpty == false else { return matches }
        return matches.filter { nlqTypes.contains($0.entityType) }
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
        case .excludeFilter:
            return .excludeFilter
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
