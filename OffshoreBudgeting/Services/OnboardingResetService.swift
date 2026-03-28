import Foundation

enum OnboardingResetService {

    static let onboardingStepKey = "onboarding_step"
    static let didPressGetStartedKey = "onboarding_didPressGetStarted"
    static let didChooseDataSourceKey = "onboarding_didChooseDataSource"
    static let didCompleteOnboardingKey = "didCompleteOnboarding"

    static func repeatOnboarding(defaults: UserDefaults = .standard) {
        defaults.set(0, forKey: onboardingStepKey)
        defaults.set(false, forKey: didPressGetStartedKey)
        defaults.set(false, forKey: didCompleteOnboardingKey)
    }
}
