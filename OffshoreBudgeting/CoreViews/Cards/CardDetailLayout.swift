import SwiftUI

nonisolated struct CardDetailLayout: Equatable, Sendable {
    enum Placement: Equatable, Sendable {
        case stacked(CGRect)
        case sideBySide(summary: CGRect, expenses: CGRect)
        case tabletop(summary: CGRect, expenses: CGRect)
    }

    let placement: Placement
    let stackedFallback: CGRect
    let isFold: Bool

    private static let gutter: CGFloat = 16

    func fitting(compactSummaryHeight: CGFloat) -> Placement {
        switch placement {
        case .sideBySide(let summary, _), .tabletop(let summary, _):
            return compactSummaryHeight <= summary.height ? placement : .stacked(stackedFallback)
        case .stacked:
            return placement
        }
    }

    init(size: CGSize, division: CGRect? = nil) {
        let bounds = CGRect(origin: .zero, size: size)

        if let division, let split = Self.split(at: division, in: bounds) {
            placement = split.placement
            stackedFallback = split.fallback
            isFold = division.height > division.width
            return
        }

        stackedFallback = bounds
        isFold = false
        if size.width >= 760 && size.height >= 360 {
            let summary = CGRect(x: 0, y: 0, width: 300, height: size.height)
            let expenses = CGRect(x: summary.maxX + Self.gutter, y: 0,
                                  width: size.width - summary.width - Self.gutter, height: size.height)
            placement = .sideBySide(summary: summary, expenses: expenses)
        } else {
            placement = .stacked(bounds)
        }
    }

    private static func split(at division: CGRect, in bounds: CGRect) -> (placement: Placement, fallback: CGRect)? {
        // The region's long axis runs along the crease. Leave a gutter even for a zero-width crease.
        let sideBySide = division.height > division.width
        let padding = gutter / 2
        let first: CGRect
        let second: CGRect
        let splitPlacement: Placement?
        if sideBySide {
            guard division.maxX > bounds.minX, division.minX < bounds.maxX else { return nil }
            let firstEnd = max(0, division.minX - padding)
            let secondStart = min(bounds.width, division.maxX + padding)
            first = CGRect(x: 0, y: 0, width: firstEnd, height: bounds.height)
            second = CGRect(x: secondStart, y: 0, width: bounds.width - secondStart, height: bounds.height)
            if first.width >= 230 && second.width >= 260 && bounds.height >= 220 {
                splitPlacement = .sideBySide(summary: first, expenses: second)
            } else {
                splitPlacement = nil
            }
        } else {
            guard division.maxY > bounds.minY, division.minY < bounds.maxY else { return nil }
            let firstEnd = max(0, division.minY - padding)
            let secondStart = min(bounds.height, division.maxY + padding)
            first = CGRect(x: 0, y: 0, width: bounds.width, height: firstEnd)
            second = CGRect(x: 0, y: secondStart, width: bounds.width, height: bounds.height - secondStart)
            if first.height >= 130 && second.height >= 144 && bounds.width >= 300 {
                splitPlacement = .tabletop(summary: first, expenses: second)
            } else {
                splitPlacement = nil
            }
        }

        let fallback = first.width * first.height >= second.width * second.height ? first : second
        return (splitPlacement ?? .stacked(fallback), fallback)
    }

    static func measure(_ proxy: GeometryProxy) -> Self {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        if #available(iOS 27.1, *) {
            let division = proxy.reservedRegions(kind: .division).first(where: \.isActive)
            return Self(size: proxy.size, division: division?.frame)
        }
        #endif
        return Self(size: proxy.size)
    }
}
