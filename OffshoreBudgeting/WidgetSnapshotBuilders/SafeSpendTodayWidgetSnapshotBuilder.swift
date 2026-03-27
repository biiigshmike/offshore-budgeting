import Foundation
import SwiftData
import WidgetKit

@MainActor
enum SafeSpendTodayWidgetSnapshotBuilder {
    private static let appGroupID = "group.com.mb.offshore-budgeting"
    private static let selectedWorkspaceKey = "selectedWorkspaceID"
    private static let widgetKind = "SafeSpendTodayWidget"

    private struct Snapshot: Codable {
        let title: String
        let periodTitle: String
        let rangeStart: Date
        let rangeEnd: Date
        let safeToSpendToday: Double?
        let periodRemainingRoom: Double?
        let daysLeftInPeriod: Int?
        let isDailyPeriod: Bool
        let message: String?
    }

    static func buildAndSave(
        modelContext: ModelContext,
        workspaceID: UUID,
        now: Date = .now,
        shouldReloadTimelines: Bool = true
    ) {
        guard let snapshot = buildSnapshot(
            modelContext: modelContext,
            workspaceID: workspaceID,
            now: now
        ) else {
            return
        }

        save(
            snapshot: snapshot,
            workspaceID: workspaceID.uuidString
        )

        if shouldReloadTimelines {
            reloadTimelines()
        }
    }

    private static func buildSnapshot(
        modelContext: ModelContext,
        workspaceID: UUID,
        now: Date
    ) -> Snapshot? {
        let workspaceDescriptor = FetchDescriptor<Workspace>(
            predicate: #Predicate<Workspace> { workspace in
                workspace.id == workspaceID
            }
        )

        guard let workspace = try? modelContext.fetch(workspaceDescriptor).first else {
            return nil
        }

        let budgetingPeriod = defaultBudgetingPeriodFromSharedDefaults()
        let summary = SafeSpendTodayCalculator.calculate(
            workspace: workspace,
            budgetingPeriod: budgetingPeriod,
            now: now
        )

        return Snapshot(
            title: "Safe Spend Today",
            periodTitle: budgetingPeriod.displayTitle,
            rangeStart: summary.rangeStart,
            rangeEnd: summary.rangeEnd,
            safeToSpendToday: summary.safeToSpendToday,
            periodRemainingRoom: summary.periodRemainingRoom,
            daysLeftInPeriod: summary.daysLeftInPeriod,
            isDailyPeriod: summary.isDaily,
            message: nil
        )
    }

    static func reloadTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    static func setSelectedWorkspaceID(_ workspaceID: String) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.set(workspaceID, forKey: selectedWorkspaceKey)
    }

    private static func save(snapshot: Snapshot, workspaceID: String) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        setSelectedWorkspaceID(workspaceID)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey(workspaceID: workspaceID))
    }

    private static func snapshotKey(workspaceID: String) -> String {
        "safeSpendTodayWidget.snapshot.\(workspaceID)"
    }

    private static func defaultBudgetingPeriodFromSharedDefaults() -> BudgetingPeriod {
        let defaults = UserDefaults(suiteName: appGroupID)
        let rawValue = defaults?.string(forKey: "general_defaultBudgetingPeriod") ?? BudgetingPeriod.monthly.rawValue
        return BudgetingPeriod(rawValue: rawValue) ?? .monthly
    }
}
