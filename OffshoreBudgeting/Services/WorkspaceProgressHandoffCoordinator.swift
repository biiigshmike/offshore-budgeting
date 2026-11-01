import Foundation
import Observation

/// A process-wide claim prevents two active windows from presenting the same handoff.
/// Keep ownership until dismissal finishes so launch prompts cannot interrupt the sheet.
@Observable @MainActor
final class WorkspaceProgressHandoffCoordinator {
    static let shared = WorkspaceProgressHandoffCoordinator()

    private(set) var ownerID: UUID?
    private(set) var workspaceID: UUID?
    var isPresenting: Bool { ownerID != nil }

    func claim(workspaceID: UUID, ownerID: UUID, store: WorkspaceProgressHandoffStore) -> Bool {
        guard self.ownerID == nil, store.consume(workspaceID: workspaceID) else { return false }
        self.ownerID = ownerID
        self.workspaceID = workspaceID
        return true
    }

    func finish(ownerID: UUID) {
        guard self.ownerID == ownerID else { return }
        self.ownerID = nil
        self.workspaceID = nil
    }
}
