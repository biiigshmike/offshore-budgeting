//
//  CardWidgetModels.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/27/26.
//

import Foundation
import WidgetKit

nonisolated enum WidgetCardVisualTheme: String, CaseIterable, Hashable {
    case ruby
    case aqua
    case ultraviolet
    case charcoal
    case seafoam
    case sunset
    case midnight
    case emerald
    case sunrise
    case fuschia
    case periwinkle
    case aster

    static let defaultTheme: WidgetCardVisualTheme = .ruby

    static func resolve(_ token: String) -> WidgetCardVisualTheme {
        switch token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case ruby.rawValue, "rose":
            return .ruby
        case aqua.rawValue, "ocean":
            return .aqua
        case ultraviolet.rawValue, "violet":
            return .ultraviolet
        case charcoal.rawValue, "graphite":
            return .charcoal
        case seafoam.rawValue, "mint":
            return .seafoam
        case sunset.rawValue:
            return .sunset
        case midnight.rawValue:
            return .midnight
        case emerald.rawValue, "forest":
            return .emerald
        case sunrise.rawValue:
            return .sunrise
        case fuschia.rawValue, "blossom", "fuchsia":
            return .fuschia
        case periwinkle.rawValue, "lavender":
            return .periwinkle
        case aster.rawValue, "nebula":
            return .aster
        default:
            return defaultTheme
        }
    }
}

nonisolated enum WidgetCardVisualEffect: String, CaseIterable, Hashable {
    case plastic
    case metal
    case holographic
    case glass

    static let defaultEffect: WidgetCardVisualEffect = .plastic

    static func resolve(_ token: String) -> WidgetCardVisualEffect {
        switch token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case metal.rawValue:
            return .metal
        case holographic.rawValue:
            return .holographic
        case glass.rawValue:
            return .glass
        case plastic.rawValue, "none":
            return .plastic
        default:
            return defaultEffect
        }
    }
}

nonisolated struct CardWidgetSnapshot: Codable, Hashable {
    let title: String                 // Card name
    let cardID: String
    let themeToken: String
    let effectToken: String

    let periodToken: String
    let rangeStart: Date
    let rangeEnd: Date

    let unifiedExpensesTotal: Double
    let recentItems: [CardWidgetRecentItem]?

    nonisolated struct CardWidgetRecentItem: Codable, Hashable {
        let name: String
        let amount: Double
        let date: Date
        let categoryHex: String?
    }
}

nonisolated struct CardWidgetEntry: TimelineEntry {
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
            themeToken: WidgetCardVisualTheme.ruby.rawValue,
            effectToken: WidgetCardVisualEffect.plastic.rawValue,
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
