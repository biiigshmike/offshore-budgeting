//
//  CardVisualView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/21/26.
//

import SwiftUI

// MARK: - Card Styling Options

enum CardEffectOption: String, CaseIterable, Identifiable {
    case plastic
    case metal
    case holographic
    case glass

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .plastic: return "Plastic"
        case .metal: return "Metal"
        case .holographic: return "Holographic"
        case .glass: return "Glass"
        }
    }
}

enum CardThemeOption: String, CaseIterable, Identifiable {
    case ruby
    case aqua
    case ultraviolet
    case charcoal
    case seafoam
    case sunset
    case midnight
    case emerald
    case sunrise
    case fuschia
    case periwinkle
    case aster

    var id: String { rawValue }

    var displayName: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
}

// MARK: - Theme Palette

enum CardThemePalette {
    static func colors(for theme: CardThemeOption) -> [Color] {
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

// MARK: - Visual Card

struct CardVisualView: View {
    let title: String
    let theme: CardThemeOption
    let effect: CardEffectOption

    /// Optional layout knobs so the same renderer can be used in a hero card and tiny carousel tiles.
    let minHeight: CGFloat?
    let showsShadow: Bool
    let titleFont: Font
    let titlePadding: CGFloat
    let titleOpacity: Double

    init(
        title: String,
        theme: CardThemeOption,
        effect: CardEffectOption,
        minHeight: CGFloat? = 155,
        showsShadow: Bool = true,
        titleFont: Font = .title3.weight(.semibold),
        titlePadding: CGFloat = 16,
        titleOpacity: Double = 0.80
    ) {
        self.title = title
        self.theme = theme
        self.effect = effect
        self.minHeight = minHeight
        self.showsShadow = showsShadow
        self.titleFont = titleFont
        self.titlePadding = titlePadding
        self.titleOpacity = titleOpacity
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(baseGradient)

            effectOverlay

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 1)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 6)
                .blur(radius: 8)
                .mask(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.0), .white.opacity(0.9)],
                                startPoint: .bottomTrailing,
                                endPoint: .topLeading
                            )
                        )
                )

            Text(title)
                .font(titleFont)
                .foregroundStyle(.white.opacity(titleOpacity))
                .padding(titlePadding)
        }
        .aspectRatio(1.586, contentMode: .fit)
        .applyMinHeightIfNeeded(minHeight)
        .applyShadowIfNeeded(showsShadow)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }

    private var baseGradient: LinearGradient {
        LinearGradient(
            colors: CardThemePalette.colors(for: theme),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private var effectOverlay: some View {
        switch effect {

        case .plastic:
            // Plastic = shiny specular streaks, clipped to the card shape
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
            // Glass = translucent material + soft highlight
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
            // Brushed metal: faint HORIZONTAL grain + cool overlay
            BrushedMetalOverlay(
                direction: .horizontal,
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
            // Holographic (Option A, subtle)
            HoloLiquidOverlay(theme: theme)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .blendMode(.overlay)
                .opacity(0.95)
        }
    }
}

// MARK: - Small view modifiers

private extension View {
    @ViewBuilder
    func applyMinHeightIfNeeded(_ minHeight: CGFloat?) -> some View {
        if let minHeight {
            self.frame(minHeight: minHeight)
        } else {
            self
        }
    }

    @ViewBuilder
    func applyShadowIfNeeded(_ enabled: Bool) -> some View {
        if enabled {
            self.shadow(radius: 6, y: 3)
        } else {
            self
        }
    }
}

// MARK: - Brushed Metal Overlay

enum BrushedDirection {
    case horizontal
    case vertical
}

struct BrushedMetalOverlay: View {
    let direction: BrushedDirection

    // tweak knobs
    let stripeThickness: CGFloat
    let stripeSpacing: CGFloat
    let brightAlpha: CGFloat
    let dimAlpha: CGFloat

    var body: some View {
        Canvas { context, size in
            switch direction {
            case .horizontal:
                let step = max(1, stripeSpacing)
                var y: CGFloat = 0

                while y < size.height + step {
                    let rect = CGRect(x: 0, y: y, width: size.width, height: stripeThickness)
                    let isBright = Int(y / step) % 2 == 0
                    let alpha = isBright ? brightAlpha : dimAlpha
                    context.fill(Path(rect), with: .color(.white.opacity(alpha)))
                    y += step
                }

            case .vertical:
                let step = max(1, stripeSpacing)
                var x: CGFloat = 0

                while x < size.width + step {
                    let rect = CGRect(x: x, y: 0, width: stripeThickness, height: size.height)
                    let isBright = Int(x / step) % 2 == 0
                    let alpha = isBright ? brightAlpha : dimAlpha
                    context.fill(Path(rect), with: .color(.white.opacity(alpha)))
                    x += step
                }
            }
        }
    }
}

// MARK: - Holographic (Option A): Liquid Blend + Highlights + Spectral Sheen

private struct HoloLiquidOverlay: View {
    let theme: CardThemeOption

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let colors = CardThemePalette.colors(for: theme)
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

                RadialGradient(
                    colors: [Color.white.opacity(0.20), Color.white.opacity(0.0)],
                    center: .init(x: 0.30, y: 0.20),
                    startRadius: 0,
                    endRadius: min(size.width, size.height) * 0.55
                )
                .blendMode(.screen)

                RadialGradient(
                    colors: [Color.white.opacity(0.12), Color.white.opacity(0.0)],
                    center: .init(x: 0.78, y: 0.60),
                    startRadius: 0,
                    endRadius: min(size.width, size.height) * 0.60
                )
                .blendMode(.screen)

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
}
