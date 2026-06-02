//
//  SpendTrendsWidgetConfigurationIntent.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/7/26.
//

import WidgetKit
import AppIntents

struct SpendTrendsWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Spend Trends Widget"
    static var description = IntentDescription("Show spend trends for all cards or a selected card.")

    @Parameter(title: "Card Filter")
    var card: SpendTrendsWidgetCardEntity?

    @Parameter(title: "Default Period")
    var period: SpendTrendsWidgetPeriod?

    init() {
        self.card = .allCards
        self.period = .period
    }
}

extension SpendTrendsWidgetConfigurationIntent {
    var resolvedPeriod: SpendTrendsWidgetPeriod { period ?? .period }
    var resolvedPeriodToken: String { resolvedPeriod.rawValue }
    var resolvedCardID: String? {
        guard let card, card.isAllCards == false else { return nil }
        return card.id
    }
}
