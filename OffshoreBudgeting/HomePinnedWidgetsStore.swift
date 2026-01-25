//
//  HomePinnedWidgetsStore.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/26/26.
//

import Foundation

enum HomeWidgetID: String, CaseIterable, Identifiable, Codable {
    case income
    case nextPlannedExpense
    case categorySpotlight
    case categoryAvailability

    var id: String { rawValue }

    var title: String {
        switch self {
        case .income: return "Income"
        case .nextPlannedExpense: return "Next Planned Expense"
        case .categorySpotlight: return "Category Spotlight"
        case .categoryAvailability: return "Category Availability"
        }
    }
}

struct HomePinnedWidgetsStore {

    // MARK: - Storage

    private let storageKey: String

    init(workspaceID: UUID) {
        self.storageKey = "home_pinnedWidgets_\(workspaceID.uuidString)"
    }

    func load() -> [HomeWidgetID] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            // Default order
            return [.income, .nextPlannedExpense, .categorySpotlight]
        }

        // New format
        if let decoded = try? JSONDecoder().decode([HomeWidgetID].self, from: data) {
            return normalize(decoded)
        }

        // Fallback
        return [.income, .nextPlannedExpense, .categorySpotlight]
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
