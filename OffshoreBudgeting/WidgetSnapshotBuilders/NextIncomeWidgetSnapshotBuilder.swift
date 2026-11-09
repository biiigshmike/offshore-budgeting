import Foundation
import SwiftData

nonisolated enum NextIncomeWidgetSnapshotBuilder {
    static func buildAndSave(modelContext: ModelContext, workspaceID: UUID, now: Date) {
        let days = buildDays(modelContext: modelContext, workspaceID: workspaceID, now: now) ?? []
        NextIncomeWidgetSnapshotStore.save(days, workspaceID: workspaceID.uuidString)
    }

    static func buildDays(
        modelContext: ModelContext,
        workspaceID: UUID,
        now: Date,
        calendar: Calendar = .current
    ) -> [NextIncomeWidgetDay]? {
        let today = calendar.startOfDay(for: now)
        let descriptor = FetchDescriptor<Income>(
            predicate: #Predicate<Income> {
                $0.workspace?.id == workspaceID && $0.isPlanned && $0.date >= today
            },
            sortBy: [SortDescriptor(\Income.date)]
        )

        guard let incomes = try? modelContext.fetch(descriptor) else { return nil }
        return (0...14).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return NextIncomeWidgetDay(date: day, nextIncomeDate: incomes.first { $0.date >= day }?.date)
        }
    }
}
