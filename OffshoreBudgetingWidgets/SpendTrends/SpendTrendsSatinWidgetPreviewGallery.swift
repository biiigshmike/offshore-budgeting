#if DEBUG
import SwiftUI
import WidgetKit

/// Native widget previews below expose Xcode's full-color/tinted and accessibility environment controls.
struct SpendTrendsSatinWidgetPreviewGallery: View {
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.fixed(360)), GridItem(.fixed(360))], spacing: 20) {
                ForEach(SpendTrendsSatinPreviewFixtures.widgetScenarios.indices, id: \.self) { index in
                    let scenario = SpendTrendsSatinPreviewFixtures.widgetScenarios[index]
                    VStack(alignment: .leading, spacing: 8) {
                        Text(scenario.name).font(.headline)
                        SpendTrendsWidgetMediumView(snapshot: scenario.snapshot)
                            .frame(width: 360, height: 170)
                            .background(.background, in: RoundedRectangle(cornerRadius: 24))
                    }
                }
            }
            .padding(20)
        }
        .background(.secondary.opacity(0.12))
    }
}

#Preview("Satin Widget Periods · Light") {
    SpendTrendsSatinWidgetPreviewGallery()
        .frame(width: 780, height: 1000)
        .preferredColorScheme(.light)
}

#Preview("Satin Widget Periods · Dark") {
    SpendTrendsSatinWidgetPreviewGallery()
        .frame(width: 780, height: 1000)
        .preferredColorScheme(.dark)
}

#Preview("Satin Small", as: .systemSmall) {
    SpendTrendsWidget()
} timeline: {
    SpendTrendsSatinPreviewFixtures.entry
    SpendTrendsWidgetEntry(date: SpendTrendsSatinPreviewFixtures.yearly.rangeEnd, periodToken: "1Y", cardID: nil, snapshot: SpendTrendsSatinPreviewFixtures.yearly)
}

#Preview("Satin Medium", as: .systemMedium) {
    SpendTrendsWidget()
} timeline: {
    SpendTrendsSatinPreviewFixtures.entry
    SpendTrendsWidgetEntry(date: SpendTrendsSatinPreviewFixtures.yearly.rangeEnd, periodToken: "1Y", cardID: nil, snapshot: SpendTrendsSatinPreviewFixtures.yearly)
}

#Preview("Satin Large", as: .systemLarge) {
    SpendTrendsWidget()
} timeline: {
    SpendTrendsSatinPreviewFixtures.entry
    SpendTrendsWidgetEntry(date: SpendTrendsSatinPreviewFixtures.yearly.rangeEnd, periodToken: "1Y", cardID: nil, snapshot: SpendTrendsSatinPreviewFixtures.yearly)
}

#Preview("Satin Extra Large", as: .systemExtraLarge) {
    SpendTrendsWidget()
} timeline: {
    SpendTrendsSatinPreviewFixtures.entry
    SpendTrendsWidgetEntry(date: SpendTrendsSatinPreviewFixtures.yearly.rangeEnd, periodToken: "1Y", cardID: nil, snapshot: SpendTrendsSatinPreviewFixtures.yearly)
}

#Preview("Satin Yearly · Small Dark") {
    SpendTrendsWidgetSmallView(snapshot: SpendTrendsSatinPreviewFixtures.yearly)
        .frame(width: 170, height: 170)
        .background(.background, in: RoundedRectangle(cornerRadius: 24))
        .preferredColorScheme(.dark)
}
#endif
