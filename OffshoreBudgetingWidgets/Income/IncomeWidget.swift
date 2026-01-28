//
//  IncomeWidget.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/27/26.
//


import WidgetKit
import SwiftUI

struct IncomeWidget: Widget {
    static let kind = "IncomeWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: IncomeWidgetConfigurationIntent.self,
            provider: IncomeWidgetProvider()
        ) { entry in
            IncomeWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Income")
        .description("Track planned vs actual income for a selected period.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}
