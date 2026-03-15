//
//  NextPlannedExpenseWidgetModels.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/7/26.
//

import Foundation
import WidgetKit

struct NextPlannedExpenseWidgetSnapshot: Codable, Hashable {
    let title: String
    let periodToken: String
    let rangeStart: Date
    let rangeEnd: Date
    let items: [Item]

    struct Item: Codable, Hashable {
        let expenseID: String
        let expenseTitle: String
        let cardName: String
        let cardThemeToken: String
        let cardEffectToken: String
        let expenseDate: Date
        let plannedAmount: Double
        let actualAmount: Double
    }
}

struct NextPlannedExpenseWidgetEntry: TimelineEntry {
    let date: Date
    let periodToken: String
    let cardID: String?
    let snapshot: NextPlannedExpenseWidgetSnapshot?
}

extension NextPlannedExpenseWidgetSnapshot {
    static var placeholder: NextPlannedExpenseWidgetSnapshot {
        NextPlannedExpenseWidgetSnapshot(
            title: "Next Planned Expense",
            periodToken: "1M",
            rangeStart: Calendar.current.date(byAdding: .day, value: -29, to: .now) ?? .now,
            rangeEnd: .now,
            items: [
                .init(
                    expenseID: UUID().uuidString,
                    expenseTitle: "Groceries",
                    cardName: "Everyday Card",
                    cardThemeToken: "graphite",
                    cardEffectToken: "plastic",
                    expenseDate: Calendar.current.date(byAdding: .day, value: 2, to: .now) ?? .now,
                    plannedAmount: 120,
                    actualAmount: 98
                ),
                .init(
                    expenseID: UUID().uuidString,
                    expenseTitle: "Gas",
                    cardName: "Everyday Card",
                    cardThemeToken: "graphite",
                    cardEffectToken: "plastic",
                    expenseDate: Calendar.current.date(byAdding: .day, value: 4, to: .now) ?? .now,
                    plannedAmount: 65,
                    actualAmount: 65
                ),
                .init(
                    expenseID: UUID().uuidString,
                    expenseTitle: "Phone Bill",
                    cardName: "Bills Card",
                    cardThemeToken: "ocean",
                    cardEffectToken: "plastic",
                    expenseDate: Calendar.current.date(byAdding: .day, value: 6, to: .now) ?? .now,
                    plannedAmount: 95,
                    actualAmount: 0
                ),
                .init(
                    expenseID: UUID().uuidString,
                    expenseTitle: "Streaming",
                    cardName: "Bills Card",
                    cardThemeToken: "ocean",
                    cardEffectToken: "plastic",
                    expenseDate: Calendar.current.date(byAdding: .day, value: 8, to: .now) ?? .now,
                    plannedAmount: 18.99,
                    actualAmount: 18.99
                )
            ]
        )
    }

    static var truncationPreview: NextPlannedExpenseWidgetSnapshot {
        NextPlannedExpenseWidgetSnapshot(
            title: "Next Planned Expense",
            periodToken: "P",
            rangeStart: Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1)) ?? .now,
            rangeEnd: Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 31)) ?? .now,
            items: [
                .init(
                    expenseID: UUID().uuidString,
                    expenseTitle: "Progressive Workspace Insurance Premium",
                    cardName: "Debit Card",
                    cardThemeToken: "sunset",
                    cardEffectToken: "plastic",
                    expenseDate: Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 14)) ?? .now,
                    plannedAmount: 210.16,
                    actualAmount: 210.16
                ),
                .init(
                    expenseID: UUID().uuidString,
                    expenseTitle: "QuickQuack Car Wash Family Membership",
                    cardName: "Apple Card",
                    cardThemeToken: "graphite",
                    cardEffectToken: "plastic",
                    expenseDate: Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 14)) ?? .now,
                    plannedAmount: 37.99,
                    actualAmount: 37.99
                ),
                .init(
                    expenseID: UUID().uuidString,
                    expenseTitle: "Cloud Backup Subscription Renewal",
                    cardName: "Bills Card",
                    cardThemeToken: "ocean",
                    cardEffectToken: "plastic",
                    expenseDate: Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 18)) ?? .now,
                    plannedAmount: 128.45,
                    actualAmount: 0
                )
            ]
        )
    }
}
