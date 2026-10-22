import SwiftUI

/// Publishes Home-owned dates to the phone tab shell without moving persistence.
@MainActor
@Observable
final class HomeDateRangeAccessory {
    private(set) var ownerID: UUID?
    private(set) var workspaceID: UUID?
    private(set) var startDate: Date = .now
    private(set) var endDate: Date = .now
    private(set) var apply: (Date, Date) -> Void = { _, _ in }

    func register(ownerID: UUID, workspaceID: UUID, start: Date, end: Date,
                  apply: @escaping (Date, Date) -> Void) {
        self.ownerID = ownerID
        self.workspaceID = workspaceID
        startDate = start
        endDate = end
        self.apply = apply
    }

    func clear(ownerID: UUID) {
        guard self.ownerID == ownerID else { return }
        self.ownerID = nil
        workspaceID = nil
        apply = { _, _ in }
    }
}

private struct HomeDateRangeAccessoryKey: EnvironmentKey {
    static let defaultValue: HomeDateRangeAccessory? = nil
}

extension EnvironmentValues {
    var homeDateRangeAccessory: HomeDateRangeAccessory? {
        get { self[HomeDateRangeAccessoryKey.self] }
        set { self[HomeDateRangeAccessoryKey.self] = newValue }
    }
}
