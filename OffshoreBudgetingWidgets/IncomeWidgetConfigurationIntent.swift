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

// MARK: - Period Enum

enum IncomeWidgetPeriod: String, CaseIterable, AppEnum {
    case period = "P"
    case oneWeek = "1W"
    case oneMonth = "1M"
    case oneYear = "1Y"
    case q1 = "Q1"
    case q2 = "Q2"
    case q3 = "Q3"
    case q4 = "Q4"

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Period"
    }

    static var caseDisplayRepresentations: [IncomeWidgetPeriod: DisplayRepresentation] {
        [
            .period: "Pay Period",
            .oneWeek: "1 Week",
            .oneMonth: "1 Month",
            .oneYear: "1 Year",
            .q1: "Q1",
            .q2: "Q2",
            .q3: "Q3",
            .q4: "Q4"
        ]
    }
}

// MARK: - Convenience

extension IncomeWidgetConfigurationIntent {
    var resolvedPeriod: IncomeWidgetPeriod {
        period ?? .period
    }

    var resolvedPeriodToken: String {
        resolvedPeriod.rawValue
    }
}
