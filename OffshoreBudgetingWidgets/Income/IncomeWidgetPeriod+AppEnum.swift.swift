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
            .period: "Default Period",
            .oneWeek: "1 Week",
            .oneMonth: "1 Month",
            .oneYear: "1 Year",
            .q: "Q"
        ]
    }
}
