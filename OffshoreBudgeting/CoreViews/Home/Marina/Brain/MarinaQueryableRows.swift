import Foundation

enum MarinaValue: Equatable, Sendable {
    case text(String)
    case money(Double)
    case number(Double)
    case integer(Int)
    case date(Date)
    case boolean(Bool)
    case colorHex(String)
    case empty
}

struct MarinaResolvedRelationship: Equatable, Sendable {
    let key: MarinaRelationshipKey
    let targetEntity: MarinaSemanticEntity?
    let targetID: UUID?
    let displayName: String?
}

struct MarinaQueryableRow: Equatable, Sendable {
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

    static let defaultAdapters: [any MarinaEntityAdapter] = [
        MarinaVariableExpenseAdapter(),
        MarinaPlannedExpenseAdapter(),
        MarinaIncomeAdapter(),
        MarinaCategoryAdapter(),
        MarinaCardAdapter(),
        MarinaBudgetAdapter(),
        MarinaPresetAdapter()
    ]
}
