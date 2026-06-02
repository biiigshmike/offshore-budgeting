//
//  SpendTrendsWidgetPeriod+AppEnum.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/7/26.
//

import AppIntents

extension SpendTrendsWidgetPeriod: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Period" }

    static var caseDisplayRepresentations: [SpendTrendsWidgetPeriod: DisplayRepresentation] {
        [
            .period: "Default Period",
            .oneWeek: "Current Week",
            .oneMonth: "Current Month",
            .oneYear: "Current Year",
            .q: "Current Quarter"
        ]
    }
}
