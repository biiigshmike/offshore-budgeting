import Foundation

nonisolated struct MarinaCandidateSearchRequest {
    let rawTargetText: String
    let semanticRequest: MarinaSemanticRequest
    let snapshot: MarinaWorkspaceSnapshot
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

    var isStrongEnoughForAutomaticResolution: Bool {
        matchStrength.isUsefulForAutomaticResolution && semanticHintFit != .conflicting
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
        let searchText: String
        let sampleDescriptions: [String]
        let occurrenceCount: Int
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

        let matches = records(from: request.snapshot)
            .compactMap { match(record: $0, target: target, semanticRequest: request.semanticRequest) }
            .sorted(by: isBetterMatch)

        let automaticMatches = matches.filter(\.isStrongEnoughForAutomaticResolution)
        let recommended = recommendedMatch(from: automaticMatches)
        let ambiguityStatus: MarinaCandidateAmbiguityStatus
        if matches.isEmpty {
            ambiguityStatus = .noUsefulCandidate
        } else if automaticMatches.isEmpty {
            ambiguityStatus = .weakOnly
        } else if recommended != nil {
            ambiguityStatus = .obvious
        } else {
            ambiguityStatus = .ambiguous
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
        guard let strength = matchStrength(candidate: record.searchText, target: target) else {
            return nil
        }

        return MarinaCandidateMatch(
            entity: record.entity,
            fieldName: record.fieldName,
            displayName: record.displayName,
            sourceID: record.sourceID,
            normalizedMatchedText: normalized(record.searchText),
            matchStrength: strength,
            occurrenceCount: record.occurrenceCount,
            sampleDescriptions: Array(record.sampleDescriptions.filter { $0.isEmpty == false }.prefix(3)),
            semanticHintFit: semanticHintFit(for: record.entity, fieldName: record.fieldName, request: semanticRequest)
        )
    }

    private func recommendedMatch(from matches: [MarinaCandidateMatch]) -> MarinaCandidateMatch? {
        guard let first = matches.first else { return nil }

        let entityTypes = Set(matches.map(\.entity))
        if first.semanticHintFit != .strong, entityTypes.count > 1 {
            return nil
        }

        let equallyStrong = matches.filter {
            $0.matchStrength == first.matchStrength
                && $0.semanticHintFit == first.semanticHintFit
        }

        if first.semanticHintFit == .strong {
            let sameEntity = equallyStrong.filter { $0.entity == first.entity }
            return sameEntity.count == 1 ? first : nil
        }

        return equallyStrong.count == 1 ? first : nil
    }

    private func records(from snapshot: MarinaWorkspaceSnapshot) -> [SearchRecord] {
        var records: [SearchRecord] = []

        records.append(contentsOf: snapshot.cards.map {
            SearchRecord(
                entity: .card,
                fieldName: "name",
                displayName: $0.name,
                sourceID: $0.id.uuidString,
                searchText: $0.name,
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
                searchText: $0.name,
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
                searchText: $0.title,
                sampleDescriptions: [$0.title],
                occurrenceCount: 1
            )
        })

        records.append(contentsOf: incomeSourceRecords(from: snapshot))

        records.append(contentsOf: snapshot.savingsAccounts.map {
            SearchRecord(
                entity: .savingsAccount,
                fieldName: "name",
                displayName: $0.name,
                sourceID: $0.id.uuidString,
                searchText: $0.name,
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
                searchText: $0.name,
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
                searchText: $0.name,
                sampleDescriptions: [$0.name],
                occurrenceCount: 1
            )
        })

        records.append(contentsOf: expenseTextRecords(
            entity: .variableExpense,
            fieldName: "merchantText",
            rows: snapshot.variableExpenses.map { ($0.id, $0.descriptionText) }
        ))

        records.append(contentsOf: expenseTextRecords(
            entity: .plannedExpense,
            fieldName: "title",
            rows: snapshot.plannedExpenses.map { ($0.id, $0.title) }
        ))

        return records
    }

    private func incomeSourceRecords(from snapshot: MarinaWorkspaceSnapshot) -> [SearchRecord] {
        let grouped = Dictionary(grouping: snapshot.incomes, by: { normalized($0.source) })
        return grouped.values.compactMap { incomes in
            guard let first = incomes.first else { return nil }
            let samples = incomes.map(\.source).filter { $0.isEmpty == false }
            return SearchRecord(
                entity: .income,
                fieldName: "source",
                displayName: first.source,
                sourceID: nil,
                searchText: first.source,
                sampleDescriptions: samples,
                occurrenceCount: incomes.count
            )
        }
    }

    private func expenseTextRecords(
        entity: MarinaSemanticEntity,
        fieldName: String,
        rows: [(UUID, String)]
    ) -> [SearchRecord] {
        let grouped = Dictionary(grouping: rows) { normalized($0.1) }
        return grouped.values.compactMap { groupedRows in
            guard let first = groupedRows.first else { return nil }
            let samples = groupedRows
                .map { $0.1 }
                .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            return SearchRecord(
                entity: entity,
                fieldName: fieldName,
                displayName: first.1,
                sourceID: first.0.uuidString,
                searchText: first.1,
                sampleDescriptions: samples,
                occurrenceCount: groupedRows.count
            )
        }
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

        let candidate = normalized(trimmedCandidate)
        let target = normalized(trimmedTarget)
        guard candidate.isEmpty == false, target.isEmpty == false else {
            return nil
        }

        if candidate == target {
            return .normalizedExact
        }
        if candidate.hasPrefix(target) {
            return .prefix
        }
        if candidate.contains(target) {
            return .contains
        }
        if tokenOverlap(candidate: candidate, target: target) {
            return .tokenOverlap
        }
        return nil
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
        normalized(value)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 2 }
    }

    private func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "’", with: "'")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "[^A-Za-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
            .split(separator: " ")
            .map { singularized($0) }
            .joined(separator: " ")
    }

    private func singularized(_ word: Substring) -> String {
        var value = String(word)
        if value.hasSuffix("ies"), value.count > 3 {
            value.removeLast(3)
            return value + "y"
        }
        if value.hasSuffix("ses") == false,
           value.hasSuffix("s"),
           value.count > 1 {
            value.removeLast()
        }
        return value
    }

    private func isBetterMatch(_ left: MarinaCandidateMatch, _ right: MarinaCandidateMatch) -> Bool {
        if left.matchStrength != right.matchStrength {
            return left.matchStrength < right.matchStrength
        }
        if left.semanticHintFit != right.semanticHintFit {
            return left.semanticHintFit < right.semanticHintFit
        }
        if left.occurrenceCount != right.occurrenceCount {
            return left.occurrenceCount > right.occurrenceCount
        }
        if left.entity.rawValue != right.entity.rawValue {
            return left.entity.rawValue < right.entity.rawValue
        }
        return left.displayName.localizedCaseInsensitiveCompare(right.displayName) == .orderedAscending
    }
}
