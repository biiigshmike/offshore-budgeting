//
//  NextPlannedExpenseWidgetPeriod+AppEnum.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/7/26.
//

import AppIntents

extension NextPlannedExpenseWidgetPeriod: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Period" }

    static var caseDisplayRepresentations: [NextPlannedExpenseWidgetPeriod: DisplayRepresentation] {
        [
            .period: "Default Period",
            .oneWeek: "1 Week",
            .oneMonth: "1 Month",
            .oneYear: "1 Year",
            .q: "Q"
        ]
    }
}
