import Foundation
import Observation
import SwiftData

#if DEBUG
@MainActor
@Observable
final class ScreenshotStartupCoordinator {
    static let shared = ScreenshotStartupCoordinator()

    private(set) var container: ModelContainer?
    private(set) var failureMessage: String?
    private let open: @MainActor () throws -> ModelContainer
    private let prepare: @MainActor (ModelContainer) throws -> Void

    init(
        open: @escaping @MainActor () throws -> ModelContainer = {
            try ScreenshotStartupCoordinator.failIfRequested(stage: "Open")
            return try OffshoreBudgetingApp.makeScreenshotContainer()
        },
        prepare: @escaping @MainActor (ModelContainer) throws -> Void = { container in
            let workspaceID = try DebugSeeder.runIfNeeded(
                container: container,
                forceReset: ProcessInfo.processInfo.arguments.contains("-resetSeed"),
                beforeSave: { try ScreenshotStartupCoordinator.failIfRequested(stage: "Save") }
            )
            try ScreenshotStartupCoordinator.failIfRequested(stage: "Validation")
            _ = try ScreenshotStartupCoordinator.validate(container: container)
            ScreenshotStartupCoordinator.configurePreferences(
                workspaceID: workspaceID,
                defaults: .standard,
                resetOnboarding: ProcessInfo.processInfo.arguments.contains("-resetSeed")
            )
        }
    ) {
        self.open = open
        self.prepare = prepare
        retry()
    }

    func retry() {
        container = nil
        failureMessage = nil
        StartupDiagnostics.beginLaunch()
        StartupDiagnostics.log("screenshot setup starting bundle=\(Bundle.main.bundleIdentifier ?? "<unknown>") compiledMode=\(DebugScreenshotMode.isCompiledBuild)")
        do {
            let candidate = try open()
            try prepare(candidate)
            // Publish only after seeding, validation, and preferences succeed.
            container = candidate
            StartupDiagnostics.log("screenshot setup ready")
            StartupDiagnostics.logContainer(candidate)
        } catch {
            failureMessage = error.localizedDescription
            StartupDiagnostics.log("screenshot setup failed error=\(String(reflecting: error)) details=\((error as NSError).userInfo)")
        }
    }

    func revalidateDisplayedSession() {
        guard let container else { return }
        do {
            _ = try Self.validate(container: container)
        } catch {
            self.container = nil
            failureMessage = error.localizedDescription
            StartupDiagnostics.log("screenshot displayed session rejected error=\(String(reflecting: error))")
        }
    }

    func requireContainer() throws -> ModelContainer {
        guard let container else {
            throw ScreenshotStartupError.unavailable(failureMessage ?? "Screenshot setup has not completed.")
        }
        return container
    }

    static func validate(container: ModelContainer) throws -> UUID {
        guard container.configurations.count == 1,
              container.configurations.allSatisfy({ DebugScreenshotMode.owns($0) }) else {
            throw ScreenshotStartupError.invalidStore
        }
        let context = ModelContext(container)
        let workspaces = try context.fetch(FetchDescriptor<Workspace>())
        let cards = try context.fetch(FetchDescriptor<Card>())
        for workspace in workspaces {
            let names = Set(cards.filter { $0.workspace?.id == workspace.id }
                .map { $0.name.replacingOccurrences(of: " ", with: "").lowercased() })
            guard names.isSuperset(of: ["checking", "applecard", "amex"]) else { continue }
            let workspaceID = workspace.id
            let expenses = FetchDescriptor<VariableExpense>(predicate: #Predicate { $0.workspace?.id == workspaceID })
            if try context.fetchCount(expenses) > 0 {
                return workspace.id
            }
        }
        throw ScreenshotStartupError.missingSampleData
    }

    static func configurePreferences(workspaceID: UUID, defaults: UserDefaults, resetOnboarding: Bool = false) {
        if resetOnboarding || !defaults.bool(forKey: "debug_screenshotInitialized") {
            defaults.set(true, forKey: "didCompleteOnboarding")
            defaults.set(true, forKey: "onboarding_didChooseDataSource")
            defaults.set(true, forKey: "onboarding_didPressGetStarted")
            defaults.set(1, forKey: "onboarding_step")
            defaults.set(true, forKey: "debug_screenshotInitialized")
        }
        defaults.set(workspaceID.uuidString, forKey: "selectedWorkspaceID")
        defaults.set(true, forKey: "didSeedDefaultWorkspaces")
        defaults.set(false, forKey: "icloud_useCloud")
        defaults.set(false, forKey: "icloud_activeUseCloud")
        defaults.set(0.0, forKey: "icloud_bootstrapStartedAt")
    }

    private static func failIfRequested(stage: String) throws {
        // Fault injection is opt-in and restricted to UI-test launches.
        if UITestSupport.isEnabled,
           ProcessInfo.processInfo.arguments.contains("-screenshotTestFail\(stage)") {
            throw ScreenshotStartupError.injectedFailure(stage)
        }
    }
}
#endif
