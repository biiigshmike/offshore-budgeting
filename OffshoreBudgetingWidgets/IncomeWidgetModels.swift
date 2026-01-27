//
//  IncomeWidgetModels.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/27/26.
//


import Foundation
import WidgetKit

struct IncomeWidgetSnapshot: Codable, Hashable {
    let title: String
    let periodToken: String
    let rangeStart: Date
    let rangeEnd: Date

    let plannedTotal: Double
    let actualTotal: Double

    let recentItems: [IncomeWidgetRecentItem]?

    struct IncomeWidgetRecentItem: Codable, Hashable {
        let source: String
        let amount: Double
        let date: Date
    }
}

struct IncomeWidgetEntry: TimelineEntry {
    let date: Date
    let configuration: IncomeWidgetConfigurationIntent
    let snapshot: IncomeWidgetSnapshot?
}

extension IncomeWidgetSnapshot {
    static var placeholder: IncomeWidgetSnapshot {
        IncomeWidgetSnapshot(
            title: "Income",
            periodToken: "1M",
            rangeStart: Calendar.current.date(byAdding: .day, value: -29, to: .now) ?? .now,
            rangeEnd: .now,
            plannedTotal: 4200,
            actualTotal: 3890,
            recentItems: [
                .init(source: "Paycheck", amount: 2200, date: Calendar.current.date(byAdding: .day, value: -3, to: .now) ?? .now),
                .init(source: "Side Gig", amount: 350, date: Calendar.current.date(byAdding: .day, value: -9, to: .now) ?? .now),
                .init(source: "Bonus", amount: 600, date: Calendar.current.date(byAdding: .day, value: -18, to: .now) ?? .now)
            ]
        )
    }
}
