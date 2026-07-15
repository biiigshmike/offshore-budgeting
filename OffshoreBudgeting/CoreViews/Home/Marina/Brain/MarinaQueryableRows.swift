import Foundation

nonisolated enum MarinaValue: Equatable, Sendable {
    case text(String)
    case money(Double)
    case number(Double)
    case integer(Int)
    case date(Date)
    case boolean(Bool)
    case colorHex(String)
    case empty
}

nonisolated struct MarinaResolvedRelationship: Equatable, Sendable {
    let key: MarinaRelationshipKey
    let targetEntity: MarinaSemanticEntity?
    let targetID: UUID?
    let displayName: String?
}

nonisolated struct MarinaQueryableRow: Equatable, Sendable {
    let id: UUID
    let entity: MarinaSemanticEntity
    let displayName: String
    let fields: [MarinaFieldKey: MarinaValue]
    let relationships: [MarinaRelationshipKey: MarinaResolvedRelationship]
    let relationshipCollections: [MarinaRelationshipKey: [MarinaResolvedRelationship]]

    init(
        id: UUID,
        entity: MarinaSemanticEntity,
        displayName: String,
        fields: [MarinaFieldKey: MarinaValue],
        relationships: [MarinaRelationshipKey: MarinaResolvedRelationship],
        relationshipCollections: [MarinaRelationshipKey: [MarinaResolvedRelationship]] = [:]
    ) {
        self.id = id
        self.entity = entity
        self.displayName = displayName
        self.fields = fields
        self.relationships = relationships
        self.relationshipCollections = relationshipCollections
    }
}

protocol MarinaEntityAdapter {
    var entity: MarinaSemanticEntity { get }

    func rows(from snapshot: MarinaWorkspaceSnapshot) -> [MarinaQueryableRow]
    func calculationRows(from snapshot: MarinaWorkspaceSnapshot) -> [MarinaQueryableRow]
}

extension MarinaEntityAdapter {
    func calculationRows(from snapshot: MarinaWorkspaceSnapshot) -> [MarinaQueryableRow] {
        rows(from: snapshot)
    }
}

struct MarinaEntityAdapterRegistry {
    let adapters: [MarinaSemanticEntity: any MarinaEntityAdapter]

    init(adapters: [any MarinaEntityAdapter] = MarinaEntityAdapterRegistry.defaultAdapters) {
        self.adapters = Dictionary(uniqueKeysWithValues: adapters.map { ($0.entity, $0) })
    }

    func adapter(for entity: MarinaSemanticEntity) -> (any MarinaEntityAdapter)? {
        adapters[entity]
    }

    func rows(for surface: MarinaUniversalEntitySurface, from snapshot: MarinaWorkspaceSnapshot) -> [MarinaQueryableRow]? {
        switch surface {
        case let .semantic(entity):
            return adapter(for: entity)?.rows(from: snapshot)
        case .unifiedExpenses:
            guard let variableAdapter = adapter(for: .variableExpense),
                  let plannedAdapter = adapter(for: .plannedExpense) else {
                return nil
            }
            return MarinaUnifiedExpenseAdapter(
                variableAdapter: variableAdapter,
                plannedAdapter: plannedAdapter
            )
            .rows(from: snapshot)
        case .savingsLedgerEntries:
            return MarinaSavingsLedgerEntryAdapter().rows(from: snapshot)
        case .reconciliationLedgerEntries:
            return MarinaReconciliationLedgerEntryAdapter().rows(from: snapshot)
        }
    }

    func rows(
        for plan: MarinaUniversalQueryPlan,
        from snapshot: MarinaWorkspaceSnapshot
    ) -> [MarinaQueryableRow]? {
        MarinaScopedRowProvider(adapterRegistry: self).rows(for: plan, from: snapshot)
    }

    static let defaultAdapters: [any MarinaEntityAdapter] = [
        MarinaWorkspaceAdapter(),
        MarinaVariableExpenseAdapter(),
        MarinaPlannedExpenseAdapter(),
        MarinaIncomeAdapter(),
        MarinaIncomeSeriesAdapter(),
        MarinaCategoryAdapter(),
        MarinaCardAdapter(),
        MarinaBudgetAdapter(),
        MarinaPresetAdapter(),
        MarinaSavingsAccountAdapter(),
        MarinaReconciliationAccountAdapter()
    ]
}
