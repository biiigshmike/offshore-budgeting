//
//  HomePinnedWidgetsStore.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/26/26.
//

import Foundation

enum HomeWidgetID: String, CaseIterable, Identifiable, Codable {
    case nextPlannedExpense
    case categorySpotlight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nextPlannedExpense: return "Next Planned Expense"
        case .categorySpotlight: return "Category Spotlight"
        }
    }
}

struct HomePinnedWidgetsStore {

    // MARK: - Legacy support (optional)

    private struct LegacyState: Codable {
        var showNextPlannedExpense: Bool
        var showCategorySpotlight: Bool
    }

    // MARK: - Storage

    private let storageKey: String

    init(workspaceID: UUID) {
        self.storageKey = "home_pinnedWidgets_\(workspaceID.uuidString)"
    }

    func load() -> [HomeWidgetID] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            // Default order
            return [.nextPlannedExpense, .categorySpotlight]
        }

        // New format
        if let decoded = try? JSONDecoder().decode([HomeWidgetID].self, from: data) {
            return normalize(decoded)
        }

        // Legacy migration
        if let legacy = try? JSONDecoder().decode(LegacyState.self, from: data) {
            var widgets: [HomeWidgetID] = []
            if legacy.showNextPlannedExpense { widgets.append(.nextPlannedExpense) }
            if legacy.showCategorySpotlight { widgets.append(.categorySpotlight) }

            // Persist immediately in new format
            save(widgets)
            return normalize(widgets)
        }

        // Fallback
        return [.nextPlannedExpense, .categorySpotlight]
    }

    func save(_ widgets: [HomeWidgetID]) {
        let normalized = normalize(widgets)
        let data = (try? JSONEncoder().encode(normalized)) ?? Data()
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    // MARK: - Helpers

    private func normalize(_ widgets: [HomeWidgetID]) -> [HomeWidgetID] {
        // Remove duplicates, preserve order, and keep only supported widgets.
        var seen = Set<HomeWidgetID>()
        var result: [HomeWidgetID] = []

        for w in widgets {
            guard !seen.contains(w) else { continue }
            seen.insert(w)
            result.append(w)
        }

        return result
    }
}
