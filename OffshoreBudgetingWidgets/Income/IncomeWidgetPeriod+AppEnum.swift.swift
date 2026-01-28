//
//  IncomeWidgetPeriod+AppEnum.swift.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/27/26.
//

import AppIntents

extension IncomeWidgetPeriod: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Period" }

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
