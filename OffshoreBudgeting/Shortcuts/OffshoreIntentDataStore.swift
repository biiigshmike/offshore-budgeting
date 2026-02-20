import Foundation
import SwiftData

// MARK: - OffshoreIntentDataStore

@MainActor
final class OffshoreIntentDataStore {
    static let shared = OffshoreIntentDataStore()

    private static var cachedContainers: [Bool: ModelContainer] = [:]

    private init() {}

    // MARK: - Errors

    enum IntentDataError: LocalizedError, Equatable {
        case workspaceUnavailable
        case cardUnavailable
        case ambiguousCardName
        case categoryUnavailable
        case allocationAccountUnavailable

        var errorDescription: String? {
            switch self {
            case .workspaceUnavailable:
                return "No workspace is selected. Open Offshore and pick a workspace first."
            case .cardUnavailable:
                return "The selected card was not found in your active workspace."
            case .ambiguousCardName:
                return "More than one card matched that Wallet card name. Rename cards so each one is unique."
            case .categoryUnavailable:
                return "The selected category was not found in your active workspace."
            case .allocationAccountUnavailable:
                return "The selected Reconciliation was not found in your active workspace."
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

    func fetchAllocationAccountEntitiesForSelectedWorkspace() throws -> [OffshoreAllocationAccountEntity] {
        guard let workspace = try selectedWorkspace() else { return [] }
        let context = try makeModelContext()

        let workspaceID = workspace.id
        let descriptor = FetchDescriptor<AllocationAccount>(
            predicate: #Predicate<AllocationAccount> { account in
                account.workspace?.id == workspaceID && account.isArchived == false
            },
            sortBy: [SortDescriptor(\AllocationAccount.name, order: .forward)]
        )

        return try context.fetch(descriptor).map {
            OffshoreAllocationAccountEntity(id: $0.id.uuidString, name: $0.name)
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

    func resolveCard(
        id: String?,
        name: String?,
        in workspace: Workspace,
        modelContext: ModelContext
    ) throws -> Card {
        let trimmedID = (id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedID.isEmpty {
            return try resolveCard(id: trimmedID, in: workspace, modelContext: modelContext)
        }

        let normalizedName = normalizeLookupText(name)
        guard !normalizedName.isEmpty else {
            throw IntentDataError.cardUnavailable
        }

        let workspaceID = workspace.id
        let descriptor = FetchDescriptor<Card>(
            predicate: #Predicate<Card> { card in
                card.workspace?.id == workspaceID
            }
        )
        let cards = try modelContext.fetch(descriptor)
        let matches = cards.filter {
            normalizeLookupText($0.name) == normalizedName
        }

        guard let first = matches.first else {
            throw IntentDataError.cardUnavailable
        }

        if matches.count > 1 {
            throw IntentDataError.ambiguousCardName
        }

        return first
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

    func resolveCategory(
        id: String?,
        merchant: String?,
        in workspace: Workspace,
        modelContext: ModelContext
    ) throws -> Category? {
        if let resolvedByID = try resolveCategory(id: id, in: workspace, modelContext: modelContext) {
            return resolvedByID
        }

        let trimmedMerchant = (merchant ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedMerchant.isEmpty {
            let merchantKey = MerchantNormalizer.normalizeKey(trimmedMerchant)
            if !merchantKey.isEmpty {
                let rulesByKey = ImportLearningStore.fetchRules(for: workspace, modelContext: modelContext)
                let matcher = ImportMerchantRuleMatcher(rulesByKey: rulesByKey)
                if let match = matcher.match(for: merchantKey),
                   let preferredCategory = match.rule.preferredCategory {
                    return preferredCategory
                }
            }
        }
        return nil
    }

    func resolveAllocationAccount(id: String?, in workspace: Workspace, modelContext: ModelContext) throws -> AllocationAccount? {
        guard let id, let uuid = UUID(uuidString: id) else {
            return nil
        }

        let workspaceID = workspace.id
        let descriptor = FetchDescriptor<AllocationAccount>(
            predicate: #Predicate<AllocationAccount> { account in
                account.id == uuid && account.workspace?.id == workspaceID && account.isArchived == false
            }
        )

        guard let account = try modelContext.fetch(descriptor).first else {
            throw IntentDataError.allocationAccountUnavailable
        }
        return account
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

    private func normalizeLookupText(_ value: String?) -> String {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }

        let collapsed = trimmed.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        return collapsed.uppercased()
    }
}
