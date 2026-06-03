//
//  IncomeWidgetModels.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/27/26.
//

import Foundation
import WidgetKit

nonisolated struct IncomeWidgetSnapshot: Codable, Hashable {
    let title: String
    let periodToken: String
    let rangeStart: Date
    let rangeEnd: Date

    let plannedTotal: Double
    let actualTotal: Double

    let recentItems: [IncomeWidgetRecentItem]?

    nonisolated struct IncomeWidgetRecentItem: Codable, Hashable {
        let source: String
        let amount: Double
        let date: Date
        let isPlanned: Bool
    }
}

nonisolated struct IncomeWidgetEntry: TimelineEntry {
    let date: Date
    let periodToken: String
    let snapshot: IncomeWidgetSnapshot?
}


extension IncomeWidgetSnapshot {
    static var placeholder: IncomeWidgetSnapshot {
        IncomeWidgetSnapshot(
            title: NSLocalizedString("Income", comment: "Income widget preview title."),
            periodToken: "1M",
            rangeStart: Calendar.current.date(byAdding: .day, value: -29, to: .now) ?? .now,
            rangeEnd: .now,
            plannedTotal: 4200,
            actualTotal: 3890,
            recentItems: [
                .init(source: "Paycheck", amount: 2200, date: Calendar.current.date(byAdding: .day, value: -3, to: .now) ?? .now, isPlanned: false),
                .init(source: "Side Gig", amount: 350, date: Calendar.current.date(byAdding: .day, value: -9, to: .now) ?? .now, isPlanned: false),
                .init(source: "Bonus", amount: 600, date: Calendar.current.date(byAdding: .day, value: -18, to: .now) ?? .now, isPlanned: true)
            ]
        )
    }

    static var truncationPreview: IncomeWidgetSnapshot {
        IncomeWidgetSnapshot(
            title: NSLocalizedString("Income", comment: "Income widget preview title."),
            periodToken: "P",
            rangeStart: Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1)) ?? .now,
            rangeEnd: Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 31)) ?? .now,
            plannedTotal: 5235.30,
            actualTotal: 2559.32,
            recentItems: [
                .init(source: "International Payroll Deposit", amount: 2494.80, date: Calendar.current.date(byAdding: .day, value: -3, to: .now) ?? .now, isPlanned: false),
                .init(source: "Tax Adjustment Refund", amount: 53.29, date: Calendar.current.date(byAdding: .day, value: -6, to: .now) ?? .now, isPlanned: false),
                .init(source: "Performance Paycheck", amount: 2740.50, date: Calendar.current.date(byAdding: .day, value: -11, to: .now) ?? .now, isPlanned: true),
                .init(source: "Workspace Expense Reimbursement", amount: 10.87, date: Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now, isPlanned: false)
            ]
        )
    }

    static var extraLargeUnderTargetPreview: IncomeWidgetSnapshot {
        IncomeWidgetSnapshot(
            title: NSLocalizedString("Income", comment: "Income widget preview title."),
            periodToken: "P",
            rangeStart: Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 1)) ?? .now,
            rangeEnd: Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 30)) ?? .now,
            plannedTotal: 5_584.00,
            actualTotal: 0,
            recentItems: [
                .init(source: "California EDD", amount: 2_792.00, date: Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 1)) ?? .now, isPlanned: true),
                .init(source: "California EDD", amount: 2_792.00, date: Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15)) ?? .now, isPlanned: true)
            ]
        )
    }

    static var extraLargeOverTargetPreview: IncomeWidgetSnapshot {
        IncomeWidgetSnapshot(
            title: NSLocalizedString("Income", comment: "Income widget preview title."),
            periodToken: "P",
            rangeStart: Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1)) ?? .now,
            rangeEnd: Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 31)) ?? .now,
            plannedTotal: 11_168.00,
            actualTotal: 20_604.40,
            recentItems: [
                .init(source: "California EDD", amount: 2_792.00, date: Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 1)) ?? .now, isPlanned: true),
                .init(source: "California EDD", amount: 2_792.00, date: Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15)) ?? .now, isPlanned: false),
                .init(source: "SDI", amount: 2_792.00, date: Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 1)) ?? .now, isPlanned: true),
                .init(source: "Paycheck", amount: 790.62, date: Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 15)) ?? .now, isPlanned: false)
            ]
        )
    }

    static var extraLargeOnTargetPreview: IncomeWidgetSnapshot {
        IncomeWidgetSnapshot(
            title: NSLocalizedString("Income", comment: "Income widget preview title."),
            periodToken: "P",
            rangeStart: Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 1)) ?? .now,
            rangeEnd: Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 31)) ?? .now,
            plannedTotal: 0,
            actualTotal: 0,
            recentItems: nil
        )
    }
}
