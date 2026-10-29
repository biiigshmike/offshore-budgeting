import SwiftUI

/// The same card and spending breakdown in Home tiles and saved conversation results.
struct CardSummaryContentView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let themeRaw: String
    let effectRaw: String
    let total: Double
    let planned: Double
    let variable: Double

    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
    }

    var body: some View {
        layout {
            CardVisualView(title: title,
                theme: CardThemeOption(rawValue: themeRaw) ?? .charcoal,
                effect: CardEffectOption(rawValue: effectRaw) ?? .plastic,
                minHeight: nil, showsShadow: false,
                titleFont: .headline.weight(.semibold), titlePadding: 12, titleOpacity: 0.85)
                .frame(width: 120)
            CardSummaryMetricsView(total: total, planned: planned, variable: variable)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
        }
    }
}
