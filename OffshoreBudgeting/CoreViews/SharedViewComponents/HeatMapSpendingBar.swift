import SwiftUI

struct HeatMapSpendingBar: View {
    let stops: [Gradient.Stop]

    var body: some View {
        ZStack {
            if !stops.isEmpty {
                LinearGradient(
                    gradient: Gradient(stops: stops),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .saturation(1.75)
                .blur(radius: 36)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.16),
                            Color.white.opacity(0.05),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

