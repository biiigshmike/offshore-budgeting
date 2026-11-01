import SwiftUI

/// Shared by Home, metric detail, and WidgetKit; dimensions are resolved by the chart.
struct SpendTrendsSatinBar: View {
    @Environment(\.colorSchemeContrast) private var contrast

    let segments: [SpendTrendsBarSegment]
    let width: CGFloat
    let height: CGFloat
    var isSelected = false

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: SpendTrendsBarStyle.cornerRadius(width: width, height: height),
            style: .continuous
        )
        let stops = SpendTrendsBarGeometry.stops(
            amounts: segments.map(\.amount), width: width, height: height
        )
        let gradientStops = stops.map {
            Gradient.Stop(color: segments[$0.segmentIndex].color, location: $0.location)
        }
        let fill: AnyShapeStyle = if let first = gradientStops.first, gradientStops.count == 2 {
            AnyShapeStyle(first.color)
        } else if gradientStops.isEmpty {
            AnyShapeStyle(Color.secondary)
        } else {
            AnyShapeStyle(LinearGradient(stops: gradientStops, startPoint: .bottom, endPoint: .top))
        }

        shape
            .fill(fill)
            .overlay {
                shape.fill(
                    LinearGradient(colors: [.white.opacity(0.05), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                )
            }
            .overlay {
                if isSelected || contrast == .increased {
                    shape.strokeBorder(.primary.opacity(isSelected ? 0.65 : 0.5),
                                       lineWidth: isSelected ? 1.5 : 1)
                }
            }
            .frame(width: width, height: height)
    }
}
