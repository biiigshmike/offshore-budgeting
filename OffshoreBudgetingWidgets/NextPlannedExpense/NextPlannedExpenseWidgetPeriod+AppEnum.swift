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
            .oneWeek: "Current Week",
            .oneMonth: "Current Month",
            .oneYear: "Current Year",
            .q: "Current Quarter"
        ]
    }
}
