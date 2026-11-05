import Foundation

enum WorkspaceProgressPreferences {
    static func hiddenKey(workspaceID: UUID) -> String {
        "general_hideWorkspaceProgress_\(workspaceID.uuidString)"
    }

    static func savedChoice(for workspace: Workspace, defaults: UserDefaults = .standard) -> Bool? {
        workspace.hideWorkspaceProgress ?? legacyChoice(for: workspace, defaults: defaults)
    }

    static func migrateLegacyChoice(
        for workspace: Workspace,
        defaults: UserDefaults = .standard,
        save: () throws -> Void
    ) rethrows {
        guard workspace.hideWorkspaceProgress == nil,
              let isHidden = legacyChoice(for: workspace, defaults: defaults)
        else { return }
        try saveChoice(isHidden, for: workspace, save: save)
    }

    static func saveChoice(_ isHidden: Bool, for workspace: Workspace, save: () throws -> Void) rethrows {
        let previousChoice = workspace.hideWorkspaceProgress
        workspace.hideWorkspaceProgress = isHidden
        do {
            try save()
        } catch {
            workspace.hideWorkspaceProgress = previousChoice
            throw error
        }
    }

    private static func legacyChoice(for workspace: Workspace, defaults: UserDefaults) -> Bool? {
        defaults.object(forKey: hiddenKey(workspaceID: workspace.id)) as? Bool
    }
}
