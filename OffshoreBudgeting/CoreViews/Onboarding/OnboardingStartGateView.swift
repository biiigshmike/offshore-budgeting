import SwiftUI

/// First-run screens that run *before* any SwiftData views are created.
/// This allows choosing the data source without requiring an app restart.
struct OnboardingStartGateView: View {

    let onChooseDataSource: (Bool) -> Void

    @AppStorage("onboarding_didPressGetStarted") private var didPressGetStarted: Bool = false

    @State private var path: [Route] = []
    @State private var showingICloudUnavailable: Bool = false

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
                    didPressGetStarted = true
                    path = [.dataSource]
                } label: {
                    Text("Get Started")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
            } else {
                Button {
                    didPressGetStarted = true
                    path = [.dataSource]
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
                            .foregroundStyle(.secondary)
                        Text("On Device")
                        Spacer()
                    }
                }

                Button {
                    handleICloudTapped()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "icloud")
                            .foregroundStyle(.blue)
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
        FileManager.default.ubiquityIdentityToken != nil
    }

    private func handleICloudTapped() {
        guard isICloudAvailable else {
            showingICloudUnavailable = true
            return
        }
        onChooseDataSource(true)
    }
}

private enum Route: Hashable {
    case dataSource
}

