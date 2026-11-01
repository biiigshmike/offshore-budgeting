import Foundation
import Testing
@testable import Offshore

struct SpendTrendsBarGeometryTests {
    @Test func emptyOrNonpositiveSegmentsHaveNoGradient() {
        #expect(SpendTrendsBarGeometry.stops(amounts: [], width: 24, height: 120).isEmpty)
        #expect(SpendTrendsBarGeometry.stops(amounts: [0, -1], width: 24, height: 120).isEmpty)
        #expect(SpendTrendsBarGeometry.stops(amounts: [.nan, .infinity], width: 24, height: 120).isEmpty)
    }

    @Test func invalidDimensionsHaveNoGradient() {
        for size in [CGFloat.zero, -1, .nan, .infinity] {
            #expect(SpendTrendsBarGeometry.stops(amounts: [10], width: size, height: 120).isEmpty)
            #expect(SpendTrendsBarGeometry.stops(amounts: [10], width: 24, height: size).isEmpty)
        }
    }

    @Test func singleCategoryKeepsOneColorFromBottomToTop() {
        let stops = SpendTrendsBarGeometry.stops(amounts: [0, 75, 0], width: 24, height: 120)
        #expect(stops == [
            .init(segmentIndex: 1, location: 0),
            .init(segmentIndex: 1, location: 1)
        ])
    }

    @Test func boundariesFollowProportionalAmountsAndOriginalOrder() throws {
        let stops = SpendTrendsBarGeometry.stops(amounts: [60, 30, 10], width: 24, height: 200)
        #expect(stops.map(\.segmentIndex) == [0, 0, 1, 1, 2, 2])
        #expect(stops.count == 6)
        let firstStart = try #require(stops[safe: 1])
        let firstEnd = try #require(stops[safe: 2])
        let secondStart = try #require(stops[safe: 3])
        let secondEnd = try #require(stops[safe: 4])
        #expect(abs((firstStart.location + firstEnd.location) / 2 - 0.6) < 0.000_001)
        #expect(abs((secondStart.location + secondEnd.location) / 2 - 0.9) < 0.000_001)
        expectBoundedOrderedStops(stops)
    }

    @Test func skippingInvalidSegmentsPreservesOriginalColorIndices() {
        let stops = SpendTrendsBarGeometry.stops(
            amounts: [0, 10, -5, .nan, 30, .infinity], width: 24, height: 120
        )
        #expect(stops.map(\.segmentIndex) == [1, 1, 4, 4])
        expectBoundedOrderedStops(stops)
    }

    @Test func equalAmountsRetainProducerOrder() {
        let stops = SpendTrendsBarGeometry.stops(amounts: [10, 10, 10], width: 24, height: 120)
        #expect(stops.map(\.segmentIndex) == [0, 0, 1, 1, 2, 2])
    }

    @Test func blendDistanceStaysConstantInPointsAcrossBarHeights() throws {
        let short = SpendTrendsBarGeometry.stops(amounts: [50, 50], width: 24, height: 60)
        let tall = SpendTrendsBarGeometry.stops(amounts: [50, 50], width: 24, height: 240)
        let shortStart = try #require(short[safe: 1])
        let shortEnd = try #require(short[safe: 2])
        let tallStart = try #require(tall[safe: 1])
        let tallEnd = try #require(tall[safe: 2])
        let shortBlendPoints = (shortEnd.location - shortStart.location) * 60
        let tallBlendPoints = (tallEnd.location - tallStart.location) * 240
        #expect(abs(shortBlendPoints - tallBlendPoints) < 0.000_001)
        #expect(shortBlendPoints > 0)
    }

    @Test func tinyAdjacentSlicesRetainSolidColorCores() throws {
        let amounts = [1_000.0, 0.1, 0.01, 0.1]
        let stops = SpendTrendsBarGeometry.stops(amounts: amounts, width: 36, height: 2)
        expectBoundedOrderedStops(stops)
        #expect(stops.count == 8)
        for index in 1..<(amounts.count - 1) {
            let coreStart = try #require(stops[safe: index * 2])
            let coreEnd = try #require(stops[safe: index * 2 + 1])
            let proportionalHeight = amounts[index] / amounts.reduce(0, +)
            #expect(coreStart.segmentIndex == index)
            #expect(coreEnd.segmentIndex == index)
            #expect(coreEnd.location - coreStart.location >= proportionalHeight * 0.49)
        }
    }

    @Test func twelveCategoriesFitInsideBarWithoutSegmentInflation() throws {
        let amounts = Array(repeating: 1.0, count: 12)
        let stops = SpendTrendsBarGeometry.stops(amounts: amounts, width: 24, height: 2)
        expectBoundedOrderedStops(stops)
        #expect(stops.count == 24)
        #expect(Set(stops.map(\.segmentIndex)) == Set(0..<12))
        for index in 1..<11 {
            let start = try #require(stops[safe: index * 2])
            let end = try #require(stops[safe: index * 2 + 1])
            #expect(end.location - start.location >= (1.0 / 12) * 0.49)
        }
    }

    @Test func veryLargeAmountsNormalizeWithoutOverflow() throws {
        let stops = SpendTrendsBarGeometry.stops(
            amounts: [.greatestFiniteMagnitude, .greatestFiniteMagnitude], width: 24, height: 120
        )
        expectBoundedOrderedStops(stops)
        #expect(stops.count == 4)
        let left = try #require(stops[safe: 1])
        let right = try #require(stops[safe: 2])
        #expect(abs((left.location + right.location) / 2 - 0.5) < 0.000_001)
    }

    @Test func commonScalingOfAmountsDoesNotChangeGradientGeometry() {
        let original = SpendTrendsBarGeometry.stops(amounts: [60, 30, 10], width: 24, height: 120)
        let scaled = SpendTrendsBarGeometry.stops(amounts: [600, 300, 100], width: 24, height: 120)
        #expect(original == scaled)
    }

    @Test func slenderWidthsAdaptToDenseAndSparsePeriods() {
        #expect(SpendTrendsBarStyle.compactWidth(slotWidth: 100) == 24)
        #expect(SpendTrendsBarStyle.detailWidth(slotWidth: 100) == 36)
        #expect(abs(SpendTrendsBarStyle.compactWidth(slotWidth: 10) - 5.8) < 0.000_001)
        #expect(abs(SpendTrendsBarStyle.detailWidth(slotWidth: 10) - 6) < 0.000_001)
        #expect(SpendTrendsBarStyle.compactWidth(slotWidth: 0) == 0)
        #expect(SpendTrendsBarStyle.detailWidth(slotWidth: -1) == 0)
    }

    @Test func cornerRadiusFitsShortBarsAndCapsTallBars() {
        #expect(SpendTrendsBarStyle.cornerRadius(width: 36, height: 120) == 8)
        #expect(abs(SpendTrendsBarStyle.cornerRadius(width: 24, height: 120) - 6.72) < 0.000_001)
        #expect(SpendTrendsBarStyle.cornerRadius(width: 24, height: 2) == 1)
        #expect(SpendTrendsBarStyle.cornerRadius(width: 0, height: 120) == 0)
    }

    @Test func positiveSubDollarBarsHaveMinimumHeightAndZerosStayEmpty() {
        #expect(SpendTrendsBarStyle.barHeight(total: 50, maximum: 100, availableHeight: 120) == 60)
        #expect(SpendTrendsBarStyle.barHeight(total: 0.01, maximum: 100, availableHeight: 120) == 2)
        #expect(SpendTrendsBarStyle.barHeight(total: 150, maximum: 100, availableHeight: 120) == 120)
        #expect(SpendTrendsBarStyle.barHeight(total: 0, maximum: 100, availableHeight: 120) == 0)
        #expect(SpendTrendsBarStyle.barHeight(total: -1, maximum: 100, availableHeight: 120) == 0)
        #expect(SpendTrendsBarStyle.barHeight(total: .nan, maximum: 100, availableHeight: 120) == 0)
    }

    private func expectBoundedOrderedStops(_ stops: [SpendTrendsBarGeometry.Stop]) {
        #expect(stops.first?.location == 0)
        #expect(stops.last?.location == 1)
        #expect(stops.allSatisfy { $0.location.isFinite && (0...1).contains($0.location) })
        #expect(zip(stops, stops.dropFirst()).allSatisfy { pair in
            pair.0.location <= pair.1.location
        })
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
