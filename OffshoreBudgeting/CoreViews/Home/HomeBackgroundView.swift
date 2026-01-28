//
//  HomeBackgroundView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/24/26.
//

import SwiftUI

struct HomeBackgroundView: View {

    var body: some View {
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
            .ignoresSafeArea()
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
