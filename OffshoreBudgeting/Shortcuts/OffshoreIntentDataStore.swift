import Foundation
import SwiftData

// MARK: - OffshoreIntentDataStore

@MainActor
final class OffshoreIntentDataStore {
    static let shared = OffshoreIntentDataStore()

    private static var cachedContainers: [Bool: ModelContainer] = [:]

    private init() {}

    // MARK: - Errors

    enum IntentDataError: LocalizedError {
        case workspaceUnavailable
        case cardUnavailable
        case categoryUnavailable

        var errorDescription: String? {
            switch self {
            case .workspaceUnavailable:
                return "No workspace is selected. Open Offshore and pick a workspace first."
            case .cardUnavailable:
                return "The selected card was not found in your active workspace."
            case .categoryUnavailable:
                return "The selected category was not found in your active workspace."
            }
        }
    }

    // MARK: - Public

    func fetchCardEntitiesForSelectedWorkspace() throws -> [OffshoreCardEntity] {
        guard let workspace = try selectedWorkspace() else { return [] }
        let context = try makeModelContext()

        let workspaceID = workspace.id
        let descriptor = FetchDescriptor<Card>(
            predicate: #Predicate<Card> { card in
                card.workspace?.id == workspaceID
            },
            sortBy: [SortDescriptor(\Card.name, order: .forward)]
        )

        return try context.fetch(descriptor).map {
            OffshoreCardEntity(id: $0.id.uuidString, name: $0.name)
        }
    }

    func fetchCategoryEntitiesForSelectedWorkspace() throws -> [OffshoreCategoryEntity] {
        guard let workspace = try selectedWorkspace() else { return [] }
        let context = try makeModelContext()

        let workspaceID = workspace.id
        let descriptor = FetchDescriptor<Category>(
            predicate: #Predicate<Category> { category in
                category.workspace?.id == workspaceID
            },
            sortBy: [SortDescriptor(\Category.name, order: .forward)]
        )

        return try context.fetch(descriptor).map {
            OffshoreCategoryEntity(id: $0.id.uuidString, name: $0.name)
        }
    }

    func performInSelectedWorkspace<Result>(_ block: (ModelContext, Workspace) throws -> Result) throws -> Result {
        let context = try makeModelContext()
        guard let workspace = try fetchSelectedWorkspace(from: context) else {
            throw IntentDataError.workspaceUnavailable
        }
        return try block(context, workspace)
    }

    func performWrite<Result>(_ block: (ModelContext, Workspace) throws -> Result) throws -> Result {
        try performInSelectedWorkspace(block)
    }

    func resolveCard(id: String, in workspace: Workspace, modelContext: ModelContext) throws -> Card {
        guard let uuid = UUID(uuidString: id) else {
            throw IntentDataError.cardUnavailable
        }

        let workspaceID = workspace.id
        let descriptor = FetchDescriptor<Card>(
            predicate: #Predicate<Card> { card in
                card.id == uuid && card.workspace?.id == workspaceID
            }
        )

        guard let card = try modelContext.fetch(descriptor).first else {
            throw IntentDataError.cardUnavailable
        }

        return card
    }

    func resolveCategory(id: String?, in workspace: Workspace, modelContext: ModelContext) throws -> Category? {
        guard let id, let uuid = UUID(uuidString: id) else {
            return nil
        }

        let workspaceID = workspace.id
        let descriptor = FetchDescriptor<Category>(
            predicate: #Predicate<Category> { category in
                category.id == uuid && category.workspace?.id == workspaceID
            }
        )

        return try modelContext.fetch(descriptor).first
    }

    // MARK: - Private

    private func selectedWorkspace() throws -> Workspace? {
        let context = try makeModelContext()
        return try fetchSelectedWorkspace(from: context)
    }

    private func fetchSelectedWorkspace(from context: ModelContext) throws -> Workspace? {
        if let selectedID = selectedWorkspaceID() {
            let descriptor = FetchDescriptor<Workspace>(
                predicate: #Predicate<Workspace> { workspace in
                    workspace.id == selectedID
                }
            )
            if let workspace = try context.fetch(descriptor).first {
                return workspace
            }
        }

        let descriptor = FetchDescriptor<Workspace>(
            sortBy: [SortDescriptor(\Workspace.name, order: .forward)]
        )
        return try context.fetch(descriptor).first
    }

    private func selectedWorkspaceID() -> UUID? {
        guard let rawID = UserDefaults.standard.string(forKey: "selectedWorkspaceID") else {
            return nil
        }
        return UUID(uuidString: rawID)
    }

    private func makeModelContext() throws -> ModelContext {
        let useICloud = UserDefaults.standard.bool(forKey: "icloud_activeUseCloud")
            || UserDefaults.standard.bool(forKey: "icloud_useCloud")
        let container: ModelContainer
        if let cached = Self.cachedContainers[useICloud] {
            container = cached
        } else {
            let created = OffshoreBudgetingApp.makeModelContainer(useICloud: useICloud)
            Self.cachedContainers[useICloud] = created
            container = created
        }
        return ModelContext(container)
    }
}
