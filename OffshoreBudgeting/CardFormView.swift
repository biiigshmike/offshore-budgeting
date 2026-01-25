//
//  CardFormView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/21/26.
//

import SwiftUI

struct CardFormView: View {

    @Binding var name: String
    @Binding var effect: CardEffectOption
    @Binding var theme: CardThemeOption

    static func trimmedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func canSave(name: String) -> Bool {
        !trimmedName(name).isEmpty
    }

    var body: some View {
        Form {
            Section("Preview") {
                CardVisualView(
                    title: CardFormView.trimmedName(name).isEmpty ? "New Card" : CardFormView.trimmedName(name),
                    theme: theme,
                    effect: effect
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }

            Section("Name") {
                TextField("Apple Card", text: $name)
            }

            Section("Effect") {
                EffectCapsuleGrid(selection: $effect, currentTheme: theme)
            }

            Section("Theme") {
                ThemeCapsuleGrid(selection: $theme)
            }
        }
    }
}

// MARK: - Effect Grid (capsules painted with theme + effect)

private struct EffectCapsuleGrid: View {
    @Binding var selection: CardEffectOption
    let currentTheme: CardThemeOption

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(CardEffectOption.allCases) { option in
                Button {
                    selection = option
                } label: {
                    PaintedCapsule(
                        title: option.displayName,
                        theme: currentTheme,
                        effect: option,
                        isSelected: selection == option,
                        showEffectOverlay: true
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Theme Grid (capsules painted with theme)

private struct ThemeCapsuleGrid: View {
    @Binding var selection: CardThemeOption

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(CardThemeOption.allCases) { option in
                Button {
                    selection = option
                } label: {
                    PaintedCapsule(
                        title: option.displayName,
                        theme: option,
                        effect: .plastic,
                        isSelected: selection == option,
                        showEffectOverlay: false
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Painted Capsule UI

private struct PaintedCapsule: View {
    let title: String
    let theme: CardThemeOption
    let effect: CardEffectOption
    let isSelected: Bool
    let showEffectOverlay: Bool

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: CardThemePalette.colors(for: theme),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.22), lineWidth: 1)
                )
                .overlay(effectOverlay.opacity(showEffectOverlay ? 1 : 0))

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .overlay(
            Capsule(style: .continuous)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 3)
        )
    }

    @ViewBuilder
    private var effectOverlay: some View {
        switch effect {
        case .plastic:
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.40), .white.opacity(0.06), .white.opacity(0.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.screen)

        case .glass:
            Capsule(style: .continuous)
                .fill(.thinMaterial)
                .opacity(0.65)

        case .metal:
            CapsuleBrushedMetalOverlay(
                stripeThickness: 1.0,
                stripeSpacing: 5.0,
                brightAlpha: 0.05,
                dimAlpha: 0.02
            )
            .clipShape(Capsule(style: .continuous))
            .blendMode(.overlay)

        case .holographic:
            CapsuleFoilOverlay()
                .clipShape(Capsule(style: .continuous))
                .blendMode(.overlay)
                .opacity(0.95)
        }
    }
}

// MARK: - Capsule Metal + Foil Overlays (local)

private struct CapsuleBrushedMetalOverlay: View {
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

private struct CapsuleFoilOverlay: View {
    var body: some View {
        AngularGradient(
            colors: [
                .pink.opacity(0.55),
                .purple.opacity(0.55),
                .blue.opacity(0.55),
                .mint.opacity(0.55),
                .yellow.opacity(0.55),
                .pink.opacity(0.55)
            ],
            center: .center
        )
        .opacity(0.95)
        .mask(CapsuleFoilBandsMask().opacity(0.75))
    }
}

private struct CapsuleFoilBandsMask: View {
    var body: some View {
        Canvas { context, size in
            let bandWidth: CGFloat = 16
            let gap: CGFloat = 12
            let total = bandWidth + gap

            context.rotate(by: .degrees(-18))

            let extendedWidth = size.width * 2.0
            let extendedHeight = size.height * 2.0

            var x: CGFloat = -extendedWidth
            while x < extendedWidth * 2 {
                let rect = CGRect(x: x, y: -extendedHeight, width: bandWidth, height: extendedHeight * 3)

                let gradient = GraphicsContext.Shading.linearGradient(
                    Gradient(stops: [
                        .init(color: .white.opacity(0.00), location: 0.0),
                        .init(color: .white.opacity(0.60), location: 0.5),
                        .init(color: .white.opacity(0.00), location: 1.0)
                    ]),
                    startPoint: CGPoint(x: rect.minX, y: rect.midY),
                    endPoint: CGPoint(x: rect.maxX, y: rect.midY)
                )

                context.fill(Path(rect), with: gradient)
                x += total
            }
        }
    }
}

#Preview("Card Form") {
    NavigationStack {
        CardFormView(
            name: .constant("New Card"),
            effect: .constant(.plastic),
            theme: .constant(.rose)
        )
        .navigationTitle("Add Card")
    }
}
