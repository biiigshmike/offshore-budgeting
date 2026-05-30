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
    let titleLineLimit: Int

    init(
        title: String,
        themeToken: String,
        effectToken: String,
        showsTitle: Bool = true,
        titleFont: Font = .title3.weight(.semibold),
        titlePadding: CGFloat = 16,
        titleOpacity: Double = 0.80,
        titleLineLimit: Int = 1
    ) {
        self.title = title
        self.themeToken = themeToken
        self.effectToken = effectToken
        self.showsTitle = showsTitle
        self.titleFont = titleFont
        self.titlePadding = titlePadding
        self.titleOpacity = titleOpacity
        self.titleLineLimit = titleLineLimit
    }

    private var resolvedTheme: WidgetCardVisualTheme {
        WidgetCardVisualTheme.resolve(themeToken)
    }

    private var resolvedEffect: WidgetCardVisualEffect {
        WidgetCardVisualEffect.resolve(effectToken)
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
                    .lineLimit(titleLineLimit)
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
            colors: paletteColors(for: resolvedTheme),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private var overlayEffect: some View {
        switch resolvedEffect {
        case .plastic:
            let cardShape = RoundedRectangle(cornerRadius: 18, style: .continuous)

            ZStack {
                cardShape
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.42),
                                .white.opacity(0.08),
                                .white.opacity(0.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.screen)

                cardShape
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.0),
                                .white.opacity(0.22),
                                .white.opacity(0.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .rotationEffect(.degrees(-18))
                    .blendMode(.overlay)
                    .opacity(0.9)
            }
            .mask(cardShape)

        case .glass:
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.thinMaterial)
                .opacity(0.68)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.18),
                            .white.opacity(0.06),
                            .white.opacity(0.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.overlay)
                .opacity(0.95)

        case .metal:
            WidgetBrushedMetalOverlay(
                stripeThickness: 1.0,
                stripeSpacing: 5.0,
                brightAlpha: 0.06,
                dimAlpha: 0.025
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .blendMode(.overlay)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.10),
                            .black.opacity(0.20)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blendMode(.overlay)
                .opacity(0.9)

        case .holographic:
            WidgetHoloLiquidOverlay(theme: resolvedTheme)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .blendMode(.overlay)
                .opacity(0.95)
        }
    }

    private func paletteColors(for theme: WidgetCardVisualTheme) -> [Color] {
        switch theme {
        case .ruby: return [.pink, .red.opacity(0.85)]
        case .aqua: return [.teal, .blue.opacity(0.9)]
        case .ultraviolet: return [.purple, .indigo.opacity(0.9)]
        case .charcoal: return [.black.opacity(0.9), .gray.opacity(0.85)]
        case .seafoam: return [.mint, .teal.opacity(0.9)]
        case .sunset: return [.orange, .pink.opacity(0.9)]
        case .midnight: return [.black, .indigo.opacity(0.9)]
        case .emerald: return [.green, .teal.opacity(0.85)]
        case .sunrise: return [.yellow, .orange.opacity(0.95)]
        case .fuschia: return [.pink, .purple.opacity(0.8)]
        case .periwinkle: return [.purple.opacity(0.65), .blue.opacity(0.8)]
        case .aster: return [.indigo, .purple.opacity(0.95)]
        }
    }
}

private struct WidgetBrushedMetalOverlay: View {
    let stripeThickness: CGFloat
    let stripeSpacing: CGFloat
    let brightAlpha: CGFloat
    let dimAlpha: CGFloat

    var body: some View {
        Canvas { context, size in
            let step = max(1, stripeSpacing)
            var y: CGFloat = 0

            while y < size.height + step {
                let rect = CGRect(x: 0, y: y, width: size.width, height: stripeThickness)
                let isBright = Int(y / step) % 2 == 0
                let alpha = isBright ? brightAlpha : dimAlpha
                context.fill(Path(rect), with: .color(.white.opacity(alpha)))
                y += step
            }
        }
    }
}

private struct WidgetHoloLiquidOverlay: View {
    let theme: WidgetCardVisualTheme

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let colors = paletteColors(for: theme)
            let c1 = colors.first ?? .pink
            let c2 = colors.dropFirst().first ?? .purple

            ZStack {
                RadialGradient(
                    colors: [Color.black.opacity(0.22), Color.black.opacity(0.0)],
                    center: .init(x: 0.18, y: 0.22),
                    startRadius: 0,
                    endRadius: min(size.width, size.height) * 0.60
                )
                .blendMode(.multiply)

                RadialGradient(
                    colors: [Color.black.opacity(0.18), Color.black.opacity(0.0)],
                    center: .init(x: 0.86, y: 0.80),
                    startRadius: 0,
                    endRadius: min(size.width, size.height) * 0.70
                )
                .blendMode(.multiply)

                RadialGradient(
                    colors: [c1.opacity(0.55), c1.opacity(0.0)],
                    center: .init(x: 0.22, y: 0.72),
                    startRadius: 0,
                    endRadius: min(size.width, size.height) * 0.65
                )
                .blendMode(.overlay)

                RadialGradient(
                    colors: [c2.opacity(0.50), c2.opacity(0.0)],
                    center: .init(x: 0.78, y: 0.30),
                    startRadius: 0,
                    endRadius: min(size.width, size.height) * 0.60
                )
                .blendMode(.overlay)

                RadialGradient(
                    colors: [c1.opacity(0.22), c2.opacity(0.18), Color.clear],
                    center: .init(x: 0.55, y: 0.55),
                    startRadius: 0,
                    endRadius: min(size.width, size.height) * 0.75
                )
                .blendMode(.overlay)

                AngularGradient(
                    colors: [
                        .pink.opacity(0.22),
                        .purple.opacity(0.18),
                        .blue.opacity(0.20),
                        .mint.opacity(0.18),
                        .yellow.opacity(0.16),
                        .pink.opacity(0.22)
                    ],
                    center: .center
                )
                .opacity(0.35)
                .mask(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.85),
                            Color.white.opacity(0.0)
                        ],
                        center: .init(x: 0.62, y: 0.38),
                        startRadius: min(size.width, size.height) * 0.10,
                        endRadius: min(size.width, size.height) * 0.85
                    )
                )
                .blendMode(.screen)

                LinearGradient(
                    colors: [
                        .white.opacity(0.0),
                        .white.opacity(0.10),
                        .white.opacity(0.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(.overlay)
                .opacity(0.55)
            }
        }
    }

    private func paletteColors(for theme: WidgetCardVisualTheme) -> [Color] {
        switch theme {
        case .ruby: return [.pink, .red.opacity(0.85)]
        case .aqua: return [.teal, .blue.opacity(0.9)]
        case .ultraviolet: return [.purple, .indigo.opacity(0.9)]
        case .charcoal: return [.black.opacity(0.9), .gray.opacity(0.85)]
        case .seafoam: return [.mint, .teal.opacity(0.9)]
        case .sunset: return [.orange, .pink.opacity(0.9)]
        case .midnight: return [.black, .indigo.opacity(0.9)]
        case .emerald: return [.green, .teal.opacity(0.85)]
        case .sunrise: return [.yellow, .orange.opacity(0.95)]
        case .fuschia: return [.pink, .purple.opacity(0.8)]
        case .periwinkle: return [.purple.opacity(0.65), .blue.opacity(0.8)]
        case .aster: return [.indigo, .purple.opacity(0.95)]
        }
    }
}
