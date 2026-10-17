//
//  HomeViewBootstrap.swift
//  OffshoreBudgeting
//
//  Created by Codex on 3/13/26.
//

import Foundation

struct HomeViewBootstrap {
    struct AppliedRangeSeed: Equatable {
        let start: Date
        let end: Date
        let lastSyncedDefaultBudgetingPeriodRaw: String
    }

    private static func appliedStartKey(workspaceID: UUID) -> String {
        "home_appliedStartTimestamp_\(workspaceID.uuidString)"
    }

    private static func appliedEndKey(workspaceID: UUID) -> String {
        "home_appliedEndTimestamp_\(workspaceID.uuidString)"
    }

    private static func lastSyncedDefaultBudgetingPeriodKey(workspaceID: UUID) -> String {
        "home_lastSyncedDefaultBudgetingPeriod_\(workspaceID.uuidString)"
    }

    private static let legacyAppliedStartKey = "home_appliedStartTimestamp"
    private static let legacyAppliedEndKey = "home_appliedEndTimestamp"

    static func canonicalAppliedRangeSeed(
        defaultBudgetingPeriodRaw: String,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> AppliedRangeSeed {
        let period = BudgetingPeriod(rawValue: defaultBudgetingPeriodRaw) ?? .monthly
        let range = period.defaultRange(containing: now, calendar: calendar)
        return AppliedRangeSeed(
            start: range.start,
            end: range.end,
            lastSyncedDefaultBudgetingPeriodRaw: defaultBudgetingPeriodRaw
        )
    }

    static func initialPinnedItems(
        workspaceID: UUID,
        fallbackCardIDs: [UUID],
        defaults: UserDefaults = .standard
    ) -> [HomePinnedItem] {
        let itemsStore = HomePinnedItemsStore(workspaceID: workspaceID, defaults: defaults)
        let loaded = itemsStore.load()

        if loaded.isEmpty == false {
            return loaded
        }

        let widgetsStore = HomePinnedWidgetsStore(workspaceID: workspaceID, defaults: defaults)
        let cardsStore = HomePinnedCardsStore(workspaceID: workspaceID, defaults: defaults)

        let migratedWidgets = widgetsStore.load().map { HomePinnedItem.widget($0, .small) }

        let migratedCardIDs: [UUID] = {
            let loadedIDs = cardsStore.load()
            if loadedIDs.isEmpty {
                return fallbackCardIDs
            }
            return loadedIDs
        }()

        return migratedWidgets + migratedCardIDs.map { HomePinnedItem.card($0, .small) }
    }

    static func initialAppliedRangeSeed(
        workspaceID: UUID,
        defaultBudgetingPeriodRaw: String,
        defaults: UserDefaults = .standard,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> AppliedRangeSeed {
        let startKey = appliedStartKey(workspaceID: workspaceID)
        let endKey = appliedEndKey(workspaceID: workspaceID)
        let lastSyncedKey = lastSyncedDefaultBudgetingPeriodKey(workspaceID: workspaceID)

        let storedStart = defaults.object(forKey: startKey) as? Double
        let storedEnd = defaults.object(forKey: endKey) as? Double
        let storedLastSynced = defaults.string(forKey: lastSyncedKey) ?? ""

        if let storedStart, let storedEnd, storedStart > 0, storedEnd > 0 {
            let start = Date(timeIntervalSince1970: storedStart)
            let end = Date(timeIntervalSince1970: max(storedEnd, storedStart))
            return AppliedRangeSeed(
                start: start,
                end: end,
                lastSyncedDefaultBudgetingPeriodRaw: storedLastSynced
            )
        }

        let legacyStart = defaults.double(forKey: legacyAppliedStartKey)
        let legacyEnd = defaults.double(forKey: legacyAppliedEndKey)
        if legacyStart > 0, legacyEnd > 0 {
            let start = Date(timeIntervalSince1970: legacyStart)
            let end = Date(timeIntervalSince1970: max(legacyEnd, legacyStart))
            return AppliedRangeSeed(
                start: start,
                end: end,
                lastSyncedDefaultBudgetingPeriodRaw: defaultBudgetingPeriodRaw
            )
        }

        return canonicalAppliedRangeSeed(
            defaultBudgetingPeriodRaw: defaultBudgetingPeriodRaw,
            now: now,
            calendar: calendar
        )
    }
}
