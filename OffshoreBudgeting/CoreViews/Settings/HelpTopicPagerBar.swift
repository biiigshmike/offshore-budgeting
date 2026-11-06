import SwiftUI

struct HelpTopicPagerBar: View {
    let previousTitle: String?
    let nextTitle: String?
    let onBack: () -> Void
    let onNext: () -> Void

    var body: some View {
        let back = String(localized: "common.back", defaultValue: "Back", comment: "Back action label.")
        let next = String(localized: "common.next", defaultValue: "Next", comment: "Next action label.")
        let previousTopic = previousTitle ?? String(localized: "help.startOfSection", defaultValue: "Start of Section")
        let nextTopic = nextTitle ?? String(localized: "help.endOfSection", defaultValue: "End of Section")

        HStack(spacing: 12) {
            TintedGlassNavigationButton(
                title: Text(back), tint: .gray, action: onBack
            )
                .accessibilityLabel(Text(verbatim: "\(back), \(previousTopic)"))
                .accessibilityIdentifier("helpPagerBack")
                .disabled(previousTitle == nil)

            TintedGlassNavigationButton(
                title: Text(next), tint: .accentColor, action: onNext
            )
                .accessibilityLabel(Text(verbatim: "\(next), \(nextTopic)"))
                .accessibilityIdentifier("helpPagerNext")
                .disabled(nextTitle == nil)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
    }
}
