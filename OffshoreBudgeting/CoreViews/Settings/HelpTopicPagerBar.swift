import SwiftUI

struct HelpTopicPagerBar: View {
    let previousTitle: String?
    let nextTitle: String?
    let onBack: () -> Void
    let onNext: () -> Void

    // Match the five-tab landscape bar at standard text sizes.
    private static let maxWidth: CGFloat = 488
    private static let verticalGlassInset: CGFloat = 4

    var body: some View {
        let back = String(localized: "common.back", defaultValue: "Back", comment: "Back action label.")
        let next = String(localized: "common.next", defaultValue: "Next", comment: "Next action label.")
        let previousTopic = previousTitle ?? String(localized: "help.startOfSection", defaultValue: "Start of Section")
        let nextTopic = nextTitle ?? String(localized: "help.endOfSection", defaultValue: "End of Section")

        HStack(spacing: 12) {
            TintedGlassNavigationButton(
                title: Text(back), tint: .gray, verticalGlassInset: Self.verticalGlassInset, action: onBack
            )
                .accessibilityLabel(Text(verbatim: "\(back), \(previousTopic)"))
                .accessibilityIdentifier("helpPagerBack")
                .disabled(previousTitle == nil)

            TintedGlassNavigationButton(
                title: Text(next), tint: .accentColor, verticalGlassInset: Self.verticalGlassInset, action: onNext
            )
                .accessibilityLabel(Text(verbatim: "\(next), \(nextTopic)"))
                .accessibilityIdentifier("helpPagerNext")
                .disabled(nextTitle == nil)
        }
        .frame(maxWidth: Self.maxWidth)
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
    }
}
