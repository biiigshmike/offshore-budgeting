//
//  HomePinnedItemsStore.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/28/26.
//

import Foundation

// MARK: - Unified pinned items

enum HomePinnedItem: Identifiable, Codable, Equatable {

    case widget(HomeWidgetID)
    case card(UUID)

    var id: String {
        switch self {
        case .widget(let widget): return "widget-\(widget.rawValue)"
        case .card(let uuid): return "card-\(uuid.uuidString)"
        }
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case type
        case widget
        case cardID
    }

    private enum ItemType: String, Codable {
        case widget
        case card
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ItemType.self, forKey: .type)

        switch type {
        case .widget:
            let widget = try container.decode(HomeWidgetID.self, forKey: .widget)
            self = .widget(widget)

        case .card:
            let id = try container.decode(UUID.self, forKey: .cardID)
            self = .card(id)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .widget(let widget):
            try container.encode(ItemType.widget, forKey: .type)
            try container.encode(widget, forKey: .widget)

        case .card(let id):
            try container.encode(ItemType.card, forKey: .type)
            try container.encode(id, forKey: .cardID)
        }
    }
}

// MARK: - Store

struct HomePinnedItemsStore {

    private let storageKey: String

    init(workspaceID: UUID) {
        self.storageKey = "home_pinnedItems_\(workspaceID.uuidString)"
    }

    func load() -> [HomePinnedItem] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([HomePinnedItem].self, from: data)) ?? []
    }

    func save(_ items: [HomePinnedItem]) {
        let normalized = normalize(items)
        let data = (try? JSONEncoder().encode(normalized)) ?? Data()
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    // MARK: - Helpers

    private func normalize(_ items: [HomePinnedItem]) -> [HomePinnedItem] {
        // Remove duplicates, preserve order.
        var seen = Set<String>()
        var result: [HomePinnedItem] = []

        for item in items {
            guard !seen.contains(item.id) else { continue }
            seen.insert(item.id)
            result.append(item)
        }

        return result
    }
}
