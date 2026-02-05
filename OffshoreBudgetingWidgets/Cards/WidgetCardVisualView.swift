//
//  WidgetCardVisualView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/27/26.
//

import SwiftUI

struct WidgetCardVisualView: View {
    let title: String
    let themeToken: String
    let effectToken: String

    let showsTitle: Bool
    let titleFont: Font
    let titlePadding: CGFloat
    let titleOpacity: Double

    init(
        title: String,
        themeToken: String,
        effectToken: String,
        showsTitle: Bool = true,
        titleFont: Font = .title3.weight(.semibold),
        titlePadding: CGFloat = 16,
        titleOpacity: Double = 0.80
    ) {
        self.title = title
        self.themeToken = themeToken
        self.effectToken = effectToken
        self.showsTitle = showsTitle
        self.titleFont = titleFont
        self.titlePadding = titlePadding
        self.titleOpacity = titleOpacity
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(baseGradient)

            overlayEffect

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)

            if showsTitle {
                Text(title)
                    .font(titleFont)
                    .foregroundStyle(.white.opacity(titleOpacity))
                    .padding(titlePadding)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
            }
        }
        .aspectRatio(1.586, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }

    private var baseGradient: LinearGradient {
        LinearGradient(
            colors: paletteColors(for: themeToken),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private var overlayEffect: some View {
        switch effectToken.lowercased() {
        case "glass":
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.thinMaterial)
                .opacity(0.60)

        case "metal":
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.10), .black.opacity(0.18)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .opacity(0.9)
                .blendMode(.overlay)

        case "holographic":
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            .pink.opacity(0.18),
                            .purple.opacity(0.14),
                            .blue.opacity(0.16),
                            .mint.opacity(0.14),
                            .yellow.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .opacity(0.9)
                .blendMode(.overlay)

        default:
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.22), .white.opacity(0.06), .white.opacity(0.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .opacity(0.9)
                .blendMode(.screen)
        }
    }

    private func paletteColors(for token: String) -> [Color] {
        switch token.lowercased() {
        case "rose": return [.pink, .red.opacity(0.85)]
        case "ocean": return [.teal, .blue.opacity(0.9)]
        case "violet": return [.purple, .indigo.opacity(0.9)]
        case "mint": return [.mint, .teal.opacity(0.9)]
        case "sunset": return [.orange, .pink.opacity(0.9)]
        case "midnight": return [.black, .indigo.opacity(0.9)]
        case "forest": return [.green, .teal.opacity(0.85)]
        case "sunrise": return [.yellow, .orange.opacity(0.95)]
        case "blossom": return [.pink, .purple.opacity(0.8)]
        case "lavender": return [.purple.opacity(0.65), .blue.opacity(0.8)]
        case "nebula": return [.indigo, .purple.opacity(0.95)]
        default: return [.black.opacity(0.9), .gray.opacity(0.85)]
        }
    }
}
