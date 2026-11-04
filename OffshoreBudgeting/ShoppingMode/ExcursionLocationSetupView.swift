import SwiftUI
import CoreLocation
import UIKit

struct ExcursionLocationSetupView: View {
    @ObservedObject private var locationService = ShoppingModeLocationService.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var requestingInitialAccess = false
    @State private var upgradeRequested = false
    @State private var completed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Get nearby reminders while you’re out.")
                        .font(.headline)
                    Text("Offshore uses your location to suggest logging nearby purchases during Excursion Mode.")
                }
                Section {
                    permissionChoices
                }
            }
            .navigationTitle("Nearby Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
        .task { locationService.refreshAuthorizationState() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                requestingInitialAccess = false
                locationService.refreshAuthorizationState()
            }
        }
        .onChange(of: locationService.authorizationStatus) { _, status in
            requestingInitialAccess = false
            if status == .notDetermined { upgradeRequested = false }
            if status == .authorizedAlways && upgradeRequested { finish() }
        }
    }

    @ViewBuilder
    private var permissionChoices: some View {
        switch locationService.authorizationStatus {
        case .notDetermined:
            Text("Allow location access to get started. You can then choose whether reminders work with Offshore closed.")
            Button("Continue") {
                requestingInitialAccess = true
                locationService.requestAuthorizationForExcursionMode()
            }
            .disabled(requestingInitialAccess)
            .accessibilityIdentifier("excursionInitialLocation")
        case .authorizedWhenInUse:
            #if targetEnvironment(macCatalyst)
            Text("Location access is ready for nearby reminders.")
            Button("Continue") { finish() }
            #else
            manualUpgradeChoices
            #endif
        case .authorizedAlways:
            Text("Nearby reminders can work with Offshore closed.")
            Button("Continue") { finish() }
        case .denied:
            Text("Location access is off. You can allow it in Settings, then come back here.")
            openSettingsButton
        case .restricted:
            Text("Location access is restricted on this device.")
        @unknown default:
            Text("Location access is unavailable right now.")
        }
    }

    @ViewBuilder
    private var manualUpgradeChoices: some View {
        Text("Works while Offshore is open.")
        Text("Allow Always location access to get nearby reminders when Offshore isn’t open.")
            .foregroundStyle(.secondary)
        Button("Allow background reminders") {
            upgradeRequested = true
            locationService.requestAuthorizationForExcursionMode()
        }
        .disabled(upgradeRequested)
        .accessibilityIdentifier("excursionBackgroundLocation")
        Button("Use while Offshore is open") { finish() }
            .accessibilityIdentifier("excursionUseWhileOpen")
        if upgradeRequested {
            Text("If no prompt appears, you can change location access in Settings. You can also keep using reminders while Offshore is open.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        openSettingsButton
    }

    private var openSettingsButton: some View {
        Button("Open Settings") {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        }
    }

    private func finish() {
        guard !completed else { return }
        completed = true
        dismiss()
    }
}
