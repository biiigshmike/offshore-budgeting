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

/// The expense picker artwork at a size suitable for a list row.
struct SharedRowCardArtwork: View {
    let name: String
    let themeRaw: String
    let effectRaw: String

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            if let image = EntityMenuImageCache.card(
                themeRaw: themeRaw,
                effectRaw: effectRaw,
                colorScheme: colorScheme,
                scale: displayScale
            ) {
                Image(uiImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "creditcard")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 20, height: 13)
        .accessibilityLabel(Text("Card: \(name)"))
    }
}
