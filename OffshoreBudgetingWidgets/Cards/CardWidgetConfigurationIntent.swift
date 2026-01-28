//
//  CardWidgetConfigurationIntent.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/27/26.
//

import WidgetKit
import AppIntents

struct CardWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Card Widget"
    static var description = IntentDescription("Show a card and its expenses for a selected period.")

    @Parameter(title: "Card")
    var card: CardWidgetCardEntity?

    @Parameter(title: "Period")
    var period: CardWidgetPeriod?

    init() {
        self.card = nil
        self.period = .period
    }
}

extension CardWidgetConfigurationIntent {
    var resolvedPeriod: CardWidgetPeriod { period ?? .period }
    var resolvedPeriodToken: String { resolvedPeriod.rawValue }
    var resolvedCardID: String? { card?.id }
}
