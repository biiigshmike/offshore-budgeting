//
//  NextPlannedExpenseWidget.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/7/26.
//

import WidgetKit
import SwiftUI

struct NextPlannedExpenseWidget: Widget {
    static let kind = "NextPlannedExpenseWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: NextPlannedExpenseWidgetConfigurationIntent.self,
            provider: NextPlannedExpenseWidgetProvider()
        ) { entry in
            NextPlannedExpenseWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Next Planned Expense")
        .description("Show upcoming planned expenses for all cards or a selected card.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}
