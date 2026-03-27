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
    let safeSpendTodayDurationMillis: Double
    let forecastSavingsDurationMillis: Double

    var totalDurationMillis: Double {
        incomeDurationMillis
            + cardDurationMillis
            + nextPlannedExpenseDurationMillis
            + spendTrendsDurationMillis
            + safeSpendTodayDurationMillis
            + forecastSavingsDurationMillis
    }

    var traceSummary: String {
        "incomeMs=\(Self.formatted(incomeDurationMillis)) " +
        "cardsMs=\(Self.formatted(cardDurationMillis)) " +
        "nextPlannedMs=\(Self.formatted(nextPlannedExpenseDurationMillis)) " +
        "spendTrendsMs=\(Self.formatted(spendTrendsDurationMillis)) " +
        "safeSpendMs=\(Self.formatted(safeSpendTodayDurationMillis)) " +
        "forecastMs=\(Self.formatted(forecastSavingsDurationMillis)) " +
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

    func refreshAll(workspaceID: UUID) async -> ContentViewWidgetRefreshReport {
        let incomeDurationMillis = Self.measure {
            let modelContext = ModelContext(modelContainer)
            IncomeWidgetSnapshotBuilder.buildAndSaveAllPeriods(
                modelContext: modelContext,
                workspaceID: workspaceID,
                shouldReloadTimelines: false
            )
        }

        let cardDurationMillis = Self.measure {
            let modelContext = ModelContext(modelContainer)
            CardWidgetSnapshotBuilder.buildAndSaveAllPeriods(
                modelContext: modelContext,
                workspaceID: workspaceID,
                shouldReloadTimelines: false
            )
        }

        let nextPlannedExpenseDurationMillis = Self.measure {
            let modelContext = ModelContext(modelContainer)
            NextPlannedExpenseWidgetSnapshotBuilder.buildAndSaveAllPeriods(
                modelContext: modelContext,
                workspaceID: workspaceID,
                shouldReloadTimelines: false
            )
        }

        let spendTrendsDurationMillis = Self.measure {
            let modelContext = ModelContext(modelContainer)
            SpendTrendsWidgetSnapshotBuilder.buildAndSaveAllPeriods(
                modelContext: modelContext,
                workspaceID: workspaceID,
                shouldReloadTimelines: false
            )
        }

        let safeSpendTodayStart = DispatchTime.now().uptimeNanoseconds
        await MainActor.run {
            let modelContext = ModelContext(modelContainer)
            SafeSpendTodayWidgetSnapshotBuilder.buildAndSave(
                modelContext: modelContext,
                workspaceID: workspaceID,
                shouldReloadTimelines: false
            )
        }
        let safeSpendTodayDurationMillis = Double(DispatchTime.now().uptimeNanoseconds - safeSpendTodayStart) / 1_000_000

        let forecastSavingsStart = DispatchTime.now().uptimeNanoseconds
        await MainActor.run {
            let modelContext = ModelContext(modelContainer)
            ForecastSavingsWidgetSnapshotBuilder.buildAndSave(
                modelContext: modelContext,
                workspaceID: workspaceID,
                shouldReloadTimelines: false
            )
        }
        let forecastSavingsDurationMillis = Double(DispatchTime.now().uptimeNanoseconds - forecastSavingsStart) / 1_000_000

        IncomeWidgetSnapshotStore.reloadIncomeWidgetTimelines()
        CardWidgetSnapshotStore.reloadCardWidgetTimelines()
        NextPlannedExpenseWidgetSnapshotStore.reloadTimelines()
        SpendTrendsWidgetSnapshotStore.reloadTimelines()
        await MainActor.run {
            SafeSpendTodayWidgetSnapshotBuilder.reloadTimelines()
            ForecastSavingsWidgetSnapshotBuilder.reloadTimelines()
        }

        return ContentViewWidgetRefreshReport(
            incomeDurationMillis: incomeDurationMillis,
            cardDurationMillis: cardDurationMillis,
            nextPlannedExpenseDurationMillis: nextPlannedExpenseDurationMillis,
            spendTrendsDurationMillis: spendTrendsDurationMillis,
            safeSpendTodayDurationMillis: safeSpendTodayDurationMillis,
            forecastSavingsDurationMillis: forecastSavingsDurationMillis
        )
    }

    private static func measure(_ work: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        work()
        let end = DispatchTime.now().uptimeNanoseconds
        return Double(end - start) / 1_000_000
    }
}
