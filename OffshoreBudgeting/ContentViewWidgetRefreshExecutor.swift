//
//  ContentViewWidgetRefreshExecutor.swift
//  OffshoreBudgeting
//
//  Created by Codex on 3/14/26.
//

import Foundation
import SwiftData

nonisolated struct ContentViewWidgetRefreshReport: Equatable {
    let incomeDurationMillis: Double
    let cardDurationMillis: Double
    let nextPlannedExpenseDurationMillis: Double
    let spendTrendsDurationMillis: Double

    var totalDurationMillis: Double {
        incomeDurationMillis
            + cardDurationMillis
            + nextPlannedExpenseDurationMillis
            + spendTrendsDurationMillis
    }

    var traceSummary: String {
        "incomeMs=\(Self.formatted(incomeDurationMillis)) " +
        "cardsMs=\(Self.formatted(cardDurationMillis)) " +
        "nextPlannedMs=\(Self.formatted(nextPlannedExpenseDurationMillis)) " +
        "spendTrendsMs=\(Self.formatted(spendTrendsDurationMillis)) " +
        "totalMs=\(Self.formatted(totalDurationMillis))"
    }

    private static func formatted(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

actor ContentViewWidgetRefreshExecutor {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func refreshAll(workspaceID: UUID) -> ContentViewWidgetRefreshReport {
        let modelContext = ModelContext(modelContainer)

        let incomeDurationMillis = Self.measure {
            IncomeWidgetSnapshotBuilder.buildAndSaveAllPeriods(
                modelContext: modelContext,
                workspaceID: workspaceID,
                shouldReloadTimelines: false
            )
        }

        let cardDurationMillis = Self.measure {
            CardWidgetSnapshotBuilder.buildAndSaveAllPeriods(
                modelContext: modelContext,
                workspaceID: workspaceID,
                shouldReloadTimelines: false
            )
        }

        let nextPlannedExpenseDurationMillis = Self.measure {
            NextPlannedExpenseWidgetSnapshotBuilder.buildAndSaveAllPeriods(
                modelContext: modelContext,
                workspaceID: workspaceID,
                shouldReloadTimelines: false
            )
        }

        let spendTrendsDurationMillis = Self.measure {
            SpendTrendsWidgetSnapshotBuilder.buildAndSaveAllPeriods(
                modelContext: modelContext,
                workspaceID: workspaceID,
                shouldReloadTimelines: false
            )
        }

        IncomeWidgetSnapshotStore.reloadIncomeWidgetTimelines()
        CardWidgetSnapshotStore.reloadCardWidgetTimelines()
        NextPlannedExpenseWidgetSnapshotStore.reloadTimelines()
        SpendTrendsWidgetSnapshotStore.reloadTimelines()

        return ContentViewWidgetRefreshReport(
            incomeDurationMillis: incomeDurationMillis,
            cardDurationMillis: cardDurationMillis,
            nextPlannedExpenseDurationMillis: nextPlannedExpenseDurationMillis,
            spendTrendsDurationMillis: spendTrendsDurationMillis
        )
    }

    private static func measure(_ work: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        work()
        let end = DispatchTime.now().uptimeNanoseconds
        return Double(end - start) / 1_000_000
    }
}
