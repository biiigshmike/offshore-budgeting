//
//  WaveBackdrop.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/27/26.
//


import SwiftUI

/// Reusable animated backdrop intended for onboarding welcome screens.
/// Subtle at rest, can intensify when transitioning away.
struct WaveBackdrop: View {

    let isExiting: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            baseGradient

            if !reduceMotion {
                RefractionPlaceholder(
                    intensity: refractionIntensity,
                    speed: refractionSpeed,
                    blobOpacity: blobOpacity,
                    blobScale: blobScale
                )
                .blendMode(refractionBlendMode)
                .opacity(refractionLayerOpacity)
            }

            readabilityVignette
        }
        .ignoresSafeArea()
        .compositingGroup()
    }

    // MARK: - Tuning

    private var isDarkMode: Bool { colorScheme == .dark }

    /// Overall intensity for how much the “water” should read.
    private var refractionIntensity: Double {
        // Dark mode reads stronger, so tone it down.
        // Light mode needs a boost or it disappears.
        let base = isDarkMode ? 0.32 : 0.70
        return base * (isExiting ? 1.15 : 1.0)
    }

    private var refractionSpeed: Double {
        (isExiting ? 1.0 : 0.35)
    }

    /// How visible the refraction layer is.
    private var refractionLayerOpacity: Double {
        // Light mode needs more presence. Dark mode needs restraint.
        let base = isDarkMode ? 0.62 : 0.92
        return base * (isExiting ? 1.0 : 0.95)
    }

    /// Blend mode that behaves better per scheme.
    private var refractionBlendMode: BlendMode {
        // In light mode, overlay can be too polite, screen is usually more readable.
        // In dark mode, overlay is gorgeous.
        return isDarkMode ? .overlay : .screen
    }

    /// Individual blob “brightness” contribution.
    private var blobOpacity: Double {
        // Light mode: lift the blobs so they show up
        // Dark mode: soften to avoid “pool party”
        isDarkMode ? 0.07 : 0.16
    }

    /// iPhone needs slightly smaller, more frequent shapes.
    /// Big canvases can handle larger blobs.
    private var blobScale: Double {
        // This is a simple heuristic that works well cross-device:
        // smaller scale means more shapes visible on iPhone.
        return isExiting ? 1.0 : 0.92
    }

    // MARK: - Layers

    private var baseGradient: some View {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.34),
                Color.accentColor.opacity(isDarkMode ? 0.12 : 0.10),
                Color(.systemBackground)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var readabilityVignette: some View {
        RadialGradient(
            colors: [
                Color.black.opacity(isDarkMode ? 0.18 : 0.10),
                Color.black.opacity(isDarkMode ? 0.06 : 0.03),
                Color.clear
            ],
            center: .top,
            startRadius: 60,
            endRadius: 620
        )
        .blendMode(.multiply)
        .opacity(isDarkMode ? 0.28 : 0.22)
    }
}


/// Placeholder “living light” layer that feels like gentle water refraction.
/// Not literal waves. This is intentionally subtle and non-tacky.
private struct RefractionPlaceholder: View {

    let intensity: Double
    let speed: Double

    /// Base opacity for blob fills (adaptive via WaveBackdrop)
    let blobOpacity: Double

    /// Scale multiplier for blob sizes (adaptive via WaveBackdrop)
    let blobScale: Double

    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Circle()
                    .fill(.white.opacity(blobOpacity * 1.0 * intensity))
                    .frame(
                        width: geo.size.width * 0.95 * blobScale,
                        height: geo.size.width * 0.95 * blobScale
                    )
                    .blur(radius: 44)
                    .offset(
                        x: -geo.size.width * 0.18 + sin(phase) * 28,
                        y: -geo.size.height * 0.28 + cos(phase * 0.92) * 24
                    )

                Circle()
                    .fill(.white.opacity(blobOpacity * 0.85 * intensity))
                    .frame(
                        width: geo.size.width * 0.70 * blobScale,
                        height: geo.size.width * 0.70 * blobScale
                    )
                    .blur(radius: 52)
                    .offset(
                        x: geo.size.width * 0.26 + cos(phase * 0.82) * 30,
                        y: geo.size.height * 0.12 + sin(phase * 1.08) * 22
                    )

                Circle()
                    .fill(.white.opacity(blobOpacity * 0.70 * intensity))
                    .frame(
                        width: geo.size.width * 1.08 * blobScale,
                        height: geo.size.width * 1.08 * blobScale
                    )
                    .blur(radius: 64)
                    .offset(
                        x: geo.size.width * 0.04 + sin(phase * 0.68) * 18,
                        y: geo.size.height * 0.36 + cos(phase * 0.62) * 16
                    )

                // Extra smaller caustic hint that helps iPhone not feel like “one flash”
                Circle()
                    .fill(.white.opacity(blobOpacity * 0.55 * intensity))
                    .frame(
                        width: geo.size.width * 0.42 * blobScale,
                        height: geo.size.width * 0.42 * blobScale
                    )
                    .blur(radius: 36)
                    .offset(
                        x: -geo.size.width * 0.06 + cos(phase * 1.32) * 22,
                        y: geo.size.height * 0.22 + sin(phase * 1.18) * 18
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { restartAnimation() }
            .onChange(of: speed) { _, _ in restartAnimation() }
        }
    }

    private func restartAnimation() {
        phase = 0
        withAnimation(.linear(duration: 30 / max(speed, 0.01)).repeatForever(autoreverses: false)) {
            phase = .pi * 2
        }
    }
}
