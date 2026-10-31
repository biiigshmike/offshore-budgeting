import SwiftUI

/// Uses an intrinsic-size image so the same label works in a native menu and
/// on its closed picker, while the full card name remains available to VoiceOver.
struct CardMenuLabel: View {
    let card: Card?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Label {
            if let card {
                Text(card.name)
            } else {
                Text("Choose a Card")
            }
        } icon: {
            if let card,
               let image = EntityMenuImageCache.card(
                themeRaw: card.theme,
                effectRaw: card.effect,
                colorScheme: colorScheme,
                scale: displayScale
               ) {
                Image(uiImage: image)
                    .renderingMode(.original)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "creditcard")
                    .accessibilityHidden(true)
            }
        }
    }
}
