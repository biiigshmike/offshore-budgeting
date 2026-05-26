import Foundation

enum MarinaCanonicalQuerySource: String, Codable, Equatable, Sendable {
    case deterministicSwift
    case appleIntelligence
    case priorContext
}

enum MarinaCanonicalDateDefaultPolicy: String, Codable, Equatable, Sendable {
    case none
    case currentPeriod
    case recentRows
    case allTime
    case explicitOnly
}

enum MarinaCanonicalQueryFailureKind: String, Codable, Equatable, Sendable {
    case notSafeRead
    case noDomainSubject
    case explicitNamedTargetRequired
    case unsupportedOperationForEntity
    case missingComparisonPeriod
}

struct MarinaCanonicalEntityPolicy: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let modelName: String
    let subject: MarinaSubject?
    let searchableNames: [String]
    let amountFields: [String]
    let dateFields: [String]
    let relationships: [String]
    let defaultDatePolicy: MarinaCanonicalDateDefaultPolicy
    let defaultOperation: MarinaOperation
    let supportedOperations: [MarinaOperation]
    let measure: MarinaCandidateMeasure
    let amountField: MarinaAmountField?
    let amountBasis: MarinaFinancialAmountBasis?
    let defaultPresentation: MarinaResponseShape
    let executorRoute: MarinaPreferredExecutorRoute?

    init(
        modelName: String,
        subject: MarinaSubject?,
        searchableNames: [String],
        amountFields: [String],
        dateFields: [String],
        relationships: [String],
        defaultDatePolicy: MarinaCanonicalDateDefaultPolicy,
        defaultOperation: MarinaOperation,
        supportedOperations: [MarinaOperation],
        measure: MarinaCandidateMeasure,
        amountField: MarinaAmountField?,
        amountBasis: MarinaFinancialAmountBasis?,
        defaultPresentation: MarinaResponseShape,
        executorRoute: MarinaPreferredExecutorRoute?
    ) {
        self.id = modelName
        self.modelName = modelName
        self.subject = subject
        self.searchableNames = searchableNames
        self.amountFields = amountFields
        self.dateFields = dateFields
        self.relationships = relationships
        self.defaultDatePolicy = defaultDatePolicy
        self.defaultOperation = defaultOperation
        self.supportedOperations = supportedOperations
        self.measure = measure
        self.amountField = amountField
        self.amountBasis = amountBasis
        self.defaultPresentation = defaultPresentation
        self.executorRoute = executorRoute
    }
}

struct MarinaCanonicalQuery: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let source: MarinaCanonicalQuerySource
    let modelName: String
    let subject: MarinaSubject?
    let operation: MarinaOperation
    let measure: MarinaCandidateMeasure
    let amountField: MarinaAmountField?
    let amountBasis: MarinaFinancialAmountBasis?
    let statusScope: MarinaIncomeStatusScope?
    let filters: [MarinaFilter]
    let dateScope: MarinaDateRangeRequest?
    let dateSource: MarinaDateSource
    let comparisonDateScope: MarinaDateRangeRequest?
    let grouping: MarinaGrouping?
    let ranking: MarinaRanking?
    let limit: Int?
    let presentation: MarinaResponseShape
    let confidence: MarinaCandidateConfidence
    let assumptions: [String]

    init(
        id: UUID = UUID(),
        source: MarinaCanonicalQuerySource,
        modelName: String,
        subject: MarinaSubject?,
        operation: MarinaOperation,
        measure: MarinaCandidateMeasure,
        amountField: MarinaAmountField?,
        amountBasis: MarinaFinancialAmountBasis?,
        statusScope: MarinaIncomeStatusScope? = nil,
        filters: [MarinaFilter] = [],
        dateScope: MarinaDateRangeRequest? = nil,
        dateSource: MarinaDateSource = .none,
        comparisonDateScope: MarinaDateRangeRequest? = nil,
        grouping: MarinaGrouping? = nil,
        ranking: MarinaRanking? = nil,
        limit: Int? = nil,
        presentation: MarinaResponseShape,
        confidence: MarinaCandidateConfidence,
        assumptions: [String] = []
    ) {
        self.id = id
        self.source = source
        self.modelName = modelName
        self.subject = subject
        self.operation = operation
        self.measure = measure
        self.amountField = amountField
        self.amountBasis = amountBasis
        self.statusScope = statusScope
        self.filters = filters
        self.dateScope = dateScope
        self.dateSource = dateSource
        self.comparisonDateScope = comparisonDateScope
        self.grouping = grouping
        self.ranking = ranking
        self.limit = limit
        self.presentation = presentation
        self.confidence = confidence
        self.assumptions = assumptions
    }

    var semanticQuery: MarinaSemanticQuery? {
        guard let subject else { return nil }
        return MarinaSemanticQuery(
            subject: subject,
            operation: operation,
            filters: filters,
            amountField: amountField,
            dateRange: dateScope,
            comparisonDateRange: comparisonDateScope,
            grouping: grouping,
            ranking: ranking,
            limit: limit,
            incomeStatusScope: statusScope,
            responseShape: presentation
        )
    }

    var universalQuery: MarinaUniversalQueryIR {
        MarinaUniversalQueryIR(
            operation: universalOperation,
            modelName: modelName,
            filters: filters.map(universalFilter),
            amountBasis: amountField,
            dateRange: dateScope?.resolvedRange,
            dateSource: dateSource,
            grouping: grouping?.dimension.rawValue,
            ranking: ranking?.direction,
            limit: limit,
            workspaceScopePolicy: modelName == "Workspace" ? .explicitGlobal : .selectedWorkspace,
            presentationShape: presentation,
            evidenceRowType: modelName
        )
    }

    private var universalOperation: MarinaUniversalQueryOperation {
        switch operation {
        case .sum, .percentageShare:
            return .sum
        case .average, .median:
            return .average
        case .count:
            return .count
        case .minimum:
            return .minimum
        case .maximum:
            return .maximum
        case .list:
            return .list
        case .compare:
            return .compare
        case .rank:
            return .rank
        case .breakdown:
            return .groupBreakdown
        case .lookupDetails:
            return .detail
        case .forecast, .simulate:
            return .simulate
        }
    }

    private func universalFilter(from filter: MarinaFilter) -> MarinaUniversalQueryFilter {
        MarinaUniversalQueryFilter(
            field: universalField(for: filter.relationship),
            value: filter.value,
            match: filter.relationship == .uncategorized ? .uncategorized : (filter.matchMode == .exact ? .exact : .contains)
        )
    }

    private func universalField(for relationship: MarinaRelationshipField) -> String? {
        switch relationship {
        case .category:
            return "category"
        case .merchant:
            return "merchant"
        case .card:
            return "card"
        case .budget:
            return "budget"
        case .preset:
            return "preset"
        case .incomeSource:
            return "income source"
        case .allocationAccount:
            return "allocation account"
        case .savingsAccount:
            return "savings account"
        case .transaction:
            return "transaction"
        case .workspace:
            return "workspace"
        case .uncategorized:
            return "category"
        case .unknown:
            return nil
        }
    }
}

struct MarinaCanonicalQueryDecision: Equatable, Sendable {
    let query: MarinaCanonicalQuery
    let reason: String
}

struct MarinaCanonicalQueryFailure: Error, Equatable, Sendable {
    let kind: MarinaCanonicalQueryFailureKind
    let message: String
}

@MainActor
struct MarinaCanonicalDomainCatalog {
    private let entityCatalog: MarinaEntityCatalog
    private let semanticCatalogCompiler: MarinaSemanticCatalogCompiler

    init(entityCatalog: MarinaEntityCatalog? = nil) {
        let catalog = entityCatalog ?? .current
        self.entityCatalog = catalog
        self.semanticCatalogCompiler = MarinaSemanticCatalogCompiler(catalog: catalog)
    }

    var policies: [MarinaCanonicalEntityPolicy] {
        entityCatalog.descriptors
            .filter { $0.kind == .persistentModel }
            .map(policy)
    }

    func policy(for modelName: String) -> MarinaCanonicalEntityPolicy? {
        guard let descriptor = entityCatalog.descriptor(for: modelName) else { return nil }
        return policy(for: descriptor)
    }

    func policy(matching normalizedPrompt: String) -> MarinaCanonicalEntityPolicy? {
        if containsWholePhrase("income", in: normalizedPrompt)
            || containsWholePhrase("paycheck", in: normalizedPrompt) {
            if containsAny(["income series", "income schedule", "recurring income"], in: normalizedPrompt) {
                return policy(for: "IncomeSeries")
            }
            return policy(for: "Income")
        }

        if containsAny(["savings activity", "savings movement", "savings ledger"], in: normalizedPrompt) {
            return policy(for: "SavingsLedgerEntry")
        }
        if containsWholePhrase("savings", in: normalizedPrompt) {
            if containsAny(["balance", "status", "running total", "total saved"], in: normalizedPrompt) {
                return policy(for: "SavingsAccount")
            }
            return policy(for: "SavingsLedgerEntry")
        }

        if containsAny(["recent transaction", "recent transactions", "transaction", "transactions", "spending", "spend"], in: normalizedPrompt) {
            if containsAny(["planned expense", "planned expenses", "upcoming expense", "bill", "bills"], in: normalizedPrompt) {
                return policy(for: "PlannedExpense")
            }
            return policy(for: "VariableExpense")
        }

        if containsAny(["budget limit", "category limit", "category goal"], in: normalizedPrompt) {
            return policy(for: "BudgetCategoryLimit")
        }
        if containsAny(["linked card", "budget card link"], in: normalizedPrompt) {
            return policy(for: "BudgetCardLink")
        }
        if containsAny(["linked preset", "budget preset link"], in: normalizedPrompt) {
            return policy(for: "BudgetPresetLink")
        }

        let matches = policies.compactMap { policy -> (MarinaCanonicalEntityPolicy, Int)? in
            let score = policy.searchableNames.reduce(0) { partial, name in
                guard containsWholePhrase(name, in: normalizedPrompt) else { return partial }
                let tokenCount = name.split(separator: " ").count
                return max(partial, tokenCount > 1 ? tokenCount * 4 : 2)
            }
            return score > 0 ? (policy, score) : nil
        }
        .sorted {
            if $0.1 == $1.1 { return $0.0.modelName < $1.0.modelName }
            return $0.1 > $1.1
        }
        return matches.first?.0
    }

    private func policy(for descriptor: MarinaEntityDescriptor) -> MarinaCanonicalEntityPolicy {
        let semanticNames = semanticCatalogCompiler.aliases(for: descriptor)
        let names = ([descriptor.entityName, descriptor.displayName] + descriptor.displayFields + descriptor.searchableFields + semanticNames)
            .map(normalized)
            .filter { $0.isEmpty == false }
        let supported = supportedOperations(for: descriptor)
        let defaults = defaults(for: descriptor)
        return MarinaCanonicalEntityPolicy(
            modelName: descriptor.entityName,
            subject: defaults.subject,
            searchableNames: unique(names),
            amountFields: descriptor.amountFields,
            dateFields: descriptor.dateFields,
            relationships: descriptor.relationships.map(\.name),
            defaultDatePolicy: defaults.datePolicy,
            defaultOperation: defaults.operation,
            supportedOperations: supported,
            measure: defaults.measure,
            amountField: defaults.amountField,
            amountBasis: defaults.amountBasis,
            defaultPresentation: defaults.presentation,
            executorRoute: defaults.executorRoute
        )
    }

    private func supportedOperations(for descriptor: MarinaEntityDescriptor) -> [MarinaOperation] {
        var operations: [MarinaOperation] = []
        if descriptor.isQueryable {
            operations.append(contentsOf: [.lookupDetails, .list, .count])
        }
        if descriptor.amountFields.isEmpty == false || descriptor.isAggregatable {
            operations.append(contentsOf: [.sum, .average, .minimum, .maximum, .rank, .breakdown])
        }
        if descriptor.supportedOperations.contains("compare") || descriptor.isAggregatable {
            operations.append(.compare)
        }
        return unique(operations)
    }

    private func defaults(
        for descriptor: MarinaEntityDescriptor
    ) -> (
        subject: MarinaSubject?,
        operation: MarinaOperation,
        measure: MarinaCandidateMeasure,
        amountField: MarinaAmountField?,
        amountBasis: MarinaFinancialAmountBasis?,
        datePolicy: MarinaCanonicalDateDefaultPolicy,
        presentation: MarinaResponseShape,
        executorRoute: MarinaPreferredExecutorRoute?
    ) {
        switch descriptor.entityName {
        case "Workspace":
            return (.workspaces, .lookupDetails, .transactionAmount, nil, nil, .none, .summaryCard, .databaseLookup)
        case "Budget":
            return (.budgets, .lookupDetails, .remainingBudget, nil, .budgetImpact, .currentPeriod, .summaryCard, .composableWorkspace)
        case "BudgetCategoryLimit":
            return (.budgets, .lookupDetails, .remainingBudget, .budgetImpactAmount, .budgetImpact, .currentPeriod, .relationshipList, .composableWorkspace)
        case "BudgetCardLink":
            return (.budgets, .lookupDetails, .remainingBudget, nil, .count, .none, .relationshipList, .composableWorkspace)
        case "BudgetPresetLink":
            return (.budgets, .lookupDetails, .remainingBudget, nil, .count, .none, .relationshipList, .composableWorkspace)
        case "Card":
            return (.cards, .list, .transactionAmount, nil, .count, .none, .relationshipList, .databaseLookup)
        case "Category":
            return (.categories, .list, .spend, nil, .budgetImpact, .none, .relationshipList, .databaseLookup)
        case "Preset":
            return (.presets, .list, .presetAmount, .plannedAmount, .plannedAmount, .none, .relationshipList, .workspaceAggregation)
        case "PlannedExpense":
            return (.plannedExpenses, .list, .presetAmount, .effectivePlannedAmount, .plannedEffectiveAmount, .currentPeriod, .rankedList, .workspaceAggregation)
        case "VariableExpense":
            return (.variableExpenses, .sum, .spend, .budgetImpactAmount, .budgetImpact, .currentPeriod, .summaryCard, .aggregate)
        case "AllocationAccount":
            return (.reconciliationAccounts, .lookupDetails, .reconciliationBalance, .reconciliationBalance, .reconciliationBalance, .none, .summaryCard, .workspaceAggregation)
        case "ExpenseAllocation":
            return (.reconciliationItems, .list, .reconciliationBalance, .allocatedAmount, .allocated, .currentPeriod, .relationshipList, .composableWorkspace)
        case "AllocationSettlement":
            return (.reconciliationItems, .list, .reconciliationBalance, .amount, .reconciliationSettlement, .currentPeriod, .relationshipList, .composableWorkspace)
        case "SavingsAccount":
            return (.savingsAccounts, .lookupDetails, .savings, .savingsAmount, .savingsRunningTotal, .none, .summaryCard, .homeAdapter)
        case "SavingsLedgerEntry":
            return (.savingsLedgerEntries, .list, .savingsMovement, .savingsAmount, .savingsMovement, .currentPeriod, .relationshipList, .workspaceAggregation)
        case "ImportMerchantRule":
            return (.merchant, .list, .transactionAmount, nil, nil, .none, .relationshipList, .databaseLookup)
        case "AssistantAliasRule":
            return (.workspaces, .list, .transactionAmount, nil, nil, .none, .relationshipList, .databaseLookup)
        case "IncomeSeries":
            return (.incomeSource, .list, .income, .incomeAmount, .plannedIncome, .currentPeriod, .relationshipList, .workspaceAggregation)
        case "Income":
            return (.income, .sum, .income, .incomeAmount, .actualIncome, .currentPeriod, .summaryCard, .workspaceAggregation)
        default:
            return (nil, .lookupDetails, .transactionAmount, nil, nil, .none, .summaryCard, nil)
        }
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: #"([a-z0-9])([A-Z])"#, with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: #"([A-Z])([A-Z][a-z])"#, with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "[^a-z0-9\\s&]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func containsAny(_ needles: [String], in haystack: String) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    private func containsWholePhrase(_ phrase: String, in normalizedPrompt: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        return normalizedPrompt.range(of: #"(?<![a-z0-9])\#(escaped)(?![a-z0-9])"#, options: .regularExpression) != nil
    }

    private func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen: Set<T> = []
        return values.filter { seen.insert($0).inserted }
    }
}

@MainActor
struct MarinaCanonicalQueryCompiler {
    private let catalog: MarinaCanonicalDomainCatalog

    init(catalog: MarinaCanonicalDomainCatalog? = nil) {
        self.catalog = catalog ?? MarinaCanonicalDomainCatalog()
    }

    func compile(
        prompt: String,
        now: Date,
        defaultPeriodUnit: HomeQueryPeriodUnit,
        source: MarinaCanonicalQuerySource = .deterministicSwift
    ) -> Result<MarinaCanonicalQueryDecision, MarinaCanonicalQueryFailure> {
        let normalizedPrompt = normalized(prompt)
        guard normalizedPrompt.isEmpty == false,
              isSafeReadPrompt(prompt, normalizedPrompt: normalizedPrompt) else {
            return .failure(MarinaCanonicalQueryFailure(kind: .notSafeRead, message: "That prompt is not a safe read query."))
        }

        guard selectedWorkspaceIdentityQuestion(normalizedPrompt) || hasExplicitNamedTargetSignal(in: normalizedPrompt) == false else {
            return .failure(MarinaCanonicalQueryFailure(kind: .explicitNamedTargetRequired, message: "Named-target prompts must resolve through the entity resolver."))
        }

        guard let policy = catalog.policy(matching: normalizedPrompt) else {
            return .failure(MarinaCanonicalQueryFailure(kind: .noDomainSubject, message: "No domain entity matched the prompt."))
        }

        var operation = operation(in: normalizedPrompt, policy: policy)
        let grouping = grouping(in: normalizedPrompt, policy: policy)
        if grouping != nil,
           [.sum, .average, .count].contains(operation),
           policy.amountField != nil {
            operation = .breakdown
        }

        guard policy.supportedOperations.contains(operation)
            || (operation == .breakdown && policy.supportedOperations.contains(.sum)) else {
            return .failure(MarinaCanonicalQueryFailure(kind: .unsupportedOperationForEntity, message: "\(operation.rawValue) is not supported for \(policy.modelName)."))
        }

        if operation == .compare,
           comparisonDateRange(in: prompt, now: now, defaultPeriodUnit: defaultPeriodUnit) == nil {
            return .failure(MarinaCanonicalQueryFailure(kind: .missingComparisonPeriod, message: "Comparison queries need a comparison period."))
        }

        let dateDecision = dateScope(
            in: prompt,
            policy: policy,
            now: now,
            defaultPeriodUnit: defaultPeriodUnit
        )
        let statusScope = incomeStatusScope(in: normalizedPrompt, policy: policy)
        let ranking = ranking(in: normalizedPrompt, operation: operation)
        let limit = MarinaResultLimitExtractor().limit(in: prompt) ?? defaultLimit(in: normalizedPrompt, policy: policy, operation: operation)
        let filters = filters(in: normalizedPrompt, policy: policy)
        var assumptions = dateDecision.assumptions
        if policy.modelName == "Income", statusScope == .actual, containsAny(["all income", "planned and actual", "actual and planned"], in: normalizedPrompt) == false {
            assumptions.append("Interpreted income as received/actual income.")
        }
        if policy.modelName == "VariableExpense", filters.contains(where: { $0.relationship == .uncategorized }) {
            assumptions.append("Interpreted uncategorized as a nil category filter.")
        }

        let query = MarinaCanonicalQuery(
            source: source,
            modelName: policy.modelName,
            subject: policy.subject,
            operation: operation,
            measure: measure(for: policy, normalizedPrompt: normalizedPrompt, operation: operation),
            amountField: amountField(for: policy, operation: operation),
            amountBasis: amountBasis(for: policy, statusScope: statusScope),
            statusScope: statusScope,
            filters: filters,
            dateScope: dateDecision.scope,
            dateSource: dateDecision.source,
            comparisonDateScope: comparisonDateRange(in: prompt, now: now, defaultPeriodUnit: defaultPeriodUnit),
            grouping: grouping,
            ranking: ranking,
            limit: limit,
            presentation: presentation(for: operation, grouping: grouping, policy: policy),
            confidence: .high,
            assumptions: assumptions
        )
        return .success(MarinaCanonicalQueryDecision(query: query, reason: "canonicalQuery:model:\(policy.modelName):operation:\(operation.rawValue)"))
    }

    func compile(
        prompt: String,
        context: MarinaTurnContext,
        source: MarinaCanonicalQuerySource = .deterministicSwift
    ) -> Result<MarinaCanonicalQueryDecision, MarinaCanonicalQueryFailure> {
        compile(
            prompt: prompt,
            now: context.now,
            defaultPeriodUnit: context.defaultPeriodUnit,
            source: source
        )
    }

    nonisolated static func isGenericTargetValue(_ value: String, modelName: String) -> Bool {
        let normalizedValue = value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch modelName {
        case "Income":
            return [
                "income", "actual", "planned", "actual income", "planned income",
                "received income", "income received", "expected income", "projected income"
            ].contains(normalizedValue)
        case "VariableExpense":
            return ["spend", "spending", "expense", "expenses", "transaction", "transactions"].contains(normalizedValue)
        case "SavingsLedgerEntry", "SavingsAccount":
            return ["savings", "saving", "savings activity", "savings movement", "savings balance"].contains(normalizedValue)
        default:
            return normalizedValue == modelName
                .replacingOccurrences(of: #"([a-z0-9])([A-Z])"#, with: "$1 $2", options: .regularExpression)
                .lowercased()
        }
    }

    private func isSafeReadPrompt(_ prompt: String, normalizedPrompt: String) -> Bool {
        guard MarinaRoutePatternRegistry.isReadOnlyStep5Mutation(prompt) == nil,
              MarinaMutationIntentGuard().isMutationPrompt(prompt) == false else {
            return false
        }
        let adviceTerms = [
            "should i invest", "should i buy", "should i sell", "financial advice",
            "investment advice", "tax advice", "legal advice", "credit advice",
            "insurance advice"
        ]
        return adviceTerms.contains { normalizedPrompt.contains($0) } == false
    }

    private func operation(
        in normalizedPrompt: String,
        policy: MarinaCanonicalEntityPolicy
    ) -> MarinaOperation {
        if selectedWorkspaceIdentityQuestion(normalizedPrompt) {
            return .lookupDetails
        }
        if normalizedPrompt.hasPrefix("how many ")
            || normalizedPrompt.hasPrefix("count ")
            || normalizedPrompt.contains(" count ") {
            return .count
        }
        if containsAny(["average", "avg"], in: normalizedPrompt) {
            return .average
        }
        if containsAny(["compare", " versus ", " vs "], in: " \(normalizedPrompt) ") {
            return .compare
        }
        if containsAny(["top ", "largest", "biggest", "highest", "most "], in: normalizedPrompt) {
            return .rank
        }
        if containsAny(["smallest", "lowest", "least "], in: normalizedPrompt) {
            return .rank
        }
        if containsAny(["breakdown", " by ", " each ", " per "], in: " \(normalizedPrompt) ") {
            return policy.amountField == nil ? .list : .breakdown
        }
        if containsAny(["recent ", "latest ", "newest ", "activity", "list ", "show all "], in: normalizedPrompt) {
            return .list
        }
        if containsAny(["total", "sum", "how much", "what is my", "what are my"], in: normalizedPrompt),
           policy.amountField != nil {
            return .sum
        }
        return policy.defaultOperation
    }

    private func measure(
        for policy: MarinaCanonicalEntityPolicy,
        normalizedPrompt: String,
        operation: MarinaOperation
    ) -> MarinaCandidateMeasure {
        if policy.modelName == "VariableExpense",
           operation == .list {
            return .transactionAmount
        }
        return policy.measure
    }

    private func amountField(
        for policy: MarinaCanonicalEntityPolicy,
        operation: MarinaOperation
    ) -> MarinaAmountField? {
        switch operation {
        case .count, .list, .lookupDetails:
            return operation == .list ? policy.amountField : nil
        default:
            return policy.amountField
        }
    }

    private func amountBasis(
        for policy: MarinaCanonicalEntityPolicy,
        statusScope: MarinaIncomeStatusScope?
    ) -> MarinaFinancialAmountBasis? {
        guard policy.modelName == "Income" else {
            return policy.amountBasis
        }
        return statusScope == .planned ? .plannedIncome : .actualIncome
    }

    private func incomeStatusScope(
        in normalizedPrompt: String,
        policy: MarinaCanonicalEntityPolicy
    ) -> MarinaIncomeStatusScope? {
        guard policy.modelName == "Income" else { return nil }
        if containsAny(["all income", "planned and actual", "actual and planned"], in: normalizedPrompt) {
            return .all
        }
        if containsAny(["planned", "expected", "projected", "forecast"], in: normalizedPrompt) {
            return .planned
        }
        return .actual
    }

    private func grouping(
        in normalizedPrompt: String,
        policy: MarinaCanonicalEntityPolicy
    ) -> MarinaGrouping? {
        let padded = " \(normalizedPrompt) "
        let dimension: MarinaGroupingDimensionCandidate?
        if containsAny([" by source ", " per source ", " each source ", " income source "], in: padded) {
            dimension = .incomeSource
        } else if containsAny([" by category ", " per category ", " each category "], in: padded) {
            dimension = .category
        } else if containsAny([" by card ", " per card ", " each card "], in: padded) {
            dimension = .card
        } else if containsAny([" by merchant ", " per merchant ", " each merchant "], in: padded) {
            dimension = .merchant
        } else if containsAny([" by month ", " per month ", " each month "], in: padded) {
            dimension = .month
        } else if containsAny([" by week ", " per week ", " each week "], in: padded) {
            dimension = .week
        } else if containsAny([" by day ", " per day ", " each day "], in: padded) {
            dimension = .day
        } else if policy.modelName == "SavingsLedgerEntry",
                  containsAny(["activity", "movement", "ledger"], in: normalizedPrompt) {
            dimension = .savingsLedgerEntry
        } else {
            dimension = nil
        }
        return dimension.map { MarinaGrouping(dimension: $0, rawText: nil) }
    }

    private func ranking(
        in normalizedPrompt: String,
        operation: MarinaOperation
    ) -> MarinaRanking? {
        guard operation == .rank || containsAny(["recent", "latest", "newest"], in: normalizedPrompt) else {
            return nil
        }
        let direction: MarinaRankingDirectionCandidate
        if containsAny(["smallest", "lowest", "least"], in: normalizedPrompt) {
            direction = .smallest
        } else if containsAny(["recent", "latest", "newest"], in: normalizedPrompt) {
            direction = .newest
        } else {
            direction = .largest
        }
        return MarinaRanking(direction: direction, limit: nil, rawText: nil)
    }

    private func filters(
        in normalizedPrompt: String,
        policy: MarinaCanonicalEntityPolicy
    ) -> [MarinaFilter] {
        guard policy.modelName == "VariableExpense",
              containsWholePhrase("uncategorized", in: normalizedPrompt) else {
            return []
        }
        return [
            MarinaFilter(
                role: .filter,
                relationship: .uncategorized,
                value: "Uncategorized",
                matchMode: .exact,
                entityTypeHint: .category,
                allowedEntityTypeHints: [.category],
                sourceID: nil
            )
        ]
    }

    private func dateScope(
        in prompt: String,
        policy: MarinaCanonicalEntityPolicy,
        now: Date,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> (scope: MarinaDateRangeRequest?, source: MarinaDateSource, assumptions: [String]) {
        if let explicitRange = MarinaDateRangeTextResolver(
            calendar: Calendar(identifier: .gregorian),
            nowProvider: { now }
        ).resolve(prompt, defaultPeriodUnit: defaultPeriodUnit) {
            return (
                MarinaDateRangeRequest(
                    role: .primary,
                    rawText: prompt,
                    resolvedRange: explicitRange,
                    periodUnit: defaultPeriodUnit
                ),
                .promptExplicit,
                []
            )
        }

        switch policy.defaultDatePolicy {
        case .currentPeriod:
            let range = currentPeriodRange(containing: now, unit: defaultPeriodUnit)
            return (
                MarinaDateRangeRequest(
                    role: .primary,
                    rawText: "current \(defaultPeriodUnit.rawValue)",
                    resolvedRange: range,
                    periodUnit: defaultPeriodUnit
                ),
                .defaultBudgetingPeriod,
                ["Defaulted date scope to current \(defaultPeriodUnit.rawValue)."]
            )
        case .recentRows:
            return (nil, .none, ["Defaulted to recent rows."])
        case .allTime:
            let range = HomeQueryDateRange(startDate: date(2000, 1, 1), endDate: now)
            return (
                MarinaDateRangeRequest(role: .primary, rawText: "all time", resolvedRange: range, periodUnit: nil),
                .defaultBudgetingPeriod,
                ["Defaulted date scope to all time."]
            )
        case .explicitOnly, .none:
            return (nil, .none, [])
        }
    }

    private func comparisonDateRange(
        in prompt: String,
        now: Date,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> MarinaDateRangeRequest? {
        let normalizedPrompt = normalized(prompt)
        guard containsAny(["previous", "last ", "prior ", "versus", " vs ", "compare"], in: " \(normalizedPrompt) ") else {
            return nil
        }
        guard let primary = MarinaDateRangeTextResolver(
            calendar: Calendar(identifier: .gregorian),
            nowProvider: { now }
        ).resolve(prompt, defaultPeriodUnit: defaultPeriodUnit) else {
            return nil
        }
        let previous = previousEquivalentRange(to: primary, unit: defaultPeriodUnit)
        return MarinaDateRangeRequest(
            role: .comparison,
            rawText: "previous \(defaultPeriodUnit.rawValue)",
            resolvedRange: previous,
            periodUnit: defaultPeriodUnit
        )
    }

    private func defaultLimit(
        in normalizedPrompt: String,
        policy: MarinaCanonicalEntityPolicy,
        operation: MarinaOperation
    ) -> Int? {
        if operation == .list,
           policy.defaultDatePolicy == .recentRows || containsAny(["recent", "latest", "newest"], in: normalizedPrompt) {
            return 10
        }
        if operation == .rank {
            return 5
        }
        return nil
    }

    private func presentation(
        for operation: MarinaOperation,
        grouping: MarinaGrouping?,
        policy: MarinaCanonicalEntityPolicy
    ) -> MarinaResponseShape {
        if grouping != nil { return .groupedBreakdown }
        switch operation {
        case .sum, .average, .count, .minimum, .maximum, .median:
            return .summaryCard
        case .compare:
            return .comparison
        case .rank:
            return .rankedList
        case .breakdown, .percentageShare:
            return .groupedBreakdown
        case .list:
            return .relationshipList
        case .lookupDetails, .forecast, .simulate:
            return policy.defaultPresentation
        }
    }

    private func hasExplicitNamedTargetSignal(in normalizedPrompt: String) -> Bool {
        let padded = " \(normalizedPrompt) "
        if containsAny([" from each ", " by source ", " each source ", " per source "], in: padded) {
            return false
        }
        return containsAny([" at ", " from ", " on ", " named ", " called "], in: padded)
    }

    private func selectedWorkspaceIdentityQuestion(_ normalizedPrompt: String) -> Bool {
        normalizedPrompt.contains("workspace am i in")
            || normalizedPrompt.contains("current workspace")
            || normalizedPrompt.contains("selected workspace")
            || normalizedPrompt.contains("which workspace")
            || normalizedPrompt == "what workspace"
            || normalizedPrompt.hasPrefix("what workspace ")
    }

    private func currentPeriodRange(
        containing date: Date,
        unit: HomeQueryPeriodUnit
    ) -> HomeQueryDateRange {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let component: Calendar.Component
        switch unit {
        case .day:
            component = .day
        case .week:
            component = .weekOfYear
        case .month:
            component = .month
        case .quarter:
            return currentQuarterRange(containing: date, calendar: calendar)
        case .year:
            component = .year
        }
        guard let interval = calendar.dateInterval(of: component, for: date) else {
            return HomeQueryDateRange(startDate: calendar.startOfDay(for: date), endDate: date)
        }
        return HomeQueryDateRange(
            startDate: interval.start,
            endDate: interval.end.addingTimeInterval(-1)
        )
    }

    private func currentQuarterRange(containing date: Date, calendar: Calendar) -> HomeQueryDateRange {
        let components = calendar.dateComponents([.year, .month], from: date)
        let month = components.month ?? 1
        let quarterStartMonth = ((month - 1) / 3) * 3 + 1
        let start = calendar.date(from: DateComponents(year: components.year, month: quarterStartMonth, day: 1)) ?? date
        let end = calendar.date(byAdding: DateComponents(month: 3, second: -1), to: start) ?? start
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func previousEquivalentRange(
        to range: HomeQueryDateRange,
        unit: HomeQueryPeriodUnit
    ) -> HomeQueryDateRange {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let component: Calendar.Component
        switch unit {
        case .day:
            component = .day
        case .week:
            component = .weekOfYear
        case .month:
            component = .month
        case .quarter:
            component = .month
        case .year:
            component = .year
        }
        let value = unit == .quarter ? -3 : -1
        let start = calendar.date(byAdding: component, value: value, to: range.startDate) ?? range.startDate
        let end = calendar.date(byAdding: component, value: value, to: range.endDate) ?? range.endDate
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s&]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func containsAny(_ needles: [String], in haystack: String) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    private func containsWholePhrase(_ phrase: String, in normalizedPrompt: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        return normalizedPrompt.range(of: #"(?<![a-z0-9])\#(escaped)(?![a-z0-9])"#, options: .regularExpression) != nil
    }
}

@MainActor
struct MarinaTargetedBalanceCanonicalizer {
    static let generatedSchemaName = "MarinaCanonicalBalance"

    private let semanticAdapter = MarinaSemanticQueryAdapter()

    func interpretation(
        prompt: String,
        context: MarinaTurnContext
    ) -> MarinaTurnInterpretation? {
        let normalizedPrompt = normalized(prompt)
        guard normalizedPrompt.isEmpty == false,
              hasBalanceCue(normalizedPrompt),
              isSafeReadPrompt(prompt) else {
            return nil
        }

        let targetText = extractedTargetText(from: normalizedPrompt)
        let dateDecision = dateScope(
            prompt: prompt,
            normalizedPrompt: normalizedPrompt,
            now: context.now,
            defaultPeriodUnit: context.defaultPeriodUnit
        )

        if isStatementBalancePrompt(normalizedPrompt) {
            return unsupportedInterpretation(
                prompt: prompt,
                message: "Marina does not store imported or statement account balances yet. I can show current-period card ledger spend, reconciliation balances, or savings balances from recorded entries."
            )
        }

        let targets = balanceTargets(provider: context.provider)
        let matches = matchingTargets(
            prompt: normalizedPrompt,
            targetText: targetText,
            targets: targets
        )

        guard targetText.isEmpty == false || matches.isEmpty == false else {
            return clarificationInterpretation(
                prompt: prompt,
                kind: .missingTarget,
                message: "Which balance should I check?",
                targets: targets,
                dateDecision: dateDecision
            )
        }

        guard matches.isEmpty == false else {
            return clarificationInterpretation(
                prompt: prompt,
                kind: .missingTarget,
                message: "Which balance should I check?",
                targets: targets,
                dateDecision: dateDecision
            )
        }

        guard matches.count == 1, let target = matches.first else {
            let targetLabel = targetText.isEmpty ? (matches.first?.displayName ?? "that") : displayText(targetText)
            return clarificationInterpretation(
                prompt: prompt,
                kind: .ambiguousTarget,
                message: "Which \(targetLabel) balance did you mean?",
                targets: matches,
                dateDecision: dateDecision
            )
        }

        return queryInterpretation(
            target: target,
            prompt: prompt,
            dateDecision: dateDecision
        )
    }

    private func queryInterpretation(
        target: BalanceTarget,
        prompt: String,
        dateDecision: DateDecision
    ) -> MarinaTurnInterpretation {
        let query = semanticQuery(target: target, dateDecision: dateDecision)
        let candidate = semanticAdapter.compatibilityCandidate(
            from: query,
            prompt: prompt,
            source: .deterministic
        )
        let dateReason = dateDecision.source == .promptExplicit
            ? "explicitDate"
            : "defaultCurrent\(dateDecision.periodUnit.rawValue.capitalized)"
        return MarinaTurnInterpretation(
            result: .query(query),
            compatibilityCandidate: candidate,
            repairSummary: "canonicalBalance:\(target.traceName):\(dateReason)",
            generatedSchemaName: Self.generatedSchemaName
        )
    }

    private func clarificationInterpretation(
        prompt: String,
        kind: MarinaClarificationKind,
        message: String,
        targets: [BalanceTarget],
        dateDecision: DateDecision
    ) -> MarinaTurnInterpretation {
        let candidate = balanceCandidate(prompt: prompt)
        let choices = targets.prefix(12).map { target in
            let query = semanticQuery(target: target, dateDecision: dateDecision)
            let resumeCandidate = semanticAdapter.compatibilityCandidate(
                from: query,
                prompt: prompt,
                source: .deterministic
            )
            return MarinaClarificationChoice(
                title: target.displayName,
                subtitle: "\(target.choiceSubtitle) balance",
                entityRole: .primaryTarget,
                entityTypeHint: target.entityType,
                patchSlot: .target,
                rawValue: target.displayName,
                sourceID: target.id,
                resumeIntent: MarinaClarificationResumeIntent(
                    candidate: resumeCandidate,
                    semanticQuery: query
                )
            )
        }
        return MarinaTurnInterpretation(
            result: .clarification(
                MarinaTypedClarification(
                    kind: kind,
                    message: message,
                    candidate: candidate,
                    patchSlot: .target,
                    choices: choices
                )
            ),
            compatibilityCandidate: candidate,
            repairSummary: "canonicalBalance:\(kind.rawValue)",
            generatedSchemaName: Self.generatedSchemaName
        )
    }

    private func unsupportedInterpretation(
        prompt: String,
        message: String
    ) -> MarinaTurnInterpretation {
        let candidate = balanceCandidate(prompt: prompt)
        return MarinaTurnInterpretation(
            result: .unsupported(
                MarinaTypedUnsupportedResponse(
                    kind: .unsupportedCombination,
                    message: message,
                    candidate: candidate
                )
            ),
            compatibilityCandidate: candidate,
            repairSummary: "canonicalBalance:unsupportedStatementBalance",
            generatedSchemaName: Self.generatedSchemaName
        )
    }

    private func semanticQuery(
        target: BalanceTarget,
        dateDecision: DateDecision
    ) -> MarinaSemanticQuery {
        MarinaSemanticQuery(
            subject: target.subject,
            operation: .lookupDetails,
            filters: [
                MarinaFilter(
                    role: .primaryTarget,
                    relationship: target.relationship,
                    value: target.displayName,
                    matchMode: .exact,
                    entityTypeHint: target.entityType,
                    allowedEntityTypeHints: [target.entityType],
                    sourceID: target.id
                )
            ],
            amountField: target.amountField,
            dateRange: dateDecision.request,
            responseShape: .summaryCard,
            requestedDetail: .balance,
            routeIntent: MarinaRouteIntent(
                kind: target.routeKind,
                subject: target.subject,
                operation: .lookupDetails,
                measure: target.measure,
                grouping: nil,
                targetTypes: [target.entityType],
                requestedDetail: .balance,
                responseShape: .summaryCard,
                preferredExecutorRoute: .workspaceAggregation
            )
        )
    }

    private func balanceCandidate(prompt: String) -> MarinaQueryPlanCandidate {
        MarinaQueryPlanCandidate(
            requestFamily: .analytics,
            source: .deterministic,
            rawPrompt: prompt,
            operation: .lookupDetails,
            measure: .reconciliationBalance,
            responseShapeHint: .summaryCard,
            confidence: .high
        )
    }

    private func balanceTargets(provider: MarinaDataProvider) -> [BalanceTarget] {
        let reconciliation = provider.fetchAllAllocationAccounts()
            .filter { $0.isArchived == false }
            .map {
                BalanceTarget(
                    id: $0.id,
                    displayName: $0.name,
                    entityType: .allocationAccount,
                    relationship: .allocationAccount,
                    subject: .reconciliationAccounts,
                    measure: .reconciliationBalance,
                    amountField: .reconciliationBalance,
                    routeKind: .reconciliationBalance,
                    choiceSubtitle: "Reconciliation account",
                    traceName: "reconciliation"
                )
            }
        let cards = provider.fetchAllCards().map {
            BalanceTarget(
                id: $0.id,
                displayName: $0.name,
                entityType: .card,
                relationship: .card,
                subject: .cards,
                measure: .spend,
                amountField: nil,
                routeKind: .broadSpend,
                choiceSubtitle: "Card",
                traceName: "card"
            )
        }
        let savings = provider.fetchAllSavingsAccounts().map {
            BalanceTarget(
                id: $0.id,
                displayName: $0.name,
                entityType: .savingsAccount,
                relationship: .savingsAccount,
                subject: .savingsAccounts,
                measure: .savings,
                amountField: .savingsAmount,
                routeKind: .savingsStatus,
                choiceSubtitle: "Savings account",
                traceName: "savings"
            )
        }
        return unique(reconciliation + cards + savings)
    }

    private func matchingTargets(
        prompt normalizedPrompt: String,
        targetText: String,
        targets: [BalanceTarget]
    ) -> [BalanceTarget] {
        let exactPromptMatches = targets.filter { target in
            containsWholePhrase(normalized(target.displayName), in: normalizedPrompt)
        }
        if exactPromptMatches.isEmpty == false {
            return unique(exactPromptMatches)
        }

        let normalizedTarget = normalized(targetText)
        guard normalizedTarget.isEmpty == false else { return [] }
        return unique(targets.filter { target in
            let name = normalized(target.displayName)
            return name == normalizedTarget
                || containsWholePhrase(name, in: normalizedTarget)
                || containsWholePhrase(normalizedTarget, in: name)
        })
    }

    private func dateScope(
        prompt: String,
        normalizedPrompt _: String,
        now: Date,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> DateDecision {
        if let explicitRange = MarinaDateRangeTextResolver(
            calendar: Calendar(identifier: .gregorian),
            nowProvider: { now }
        ).resolve(prompt, defaultPeriodUnit: defaultPeriodUnit) {
            return DateDecision(
                request: MarinaDateRangeRequest(
                    role: .primary,
                    rawText: prompt,
                    resolvedRange: explicitRange,
                    periodUnit: defaultPeriodUnit
                ),
                source: .promptExplicit,
                periodUnit: defaultPeriodUnit
            )
        }

        let range = currentPeriodRange(containing: now, unit: defaultPeriodUnit)
        return DateDecision(
            request: MarinaDateRangeRequest(
                role: .primary,
                rawText: "current \(defaultPeriodUnit.rawValue)",
                resolvedRange: range,
                periodUnit: defaultPeriodUnit
            ),
            source: .defaultBudgetingPeriod,
            periodUnit: defaultPeriodUnit
        )
    }

    private func currentPeriodRange(
        containing date: Date,
        unit: HomeQueryPeriodUnit
    ) -> HomeQueryDateRange {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let component: Calendar.Component
        switch unit {
        case .day:
            component = .day
        case .week:
            component = .weekOfYear
        case .month:
            component = .month
        case .quarter:
            return currentQuarterRange(containing: date, calendar: calendar)
        case .year:
            component = .year
        }
        guard let interval = calendar.dateInterval(of: component, for: date) else {
            return HomeQueryDateRange(startDate: calendar.startOfDay(for: date), endDate: date)
        }
        return HomeQueryDateRange(
            startDate: interval.start,
            endDate: interval.end.addingTimeInterval(-1)
        )
    }

    private func currentQuarterRange(containing date: Date, calendar: Calendar) -> HomeQueryDateRange {
        let components = calendar.dateComponents([.year, .month], from: date)
        let month = components.month ?? 1
        let quarterStartMonth = ((month - 1) / 3) * 3 + 1
        let start = calendar.date(from: DateComponents(year: components.year, month: quarterStartMonth, day: 1)) ?? date
        let end = calendar.date(byAdding: DateComponents(month: 3, second: -1), to: start) ?? start
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func extractedTargetText(from normalizedPrompt: String) -> String {
        let filler: Set<String> = [
            "what", "whats", "is", "are", "was", "were", "my", "the", "a", "an",
            "current", "selected", "this", "that", "account", "accounts", "balance",
            "balances", "reconciliation", "shared", "savings", "saving", "please",
            "show", "tell", "me", "their", "his", "her", "for", "of", "to", "on",
            "in", "as", "at", "period", "month", "week", "year", "today", "now",
            "actual", "overall", "total", "card", "cards", "s"
        ]
        return normalizedPrompt
            .split(separator: " ")
            .map(String.init)
            .filter { filler.contains($0) == false }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func hasBalanceCue(_ normalizedPrompt: String) -> Bool {
        containsWholePhrase("balance", in: normalizedPrompt)
            || containsWholePhrase("balances", in: normalizedPrompt)
    }

    private func isStatementBalancePrompt(_ normalizedPrompt: String) -> Bool {
        containsAny(
            ["statement balance", "imported balance", "imported account balance", "bank balance"],
            in: normalizedPrompt
        )
    }

    private func isSafeReadPrompt(_ prompt: String) -> Bool {
        MarinaRoutePatternRegistry.isReadOnlyStep5Mutation(prompt) == nil
            && MarinaMutationIntentGuard().isMutationPrompt(prompt) == false
    }

    private func unique(_ targets: [BalanceTarget]) -> [BalanceTarget] {
        var seen: Set<String> = []
        return targets.filter { target in
            let key = "\(target.entityType.rawValue)|\(target.id.uuidString.lowercased())"
            return seen.insert(key).inserted
        }
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: #"([a-z0-9&])'s\b"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "[^a-z0-9\\s&]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func displayText(_ value: String) -> String {
        value
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + String($0.dropFirst()) }
            .joined(separator: " ")
    }

    private func containsAny(_ needles: [String], in haystack: String) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    private func containsWholePhrase(_ phrase: String, in normalizedPrompt: String) -> Bool {
        guard phrase.isEmpty == false else { return false }
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        return normalizedPrompt.range(of: #"(?<![a-z0-9])\#(escaped)(?![a-z0-9])"#, options: .regularExpression) != nil
    }

    private struct BalanceTarget: Equatable {
        let id: UUID
        let displayName: String
        let entityType: MarinaCandidateEntityTypeHint
        let relationship: MarinaRelationshipField
        let subject: MarinaSubject
        let measure: MarinaCandidateMeasure
        let amountField: MarinaAmountField?
        let routeKind: MarinaRouteIntentKind
        let choiceSubtitle: String
        let traceName: String
    }

    private struct DateDecision {
        let request: MarinaDateRangeRequest
        let source: MarinaDateSource
        let periodUnit: HomeQueryPeriodUnit
    }
}

@MainActor
struct MarinaTargetedDetailCanonicalizer {
    static let generatedSchemaName = "MarinaCanonicalDetail"

    private let balanceCanonicalizer = MarinaTargetedBalanceCanonicalizer()
    private let semanticAdapter = MarinaSemanticQueryAdapter()

    func interpretation(
        prompt: String,
        context: MarinaTurnContext
    ) -> MarinaTurnInterpretation? {
        if let balanceInterpretation = balanceCanonicalizer.interpretation(prompt: prompt, context: context) {
            return balanceInterpretation
        }

        let normalizedPrompt = normalized(prompt)
        guard normalizedPrompt.isEmpty == false,
              isSafeReadPrompt(prompt) else {
            return nil
        }

        if isActiveBudgetStatusPrompt(normalizedPrompt)
            || isIncomeStatusPrompt(normalizedPrompt)
            || containsWholePhrase("status", in: normalizedPrompt) {
            return statusInterpretation(prompt: prompt, normalizedPrompt: normalizedPrompt, context: context)
        }

        if hasLinkedCue(normalizedPrompt)
            || containsWholePhrase("linked", in: normalizedPrompt) {
            return linkedInterpretation(prompt: prompt, normalizedPrompt: normalizedPrompt, context: context)
        }

        if hasDueCue(normalizedPrompt) {
            return dueInterpretation(prompt: prompt, normalizedPrompt: normalizedPrompt, context: context)
        }

        if hasActivityCue(normalizedPrompt) {
            return activityInterpretation(prompt: prompt, normalizedPrompt: normalizedPrompt, context: context)
        }

        if hasRemainingCue(normalizedPrompt) {
            return remainingInterpretation(prompt: prompt, normalizedPrompt: normalizedPrompt, context: context)
        }

        return nil
    }

    private func statusInterpretation(
        prompt: String,
        normalizedPrompt: String,
        context: MarinaTurnContext
    ) -> MarinaTurnInterpretation? {
        if isActiveBudgetStatusPrompt(normalizedPrompt) {
            return queryInterpretation(
                query: activeBudgetStatusQuery(dateDecision: .none),
                prompt: prompt,
                traceName: "status.activeBudget"
            )
        }

        if isIncomeStatusPrompt(normalizedPrompt) {
            return queryInterpretation(
                query: incomeStatusQuery(
                    dateDecision: dateDecision(
                        prompt: prompt,
                        now: context.now,
                        defaultPeriodUnit: context.defaultPeriodUnit,
                        defaultPolicy: .currentPeriod
                    )
                ),
                prompt: prompt,
                traceName: "status.income"
            )
        }

        if containsWholePhrase("savings", in: normalizedPrompt)
            || containsWholePhrase("saving", in: normalizedPrompt) {
            let savingsMatches = exactMatches(
                in: normalizedPrompt,
                provider: context.provider,
                types: [.savingsAccount]
            )
            if savingsMatches.count > 1 {
                return clarificationInterpretation(
                    prompt: prompt,
                    kind: .ambiguousTarget,
                    message: "Which savings status should I check?",
                    traceName: "status.ambiguousSavings",
                    choices: savingsMatches.map {
                        choice(
                            title: $0.displayName,
                            subtitle: "Savings account status",
                            target: $0,
                            query: savingsStatusQuery(target: $0, dateDecision: .none),
                            prompt: prompt
                        )
                    }
                )
            }
            return queryInterpretation(
                query: savingsStatusQuery(target: savingsMatches.first, dateDecision: .none),
                prompt: prompt,
                traceName: "status.savings"
            )
        }

        let budgetMatches = exactMatches(
            in: normalizedPrompt,
            provider: context.provider,
            types: [.budget]
        )
        if let budget = singleOrClarifyTarget(
            budgetMatches,
            prompt: prompt,
            message: "Which budget status should I check?",
            traceName: "status.ambiguousBudget",
            query: { budgetStatusQuery(target: $0) }
        ) {
            return budget
        }
        if containsWholePhrase("budget", in: normalizedPrompt) {
            return queryInterpretation(
                query: activeBudgetStatusQuery(dateDecision: .none),
                prompt: prompt,
                traceName: "status.activeBudget"
            )
        }

        return missingDetailClarification(
            prompt: prompt,
            message: "Which status should I check?",
            traceName: "status.missingTarget",
            choices: [
                ("Active budget", "Current budget status", activeBudgetStatusQuery(dateDecision: .none)),
                ("Savings status", "Stored savings status", savingsStatusQuery(target: nil, dateDecision: .none)),
                (
                    "Income status",
                    "Actual versus planned income",
                    incomeStatusQuery(
                        dateDecision: dateDecision(
                            prompt: prompt,
                            now: context.now,
                            defaultPeriodUnit: context.defaultPeriodUnit,
                            defaultPolicy: .currentPeriod
                        )
                    )
                )
            ]
        )
    }

    private func linkedInterpretation(
        prompt: String,
        normalizedPrompt: String,
        context: MarinaTurnContext
    ) -> MarinaTurnInterpretation? {
        let budgetMatches = exactMatches(in: normalizedPrompt, provider: context.provider, types: [.budget])
        let activeBudget = activeBudgetTarget(provider: context.provider, now: context.now)
        let budget = budgetMatches.count == 1 ? budgetMatches.first : nil
        let membershipList = asksForBudgetMembershipList(normalizedPrompt)
        let memberMatches = exactMatches(in: normalizedPrompt, provider: context.provider, types: [.card, .preset])

        if membershipList {
            guard memberMatches.isEmpty == false else {
                return clarificationInterpretation(
                    prompt: prompt,
                    kind: .missingTarget,
                    message: "Which card or preset should I check across budgets?",
                    traceName: "linked.missingMember",
                    choices: targetChoices(
                        prompt: prompt,
                        targets: targets(provider: context.provider, types: [.card, .preset]).prefix(12).map { $0 },
                        subtitle: { "\($0.displayType) membership" },
                        query: { budgetMembershipQuery(member: $0, budget: nil) }
                    )
                )
            }
            if memberMatches.count > 1 {
                return clarificationInterpretation(
                    prompt: prompt,
                    kind: .ambiguousTarget,
                    message: "Which linked item should I check across budgets?",
                    traceName: "linked.ambiguousMember",
                    choices: targetChoices(
                        prompt: prompt,
                        targets: memberMatches,
                        subtitle: { "\($0.displayType) membership" },
                        query: { budgetMembershipQuery(member: $0, budget: nil) }
                    )
                )
            }
            guard let member = memberMatches.first else { return nil }
            return queryInterpretation(
                query: budgetMembershipQuery(member: member, budget: nil),
                prompt: prompt,
                traceName: "linked.membershipList"
            )
        }

        if memberMatches.isEmpty == false,
           (containsWholePhrase("is", in: normalizedPrompt) || containsWholePhrase("included", in: normalizedPrompt)) {
            guard budgetMatches.count <= 1 else {
                return clarificationInterpretation(
                    prompt: prompt,
                    kind: .ambiguousTarget,
                    message: "Which budget should I check for that linked item?",
                    traceName: "linked.ambiguousBudget",
                    choices: targetChoices(
                        prompt: prompt,
                        targets: budgetMatches,
                        subtitle: { "\($0.displayType) membership" },
                        query: { budgetMembershipQuery(member: memberMatches[0], budget: $0) }
                    )
                )
            }
            guard memberMatches.count == 1, let member = memberMatches.first else {
                return clarificationInterpretation(
                    prompt: prompt,
                    kind: .ambiguousTarget,
                    message: "Which linked item did you mean?",
                    traceName: "linked.ambiguousMember",
                    choices: targetChoices(
                        prompt: prompt,
                        targets: memberMatches,
                        subtitle: { "\($0.displayType) membership" },
                        query: { budgetMembershipQuery(member: $0, budget: budget ?? activeBudget) }
                    )
                )
            }
            return queryInterpretation(
                query: budgetMembershipQuery(member: member, budget: budget ?? activeBudget),
                prompt: prompt,
                traceName: "linked.membership"
            )
        }

        let detail = linkedBudgetDetail(normalizedPrompt)
        guard let detail else {
            return missingDetailClarification(
                prompt: prompt,
                message: "Which linked budget detail should I check?",
                traceName: "linked.missingDetail",
                choices: [
                    ("Linked cards", "Cards attached to a budget", budgetLinkedQuery(budget: budget ?? activeBudget, detail: .linkedCards)),
                    ("Linked presets", "Presets attached to a budget", budgetLinkedQuery(budget: budget ?? activeBudget, detail: .linkedPresets)),
                    ("Category limits", "Budget category limits", budgetLinkedQuery(budget: budget ?? activeBudget, detail: .categoryLimits))
                ]
            )
        }

        if budgetMatches.count > 1 {
            return clarificationInterpretation(
                prompt: prompt,
                kind: .ambiguousTarget,
                message: "Which budget should I check?",
                traceName: "linked.ambiguousBudget",
                choices: targetChoices(
                    prompt: prompt,
                    targets: budgetMatches,
                    subtitle: { "\($0.displayType) linked details" },
                    query: { budgetLinkedQuery(budget: $0, detail: detail) }
                )
            )
        }

        guard let resolvedBudget = budget ?? activeBudget else {
            return clarificationInterpretation(
                prompt: prompt,
                kind: .missingTarget,
                message: "Which budget should I check?",
                traceName: "linked.missingBudget",
                choices: targetChoices(
                    prompt: prompt,
                    targets: targets(provider: context.provider, types: [.budget]).prefix(12).map { $0 },
                    subtitle: { "\($0.displayType) linked details" },
                    query: { budgetLinkedQuery(budget: $0, detail: detail) }
                )
            )
        }

        return queryInterpretation(
            query: budgetLinkedQuery(budget: resolvedBudget, detail: detail),
            prompt: prompt,
            traceName: "linked.\(detail.rawValue)"
        )
    }

    private func dueInterpretation(
        prompt: String,
        normalizedPrompt: String,
        context: MarinaTurnContext
    ) -> MarinaTurnInterpretation? {
        let matches = exactMatches(
            in: normalizedPrompt,
            provider: context.provider,
            types: dueTargetTypes(normalizedPrompt)
        )
        if matches.count > 1 {
            return clarificationInterpretation(
                prompt: prompt,
                kind: .ambiguousTarget,
                message: "Which due item filter did you mean?",
                traceName: "due.ambiguousTarget",
                choices: targetChoices(
                    prompt: prompt,
                    targets: matches,
                    subtitle: { "\($0.displayType) due items" },
                    query: {
                        plannedDueQuery(
                            target: $0,
                            dateDecision: dateDecision(
                                prompt: prompt,
                                now: context.now,
                                defaultPeriodUnit: context.defaultPeriodUnit,
                                defaultPolicy: .explicitOnly
                            )
                        )
                    }
                )
            )
        }

        return queryInterpretation(
            query: plannedDueQuery(
                target: matches.first,
                dateDecision: dateDecision(
                    prompt: prompt,
                    now: context.now,
                    defaultPeriodUnit: context.defaultPeriodUnit,
                    defaultPolicy: .explicitOnly
                )
            ),
            prompt: prompt,
            traceName: "due.plannedRows"
        )
    }

    private func activityInterpretation(
        prompt: String,
        normalizedPrompt: String,
        context: MarinaTurnContext
    ) -> MarinaTurnInterpretation? {
        if containsWholePhrase("savings", in: normalizedPrompt)
            || containsWholePhrase("saving", in: normalizedPrompt) {
            let matches = exactMatches(in: normalizedPrompt, provider: context.provider, types: [.savingsAccount])
            if matches.count > 1 {
                return clarificationInterpretation(
                    prompt: prompt,
                    kind: .ambiguousTarget,
                    message: "Which savings account activity should I show?",
                    traceName: "activity.ambiguousSavings",
                    choices: targetChoices(
                        prompt: prompt,
                        targets: matches,
                        subtitle: { "\($0.displayType) activity" },
                        query: {
                            savingsActivityQuery(
                                target: $0,
                                dateDecision: dateDecision(
                                    prompt: prompt,
                                    now: context.now,
                                    defaultPeriodUnit: context.defaultPeriodUnit,
                                    defaultPolicy: .currentPeriod
                                )
                            )
                        }
                    )
                )
            }
            return queryInterpretation(
                query: savingsActivityQuery(
                    target: matches.first,
                    dateDecision: dateDecision(
                        prompt: prompt,
                        now: context.now,
                        defaultPeriodUnit: context.defaultPeriodUnit,
                        defaultPolicy: .currentPeriod
                    )
                ),
                prompt: prompt,
                traceName: "activity.savings"
            )
        }

        let allowedTypes = activityTargetTypes(normalizedPrompt)
        let matches = exactMatches(in: normalizedPrompt, provider: context.provider, types: allowedTypes)
        if matches.count > 1 {
            return clarificationInterpretation(
                prompt: prompt,
                kind: .ambiguousTarget,
                message: "Which activity did you mean?",
                traceName: "activity.ambiguousTarget",
                choices: targetChoices(
                    prompt: prompt,
                    targets: matches,
                    subtitle: { "\($0.displayType) activity" },
                    query: {
                        activityQuery(
                            target: $0,
                            dateDecision: dateDecision(
                                prompt: prompt,
                                now: context.now,
                                defaultPeriodUnit: context.defaultPeriodUnit,
                                defaultPolicy: activityDatePolicy(for: $0)
                            )
                        )
                    }
                )
            )
        }

        if let target = matches.first {
            return queryInterpretation(
                query: activityQuery(
                    target: target,
                    dateDecision: dateDecision(
                        prompt: prompt,
                        now: context.now,
                        defaultPeriodUnit: context.defaultPeriodUnit,
                        defaultPolicy: activityDatePolicy(for: target)
                    )
                ),
                prompt: prompt,
                traceName: "activity.\(target.traceName)"
            )
        }

        if containsAny(["transaction activity", "spending activity", "expense activity"], in: normalizedPrompt) {
            return queryInterpretation(
                query: transactionActivityQuery(
                    target: nil,
                    dateDecision: dateDecision(
                        prompt: prompt,
                        now: context.now,
                        defaultPeriodUnit: context.defaultPeriodUnit,
                        defaultPolicy: .explicitOnly
                    )
                ),
                prompt: prompt,
                traceName: "activity.transactions"
            )
        }

        return missingDetailClarification(
            prompt: prompt,
            message: "Which activity should I show?",
            traceName: "activity.missingTarget",
            choices: [
                (
                    "Savings activity",
                    "Savings ledger rows",
                    savingsActivityQuery(
                        target: nil,
                        dateDecision: dateDecision(
                            prompt: prompt,
                            now: context.now,
                            defaultPeriodUnit: context.defaultPeriodUnit,
                            defaultPolicy: .currentPeriod
                        )
                    )
                ),
                (
                    "Recent transactions",
                    "Workspace transaction activity",
                    transactionActivityQuery(
                        target: nil,
                        dateDecision: dateDecision(
                            prompt: prompt,
                            now: context.now,
                            defaultPeriodUnit: context.defaultPeriodUnit,
                            defaultPolicy: .explicitOnly
                        )
                    )
                )
            ]
        )
    }

    private func remainingInterpretation(
        prompt: String,
        normalizedPrompt: String,
        context: MarinaTurnContext
    ) -> MarinaTurnInterpretation? {
        if containsAny(["planned expense", "planned expenses", "bill", "bills", "due"], in: normalizedPrompt) {
            return dueInterpretation(prompt: prompt, normalizedPrompt: normalizedPrompt, context: context)
        }

        let categories = exactMatches(in: normalizedPrompt, provider: context.provider, types: [.category])
        if categories.count > 1 {
            return clarificationInterpretation(
                prompt: prompt,
                kind: .ambiguousTarget,
                message: "Which category remaining amount should I check?",
                traceName: "remaining.ambiguousCategory",
                choices: targetChoices(
                    prompt: prompt,
                    targets: categories,
                    subtitle: { "\($0.displayType) remaining" },
                    query: {
                        categoryRemainingQuery(
                            target: $0,
                            dateDecision: dateDecision(
                                prompt: prompt,
                                now: context.now,
                                defaultPeriodUnit: context.defaultPeriodUnit,
                                defaultPolicy: .currentPeriod
                            )
                        )
                    }
                )
            )
        }
        if let category = categories.first {
            return queryInterpretation(
                query: categoryRemainingQuery(
                    target: category,
                    dateDecision: dateDecision(
                        prompt: prompt,
                        now: context.now,
                        defaultPeriodUnit: context.defaultPeriodUnit,
                        defaultPolicy: .currentPeriod
                    )
                ),
                prompt: prompt,
                traceName: "remaining.category"
            )
        }

        let budgets = exactMatches(in: normalizedPrompt, provider: context.provider, types: [.budget])
        if budgets.count > 1 {
            return clarificationInterpretation(
                prompt: prompt,
                kind: .ambiguousTarget,
                message: "Which budget remaining amount should I check?",
                traceName: "remaining.ambiguousBudget",
                choices: targetChoices(
                    prompt: prompt,
                    targets: budgets,
                    subtitle: { "\($0.displayType) remaining" },
                    query: { budgetRemainingQuery(target: $0, now: context.now, defaultPeriodUnit: context.defaultPeriodUnit) }
                )
            )
        }
        if let budget = budgets.first {
            return queryInterpretation(
                query: budgetRemainingQuery(target: budget, now: context.now, defaultPeriodUnit: context.defaultPeriodUnit),
                prompt: prompt,
                traceName: "remaining.budget"
            )
        }

        if hasBudgetRemainingDomain(normalizedPrompt) {
            return queryInterpretation(
                query: safeSpendRemainingQuery(
                    dateDecision: dateDecision(
                        prompt: prompt,
                        now: context.now,
                        defaultPeriodUnit: context.defaultPeriodUnit,
                        defaultPolicy: .currentPeriod
                    )
                ),
                prompt: prompt,
                traceName: "remaining.safeSpend"
            )
        }

        return missingDetailClarification(
            prompt: prompt,
            message: "Which remaining amount should I check?",
            traceName: "remaining.missingTarget",
            choices: [
                (
                    "Remaining budget",
                    "Safe-spend remaining room",
                    safeSpendRemainingQuery(
                        dateDecision: dateDecision(
                            prompt: prompt,
                            now: context.now,
                            defaultPeriodUnit: context.defaultPeriodUnit,
                            defaultPolicy: .currentPeriod
                        )
                    )
                )
            ]
        )
    }

    private func activeBudgetStatusQuery(dateDecision: DateDecision) -> MarinaSemanticQuery {
        let routeIntent = MarinaRouteIntent(
            kind: .activeBudget,
            subject: .budgets,
            operation: .lookupDetails,
            measure: .remainingBudget,
            grouping: nil,
            targetTypes: [.budget],
            requestedDetail: .status,
            responseShape: .summaryCard,
            preferredExecutorRoute: .composableWorkspace
        )
        return MarinaSemanticQuery(
            subject: .budgets,
            operation: .lookupDetails,
            dateRange: dateDecision.request,
            responseShape: .summaryCard,
            requestedDetail: .status,
            routeIntent: routeIntent
        )
    }

    private func incomeStatusQuery(dateDecision: DateDecision) -> MarinaSemanticQuery {
        let routeIntent = MarinaRouteIntent(
            kind: .incomePlannedVsActual,
            subject: .income,
            operation: .sum,
            measure: .income,
            grouping: nil,
            targetTypes: [],
            requestedDetail: .status,
            responseShape: .summaryCard,
            preferredExecutorRoute: .workspaceAggregation
        )
        return MarinaSemanticQuery(
            subject: .income,
            operation: .sum,
            amountField: .incomeAmount,
            dateRange: dateDecision.request,
            incomeStatusScope: .all,
            responseShape: .summaryCard,
            requestedDetail: .status,
            routeIntent: routeIntent
        )
    }

    private func savingsStatusQuery(target: DetailTarget?, dateDecision: DateDecision) -> MarinaSemanticQuery {
        let filters = target.map { [filter(for: $0)] } ?? []
        return MarinaSemanticQuery(
            subject: .savingsAccounts,
            operation: .lookupDetails,
            filters: filters,
            amountField: .savingsAmount,
            dateRange: dateDecision.request,
            responseShape: .summaryCard,
            requestedDetail: .status,
            routeIntent: MarinaRouteIntent(
                kind: .savingsStatus,
                subject: .savingsAccounts,
                operation: .lookupDetails,
                measure: .savings,
                grouping: nil,
                targetTypes: target.map { [$0.entityType] } ?? [],
                requestedDetail: .status,
                responseShape: .summaryCard,
                preferredExecutorRoute: .homeAdapter
            )
        )
    }

    private func budgetStatusQuery(target: DetailTarget) -> MarinaSemanticQuery {
        let dateDecision = target.range.map {
            DateDecision(
                request: MarinaDateRangeRequest(role: .primary, rawText: target.displayName, resolvedRange: $0, periodUnit: nil),
                source: .promptExplicit,
                periodUnit: nil
            )
        } ?? .none
        return MarinaSemanticQuery(
            subject: .budgets,
            operation: .lookupDetails,
            filters: [filter(for: target)],
            dateRange: dateDecision.request,
            responseShape: .summaryCard,
            requestedDetail: .status,
            routeIntent: MarinaRouteIntent(
                kind: .budgetSummary,
                subject: .budgets,
                operation: .lookupDetails,
                measure: .remainingBudget,
                grouping: nil,
                targetTypes: [.budget],
                requestedDetail: .status,
                responseShape: .summaryCard,
                preferredExecutorRoute: .composableWorkspace
            )
        )
    }

    private func budgetLinkedQuery(budget: DetailTarget?, detail: MarinaSemanticRequestedDetail) -> MarinaSemanticQuery {
        let routeKind: MarinaRouteIntentKind
        switch detail {
        case .linkedCards:
            routeKind = .budgetLinkedCards
        case .linkedPresets:
            routeKind = .budgetLinkedPresets
        case .categoryLimits:
            routeKind = .budgetCategoryLimits
        default:
            routeKind = .budgetMembership
        }
        return MarinaSemanticQuery(
            subject: .budgets,
            operation: .lookupDetails,
            filters: budget.map { [filter(for: $0)] } ?? [],
            dateRange: budget?.range.map {
                MarinaDateRangeRequest(role: .primary, rawText: budget?.displayName, resolvedRange: $0, periodUnit: nil)
            },
            responseShape: .relationshipList,
            requestedDetail: detail,
            routeIntent: MarinaRouteIntent(
                kind: routeKind,
                subject: .budgets,
                operation: .lookupDetails,
                measure: .remainingBudget,
                grouping: nil,
                targetTypes: [.budget],
                requestedDetail: detail,
                responseShape: .relationshipList,
                preferredExecutorRoute: .composableWorkspace
            )
        )
    }

    private func budgetMembershipQuery(member: DetailTarget, budget: DetailTarget?) -> MarinaSemanticQuery {
        let filters = [budget, member].compactMap { $0 }.map { filter(for: $0) }
        let targetTypes = filters.compactMap(\.entityTypeHint)
        return MarinaSemanticQuery(
            subject: .budgets,
            operation: .lookupDetails,
            filters: filters,
            dateRange: budget?.range.map {
                MarinaDateRangeRequest(role: .primary, rawText: budget?.displayName, resolvedRange: $0, periodUnit: nil)
            },
            responseShape: .membershipStatus,
            requestedDetail: .membership,
            routeIntent: MarinaRouteIntent(
                kind: .budgetMembership,
                subject: .budgets,
                operation: .lookupDetails,
                measure: .remainingBudget,
                grouping: nil,
                targetTypes: targetTypes,
                requestedDetail: .membership,
                responseShape: budget == nil ? .relationshipList : .membershipStatus,
                preferredExecutorRoute: .composableWorkspace
            )
        )
    }

    private func plannedDueQuery(target: DetailTarget?, dateDecision: DateDecision) -> MarinaSemanticQuery {
        let grouping = MarinaGrouping(dimension: .transaction, rawText: "due rows")
        return MarinaSemanticQuery(
            subject: .plannedExpenses,
            operation: .list,
            filters: target.map { [filter(for: $0)] } ?? [],
            amountField: .effectivePlannedAmount,
            dateRange: dateDecision.request,
            grouping: grouping,
            ranking: MarinaRanking(direction: .newest, limit: 10, rawText: "due"),
            limit: 10,
            responseShape: .rankedList,
            requestedDetail: .date,
            routeIntent: MarinaRouteIntent(
                kind: .plannedExpenseRows,
                subject: .plannedExpenses,
                operation: .listRows,
                measure: .presetAmount,
                grouping: .transaction,
                targetTypes: target.map { [$0.entityType] } ?? [],
                requestedDetail: .date,
                responseShape: .rankedList,
                preferredExecutorRoute: .workspaceAggregation
            )
        )
    }

    private func savingsActivityQuery(target: DetailTarget?, dateDecision: DateDecision) -> MarinaSemanticQuery {
        let grouping = MarinaGrouping(dimension: .savingsLedgerEntry, rawText: "activity")
        return MarinaSemanticQuery(
            subject: .savingsLedgerEntries,
            operation: .list,
            filters: target.map { [filter(for: $0)] } ?? [],
            amountField: .savingsAmount,
            dateRange: dateDecision.request,
            grouping: grouping,
            ranking: MarinaRanking(direction: .newest, limit: 10, rawText: "activity"),
            limit: 10,
            responseShape: .rankedList,
            requestedDetail: .general,
            routeIntent: MarinaRouteIntent(
                kind: .savingsActivity,
                subject: .savingsLedgerEntries,
                operation: .listRows,
                measure: .savingsMovement,
                grouping: .savingsLedgerEntry,
                targetTypes: target.map { [$0.entityType] } ?? [],
                requestedDetail: .general,
                responseShape: .rankedList,
                preferredExecutorRoute: .workspaceAggregation
            )
        )
    }

    private func activityQuery(target: DetailTarget, dateDecision: DateDecision) -> MarinaSemanticQuery {
        switch target.entityType {
        case .allocationAccount:
            return reconciliationActivityQuery(target: target, dateDecision: dateDecision)
        case .savingsAccount:
            return savingsActivityQuery(target: target, dateDecision: dateDecision)
        default:
            return transactionActivityQuery(target: target, dateDecision: dateDecision)
        }
    }

    private func transactionActivityQuery(target: DetailTarget?, dateDecision: DateDecision) -> MarinaSemanticQuery {
        let grouping = MarinaGrouping(dimension: .transaction, rawText: "activity")
        return MarinaSemanticQuery(
            subject: .variableExpenses,
            operation: .list,
            filters: target.map { [filter(for: $0)] } ?? [],
            amountField: .budgetImpactAmount,
            dateRange: dateDecision.request,
            grouping: grouping,
            ranking: MarinaRanking(direction: .newest, limit: 10, rawText: "activity"),
            limit: 10,
            responseShape: .rankedList,
            requestedDetail: .general,
            routeIntent: MarinaRouteIntent(
                kind: .recentTransactionRows,
                subject: .variableExpenses,
                operation: .listRows,
                measure: .transactionAmount,
                grouping: .transaction,
                targetTypes: target.map { [$0.entityType] } ?? [],
                requestedDetail: .general,
                responseShape: .rankedList,
                preferredExecutorRoute: .composableWorkspace
            )
        )
    }

    private func reconciliationActivityQuery(target: DetailTarget, dateDecision: DateDecision) -> MarinaSemanticQuery {
        let grouping = MarinaGrouping(dimension: .allocationAccount, rawText: "activity")
        return MarinaSemanticQuery(
            subject: .reconciliationAccounts,
            operation: .list,
            filters: [filter(for: target)],
            amountField: .reconciliationBalance,
            dateRange: dateDecision.request,
            grouping: grouping,
            ranking: MarinaRanking(direction: .newest, limit: 10, rawText: "activity"),
            limit: 10,
            responseShape: .rankedList,
            requestedDetail: .general,
            routeIntent: MarinaRouteIntent(
                kind: .reconciliationActivity,
                subject: .reconciliationAccounts,
                operation: .listRows,
                measure: .reconciliationBalance,
                grouping: .allocationAccount,
                targetTypes: [.allocationAccount],
                requestedDetail: .general,
                responseShape: .rankedList,
                preferredExecutorRoute: .composableWorkspace
            )
        )
    }

    private func categoryRemainingQuery(target: DetailTarget, dateDecision: DateDecision) -> MarinaSemanticQuery {
        MarinaSemanticQuery(
            subject: .budgets,
            operation: .lookupDetails,
            filters: [filter(for: target)],
            amountField: .budgetImpactAmount,
            dateRange: dateDecision.request,
            responseShape: .summaryCard,
            requestedDetail: .amount,
            routeIntent: MarinaRouteIntent(
                kind: .budgetCategoryLimit,
                subject: .budgets,
                operation: .lookupDetails,
                measure: .remainingBudget,
                grouping: nil,
                targetTypes: [.category],
                requestedDetail: .amount,
                responseShape: .summaryCard,
                preferredExecutorRoute: .composableWorkspace
            )
        )
    }

    private func budgetRemainingQuery(
        target: DetailTarget,
        now: Date,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> MarinaSemanticQuery {
        safeSpendRemainingQuery(
            dateDecision: target.range.map {
                DateDecision(
                    request: MarinaDateRangeRequest(role: .primary, rawText: target.displayName, resolvedRange: $0, periodUnit: defaultPeriodUnit),
                    source: .promptExplicit,
                    periodUnit: defaultPeriodUnit
                )
            } ?? dateDecision(
                prompt: target.displayName,
                now: now,
                defaultPeriodUnit: defaultPeriodUnit,
                defaultPolicy: .currentPeriod
            )
        )
    }

    private func safeSpendRemainingQuery(dateDecision: DateDecision) -> MarinaSemanticQuery {
        MarinaSemanticQuery(
            subject: .budgets,
            operation: .lookupDetails,
            amountField: nil,
            dateRange: dateDecision.request,
            responseShape: .summaryCard,
            requestedDetail: .amount,
            routeIntent: MarinaRouteIntent(
                kind: .generic,
                subject: .budgets,
                operation: .lookupDetails,
                measure: .remainingBudget,
                grouping: nil,
                targetTypes: [],
                requestedDetail: .amount,
                responseShape: .summaryCard,
                preferredExecutorRoute: .homeAdapter
            )
        )
    }

    private func queryInterpretation(
        query: MarinaSemanticQuery,
        prompt: String,
        traceName: String
    ) -> MarinaTurnInterpretation {
        let candidate = semanticAdapter.compatibilityCandidate(
            from: query,
            prompt: prompt,
            source: .deterministic
        )
        return MarinaTurnInterpretation(
            result: .query(query),
            compatibilityCandidate: candidate,
            repairSummary: "canonicalDetail:\(traceName)",
            generatedSchemaName: Self.generatedSchemaName
        )
    }

    private func clarificationInterpretation(
        prompt: String,
        kind: MarinaClarificationKind,
        message: String,
        traceName: String,
        choices: [MarinaClarificationChoice]
    ) -> MarinaTurnInterpretation {
        let candidate = detailCandidate(prompt: prompt)
        return MarinaTurnInterpretation(
            result: .clarification(
                MarinaTypedClarification(
                    kind: kind,
                    message: message,
                    candidate: candidate,
                    patchSlot: .target,
                    choices: choices
                )
            ),
            compatibilityCandidate: candidate,
            repairSummary: "canonicalDetail:\(traceName)",
            generatedSchemaName: Self.generatedSchemaName
        )
    }

    private func missingDetailClarification(
        prompt: String,
        message: String,
        traceName: String,
        choices: [(title: String, subtitle: String, query: MarinaSemanticQuery)]
    ) -> MarinaTurnInterpretation {
        clarificationInterpretation(
            prompt: prompt,
            kind: .missingTarget,
            message: message,
            traceName: traceName,
            choices: choices.map { item in
                let resumeCandidate = semanticAdapter.compatibilityCandidate(
                    from: item.query,
                    prompt: prompt,
                    source: .deterministic
                )
                return MarinaClarificationChoice(
                    title: item.title,
                    subtitle: item.subtitle,
                    entityRole: .primaryTarget,
                    entityTypeHint: nil,
                    patchSlot: .target,
                    rawValue: item.title,
                    sourceID: nil,
                    resumeIntent: MarinaClarificationResumeIntent(
                        candidate: resumeCandidate,
                        semanticQuery: item.query
                    )
                )
            }
        )
    }

    private func singleOrClarifyTarget(
        _ matches: [DetailTarget],
        prompt: String,
        message: String,
        traceName: String,
        query: (DetailTarget) -> MarinaSemanticQuery
    ) -> MarinaTurnInterpretation? {
        if matches.count == 1, let target = matches.first {
            return queryInterpretation(
                query: query(target),
                prompt: prompt,
                traceName: traceName.replacingOccurrences(of: "ambiguous", with: "target")
            )
        }
        if matches.count > 1 {
            return clarificationInterpretation(
                prompt: prompt,
                kind: .ambiguousTarget,
                message: message,
                traceName: traceName,
                choices: targetChoices(
                    prompt: prompt,
                    targets: matches,
                    subtitle: { "\($0.displayType) status" },
                    query: query
                )
            )
        }
        return nil
    }

    private func targetChoices(
        prompt: String,
        targets: [DetailTarget],
        subtitle: (DetailTarget) -> String,
        query: (DetailTarget) -> MarinaSemanticQuery
    ) -> [MarinaClarificationChoice] {
        targets.map {
            choice(
                title: $0.displayName,
                subtitle: subtitle($0),
                target: $0,
                query: query($0),
                prompt: prompt
            )
        }
    }

    private func choice(
        title: String,
        subtitle: String,
        target: DetailTarget,
        query: MarinaSemanticQuery,
        prompt: String
    ) -> MarinaClarificationChoice {
        let resumeCandidate = semanticAdapter.compatibilityCandidate(
            from: query,
            prompt: prompt,
            source: .deterministic
        )
        return MarinaClarificationChoice(
            title: title,
            subtitle: subtitle,
            entityRole: .primaryTarget,
            entityTypeHint: target.entityType,
            patchSlot: .target,
            rawValue: target.displayName,
            sourceID: target.sourceID,
            resumeIntent: MarinaClarificationResumeIntent(
                candidate: resumeCandidate,
                semanticQuery: query
            )
        )
    }

    private func filter(for target: DetailTarget) -> MarinaFilter {
        MarinaFilter(
            role: .primaryTarget,
            relationship: target.relationship,
            value: target.displayName,
            matchMode: target.sourceID == nil ? .freeText : .exact,
            entityTypeHint: target.entityType,
            allowedEntityTypeHints: [target.entityType],
            sourceID: target.sourceID
        )
    }

    private func detailCandidate(prompt: String) -> MarinaQueryPlanCandidate {
        MarinaQueryPlanCandidate(
            requestFamily: .analytics,
            source: .deterministic,
            rawPrompt: prompt,
            operation: .lookupDetails,
            measure: .remainingBudget,
            responseShapeHint: .clarification,
            confidence: .high
        )
    }

    private func exactMatches(
        in normalizedPrompt: String,
        provider: MarinaDataProvider,
        types: [MarinaCandidateEntityTypeHint]
    ) -> [DetailTarget] {
        let matches = targets(provider: provider, types: types).filter { target in
            let normalizedName = normalized(target.displayName)
            guard normalizedName.isEmpty == false else { return false }
            return containsWholePhrase(normalizedName, in: normalizedPrompt)
        }
        return unique(matches)
    }

    private func targets(
        provider: MarinaDataProvider,
        types: [MarinaCandidateEntityTypeHint]
    ) -> [DetailTarget] {
        var values: [DetailTarget] = []
        if types.contains(.budget) {
            values.append(contentsOf: provider.fetchAllBudgets().map {
                DetailTarget(
                    displayName: $0.name,
                    entityType: .budget,
                    relationship: .budget,
                    sourceID: $0.id,
                    range: HomeQueryDateRange(startDate: $0.startDate, endDate: $0.endDate)
                )
            })
        }
        if types.contains(.card) {
            values.append(contentsOf: provider.fetchAllCards().map {
                DetailTarget(displayName: $0.name, entityType: .card, relationship: .card, sourceID: $0.id)
            })
        }
        if types.contains(.preset) {
            values.append(contentsOf: provider.fetchAllPresets().filter { $0.isArchived == false }.map {
                DetailTarget(displayName: $0.title, entityType: .preset, relationship: .preset, sourceID: $0.id)
            })
        }
        if types.contains(.category) {
            values.append(contentsOf: provider.fetchAllCategories().map {
                DetailTarget(displayName: $0.name, entityType: .category, relationship: .category, sourceID: $0.id)
            })
        }
        if types.contains(.savingsAccount) {
            values.append(contentsOf: provider.fetchAllSavingsAccounts().map {
                DetailTarget(displayName: $0.name, entityType: .savingsAccount, relationship: .savingsAccount, sourceID: $0.id)
            })
        }
        if types.contains(.allocationAccount) {
            values.append(contentsOf: provider.fetchAllAllocationAccounts().filter { $0.isArchived == false }.map {
                DetailTarget(displayName: $0.name, entityType: .allocationAccount, relationship: .allocationAccount, sourceID: $0.id)
            })
        }
        if types.contains(.merchant) {
            let merchants = provider.fetchAllVariableExpenses().map(\.descriptionText)
            values.append(contentsOf: uniqueStrings(merchants).map {
                DetailTarget(displayName: $0, entityType: .merchant, relationship: .merchant, sourceID: nil)
            })
        }
        return unique(values)
    }

    private func activeBudgetTarget(
        provider: MarinaDataProvider,
        now: Date
    ) -> DetailTarget? {
        let day = Calendar(identifier: .gregorian).startOfDay(for: now)
        return provider.fetchAllBudgets()
            .filter {
                Calendar(identifier: .gregorian).startOfDay(for: $0.startDate) <= day
                    && Calendar(identifier: .gregorian).startOfDay(for: $0.endDate) >= day
            }
            .sorted { lhs, rhs in
                if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .first
            .map {
                DetailTarget(
                    displayName: $0.name,
                    entityType: .budget,
                    relationship: .budget,
                    sourceID: $0.id,
                    range: HomeQueryDateRange(startDate: $0.startDate, endDate: $0.endDate)
                )
            }
    }

    private func dateDecision(
        prompt: String,
        now: Date,
        defaultPeriodUnit: HomeQueryPeriodUnit,
        defaultPolicy: MarinaCanonicalDateDefaultPolicy
    ) -> DateDecision {
        if let explicitRange = MarinaDateRangeTextResolver(
            calendar: Calendar(identifier: .gregorian),
            nowProvider: { now }
        ).resolve(prompt, defaultPeriodUnit: defaultPeriodUnit) {
            return DateDecision(
                request: MarinaDateRangeRequest(
                    role: .primary,
                    rawText: prompt,
                    resolvedRange: explicitRange,
                    periodUnit: defaultPeriodUnit
                ),
                source: .promptExplicit,
                periodUnit: defaultPeriodUnit
            )
        }

        guard defaultPolicy == .currentPeriod else { return .none }
        let range = currentPeriodRange(containing: now, unit: defaultPeriodUnit)
        return DateDecision(
            request: MarinaDateRangeRequest(
                role: .primary,
                rawText: "current \(defaultPeriodUnit.rawValue)",
                resolvedRange: range,
                periodUnit: defaultPeriodUnit
            ),
            source: .defaultBudgetingPeriod,
            periodUnit: defaultPeriodUnit
        )
    }

    private func currentPeriodRange(
        containing date: Date,
        unit: HomeQueryPeriodUnit
    ) -> HomeQueryDateRange {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let component: Calendar.Component
        switch unit {
        case .day:
            component = .day
        case .week:
            component = .weekOfYear
        case .month:
            component = .month
        case .quarter:
            return currentQuarterRange(containing: date, calendar: calendar)
        case .year:
            component = .year
        }
        guard let interval = calendar.dateInterval(of: component, for: date) else {
            return HomeQueryDateRange(startDate: calendar.startOfDay(for: date), endDate: date)
        }
        return HomeQueryDateRange(startDate: interval.start, endDate: interval.end.addingTimeInterval(-1))
    }

    private func currentQuarterRange(containing date: Date, calendar: Calendar) -> HomeQueryDateRange {
        let components = calendar.dateComponents([.year, .month], from: date)
        let month = components.month ?? 1
        let quarterStartMonth = ((month - 1) / 3) * 3 + 1
        let start = calendar.date(from: DateComponents(year: components.year, month: quarterStartMonth, day: 1)) ?? date
        let end = calendar.date(byAdding: DateComponents(month: 3, second: -1), to: start) ?? start
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func isActiveBudgetStatusPrompt(_ normalizedPrompt: String) -> Bool {
        containsAny(["active budget", "current budget", "selected budget"], in: normalizedPrompt)
            && (containsWholePhrase("status", in: normalizedPrompt)
                || normalizedPrompt.hasPrefix("what is")
                || normalizedPrompt.hasPrefix("which is")
                || normalizedPrompt.hasPrefix("show"))
    }

    private func isIncomeStatusPrompt(_ normalizedPrompt: String) -> Bool {
        guard containsWholePhrase("income", in: normalizedPrompt) else { return false }
        return containsWholePhrase("status", in: normalizedPrompt)
            || containsAny(["planned vs actual", "actual vs planned", "actual versus planned", "planned versus actual", "actual vs expected", "expected vs actual", "doing vs planned", "doing versus planned"], in: normalizedPrompt)
            || (containsAny(["planned", "actual", "expected"], in: normalizedPrompt) && containsAny([" vs ", " versus ", "doing"], in: " \(normalizedPrompt) "))
    }

    private func hasLinkedCue(_ normalizedPrompt: String) -> Bool {
        containsAny(["linked", "included", "attached", "using", "use "], in: normalizedPrompt)
            && containsAny(["budget", "budgets", "card", "cards", "preset", "presets", "category limit", "category limits"], in: normalizedPrompt)
    }

    private func hasDueCue(_ normalizedPrompt: String) -> Bool {
        containsWholePhrase("due", in: normalizedPrompt)
            || containsAny(["upcoming bill", "upcoming bills", "upcoming expense", "upcoming expenses", "what bills", "next bill", "next expense"], in: normalizedPrompt)
    }

    private func hasActivityCue(_ normalizedPrompt: String) -> Bool {
        containsWholePhrase("activity", in: normalizedPrompt)
            || containsAny(["recent activity", "ledger activity"], in: normalizedPrompt)
    }

    private func hasRemainingCue(_ normalizedPrompt: String) -> Bool {
        containsWholePhrase("remaining", in: normalizedPrompt)
            || containsAny(["how much is left", "how much can i still spend", "can i still spend", "safe spend", "still spend", "left in"], in: normalizedPrompt)
    }

    private func hasBudgetRemainingDomain(_ normalizedPrompt: String) -> Bool {
        containsAny(["budget", "safe spend", "can i spend", "still spend", "spend today", "remaining room"], in: normalizedPrompt)
    }

    private func linkedBudgetDetail(_ normalizedPrompt: String) -> MarinaSemanticRequestedDetail? {
        if containsAny(["card", "cards"], in: normalizedPrompt) { return .linkedCards }
        if containsAny(["preset", "presets"], in: normalizedPrompt) { return .linkedPresets }
        if containsAny(["category limit", "category limits", "spending limit", "spending limits"], in: normalizedPrompt) { return .categoryLimits }
        return nil
    }

    private func asksForBudgetMembershipList(_ normalizedPrompt: String) -> Bool {
        containsAny(["which budget", "which budgets", "what budget", "what budgets", "budgets use", "budgets using", "budgets include"], in: normalizedPrompt)
    }

    private func dueTargetTypes(_ normalizedPrompt: String) -> [MarinaCandidateEntityTypeHint] {
        if containsAny(["card", "cards"], in: normalizedPrompt) { return [.card] }
        if containsAny(["category", "categories"], in: normalizedPrompt) { return [.category] }
        if containsAny(["preset", "presets"], in: normalizedPrompt) { return [.preset] }
        return [.preset, .category, .card]
    }

    private func activityTargetTypes(_ normalizedPrompt: String) -> [MarinaCandidateEntityTypeHint] {
        if containsAny(["card", "cards"], in: normalizedPrompt) { return [.card] }
        if containsAny(["category", "categories"], in: normalizedPrompt) { return [.category] }
        if containsAny(["merchant", "merchants"], in: normalizedPrompt) { return [.merchant] }
        if containsAny(["reconciliation", "allocation", "shared"], in: normalizedPrompt) { return [.allocationAccount] }
        return [.allocationAccount, .card, .category, .merchant, .savingsAccount]
    }

    private func activityDatePolicy(for target: DetailTarget) -> MarinaCanonicalDateDefaultPolicy {
        switch target.entityType {
        case .allocationAccount, .savingsAccount:
            return .currentPeriod
        default:
            return .explicitOnly
        }
    }

    private func isSafeReadPrompt(_ prompt: String) -> Bool {
        MarinaRoutePatternRegistry.isReadOnlyStep5Mutation(prompt) == nil
            && MarinaMutationIntentGuard().isMutationPrompt(prompt) == false
    }

    private func unique(_ targets: [DetailTarget]) -> [DetailTarget] {
        var seen: Set<String> = []
        return targets.filter {
            let key = "\($0.entityType.rawValue)|\($0.sourceID?.uuidString.lowercased() ?? normalized($0.displayName))"
            return seen.insert(key).inserted
        }
    }

    private func uniqueStrings(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .filter { seen.insert(normalized($0)).inserted }
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: #"([a-z0-9&])'s\b"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "[^a-z0-9\\s&]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func containsAny(_ needles: [String], in haystack: String) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    private func containsWholePhrase(_ phrase: String, in normalizedPrompt: String) -> Bool {
        guard phrase.isEmpty == false else { return false }
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        return normalizedPrompt.range(of: #"(?<![a-z0-9])\#(escaped)(?![a-z0-9])"#, options: .regularExpression) != nil
    }

    private struct DetailTarget: Equatable {
        let displayName: String
        let entityType: MarinaCandidateEntityTypeHint
        let relationship: MarinaRelationshipField
        let sourceID: UUID?
        let range: HomeQueryDateRange?

        init(
            displayName: String,
            entityType: MarinaCandidateEntityTypeHint,
            relationship: MarinaRelationshipField,
            sourceID: UUID?,
            range: HomeQueryDateRange? = nil
        ) {
            self.displayName = displayName
            self.entityType = entityType
            self.relationship = relationship
            self.sourceID = sourceID
            self.range = range
        }

        var displayType: String {
            switch entityType {
            case .category:
                return "Category"
            case .merchant:
                return "Merchant"
            case .expense:
                return "Expense"
            case .card:
                return "Card"
            case .budget:
                return "Budget"
            case .preset:
                return "Preset"
            case .incomeSource:
                return "Income source"
            case .allocationAccount:
                return "Reconciliation account"
            case .savingsAccount:
                return "Savings account"
            case .transaction:
                return "Transaction"
            case .workspace:
                return "Workspace"
            }
        }

        var traceName: String {
            switch entityType {
            case .allocationAccount:
                return "reconciliation"
            case .savingsAccount:
                return "savings"
            default:
                return entityType.rawValue
            }
        }
    }

    private struct DateDecision {
        let request: MarinaDateRangeRequest?
        let source: MarinaDateSource
        let periodUnit: HomeQueryPeriodUnit?

        static let none = DateDecision(request: nil, source: .none, periodUnit: nil)
    }
}

@MainActor
struct MarinaCanonicalQueryRewriter {
    static let generatedSchemaName = "MarinaCanonicalQuery"

    private let compiler: MarinaCanonicalQueryCompiler
    private let detailCanonicalizer = MarinaTargetedDetailCanonicalizer()
    private let semanticAdapter = MarinaSemanticQueryAdapter()

    init(compiler: MarinaCanonicalQueryCompiler? = nil) {
        self.compiler = compiler ?? MarinaCanonicalQueryCompiler()
    }

    func rewrite(
        prompt: String,
        interpretation: MarinaTurnInterpretation,
        candidate: MarinaQueryPlanCandidate,
        context: MarinaTurnContext
    ) -> MarinaTurnInterpretation? {
        guard interpretation.generatedSchemaName != Self.generatedSchemaName,
              interpretation.generatedSchemaName != "legacyContractAdapter",
              interpretation.generatedSchemaName != MarinaTargetedDetailCanonicalizer.generatedSchemaName,
              interpretation.generatedSchemaName != MarinaTargetedBalanceCanonicalizer.generatedSchemaName else { return nil }
        if let detailInterpretation = detailCanonicalizer.interpretation(prompt: prompt, context: context) {
            return detailInterpretation
        }
        guard case .success(let decision) = compiler.compile(prompt: prompt, context: context),
              shouldUseCanonical(decision: decision, interpretation: interpretation, candidate: candidate),
              let semanticQuery = decision.query.semanticQuery else {
            return nil
        }
        return makeInterpretation(from: decision, semanticQuery: semanticQuery, prompt: prompt)
    }

    func deterministicInterpretation(
        prompt: String,
        context: MarinaTurnContext
    ) -> MarinaTurnInterpretation? {
        if let detailInterpretation = detailCanonicalizer.interpretation(prompt: prompt, context: context) {
            return detailInterpretation
        }
        guard case .success(let decision) = compiler.compile(prompt: prompt, context: context),
              let semanticQuery = decision.query.semanticQuery else {
            return nil
        }
        return makeInterpretation(from: decision, semanticQuery: semanticQuery, prompt: prompt)
    }

    private func makeInterpretation(
        from decision: MarinaCanonicalQueryDecision,
        semanticQuery: MarinaSemanticQuery,
        prompt: String
    ) -> MarinaTurnInterpretation {
        let candidate = semanticAdapter.compatibilityCandidate(
            from: semanticQuery,
            prompt: prompt,
            source: .deterministic
        )
        let assumptionSummary = decision.query.assumptions.isEmpty
            ? nil
            : decision.query.assumptions.joined(separator: "|")
        return MarinaTurnInterpretation(
            result: .query(semanticQuery),
            compatibilityCandidate: candidate,
            repairSummary: [decision.reason, assumptionSummary].compactMap { $0 }.joined(separator: ";"),
            generatedSchemaName: Self.generatedSchemaName
        )
    }

    private func shouldUseCanonical(
        decision: MarinaCanonicalQueryDecision,
        interpretation: MarinaTurnInterpretation,
        candidate: MarinaQueryPlanCandidate
    ) -> Bool {
        switch interpretation.result {
        case .unsupported, .clarification:
            return true
        case .query(let query):
            if modelHasGenericSubjectFilter(query: query, modelName: decision.query.modelName) {
                return true
            }
            if modelHasGenericSubjectMention(candidate: candidate, modelName: decision.query.modelName) {
                return true
            }
            if decision.query.dateSource == .defaultBudgetingPeriod,
               query.dateRange == nil,
               candidate.timeScopes.isEmpty {
                return true
            }
            if decision.query.modelName == "Income",
               query.incomeStatusScope != decision.query.statusScope {
                return true
            }
            return false
        }
    }

    private func modelHasGenericSubjectFilter(
        query: MarinaSemanticQuery,
        modelName: String
    ) -> Bool {
        query.filters.contains { filter in
            MarinaCanonicalQueryCompiler.isGenericTargetValue(filter.value, modelName: modelName)
        }
    }

    private func modelHasGenericSubjectMention(
        candidate: MarinaQueryPlanCandidate,
        modelName: String
    ) -> Bool {
        candidate.entityMentions.contains { mention in
            guard let rawText = mention.rawText else { return false }
            return MarinaCanonicalQueryCompiler.isGenericTargetValue(rawText, modelName: modelName)
        }
    }
}
