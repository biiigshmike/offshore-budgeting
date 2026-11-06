import SwiftUI
import SwiftData

/// Root gate that prevents SwiftData views from being created until the user
/// has selected a data source on first run.
struct AppBootstrapRootView: View {

    @Binding var modelContainer: ModelContainer
    let initialSectionOverride: AppSection?

    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding: Bool = false
    @AppStorage("onboarding_didChooseDataSource") private var didChooseDataSource: Bool = false

    @AppStorage("onboarding_step") private var onboardingStep: Int = 0
    @AppStorage("selectedWorkspaceID") private var selectedWorkspaceID: String = ""

    @AppStorage("icloud_useCloud") private var desiredUseICloud: Bool = false
    @AppStorage("icloud_activeUseCloud") private var activeUseICloud: Bool = false
    @AppStorage("icloud_bootstrapStartedAt") private var iCloudBootstrapStartedAt: Double = 0
    @State private var showingStorageSwitchSaveError = false

    var body: some View {
        if didCompleteOnboarding == false, didChooseDataSource == false {
            OnboardingStartGateView(onChooseDataSource: chooseDataSource)
                .alert("Couldn’t Switch Storage", isPresented: $showingStorageSwitchSaveError) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text("Offshore couldn’t save your changes. Try switching storage again.")
                }
        } else {
            ContentView(
                initialSectionOverride: initialSectionOverride,
                modelContainer: modelContainer
            )
            .modelContainer(modelContainer)
            .id(ObjectIdentifier(modelContainer))
        }
    }

    private func chooseDataSource(_ useICloud: Bool) {
        if useICloud != activeUseICloud {
            // Onboarding edits can still be waiting for SwiftData autosave.
            let context = modelContainer.mainContext
            do {
                if context.hasChanges {
                    try context.save()
                }
            } catch {
                showingStorageSwitchSaveError = true
                return
            }
            switchDataSource(useICloud: useICloud)
        }
        desiredUseICloud = useICloud
        onboardingStep = max(1, onboardingStep)
        didChooseDataSource = true
    }

    private func switchDataSource(useICloud: Bool) {
        let startedAt = useICloud ? Date().timeIntervalSince1970 : 0
        if useICloud {
            ICloudBootstrap.logICloudSelection(startedAt: startedAt)
            #if DEBUG
            ICloudBootstrap.observeCloudKitEvents(startedAt: startedAt)
            ICloudBootstrap.logMilestone("Creating iCloud model container", startedAt: startedAt)
            #endif
        }

        let container = OffshoreBudgetingApp.makeModelContainer(useICloud: useICloud)
        #if DEBUG
        if useICloud {
            ICloudBootstrap.logMilestone("Model container returned", startedAt: startedAt)
        }
        UITestSupport.applyScenarioDataIfNeeded(container: container)
        #endif

        modelContainer = container
        selectedWorkspaceID = ""
        activeUseICloud = useICloud
        iCloudBootstrapStartedAt = startedAt
    }
}
