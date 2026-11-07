import CoreLocation
import SwiftUI
import UIKit

#if !targetEnvironment(macCatalyst)
struct SettingsExcursionModeView: View {
    @ObservedObject private var shoppingModeManager = ShoppingModeManager.shared
    @ObservedObject private var excursionLocation = ShoppingModeLocationService.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    @State private var showingExcursionSetup = false
    @State private var showingExcursionStartAlert = false
    @State private var showingExcursionLocationUnavailable = false
    @State private var selectedExcursionMinutes = 60
    @State private var pendingExcursionMinutes: Int?
    @State private var isStarting = false
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""

    private var isStartPending: Bool {
        pendingExcursionMinutes != nil || isStarting
    }

    var body: some View {
        List {
            Section {
                ExcursionStatusHero(
                    status: shoppingModeManager.status,
                    locationCapability: shoppingModeManager.locationCapability
                )
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                if shoppingModeManager.status.isActive {
                    Button("Stop Excursion Mode", role: .destructive) {
                        shoppingModeManager.end()
                    }
                    locationSetupAction
                } else {
                    if dynamicTypeSize.isAccessibilitySize {
                        durationPicker.pickerStyle(.inline)
                    } else {
                        durationPicker.pickerStyle(.segmented)
                    }

                    Button {
                        let minutes = selectedExcursionMinutes
                        Task { await prepareExcursion(minutes: minutes) }
                    } label: {
                        Text("Start Excursion Mode")
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .glassProminentButtonStyleCompat()
                    .disabled(isStartPending)
                }
            } footer: {
                Text(shoppingModeManager.locationCapability.statusText)
                    .accessibilityIdentifier("excursionLocationStatus")
            }

            Section {
                NavigationLink {
                    ExcursionPreferencesView()
                } label: {
                    Label("Preferences", systemImage: "slider.horizontal.3")
                }
                .accessibilityIdentifier("excursionPreferences")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Excursion Mode")
        .task { shoppingModeManager.refreshIfExpired() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { advanceExcursionStart() }
        }
        .appSheet(isPresented: $showingExcursionSetup) {
            ExcursionLocationSetupView()
                .presentationDetents([.large])
        }
        .onChange(of: excursionLocation.authorizationStatus) { _, _ in
            advanceExcursionStart()
        }
        .alert("Get nearby reminders while you’re out", isPresented: $showingExcursionStartAlert) {
            Button("Continue") { beginExcursionLocationRequest() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("For reminders when Offshore is closed, choose Allow While Using App first, then Change to Always Allow. If you choose Allow Once, reminders work only while Offshore is open.")
        }
        .alert("Location access is off", isPresented: $showingExcursionLocationUnavailable) {
            if excursionLocation.authorizationStatus == .denied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
            Button("Dismiss", role: .cancel) { }
        } message: {
            Text(excursionLocation.capability.statusText)
        }
        .alert("Couldn’t Start Excursion Mode", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .blocksAutomaticExpenseReview(
            while: showingErrorAlert || showingExcursionStartAlert || showingExcursionLocationUnavailable
        )
    }

    private var durationPicker: some View {
        Picker("Duration", selection: $selectedExcursionMinutes) {
            #if DEBUG
            Text("1 minute").tag(1)
            #endif
            Text("1 hour").tag(60)
            Text("2 hours").tag(120)
            Text("4 hours").tag(240)
        }
        .disabled(isStartPending)
    }

    @ViewBuilder
    private var locationSetupAction: some View {
        switch shoppingModeManager.locationCapability {
        case .foregroundOnly, .paused:
            Button("Allow background reminders", action: showLocationSetup)
        case .needsPermission, .denied, .preciseLocationRequired:
            Button("Set Up Location", action: showLocationSetup)
        case .background, .restricted:
            EmptyView()
        }
    }

    private func showLocationSetup() {
        pendingExcursionMinutes = nil
        showingExcursionSetup = true
    }

    private func prepareExcursion(minutes: Int) async {
        guard pendingExcursionMinutes == nil, !isStarting, !shoppingModeManager.status.isActive else { return }
        switch excursionLocation.currentAuthorizationStatus() {
        case .authorizedAlways:
            await activateExcursion(minutes: minutes)
        case .notDetermined, .authorizedWhenInUse:
            showingExcursionStartAlert = true
        default:
            showingExcursionLocationUnavailable = true
        }
    }

    private func beginExcursionLocationRequest() {
        pendingExcursionMinutes = selectedExcursionMinutes
        if excursionLocation.currentAuthorizationStatus() == .notDetermined {
            excursionLocation.requestAuthorizationForExcursionMode()
        } else {
            advanceExcursionStart()
        }
    }

    private func advanceExcursionStart() {
        guard let minutes = pendingExcursionMinutes, scenePhase == .active,
              UIApplication.shared.applicationState == .active else { return }

        let status = excursionLocation.currentAuthorizationStatus()
        guard status != .notDetermined else { return }
        pendingExcursionMinutes = nil
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            if status == .authorizedWhenInUse {
                excursionLocation.requestAuthorizationForExcursionMode()
            }
            // A declined or suppressed upgrade may leave authorization unchanged.
            Task { await activateExcursion(minutes: minutes) }
        default:
            showingExcursionLocationUnavailable = true
        }
    }

    private func activateExcursion(minutes: Int) async {
        guard !isStarting, !shoppingModeManager.status.isActive else { return }
        isStarting = true
        defer { isStarting = false }

        let result: ShoppingModeStartResult
        #if DEBUG
        if minutes < 60 {
            result = await shoppingModeManager.start(minutes: minutes)
        } else {
            result = await shoppingModeManager.start(hours: minutes / 60)
        }
        #else
        result = await shoppingModeManager.start(hours: minutes / 60)
        #endif
        if case .blocked(let blockers) = result {
            errorMessage = blockers.map(\.message).joined(separator: "\n")
            showingErrorAlert = true
        }
    }
}
#endif
