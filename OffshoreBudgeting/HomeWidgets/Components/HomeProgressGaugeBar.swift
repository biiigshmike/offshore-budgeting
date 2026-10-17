import SwiftUI

struct HomeProgressGaugeBar: View {

    let progress: Double
    let barHeight: CGFloat

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let clamped = min(max(progress, 0), 1)
            let fillWidth = width * clamped

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.secondary.opacity(0.22))
                    .frame(height: barHeight)

                Capsule(style: .continuous)
                    .fill(Color.blue.opacity(0.85))
                    .frame(width: fillWidth, height: barHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: barHeight)
    }
}


