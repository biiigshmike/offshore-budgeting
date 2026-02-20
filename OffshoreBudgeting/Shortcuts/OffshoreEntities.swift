import AppIntents

// MARK: - Card Entity

struct OffshoreCardEntity: AppEntity, Identifiable, Hashable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Card"
    static var defaultQuery = OffshoreCardEntityQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct OffshoreCardEntityQuery: EntityQuery {
    func suggestedEntities() async throws -> [OffshoreCardEntity] {
        try await MainActor.run {
            try OffshoreIntentDataStore.shared.fetchCardEntitiesForSelectedWorkspace()
        }
    }

    func entities(for identifiers: [OffshoreCardEntity.ID]) async throws -> [OffshoreCardEntity] {
        let all = try await suggestedEntities()
        let set = Set(identifiers)
        return all.filter { set.contains($0.id) }
    }
}

// MARK: - Category Entity

struct OffshoreCategoryEntity: AppEntity, Identifiable, Hashable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Category"
    static var defaultQuery = OffshoreCategoryEntityQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct OffshoreCategoryEntityQuery: EntityQuery {
    func suggestedEntities() async throws -> [OffshoreCategoryEntity] {
        try await MainActor.run {
            try OffshoreIntentDataStore.shared.fetchCategoryEntitiesForSelectedWorkspace()
        }
    }

    func entities(for identifiers: [OffshoreCategoryEntity.ID]) async throws -> [OffshoreCategoryEntity] {
        let all = try await suggestedEntities()
        let set = Set(identifiers)
        return all.filter { set.contains($0.id) }
    }
}

// MARK: - Reconciliation Entity

struct OffshoreAllocationAccountEntity: AppEntity, Identifiable, Hashable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Reconciliation"
    static var defaultQuery = OffshoreAllocationAccountEntityQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct OffshoreAllocationAccountEntityQuery: EntityQuery {
    func suggestedEntities() async throws -> [OffshoreAllocationAccountEntity] {
        try await MainActor.run {
            try OffshoreIntentDataStore.shared.fetchAllocationAccountEntitiesForSelectedWorkspace()
        }
    }

    func entities(for identifiers: [OffshoreAllocationAccountEntity.ID]) async throws -> [OffshoreAllocationAccountEntity] {
        let all = try await suggestedEntities()
        let set = Set(identifiers)
        return all.filter { set.contains($0.id) }
    }
}
