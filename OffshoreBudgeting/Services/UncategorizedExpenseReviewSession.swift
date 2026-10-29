import SwiftUI

/// Owned above the lock gate. Temporary inactivity and view reconstruction do not
/// create a new opportunity to interrupt the user.
@Observable @MainActor
final class UncategorizedExpenseReviewSession {
    private(set) var generation = 0
    private(set) var isPending = false
    private(set) var workspaceID: UUID?
    private var hasStarted = false
    private var wasBackgrounded = false

    func update(phase: ScenePhase, enabled: Bool) {
        if phase == .background {
            wasBackgrounded = true
        } else if phase == .active, !hasStarted || wasBackgrounded {
            hasStarted = true
            wasBackgrounded = false
            generation += 1
            isPending = enabled
            workspaceID = nil
        }
    }

    func selectWorkspace(_ id: UUID?) {
        guard let id else { return }
        if let workspaceID, workspaceID != id {
            isPending = false
        }
        workspaceID = id
    }

    func consume() {
        isPending = false
    }
}
