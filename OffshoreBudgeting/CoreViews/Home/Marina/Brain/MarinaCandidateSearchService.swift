import Foundation

nonisolated struct MarinaCandidateSearchRequest {
    let rawTargetText: String
    let semanticRequest: MarinaSemanticRequest
    let snapshot: MarinaWorkspaceSnapshot
    let dateRange: HomeQueryDateRange?

    init(
        rawTargetText: String,
        semanticRequest: MarinaSemanticRequest,
        snapshot: MarinaWorkspaceSnapshot,
        dateRange: HomeQueryDateRange? = nil
    ) {
        self.rawTargetText = rawTargetText
        self.semanticRequest = semanticRequest
        self.snapshot = snapshot
        self.dateRange = dateRange
    }
}

nonisolated struct MarinaCandidateSearchResult {
    let matches: [MarinaCandidateMatch]
    let ambiguityStatus: MarinaCandidateAmbiguityStatus
    let recommendedMatch: MarinaCandidateMatch?
}

nonisolated struct MarinaCandidateMatch: Equatable, Sendable {
    let entity: MarinaSemanticEntity
    let fieldName: String
    let displayName: String
    let sourceID: String?
    let normalizedMatchedText: String
    let matchStrength: MarinaCandidateMatchStrength
    let occurrenceCount: Int
    let sampleDescriptions: [String]
    let semanticHintFit: MarinaCandidateSemanticHintFit
    let evidence: MarinaCandidateEvidence

    var isStrongEnoughForAutomaticResolution: Bool {
        matchStrength.isExactEquivalent && semanticHintFit != .conflicting
    }

    var isStrongEnoughForAutomaticRecommendation: Bool {
        matchStrength.isExactEquivalent && semanticHintFit != .conflicting
    }
}

nonisolated enum MarinaCandidateEvidence: Int, Comparable, Equatable, Sendable {
    case liveRecord
    case assistantAlias
    case importMerchantRule

    static func < (lhs: MarinaCandidateEvidence, rhs: MarinaCandidateEvidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

nonisolated enum MarinaCandidateMatchStrength: Int, Comparable, Equatable, Sendable {
    case exact = 0
    case normalizedExact = 1
    case prefix = 2
    case contains = 3
    case tokenOverlap = 4

    static func < (lhs: MarinaCandidateMatchStrength, rhs: MarinaCandidateMatchStrength) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var isUsefulForAutomaticResolution: Bool {
        self != .tokenOverlap
    }

    var isExactEquivalent: Bool {
        self == .exact || self == .normalizedExact
    }
}

nonisolated enum MarinaCandidateSemanticHintFit: Int, Comparable, Equatable, Sendable {
    case strong = 0
    case compatible = 1
    case neutral = 2
    case conflicting = 3

    static func < (lhs: MarinaCandidateSemanticHintFit, rhs: MarinaCandidateSemanticHintFit) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

nonisolated enum MarinaCandidateAmbiguityStatus: Equatable, Sendable {
    case noUsefulCandidate
    case weakOnly
    case obvious
    case ambiguous
}

nonisolated struct MarinaCandidateMatchTrace: Equatable, Sendable {
    let entity: MarinaSemanticEntity
    let fieldName: String
    let displayName: String
    let matchStrength: MarinaCandidateMatchStrength
    let occurrenceCount: Int
    let semanticHintFit: MarinaCandidateSemanticHintFit

    init(match: MarinaCandidateMatch) {
        entity = match.entity
        fieldName = match.fieldName
        displayName = match.displayName
        matchStrength = match.matchStrength
        occurrenceCount = match.occurrenceCount
        semanticHintFit = match.semanticHintFit
    }

    var debugDescription: String {
        "\(entity.rawValue).\(fieldName)=\(displayName) strength=\(matchStrength) hint=\(semanticHintFit) count=\(occurrenceCount)"
    }
}

nonisolated struct MarinaCandidateSearchTrace: Equatable, Sendable {
    let rawTargetText: String
    let slot: String
    let ambiguityStatus: MarinaCandidateAmbiguityStatus
    let recommendedDisplayName: String?
    let matches: [MarinaCandidateMatchTrace]

    init(
        rawTargetText: String,
        slot: String,
        result: MarinaCandidateSearchResult
    ) {
        self.rawTargetText = rawTargetText
        self.slot = slot
        ambiguityStatus = result.ambiguityStatus
        recommendedDisplayName = result.recommendedMatch?.displayName
        matches = result.matches.map(MarinaCandidateMatchTrace.init(match:))
    }

    var debugDescription: String {
        let matchSummary = matches.map(\.debugDescription).joined(separator: "; ")
        return "\(slot): \(rawTargetText) status=\(ambiguityStatus) recommended=\(recommendedDisplayName ?? "none") matches=[\(matchSummary)]"
    }
}

struct MarinaCandidateSearchService {
    private struct SearchRecord {
        let entity: MarinaSemanticEntity
        let fieldName: String
        let displayName: String
        let sourceID: String?
        let searchTexts: [String]
        let sampleDescriptions: [String]
        let occurrenceCount: Int
        let evidence: MarinaCandidateEvidence

        init(
            entity: MarinaSemanticEntity,
            fieldName: String,
            displayName: String,
            sourceID: String?,
            searchTexts: [String],
            sampleDescriptions: [String],
            occurrenceCount: Int,
            evidence: MarinaCandidateEvidence = .liveRecord
        ) {
            self.entity = entity
            self.fieldName = fieldName
            self.displayName = displayName
            self.sourceID = sourceID
            self.searchTexts = searchTexts
            self.sampleDescriptions = sampleDescriptions
            self.occurrenceCount = occurrenceCount
            self.evidence = evidence
        }
    }

    func search(_ request: MarinaCandidateSearchRequest) -> MarinaCandidateSearchResult {
        let target = request.rawTargetText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard target.isEmpty == false else {
            return MarinaCandidateSearchResult(
                matches: [],
                ambiguityStatus: .noUsefulCandidate,
                recommendedMatch: nil
            )
        }

        let matches = deduplicated(
            records(
                from: request.snapshot,
                semanticRequest: request.semanticRequest,
                dateRange: request.dateRange
            )
            .compactMap { match(record: $0, target: target, semanticRequest: request.semanticRequest) }
        )
            .sorted(by: isBetterMatch)

        let choiceMatches = matches.filter(\.isStrongEnoughForAutomaticResolution)
        let suggestionMatches = matches.filter {
            $0.semanticHintFit != .conflicting && $0.matchStrength.isExactEquivalent == false
        }
        let recommendationMatches = matches.filter(\.isStrongEnoughForAutomaticRecommendation)
        let recommended = recommendedMatch(from: recommendationMatches)
        let ambiguityStatus: MarinaCandidateAmbiguityStatus
        if matches.isEmpty {
            ambiguityStatus = .noUsefulCandidate
        } else if recommended != nil {
            ambiguityStatus = .obvious
        } else if choiceMatches.count > 1 || (choiceMatches.isEmpty && suggestionMatches.count > 1) {
            ambiguityStatus = .ambiguous
        } else {
            ambiguityStatus = .weakOnly
        }

        return MarinaCandidateSearchResult(
            matches: matches,
            ambiguityStatus: ambiguityStatus,
            recommendedMatch: recommended
        )
    }

    private func match(
        record: SearchRecord,
        target: String,
        semanticRequest: MarinaSemanticRequest
    ) -> MarinaCandidateMatch? {
        let rankedSearchTexts = record.searchTexts.compactMap { searchText -> (String, MarinaCandidateMatchStrength)? in
            matchStrength(candidate: searchText, target: target).map { (searchText, $0) }
        }
        .sorted {
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            return $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending
        }
        guard let matchedSearchText = rankedSearchTexts.first else {
            return nil
        }

        return MarinaCandidateMatch(
            entity: record.entity,
            fieldName: record.fieldName,
            displayName: record.displayName,
            sourceID: record.sourceID,
            normalizedMatchedText: MarinaCanonicalTextNormalizer.canonical(matchedSearchText.0),
            matchStrength: matchedSearchText.1,
            occurrenceCount: record.occurrenceCount,
            sampleDescriptions: Array(record.sampleDescriptions.filter { $0.isEmpty == false }.prefix(3)),
            semanticHintFit: semanticHintFit(for: record.entity, fieldName: record.fieldName, request: semanticRequest),
            evidence: record.evidence
        )
    }

    private func recommendedMatch(from matches: [MarinaCandidateMatch]) -> MarinaCandidateMatch? {
        let exactMatches = matches.filter { $0.matchStrength.isExactEquivalent }
        let aliasMatches = exactMatches.filter { $0.evidence == .assistantAlias }
        let candidates = aliasMatches.isEmpty ? exactMatches : aliasMatches
        guard let bestHint = candidates.map(\.semanticHintFit).min() else { return nil }
        let finalists = candidates.filter { $0.semanticHintFit == bestHint }
        return finalists.count == 1 ? finalists[0] : nil
    }

    private func records(
        from snapshot: MarinaWorkspaceSnapshot,
        semanticRequest: MarinaSemanticRequest,
        dateRange: HomeQueryDateRange?
    ) -> [SearchRecord] {
        var records: [SearchRecord] = []

        records.append(
            SearchRecord(
                entity: .workspace,
                fieldName: "name",
                displayName: snapshot.workspace.name,
                sourceID: snapshot.workspace.id.uuidString,
                searchTexts: [snapshot.workspace.name],
                sampleDescriptions: [snapshot.workspace.name],
                occurrenceCount: 1
            )
        )

        records.append(contentsOf: snapshot.cards.map {
            SearchRecord(
                entity: .card,
                fieldName: "name",
                displayName: $0.name,
                sourceID: $0.id.uuidString,
                searchTexts: [$0.name],
                sampleDescriptions: [$0.name],
                occurrenceCount: 1
            )
        })

        records.append(contentsOf: snapshot.categories.map {
            SearchRecord(
                entity: .category,
                fieldName: "name",
                displayName: $0.name,
                sourceID: $0.id.uuidString,
                searchTexts: [$0.name],
                sampleDescriptions: [$0.name],
                occurrenceCount: 1
            )
        })

        records.append(contentsOf: snapshot.presets.map {
            SearchRecord(
                entity: .preset,
                fieldName: "title",
                displayName: $0.title,
                sourceID: $0.id.uuidString,
                searchTexts: [$0.title],
                sampleDescriptions: [$0.title],
                occurrenceCount: 1
            )
        })

        records.append(contentsOf: incomeSourceRecords(from: snapshot))
        records.append(contentsOf: snapshot.incomeSeries.map {
            SearchRecord(
                entity: .incomeSeries,
                fieldName: "source",
                displayName: $0.source,
                sourceID: $0.id.uuidString,
                searchTexts: [$0.source],
                sampleDescriptions: [$0.source],
                occurrenceCount: 1
            )
        })

        records.append(contentsOf: snapshot.savingsAccounts.map {
            SearchRecord(
                entity: .savingsAccount,
                fieldName: "name",
                displayName: $0.name,
                sourceID: $0.id.uuidString,
                searchTexts: [$0.name],
                sampleDescriptions: [$0.name],
                occurrenceCount: 1
            )
        })

        records.append(contentsOf: snapshot.reconciliationAccounts.map {
            SearchRecord(
                entity: .reconciliationAccount,
                fieldName: "name",
                displayName: $0.name,
                sourceID: $0.id.uuidString,
                searchTexts: [$0.name],
                sampleDescriptions: [$0.name],
                occurrenceCount: 1
            )
        })

        records.append(contentsOf: snapshot.budgets.map {
            SearchRecord(
                entity: .budget,
                fieldName: "name",
                displayName: $0.name,
                sourceID: $0.id.uuidString,
                searchTexts: [$0.name],
                sampleDescriptions: [$0.name],
                occurrenceCount: 1
            )
        })

        let expenseEvidence = scopedExpenseEvidence(
            from: snapshot,
            request: semanticRequest,
            dateRange: dateRange
        )
        let variableExpenseTextRecords = expenseTextRecords(
            entity: .variableExpense,
            fieldName: "merchantText",
            rows: expenseEvidence.variable.map { ($0.id, $0.descriptionText) }
        )
        records.append(contentsOf: variableExpenseTextRecords)

        let plannedExpenseTextRecords = expenseTextRecords(
            entity: .plannedExpense,
            fieldName: "title",
            rows: expenseEvidence.planned.map { ($0.id, $0.title) }
        )
        records.append(contentsOf: plannedExpenseTextRecords)
        records.append(contentsOf: importMerchantRuleRecords(
            from: snapshot,
            variableExpenses: expenseEvidence.variable,
            plannedExpenses: expenseEvidence.planned
        ))
        records.append(contentsOf: assistantAliasRecords(
            from: snapshot,
            expenseTextRecords: variableExpenseTextRecords + plannedExpenseTextRecords
        ))

        return records
    }

    private func scopedExpenseEvidence(
        from snapshot: MarinaWorkspaceSnapshot,
        request: MarinaSemanticRequest,
        dateRange: HomeQueryDateRange?
    ) -> (variable: [VariableExpense], planned: [PlannedExpense]) {
        var variable = snapshot.homeCalculationVariableExpenses
        var planned = snapshot.homeCalculationPlannedExpenses

        if case let .budget(budgetID)? = request.resolvedScope,
           let budget = snapshot.budgets.first(where: { $0.id == budgetID }) {
            let linkedCardIDs = Set((budget.cardLinks ?? []).compactMap { link -> UUID? in
                guard link.budget?.id == budgetID,
                      link.budget?.workspace?.id == snapshot.workspace.id,
                      link.card?.workspace?.id == snapshot.workspace.id else {
                    return nil
                }
                return link.card?.id
            })
            variable = variable.filter {
                guard let cardID = $0.card?.id, linkedCardIDs.contains(cardID) else { return false }
                return $0.transactionDate >= budget.startDate && $0.transactionDate <= budget.endDate
            }
            planned = planned.filter {
                guard $0.sourceBudgetID == budgetID,
                      let cardID = $0.card?.id,
                      linkedCardIDs.contains(cardID) else {
                    return false
                }
                return $0.expenseDate >= budget.startDate && $0.expenseDate <= budget.endDate
            }
        }

        if let dateRange {
            variable = variable.filter {
                $0.transactionDate >= dateRange.startDate && $0.transactionDate <= dateRange.endDate
            }
            planned = planned.filter {
                $0.expenseDate >= dateRange.startDate && $0.expenseDate <= dateRange.endDate
            }
        }

        return (variable, planned)
    }

    private func incomeSourceRecords(from snapshot: MarinaWorkspaceSnapshot) -> [SearchRecord] {
        let sources = snapshot.incomes.map(\.source)
        let grouped = Dictionary(grouping: sources) { MarinaCanonicalTextNormalizer.canonical($0) }
        return grouped.values.compactMap { groupedSources in
            guard let first = groupedSources.first,
                  first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return nil
            }
            let samples = groupedSources.filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            return SearchRecord(
                entity: .income,
                fieldName: "source",
                displayName: first,
                sourceID: nil,
                searchTexts: Array(Set(samples)),
                sampleDescriptions: samples,
                occurrenceCount: groupedSources.count
            )
        }
    }

    private func expenseTextRecords(
        entity: MarinaSemanticEntity,
        fieldName: String,
        rows: [(UUID, String)]
    ) -> [SearchRecord] {
        let grouped = Dictionary(grouping: rows) { MarinaCanonicalTextNormalizer.canonical($0.1) }
        return grouped.values.compactMap { groupedRows in
            guard let first = groupedRows.first,
                  first.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return nil
            }
            let samples = groupedRows
                .map { $0.1 }
                .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            return SearchRecord(
                entity: entity,
                fieldName: fieldName,
                displayName: first.1,
                sourceID: first.0.uuidString,
                searchTexts: Array(Set(samples)),
                sampleDescriptions: samples,
                occurrenceCount: groupedRows.count
            )
        }
    }

    private func importMerchantRuleRecords(
        from snapshot: MarinaWorkspaceSnapshot,
        variableExpenses: [VariableExpense],
        plannedExpenses: [PlannedExpense]
    ) -> [SearchRecord] {
        let variableRows = variableExpenses.map { $0.descriptionText }
        let plannedRows = plannedExpenses.map { $0.title }

        return snapshot.importMerchantRules.compactMap { rule in
            let merchantKey = rule.merchantKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard merchantKey.isEmpty == false else { return nil }

            let samples = (variableRows + plannedRows).filter {
                MerchantNormalizer.normalizeKey($0) == merchantKey
            }
            let preferredName = rule.preferredName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = preferredName.flatMap { $0.isEmpty ? nil : $0 }
                ?? samples.first
                ?? MerchantNormalizer.displayName(merchantKey)
            guard displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return nil
            }

            return SearchRecord(
                entity: .variableExpense,
                fieldName: "merchantText",
                displayName: displayName,
                sourceID: nil,
                searchTexts: Array(Set([merchantKey, preferredName, displayName].compactMap { $0 })),
                sampleDescriptions: samples,
                occurrenceCount: samples.count,
                evidence: .importMerchantRule
            )
        }
    }

    private func assistantAliasRecords(
        from snapshot: MarinaWorkspaceSnapshot,
        expenseTextRecords: [SearchRecord]
    ) -> [SearchRecord] {
        snapshot.assistantAliasRules.flatMap { rule -> [SearchRecord] in
            let aliasKey = rule.aliasKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let targetValue = rule.targetValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard aliasKey.isEmpty == false, targetValue.isEmpty == false else { return [] }

            switch rule.entityType {
            case .card:
                return namedAliasRecords(
                    aliasKey: aliasKey,
                    targetValue: targetValue,
                    values: snapshot.cards,
                    entity: .card,
                    fieldName: "name",
                    name: \Card.name,
                    id: \Card.id
                )
            case .category:
                return namedAliasRecords(
                    aliasKey: aliasKey,
                    targetValue: targetValue,
                    values: snapshot.categories,
                    entity: .category,
                    fieldName: "name",
                    name: \Category.name,
                    id: \Category.id
                )
            case .incomeSource:
                return incomeSourceRecords(from: snapshot)
                    .filter { MarinaCanonicalTextNormalizer.areStronglyEquivalent($0.displayName, targetValue) }
                    .map { aliasRecord(aliasKey: aliasKey, target: $0) }
            case .merchant:
                let targets = expenseTextRecords.filter {
                    MarinaCanonicalTextNormalizer.areStronglyEquivalent($0.displayName, targetValue)
                }
                guard let first = targets.first else { return [] }
                let samples = Array(Set(targets.flatMap(\.sampleDescriptions)))
                    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                return [
                    SearchRecord(
                        entity: .variableExpense,
                        fieldName: "merchantText",
                        displayName: first.displayName,
                        sourceID: nil,
                        searchTexts: [aliasKey],
                        sampleDescriptions: Array(samples.prefix(3)),
                        occurrenceCount: targets.reduce(0) { $0 + $1.occurrenceCount },
                        evidence: .assistantAlias
                    )
                ]
            case .budget:
                return namedAliasRecords(
                    aliasKey: aliasKey,
                    targetValue: targetValue,
                    values: snapshot.budgets,
                    entity: .budget,
                    fieldName: "name",
                    name: \Budget.name,
                    id: \Budget.id
                )
            case .preset:
                return namedAliasRecords(
                    aliasKey: aliasKey,
                    targetValue: targetValue,
                    values: snapshot.presets,
                    entity: .preset,
                    fieldName: "title",
                    name: \Preset.title,
                    id: \Preset.id
                )
            }
        }
    }

    private func namedAliasRecords<Value>(
        aliasKey: String,
        targetValue: String,
        values: [Value],
        entity: MarinaSemanticEntity,
        fieldName: String,
        name: KeyPath<Value, String>,
        id: KeyPath<Value, UUID>
    ) -> [SearchRecord] {
        values
            .filter { MarinaCanonicalTextNormalizer.areStronglyEquivalent($0[keyPath: name], targetValue) }
            .map {
                SearchRecord(
                    entity: entity,
                    fieldName: fieldName,
                    displayName: $0[keyPath: name],
                    sourceID: $0[keyPath: id].uuidString,
                    searchTexts: [aliasKey],
                    sampleDescriptions: [$0[keyPath: name]],
                    occurrenceCount: 1,
                    evidence: .assistantAlias
                )
            }
    }

    private func aliasRecord(aliasKey: String, target: SearchRecord) -> SearchRecord {
        SearchRecord(
            entity: target.entity,
            fieldName: target.fieldName,
            displayName: target.displayName,
            sourceID: target.sourceID,
            searchTexts: [aliasKey],
            sampleDescriptions: target.sampleDescriptions,
            occurrenceCount: target.occurrenceCount,
            evidence: .assistantAlias
        )
    }

    private func semanticHintFit(
        for entity: MarinaSemanticEntity,
        fieldName: String,
        request: MarinaSemanticRequest
    ) -> MarinaCandidateSemanticHintFit {
        if stronglyHints(entity: entity, fieldName: fieldName, request: request) {
            return .strong
        }

        if explicitlyConflicts(entity: entity, request: request) {
            return .conflicting
        }

        if compatibleEntities(for: request).contains(entity) {
            return .compatible
        }

        return .neutral
    }

    private func stronglyHints(
        entity: MarinaSemanticEntity,
        fieldName: String,
        request: MarinaSemanticRequest
    ) -> Bool {
        switch entity {
        case .card:
            return request.entity == .card || request.dimensions.contains(.card)
        case .category:
            return request.entity == .category || request.dimensions.contains(.category)
        case .income:
            return request.entity == .income || request.dimensions.contains(.incomeSource)
        case .incomeSeries:
            return request.entity == .incomeSeries || request.dimensions.contains(.incomeSeries)
        case .preset:
            return request.entity == .preset || request.dimensions.contains(.preset)
        case .savingsAccount:
            return request.entity == .savingsAccount || request.dimensions.contains(.savingsAccount)
        case .reconciliationAccount:
            return request.entity == .reconciliationAccount || request.dimensions.contains(.reconciliationAccount)
        case .budget:
            return request.entity == .budget || request.dimensions.contains(.budget)
        case .variableExpense:
            return request.dimensions.contains(.merchantText)
        case .plannedExpense:
            return request.entity == .plannedExpense && fieldName == "title"
                || request.dimensions.contains(.merchantText)
        case .workspace:
            return request.entity == .workspace || request.dimensions.contains(.workspace)
        }
    }

    private func compatibleEntities(for request: MarinaSemanticRequest) -> Set<MarinaSemanticEntity> {
        switch request.entity {
        case .variableExpense, .plannedExpense:
            return [.variableExpense, .plannedExpense, .category, .card, .preset, .budget, .reconciliationAccount, .savingsAccount]
        case .card:
            return [.card, .variableExpense, .plannedExpense]
        case .category:
            return [.category, .variableExpense, .plannedExpense, .preset]
        case .income:
            return [.income]
        case .incomeSeries:
            return [.income, .incomeSeries]
        case .preset:
            return [.preset, .plannedExpense, .category, .card]
        case .reconciliationAccount:
            return [.reconciliationAccount, .category, .variableExpense, .plannedExpense]
        case .savingsAccount:
            return [.savingsAccount]
        case .budget:
            return [.budget]
        case .workspace:
            return []
        }
    }

    private func explicitlyConflicts(entity: MarinaSemanticEntity, request: MarinaSemanticRequest) -> Bool {
        if request.dimensions.contains(.card) { return entity != .card }
        if request.dimensions.contains(.category) { return entity != .category }
        if request.dimensions.contains(.incomeSource) { return entity != .income }
        if request.dimensions.contains(.preset) { return entity != .preset }
        if request.dimensions.contains(.savingsAccount) { return entity != .savingsAccount }
        if request.dimensions.contains(.reconciliationAccount) { return entity != .reconciliationAccount }
        if request.dimensions.contains(.budget) { return entity != .budget }
        return false
    }

    private func matchStrength(candidate: String, target: String) -> MarinaCandidateMatchStrength? {
        let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedCandidate.isEmpty == false, trimmedTarget.isEmpty == false else {
            return nil
        }

        if trimmedCandidate == trimmedTarget {
            return .exact
        }

        let candidate = MarinaCanonicalTextNormalizer.canonical(trimmedCandidate)
        let target = MarinaCanonicalTextNormalizer.canonical(trimmedTarget)
        guard candidate.isEmpty == false, target.isEmpty == false else {
            return nil
        }

        if candidate == target {
            return .normalizedExact
        }
        if MarinaCanonicalTextNormalizer.areStronglyEquivalent(trimmedCandidate, trimmedTarget) {
            return .normalizedExact
        }
        let candidateForms = MarinaCanonicalTextNormalizer.morphologyForms(trimmedCandidate)
        let targetForms = MarinaCanonicalTextNormalizer.morphologyForms(trimmedTarget)
        if morphologyPairs(candidateForms, targetForms).contains(where: { pair in
            pair.candidate.hasPrefix(pair.target)
        }) {
            return .prefix
        }
        if morphologyPairs(candidateForms, targetForms).contains(where: { pair in
            pair.candidate.contains(pair.target)
        }) {
            return .contains
        }
        if tokenOverlap(candidate: candidate, target: target) {
            return .tokenOverlap
        }
        return nil
    }

    private func morphologyPairs(
        _ candidates: Set<String>,
        _ targets: Set<String>
    ) -> [(candidate: String, target: String)] {
        candidates.flatMap { candidate in
            targets.compactMap { target in
                guard candidate.isEmpty == false, target.isEmpty == false else { return nil }
                return (candidate: candidate, target: target)
            }
        }
    }

    private func tokenOverlap(candidate: String, target: String) -> Bool {
        let candidateTokens = Set(tokens(from: candidate))
        let targetTokens = Set(tokens(from: target))
        guard candidateTokens.isEmpty == false, targetTokens.isEmpty == false else {
            return false
        }
        return candidateTokens.isDisjoint(with: targetTokens) == false
    }

    private func tokens(from value: String) -> [String] {
        MarinaCanonicalTextNormalizer.canonical(value)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 2 }
    }

    private func deduplicated(_ matches: [MarinaCandidateMatch]) -> [MarinaCandidateMatch] {
        var byMeaning: [String: MarinaCandidateMatch] = [:]
        for match in matches {
            let key = meaningKey(for: match)
            guard let existing = byMeaning[key] else {
                byMeaning[key] = match
                continue
            }

            let preferred = isBetterMatch(match, existing) ? match : existing
            let other = preferred == match ? existing : match
            let samples = Array(Set(preferred.sampleDescriptions + other.sampleDescriptions))
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            let combinedOccurrenceCount: Int
            if (preferred.entity == .variableExpense || preferred.entity == .plannedExpense),
               (other.entity == .variableExpense || other.entity == .plannedExpense),
               preferred.entity != other.entity {
                combinedOccurrenceCount = preferred.occurrenceCount + other.occurrenceCount
            } else {
                combinedOccurrenceCount = max(preferred.occurrenceCount, other.occurrenceCount)
            }
            byMeaning[key] = MarinaCandidateMatch(
                entity: preferred.entity,
                fieldName: preferred.fieldName,
                displayName: preferred.displayName,
                sourceID: preferred.sourceID ?? other.sourceID,
                normalizedMatchedText: preferred.normalizedMatchedText,
                matchStrength: preferred.matchStrength,
                occurrenceCount: combinedOccurrenceCount,
                sampleDescriptions: Array(samples.prefix(3)),
                semanticHintFit: min(preferred.semanticHintFit, other.semanticHintFit),
                evidence: min(preferred.evidence, other.evidence)
            )
        }
        return Array(byMeaning.values)
    }

    private func meaningKey(for match: MarinaCandidateMatch) -> String {
        switch match.entity {
        case .card, .category, .preset, .savingsAccount, .reconciliationAccount, .budget, .workspace:
            return "\(match.entity.rawValue)|\(match.fieldName)|\(match.sourceID ?? MarinaCanonicalTextNormalizer.canonical(match.displayName))"
        case .variableExpense, .plannedExpense:
            return "expenseText|\(MarinaCanonicalTextNormalizer.canonical(match.displayName))"
        case .income, .incomeSeries:
            return "\(match.entity.rawValue)|\(match.fieldName)|\(MarinaCanonicalTextNormalizer.canonical(match.displayName))"
        }
    }

    private func isBetterMatch(_ left: MarinaCandidateMatch, _ right: MarinaCandidateMatch) -> Bool {
        if left.matchStrength != right.matchStrength {
            return left.matchStrength < right.matchStrength
        }
        if left.semanticHintFit != right.semanticHintFit {
            return left.semanticHintFit < right.semanticHintFit
        }
        if left.evidence != right.evidence {
            return left.evidence < right.evidence
        }
        if left.occurrenceCount != right.occurrenceCount {
            return left.occurrenceCount > right.occurrenceCount
        }
        if left.entity.rawValue != right.entity.rawValue {
            return left.entity.rawValue < right.entity.rawValue
        }
        let displayOrder = left.displayName.localizedCaseInsensitiveCompare(right.displayName)
        if displayOrder != .orderedSame {
            return displayOrder == .orderedAscending
        }
        return (left.sourceID ?? "") < (right.sourceID ?? "")
    }
}
