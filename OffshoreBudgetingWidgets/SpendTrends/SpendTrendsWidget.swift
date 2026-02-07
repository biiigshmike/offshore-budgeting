//
//  SpendTrendsWidget.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/7/26.
//

import WidgetKit
import SwiftUI

struct SpendTrendsWidget: Widget {
    static let kind = "SpendTrendsWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: SpendTrendsWidgetConfigurationIntent.self,
            provider: SpendTrendsWidgetProvider()
        ) { entry in
            SpendTrendsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Spend Trends")
        .description("Track spending trends and top categories for a selected period.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}
