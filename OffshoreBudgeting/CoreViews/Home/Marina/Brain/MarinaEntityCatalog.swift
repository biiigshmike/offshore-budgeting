import Foundation

nonisolated enum MarinaFieldKey: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case id
    case name
    case title
    case amount
    case plannedAmount
    case actualAmount
    case effectiveAmount
    case budgetImpact
    case projectedBudgetImpact
    case ledgerSignedAmount
    case plannedIncomeTotal
    case actualIncomeTotal
    case plannedExpenseProjectedTotal
    case plannedExpenseActualTotal
    case plannedExpenseEffectiveTotal
    case variableExpenseTotal
    case unifiedExpenseTotal
    case maximumSavings
    case projectedSavings
    case actualSavings
    case incomeAmount
    case savingsTotal
    case reconciliationBalance
    case date
    case startDate
    case endDate
    case transactionDate
    case expenseDate
    case createdAt
    case updatedAt
    case merchantText
    case descriptionText
    case source
    case note
    case kind
    case frequency
    case interval
    case weeklyWeekday
    case monthlyDayOfMonth
    case monthlyIsLastDay
    case yearlyMonth
    case yearlyDayOfMonth
    case color
    case archivedState
    case isPlanned
    case isException
}

nonisolated enum MarinaRelationshipKey: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case workspace
    case budget
    case card
    case category
    case preset
    case incomeSource
    case incomeSeries
    case savingsAccount
    case reconciliationAccount
    case allocationAccount
    case plannedExpense
    case variableExpense
}

nonisolated enum MarinaValueType: String, Codable, Equatable, Hashable, Sendable {
    case text
    case money
    case number
    case date
    case boolean
    case color
    case relationship
}

nonisolated enum MarinaQueryVerb: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case list
    case fetch
    case count
    case search
    case filter
    case sum
    case average
    case compare
    case group
    case rank
    case sort
    case forecast
    case whatIf
}

nonisolated struct MarinaFieldDescriptor: Equatable, Sendable {
    let key: MarinaFieldKey
    let displayName: String
    let aliases: [String]
    let valueType: MarinaValueType
    let isSearchable: Bool
    let isFilterable: Bool
    let isGroupable: Bool
    let isSortable: Bool
    let isAggregatable: Bool
}

nonisolated struct MarinaRelationshipDescriptor: Equatable, Sendable {
    let key: MarinaRelationshipKey
    let displayName: String
    let aliases: [String]
    let targetEntity: MarinaSemanticEntity?
    let isFilterable: Bool
    let isGroupable: Bool
    let isSortable: Bool
    let isOptional: Bool
}

nonisolated struct MarinaMeasureDescriptor: Equatable, Sendable {
    let measure: MarinaSemanticMeasure
    let displayName: String
    let aliases: [String]
    let supportedEntities: Set<MarinaSemanticEntity>
    let requiredFields: Set<MarinaFieldKey>
    let requiredRelationships: Set<MarinaRelationshipKey>
}

nonisolated struct MarinaEntityDescriptor: Equatable, Sendable {
    let entity: MarinaSemanticEntity
    let displayName: String
    let aliases: [String]
    let fields: [MarinaFieldDescriptor]
    let relationships: [MarinaRelationshipDescriptor]
    let supportedOperations: Set<MarinaSemanticOperation>
    let supportedMeasures: Set<MarinaSemanticMeasure>
    let defaultDateField: MarinaFieldKey?
    let defaultAmountField: MarinaFieldKey?
    let defaultSearchFields: [MarinaFieldKey]
    let workspaceScoped: Bool
    let isInternalOnly: Bool
}

nonisolated struct MarinaUniversalSurfaceDescriptor: Equatable, Sendable {
    let surface: MarinaUniversalEntitySurface
    let displayName: String
    let aliases: [String]
    let fields: [MarinaFieldDescriptor]
    let relationships: [MarinaRelationshipDescriptor]
    let supportedOperations: Set<MarinaSemanticOperation>
    let supportedMeasures: Set<MarinaSemanticMeasure>
    let defaultDateField: MarinaFieldKey?
    let defaultAmountField: MarinaFieldKey?
    let defaultSearchFields: [MarinaFieldKey]
    let workspaceScoped: Bool
    let isInternalOnly: Bool

    init(
        surface: MarinaUniversalEntitySurface,
        displayName: String,
        aliases: [String],
        fields: [MarinaFieldDescriptor],
        relationships: [MarinaRelationshipDescriptor],
        supportedOperations: Set<MarinaSemanticOperation>,
        supportedMeasures: Set<MarinaSemanticMeasure>,
        defaultDateField: MarinaFieldKey?,
        defaultAmountField: MarinaFieldKey?,
        defaultSearchFields: [MarinaFieldKey],
        workspaceScoped: Bool,
        isInternalOnly: Bool
    ) {
        self.surface = surface
        self.displayName = displayName
        self.aliases = aliases
        self.fields = fields
        self.relationships = relationships
        self.supportedOperations = supportedOperations
        self.supportedMeasures = supportedMeasures
        self.defaultDateField = defaultDateField
        self.defaultAmountField = defaultAmountField
        self.defaultSearchFields = defaultSearchFields
        self.workspaceScoped = workspaceScoped
        self.isInternalOnly = isInternalOnly
    }

    init(surface: MarinaUniversalEntitySurface, entityDescriptor descriptor: MarinaEntityDescriptor) {
        self.init(
            surface: surface,
            displayName: descriptor.displayName,
            aliases: descriptor.aliases,
            fields: descriptor.fields,
            relationships: descriptor.relationships,
            supportedOperations: descriptor.supportedOperations,
            supportedMeasures: descriptor.supportedMeasures,
            defaultDateField: descriptor.defaultDateField,
            defaultAmountField: descriptor.defaultAmountField,
            defaultSearchFields: descriptor.defaultSearchFields,
            workspaceScoped: descriptor.workspaceScoped,
            isInternalOnly: descriptor.isInternalOnly
        )
    }
}

nonisolated enum MarinaCapabilityFailureReason: String, Codable, Equatable, Sendable {
    case missingEntityDescriptor
    case internalOnly
    case operationNotSupported
    case fieldNotSearchable
    case fieldNotFilterable
    case fieldNotGroupable
    case fieldNotSortable
    case measureNotAvailable
    case missingDateField
    case missingAmountField
    case ambiguousEntity
    case unresolvedEntity
    case readOnly
    case unsupportedCombination
}

nonisolated enum MarinaCapabilityResult: Equatable, Sendable {
    case supported
    case unsupported(MarinaCapabilityFailureReason)
}

nonisolated enum MarinaSwiftDataModel: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case workspace = "Workspace"
    case budget = "Budget"
    case budgetCategoryLimit = "BudgetCategoryLimit"
    case card = "Card"
    case budgetCardLink = "BudgetCardLink"
    case budgetPresetLink = "BudgetPresetLink"
    case category = "Category"
    case preset = "Preset"
    case plannedExpense = "PlannedExpense"
    case variableExpense = "VariableExpense"
    case allocationAccount = "AllocationAccount"
    case expenseAllocation = "ExpenseAllocation"
    case allocationSettlement = "AllocationSettlement"
    case savingsAccount = "SavingsAccount"
    case savingsLedgerEntry = "SavingsLedgerEntry"
    case importMerchantRule = "ImportMerchantRule"
    case assistantAliasRule = "AssistantAliasRule"
    case incomeSeries = "IncomeSeries"
    case marinaChatSession = "MarinaChatSession"
    case income = "Income"
}

nonisolated enum MarinaModelQueryClassification: String, Codable, CaseIterable, Equatable, Sendable {
    case publicEntity
    case publicProjectionSource
    case supportingData
    case resolverMemory
    case conversationOnly
}

nonisolated struct MarinaModelQueryDescriptor: Equatable, Sendable {
    let model: MarinaSwiftDataModel
    let classification: MarinaModelQueryClassification
    let semanticEntities: Set<MarinaSemanticEntity>
    let publicProjections: Set<MarinaSemanticProjection>

    var isPubliclyQueryable: Bool {
        classification == .publicEntity || classification == .publicProjectionSource
    }
}

struct MarinaEntityCatalog: Sendable {
    let entities: [MarinaSemanticEntity: MarinaEntityDescriptor]
    let measures: [MarinaSemanticMeasure: MarinaMeasureDescriptor]
    let projections: [MarinaSemanticEntity: Set<MarinaSemanticProjection>]
    let models: [MarinaSwiftDataModel: MarinaModelQueryDescriptor]

    init(
        entities: [MarinaSemanticEntity: MarinaEntityDescriptor] = MarinaEntityCatalog.defaultEntities,
        measures: [MarinaSemanticMeasure: MarinaMeasureDescriptor] = MarinaEntityCatalog.defaultMeasures,
        projections: [MarinaSemanticEntity: Set<MarinaSemanticProjection>] = MarinaEntityCatalog.defaultProjections,
        models: [MarinaSwiftDataModel: MarinaModelQueryDescriptor] = MarinaEntityCatalog.defaultModels
    ) {
        self.entities = entities
        self.measures = measures
        self.projections = projections
        self.models = models
    }

    func descriptor(for entity: MarinaSemanticEntity) -> MarinaEntityDescriptor? {
        entities[entity]
    }

    func descriptor(for surface: MarinaUniversalEntitySurface) -> MarinaUniversalSurfaceDescriptor? {
        switch surface {
        case let .semantic(entity):
            return descriptor(for: entity).map {
                MarinaUniversalSurfaceDescriptor(surface: surface, entityDescriptor: $0)
            }
        case .unifiedExpenses:
            return Self.unifiedExpensesDescriptor
        case .savingsLedgerEntries:
            return Self.savingsLedgerEntriesDescriptor
        case .reconciliationLedgerEntries:
            return Self.reconciliationLedgerEntriesDescriptor
        }
    }

    /// Returns the descriptor for the rows emitted by a public projection.
    /// Capability ownership remains with the public entity, while row
    /// validation, sorting, filtering, and pagination use the child surface.
    func executionDescriptor(
        for surface: MarinaUniversalEntitySurface,
        projection: MarinaSemanticProjection
    ) -> MarinaUniversalSurfaceDescriptor? {
        switch (surface, projection) {
        case (.semantic(.incomeSeries), .occurrences),
             (.semantic(.budget), .income):
            return descriptor(for: .semantic(.income))
        case (.semantic(.preset), .linkedBudgets):
            return descriptor(for: .semantic(.budget))
        case (.semantic(.budget), .linkedCards):
            return descriptor(for: .semantic(.card))
        case (.semantic(.budget), .linkedPresets):
            return descriptor(for: .semantic(.preset))
        case (.semantic(.budget), .expenses):
            return descriptor(for: .unifiedExpenses)
        default:
            return descriptor(for: surface)
        }
    }

    func measureDescriptor(for measure: MarinaSemanticMeasure) -> MarinaMeasureDescriptor? {
        measures[measure]
    }

    func modelDescriptor(for model: MarinaSwiftDataModel) -> MarinaModelQueryDescriptor? {
        models[model]
    }

    func supports(entity: MarinaSemanticEntity, projection: MarinaSemanticProjection) -> MarinaCapabilityResult {
        guard descriptor(for: entity) != nil else {
            return .unsupported(.missingEntityDescriptor)
        }
        guard projections[entity]?.contains(projection) == true else {
            return .unsupported(.unsupportedCombination)
        }
        return .supported
    }

    func supports(entity: MarinaSemanticEntity, operation: MarinaSemanticOperation) -> MarinaCapabilityResult {
        guard let descriptor = descriptor(for: entity) else {
            return .unsupported(.missingEntityDescriptor)
        }
        guard descriptor.isInternalOnly == false else {
            return .unsupported(.internalOnly)
        }
        guard descriptor.supportedOperations.contains(operation) else {
            return .unsupported(.operationNotSupported)
        }
        return .supported
    }

    func supports(entity: MarinaSemanticEntity, measure: MarinaSemanticMeasure) -> MarinaCapabilityResult {
        guard let descriptor = descriptor(for: entity) else {
            return .unsupported(.missingEntityDescriptor)
        }
        guard descriptor.isInternalOnly == false else {
            return .unsupported(.internalOnly)
        }
        guard descriptor.supportedMeasures.contains(measure),
              let measureDescriptor = measureDescriptor(for: measure),
              measureDescriptor.supportedEntities.contains(entity) else {
            return .unsupported(.measureNotAvailable)
        }
        return .supported
    }
}

extension MarinaEntityCatalog {
    static let defaultEntities: [MarinaSemanticEntity: MarinaEntityDescriptor] = {
        Dictionary(uniqueKeysWithValues: defaultEntityDescriptors.map { ($0.entity, $0) })
    }()

    static let defaultMeasures: [MarinaSemanticMeasure: MarinaMeasureDescriptor] = {
        Dictionary(uniqueKeysWithValues: defaultMeasureDescriptors.map { ($0.measure, $0) })
    }()

    static let defaultProjections: [MarinaSemanticEntity: Set<MarinaSemanticProjection>] = [
        .workspace: [.records],
        .budget: [.records, .summary, .income, .expenses, .linkedCards, .linkedPresets],
        .card: [.records],
        .plannedExpense: [.records],
        .variableExpense: [.records],
        .reconciliationAccount: [.records, .activity],
        .savingsAccount: [.records, .activity],
        .income: [.records],
        .incomeSeries: [.records, .occurrences],
        .category: [.records],
        .preset: [.records, .linkedBudgets]
    ]

    static let defaultModels: [MarinaSwiftDataModel: MarinaModelQueryDescriptor] = {
        let descriptors: [MarinaModelQueryDescriptor] = [
            model(.workspace, .publicEntity, entities: [.workspace], projections: [.records]),
            model(.budget, .publicEntity, entities: [.budget], projections: [.records, .summary, .income, .expenses, .linkedCards, .linkedPresets]),
            model(.budgetCategoryLimit, .publicProjectionSource, entities: [.budget, .category], projections: [.summary]),
            model(.card, .publicEntity, entities: [.card], projections: [.records]),
            model(.budgetCardLink, .publicProjectionSource, entities: [.budget, .card], projections: [.linkedCards]),
            model(.budgetPresetLink, .publicProjectionSource, entities: [.budget, .preset], projections: [.linkedPresets, .linkedBudgets]),
            model(.category, .publicEntity, entities: [.category], projections: [.records]),
            model(.preset, .publicEntity, entities: [.preset], projections: [.records, .linkedBudgets]),
            model(.plannedExpense, .publicEntity, entities: [.plannedExpense, .budget], projections: [.records, .expenses]),
            model(.variableExpense, .publicEntity, entities: [.variableExpense, .budget], projections: [.records, .expenses]),
            model(.allocationAccount, .publicEntity, entities: [.reconciliationAccount], projections: [.records, .activity]),
            model(.expenseAllocation, .publicProjectionSource, entities: [.reconciliationAccount], projections: [.activity]),
            model(.allocationSettlement, .publicProjectionSource, entities: [.reconciliationAccount], projections: [.activity]),
            model(.savingsAccount, .publicEntity, entities: [.savingsAccount], projections: [.records, .activity]),
            model(.savingsLedgerEntry, .publicProjectionSource, entities: [.savingsAccount], projections: [.activity]),
            model(.importMerchantRule, .supportingData),
            model(.assistantAliasRule, .resolverMemory),
            model(.incomeSeries, .publicEntity, entities: [.incomeSeries], projections: [.records, .occurrences]),
            model(.marinaChatSession, .conversationOnly),
            model(.income, .publicEntity, entities: [.income, .budget, .incomeSeries], projections: [.records, .income, .occurrences])
        ]
        return Dictionary(uniqueKeysWithValues: descriptors.map { ($0.model, $0) })
    }()

    static let unifiedExpensesDescriptor = MarinaUniversalSurfaceDescriptor(
        surface: .unifiedExpenses,
        displayName: "Unified Expenses",
        aliases: ["expenses", "spending", "planned and variable expenses"],
        fields: [
            field(.id, "ID", valueType: .text, filterable: true, sortable: true),
            field(.merchantText, "Merchant text", aliases: ["merchant", "store", "vendor", "description"], valueType: .text, searchable: true, filterable: true, sortable: true),
            field(.budgetImpact, "Budget impact", aliases: ["spend", "owned spend"], valueType: .money, filterable: true, sortable: true, aggregatable: true),
            field(.date, "Date", valueType: .date, filterable: true, sortable: true)
        ],
        relationships: [
            relationship(.workspace, "Workspace", targetEntity: .workspace, optional: true, groupable: false),
            relationship(.card, "Card", targetEntity: .card, optional: true),
            relationship(.category, "Category", targetEntity: .category, optional: true),
            relationship(.preset, "Source preset", aliases: ["preset"], targetEntity: .preset, optional: true),
            relationship(.budget, "Source budget", aliases: ["budget"], targetEntity: .budget, optional: true)
        ],
        supportedOperations: [.list, .count, .sum, .average, .last, .next, .group],
        supportedMeasures: [.budgetImpact],
        defaultDateField: .date,
        defaultAmountField: .budgetImpact,
        defaultSearchFields: [.merchantText],
        workspaceScoped: true,
        isInternalOnly: false
    )

    static let savingsLedgerEntriesDescriptor = MarinaUniversalSurfaceDescriptor(
        surface: .savingsLedgerEntries,
        displayName: "Savings Ledger Entries",
        aliases: ["savings ledger", "savings activity", "savings entries"],
        fields: [
            field(.id, "ID", valueType: .text, filterable: true, sortable: true),
            field(.amount, "Amount", valueType: .money, filterable: true, sortable: true, aggregatable: true),
            field(.date, "Date", valueType: .date, filterable: true, groupable: true, sortable: true),
            field(.note, "Note", valueType: .text, searchable: true, filterable: true, sortable: true),
            field(.kind, "Kind", aliases: ["entry kind"], valueType: .text, searchable: true, filterable: true, groupable: true, sortable: true),
            field(.startDate, "Period start date", valueType: .date, filterable: true, sortable: true),
            field(.endDate, "Period end date", valueType: .date, filterable: true, sortable: true),
            field(.createdAt, "Created at", valueType: .date, filterable: true, sortable: true),
            field(.updatedAt, "Updated at", valueType: .date, filterable: true, sortable: true)
        ],
        relationships: [
            relationship(.workspace, "Workspace", targetEntity: .workspace, optional: true, groupable: false),
            relationship(.savingsAccount, "Savings account", targetEntity: .savingsAccount, optional: true),
            relationship(.variableExpense, "Variable expense", targetEntity: .variableExpense, optional: true),
            relationship(.plannedExpense, "Planned expense", targetEntity: .plannedExpense, optional: true)
        ],
        supportedOperations: [.list, .count, .sum, .average, .last, .next, .group],
        supportedMeasures: [.amount],
        defaultDateField: .date,
        defaultAmountField: .amount,
        defaultSearchFields: [.note, .kind],
        workspaceScoped: true,
        isInternalOnly: false
    )

    static let reconciliationLedgerEntriesDescriptor = MarinaUniversalSurfaceDescriptor(
        surface: .reconciliationLedgerEntries,
        displayName: "Reconciliation Ledger Entries",
        aliases: ["reconciliation activity", "allocation activity", "allocation ledger"],
        fields: [
            field(.id, "ID", valueType: .text, filterable: true, sortable: true),
            field(.amount, "Amount", valueType: .money, filterable: true, sortable: true, aggregatable: true),
            field(.date, "Date", valueType: .date, filterable: true, groupable: true, sortable: true),
            field(.note, "Note", valueType: .text, searchable: true, filterable: true, sortable: true),
            field(.kind, "Kind", aliases: ["activity kind"], valueType: .text, searchable: true, filterable: true, groupable: true, sortable: true),
            field(.createdAt, "Created at", valueType: .date, filterable: true, sortable: true),
            field(.updatedAt, "Updated at", valueType: .date, filterable: true, sortable: true)
        ],
        relationships: [
            relationship(.workspace, "Workspace", targetEntity: .workspace, optional: true, groupable: false),
            relationship(.reconciliationAccount, "Reconciliation account", aliases: ["allocation account"], targetEntity: .reconciliationAccount, optional: true),
            relationship(.variableExpense, "Variable expense", targetEntity: .variableExpense, optional: true),
            relationship(.plannedExpense, "Planned expense", targetEntity: .plannedExpense, optional: true),
            relationship(.card, "Card", targetEntity: .card, optional: true),
            relationship(.category, "Category", targetEntity: .category, optional: true)
        ],
        supportedOperations: [.list, .count, .sum, .average, .last, .next, .group],
        supportedMeasures: [.amount],
        defaultDateField: .date,
        defaultAmountField: .amount,
        defaultSearchFields: [.note, .kind],
        workspaceScoped: true,
        isInternalOnly: false
    )

    private static let defaultEntityDescriptors: [MarinaEntityDescriptor] = [
        MarinaEntityDescriptor(
            entity: .workspace,
            displayName: "Workspace",
            aliases: ["workspace", "context"],
            fields: [
                field(.id, "ID", valueType: .text, filterable: true, sortable: true),
                field(.name, "Name", aliases: ["workspace name"], valueType: .text, searchable: true, filterable: true, sortable: true),
                field(.color, "Color", aliases: ["hex color"], valueType: .color, searchable: true, filterable: true)
            ],
            relationships: [],
            supportedOperations: [.list, .count],
            supportedMeasures: [.name, .color],
            defaultDateField: nil,
            defaultAmountField: nil,
            defaultSearchFields: [.name],
            workspaceScoped: false,
            isInternalOnly: false
        ),
        MarinaEntityDescriptor(
            entity: .budget,
            displayName: "Budget",
            aliases: ["budget", "period", "budget period"],
            fields: [
                field(.id, "ID", valueType: .text, filterable: true, sortable: true),
                field(.name, "Name", valueType: .text, searchable: true, filterable: true, sortable: true),
                field(.startDate, "Start date", valueType: .date, filterable: true, groupable: true, sortable: true),
                field(.endDate, "End date", valueType: .date, filterable: true, groupable: true, sortable: true),
                field(.budgetImpact, "Budget impact", aliases: ["spend", "spending"], valueType: .money, filterable: true, sortable: true, aggregatable: true),
                field(.projectedBudgetImpact, "Projected budget impact", aliases: ["projected spend"], valueType: .money, filterable: true, sortable: true, aggregatable: true),
                field(.plannedIncomeTotal, "Planned income total", valueType: .money, filterable: true, aggregatable: true),
                field(.actualIncomeTotal, "Actual income total", valueType: .money, filterable: true, aggregatable: true),
                field(.plannedExpenseProjectedTotal, "Projected planned-expense total", valueType: .money, filterable: true, aggregatable: true),
                field(.plannedExpenseActualTotal, "Recorded planned-expense total", valueType: .money, filterable: true, aggregatable: true),
                field(.plannedExpenseEffectiveTotal, "Effective planned-expense total", valueType: .money, filterable: true, aggregatable: true),
                field(.variableExpenseTotal, "Variable-expense total", valueType: .money, filterable: true, aggregatable: true),
                field(.unifiedExpenseTotal, "Unified expense total", valueType: .money, filterable: true, aggregatable: true),
                field(.maximumSavings, "Maximum savings", valueType: .money, filterable: true, aggregatable: true),
                field(.projectedSavings, "Projected savings", valueType: .money, filterable: true, aggregatable: true),
                field(.actualSavings, "Actual savings", valueType: .money, filterable: true, aggregatable: true)
            ],
            relationships: [
                relationship(.workspace, "Workspace", targetEntity: .workspace, optional: true),
                relationship(.card, "Linked card", aliases: ["card"], targetEntity: .card, optional: true),
                relationship(.category, "Category limit", aliases: ["category"], targetEntity: .category, optional: true),
                relationship(.preset, "Linked preset", aliases: ["preset"], targetEntity: .preset, optional: true)
            ],
            supportedOperations: [.list, .sum, .average, .compare, .forecast, .whatIf],
            supportedMeasures: [.budgetImpact, .projectedBudgetImpact, .plannedIncomeTotal, .actualIncomeTotal, .plannedExpenseProjectedTotal, .plannedExpenseActualTotal, .plannedExpenseEffectiveTotal, .variableExpenseTotal, .unifiedExpenseTotal, .maximumSavings, .projectedSavings, .actualSavings, .remainingRoom, .burnRate, .projectedSpend, .safeDailySpend, .paceDifference, .coverageRatio],
            defaultDateField: .startDate,
            defaultAmountField: .budgetImpact,
            defaultSearchFields: [.name],
            workspaceScoped: true,
            isInternalOnly: false
        ),
        MarinaEntityDescriptor(
            entity: .card,
            displayName: "Card",
            aliases: ["card", "account", "spending account"],
            fields: [
                field(.id, "ID", valueType: .text, filterable: true, sortable: true),
                field(.name, "Name", valueType: .text, searchable: true, filterable: true, sortable: true),
                field(.budgetImpact, "Budget impact", aliases: ["spend", "spending"], valueType: .money, filterable: true, groupable: true, sortable: true, aggregatable: true)
            ],
            relationships: [
                relationship(.workspace, "Workspace", targetEntity: .workspace, optional: true),
                relationship(.budget, "Budget", targetEntity: .budget, optional: true),
                relationship(.category, "Category", targetEntity: .category, optional: true),
                relationship(.preset, "Default preset", aliases: ["preset"], targetEntity: .preset, optional: true)
            ],
            supportedOperations: [.list, .count, .sum, .compare, .group],
            supportedMeasures: [.budgetImpact, .name],
            defaultDateField: nil,
            defaultAmountField: .budgetImpact,
            defaultSearchFields: [.name],
            workspaceScoped: true,
            isInternalOnly: false
        ),
        MarinaEntityDescriptor(
            entity: .plannedExpense,
            displayName: "Planned Expense",
            aliases: ["planned expense", "planned transaction", "expected expense"],
            fields: expenseFields(
                titleField: .title,
                titleName: "Title",
                dateField: .expenseDate,
                dateName: "Expense date"
            ) + [
                field(.amount, "Amount", valueType: .money, filterable: true, sortable: true, aggregatable: true),
                field(.plannedAmount, "Planned amount", valueType: .money, filterable: true, sortable: true, aggregatable: true),
                field(.actualAmount, "Actual amount", valueType: .money, filterable: true, sortable: true, aggregatable: true),
                field(.effectiveAmount, "Effective amount", valueType: .money, filterable: true, sortable: true, aggregatable: true),
                field(.projectedBudgetImpact, "Projected budget impact", aliases: ["projected owned spend"], valueType: .money, filterable: true, sortable: true, aggregatable: true)
            ],
            relationships: expenseRelationships() + [
                relationship(.preset, "Source preset", aliases: ["preset"], targetEntity: .preset, optional: true),
                relationship(.budget, "Source budget", aliases: ["budget"], targetEntity: .budget, optional: true)
            ],
            supportedOperations: [.list, .count, .sum, .average, .last, .next, .group],
            supportedMeasures: [.amount, .plannedAmount, .actualAmount, .effectiveAmount, .budgetImpact, .projectedBudgetImpact],
            defaultDateField: .expenseDate,
            defaultAmountField: .budgetImpact,
            defaultSearchFields: [.title, .merchantText],
            workspaceScoped: true,
            isInternalOnly: false
        ),
        MarinaEntityDescriptor(
            entity: .variableExpense,
            displayName: "Variable Expense",
            aliases: ["variable expense", "expense", "transaction", "merchant spend"],
            fields: expenseFields(
                titleField: .descriptionText,
                titleName: "Description",
                dateField: .transactionDate,
                dateName: "Transaction date"
            ) + [
                field(.amount, "Amount", valueType: .money, filterable: true, sortable: true, aggregatable: true),
                field(.ledgerSignedAmount, "Signed ledger amount", aliases: ["ledger amount", "signed amount"], valueType: .money, filterable: true, sortable: true, aggregatable: true),
                field(.kind, "Kind", aliases: ["transaction kind"], valueType: .text, searchable: true, filterable: true, groupable: true, sortable: true)
            ],
            relationships: expenseRelationships(),
            supportedOperations: [.list, .count, .sum, .average, .last, .group],
            supportedMeasures: [.amount, .budgetImpact, .ledgerSignedAmount],
            defaultDateField: .transactionDate,
            defaultAmountField: .budgetImpact,
            defaultSearchFields: [.descriptionText, .merchantText],
            workspaceScoped: true,
            isInternalOnly: false
        ),
        MarinaEntityDescriptor(
            entity: .reconciliationAccount,
            displayName: "Reconciliation Account",
            aliases: ["reconciliation account", "shared balance", "allocation account"],
            fields: [
                field(.id, "ID", valueType: .text, filterable: true, sortable: true),
                field(.name, "Name", valueType: .text, searchable: true, filterable: true, sortable: true),
                field(.color, "Color", valueType: .color, searchable: true, filterable: true),
                field(.archivedState, "Archived state", valueType: .boolean, filterable: true, groupable: true, sortable: true)
            ],
            relationships: [
                relationship(.workspace, "Workspace", targetEntity: .workspace, optional: true)
            ],
            supportedOperations: [.list, .count, .sum, .group],
            supportedMeasures: [.name, .color, .reconciliationBalance],
            defaultDateField: nil,
            defaultAmountField: nil,
            defaultSearchFields: [.name],
            workspaceScoped: true,
            isInternalOnly: false
        ),
        MarinaEntityDescriptor(
            entity: .savingsAccount,
            displayName: "Savings Account",
            aliases: ["savings account", "savings"],
            fields: [
                field(.id, "ID", valueType: .text, filterable: true, sortable: true),
                field(.name, "Name", valueType: .text, searchable: true, filterable: true, sortable: true),
                field(.date, "Date", valueType: .date, filterable: true, sortable: true),
                field(.createdAt, "Created at", valueType: .date, filterable: true, sortable: true),
                field(.updatedAt, "Updated at", valueType: .date, filterable: true, sortable: true)
            ],
            relationships: [
                relationship(.workspace, "Workspace", targetEntity: .workspace, optional: true)
            ],
            supportedOperations: [.list, .count, .sum, .last, .group, .forecast],
            supportedMeasures: [.name, .savingsTotal],
            defaultDateField: .date,
            defaultAmountField: nil,
            defaultSearchFields: [.name],
            workspaceScoped: true,
            isInternalOnly: false
        ),
        MarinaEntityDescriptor(
            entity: .income,
            displayName: "Income",
            aliases: ["income", "pay", "deposit"],
            fields: [
                field(.id, "ID", valueType: .text, filterable: true, sortable: true),
                field(.source, "Source", aliases: ["income source"], valueType: .text, searchable: true, filterable: true, groupable: true, sortable: true),
                field(.amount, "Amount", valueType: .money, filterable: true, sortable: true, aggregatable: true),
                field(.incomeAmount, "Income amount", valueType: .money, filterable: true, sortable: true, aggregatable: true),
                field(.date, "Date", valueType: .date, filterable: true, groupable: true, sortable: true),
                field(.isPlanned, "Planned state", aliases: ["planned", "actual"], valueType: .boolean, filterable: true, groupable: true, sortable: true),
                field(.isException, "Series exception", aliases: ["exception"], valueType: .boolean, filterable: true, groupable: true, sortable: true)
            ],
            relationships: [
                relationship(.workspace, "Workspace", targetEntity: .workspace, optional: true),
                relationship(.incomeSource, "Income source", aliases: ["source"], targetEntity: nil, optional: false),
                relationship(.incomeSeries, "Income series", aliases: ["series", "recurrence"], targetEntity: .incomeSeries, optional: true),
                relationship(.card, "Card", targetEntity: .card, optional: true)
            ],
            supportedOperations: [.list, .count, .sum, .average, .compare, .group, .share, .forecast],
            supportedMeasures: [.amount, .incomeAmount, .coverageRatio],
            defaultDateField: .date,
            defaultAmountField: .incomeAmount,
            defaultSearchFields: [.source],
            workspaceScoped: true,
            isInternalOnly: false
        ),
        MarinaEntityDescriptor(
            entity: .incomeSeries,
            displayName: "Income Series",
            aliases: ["income series", "recurring income", "income schedule"],
            fields: [
                field(.id, "ID", valueType: .text, filterable: true, sortable: true),
                field(.source, "Source", aliases: ["income source"], valueType: .text, searchable: true, filterable: true, groupable: true, sortable: true),
                field(.amount, "Amount", valueType: .money, filterable: true, sortable: true, aggregatable: true),
                field(.incomeAmount, "Income amount", valueType: .money, filterable: true, sortable: true, aggregatable: true),
                field(.isPlanned, "Planned state", aliases: ["planned", "actual"], valueType: .boolean, filterable: true, groupable: true, sortable: true),
                field(.frequency, "Frequency", aliases: ["repeat", "recurrence"], valueType: .text, searchable: true, filterable: true, groupable: true, sortable: true),
                field(.interval, "Interval", valueType: .number, filterable: true, sortable: true),
                field(.weeklyWeekday, "Weekly weekday", aliases: ["weekday"], valueType: .number, filterable: true, sortable: true),
                field(.monthlyDayOfMonth, "Monthly day", aliases: ["day of month"], valueType: .number, filterable: true, sortable: true),
                field(.monthlyIsLastDay, "Monthly last-day state", aliases: ["last day"], valueType: .boolean, filterable: true),
                field(.yearlyMonth, "Yearly month", valueType: .number, filterable: true, sortable: true),
                field(.yearlyDayOfMonth, "Yearly day", valueType: .number, filterable: true, sortable: true),
                field(.startDate, "Start date", valueType: .date, filterable: true, groupable: true, sortable: true),
                field(.endDate, "End date", valueType: .date, filterable: true, groupable: true, sortable: true)
            ],
            relationships: [
                relationship(.workspace, "Workspace", targetEntity: .workspace, optional: true)
            ],
            supportedOperations: [.list, .count, .last, .next],
            supportedMeasures: [.amount, .incomeAmount],
            defaultDateField: .startDate,
            defaultAmountField: .incomeAmount,
            defaultSearchFields: [.source],
            workspaceScoped: true,
            isInternalOnly: false
        ),
        MarinaEntityDescriptor(
            entity: .category,
            displayName: "Category",
            aliases: ["category", "spending category"],
            fields: [
                field(.id, "ID", valueType: .text, filterable: true, sortable: true),
                field(.name, "Name", valueType: .text, searchable: true, filterable: true, groupable: true, sortable: true),
                field(.color, "Color", valueType: .color, searchable: true, filterable: true),
                field(.archivedState, "Archived state", valueType: .boolean, filterable: true),
                field(.budgetImpact, "Budget impact", aliases: ["spend"], valueType: .money, filterable: true, sortable: true, aggregatable: true)
            ],
            relationships: [
                relationship(.workspace, "Workspace", targetEntity: .workspace, optional: true),
                relationship(.budget, "Budget", targetEntity: .budget, optional: true),
                relationship(.card, "Card", targetEntity: .card, optional: true),
                relationship(.preset, "Preset", targetEntity: .preset, optional: true)
            ],
            supportedOperations: [.list, .count, .sum, .average, .compare, .group, .share, .forecast],
            supportedMeasures: [.budgetImpact, .categoryAvailability, .concentration, .name, .color],
            defaultDateField: nil,
            defaultAmountField: .budgetImpact,
            defaultSearchFields: [.name],
            workspaceScoped: true,
            isInternalOnly: false
        ),
        MarinaEntityDescriptor(
            entity: .preset,
            displayName: "Preset",
            aliases: ["preset", "recurring planned expense", "template"],
            fields: [
                field(.id, "ID", valueType: .text, filterable: true, sortable: true),
                field(.title, "Title", valueType: .text, searchable: true, filterable: true, sortable: true),
                field(.plannedAmount, "Planned amount", valueType: .money, filterable: true, sortable: true, aggregatable: true),
                field(.actualAmount, "Actual amount", valueType: .money, filterable: true, sortable: true, aggregatable: true),
                field(.frequency, "Frequency", aliases: ["repeat", "recurrence"], valueType: .text, searchable: true, filterable: true, groupable: true, sortable: true),
                field(.interval, "Interval", valueType: .number, filterable: true, sortable: true),
                field(.weeklyWeekday, "Weekly weekday", aliases: ["weekday"], valueType: .number, filterable: true, sortable: true),
                field(.monthlyDayOfMonth, "Monthly day", aliases: ["day of month"], valueType: .number, filterable: true, sortable: true),
                field(.monthlyIsLastDay, "Monthly last-day state", aliases: ["last day"], valueType: .boolean, filterable: true),
                field(.yearlyMonth, "Yearly month", valueType: .number, filterable: true, sortable: true),
                field(.yearlyDayOfMonth, "Yearly day", valueType: .number, filterable: true, sortable: true),
                field(.archivedState, "Archived state", valueType: .boolean, filterable: true)
            ],
            relationships: [
                relationship(.workspace, "Workspace", targetEntity: .workspace, optional: true),
                relationship(.card, "Default card", targetEntity: .card, optional: true),
                relationship(.category, "Default category", targetEntity: .category, optional: true),
                relationship(.budget, "Budget", targetEntity: .budget, optional: true)
            ],
            supportedOperations: [.list, .sum, .next, .group],
            supportedMeasures: [.plannedAmount, .actualAmount, .recurringBurden, .name],
            defaultDateField: nil,
            defaultAmountField: .plannedAmount,
            defaultSearchFields: [.title],
            workspaceScoped: true,
            isInternalOnly: false
        )
    ]

    private static let defaultMeasureDescriptors: [MarinaMeasureDescriptor] = [
        measure(.amount, "Amount", aliases: ["money", "value"], entities: [.plannedExpense, .variableExpense, .income, .incomeSeries], fields: [.amount]),
        measure(.plannedAmount, "Planned amount", aliases: ["planned"], entities: [.plannedExpense, .preset], fields: [.plannedAmount]),
        measure(.actualAmount, "Actual amount", aliases: ["actual"], entities: [.plannedExpense, .preset], fields: [.actualAmount]),
        measure(.effectiveAmount, "Effective amount", aliases: ["effective"], entities: [.plannedExpense], fields: [.effectiveAmount]),
        measure(.budgetImpact, "Budget impact", aliases: ["spend", "spending"], entities: [.budget, .card, .plannedExpense, .variableExpense, .category], fields: [.budgetImpact]),
        measure(.projectedBudgetImpact, "Projected budget impact", aliases: ["projected owned spend"], entities: [.budget, .plannedExpense], fields: [.projectedBudgetImpact]),
        measure(.ledgerSignedAmount, "Signed ledger amount", aliases: ["ledger amount", "signed amount"], entities: [.variableExpense], fields: [.ledgerSignedAmount]),
        measure(.plannedIncomeTotal, "Planned income total", aliases: ["planned income"], entities: [.budget]),
        measure(.actualIncomeTotal, "Actual income total", aliases: ["actual income"], entities: [.budget]),
        measure(.plannedExpenseProjectedTotal, "Projected planned-expense total", aliases: ["planned expense projection"], entities: [.budget]),
        measure(.plannedExpenseActualTotal, "Recorded planned-expense total", aliases: ["actual planned expenses"], entities: [.budget]),
        measure(.plannedExpenseEffectiveTotal, "Effective planned-expense total", aliases: ["effective planned expenses"], entities: [.budget]),
        measure(.variableExpenseTotal, "Variable-expense total", aliases: ["variable expenses"], entities: [.budget]),
        measure(.unifiedExpenseTotal, "Unified expense total", aliases: ["all expenses", "total expenses"], entities: [.budget]),
        measure(.savingsTotal, "Savings total", aliases: ["savings", "balance"], entities: [.savingsAccount], fields: [.savingsTotal]),
        measure(.maximumSavings, "Maximum savings", aliases: ["max savings"], entities: [.budget]),
        measure(.projectedSavings, "Projected savings", aliases: ["forecast savings"], entities: [.budget]),
        measure(.actualSavings, "Actual savings", aliases: ["current savings"], entities: [.budget]),
        measure(.incomeAmount, "Income amount", aliases: ["income"], entities: [.income, .incomeSeries], fields: [.incomeAmount]),
        measure(.reconciliationBalance, "Reconciliation balance", aliases: ["shared balance", "balance"], entities: [.reconciliationAccount], fields: [.reconciliationBalance]),
        measure(.categoryAvailability, "Category availability", aliases: ["availability", "category room"], entities: [.category], relationships: [.category, .budget]),
        measure(.remainingRoom, "Remaining room", aliases: ["safe spend", "budget room"], entities: [.budget]),
        measure(.burnRate, "Burn rate", aliases: ["daily spend", "spending rate"], entities: [.budget]),
        measure(.projectedSpend, "Projected spend", aliases: ["forecast spend"], entities: [.budget]),
        measure(.safeDailySpend, "Safe daily spend", aliases: ["safe per day", "daily allowance"], entities: [.budget]),
        measure(.paceDifference, "Pace difference", aliases: ["on track", "ahead", "behind"], entities: [.budget]),
        measure(.coverageRatio, "Coverage ratio", aliases: ["income coverage"], entities: [.budget, .income]),
        measure(.recurringBurden, "Recurring burden", aliases: ["fixed expenses", "preset burden"], entities: [.preset]),
        measure(.concentration, "Concentration", aliases: ["biggest share", "eating my budget"], entities: [.category]),
        measure(.color, "Color", aliases: ["hex color"], entities: [.workspace, .reconciliationAccount, .category], fields: [.color]),
        measure(.name, "Name", aliases: ["title", "label"], entities: [.workspace, .card, .reconciliationAccount, .savingsAccount, .category, .preset], fields: [.name, .title])
    ]

    private static func expenseFields(
        titleField: MarinaFieldKey,
        titleName: String,
        dateField: MarinaFieldKey,
        dateName: String
    ) -> [MarinaFieldDescriptor] {
        [
            field(.id, "ID", valueType: .text, filterable: true, sortable: true),
            field(titleField, titleName, valueType: .text, searchable: true, filterable: true, sortable: true),
            field(.merchantText, "Merchant text", aliases: ["merchant", "store", "vendor", "description"], valueType: .text, searchable: true, filterable: true, groupable: true, sortable: true),
            field(.date, "Date", valueType: .date, filterable: true, sortable: true),
            field(dateField, dateName, valueType: .date, filterable: true, groupable: true, sortable: true),
            field(.budgetImpact, "Budget impact", aliases: ["spend", "owned spend"], valueType: .money, filterable: true, sortable: true, aggregatable: true)
        ]
    }

    private static func expenseRelationships() -> [MarinaRelationshipDescriptor] {
        [
            relationship(.workspace, "Workspace", targetEntity: .workspace, optional: true),
            relationship(.card, "Card", targetEntity: .card, optional: true),
            relationship(.category, "Category", targetEntity: .category, optional: true),
            relationship(.reconciliationAccount, "Reconciliation account", aliases: ["shared balance"], targetEntity: .reconciliationAccount, optional: true),
            relationship(.savingsAccount, "Savings account", targetEntity: .savingsAccount, optional: true)
        ]
    }

    private static func field(
        _ key: MarinaFieldKey,
        _ displayName: String,
        aliases: [String] = [],
        valueType: MarinaValueType,
        searchable: Bool = false,
        filterable: Bool = false,
        groupable: Bool = false,
        sortable: Bool = false,
        aggregatable: Bool = false
    ) -> MarinaFieldDescriptor {
        MarinaFieldDescriptor(
            key: key,
            displayName: displayName,
            aliases: aliases,
            valueType: valueType,
            isSearchable: searchable,
            isFilterable: filterable,
            isGroupable: groupable,
            isSortable: sortable,
            isAggregatable: aggregatable
        )
    }

    private static func relationship(
        _ key: MarinaRelationshipKey,
        _ displayName: String,
        aliases: [String] = [],
        targetEntity: MarinaSemanticEntity?,
        optional: Bool,
        filterable: Bool = true,
        groupable: Bool = true,
        sortable: Bool = false
    ) -> MarinaRelationshipDescriptor {
        MarinaRelationshipDescriptor(
            key: key,
            displayName: displayName,
            aliases: aliases,
            targetEntity: targetEntity,
            isFilterable: filterable,
            isGroupable: groupable,
            isSortable: sortable,
            isOptional: optional
        )
    }

    private static func measure(
        _ measure: MarinaSemanticMeasure,
        _ displayName: String,
        aliases: [String] = [],
        entities: Set<MarinaSemanticEntity>,
        fields: Set<MarinaFieldKey> = [],
        relationships: Set<MarinaRelationshipKey> = []
    ) -> MarinaMeasureDescriptor {
        MarinaMeasureDescriptor(
            measure: measure,
            displayName: displayName,
            aliases: aliases,
            supportedEntities: entities,
            requiredFields: fields,
            requiredRelationships: relationships
        )
    }

    private static func model(
        _ model: MarinaSwiftDataModel,
        _ classification: MarinaModelQueryClassification,
        entities: Set<MarinaSemanticEntity> = [],
        projections: Set<MarinaSemanticProjection> = []
    ) -> MarinaModelQueryDescriptor {
        MarinaModelQueryDescriptor(
            model: model,
            classification: classification,
            semanticEntities: entities,
            publicProjections: projections
        )
    }
}
