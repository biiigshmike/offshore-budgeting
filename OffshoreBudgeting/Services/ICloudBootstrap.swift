import Foundation
#if DEBUG
import CoreData
#endif

enum ICloudBootstrap {
    static let maxWaitSeconds: TimeInterval = 7

    enum WorkspaceDiscoveryPhase: Equatable {
        case loading
        case loadingSlow
        case loaded(hasWorkspaces: Bool)
    }

    static func workspaceDiscoveryPhase(
        useICloud: Bool,
        startedAt: Double,
        workspaceCount: Int,
        now: Date = .now
    ) -> WorkspaceDiscoveryPhase {
        if workspaceCount > 0 {
            return .loaded(hasWorkspaces: true)
        }

        if useICloud {
            guard startedAt > 0 else { return .loading }

            let elapsed = now.timeIntervalSince1970 - startedAt
            return elapsed >= maxWaitSeconds ? .loadingSlow : .loading
        }

        return .loaded(hasWorkspaces: false)
    }

    static func logICloudSelection(startedAt: Double, logger: (String) -> Void = { print($0) }) {
        guard startedAt > 0 else { return }
        #if DEBUG
        logger("[iCloudBootstrap] iCloud selected at \(startedAt). Waiting for workspaces to load.")
        #endif
    }

    #if DEBUG
    private static var cloudKitObserver: NSObjectProtocol?

    static func observeCloudKitEvents(startedAt: Double) {
        let center = NotificationCenter.default
        if let cloudKitObserver {
            center.removeObserver(cloudKitObserver)
        }
        // Keep listening after the first workspace appears so the import end is captured.
        cloudKitObserver = center.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: nil
        ) { @Sendable notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }

            let phase: String
            switch event.type {
            case .setup: phase = "setup"
            case .import: phase = "import"
            default: return
            }

            if let end = event.endDate {
                let result = event.succeeded ? "succeeded" : "failed"
                logMilestone("CloudKit \(phase) finished (\(result))", startedAt: startedAt, at: end)
            } else {
                logMilestone("CloudKit \(phase) started", startedAt: startedAt, at: event.startDate)
            }
        }
    }

    nonisolated static func logMilestone(_ message: String, startedAt: Double, at date: Date = .now) {
        guard startedAt > 0 else { return }
        let elapsed = date.timeIntervalSince1970 - startedAt
        print("[iCloudBootstrap] +\(String(format: "%.2f", elapsed))s \(message)")
    }
    #endif

    static func logFirstWorkspaceAppearance(
        startedAt: Double,
        workspaceCount: Int,
        logger: (String) -> Void = { print($0) }
    ) {
        guard startedAt > 0, workspaceCount > 0 else { return }
        let elapsed = Date().timeIntervalSince1970 - startedAt

        #if DEBUG
        logger("[iCloudBootstrap] First iCloud workspace appeared after \(String(format: "%.2f", elapsed))s. Count: \(workspaceCount)")
        #endif
    }
}
