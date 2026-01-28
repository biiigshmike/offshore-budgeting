//
//  IncomeWidgetConfigurationIntent.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/27/26.
//


import WidgetKit
import AppIntents

struct IncomeWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Income Widget"
    static var description = IntentDescription("Configure the period shown in the Income widget.")

    @Parameter(title: "Period")
    var period: IncomeWidgetPeriod?

    init() {
        self.period = .period
    }
}

extension IncomeWidgetConfigurationIntent {
    var resolvedPeriod: IncomeWidgetPeriod { period ?? .period }
    var resolvedPeriodToken: String { resolvedPeriod.rawValue }
}
