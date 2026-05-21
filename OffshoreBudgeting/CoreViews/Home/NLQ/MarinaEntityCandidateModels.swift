import Foundation

enum MarinaEntityCandidateMatchType: String, Equatable {
    case exact
    case prefix
}

enum MarinaEntityCandidateTargetType: String, Equatable, CaseIterable {
    case category
    case merchant
    case expense
    case card
    case budget
    case preset
    case incomeSource
    case allocationAccount
    case savingsAccount
}

struct MarinaEntityCandidateMatch: Equatable {
    let entityType: MarinaEntityCandidateTargetType
    let displayValue: String
    let normalizedValue: String
    let matchType: MarinaEntityCandidateMatchType
    let sourceID: UUID
    let clarificationSubtitle: String?

    init(
        entityType: MarinaEntityCandidateTargetType,
        displayValue: String,
        normalizedValue: String,
        matchType: MarinaEntityCandidateMatchType,
        sourceID: UUID,
        clarificationSubtitle: String? = nil
    ) {
        self.entityType = entityType
        self.displayValue = displayValue
        self.normalizedValue = normalizedValue
        self.matchType = matchType
        self.sourceID = sourceID
        self.clarificationSubtitle = clarificationSubtitle
    }
}

struct MarinaEntityTargetExtractionResult: Equatable {
    let rawTargetText: String?
    let matchesByType: [MarinaEntityCandidateTargetType: [MarinaEntityCandidateMatch]]

    var hasAnyMatches: Bool {
        matchesByType.values.contains(where: { $0.isEmpty == false })
    }
}
