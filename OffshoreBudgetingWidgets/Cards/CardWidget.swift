//
//  CardWidget.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/27/26.
//

import WidgetKit
import SwiftUI

struct CardWidget: Widget {
    static let kind = "CardWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: CardWidgetConfigurationIntent.self,
            provider: CardWidgetProvider()
        ) { entry in
            CardWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Card")
        .description("Show a card preview with spending for a selected period.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}
