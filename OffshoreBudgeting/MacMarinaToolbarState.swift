import SwiftUI

/// Publishes inspector actions to SwiftUI's window toolbar without owning the
/// window, sidebar, or navigation controllers.
@MainActor
@Observable
final class MacMarinaToolbarState {
    private(set) var owner: UUID?
    private(set) var creation: [MarinaToolbarAction] = []
    private(set) var management: [MarinaToolbarAction] = []

    func publish(owner: UUID, creation: [MarinaToolbarAction], management: [MarinaToolbarAction]) {
        self.owner = owner
        self.creation = creation
        self.management = management
    }

    func clear(owner: UUID) {
        guard self.owner == owner else { return }
        clear()
    }

    func clear() {
        owner = nil
        creation = []
        management = []
    }
}

private struct MacMarinaToolbarStateKey: EnvironmentKey {
    static let defaultValue: MacMarinaToolbarState? = nil
}

extension EnvironmentValues {
    var macMarinaToolbarState: MacMarinaToolbarState? {
        get { self[MacMarinaToolbarStateKey.self] }
        set { self[MacMarinaToolbarStateKey.self] = newValue }
    }
}
