import XCTest
@testable import Offshore

final class OnboardingStepTests: XCTestCase {
    func testForwardAndBackwardNavigation() {
        let steps: [OnboardingStep] = [.welcome, .workspaces, .privacy, .categories, .cards, .presets]
        XCTAssertEqual(OnboardingStep.ordered, steps)
        for pair in zip(steps, steps.dropFirst()) {
            XCTAssertEqual(pair.0.next, pair.1)
            XCTAssertEqual(pair.1.previous, pair.0)
        }
        XCTAssertEqual(OnboardingStep.welcome.previous, .welcome)
        XCTAssertEqual(OnboardingStep.presets.next, .presets)
    }

    func testSavedProgressKeepsStableIDs() {
        XCTAssertEqual(OnboardingStep.ordered.map(\.rawValue), [0, 1, 2, 4, 5, 6])
        for step in OnboardingStep.ordered {
            XCTAssertEqual(OnboardingStep.resolve(step.rawValue), step)
        }
    }

    func testRemovedAndInvalidStepsResolveSafely() {
        XCTAssertEqual(OnboardingStep.resolve(3), .categories)
        for savedValue in [7, 8, 9, 10, Int.max] {
            XCTAssertEqual(OnboardingStep.resolve(savedValue), .presets)
        }
        XCTAssertEqual(OnboardingStep.resolve(-1), .welcome)
    }
}
