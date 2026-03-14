import Foundation

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
