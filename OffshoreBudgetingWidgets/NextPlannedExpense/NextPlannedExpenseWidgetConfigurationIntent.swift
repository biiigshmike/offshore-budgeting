//
//  NextPlannedExpenseWidgetConfigurationIntent.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/7/26.
//

import WidgetKit
import AppIntents

struct NextPlannedExpenseWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Next Planned Expense Widget"
    static var description = IntentDescription("Show the next planned expense for all cards or a selected card.")

    @Parameter(title: "Card Filter")
    var card: NextPlannedExpenseWidgetCardEntity?

    @Parameter(title: "Default Period")
    var period: NextPlannedExpenseWidgetPeriod?

    init() {
        self.card = .allCards
        self.period = .period
    }
}

extension NextPlannedExpenseWidgetConfigurationIntent {
    var resolvedPeriod: NextPlannedExpenseWidgetPeriod { period ?? .period }
    var resolvedPeriodToken: String { resolvedPeriod.rawValue }
    var resolvedCardID: String? {
        guard let card, card.isAllCards == false else { return nil }
        return card.id
    }
}
