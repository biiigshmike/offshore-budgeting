import Foundation

nonisolated enum SpendTrendsBarStyle {
    static func compactWidth(slotWidth: CGFloat) -> CGFloat {
        min(24, max(0, slotWidth) * 0.58)
    }

    static func detailWidth(slotWidth: CGFloat) -> CGFloat {
        min(36, max(0, slotWidth) * 0.60)
    }

    static func cornerRadius(width: CGFloat, height: CGFloat) -> CGFloat {
        guard width.isFinite, height.isFinite else { return 0 }
        return max(0, min(8, width * 0.28, height / 2))
    }

    static func barHeight(total: Double, maximum: Double, availableHeight: CGFloat) -> CGFloat {
        guard total.isFinite, maximum.isFinite, availableHeight.isFinite,
              total > 0, availableHeight > 0 else { return 0 }
        let fraction = min(1, max(0, total / max(0.000_1, maximum)))
        return max(2, availableHeight * CGFloat(fraction))
    }
}
