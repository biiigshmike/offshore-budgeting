import Foundation
import SwiftData

struct SavingsGraphSnapshot: Equatable {
    struct Point: Equatable {
        let date: Date
        let total: Double
    }

    let runningTotal: Double
    let runningTotalPoints: [Point]
    let currentPeriodPoints: [Point]
    let signature: SavingsGraphSnapshotSignature
}

struct SavingsGraphSnapshotSignature: Equatable {
    let workspaceID: UUID
    let rangeStart: Date
    let rangeEnd: Date
    let accountID: UUID?
    let entriesCount: Int
    let latestDateStamp: Int64
    let latestCreatedAtStamp: Int64
    let totalCents: Int64
}

@MainActor
enum SavingsGraphSnapshotService {
    static func cacheKey(
        workspaceID: UUID,
        rangeStart: Date,
        rangeEnd: Date
    ) -> String {
        [
            "savings-graph",
            workspaceID.uuidString,
            String(Int64(rangeStart.timeIntervalSinceReferenceDate)),
            String(Int64(rangeEnd.timeIntervalSinceReferenceDate))
        ].joined(separator: "|")
    }

    static func defaultRange(
        defaultBudgetingPeriodRaw: String,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        let period = BudgetingPeriod(rawValue: defaultBudgetingPeriodRaw) ?? .monthly
        let range = period.defaultRange(containing: now, calendar: calendar)
        return (
            start: calendar.startOfDay(for: range.start),
            end: normalizedEnd(range.end, calendar: calendar)
        )
    }

    static func signature(
        for workspace: Workspace,
        rangeStart: Date,
        rangeEnd: Date,
        modelContext: ModelContext
    ) -> SavingsGraphSnapshotSignature {
        let account = workspaceSavingsAccounts(for: workspace, modelContext: modelContext).first
        let entries = accountScopedEntries(for: workspace, accountID: account?.id, modelContext: modelContext)

        return SavingsGraphSnapshotSignature(
            workspaceID: workspace.id,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            accountID: account?.id,
            entriesCount: entries.count,
            latestDateStamp: Int64(entries.map(\.date.timeIntervalSinceReferenceDate).max() ?? 0),
            latestCreatedAtStamp: Int64(entries.map(\.createdAt.timeIntervalSinceReferenceDate).max() ?? 0),
            totalCents: Int64((account?.total ?? 0) * 100)
        )
    }

    static func buildSnapshot(
        for workspace: Workspace,
        rangeStart: Date,
        rangeEnd: Date,
        modelContext: ModelContext
    ) -> SavingsGraphSnapshot {
        let account = workspaceSavingsAccounts(for: workspace, modelContext: modelContext).first
        let entries = accountScopedEntries(for: workspace, accountID: account?.id, modelContext: modelContext)
        let signature = signature(
            for: workspace,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            modelContext: modelContext
        )

        return SavingsGraphSnapshot(
            runningTotal: account?.total ?? 0,
            runningTotalPoints: runningTotalPoints(from: entries),
            currentPeriodPoints: currentPeriodPoints(
                from: entries,
                rangeStart: rangeStart,
                rangeEnd: rangeEnd
            ),
            signature: signature
        )
    }

    private static func workspaceSavingsAccounts(
        for workspace: Workspace,
        modelContext: ModelContext
    ) -> [SavingsAccount] {
        let workspaceID = workspace.id
        let descriptor = FetchDescriptor<SavingsAccount>(
            predicate: #Predicate<SavingsAccount> { account in
                account.workspace != nil
            },
            sortBy: [SortDescriptor(\SavingsAccount.createdAt, order: .forward)]
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).filter { account in
            account.workspace?.id == workspaceID
        }
    }

    private static func accountScopedEntries(
        for workspace: Workspace,
        accountID: UUID?,
        modelContext: ModelContext
    ) -> [SavingsLedgerEntry] {
        guard let accountID else { return [] }
        let workspaceID = workspace.id
        let descriptor = FetchDescriptor<SavingsLedgerEntry>(
            predicate: #Predicate<SavingsLedgerEntry> { entry in
                entry.workspace != nil && entry.account != nil
            },
            sortBy: [
                SortDescriptor(\SavingsLedgerEntry.date, order: .forward),
                SortDescriptor(\SavingsLedgerEntry.createdAt, order: .forward)
            ]
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).filter { entry in
            entry.workspace?.id == workspaceID && entry.account?.id == accountID
        }
    }

    private static func currentPeriodPoints(
        from entries: [SavingsLedgerEntry],
        rangeStart: Date,
        rangeEnd: Date
    ) -> [SavingsGraphSnapshot.Point] {
        let entriesAsc = entries.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.date < rhs.date
        }

        let totalBeforeRange = entriesAsc
            .filter { $0.date < rangeStart }
            .reduce(0.0) { $0 + $1.amount }

        let entriesInRange = entriesAsc.filter { entry in
            entry.date >= rangeStart && entry.date <= rangeEnd
        }

        guard !entriesInRange.isEmpty else { return [] }

        var total = totalBeforeRange
        var totalsByDay: [Date: Double] = [:]
        totalsByDay[rangeStart] = totalBeforeRange

        for entry in entriesInRange {
            total += entry.amount
            let day = Calendar.current.startOfDay(for: entry.date)
            totalsByDay[day] = total
        }

        return totalsByDay
            .keys
            .sorted()
            .map { day in
                SavingsGraphSnapshot.Point(date: day, total: totalsByDay[day] ?? 0)
            }
    }

    private static func runningTotalPoints(from entries: [SavingsLedgerEntry]) -> [SavingsGraphSnapshot.Point] {
        let entriesAsc = entries.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.date < rhs.date
        }

        guard !entriesAsc.isEmpty else { return [] }

        var runningTotal = 0.0
        var totalsByDay: [Date: Double] = [:]

        for entry in entriesAsc {
            runningTotal += entry.amount
            let day = Calendar.current.startOfDay(for: entry.date)
            totalsByDay[day] = runningTotal
        }

        return totalsByDay
            .keys
            .sorted()
            .map { day in
                SavingsGraphSnapshot.Point(date: day, total: totalsByDay[day] ?? 0)
            }
    }

    private static func normalizedEnd(_ date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }
}
