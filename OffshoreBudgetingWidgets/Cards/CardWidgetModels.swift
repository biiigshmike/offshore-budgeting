//
//  CardWidgetModels.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/27/26.
//

import Foundation
import WidgetKit

struct CardWidgetSnapshot: Codable, Hashable {
    let title: String                 // Card name
    let cardID: String
    let themeToken: String
    let effectToken: String

    let periodToken: String
    let rangeStart: Date
    let rangeEnd: Date

    let unifiedExpensesTotal: Double
    let recentItems: [CardWidgetRecentItem]?

    struct CardWidgetRecentItem: Codable, Hashable {
        let name: String
        let amount: Double
        let date: Date
        let categoryHex: String?
    }
}

struct CardWidgetEntry: TimelineEntry {
    let date: Date
    let periodToken: String
    let cardID: String?
    let snapshot: CardWidgetSnapshot?
}

extension CardWidgetSnapshot {
    static var placeholder: CardWidgetSnapshot {
        CardWidgetSnapshot(
            title: "Everyday Card",
            cardID: UUID().uuidString,
            themeToken: "graphite",
            effectToken: "plastic",
            periodToken: "1M",
            rangeStart: Calendar.current.date(byAdding: .day, value: -29, to: .now) ?? .now,
            rangeEnd: .now,
            unifiedExpensesTotal: 1243.18,
            recentItems: [
                .init(name: "Groceries", amount: 84.22, date: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now, categoryHex: "#10B981"),
                .init(name: "Gas", amount: 52.10, date: Calendar.current.date(byAdding: .day, value: -2, to: .now) ?? .now, categoryHex: "#3B82F6"),
                .init(name: "Dinner", amount: 41.67, date: Calendar.current.date(byAdding: .day, value: -4, to: .now) ?? .now, categoryHex: "#F97316")
            ]
        )
    }
}
