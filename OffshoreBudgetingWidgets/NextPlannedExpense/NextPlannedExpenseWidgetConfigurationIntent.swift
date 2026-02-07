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

    @Parameter(title: "Card")
    var card: NextPlannedExpenseWidgetCardEntity?

    @Parameter(title: "Period")
    var period: NextPlannedExpenseWidgetPeriod?

    init() {
        self.card = nil
        self.period = .period
    }
}

extension NextPlannedExpenseWidgetConfigurationIntent {
    var resolvedPeriod: NextPlannedExpenseWidgetPeriod { period ?? .period }
    var resolvedPeriodToken: String { resolvedPeriod.rawValue }
    var resolvedCardID: String? { card?.id }
}
