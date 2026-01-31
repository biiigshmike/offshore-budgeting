//
//  HomePinnedItemsStore.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/28/26.
//

import Foundation

// MARK: - Unified pinned items

enum HomeTileSize: String, CaseIterable, Codable, Equatable {
    case small
    case wide

    var title: String {
        switch self {
        case .small: return "Small"
        case .wide: return "Wide"
        }
    }
}

enum HomePinnedItem: Identifiable, Codable, Equatable {

    case widget(HomeWidgetID, HomeTileSize)
    case card(UUID, HomeTileSize)

    var id: String {
        switch self {
        case .widget(let widget, _): return "widget-\(widget.rawValue)"
        case .card(let uuid, _): return "card-\(uuid.uuidString)"
        }
    }

    var tileSize: HomeTileSize {
        switch self {
        case .widget(_, let size): return size
        case .card(_, let size): return size
        }
    }

    func withTileSize(_ size: HomeTileSize) -> HomePinnedItem {
        switch self {
        case .widget(let widget, _):
            return .widget(widget, size)
        case .card(let id, _):
            return .card(id, size)
        }
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case type
        case widget
        case cardID
        case size
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
            let size = (try? container.decode(HomeTileSize.self, forKey: .size)) ?? .small
            self = .widget(widget, size)

        case .card:
            let id = try container.decode(UUID.self, forKey: .cardID)
            let size = (try? container.decode(HomeTileSize.self, forKey: .size)) ?? .small
            self = .card(id, size)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .widget(let widget, let size):
            try container.encode(ItemType.widget, forKey: .type)
            try container.encode(widget, forKey: .widget)
            try container.encode(size, forKey: .size)

        case .card(let id, let size):
            try container.encode(ItemType.card, forKey: .type)
            try container.encode(id, forKey: .cardID)
            try container.encode(size, forKey: .size)
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
        guard let decoded = try? JSONDecoder().decode([HomePinnedItem].self, from: data) else { return [] }
        return normalize(decoded)
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

// MARK: - Mutations

extension HomePinnedItemsStore {
    func removePinnedCard(id: UUID) {
        let updated = load().filter { item in
            guard case .card(let cardID, _) = item else { return true }
            return cardID != id
        }
        save(updated)
    }
}
