import CoreGraphics
import Testing
@testable import Offshore

struct CardDetailLayoutTests {
    @Test func compactSummaryOverflowFallsBackWithinTheLargerSafeRegion() {
        let layout = CardDetailLayout(
            size: CGSize(width: 620, height: 400),
            division: CGRect(x: 280, y: 0, width: 12, height: 400)
        )
        #expect(layout.isFold)
        #expect(layout.fitting(compactSummaryHeight: 400) == layout.placement)
        #expect(layout.fitting(compactSummaryHeight: 401) == .stacked(
            CGRect(x: 300, y: 0, width: 320, height: 400)
        ))
    }

    @Test func desktopThresholdsUseTheDetailViewport() {
        for size in [CGSize(width: 759, height: 360), CGSize(width: 760, height: 359)] {
            #expect(CardDetailLayout(size: size).placement == .stacked(CGRect(origin: .zero, size: size)))
        }

        let layout = CardDetailLayout(size: CGSize(width: 760, height: 360))
        #expect(layout.placement == .sideBySide(
            summary: CGRect(x: 0, y: 0, width: 300, height: 360),
            expenses: CGRect(x: 316, y: 0, width: 444, height: 360)
        ))
    }

    @Test func foldPlacesBothPanesOutsideTheActualDivision() {
        let layout = CardDetailLayout(
            size: CGSize(width: 620, height: 400),
            division: CGRect(x: 280, y: 0, width: 12, height: 400)
        )
        #expect(layout.placement == .sideBySide(
            summary: CGRect(x: 0, y: 0, width: 272, height: 400),
            expenses: CGRect(x: 300, y: 0, width: 320, height: 400)
        ))
    }

    @Test func tabletopUsesUpperAndLowerRegionsEvenInAWideViewport() {
        let layout = CardDetailLayout(
            size: CGSize(width: 800, height: 420),
            division: CGRect(x: 0, y: 190, width: 800, height: 10)
        )
        #expect(layout.placement == .tabletop(
            summary: CGRect(x: 0, y: 0, width: 800, height: 182),
            expenses: CGRect(x: 0, y: 208, width: 800, height: 212)
        ))
    }

    @Test func divisionFallbackStaysInTheLargerRegion() {
        let narrowFold = CardDetailLayout(
            size: CGSize(width: 560, height: 400),
            division: CGRect(x: 190, y: 0, width: 4, height: 400)
        )
        #expect(narrowFold.placement == .stacked(CGRect(x: 202, y: 0, width: 358, height: 400)))

        let shortTabletop = CardDetailLayout(
            size: CGSize(width: 800, height: 390),
            division: CGRect(x: 0, y: 263, width: 800, height: 8)
        )
        #expect(shortTabletop.placement == .stacked(CGRect(x: 0, y: 0, width: 800, height: 255)))
    }
}
