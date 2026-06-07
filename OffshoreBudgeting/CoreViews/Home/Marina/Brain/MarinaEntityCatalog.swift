import Foundation

enum MarinaFieldKey: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case id
    case name
    case title
    case amount
    case plannedAmount
    case actualAmount
    case effectiveAmount
    case budgetImpact
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
    case color
    case archivedState
    case isPlanned
}

enum MarinaRelationshipKey: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case workspace
    case budget
    case card
    case category
    case preset
    case incomeSource
    case savingsAccount
    case reconciliationAccount
    case allocationAccount
    case plannedExpense
    case variableExpense
}

enum MarinaValueType: String, Codable, Equatable, Hashable, Sendable {
    case text
    case money
    case number
    case date
    case boolean
    case color
    case relationship
}

enum MarinaQueryVerb: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
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

struct MarinaFieldDescriptor: Equatable, Sendable {
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

struct MarinaRelationshipDescriptor: Equatable, Sendable {
    let key: MarinaRelationshipKey
    let displayName: String
    let aliases: [String]
    let targetEntity: MarinaSemanticEntity?
    let isFilterable: Bool
    let isGroupable: Bool
    let isSortable: Bool
    let isOptional: Bool
}

struct MarinaMeasureDescriptor: Equatable, Sendable {
    let measure: MarinaSemanticMeasure
    let displayName: String
    let aliases: [String]
    let supportedEntities: Set<MarinaSemanticEntity>
    let requiredFields: Set<MarinaFieldKey>
    let requiredRelationships: Set<MarinaRelationshipKey>
}

struct MarinaEntityDescriptor: Equatable, Sendable {
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

enum MarinaCapabilityFailureReason: String, Codable, Equatable, Sendable {
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

enum MarinaCapabilityResult: Equatable, Sendable {
    case supported
    case unsupported(MarinaCapabilityFailureReason)
}

struct MarinaEntityCatalog: Sendable {
    let entities: [MarinaSemanticEntity: MarinaEntityDescriptor]
    let measures: [MarinaSemanticMeasure: MarinaMeasureDescriptor]

    init(
        entities: [MarinaSemanticEntity: MarinaEntityDescriptor] = MarinaEntityCatalog.defaultEntities,
        measures: [MarinaSemanticMeasure: MarinaMeasureDescriptor] = MarinaEntityCatalog.defaultMeasures
    ) {
        self.entities = entities
        self.measures = measures
    }

    func descriptor(for entity: MarinaSemanticEntity) -> MarinaEntityDescriptor? {
        entities[entity]
    }

    func measureDescriptor(for measure: MarinaSemanticMeasure) -> MarinaMeasureDescriptor? {
        measures[measure]
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

    private static let defaultEntityDescriptors: [MarinaEntityDescriptor] = [
        MarinaEntityDescriptor(
            entity: .workspace,
            displayName: "Workspace",
            aliases: ["workspace", "context"],
            fields: [
                field(.id, "ID", valueType: .text),
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
                field(.id, "ID", valueType: .text),
                field(.name, "Name", valueType: .text, searchable: true, filterable: true, sortable: true),
                field(.startDate, "Start date", valueType: .date, filterable: true, groupable: true, sortable: true),
                field(.endDate, "End date", valueType: .date, filterable: true, groupable: true, sortable: true),
                field(.budgetImpact, "Budget impact", aliases: ["spend", "spending"], valueType: .money, filterable: true, sortable: true, aggregatable: true)
            ],
            relationships: [
                relationship(.workspace, "Workspace", targetEntity: .workspace, optional: true),
                relationship(.card, "Linked card", aliases: ["card"], targetEntity: .card, optional: true),
                relationship(.category, "Category limit", aliases: ["category"], targetEntity: .category, optional: true),
                relationship(.preset, "Linked preset", aliases: ["preset"], targetEntity: .preset, optional: true)
            ],
            supportedOperations: [.list, .sum, .average, .compare, .forecast, .whatIf],
            supportedMeasures: [.budgetImpact, .remainingRoom, .burnRate, .projectedSpend, .safeDailySpend, .paceDifference, .coverageRatio],
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
                field(.id, "ID", valueType: .text),
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
                field(.effectiveAmount, "Effective amount", valueType: .money, filterable: true, sortable: true, aggregatable: true)
            ],
            relationships: expenseRelationships() + [
                relationship(.preset, "Source preset", aliases: ["preset"], targetEntity: .preset, optional: true),
                relationship(.budget, "Source budget", aliases: ["budget"], targetEntity: .budget, optional: true)
            ],
            supportedOperations: [.list, .count, .sum, .average, .last, .next, .group],
            supportedMeasures: [.amount, .plannedAmount, .actualAmount, .effectiveAmount, .budgetImpact],
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
                field(.amount, "Amount", valueType: .money, filterable: true, sortable: true, aggregatable: true)
            ],
            relationships: expenseRelationships(),
            supportedOperations: [.list, .count, .sum, .average, .last, .group],
            supportedMeasures: [.amount, .budgetImpact],
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
                field(.id, "ID", valueType: .text),
                field(.name, "Name", valueType: .text, searchable: true, filterable: true, sortable: true),
                field(.color, "Color", valueType: .color, searchable: true, filterable: true),
                field(.archivedState, "Archived state", valueType: .boolean, filterable: true),
                field(.reconciliationBalance, "Reconciliation balance", aliases: ["balance"], valueType: .money, filterable: true, sortable: true, aggregatable: true)
            ],
            relationships: [
                relationship(.workspace, "Workspace", targetEntity: .workspace, optional: true),
                relationship(.plannedExpense, "Planned expense", targetEntity: .plannedExpense, optional: true),
                relationship(.variableExpense, "Variable expense", targetEntity: .variableExpense, optional: true)
            ],
            supportedOperations: [.sum],
            supportedMeasures: [.reconciliationBalance, .name],
            defaultDateField: nil,
            defaultAmountField: .reconciliationBalance,
            defaultSearchFields: [.name],
            workspaceScoped: true,
            isInternalOnly: false
        ),
        MarinaEntityDescriptor(
            entity: .savingsAccount,
            displayName: "Savings Account",
            aliases: ["savings account", "savings"],
            fields: [
                field(.id, "ID", valueType: .text),
                field(.name, "Name", valueType: .text, searchable: true, filterable: true, sortable: true),
                field(.savingsTotal, "Savings total", aliases: ["total", "balance"], valueType: .money, filterable: true, sortable: true, aggregatable: true),
                field(.createdAt, "Created at", valueType: .date, filterable: true, sortable: true),
                field(.updatedAt, "Updated at", valueType: .date, filterable: true, sortable: true)
            ],
            relationships: [
                relationship(.workspace, "Workspace", targetEntity: .workspace, optional: true)
            ],
            supportedOperations: [.sum, .forecast],
            supportedMeasures: [.savingsTotal, .name],
            defaultDateField: .createdAt,
            defaultAmountField: .savingsTotal,
            defaultSearchFields: [.name],
            workspaceScoped: true,
            isInternalOnly: false
        ),
        MarinaEntityDescriptor(
            entity: .income,
            displayName: "Income",
            aliases: ["income", "pay", "deposit"],
            fields: [
                field(.id, "ID", valueType: .text),
                field(.source, "Source", aliases: ["income source"], valueType: .text, searchable: true, filterable: true, groupable: true, sortable: true),
                field(.amount, "Amount", valueType: .money, filterable: true, sortable: true, aggregatable: true),
                field(.incomeAmount, "Income amount", valueType: .money, filterable: true, sortable: true, aggregatable: true),
                field(.date, "Date", valueType: .date, filterable: true, groupable: true, sortable: true),
                field(.isPlanned, "Planned state", aliases: ["planned", "actual"], valueType: .boolean, filterable: true, groupable: true, sortable: true)
            ],
            relationships: [
                relationship(.workspace, "Workspace", targetEntity: .workspace, optional: true),
                relationship(.incomeSource, "Income source", aliases: ["source"], targetEntity: nil, optional: false),
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
            entity: .category,
            displayName: "Category",
            aliases: ["category", "spending category"],
            fields: [
                field(.id, "ID", valueType: .text),
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
                field(.id, "ID", valueType: .text),
                field(.title, "Title", valueType: .text, searchable: true, filterable: true, sortable: true),
                field(.plannedAmount, "Planned amount", valueType: .money, filterable: true, sortable: true, aggregatable: true),
                field(.actualAmount, "Actual amount", valueType: .money, filterable: true, sortable: true, aggregatable: true),
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
        measure(.amount, "Amount", aliases: ["money", "value"], entities: [.plannedExpense, .variableExpense, .income], fields: [.amount]),
        measure(.plannedAmount, "Planned amount", aliases: ["planned"], entities: [.plannedExpense, .preset], fields: [.plannedAmount]),
        measure(.actualAmount, "Actual amount", aliases: ["actual"], entities: [.plannedExpense, .preset], fields: [.actualAmount]),
        measure(.effectiveAmount, "Effective amount", aliases: ["effective"], entities: [.plannedExpense], fields: [.effectiveAmount]),
        measure(.budgetImpact, "Budget impact", aliases: ["spend", "spending"], entities: [.budget, .card, .plannedExpense, .variableExpense, .category], fields: [.budgetImpact]),
        measure(.savingsTotal, "Savings total", aliases: ["savings", "balance"], entities: [.savingsAccount], fields: [.savingsTotal]),
        measure(.incomeAmount, "Income amount", aliases: ["income"], entities: [.income], fields: [.incomeAmount]),
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
        measure(.color, "Color", aliases: ["hex color"], entities: [.workspace, .category], fields: [.color]),
        measure(.name, "Name", aliases: ["title", "label"], entities: [.workspace, .card, .reconciliationAccount, .savingsAccount, .category, .preset], fields: [.name, .title])
    ]

    private static func expenseFields(
        titleField: MarinaFieldKey,
        titleName: String,
        dateField: MarinaFieldKey,
        dateName: String
    ) -> [MarinaFieldDescriptor] {
        [
            field(.id, "ID", valueType: .text),
            field(titleField, titleName, valueType: .text, searchable: true, filterable: true, sortable: true),
            field(.merchantText, "Merchant text", aliases: ["merchant", "store", "vendor", "description"], valueType: .text, searchable: true, filterable: true, groupable: true, sortable: true),
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
}
