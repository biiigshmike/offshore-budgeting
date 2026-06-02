//
//  SpendTrendsWidgetCardEntity.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/7/26.
//

import AppIntents

struct SpendTrendsWidgetCardEntity: AppEntity, Identifiable, Hashable {
    static let allCardsID = "__all_cards__"
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Card Filter"
    static var defaultQuery = SpendTrendsWidgetCardQuery()

    let id: String
    let name: String

    static var allCards: SpendTrendsWidgetCardEntity {
        SpendTrendsWidgetCardEntity(id: allCardsID, name: "All Cards")
    }

    var isAllCards: Bool {
        id == Self.allCardsID
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct SpendTrendsWidgetCardQuery: EntityQuery {
    func suggestedEntities() async throws -> [SpendTrendsWidgetCardEntity] {
        if let workspaceID = SpendTrendsWidgetSnapshotStore.selectedWorkspaceID(), !workspaceID.isEmpty {
            let options = SpendTrendsWidgetSnapshotStore.loadCardOptions(workspaceID: workspaceID)
            return [SpendTrendsWidgetCardEntity.allCards] + options.map { SpendTrendsWidgetCardEntity(id: $0.id, name: $0.name) }
        }

        let fallbackWorkspaceID = UserDefaults.standard.string(forKey: "selectedWorkspaceID") ?? ""
        if !fallbackWorkspaceID.isEmpty {
            let options = SpendTrendsWidgetSnapshotStore.loadCardOptions(workspaceID: fallbackWorkspaceID)
            return [SpendTrendsWidgetCardEntity.allCards] + options.map { SpendTrendsWidgetCardEntity(id: $0.id, name: $0.name) }
        }

        return [.allCards]
    }

    func entities(for identifiers: [SpendTrendsWidgetCardEntity.ID]) async throws -> [SpendTrendsWidgetCardEntity] {
        let all = try await suggestedEntities()
        let set = Set(identifiers)
        return all.filter { set.contains($0.id) }
    }
}
