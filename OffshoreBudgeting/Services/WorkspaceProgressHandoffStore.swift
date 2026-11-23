import Foundation

/// Device-local intent to introduce setup progress after an explicit onboarding completion.
/// Main-actor access makes a matching consume atomic across the app's scenes.
@MainActor
struct WorkspaceProgressHandoffStore {
    nonisolated static let pendingWorkspaceIDKey = "onboarding_pendingWorkspaceProgressID"
    private static let budgetShortcutWorkspaceIDKey = "onboarding_pendingProgressBudgetShortcutWorkspaceID"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var pendingWorkspaceID: UUID? {
        guard let rawValue = defaults.string(forKey: Self.pendingWorkspaceIDKey) else { return nil }
        return UUID(uuidString: rawValue)
    }

    var offersBudgetShortcut: Bool {
        guard let pendingWorkspaceID else { return false }
        return defaults.string(forKey: Self.budgetShortcutWorkspaceIDKey) == pendingWorkspaceID.uuidString
    }

    func enqueue(workspaceID: UUID, offersBudgetShortcut: Bool = false) {
        defaults.set(offersBudgetShortcut ? workspaceID.uuidString : nil, forKey: Self.budgetShortcutWorkspaceIDKey)
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
        defaults.removeObject(forKey: Self.budgetShortcutWorkspaceIDKey)
    }
}
