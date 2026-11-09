//
//  NextPlannedExpenseWidgetCardEntity.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/7/26.
//

import AppIntents

struct NextPlannedExpenseWidgetCardEntity: AppEntity, Identifiable, Hashable {
    static let allCardsID = "__all_cards__"
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Card Filter"
    static var defaultQuery = NextPlannedExpenseWidgetCardQuery()

    let id: String
    let name: String

    static var allCards: NextPlannedExpenseWidgetCardEntity {
        NextPlannedExpenseWidgetCardEntity(id: allCardsID, name: "All Cards")
    }

    var isAllCards: Bool {
        id == Self.allCardsID
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct NextPlannedExpenseWidgetCardQuery: EntityQuery {
    func suggestedEntities() async throws -> [NextPlannedExpenseWidgetCardEntity] {
        guard let workspaceID = NextPlannedExpenseWidgetSnapshotStore.selectedWorkspaceID(),
              !workspaceID.isEmpty else {
            return []
        }

        return NextPlannedExpenseWidgetSnapshotStore.loadCardOptions(workspaceID: workspaceID).map {
            NextPlannedExpenseWidgetCardEntity(id: $0.id, name: $0.name)
        }
    }

    func entities(for identifiers: [NextPlannedExpenseWidgetCardEntity.ID]) async throws -> [NextPlannedExpenseWidgetCardEntity] {
        let available = try await suggestedEntities()
        return identifiers.map { id in
            if id == NextPlannedExpenseWidgetCardEntity.allCardsID { return .allCards }
            return available.first { $0.id == id }
                ?? NextPlannedExpenseWidgetCardEntity(id: id, name: String(localized: "Unavailable Card"))
        }
    }
}
