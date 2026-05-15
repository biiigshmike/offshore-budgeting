import Foundation

enum MarinaEntityKind: String, Codable, Equatable, Sendable {
    case persistentModel
    case virtual
    case derived
}

enum MarinaFieldRole: String, Codable, Equatable, Sendable {
    case searchable
    case display
    case amount
    case date
    case derivedAmount
    case storage
}

struct MarinaFieldDescriptor: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let role: MarinaFieldRole
    let notes: String?

    init(
        _ name: String,
        role: MarinaFieldRole,
        notes: String? = nil
    ) {
        self.id = "\(role.rawValue):\(name)"
        self.name = name
        self.role = role
        self.notes = notes
    }
}

struct MarinaRelationshipDescriptor: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let targetEntityName: String?
    let supportsFiltering: Bool
    let notes: String?

    init(
        _ name: String,
        targetEntityName: String? = nil,
        supportsFiltering: Bool = true,
        notes: String? = nil
    ) {
        self.id = name
        self.name = name
        self.targetEntityName = targetEntityName
        self.supportsFiltering = supportsFiltering
        self.notes = notes
    }
}

enum MarinaOperationSupport: String, Codable, Equatable, Sendable {
    case supported
    case missing
    case unsupported
}

struct MarinaOperationDescriptor: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let support: MarinaOperationSupport
    let reason: String?

    init(
        _ name: String,
        support: MarinaOperationSupport,
        reason: String? = nil
    ) {
        self.id = "\(support.rawValue):\(name)"
        self.name = name
        self.support = support
        self.reason = reason
    }
}

struct MarinaWorkspaceScopeDescriptor: Codable, Equatable, Sendable {
    let path: String
    let isMandatory: Bool
    let notes: String?

    init(path: String, isMandatory: Bool = true, notes: String? = nil) {
        self.path = path
        self.isMandatory = isMandatory
        self.notes = notes
    }
}

struct MarinaEntityDescriptor: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let entityName: String
    let displayName: String
    let kind: MarinaEntityKind
    let lookupObjectType: MarinaLookupObjectType?
    let fields: [MarinaFieldDescriptor]
    let relationships: [MarinaRelationshipDescriptor]
    let operations: [MarinaOperationDescriptor]
    let workspaceScope: MarinaWorkspaceScopeDescriptor
    let isSearchable: Bool
    let isQueryable: Bool
    let isAggregatable: Bool
    let canBeTargetFilter: Bool
    let canBeRelationshipFilter: Bool
    let contributesToDerivedMetrics: Bool

    var displayFields: [String] {
        fields.filter { $0.role == .display || $0.role == .searchable }.map(\.name)
    }

    var searchableFields: [String] {
        fields.filter { $0.role == .searchable }.map(\.name)
    }

    var amountFields: [String] {
        fields.filter { $0.role == .amount || $0.role == .derivedAmount }.map(\.name)
    }

    var dateFields: [String] {
        fields.filter { $0.role == .date }.map(\.name)
    }

    var supportedOperations: [String] {
        operations.filter { $0.support == .supported }.map(\.name)
    }

    var missingOperations: [String] {
        operations.filter { $0.support == .missing }.map(\.name)
    }

    var unsupportedOperations: [String] {
        operations.filter { $0.support == .unsupported }.map(\.name)
    }

    init(
        entityName: String,
        displayName: String? = nil,
        kind: MarinaEntityKind = .persistentModel,
        lookupObjectType: MarinaLookupObjectType? = nil,
        displayFields: [String],
        searchableFields: [String]? = nil,
        amountFields: [String] = [],
        derivedAmountFields: [String] = [],
        dateFields: [String] = [],
        workspaceScope: MarinaWorkspaceScopeDescriptor,
        relationships: [MarinaRelationshipDescriptor],
        isSearchable: Bool,
        isQueryable: Bool,
        isAggregatable: Bool,
        canBeTargetFilter: Bool,
        canBeRelationshipFilter: Bool,
        contributesToDerivedMetrics: Bool,
        supportedOperations: [String],
        missingOperations: [String],
        unsupportedOperations: [String]
    ) {
        self.id = entityName
        self.entityName = entityName
        self.displayName = displayName ?? entityName
        self.kind = kind
        self.lookupObjectType = lookupObjectType

        let searchable = searchableFields ?? (isSearchable ? displayFields : [])
        var descriptors: [MarinaFieldDescriptor] = displayFields.map { field in
            MarinaFieldDescriptor(field, role: searchable.contains(field) ? .searchable : .display)
        }
        descriptors.append(contentsOf: amountFields.map { MarinaFieldDescriptor($0, role: .amount) })
        descriptors.append(contentsOf: derivedAmountFields.map { MarinaFieldDescriptor($0, role: .derivedAmount) })
        descriptors.append(contentsOf: dateFields.map { MarinaFieldDescriptor($0, role: .date) })
        self.fields = descriptors

        self.workspaceScope = workspaceScope
        self.relationships = relationships
        self.isSearchable = isSearchable
        self.isQueryable = isQueryable
        self.isAggregatable = isAggregatable
        self.canBeTargetFilter = canBeTargetFilter
        self.canBeRelationshipFilter = canBeRelationshipFilter
        self.contributesToDerivedMetrics = contributesToDerivedMetrics
        self.operations =
            supportedOperations.map { MarinaOperationDescriptor($0, support: .supported) }
            + missingOperations.map { MarinaOperationDescriptor($0, support: .missing) }
            + unsupportedOperations.map { MarinaOperationDescriptor($0, support: .unsupported) }
    }

    func capabilityRecord() -> MarinaEntityCapabilityRecord {
        MarinaEntityCapabilityRecord(
            id: entityName,
            entityName: entityName,
            displayFields: displayFields,
            amountFields: amountFields,
            dateFields: dateFields,
            workspaceScope: workspaceScope.path,
            relationships: relationships.map(\.name),
            isSearchable: isSearchable,
            isQueryable: isQueryable,
            isAggregatable: isAggregatable,
            canBeTargetFilter: canBeTargetFilter,
            canBeRelationshipFilter: canBeRelationshipFilter,
            contributesToDerivedMetrics: contributesToDerivedMetrics,
            supportedOperations: supportedOperations,
            missingOperations: missingOperations,
            intentionallyUnsupportedOperations: unsupportedOperations,
            questionCapabilities: questionCapabilities()
        )
    }

    private func questionCapabilities() -> MarinaEntityQuestionCapabilities {
        MarinaEntityQuestionCapabilities(
            find: isSearchable ? .supported : .intentionallyUnsupported,
            summarize: isQueryable ? .supported : (contributesToDerivedMetrics ? .derived : .intentionallyUnsupported),
            aggregate: isAggregatable ? .supported : (contributesToDerivedMetrics ? .derived : .intentionallyUnsupported),
            filterBy: canBeTargetFilter ? .supported : .intentionallyUnsupported,
            compareOverTime: supportedOperations.contains("compare") ? .supported : (missingOperations.contains { $0.lowercased().contains("compare") } ? .gap : .intentionallyUnsupported),
            rank: supportedOperations.contains("rank") ? .supported : .intentionallyUnsupported,
            nextLatestPrevious: supportedOperations.contains("nextLatestPrevious") ? .supported : (missingOperations.contains { $0.lowercased().contains("next") } ? .gap : .intentionallyUnsupported),
            explainDerivedValues: contributesToDerivedMetrics ? .derived : .intentionallyUnsupported,
            balanceStatus: supportedOperations.contains("balance") ? .supported : (missingOperations.contains { $0.lowercased().contains("balance") || $0.lowercased().contains("status") } ? .gap : .intentionallyUnsupported),
            remainingAvailable: missingOperations.contains { $0.lowercased().contains("remaining") || $0.lowercased().contains("available") } ? .gap : .intentionallyUnsupported,
            projectedActualPlanned: supportedOperations.contains { $0.lowercased().contains("planned") || $0.lowercased().contains("actual") || $0.lowercased().contains("projected") } ? .supported : (missingOperations.contains { $0.lowercased().contains("planned") || $0.lowercased().contains("actual") || $0.lowercased().contains("projected") } ? .gap : .intentionallyUnsupported)
        )
    }
}

struct MarinaEntityCatalog: Codable, Equatable, Sendable {
    let descriptors: [MarinaEntityDescriptor]

    static let current = MarinaEntityCatalog(descriptors: Self.makeDescriptors())

    var persistentModelEntityNames: Set<String> {
        Set(descriptors.filter { $0.kind == .persistentModel }.map(\.entityName))
    }

    var virtualDescriptors: [MarinaEntityDescriptor] {
        descriptors.filter { $0.kind == .virtual || $0.kind == .derived }
    }

    func descriptor(for entityName: String) -> MarinaEntityDescriptor? {
        descriptors.first { $0.entityName == entityName }
    }

    func descriptor(for lookupObjectType: MarinaLookupObjectType) -> MarinaEntityDescriptor? {
        descriptors.first { $0.lookupObjectType == lookupObjectType }
    }

    func capabilityRecords() -> [MarinaEntityCapabilityRecord] {
        descriptors.map { $0.capabilityRecord() }
    }

    private static func makeDescriptors() -> [MarinaEntityDescriptor] {
        [
            descriptor("Workspace", lookup: .workspace, display: ["name", "hexColor"], scope: "self.id", relationships: ["owns workspace graph"], searchable: true, queryable: true, aggregatable: false, target: false, relationship: true, derived: true, supported: ["lookupDetails", "linkedObjectSummary"], missing: ["crossWorkspaceComparison"], unsupported: ["total", "average", "rank"]),
            descriptor("Budget", lookup: .budget, display: ["name"], dates: ["startDate", "endDate"], scope: "workspace", relationships: ["cardLinks", "presetLinks", "categoryLimits"], searchable: true, queryable: true, aggregatable: false, target: true, relationship: true, derived: true, supported: ["lookupDetails", "linkedObjectSummary", "derivedSpendSummary"], missing: ["remainingAvailable", "plannedActualProjected"], unsupported: ["directAmountAggregation"]),
            descriptor("BudgetCategoryLimit", display: ["category.name"], amounts: ["minAmount", "maxAmount"], scope: "budget.workspace/category.workspace", relationships: ["budget", "category"], searchable: false, queryable: true, aggregatable: false, target: false, relationship: true, derived: true, supported: ["linkedObjectSummary"], missing: ["remainingAvailable"], unsupported: ["spendAggregation"]),
            descriptor("Card", lookup: .card, display: ["name", "theme", "effect"], scope: "workspace", relationships: ["budgetLinks", "plannedExpenses", "variableExpenses", "income", "preset defaults"], searchable: true, queryable: true, aggregatable: false, target: true, relationship: true, derived: true, supported: ["lookupDetails", "total", "average", "compare", "rank", "filter"], missing: ["balanceStatus"], unsupported: ["directAmountAggregation"]),
            descriptor("BudgetCardLink", display: ["budget.name", "card.name"], scope: "budget.workspace/card.workspace", relationships: ["budget", "card"], searchable: false, queryable: false, aggregatable: false, target: false, relationship: true, derived: true, supported: ["linkedObjectSummary"], missing: [], unsupported: ["standaloneLookup", "aggregation"]),
            descriptor("BudgetPresetLink", display: ["budget.name", "preset.title"], scope: "budget.workspace/preset.workspace", relationships: ["budget", "preset"], searchable: false, queryable: false, aggregatable: false, target: false, relationship: true, derived: true, supported: ["linkedObjectSummary"], missing: [], unsupported: ["standaloneLookup", "aggregation"]),
            descriptor("Category", lookup: .category, display: ["name", "hexColor"], scope: "workspace", relationships: ["expenses", "presets", "limits", "importRules"], searchable: true, queryable: true, aggregatable: false, target: true, relationship: true, derived: true, supported: ["lookupDetails", "total", "average", "compare", "rank", "share", "filter"], missing: ["remainingAvailable"], unsupported: ["directAmountAggregation"]),
            descriptor("Preset", lookup: .preset, display: ["title"], amounts: ["plannedAmount"], dates: ["schedule fields", "archivedAt"], scope: "workspace", relationships: ["defaultCard", "defaultCategory", "budgetLinks"], searchable: true, queryable: true, aggregatable: false, target: true, relationship: true, derived: true, supported: ["lookupDetails", "rank", "plannedSummary"], missing: ["nextOccurrence"], unsupported: ["actualSpendWithoutMaterializedRows"]),
            descriptor("PlannedExpense", lookup: .plannedExpense, display: ["title"], amounts: ["plannedAmount", "actualAmount"], derivedAmounts: ["effectiveAmount"], dates: ["expenseDate"], scope: "workspace", relationships: ["card", "category", "allocation", "settlement", "savingsLedgerEntry"], searchable: true, queryable: true, aggregatable: true, target: true, relationship: true, derived: true, supported: ["lookupDetails", "listRows", "rank", "plannedAggregation"], missing: ["nextLatestPrevious"], unsupported: ["actualAmountZeroAsActualZero"]),
            descriptor("VariableExpense", lookup: .variableExpense, display: ["descriptionText"], amounts: ["amount"], derivedAmounts: ["spendingAmount", "ledgerSignedAmount", "budgetImpact"], dates: ["transactionDate"], scope: "workspace", relationships: ["card", "category", "allocation", "settlement", "savingsLedgerEntry"], searchable: true, queryable: true, aggregatable: true, target: true, relationship: true, derived: true, supported: ["lookupDetails", "total", "listRows", "rank", "filter"], missing: ["minMax", "countByObject"], unsupported: ["usingLedgerAmountForBudgetImpact"]),
            descriptor("AllocationAccount", lookup: .reconciliationAccount, display: ["name", "hexColor"], dates: ["archivedAt"], scope: "workspace", relationships: ["allocations", "settlements"], searchable: true, queryable: true, aggregatable: false, target: true, relationship: true, derived: true, supported: ["lookupDetails", "rank", "allocatedSpend"], missing: ["accountBalanceRoute"], unsupported: ["savingsTreatment"]),
            descriptor("ExpenseAllocation", lookup: .expenseAllocation, display: ["linked expense title"], amounts: ["allocatedAmount"], dates: ["createdAt", "updatedAt", "linked expense date"], scope: "workspace", relationships: ["account", "expense", "plannedExpense"], searchable: true, queryable: true, aggregatable: true, target: false, relationship: true, derived: true, supported: ["lookupDetails", "allocatedSpendSource"], missing: ["directTotals"], unsupported: ["standalonePrimaryTarget"]),
            descriptor("AllocationSettlement", lookup: .reconciliationItem, display: ["note"], amounts: ["amount"], dates: ["date"], scope: "workspace", relationships: ["account", "expense", "plannedExpense"], searchable: true, queryable: true, aggregatable: true, target: false, relationship: true, derived: true, supported: ["lookupDetails"], missing: ["settlementTotals"], unsupported: ["savingsMirrorBehavior"]),
            descriptor("IncomeSeries", lookup: .incomeSeries, display: ["source"], amounts: ["amount"], dates: ["startDate", "endDate", "schedule fields"], scope: "workspace", relationships: ["incomes"], searchable: true, queryable: true, aggregatable: false, target: true, relationship: true, derived: true, supported: ["lookupDetails"], missing: ["recurrenceExplanation"], unsupported: ["receivedIncomeAggregation"]),
            descriptor("SavingsAccount", lookup: .savingsAccount, display: ["name"], amounts: ["total"], dates: ["createdAt", "updatedAt", "autoCaptureThroughDate"], scope: "workspace", relationships: ["ledgerEntries"], searchable: true, queryable: true, aggregatable: false, target: true, relationship: true, derived: true, supported: ["lookupDetails", "balance"], missing: ["firstClassBalanceStatus", "projectedActual"], unsupported: ["mutatingFromStoredTotalOnly"]),
            descriptor("SavingsLedgerEntry", lookup: .savingsLedgerEntry, display: ["note", "kindRaw"], amounts: ["amount"], dates: ["date", "periodStartDate", "periodEndDate"], scope: "workspace", relationships: ["account", "expense", "plannedExpense"], searchable: true, queryable: true, aggregatable: true, target: true, relationship: true, derived: true, supported: ["lookupDetails", "rank"], missing: ["sumAverageCompareByAccount"], unsupported: ["legacyReconciliationSavingsMirror"]),
            descriptor("ImportMerchantRule", lookup: .importMerchantRule, display: ["merchantKey", "preferredName"], dates: ["createdAt", "updatedAt"], scope: "workspace", relationships: ["preferredCategory"], searchable: true, queryable: true, aggregatable: false, target: false, relationship: false, derived: true, supported: ["lookupDetails"], missing: ["ruleManagementParity"], unsupported: ["financialAggregation"]),
            descriptor("AssistantAliasRule", lookup: .assistantAliasRule, display: ["aliasKey", "targetValue", "entityTypeRaw"], dates: ["createdAt", "updatedAt"], scope: "workspace", relationships: [], searchable: true, queryable: true, aggregatable: false, target: false, relationship: false, derived: true, supported: ["lookupDetails"], missing: ["staleAliasDiagnostics"], unsupported: ["financialAggregation"]),
            descriptor("Income", lookup: .income, display: ["source"], amounts: ["amount"], dates: ["date"], scope: "workspace", relationships: ["series", "card"], searchable: true, queryable: true, aggregatable: true, target: true, relationship: true, derived: true, supported: ["lookupDetails", "total", "average", "compare", "rank"], missing: ["plannedVsActualSummary"], unsupported: ["spendingTreatment"]),
            descriptor("Virtual: Merchant", kind: .virtual, display: ["normalized expense/import text"], amounts: ["expense amount"], dates: ["expense date"], scope: "source expense workspace", relationships: ["variable expenses", "import rules"], searchable: true, queryable: true, aggregatable: false, target: true, relationship: true, derived: true, supported: ["lookupDetails", "total", "compare", "rank", "filter"], missing: ["average", "count"], unsupported: ["storedIdentityAssumption"]),
            descriptor("Virtual: IncomeSource", kind: .virtual, display: ["Income.source", "IncomeSeries.source"], amounts: ["income amount"], dates: ["income/series dates"], scope: "source workspace", relationships: ["income", "incomeSeries"], searchable: true, queryable: true, aggregatable: false, target: true, relationship: true, derived: true, supported: ["lookupDetails", "total", "average", "compare", "rank"], missing: ["plannedVsActualSourceSummary"], unsupported: ["seriesAsReceivedIncome"]),
            descriptor("Virtual: Uncategorized", kind: .virtual, display: ["nil category label"], amounts: ["expense amount"], dates: ["expense date"], scope: "source expense workspace", relationships: ["nil category expenses"], searchable: true, queryable: true, aggregatable: false, target: true, relationship: true, derived: true, supported: ["category bucket summaries"], missing: ["explicitTargetedFilter"], unsupported: ["assumingStoredCategory"]),
            descriptor("Virtual: EffectivePlannedExpenseAmount", kind: .derived, display: ["actualAmount", "plannedAmount"], amounts: ["effectiveAmount"], scope: "source planned expense workspace", relationships: ["plannedExpense"], searchable: false, queryable: true, aggregatable: true, target: false, relationship: false, derived: true, supported: ["plannedAggregation"], missing: [], unsupported: ["actualAmountZeroAsActualZero"]),
            descriptor("Virtual: ActualSavings", kind: .derived, display: ["actual savings"], amounts: ["actualSavings"], dates: ["period range"], scope: "workspace savings context", relationships: ["savingsLedgerEntries", "income", "expenses"], searchable: false, queryable: true, aggregatable: false, target: false, relationship: false, derived: true, supported: ["lookupDetails", "balance"], missing: ["projectedActual"], unsupported: ["storedTotalAsOnlySource"])
        ]
    }

    private static func descriptor(
        _ entityName: String,
        kind: MarinaEntityKind = .persistentModel,
        lookup: MarinaLookupObjectType? = nil,
        display: [String],
        amounts: [String] = [],
        derivedAmounts: [String] = [],
        dates: [String] = [],
        scope: String,
        relationships: [String],
        searchable: Bool,
        queryable: Bool,
        aggregatable: Bool,
        target: Bool,
        relationship: Bool,
        derived: Bool,
        supported: [String],
        missing: [String],
        unsupported: [String]
    ) -> MarinaEntityDescriptor {
        MarinaEntityDescriptor(
            entityName: entityName,
            kind: kind,
            lookupObjectType: lookup,
            displayFields: display,
            amountFields: amounts,
            derivedAmountFields: derivedAmounts,
            dateFields: dates,
            workspaceScope: MarinaWorkspaceScopeDescriptor(path: scope),
            relationships: relationships.map { MarinaRelationshipDescriptor($0, supportsFiltering: relationship) },
            isSearchable: searchable,
            isQueryable: queryable,
            isAggregatable: aggregatable,
            canBeTargetFilter: target,
            canBeRelationshipFilter: relationship,
            contributesToDerivedMetrics: derived,
            supportedOperations: supported,
            missingOperations: missing,
            unsupportedOperations: unsupported
        )
    }
}
