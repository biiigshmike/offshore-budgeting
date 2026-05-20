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

struct MarinaResolvedFilter: Equatable, Identifiable {
    let id: UUID
    let filter: MarinaFilter
    let role: MarinaResolvedTargetRole
    let relationship: MarinaRelationshipField
    let entityType: MarinaCandidateEntityTypeHint
    let displayName: String
    let sourceID: UUID?
}

struct MarinaAmbiguousFilter: Equatable, Identifiable {
    let id: UUID
    let filter: MarinaFilter
    let choices: [MarinaClarificationChoice]

    init(
        id: UUID = UUID(),
        filter: MarinaFilter,
        choices: [MarinaClarificationChoice]
    ) {
        self.id = id
        self.filter = filter
        self.choices = choices
    }
}

struct MarinaResolvedSemanticQuery: Equatable {
    let query: MarinaSemanticQuery
    let candidate: MarinaQueryPlanCandidate?
    let resolvedFilters: [MarinaResolvedFilter]
    let unresolvedFilters: [MarinaFilter]
    let ambiguousFilters: [MarinaAmbiguousFilter]
    let primaryDateRange: HomeQueryDateRange?
    let comparisonDateRange: HomeQueryDateRange?
    let databaseLookupRequest: MarinaDatabaseLookupRequest?

    var hasResolutionProblems: Bool {
        unresolvedFilters.isEmpty == false || ambiguousFilters.isEmpty == false
    }
}

@MainActor
struct MarinaQueryResolver {
    private let extractor = MarinaNLQCandidateExtractor()

    func resolve(
        candidate: MarinaQueryPlanCandidate,
        provider: MarinaDataProvider,
        now: Date = Date(),
        defaultPeriodUnit: HomeQueryPeriodUnit = .month
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

            switch representativeMatches(
                from: matches,
                mention: mention,
                preferExactCategoryOverExpenseDescription: candidate.operation != .lookupDetails
            ) {
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
                        choices: sortedClarificationChoices(matches.map { match in
                            MarinaClarificationChoice(
                                title: match.displayValue,
                                subtitle: match.clarificationSubtitle ?? match.entityType.rawValue,
                                entityRole: mention.role,
                                entityTypeHint: candidateType(from: match.entityType),
                                patchSlot: .target,
                                rawValue: match.displayValue,
                                sourceID: match.sourceID,
                                mentionID: mention.id
                            )
                        })
                    )
                )
            }
        }

        return MarinaResolvedQueryCandidate(
            candidate: candidate,
            resolvedTargets: resolvedTargets,
            unresolvedMentions: unresolvedMentions,
            ambiguousMentions: ambiguousMentions,
            primaryDateRange: resolvedDateRange(
                from: candidate.timeScopes.first(where: { $0.role == .primary || $0.role == .lookbackWindow }),
                now: now,
                defaultPeriodUnit: defaultPeriodUnit
            ),
            comparisonDateRange: resolvedDateRange(
                from: candidate.timeScopes.first(where: { $0.role == .comparison }),
                now: now,
                defaultPeriodUnit: defaultPeriodUnit
            )
        )
    }

    func resolve(
        query: MarinaSemanticQuery,
        provider: MarinaDataProvider,
        candidate: MarinaQueryPlanCandidate? = nil,
        now: Date = Date(),
        defaultPeriodUnit: HomeQueryPeriodUnit = .month
    ) -> MarinaResolvedSemanticQuery {
        var resolvedFilters: [MarinaResolvedFilter] = []
        var unresolvedFilters: [MarinaFilter] = []
        var ambiguousFilters: [MarinaAmbiguousFilter] = []

        for filter in query.filters {
            let trimmedValue = filter.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedValue.isEmpty == false else {
                unresolvedFilters.append(filter)
                continue
            }

            if isUncategorizedFilter(filter) {
                resolvedFilters.append(
                    MarinaResolvedFilter(
                        id: filter.id,
                        filter: filter,
                        role: filter.role,
                        relationship: .uncategorized,
                        entityType: .category,
                        displayName: "Uncategorized",
                        sourceID: nil
                    )
                )
                continue
            }

            if let sourceID = filter.sourceID,
               let entityType = filter.entityTypeHint {
                resolvedFilters.append(
                    MarinaResolvedFilter(
                        id: filter.id,
                        filter: filter,
                        role: filter.role,
                        relationship: filter.relationship,
                        entityType: entityType,
                        displayName: trimmedValue,
                        sourceID: sourceID
                    )
                )
                continue
            }

            let mention = MarinaUnresolvedEntityMention(
                id: filter.id,
                role: mentionRole(from: filter.role),
                rawText: trimmedValue,
                typeHint: filter.entityTypeHint ?? singleAllowedTypeHint(from: filter) ?? entityTypeHint(from: filter.relationship),
                allowedTypeHints: allowedTypeHints(from: filter),
                confidence: filter.matchMode == .exact ? .high : .medium
            )
            let extraction = extractor.extractCandidates(from: trimmedValue, provider: provider)
            let matches = scopedMatches(
                extraction.matchesByType.flatMap(\.value),
                mention: mention
            )

            switch representativeMatches(
                from: matches,
                mention: mention,
                preferExactCategoryOverExpenseDescription: query.operation != .lookupDetails
            ) {
            case .none:
                unresolvedFilters.append(filter)
            case .one(let match):
                resolvedFilters.append(
                    MarinaResolvedFilter(
                        id: filter.id,
                        filter: filter,
                        role: filter.role,
                        relationship: relationship(from: match.entityType),
                        entityType: candidateType(from: match.entityType),
                        displayName: match.displayValue,
                        sourceID: match.sourceID
                    )
                )
            case .many(let matches):
                ambiguousFilters.append(
                    MarinaAmbiguousFilter(
                        filter: filter,
                        choices: sortedClarificationChoices(matches.map { match in
                            MarinaClarificationChoice(
                                title: match.displayValue,
                                subtitle: match.clarificationSubtitle ?? match.entityType.rawValue,
                                entityRole: mention.role,
                                entityTypeHint: candidateType(from: match.entityType),
                                patchSlot: .target,
                                rawValue: match.displayValue,
                                sourceID: match.sourceID,
                                mentionID: filter.id
                            )
                        })
                    )
                )
            }
        }

        return MarinaResolvedSemanticQuery(
            query: query,
            candidate: candidate,
            resolvedFilters: resolvedFilters,
            unresolvedFilters: unresolvedFilters,
            ambiguousFilters: ambiguousFilters,
            primaryDateRange: resolvedDateRange(
                from: query.dateRange,
                now: now,
                defaultPeriodUnit: defaultPeriodUnit
            ),
            comparisonDateRange: resolvedDateRange(
                from: query.comparisonDateRange,
                now: now,
                defaultPeriodUnit: defaultPeriodUnit
            ),
            databaseLookupRequest: candidate?.databaseLookupRequest
        )
    }

    private func resolvedDateRange(
        from scope: MarinaUnresolvedTimeScope?,
        now: Date,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> HomeQueryDateRange? {
        guard let scope else { return nil }
        if let resolved = scope.resolvedRangeHint {
            return resolved
        }
        return resolvedDateRange(
            rawText: scope.rawText,
            periodUnit: scope.periodUnitHint,
            now: now,
            defaultPeriodUnit: defaultPeriodUnit
        )
    }

    private func resolvedDateRange(
        from request: MarinaDateRangeRequest?,
        now: Date,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> HomeQueryDateRange? {
        guard let request else { return nil }
        if let resolved = request.resolvedRange {
            return resolved
        }
        return resolvedDateRange(
            rawText: request.rawText,
            periodUnit: request.periodUnit,
            now: now,
            defaultPeriodUnit: defaultPeriodUnit
        )
    }

    private func resolvedDateRange(
        rawText: String?,
        periodUnit: HomeQueryPeriodUnit?,
        now: Date,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> HomeQueryDateRange? {
        guard let rawText = rawText?.trimmingCharacters(in: .whitespacesAndNewlines),
              rawText.isEmpty == false else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let resolver = MarinaDateResolver(calendar: calendar, nowProvider: { now })
        return resolver.resolve(
            input: rawText,
            modelStartISO8601: nil,
            modelEndISO8601: nil,
            defaultPeriodUnit: periodUnit ?? defaultPeriodUnit
        )?.queryDateRange
    }

    private enum RepresentativeMatchSet {
        case none
        case one(MarinaNLQCandidateMatch)
        case many([MarinaNLQCandidateMatch])
    }

    private func representativeMatches(
        from matches: [MarinaNLQCandidateMatch],
        mention: MarinaUnresolvedEntityMention,
        preferExactCategoryOverExpenseDescription: Bool
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
        let hasSingleTypeHint = mention.allowedTypeHints?.count == 1
            || (mention.allowedTypeHints == nil && mention.typeHint != nil)
        let isExplicitMerchantCue = mention.typeHint == .merchant
            && (mention.allowedTypeHints?.count ?? 0) > 1
        let matchEntityTypes = Set(matches.map(\.entityType))
        let exactEntityTypes = Set(exactMatches.map(\.entityType))
        let hasOnlyCategoryExactMatch = Set(storedExactMatches.map(\.entityType)) == [.category]
        let shouldPreferExplicitMerchant = isExplicitMerchantCue
            && exactEntityTypes.contains(.merchant)
        let hasMerchantPrefixCollision = matchEntityTypes.contains(.merchant)
            && exactEntityTypes.contains(.merchant) == false
        let hasStoredObjectPrefixCollision = matchEntityTypes.contains { type in
            switch type {
            case .card, .budget, .preset, .incomeSource, .allocationAccount, .savingsAccount:
                return exactEntityTypes.contains(type) == false
            case .category, .merchant, .expense:
                return false
            }
        }
        let shouldPreservePrefixCrossFamilyMatches = hasSingleTypeHint == false
            && hasOnlyCategoryExactMatch
            && (hasMerchantPrefixCollision || hasStoredObjectPrefixCollision)
        let shouldPreferExactCategory = hasSingleTypeHint == false
            && hasOnlyCategoryExactMatch
            && exactEntityTypes.isSubset(of: [.category, .merchant, .expense])
            && shouldPreservePrefixCrossFamilyMatches == false
            && shouldPreferExplicitMerchant == false
            && preferExactCategoryOverExpenseDescription
        let shouldPreserveCrossFamilyExactMatches = hasSingleTypeHint == false
            && exactEntityTypes.count > 1
            && shouldPreferExactCategory == false
        let preferredMatches: [MarinaNLQCandidateMatch]
        if shouldPreferExplicitMerchant {
            let exactMerchantMatches = exactMatches.filter { $0.entityType == .merchant }
            preferredMatches = exactMerchantMatches.isEmpty
                ? matches.filter { $0.entityType == .merchant || $0.entityType == .expense }
                : exactMerchantMatches
        } else if shouldPreserveCrossFamilyExactMatches || shouldPreservePrefixCrossFamilyMatches {
            preferredMatches = matches
        } else {
            preferredMatches = storedExactMatches.isEmpty == false ? storedExactMatches : matches
        }
        let equivalenceCollapsed = collapseEquivalentMatches(
            preferredMatches,
            preferExpenseOverMerchant: preferExactCategoryOverExpenseDescription == false
        )
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

    private func sortedClarificationChoices(_ choices: [MarinaClarificationChoice]) -> [MarinaClarificationChoice] {
        choices.sorted { lhs, rhs in
            let lhsRank = clarificationTypeRank(lhs.entityTypeHint)
            let rhsRank = clarificationTypeRank(rhs.entityTypeHint)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func clarificationTypeRank(_ type: MarinaCandidateEntityTypeHint?) -> Int {
        switch type {
        case .card:
            return 0
        case .category:
            return 1
        case .merchant:
            return 2
        case .preset:
            return 3
        case .expense, .transaction:
            return 4
        case .budget:
            return 5
        case .incomeSource:
            return 6
        case .savingsAccount:
            return 7
        case .allocationAccount:
            return 8
        case .workspace, nil:
            return 9
        }
    }

    private func collapseEquivalentMatches(
        _ matches: [MarinaNLQCandidateMatch],
        preferExpenseOverMerchant: Bool
    ) -> [MarinaNLQCandidateMatch] {
        guard matches.count > 1 else { return matches }

        let groupedByNormalizedDisplay = Dictionary(grouping: matches, by: {
            normalizeDisplay($0.displayValue)
        })
        var collapsed: [MarinaNLQCandidateMatch] = []

        for bucket in groupedByNormalizedDisplay.values {
            let hasMerchant = bucket.contains { $0.entityType == .merchant }
            let hasExpense = bucket.contains { $0.entityType == .expense }
            if hasMerchant, hasExpense {
                collapsed.append(contentsOf: bucket.filter {
                    preferExpenseOverMerchant
                        ? $0.entityType != .merchant
                        : $0.entityType != .expense
                })
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

    private func relationship(from targetType: MarinaNLQTargetType) -> MarinaRelationshipField {
        switch targetType {
        case .category:
            return .category
        case .merchant:
            return .merchant
        case .expense:
            return .transaction
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

    private func mentionRole(from role: MarinaResolvedTargetRole) -> MarinaEntityMentionRole {
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

    private func entityTypeHint(from relationship: MarinaRelationshipField) -> MarinaCandidateEntityTypeHint? {
        switch relationship {
        case .category, .uncategorized:
            return .category
        case .merchant:
            return .merchant
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
        case .transaction:
            return .transaction
        case .workspace:
            return .workspace
        case .unknown:
            return nil
        }
    }

    private func singleAllowedTypeHint(from filter: MarinaFilter) -> MarinaCandidateEntityTypeHint? {
        guard filter.allowedEntityTypeHints?.count == 1 else { return nil }
        return filter.allowedEntityTypeHints?.first
    }

    private func allowedTypeHints(from filter: MarinaFilter) -> [MarinaCandidateEntityTypeHint]? {
        if filter.allowedEntityTypeHints?.isEmpty == false {
            return filter.allowedEntityTypeHints
        }
        if let explicit = filter.entityTypeHint {
            return [explicit]
        }
        return entityTypeHint(from: filter.relationship).map { [$0] }
    }

    private func isUncategorizedFilter(_ filter: MarinaFilter) -> Bool {
        filter.relationship == .uncategorized
            || filter.value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare("uncategorized") == .orderedSame
    }
}
