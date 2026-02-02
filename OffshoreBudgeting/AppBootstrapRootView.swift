import SwiftUI
import SwiftData

/// Root gate that prevents SwiftData views from being created until the user
/// has selected a data source on first run.
struct AppBootstrapRootView: View {
    
    @EnvironmentObject private var dataSourceSwitchCoordinator: AppDataSourceSwitchCoordinator

    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding: Bool = false
    @AppStorage("onboarding_didChooseDataSource") private var didChooseDataSource: Bool = false

    @AppStorage("onboarding_step") private var onboardingStep: Int = 0

    @AppStorage("icloud_useCloud") private var desiredUseICloud: Bool = false
    @AppStorage("icloud_activeUseCloud") private var activeUseICloud: Bool = false
    @AppStorage("icloud_bootstrapStartedAt") private var iCloudBootstrapStartedAt: Double = 0

    var body: some View {
        if didCompleteOnboarding == false, didChooseDataSource == false {
            OnboardingStartGateView { useICloud in
                dataSourceSwitchCoordinator.activateDataSource(useICloud: useICloud)

                #if DEBUG
                UITestSupport.applyScenarioDataIfNeeded(container: dataSourceSwitchCoordinator.modelContainer)
                #endif

                onboardingStep = max(1, onboardingStep)
                didChooseDataSource = true
            }
        } else {
            ContentView()
        }
    }
}
