import Foundation
import WidgetKit

nonisolated struct CategoryLimitWidgetMetric: Codable, Equatable {
    let id: UUID
    let name: String
    let fractionUsed: Double
    // Optional so widgets can still read percentage-only snapshots after upgrade.
    var limitAmount: Double? = nil
    var spentAmount: Double? = nil

    var remainingAmount: Double? {
        guard let limitAmount, limitAmount.isFinite, limitAmount > 0,
              let spentAmount, spentAmount.isFinite else { return nil }
        let remaining = limitAmount - spentAmount
        return remaining.isFinite ? remaining : nil
    }
}

nonisolated struct CategoryLimitWidgetSnapshot: Codable, Equatable {
    let date: Date
    let validUntil: Date
    let metrics: [CategoryLimitWidgetMetric]
}

nonisolated struct CategoryLimitWidgetSnapshotSet: Codable {
    let days: [CategoryLimitWidgetSnapshot]
}

nonisolated struct CategoryLimitWidgetPickerBudget: Codable, Equatable {
    let start: Date
    let end: Date
    let categoryIDs: Set<UUID>
}

nonisolated struct CategoryLimitWidgetPickerOptions: Codable, Equatable {
    let budgets: [CategoryLimitWidgetPickerBudget]
    let categoryNames: [UUID: String]

    func eligibleCategoryIDs(asOf date: Date) -> Set<UUID> {
        budgets.first { $0.start <= date && date < $0.end }?.categoryIDs ?? []
    }
}

nonisolated enum CategoryLimitWidgetSnapshotStore {
    static let kind = "CategoryLimitWidget"

    static func save(_ snapshots: CategoryLimitWidgetSnapshotSet, workspaceID: UUID) {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        LockScreenWidgetWorkspace.defaults?.set(data, forKey: key(workspaceID))
    }

    static func loadSelected() -> CategoryLimitWidgetSnapshotSet? {
        guard let workspaceID = selectedWorkspaceID,
              let data = LockScreenWidgetWorkspace.defaults?.data(forKey: key(workspaceID)) else {
            return nil
        }
        return try? JSONDecoder().decode(CategoryLimitWidgetSnapshotSet.self, from: data)
    }

    static func savePickerOptions(_ options: CategoryLimitWidgetPickerOptions, workspaceID: UUID) {
        guard let data = try? JSONEncoder().encode(options) else { return }
        LockScreenWidgetWorkspace.defaults?.set(data, forKey: pickerKey(workspaceID))
    }

    static func loadSelectedPickerOptions() -> CategoryLimitWidgetPickerOptions? {
        guard let workspaceID = selectedWorkspaceID,
              let data = LockScreenWidgetWorkspace.defaults?.data(forKey: pickerKey(workspaceID)) else {
            return nil
        }
        return try? JSONDecoder().decode(CategoryLimitWidgetPickerOptions.self, from: data)
    }

    private static var selectedWorkspaceID: UUID? {
        LockScreenWidgetWorkspace.selectedID.flatMap(UUID.init(uuidString:))
    }

    static func reloadTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }

    private static func pickerKey(_ workspaceID: UUID) -> String {
        "categoryLimitWidget.picker.\(workspaceID.uuidString)"
    }

    private static func key(_ workspaceID: UUID) -> String {
        "categoryLimitWidget.snapshots.\(workspaceID.uuidString)"
    }
}
