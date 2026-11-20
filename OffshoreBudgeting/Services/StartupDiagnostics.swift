import Foundation
import SwiftData

#if DEBUG
@MainActor
enum StartupDiagnostics {
    private static let retainedLogCount = 5
    private static let maximumLogBytes = 1_048_576
    private static var didBeginLaunch = false
    private static var bytesWritten = 0
    private static var didReachLogLimit = false

    private(set) static var currentLogURL: URL?
    private(set) static var persistenceError: String?

    private static var directory: URL {
        PersistentStoreLocation.directory(in: URL.applicationSupportDirectory)
            .appending(path: "StartupDiagnostics", directoryHint: .isDirectory)
    }

    /// Called before store setup. Also lazy-started by log() for other entry points.
    static func beginLaunch() {
        guard !didBeginLaunch else { return }
        didBeginLaunch = true

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let filename = "startup-\(Date.now.timeIntervalSince1970)-\(ProcessInfo.processInfo.processIdentifier).log"
            let url = directory.appending(path: filename)
            try Data().write(to: url, options: .atomic)
            currentLogURL = url
            for oldURL in savedLogURLs().dropFirst(retainedLogCount) {
                try FileManager.default.removeItem(at: oldURL)
            }
        } catch {
            persistenceError = error.localizedDescription
            print("[StartupDiagnostics] Could not prepare persisted launch log: \(error)")
        }

        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        log("launch identity bundle=\(bundle.bundleIdentifier ?? "unknown") version=\(version) build=\(build) pid=\(ProcessInfo.processInfo.processIdentifier) compiledScreenshotBuild=\(DebugScreenshotMode.isCompiledBuild)")
        log("launch executable=\(bundle.executableURL?.path ?? "unknown") arguments=\(ProcessInfo.processInfo.arguments)")
    }

    static func log(_ message: String) {
        if !didBeginLaunch {
            beginLaunch()
        }
        let line = "[StartupDiagnostics] \(Date.now.formatted(.iso8601)) \(message)\n"
        print(line, terminator: "")
        guard let currentLogURL, !didReachLogLimit else { return }

        let data = Data(line.utf8)
        guard bytesWritten + data.count <= maximumLogBytes else {
            didReachLogLimit = true
            print("[StartupDiagnostics] Persisted launch log reached its 1 MB limit; console logging continues.")
            return
        }
        do {
            let handle = try FileHandle(forWritingTo: currentLogURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            bytesWritten += data.count
        } catch {
            persistenceError = error.localizedDescription
            print("[StartupDiagnostics] Could not persist launch log: \(error)")
        }
    }

    /// Newest first; only this app sandbox's diagnostic files are considered.
    static func savedLogURLs() -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.creationDateKey],
                options: .skipsHiddenFiles
            )
            .filter { $0.pathExtension == "log" }
            .sorted {
                let first = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let second = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return first > second
            }
        } catch {
            persistenceError = error.localizedDescription
            return []
        }
    }

    static func contents(of url: URL) -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            return "Could not read log: \(error.localizedDescription)"
        }
    }

    static func logContainer(_ container: ModelContainer) {
        log("container instance=\(ObjectIdentifier(container))")
        for configuration in container.configurations {
            log("opened actual store name=\(configuration.name) url=\(configuration.url.absoluteString) inMemory=\(configuration.isStoredInMemoryOnly)")
        }
    }

    static func logWorkspaceCount(container: ModelContainer, stage: String) {
        do {
            // Use a fresh context to inspect the saved store, not pending seed inserts.
            let count = try ModelContext(container).fetchCount(FetchDescriptor<Workspace>())
            log("\(stage) persistedWorkspaceCount=\(count)")
        } catch {
            log("\(stage) workspace count failed error=\(String(reflecting: error)) details=\((error as NSError).userInfo)")
        }
    }

    static func logDisplayedContext(_ context: ModelContext, selectedWorkspaceID: String) {
        log("displayed ContentView pid=\(ProcessInfo.processInfo.processIdentifier) screenshotMode=\(DebugScreenshotMode.isEnabled) selectedWorkspaceID=\(selectedWorkspaceID)")
        logContainer(context.container)
        let isScreenshotStore = context.container.configurations.count == 1
            && context.container.configurations.allSatisfy { DebugScreenshotMode.owns($0) }
        log("displayed ContentView usesScreenshotStore=\(isScreenshotStore)")
        do {
            let workspaces = try context.fetch(FetchDescriptor<Workspace>())
            let cardCount = try context.fetchCount(FetchDescriptor<Card>())
            let expenseCount = try context.fetchCount(FetchDescriptor<VariableExpense>())
            log("displayed data workspaces=\(workspaces.map { "\($0.name) [\($0.id)]" }.sorted()) cardCount=\(cardCount) variableExpenseCount=\(expenseCount)")
        } catch {
            log("displayed data fetch failed error=\(String(reflecting: error)) details=\((error as NSError).userInfo)")
        }
    }
}
#endif
