import SwiftUI

/// First-run screens that run *before* any SwiftData views are created.
/// This allows choosing the data source without requiring an app restart.
struct OnboardingStartGateView: View {

    let onChooseDataSource: (Bool) -> Void

    @AppStorage("onboarding_didPressGetStarted") private var didPressGetStarted: Bool = false

    @State private var path: [Route] = []
    @State private var showingICloudUnavailable: Bool = false

    // Drives the “wake up” motion when transitioning away.
    @State private var isExitingWelcome: Bool = false

    var body: some View {
        NavigationStack(path: $path) {
            welcomeScreen
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .dataSource:
                        dataSourceScreen
                    }
                }
        }
        .onAppear {
            if didPressGetStarted, path.isEmpty {
                path = [.dataSource]
            }
        }
        .alert("iCloud Unavailable", isPresented: $showingICloudUnavailable) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("To use iCloud sync, sign in to iCloud in the Settings app, then return here and try again.")
        }
    }

    // MARK: - Screens

    private var welcomeScreen: some View {
        ZStack {
            WaveBackdrop(isExiting: isExitingWelcome)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Spacer(minLength: 8)

                Image(systemName: "sailboat.fill")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(.tint)

                Text("Welcome to Offshore Budgeting!")
                    .font(.largeTitle.weight(.bold))

                Text("Press the button below to get started setting up your budgeting workspace.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                if #available(iOS 26.0, *) {
                    Button {
                        beginWelcomeExitThenNavigate()
                    } label: {
                        Text("Get Started")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.accentColor)
                } else {
                    Button {
                        beginWelcomeExitThenNavigate()
                    } label: {
                        Text("Get Started")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .navigationBarBackButtonHidden(true)
    }

    private var dataSourceScreen: some View {
        List {
            Section {
                ContentUnavailableView(
                    "Choose Data Source",
                    systemImage: "externaldrive",
                    description: Text("Pick where your data is stored. You can switch later from Manage Workspaces.")
                )
                .listRowBackground(Color.clear)
            }

            Section("Data Source") {
                Button {
                    onChooseDataSource(false)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "iphone")
                            .foregroundStyle(.tint)
                        Text("On Device")
                        Spacer()
                    }
                }

                Button {
                    handleICloudTapped()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "icloud")
                            .foregroundStyle(.tint)
                        Text("iCloud")
                        Spacer()
                    }
                }
            }

            Section {
                Text("On Device stores data only on this device. iCloud syncs across devices signed into the same Apple ID.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Get Started")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Actions

    private var isICloudAvailable: Bool {
        #if DEBUG
        if UITestSupport.shouldForceICloudAvailable {
            return true
        }
        #endif
        return FileManager.default.ubiquityIdentityToken != nil
    }

    private func handleICloudTapped() {
        guard isICloudAvailable else {
            showingICloudUnavailable = true
            return
        }
        onChooseDataSource(true)
    }

    private func beginWelcomeExitThenNavigate() {
        didPressGetStarted = true

        withAnimation(.easeInOut(duration: 0.55)) {
            isExitingWelcome = true
        }

        // Give the background a moment to “wake up” before navigation pushes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            path = [.dataSource]
        }
    }
}

private enum Route: Hashable {
    case dataSource
}
