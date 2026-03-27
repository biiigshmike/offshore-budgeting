//  OffshoreBudgetingApp.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/20/26.
//

import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

struct AppWindowContext: Codable, Hashable {
    let sectionRawValue: String
    let nonce: UUID

    init(sectionRawValue: String, nonce: UUID = UUID()) {
        self.sectionRawValue = sectionRawValue
        self.nonce = nonce
    }
}

@main
struct OffshoreBudgetingApp: App {

    init() {
        configureLegacyTabBarAppearanceIfNeeded()
    }

    // MARK: - Notifications Delegate

    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(NotificationsAppDelegate.self)
    private var notificationsAppDelegate
    #endif

    // MARK: - iCloud Opt-In State

    @AppStorage("app_rootResetToken") private var rootResetToken: String = UUID().uuidString
    @State private var postBoardingTipsStore = PostBoardingTipsStore()

    // MARK: - ModelContainer

    @State private var modelContainer: ModelContainer = {
        #if DEBUG
        UITestSupport.applyResetIfNeeded()
        #endif

        let desiredUseICloud = UserDefaults.standard.bool(forKey: "icloud_useCloud")
        UserDefaults.standard.set(desiredUseICloud, forKey: "icloud_activeUseCloud")

        if desiredUseICloud {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "icloud_bootstrapStartedAt")
        } else {
            UserDefaults.standard.set(0.0, forKey: "icloud_bootstrapStartedAt")
        }

        #if DEBUG
        // If screenshot mode is enabled, ALWAYS use a local-only container
        // never touch Cloud data while staging screenshots.
        if Self.isScreenshotModeEnabled {
            UserDefaults.standard.set(false, forKey: "icloud_activeUseCloud")
            UserDefaults.standard.set(0.0, forKey: "icloud_bootstrapStartedAt")
            return Self.makeModelContainer(useICloud: false, debugStoreOverride: "Personal")
        }
        #endif

        return Self.makeModelContainer(useICloud: desiredUseICloud)
    }()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup(for: AppWindowContext.self) { windowContext in
            WindowSceneRootView(
                modelContainer: $modelContainer,
                postBoardingTipsStore: postBoardingTipsStore,
                initialSectionOverride: initialSection(from: windowContext.wrappedValue)
            )
                .id(rootResetToken)
                .onAppear {
                    consumePendingWidgetActionIfNeeded()
                    refreshShoppingModeForForeground(reason: "sceneOnAppear")
                }
                .task {
                    #if DEBUG
                    if Self.isScreenshotModeEnabled {
                        DebugSeeder.runIfNeeded(
                            container: modelContainer,
                            forceReset: Self.isSeedResetRequested
                        )
                    }
                    #endif
                }
                .onChange(of: scenePhase) { _, newValue in
                    guard newValue == .active else { return }
                    consumePendingWidgetActionIfNeeded()
                    refreshShoppingModeForForeground(reason: "sceneBecameActive")
                }
                .onOpenURL { url in
                    _ = OffshoreDeepLinkHandler.handle(url)
                }
        }
        .modelContainer(modelContainer)
        .commands {
            if shouldInstallMenuCommands {
                OffshoreAppCommands()
            }
        }
    }

    private func initialSection(from context: AppWindowContext?) -> AppSection? {
        guard let context else { return nil }
        return AppSection.fromStorageRaw(context.sectionRawValue)
    }

    private var shouldInstallMenuCommands: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #elseif canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }

    // MARK: - Legacy UI Configuration

    private func configureLegacyTabBarAppearanceIfNeeded() {
        #if canImport(UIKit)
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        if #available(iOS 26.0, *) { return }

        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.shadowColor = .clear

        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        #endif
    }

    @MainActor
    private func consumePendingWidgetActionIfNeeded() {
        guard let pendingURL = WidgetActionRequestStore.consumePendingURL() else { return }
        _ = OffshoreDeepLinkHandler.handle(pendingURL)
    }

    @MainActor
    private func refreshShoppingModeForForeground(reason: String) {
        let start = DispatchTime.now().uptimeNanoseconds
        traceShoppingModeForeground("starting reason=\(reason)")
        TabFlickerDiagnostics.markEvent(
            "shoppingModeForegroundStart",
            metadata: ["reason": reason]
        )

        ShoppingModeManager.shared.refreshIfExpired()
        let isActive = ShoppingModeManager.shared.status.isActive
        traceShoppingModeForeground("refreshed reason=\(reason) isActive=\(isActive)")
        TabFlickerDiagnostics.markEvent(
            "shoppingModeForegroundRefreshed",
            metadata: [
                "reason": reason,
                "isActive": isActive ? "true" : "false"
            ]
        )

        if isActive {
            ShoppingModeLocationService.shared.startMonitoringIfPossible()
            traceShoppingModeForeground("monitoring restarted reason=\(reason)")
            TabFlickerDiagnostics.markEvent(
                "shoppingModeMonitoringRestarted",
                metadata: ["reason": reason]
            )
        }

        let elapsedMillis = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        traceShoppingModeForeground(
            "completed reason=\(reason) elapsedMs=\(String(format: "%.1f", elapsedMillis))"
        )
        TabFlickerDiagnostics.markEvent(
            "shoppingModeForegroundCompleted",
            metadata: [
                "reason": reason,
                "elapsedMs": String(format: "%.1f", elapsedMillis)
            ]
        )
    }

    private func traceShoppingModeForeground(_ message: String) {
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: "debug_shoppingModeForegroundTraceEnabled") else { return }
        print("[ShoppingModeForeground] \(message)")
        #endif
    }

    // MARK: - Container Factory

    private static let cloudKitContainerIdentifier: String = "iCloud.com.mb.offshore-budgeting"

    static func makeModelContainer(useICloud: Bool, debugStoreOverride: String? = nil) -> ModelContainer {
        do {
            let schema = Schema([
                Workspace.self,
                Budget.self,
                BudgetCategoryLimit.self,
                Card.self,
                BudgetCardLink.self,
                BudgetPresetLink.self,
                Category.self,
                Preset.self,
                PlannedExpense.self,
                VariableExpense.self,
                AllocationAccount.self,
                ExpenseAllocation.self,
                AllocationSettlement.self,
                SavingsAccount.self,
                SavingsLedgerEntry.self,
                ImportMerchantRule.self,
                AssistantAliasRule.self,
                IncomeSeries.self,
                Income.self
            ])

            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

            let localStoreURL = appSupport.appendingPathComponent("Local.store")
            let cloudStoreURL = appSupport.appendingPathComponent("Cloud.store")

            #if DEBUG
            if let debugStoreOverride {
                let debugURL = appSupport.appendingPathComponent("\(debugStoreOverride).store")
                let configuration = ModelConfiguration(
                    debugStoreOverride,
                    schema: schema,
                    url: debugURL,
                    allowsSave: true,
                    cloudKitDatabase: .none
                )
                return try ModelContainer(for: schema, configurations: [configuration])
            }
            #endif

            let configuration: ModelConfiguration

            if useICloud {
                #if DEBUG
                if UITestSupport.shouldUseLocalCloudStore {
                    let uiTestCloudStoreURL = appSupport.appendingPathComponent("UITestCloud.store")
                    configuration = ModelConfiguration(
                        "Cloud-UITests",
                        schema: schema,
                        url: uiTestCloudStoreURL,
                        allowsSave: true,
                        cloudKitDatabase: .none
                    )
                } else {
                    configuration = ModelConfiguration(
                        "Cloud",
                        schema: schema,
                        url: cloudStoreURL,
                        allowsSave: true,
                        cloudKitDatabase: .private(cloudKitContainerIdentifier)
                    )
                }
                #else
                configuration = ModelConfiguration(
                    "Cloud",
                    schema: schema,
                    url: cloudStoreURL,
                    allowsSave: true,
                    cloudKitDatabase: .private(cloudKitContainerIdentifier)
                )
                #endif
            } else {
                configuration = ModelConfiguration(
                    "Local",
                    schema: schema,
                    url: localStoreURL,
                    allowsSave: true,
                    cloudKitDatabase: .none
                )
            }

            return try ModelContainer(for: schema, configurations: [configuration])

        } catch {
            // Fallback local store (still needs a non-optional URL and CloudKitDatabase)
            let fallbackSchema = Schema([
                Workspace.self,
                Budget.self,
                BudgetCategoryLimit.self,
                Card.self,
                BudgetCardLink.self,
                BudgetPresetLink.self,
                Category.self,
                Preset.self,
                PlannedExpense.self,
                VariableExpense.self,
                AllocationAccount.self,
                ExpenseAllocation.self,
                AllocationSettlement.self,
                SavingsAccount.self,
                SavingsLedgerEntry.self,
                ImportMerchantRule.self,
                AssistantAliasRule.self,
                IncomeSeries.self,
                Income.self
            ])

            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

            let fallbackStoreURL = appSupport.appendingPathComponent("FallbackLocal.store")

            let fallbackConfiguration = ModelConfiguration(
                "FallbackLocal",
                schema: fallbackSchema,
                url: fallbackStoreURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )

            return (try? ModelContainer(for: fallbackSchema, configurations: [fallbackConfiguration])) ?? {
                fatalError("Failed to create SwiftData ModelContainer: \(error)")
            }()
        }
    }

    // MARK: - DEBUG Screenshot Mode

    #if DEBUG
    private static var isScreenshotModeEnabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-screenshotMode") { return true }
        return UserDefaults.standard.bool(forKey: "debug_screenshotMode")
    }

    private static var isSeedResetRequested: Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-resetSeed") { return true }
        return false
    }
    #endif
}

private struct WindowSceneRootView: View {
    @Binding var modelContainer: ModelContainer
    let postBoardingTipsStore: PostBoardingTipsStore
    let initialSectionOverride: AppSection?

    @StateObject private var commandHub: AppCommandHub = Self.makeCommandHub()
    @StateObject private var resumeState = ContentViewResumeState()

    private static func makeCommandHub() -> AppCommandHub {
        #if targetEnvironment(macCatalyst)
        return AppCommandHub(policy: .enabled)
        #elseif canImport(UIKit)
        let policy: AppCommandHubPolicy = UIDevice.current.userInterfaceIdiom == .phone ? .disabled : .enabled
        return AppCommandHub(policy: policy)
        #else
        return AppCommandHub(policy: .enabled)
        #endif
    }

    private var shouldUseFocusedSceneObject: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #elseif canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom != .phone
        #else
        return true
        #endif
    }

    var body: some View {
        let root = AppBootstrapRootView(
            modelContainer: $modelContainer,
            initialSectionOverride: initialSectionOverride,
            resumeState: resumeState
        )
        .environment(\.appCommandHub, commandHub)
        .environment(postBoardingTipsStore)

        if shouldUseFocusedSceneObject {
            root.focusedSceneObject(commandHub)
        } else {
            root
        }
    }
}

enum TabFlickerDiagnostics {
    @MainActor
    static func beginWatch(
        reason: String,
        metadata: [String: String] = [:],
        duration: TimeInterval = 1.0
    ) {
        #if DEBUG && canImport(UIKit)
        MainThreadHitchMonitor.shared.beginWatch(reason: reason, metadata: metadata, duration: duration)
        #endif
    }

    @MainActor
    static func endWatch(reason: String) {
        #if DEBUG && canImport(UIKit)
        MainThreadHitchMonitor.shared.endWatch(reason: reason)
        #endif
    }

    @MainActor
    static func markEvent(_ message: String, metadata: [String: String] = [:]) {
        #if DEBUG && canImport(UIKit)
        MainThreadHitchMonitor.shared.markEvent(message, metadata: metadata)
        #endif
    }
}

#if DEBUG && canImport(UIKit)
@MainActor
private final class MainThreadHitchMonitor: NSObject {
    static let shared = MainThreadHitchMonitor()

    private struct Watch: Identifiable {
        let id = UUID()
        let reason: String
        let metadata: [String: String]
        let startedAtUptimeNs: UInt64
        let expiresAtUptimeNs: UInt64
    }

    private struct Event {
        let uptimeNs: UInt64
        let message: String
        let metadata: [String: String]
    }

    private enum Constants {
        static let enabledKey = "debug_tabFlickerDiagnosticsEnabled"
        static let verboseKey = "debug_tabFlickerVerboseEventsEnabled"
        static let warningThresholdMs = 50.0
        static let severeThresholdMs = 100.0
        static let duplicateHitchWindowNs: UInt64 = 400_000_000
        static let recentEventWindowNs: UInt64 = 2_000_000_000
        static let maxBufferedEvents = 30
    }

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var watches: [Watch] = []
    private var recentEvents: [Event] = []
    private var lastHitchPrintedAtUptimeNs: UInt64 = 0

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Constants.enabledKey)
    }

    private var isVerboseEnabled: Bool {
        UserDefaults.standard.bool(forKey: Constants.verboseKey)
    }

    func beginWatch(reason: String, metadata: [String: String], duration: TimeInterval) {
        guard isEnabled else { return }
        ensureDisplayLink()

        let now = DispatchTime.now().uptimeNanoseconds
        let expiresAt = now + UInt64(max(duration, 0) * 1_000_000_000)
        watches.removeAll { $0.reason == reason }
        watches.append(
            Watch(
                reason: reason,
                metadata: metadata,
                startedAtUptimeNs: now,
                expiresAtUptimeNs: expiresAt
            )
        )

        logEvent("watchBegin:\(reason)", metadata: metadata, now: now)
    }

    func endWatch(reason: String) {
        guard isEnabled else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        watches.removeAll { $0.reason == reason }
        logEvent("watchEnd:\(reason)", metadata: [:], now: now)
    }

    func markEvent(_ message: String, metadata: [String: String]) {
        guard isEnabled else { return }
        ensureDisplayLink()
        logEvent(message, metadata: metadata, now: DispatchTime.now().uptimeNanoseconds)
    }

    private func ensureDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(handleDisplayLinkTick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func logEvent(_ message: String, metadata: [String: String], now: UInt64) {
        recentEvents.append(Event(uptimeNs: now, message: message, metadata: metadata))
        if recentEvents.count > Constants.maxBufferedEvents {
            recentEvents.removeFirst(recentEvents.count - Constants.maxBufferedEvents)
        }

        if isVerboseEnabled {
            print("[TabFlickerTrace] event=\(message)\(formattedMetadata(metadata))")
        }
    }

    @objc
    private func handleDisplayLinkTick(_ link: CADisplayLink) {
        let now = DispatchTime.now().uptimeNanoseconds
        watches.removeAll { $0.expiresAtUptimeNs <= now }

        guard isEnabled else {
            displayLink?.invalidate()
            displayLink = nil
            lastTimestamp = nil
            return
        }

        guard let previousTimestamp = lastTimestamp else {
            lastTimestamp = link.timestamp
            return
        }

        lastTimestamp = link.timestamp
        guard watches.isEmpty == false else { return }

        let deltaSeconds = link.timestamp - previousTimestamp
        let deltaMs = deltaSeconds * 1_000
        guard deltaMs >= Constants.warningThresholdMs else { return }
        guard now - lastHitchPrintedAtUptimeNs >= Constants.duplicateHitchWindowNs else { return }
        lastHitchPrintedAtUptimeNs = now

        let expectedFrameSeconds = expectedFrameDuration(for: link)
        let droppedFrames = max(Int((deltaSeconds / expectedFrameSeconds).rounded()) - 1, 1)
        let severity = deltaMs >= Constants.severeThresholdMs ? "severe" : "warning"
        let activeReasons = watches.map(\.reason).sorted().joined(separator: ",")
        let mergedMetadata = mergedWatchMetadata()
        let hitchKind =
            activeReasons.contains("tabSelection") ||
            activeReasons.contains("sceneResume") ||
            activeReasons.contains("coldLaunch")
            ? "probableTabBarFlicker"
            : "mainThreadHitch"

        print(
            "[TabFlickerTrace] \(hitchKind) severity=\(severity) " +
            "deltaMs=\(String(format: "%.1f", deltaMs)) " +
            "droppedFrames=\(droppedFrames) watches=\(activeReasons)\(formattedMetadata(mergedMetadata))"
        )

        let recent = recentEvents.filter { now - $0.uptimeNs <= Constants.recentEventWindowNs }
        for event in recent {
            let ageMs = Double(now - event.uptimeNs) / 1_000_000
            print(
                "[TabFlickerTrace] recent ageMs=\(String(format: "%.1f", ageMs)) " +
                "event=\(event.message)\(formattedMetadata(event.metadata))"
            )
        }
    }

    private func expectedFrameDuration(for link: CADisplayLink) -> CFTimeInterval {
        let preferredDuration = link.targetTimestamp - link.timestamp
        if preferredDuration > 0 {
            return preferredDuration
        }

        let preferredFramesPerSecond = link.preferredFramesPerSecond > 0 ? link.preferredFramesPerSecond : 60
        return 1.0 / Double(preferredFramesPerSecond)
    }

    private func mergedWatchMetadata() -> [String: String] {
        var merged: [String: String] = [:]
        for watch in watches {
            for (key, value) in watch.metadata {
                merged[key] = value
            }
        }
        return merged
    }

    private func formattedMetadata(_ metadata: [String: String]) -> String {
        guard metadata.isEmpty == false else { return "" }
        let text = metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        return " " + text
    }
}
#endif
