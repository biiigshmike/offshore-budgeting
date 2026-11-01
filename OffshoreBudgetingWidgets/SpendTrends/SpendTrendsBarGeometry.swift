import Foundation

/// Computes the positive-bar gradient without changing the source amounts or their order.
nonisolated enum SpendTrendsBarGeometry {
    nonisolated struct Stop: Equatable {
        let segmentIndex: Int
        let location: Double
    }

    static func stops(amounts: [Double], width: CGFloat, height: CGFloat) -> [Stop] {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return [] }
        let segments = amounts.enumerated().filter { $0.element.isFinite && $0.element > 0 }
        guard let largest = segments.map(\.element).max(),
              let first = segments.first, let last = segments.last else { return [] }

        // Scaling before summation keeps large finite currency values from overflowing.
        let weights = segments.map { $0.element / largest }
        let sum = weights.reduce(0, +)
        let fractions = weights.map { $0 / sum }
        let targetHalfWidth = Double(min(4, max(2, width * 0.14)))
        let barHeight = Double(height)

        var result = [Stop(segmentIndex: first.offset, location: 0)]
        var boundary = 0.0
        for index in 0..<(segments.count - 1) {
            boundary += fractions[index]
            let halfWidth = min(targetHalfWidth / barHeight,
                                fractions[index] * 0.25, fractions[index + 1] * 0.25)
            result.append(Stop(segmentIndex: segments[index].offset,
                               location: min(1, max(0, boundary - halfWidth))))
            result.append(Stop(segmentIndex: segments[index + 1].offset,
                               location: min(1, max(0, boundary + halfWidth))))
        }
        result.append(Stop(segmentIndex: last.offset, location: 1))
        return result
    }
}
