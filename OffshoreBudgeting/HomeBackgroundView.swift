//
//  HomeBackgroundView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/24/26.
//

import SwiftUI

struct HomeBackgroundView: View {

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                base

                // Light-mode: pastel wash.
                // Dark-mode: richer glow without crushing everything into black.
                RadialGradient(
                    colors: [
                        Color.blue.opacity(colorScheme == .dark ? 0.35 : 0.16),
                        Color.clear
                    ],
                    center: .topLeading,
                    startRadius: 1,
                    endRadius: proxy.size.width * 0.95
                )

                RadialGradient(
                    colors: [
                        Color.green.opacity(colorScheme == .dark ? 0.26 : 0.13),
                        Color.clear
                    ],
                    center: .topTrailing,
                    startRadius: 1,
                    endRadius: proxy.size.width * 0.95
                )

                RadialGradient(
                    colors: [
                        Color.orange.opacity(colorScheme == .dark ? 0.22 : 0.12),
                        Color.clear
                    ],
                    center: .bottomLeading,
                    startRadius: 1,
                    endRadius: proxy.size.width * 0.95
                )

                RadialGradient(
                    colors: [
                        Color.purple.opacity(colorScheme == .dark ? 0.24 : 0.12),
                        Color.clear
                    ],
                    center: .bottomTrailing,
                    startRadius: 1,
                    endRadius: proxy.size.width * 0.95
                )

                // A subtle top-to-bottom depth gradient, but not a “dark vignette”
                LinearGradient(
                    colors: [
                        Color.black.opacity(colorScheme == .dark ? 0.30 : 0.05),
                        Color.black.opacity(colorScheme == .dark ? 0.55 : 0.08)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .blendMode(.overlay)
            }
            .ignoresSafeArea()
        }
    }

    private var base: some View {
        Group {
            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color(.systemBackground).opacity(0.10),
                        Color.black.opacity(0.90)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                LinearGradient(
                    colors: [
                        Color(.systemGroupedBackground),
                        Color(.secondarySystemGroupedBackground)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }
}
