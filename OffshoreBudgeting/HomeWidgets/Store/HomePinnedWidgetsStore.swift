//
//  HomePinnedWidgetsStore.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/26/26.
//

import Foundation

enum HomeWidgetID: String, CaseIterable, Identifiable, Codable {
    case income
    case savingsOutlook
    case nextPlannedExpense
    case categorySpotlight
    case categoryAvailability
    case whatIf
    case spendTrends

    var id: String { rawValue }

    var title: String {
        switch self {
        case .income:
            return String(localized: "homeWidget.income", defaultValue: "Income", comment: "Pinned home widget title for income metrics.")
        case .savingsOutlook:
            return String(localized: "homeWidget.savingsOutlook", defaultValue: "Savings Outlook", comment: "Pinned home widget title for savings outlook.")
        case .nextPlannedExpense:
            return String(localized: "homeWidget.nextPlannedExpense", defaultValue: "Next Planned Expense", comment: "Pinned home widget title for next planned expense.")
        case .categorySpotlight:
            return String(localized: "homeWidget.categorySpotlight", defaultValue: "Category Spotlight", comment: "Pinned home widget title for category spotlight.")
        case .categoryAvailability:
            return String(localized: "homeWidget.categoryAvailability", defaultValue: "Category Availability", comment: "Pinned home widget title for category availability.")
        case .whatIf:
            return String(localized: "homeWidget.whatIf", defaultValue: "What If?", comment: "Pinned home widget title for what-if planner.")
        case .spendTrends:
            return String(localized: "homeWidget.spendTrends", defaultValue: "Spend Trends", comment: "Pinned home widget title for spending trends.")
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
            return [
                .income,
                .savingsOutlook,
                .whatIf,
                .nextPlannedExpense,
                .categorySpotlight,
                .spendTrends
            ]
        }

        if let decoded = try? JSONDecoder().decode([HomeWidgetID].self, from: data) {
            return normalize(decoded)
        }

        // Fallback
        return [
            .income,
            .savingsOutlook,
            .whatIf,
            .nextPlannedExpense,
            .categorySpotlight,
            .spendTrends
        ]
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
