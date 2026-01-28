//
//  CardWidgetCardEntity.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/27/26.
//


import AppIntents

struct CardWidgetCardEntity: AppEntity, Identifiable, Hashable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Card"
    static var defaultQuery = CardWidgetCardQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct CardWidgetCardQuery: EntityQuery {
    func suggestedEntities() async throws -> [CardWidgetCardEntity] {
        // Try selected workspace first
        if let workspaceID = CardWidgetSnapshotStore.selectedWorkspaceID(),
           !workspaceID.isEmpty {
            let options = CardWidgetSnapshotStore.loadCardOptions(workspaceID: workspaceID)
            return options.map { CardWidgetCardEntity(id: $0.id, name: $0.name) }
        }

        // Fallback: try the app’s plain @AppStorage key (non-app-group)
        // This helps in the Intent UI when the App Group value is not set yet.
        let fallbackWorkspaceID = UserDefaults.standard.string(forKey: "selectedWorkspaceID") ?? ""
        if !fallbackWorkspaceID.isEmpty {
            let options = CardWidgetSnapshotStore.loadCardOptions(workspaceID: fallbackWorkspaceID)
            return options.map { CardWidgetCardEntity(id: $0.id, name: $0.name) }
        }

        return []
    }

    func entities(for identifiers: [CardWidgetCardEntity.ID]) async throws -> [CardWidgetCardEntity] {
        let all = try await suggestedEntities()
        let set = Set(identifiers)
        return all.filter { set.contains($0.id) }
    }
}
