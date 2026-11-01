import Foundation

enum WorkspaceProgressPreferences {
    static func hiddenKey(workspaceID: UUID) -> String {
        "general_hideWorkspaceProgress_\(workspaceID.uuidString)"
    }
}
