import SwiftUI
import SwiftData

#if DEBUG
struct ScreenshotStartupRootView: View {
    let postBoardingTipsStore: PostBoardingTipsStore
    let initialSectionOverride: AppSection?
    @State private var coordinator: ScreenshotStartupCoordinator

    init(postBoardingTipsStore: PostBoardingTipsStore, initialSectionOverride: AppSection?) {
        self.postBoardingTipsStore = postBoardingTipsStore
        self.initialSectionOverride = initialSectionOverride
        _coordinator = State(initialValue: ScreenshotStartupCoordinator.shared)
    }

    var body: some View {
        Group {
            if let container = coordinator.container {
                WindowSceneRootView(
                    modelContainer: .constant(container),
                    postBoardingTipsStore: postBoardingTipsStore,
                    initialSectionOverride: initialSectionOverride
                )
                .id(ObjectIdentifier(container))
            } else {
                ContentUnavailableView {
                    Label("Screenshot Setup Failed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(coordinator.failureMessage ?? "Screenshot data is not ready.")
                        .accessibilityIdentifier("screenshotSetupError")
                } actions: {
                    Button("Retry") { coordinator.retry() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("screenshotSetupRetry")
                    if let logURL = StartupDiagnostics.currentLogURL {
                        ShareLink(item: logURL) {
                            Label("Share Startup Log", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .onAppear { coordinator.revalidateDisplayedSession() }
    }
}
#endif
