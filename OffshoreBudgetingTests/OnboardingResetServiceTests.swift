import XCTest
@testable import Offshore

final class OnboardingResetServiceTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "OnboardingResetServiceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testRepeatOnboardingResetsProgressButPreservesChosenDataSource() {
        defaults.set(7, forKey: OnboardingResetService.onboardingStepKey)
        defaults.set(true, forKey: OnboardingResetService.didPressGetStartedKey)
        defaults.set(true, forKey: OnboardingResetService.didChooseDataSourceKey)
        defaults.set(true, forKey: OnboardingResetService.didCompleteOnboardingKey)

        OnboardingResetService.repeatOnboarding(defaults: defaults)

        XCTAssertEqual(defaults.integer(forKey: OnboardingResetService.onboardingStepKey), 0)
        XCTAssertFalse(defaults.bool(forKey: OnboardingResetService.didPressGetStartedKey))
        XCTAssertFalse(defaults.bool(forKey: OnboardingResetService.didCompleteOnboardingKey))
        XCTAssertTrue(defaults.bool(forKey: OnboardingResetService.didChooseDataSourceKey))
    }
}
