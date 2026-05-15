import Foundation

struct MarinaSemanticQuery: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let subject: MarinaSubject
    let operation: MarinaOperation
    let filters: [MarinaFilter]
    let amountField: MarinaAmountField?
    let dateRange: MarinaDateRangeRequest?
    let comparisonDateRange: MarinaDateRangeRequest?
    let grouping: MarinaGrouping?
    let ranking: MarinaRanking?
    let limit: Int?
    let averageBasis: MarinaAverageBasis?
    let responseShape: MarinaResponseShape?

    init(
        id: UUID = UUID(),
        subject: MarinaSubject,
        operation: MarinaOperation,
        filters: [MarinaFilter] = [],
        amountField: MarinaAmountField? = nil,
        dateRange: MarinaDateRangeRequest? = nil,
        comparisonDateRange: MarinaDateRangeRequest? = nil,
        grouping: MarinaGrouping? = nil,
        ranking: MarinaRanking? = nil,
        limit: Int? = nil,
        averageBasis: MarinaAverageBasis? = nil,
        responseShape: MarinaResponseShape? = nil
    ) {
        self.id = id
        self.subject = subject
        self.operation = operation
        self.filters = filters
        self.amountField = amountField
        self.dateRange = dateRange
        self.comparisonDateRange = comparisonDateRange
        self.grouping = grouping
        self.ranking = ranking
        self.limit = limit
        self.averageBasis = averageBasis
        self.responseShape = responseShape
    }
}

enum MarinaInterpretationResult: Codable, Equatable, Sendable {
    case query(MarinaSemanticQuery)
    case clarification(MarinaTypedClarification)
    case unsupported(MarinaTypedUnsupportedResponse)
}

enum MarinaSubject: String, Codable, Equatable, CaseIterable, Sendable {
    case variableExpenses
    case plannedExpenses
    case income
    case budgets
    case cards
    case categories
    case presets
    case savingsAccounts
    case savingsLedgerEntries
    case reconciliationAccounts
    case reconciliationItems
    case workspaces
    case merchant
    case incomeSource
    case uncategorizedExpenses
}

enum MarinaOperation: String, Codable, Equatable, CaseIterable, Sendable {
    case sum
    case average
    case count
    case minimum
    case maximum
    case median
    case list
    case compare
    case rank
    case breakdown
    case percentageShare
    case lookupDetails
    case forecast
    case simulate
}

enum MarinaAverageBasis: String, Codable, Equatable, CaseIterable, Sendable {
    case perTransaction
    case perDay
    case perWeek
    case perMonth
    case perBudgetPeriod
}

enum MarinaAmountField: String, Codable, Equatable, CaseIterable, Sendable {
    case amount
    case plannedAmount
    case actualAmount
    case effectivePlannedAmount
    case spendingAmount
    case ledgerSignedAmount
    case budgetImpactAmount
    case incomeAmount
    case savingsAmount
    case allocatedAmount
    case reconciliationBalance
}

enum MarinaDateField: String, Codable, Equatable, CaseIterable, Sendable {
    case transactionDate
    case expenseDate
    case date
    case startDate
    case endDate
    case createdAt
    case updatedAt
    case periodRange
}

struct MarinaDateRangeRequest: Codable, Equatable, Sendable {
    let role: MarinaTimeScopeRole
    let rawText: String?
    let resolvedRange: HomeQueryDateRange?
    let periodUnit: HomeQueryPeriodUnit?

    init(
        role: MarinaTimeScopeRole,
        rawText: String? = nil,
        resolvedRange: HomeQueryDateRange? = nil,
        periodUnit: HomeQueryPeriodUnit? = nil
    ) {
        self.role = role
        self.rawText = rawText
        self.resolvedRange = resolvedRange
        self.periodUnit = periodUnit
    }
}

enum MarinaFilterMatchMode: String, Codable, Equatable, CaseIterable, Sendable {
    case exact
    case prefix
    case semanticOrAlias
    case unresolved
}

struct MarinaFilter: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let role: MarinaResolvedTargetRole
    let relationship: MarinaRelationshipField
    let value: String
    let matchMode: MarinaFilterMatchMode
    let entityTypeHint: MarinaCandidateEntityTypeHint?
    let sourceID: UUID?

    init(
        id: UUID = UUID(),
        role: MarinaResolvedTargetRole,
        relationship: MarinaRelationshipField,
        value: String,
        matchMode: MarinaFilterMatchMode = .semanticOrAlias,
        entityTypeHint: MarinaCandidateEntityTypeHint? = nil,
        sourceID: UUID? = nil
    ) {
        self.id = id
        self.role = role
        self.relationship = relationship
        self.value = value
        self.matchMode = matchMode
        self.entityTypeHint = entityTypeHint
        self.sourceID = sourceID
    }
}

enum MarinaRelationshipField: String, Codable, Equatable, CaseIterable, Sendable {
    case category
    case merchant
    case card
    case budget
    case preset
    case incomeSource
    case allocationAccount
    case savingsAccount
    case transaction
    case workspace
    case uncategorized
    case unknown
}

struct MarinaGrouping: Codable, Equatable, Sendable {
    let dimension: MarinaGroupingDimensionCandidate
    let rawText: String?
}

struct MarinaRanking: Codable, Equatable, Sendable {
    let direction: MarinaRankingDirectionCandidate
    let limit: Int?
    let rawText: String?
}

enum MarinaResponseShape: String, Codable, Equatable, CaseIterable, Sendable {
    case scalarCurrency
    case summaryCard
    case comparison
    case rankedList
    case groupedBreakdown
    case chartRows
    case clarification
    case unsupported
}

struct MarinaSemanticQueryAdapter {
    func interpretationResult(from candidate: MarinaQueryPlanCandidate) -> MarinaInterpretationResult {
        if let hint = candidate.unsupportedHint {
            return .unsupported(
                MarinaTypedUnsupportedResponse(
                    kind: unsupportedKind(from: hint),
                    message: "The interpreted query is not supported by Marina's safe query model.",
                    candidate: candidate
                )
            )
        }

        if let lookupRequest = candidate.databaseLookupRequest,
           candidate.operation == .lookupDetails || candidate.requestFamily == .databaseLookup {
            return .query(
                MarinaSemanticQuery(
                    subject: subject(from: lookupRequest.objectTypes.first ?? .unknown),
                    operation: .lookupDetails,
                    filters: lookupRequest.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [
                        MarinaFilter(
                            role: .primaryTarget,
                            relationship: relationship(from: lookupRequest.objectTypes.first ?? .unknown),
                            value: lookupRequest.searchText,
                            matchMode: .semanticOrAlias,
                            entityTypeHint: entityTypeHint(from: lookupRequest.objectTypes.first ?? .unknown),
                            sourceID: nil
                        )
                    ],
                    amountField: nil,
                    dateRange: lookupRequest.dateRange.map {
                        MarinaDateRangeRequest(role: .primary, rawText: nil, resolvedRange: $0, periodUnit: nil)
                    },
                    comparisonDateRange: nil,
                    grouping: nil,
                    ranking: nil,
                    limit: lookupRequest.limit,
                    averageBasis: nil,
                    responseShape: .summaryCard
                )
            )
        }

        guard let operation = candidate.operation,
              let measure = candidate.measure else {
            return .unsupported(
                MarinaTypedUnsupportedResponse(
                    kind: .unsupportedOperation,
                    message: "The interpreted query is missing an operation or measure.",
                    candidate: candidate
                )
            )
        }

        let semantic = MarinaSemanticQuery(
            subject: subject(from: measure, candidate: candidate),
            operation: semanticOperation(from: operation, measure: measure),
            filters: filters(from: candidate.entityMentions),
            amountField: amountField(from: measure),
            dateRange: dateRange(from: candidate.timeScopes, role: .primary)
                ?? dateRange(from: candidate.timeScopes, role: .lookbackWindow),
            comparisonDateRange: dateRange(from: candidate.timeScopes, role: .comparison),
            grouping: candidate.grouping.map { MarinaGrouping(dimension: $0.dimension, rawText: $0.rawText) },
            ranking: candidate.ranking.map { MarinaRanking(direction: $0.direction, limit: $0.limit, rawText: $0.rawText) },
            limit: candidate.limit,
            averageBasis: averageBasis(from: candidate.grouping),
            responseShape: candidate.responseShapeHint.flatMap(responseShape)
        )
        return .query(semantic)
    }

    func aggregationPlan(from semanticQuery: MarinaSemanticQuery) -> MarinaAggregationPlan {
        MarinaAggregationPlan(
            status: .notExecutableShell,
            operation: candidateOperation(from: semanticQuery.operation),
            measure: candidateMeasure(from: semanticQuery),
            targets: semanticQuery.filters.map(aggregationTarget),
            dateRange: semanticQuery.dateRange?.resolvedRange,
            comparisonDateRange: semanticQuery.comparisonDateRange?.resolvedRange,
            grouping: semanticQuery.grouping.map { MarinaGroupingCandidate(dimension: $0.dimension, rawText: $0.rawText) },
            ranking: semanticQuery.ranking.map { MarinaRankingCandidate(direction: $0.direction, limit: $0.limit, rawText: $0.rawText) },
            limit: semanticQuery.limit,
            responseShape: semanticQuery.responseShape.flatMap(responseShapeHint)
        )
    }

    private func subject(from measure: MarinaCandidateMeasure, candidate: MarinaQueryPlanCandidate) -> MarinaSubject {
        if let dataset = candidate.semanticCommand?.datasets.first {
            switch dataset {
            case .variableExpenses:
                return .variableExpenses
            case .plannedExpenses:
                return .plannedExpenses
            case .income:
                return .income
            case .incomeSeries:
                return .incomeSource
            case .cards:
                return .cards
            case .categories:
                return .categories
            case .presets:
                return .presets
            case .budgets:
                return .budgets
            case .savingsLedger:
                return .savingsLedgerEntries
            case .reconciliation, .expenseAllocations:
                return .reconciliationAccounts
            case .importMerchantRules:
                return .merchant
            case .assistantAliasRules:
                return .workspaces
            }
        }

        switch measure {
        case .spend, .categoryShare, .transactionAmount, .transactionFrequency:
            return .variableExpenses
        case .income:
            return .income
        case .savings, .savingsMovement:
            return .savingsLedgerEntries
        case .remainingBudget:
            return .budgets
        case .reconciliationBalance:
            return .reconciliationAccounts
        case .presetAmount:
            return .plannedExpenses
        }
    }

    private func subject(from lookupObjectType: MarinaLookupObjectType) -> MarinaSubject {
        switch lookupObjectType {
        case .budget:
            return .budgets
        case .income, .incomeSeries:
            return .income
        case .variableExpense:
            return .variableExpenses
        case .plannedExpense:
            return .plannedExpenses
        case .category:
            return .categories
        case .preset:
            return .presets
        case .card:
            return .cards
        case .savingsAccount:
            return .savingsAccounts
        case .savingsLedgerEntry:
            return .savingsLedgerEntries
        case .reconciliationAccount:
            return .reconciliationAccounts
        case .reconciliationItem, .expenseAllocation:
            return .reconciliationItems
        case .importMerchantRule:
            return .merchant
        case .assistantAliasRule, .workspace, .unknown:
            return .workspaces
        }
    }

    private func semanticOperation(
        from operation: MarinaCandidateOperation,
        measure: MarinaCandidateMeasure
    ) -> MarinaOperation {
        switch operation {
        case .sum:
            return measure == .categoryShare ? .percentageShare : .sum
        case .average:
            return .average
        case .count:
            return .count
        case .minimum:
            return .minimum
        case .maximum:
            return .maximum
        case .rank:
            return .rank
        case .compare:
            return .compare
        case .trend:
            return .breakdown
        case .forecast:
            return .forecast
        case .simulate:
            return .simulate
        case .listRows:
            return .list
        case .lookupDetails:
            return .lookupDetails
        }
    }

    private func candidateOperation(from operation: MarinaOperation) -> MarinaCandidateOperation {
        switch operation {
        case .sum, .percentageShare, .breakdown:
            return .sum
        case .average:
            return .average
        case .count:
            return .count
        case .minimum:
            return .minimum
        case .maximum:
            return .maximum
        case .median:
            return .average
        case .list:
            return .listRows
        case .compare:
            return .compare
        case .rank:
            return .rank
        case .lookupDetails:
            return .lookupDetails
        case .forecast:
            return .forecast
        case .simulate:
            return .simulate
        }
    }

    private func candidateMeasure(from semanticQuery: MarinaSemanticQuery) -> MarinaCandidateMeasure {
        if semanticQuery.operation == .percentageShare {
            return .categoryShare
        }

        switch semanticQuery.amountField {
        case .incomeAmount:
            return .income
        case .savingsAmount:
            if semanticQuery.subject == .savingsLedgerEntries,
               semanticQuery.operation == .rank {
                return .savingsMovement
            }
            return .savings
        case .allocatedAmount, .reconciliationBalance:
            return .reconciliationBalance
        case .plannedAmount, .actualAmount, .effectivePlannedAmount:
            return .presetAmount
        case .amount, .spendingAmount, .ledgerSignedAmount, .budgetImpactAmount:
            return semanticQuery.operation == .list ? .transactionAmount : .spend
        case nil:
            switch semanticQuery.subject {
            case .income, .incomeSource:
                return .income
            case .savingsAccounts, .savingsLedgerEntries:
                return .savings
            case .reconciliationAccounts, .reconciliationItems:
                return .reconciliationBalance
            case .plannedExpenses, .presets:
                return .presetAmount
            case .budgets:
                return .remainingBudget
            case .variableExpenses, .cards, .categories, .merchant, .uncategorizedExpenses, .workspaces:
                return semanticQuery.operation == .list ? .transactionAmount : .spend
            }
        }
    }

    private func filters(from mentions: [MarinaUnresolvedEntityMention]) -> [MarinaFilter] {
        mentions.compactMap { mention in
            guard let rawText = mention.rawText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  rawText.isEmpty == false else {
                return nil
            }
            return MarinaFilter(
                id: mention.id,
                role: resolvedRole(from: mention.role),
                relationship: relationship(from: mention.typeHint),
                value: rawText,
                matchMode: .semanticOrAlias,
                entityTypeHint: mention.typeHint,
                sourceID: nil
            )
        }
    }

    private func aggregationTarget(from filter: MarinaFilter) -> MarinaResolvedAggregationTarget {
        MarinaResolvedAggregationTarget(
            id: filter.id,
            role: filter.role,
            entityType: filter.entityTypeHint ?? entityTypeHint(from: filter.relationship),
            displayName: filter.value,
            sourceID: filter.sourceID
        )
    }

    private func relationship(from typeHint: MarinaCandidateEntityTypeHint?) -> MarinaRelationshipField {
        switch typeHint {
        case .category:
            return .category
        case .merchant:
            return .merchant
        case .expense, .transaction:
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
        case .workspace:
            return .workspace
        case nil:
            return .unknown
        }
    }

    private func relationship(from lookupObjectType: MarinaLookupObjectType) -> MarinaRelationshipField {
        switch lookupObjectType {
        case .budget:
            return .budget
        case .income, .incomeSeries:
            return .incomeSource
        case .variableExpense, .plannedExpense:
            return .transaction
        case .category:
            return .category
        case .preset:
            return .preset
        case .card:
            return .card
        case .savingsAccount, .savingsLedgerEntry:
            return .savingsAccount
        case .reconciliationAccount, .reconciliationItem, .expenseAllocation:
            return .allocationAccount
        case .importMerchantRule:
            return .merchant
        case .assistantAliasRule, .workspace:
            return .workspace
        case .unknown:
            return .unknown
        }
    }

    private func entityTypeHint(from lookupObjectType: MarinaLookupObjectType) -> MarinaCandidateEntityTypeHint? {
        switch lookupObjectType {
        case .budget:
            return .budget
        case .income, .incomeSeries:
            return .incomeSource
        case .variableExpense, .plannedExpense:
            return .transaction
        case .category:
            return .category
        case .preset:
            return .preset
        case .card:
            return .card
        case .savingsAccount, .savingsLedgerEntry:
            return .savingsAccount
        case .reconciliationAccount, .reconciliationItem, .expenseAllocation:
            return .allocationAccount
        case .importMerchantRule:
            return .merchant
        case .assistantAliasRule, .workspace:
            return .workspace
        case .unknown:
            return nil
        }
    }

    private func entityTypeHint(from relationship: MarinaRelationshipField) -> MarinaCandidateEntityTypeHint {
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
        case .workspace, .unknown:
            return .workspace
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

    private func dateRange(
        from scopes: [MarinaUnresolvedTimeScope],
        role: MarinaTimeScopeRole
    ) -> MarinaDateRangeRequest? {
        scopes.first { $0.role == role }.map {
            MarinaDateRangeRequest(
                role: $0.role,
                rawText: $0.rawText,
                resolvedRange: $0.resolvedRangeHint,
                periodUnit: $0.periodUnitHint
            )
        }
    }

    private func amountField(from measure: MarinaCandidateMeasure) -> MarinaAmountField? {
        switch measure {
        case .spend, .categoryShare:
            return .budgetImpactAmount
        case .income:
            return .incomeAmount
        case .savings, .savingsMovement:
            return .savingsAmount
        case .remainingBudget:
            return nil
        case .reconciliationBalance:
            return .reconciliationBalance
        case .transactionAmount:
            return .budgetImpactAmount
        case .transactionFrequency:
            return nil
        case .presetAmount:
            return .effectivePlannedAmount
        }
    }

    private func averageBasis(from grouping: MarinaGroupingCandidate?) -> MarinaAverageBasis? {
        switch grouping?.dimension {
        case .day:
            return .perDay
        case .week:
            return .perWeek
        case .month:
            return .perMonth
        case .transaction:
            return .perTransaction
        case .category, .merchant, .card, .incomeSource, .preset, .savingsLedgerEntry, .allocationAccount, nil:
            return nil
        }
    }

    private func responseShape(_ hint: MarinaResponseShapeHint) -> MarinaResponseShape? {
        MarinaResponseShape(rawValue: hint.rawValue)
    }

    private func responseShapeHint(_ shape: MarinaResponseShape) -> MarinaResponseShapeHint? {
        MarinaResponseShapeHint(rawValue: shape.rawValue)
    }

    private func unsupportedKind(from hint: MarinaUnsupportedHint) -> MarinaUnsupportedResponseKind {
        switch hint {
        case .unsupportedOperation, .unsupportedProjection:
            return .unsupportedOperation
        case .missingRequiredTarget:
            return .unsupportedTargetType
        case .unsupportedSimulation:
            return .unsupportedSimulation
        case .unsupportedCombination, .unsupportedExclusionFilter, .unsupportedBudgetLimit,
             .unsupportedFrequencyRanking, .unsupportedCardRanking, .unsupportedRankedComparison,
             .lowConfidence:
            return .unsupportedCombination
        }
    }
}
