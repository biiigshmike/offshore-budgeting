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
            .oneWeek: "Current Week",
            .oneMonth: "Current Month",
            .oneYear: "Current Year",
            .q: "Current Quarter"
        ]
    }
}
