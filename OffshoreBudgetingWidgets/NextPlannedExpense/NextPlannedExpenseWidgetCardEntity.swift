//
//  NextPlannedExpenseWidgetCardEntity.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/7/26.
//

import AppIntents

struct NextPlannedExpenseWidgetCardEntity: AppEntity, Identifiable, Hashable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Card"
    static var defaultQuery = NextPlannedExpenseWidgetCardQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct NextPlannedExpenseWidgetCardQuery: EntityQuery {
    func suggestedEntities() async throws -> [NextPlannedExpenseWidgetCardEntity] {
        if let workspaceID = NextPlannedExpenseWidgetSnapshotStore.selectedWorkspaceID(),
           !workspaceID.isEmpty {
            let options = NextPlannedExpenseWidgetSnapshotStore.loadCardOptions(workspaceID: workspaceID)
            return options.map { NextPlannedExpenseWidgetCardEntity(id: $0.id, name: $0.name) }
        }

        let fallbackWorkspaceID = UserDefaults.standard.string(forKey: "selectedWorkspaceID") ?? ""
        if !fallbackWorkspaceID.isEmpty {
            let options = NextPlannedExpenseWidgetSnapshotStore.loadCardOptions(workspaceID: fallbackWorkspaceID)
            return options.map { NextPlannedExpenseWidgetCardEntity(id: $0.id, name: $0.name) }
        }

        return []
    }

    func entities(for identifiers: [NextPlannedExpenseWidgetCardEntity.ID]) async throws -> [NextPlannedExpenseWidgetCardEntity] {
        let all = try await suggestedEntities()
        let set = Set(identifiers)
        return all.filter { set.contains($0.id) }
    }
}
