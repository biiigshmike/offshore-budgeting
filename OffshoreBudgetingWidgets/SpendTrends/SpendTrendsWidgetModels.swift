//
//  SpendTrendsWidgetModels.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/7/26.
//

import Foundation
import WidgetKit

struct SpendTrendsWidgetSnapshot: Codable, Hashable {
    let title: String
    let periodToken: String
    let rangeStart: Date
    let rangeEnd: Date
    let totalSpent: Double
    let buckets: [Bucket]
    let highestBucket: HighestBucket?
    let topCategories: [TopCategory]

    struct Bucket: Codable, Hashable, Identifiable {
        let id: String
        let label: String
        let total: Double
        let slices: [Slice]
    }

    struct Slice: Codable, Hashable, Identifiable {
        let id: String
        let name: String
        let hexColor: String?
        let amount: Double
    }

    struct HighestBucket: Codable, Hashable {
        let label: String
        let amount: Double
        let topCategoryName: String
        let topCategoryAmount: Double
        let topCategoryPercentOfBucket: Double
    }

    struct TopCategory: Codable, Hashable, Identifiable {
        let id: String
        let name: String
        let hexColor: String?
        let amount: Double
        let percentOfTotal: Double
    }
}

struct SpendTrendsWidgetEntry: TimelineEntry {
    let date: Date
    let periodToken: String
    let cardID: String?
    let snapshot: SpendTrendsWidgetSnapshot?
}

extension SpendTrendsWidgetSnapshot {
    static var placeholder: SpendTrendsWidgetSnapshot {
        SpendTrendsWidgetSnapshot(
            title: "Spend Trends",
            periodToken: "1M",
            rangeStart: Calendar.current.date(byAdding: .day, value: -29, to: .now) ?? .now,
            rangeEnd: .now,
            totalSpent: 1268,
            buckets: [
                .init(
                    id: "b1",
                    label: "1-4",
                    total: 210,
                    slices: [
                        .init(id: "groceries", name: "Groceries", hexColor: "#10B981", amount: 120),
                        .init(id: "gas", name: "Gas", hexColor: "#3B82F6", amount: 90)
                    ]
                ),
                .init(
                    id: "b2",
                    label: "5-11",
                    total: 330,
                    slices: [
                        .init(id: "groceries2", name: "Groceries", hexColor: "#10B981", amount: 180),
                        .init(id: "dining2", name: "Dining", hexColor: "#F97316", amount: 150)
                    ]
                ),
                .init(
                    id: "b3",
                    label: "12-18",
                    total: 480,
                    slices: [
                        .init(id: "travel3", name: "Travel", hexColor: "#8B5CF6", amount: 290),
                        .init(id: "gas3", name: "Gas", hexColor: "#3B82F6", amount: 190)
                    ]
                ),
                .init(
                    id: "b4",
                    label: "19-25",
                    total: 248,
                    slices: [
                        .init(id: "groceries4", name: "Groceries", hexColor: "#10B981", amount: 170),
                        .init(id: "other4", name: "Other", hexColor: "#6B7280", amount: 78)
                    ]
                )
            ],
            highestBucket: .init(
                label: "12-18",
                amount: 480,
                topCategoryName: "Travel",
                topCategoryAmount: 290,
                topCategoryPercentOfBucket: 0.604
            ),
            topCategories: [
                .init(id: "travel", name: "Travel", hexColor: "#8B5CF6", amount: 290, percentOfTotal: 0.2287),
                .init(id: "groceries", name: "Groceries", hexColor: "#10B981", amount: 470, percentOfTotal: 0.3707),
                .init(id: "gas", name: "Gas", hexColor: "#3B82F6", amount: 280, percentOfTotal: 0.2208),
                .init(id: "dining", name: "Dining", hexColor: "#F97316", amount: 150, percentOfTotal: 0.1183),
                .init(id: "other", name: "Other", hexColor: "#6B7280", amount: 78, percentOfTotal: 0.0615)
            ]
        )
    }
}
