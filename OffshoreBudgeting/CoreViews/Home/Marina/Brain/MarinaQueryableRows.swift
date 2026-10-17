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
}

protocol MarinaEntityAdapter {
    var entity: MarinaSemanticEntity { get }

    func rows(from snapshot: MarinaWorkspaceSnapshot) -> [MarinaQueryableRow]
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

    static let defaultAdapters: [any MarinaEntityAdapter] = [
        MarinaVariableExpenseAdapter(),
        MarinaPlannedExpenseAdapter(),
        MarinaIncomeAdapter(),
        MarinaCategoryAdapter(),
        MarinaCardAdapter(),
        MarinaBudgetAdapter(),
        MarinaPresetAdapter(),
        MarinaSavingsAccountAdapter(),
        MarinaReconciliationAccountAdapter()
    ]
}
