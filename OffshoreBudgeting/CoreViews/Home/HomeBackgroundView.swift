//
//  HomeBackgroundView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/24/26.
//

import SwiftUI

struct HomeBackgroundView: View {

    @Environment(\.appearanceTheme) private var theme
    var extendsIntoSafeArea = true

    var body: some View {
        if extendsIntoSafeArea {
            backdrop.ignoresSafeArea()
        } else {
            backdrop
        }
    }

    @ViewBuilder
    private var backdrop: some View {
        if let palette = theme.homeBackgroundPalette {
            presetBackdrop(base: palette.base, highlight: palette.highlight, wash: palette.wash)
        } else {
            offshoreBackdrop
        }
    }

    private func presetBackdrop(base: Color, highlight: Color, wash: Color) -> some View {
        GeometryReader { proxy in
            // Let the washes overlap on tall Home screens and in the short preview.
            let radius = max(proxy.size.width, proxy.size.height * 0.75)

            ZStack {
                LinearGradient(
                    colors: [base.mix(with: highlight, by: 0.18), base, base.mix(with: wash, by: 0.24)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                RadialGradient(
                    colors: [highlight.opacity(0.62), .clear],
                    center: UnitPoint(x: 0.5, y: 0.0),
                    startRadius: 0,
                    endRadius: radius * 0.85
                )
                RadialGradient(
                    colors: [theme.accent.opacity(0.14), .clear],
                    center: UnitPoint(x: 0.5, y: 0.55),
                    startRadius: 0,
                    endRadius: radius * 0.65
                )
                RadialGradient(
                    colors: [wash.opacity(0.58), .clear],
                    center: UnitPoint(x: 0.5, y: 1.15),
                    startRadius: radius * 0.10,
                    endRadius: radius * 0.80
                )
            }
        }
    }

    private var offshoreBackdrop: some View {
        GeometryReader { proxy in
            let minSide = min(proxy.size.width, proxy.size.height)

            ZStack {
                base
                RadialGradient(
                    colors: [
                        Color("OffshoreWave").opacity(0.18),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.5, y: 0.25),
                    startRadius: 1,
                    endRadius: minSide * 0.85
                )
                .blendMode(.screen)
                RadialGradient(
                    colors: [
                        Color("OffshoreSky").opacity(0.4),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.5, y: 0.0),
                    startRadius: 1,
                    endRadius: minSide * 1.05
                )
                RadialGradient(
                    colors: [
                        Color("OffshoreBrand").opacity(0.3),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.5, y: 0.55),
                    startRadius: 1,
                    endRadius: minSide * 0.95
                )
                RadialGradient(
                    colors: [
                        Color("OffshoreSand").opacity(0.55),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.5, y: 1.15),
                    startRadius: minSide * 0.12,
                    endRadius: minSide * 0.95
                )
                .blendMode(.softLight)
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.18),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .center
                )
                .blendMode(.overlay)
            }
        }
    }

    private var base: some View {
        LinearGradient(
            colors: [
                Color("OffshoreSand").opacity(0.4),
                Color("OffshoreWave").opacity(0.1),
                Color("OffshoreBrand").opacity(0.2),
                Color("OffshoreWave").opacity(0.18),
                Color("OffshoreDepth").opacity(0.2),
                Color("OffshoreSky").opacity(0.3)
            ],
            startPoint: .bottom,
            endPoint: .top
        )
    }
}
