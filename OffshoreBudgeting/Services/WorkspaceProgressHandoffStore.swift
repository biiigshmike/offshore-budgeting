import Foundation

/// Device-local intent to introduce setup progress after an explicit onboarding completion.
/// Main-actor access makes a matching consume atomic across the app's scenes.
@MainActor
struct WorkspaceProgressHandoffStore {
    nonisolated static let pendingWorkspaceIDKey = "onboarding_pendingWorkspaceProgressID"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var pendingWorkspaceID: UUID? {
        guard let rawValue = defaults.string(forKey: Self.pendingWorkspaceIDKey) else { return nil }
        return UUID(uuidString: rawValue)
    }

    func enqueue(workspaceID: UUID) {
        defaults.set(workspaceID.uuidString, forKey: Self.pendingWorkspaceIDKey)
    }

    @discardableResult
    func consume(workspaceID: UUID) -> Bool {
        guard pendingWorkspaceID == workspaceID else { return false }
        cancel()
        return true
    }

    func cancel() {
        defaults.removeObject(forKey: Self.pendingWorkspaceIDKey)
    }
}
