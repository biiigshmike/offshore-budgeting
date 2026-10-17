import SwiftUI

// MARK: - Pill Bar (scaled, feathered gradient only, no blur)

struct SpendTrendsScaledPillBar: View {

    let bucket: HomeSpendTrendBucket
    let maxTotal: Double
    let availableHeight: CGFloat
    let barWidth: CGFloat
    let colorForSlice: (HomeSpendTrendSlice) -> Color
    private let displayEpsilon: Double = 0

    var body: some View {
        let fraction = min(1.0, max(0.0, bucket.total / max(0.000_1, maxTotal)))
        let barHeight = max(2, availableHeight * CGFloat(fraction))

        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let gradient = featheredGradient(bucket: bucket)

        VStack(spacing: 0) {
            Spacer(minLength: 0)

            if bucket.total > displayEpsilon {
                ZStack(alignment: .bottom) {
                    shape
                        .fill(gradient)
                        .frame(width: barWidth, height: barHeight)

                    shape
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                        .frame(width: barWidth, height: barHeight)
                }
            } else {
                // I keep a "transparent bar" here so zero buckets still reserve their slot width.
                // Without this, the HStack can compress and labels drift away from their bars.
                Color.clear
                    .frame(width: barWidth, height: 2)
            }
        }
    }

    /// Feathered gradient: blends colors at boundaries without blur, so nothing can “float”.
    private func featheredGradient(bucket: HomeSpendTrendBucket) -> LinearGradient {
        let slices = bucket.slices
            .filter { $0.amount > 0 }
            .sorted { $0.amount > $1.amount }

        let total = max(bucket.total, 0.000_1)

        func clamp(_ x: Double) -> Double {
            min(1.0, max(0.0, x))
        }

        let feather: Double = 0.055

        let colors = slices.map { colorForSlice($0) }
        guard let firstColor = colors.first else {
            return LinearGradient(
                colors: [.secondary],
                startPoint: .bottom,
                endPoint: .top
            )
        }

        var rawStops: [Gradient.Stop] = []

        // Always start at 0
        rawStops.append(.init(color: firstColor, location: 0))

        var running: Double = 0

        for i in 0..<(slices.count - 1) {
            running += slices[i].amount
            let p = clamp(running / total)

            let left = clamp(p - feather)
            let right = clamp(p + feather)

            let a = colors[i]
            let b = colors[i + 1]

            // Only add if they make sense
            if left > 0 {
                rawStops.append(.init(color: a, location: left))
            }

            if right < 1 {
                rawStops.append(.init(color: b, location: right))
            }
        }

        // Always end at 1
        rawStops.append(.init(color: colors.last ?? firstColor, location: 1))

        // FINAL SAFETY PASS
        // Sort and remove any out-of-order / duplicate locations
        let stops = rawStops
            .sorted { $0.location < $1.location }
            .reduce(into: [Gradient.Stop]()) { acc, stop in
                if let last = acc.last, abs(last.location - stop.location) < 0.0001 {
                    // Same location, replace color (later wins)
                    acc[acc.count - 1] = stop
                } else {
                    acc.append(stop)
                }
            }

        return LinearGradient(
            gradient: Gradient(stops: stops),
            startPoint: .bottom,
            endPoint: .top
        )
    }
}
