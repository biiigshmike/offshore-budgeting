import Foundation
import SwiftData

@MainActor
enum SavingsAccountService {

    // MARK: - Account

    struct SavingsNormalizationReport {
        let mergedAccountsCount: Int
        let reassignedEntriesCount: Int
        let dedupedPeriodCloseCount: Int
        let dedupedManualAdjustmentCount: Int
        let removedReconciliationSettlementCount: Int
        let recalculatedTotal: Double
    }

    static func ensureSavingsAccount(
        for workspace: Workspace,
        modelContext: ModelContext
    ) -> SavingsAccount {
        var accounts = workspaceSavingsAccounts(for: workspace, modelContext: modelContext)
        if accounts.isEmpty {
            let account = SavingsAccount(workspace: workspace)
            modelContext.insert(account)
            accounts = [account]
        }
        return accounts[0]
    }

    static func workspaceSavingsAccounts(
        for workspace: Workspace,
        modelContext: ModelContext
    ) -> [SavingsAccount] {
        let workspaceID = workspace.id
        let descriptor = FetchDescriptor<SavingsAccount>(
            predicate: #Predicate<SavingsAccount> { account in
                account.workspace?.id == workspaceID
            },
            sortBy: [SortDescriptor(\SavingsAccount.createdAt, order: .forward)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    static func balance(for account: SavingsAccount) -> Double {
        account.total
    }

    @discardableResult
    static func normalizeSavingsData(
        for workspace: Workspace,
        modelContext: ModelContext
    ) -> SavingsNormalizationReport {
        let accounts = workspaceSavingsAccounts(for: workspace, modelContext: modelContext)
        guard let primaryAccount = accounts.first else {
            return SavingsNormalizationReport(
                mergedAccountsCount: 0,
                reassignedEntriesCount: 0,
                dedupedPeriodCloseCount: 0,
                dedupedManualAdjustmentCount: 0,
                removedReconciliationSettlementCount: 0,
                recalculatedTotal: 0
            )
        }

        var reassignedEntriesCount = 0
        var didMutate = false
        let workspaceEntries = workspaceSavingsEntries(for: workspace, modelContext: modelContext)
        for entry in workspaceEntries {
            let isAlreadyPrimary = entry.account?.id == primaryAccount.id
            if isAlreadyPrimary { continue }
            entry.account = primaryAccount
            reassignedEntriesCount += 1
            didMutate = true
        }

        var mergedAccountsCount = 0
        for duplicateAccount in accounts.dropFirst() {
            mergeAccountState(from: duplicateAccount, into: primaryAccount)
            modelContext.delete(duplicateAccount)
            mergedAccountsCount += 1
            didMutate = true
        }

        let dedupeReport = repairDuplicateEntries(
            for: workspace,
            preferredAccount: primaryAccount,
            modelContext: modelContext
        )
        if dedupeReport.didMutate {
            didMutate = true
        }

        let removedSettlementCount = removeMirroredReconciliationSettlements(
            for: workspace,
            preferredAccount: primaryAccount,
            modelContext: modelContext
        )
        if removedSettlementCount > 0 {
            didMutate = true
        }

        let previousTotal = primaryAccount.total
        recalculateAccountTotal(accountID: primaryAccount.id, modelContext: modelContext)
        if primaryAccount.total != previousTotal {
            didMutate = true
        }
        if didMutate {
            try? modelContext.save()
        }

        trace(
            "Normalization mergedAccounts=\(mergedAccountsCount) " +
            "reassignedEntries=\(reassignedEntriesCount) " +
            "dedupedPeriodClose=\(dedupeReport.periodCloseDeletedCount) " +
            "dedupedManual=\(dedupeReport.manualDeletedCount) " +
            "removedMirroredSettlements=\(removedSettlementCount) total=\(primaryAccount.total)"
        )

        return SavingsNormalizationReport(
            mergedAccountsCount: mergedAccountsCount,
            reassignedEntriesCount: reassignedEntriesCount,
            dedupedPeriodCloseCount: dedupeReport.periodCloseDeletedCount,
            dedupedManualAdjustmentCount: dedupeReport.manualDeletedCount,
            removedReconciliationSettlementCount: removedSettlementCount,
            recalculatedTotal: primaryAccount.total
        )
    }

    @discardableResult
    static func rebuildRunningTotal(
        for workspace: Workspace,
        modelContext: ModelContext
    ) -> Double {
        let account = ensureSavingsAccount(for: workspace, modelContext: modelContext)
        _ = removeMirroredReconciliationSettlements(
            for: workspace,
            preferredAccount: account,
            modelContext: modelContext
        )
        recalculateAccountTotal(accountID: account.id, modelContext: modelContext)
        try? modelContext.save()
        trace("Manual running-total rebuild total=\(account.total)")
        return account.total
    }

    // MARK: - Debug Trace

    private static var isTraceEnabled: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "debug_savingsAutoCaptureTraceEnabled")
        #else
        false
        #endif
    }

    private static func trace(_ message: String) {
        #if DEBUG
        guard isTraceEnabled else { return }
        print("[SavingsTrace] \(message)")
        #endif
    }

    // MARK: - Auto Capture

    static func runAutoCaptureIfNeeded(
        for workspace: Workspace,
        defaultBudgetingPeriodRaw: String,
        incomes: [Income],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        modelContext: ModelContext,
        now: Date = .now
    ) {
        let account = ensureSavingsAccount(for: workspace, modelContext: modelContext)
        let period = BudgetingPeriod(rawValue: defaultBudgetingPeriodRaw) ?? .monthly
        let workspaceID = workspace.id

        trace(
            "Auto-capture start workspace=\(workspace.name) period=\(period.rawValue) " +
            "incomes=\(incomes.count) planned=\(plannedExpenses.count) variable=\(variableExpenses.count)"
        )

        let dedupeReport = repairDuplicateEntries(
            for: workspace,
            preferredAccount: account,
            modelContext: modelContext
        )
        if dedupeReport.didMutate {
            trace(
                "Auto-capture repaired duplicates periodClose=\(dedupeReport.periodCloseDeletedCount) " +
                "manual=\(dedupeReport.manualDeletedCount)"
            )
        }

        let currentRange = periodRange(containing: now, period: period)
        guard let latestClosedRange = previousRange(before: currentRange.start, period: period) else {
            trace("No latest closed range found. Skipping auto-capture.")
            return
        }

        if !account.didBackfillHistory {
            trace("Backfill needed. through=\(AppDateFormat.abbreviatedDate(latestClosedRange.end))")
            backfillHistory(
                workspace: workspace,
                account: account,
                period: period,
                through: latestClosedRange.end,
                incomes: incomes,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                modelContext: modelContext
            )
            account.didBackfillHistory = true
            account.autoCaptureThroughDate = latestClosedRange.end
        }

        var refreshStartRange: (start: Date, end: Date)?
        var insertStartRange: (start: Date, end: Date)?
        if let autoCaptureThroughDate = account.autoCaptureThroughDate {
            let processedRange = periodRange(containing: autoCaptureThroughDate, period: period)
            let isRangeEnd = Calendar.current.isDate(autoCaptureThroughDate, inSameDayAs: processedRange.end)
            refreshStartRange = processedRange
            insertStartRange = isRangeEnd ? nextRange(after: processedRange, period: period) : processedRange
        } else {
            refreshStartRange = latestClosedRange
            insertStartRange = latestClosedRange
        }

        if let refreshStartRange {
            trace(
                "Capture window start=\(AppDateFormat.abbreviatedDate(refreshStartRange.start)) " +
                "latestClosedEnd=\(AppDateFormat.abbreviatedDate(latestClosedRange.end))"
            )
        } else {
            trace(
                "Capture window is empty latestClosedEnd=\(AppDateFormat.abbreviatedDate(latestClosedRange.end))"
            )
        }

        var cursor = refreshStartRange
        while let currentRange = cursor, currentRange.start <= latestClosedRange.start {
            refreshOrInsertPeriodClose(
                workspace: workspace,
                workspaceID: workspaceID,
                account: account,
                range: currentRange,
                incomes: incomes,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                modelContext: modelContext,
                allowInsert: shouldInsertPeriodClose(
                    currentRange,
                    insertStartRange: insertStartRange,
                    incomes: incomes,
                    plannedExpenses: plannedExpenses,
                    variableExpenses: variableExpenses
                )
            )

            guard let next = nextRange(after: currentRange, period: period) else { break }
            cursor = next
        }

        account.autoCaptureThroughDate = latestClosedRange.end
        recalculateAccountTotal(account)
        account.updatedAt = .now
        trace("Auto-capture end runningTotal=\(account.total)")
        try? modelContext.save()
    }

    static func shouldRunForegroundAutoCapture(
        for workspace: Workspace,
        defaultBudgetingPeriodRaw: String,
        modelContext: ModelContext,
        now: Date = .now
    ) -> Bool {
        guard let latestClosedPeriodEnd = latestClosedPeriodEnd(
            defaultBudgetingPeriodRaw: defaultBudgetingPeriodRaw,
            now: now
        ) else {
            return false
        }

        guard let account = workspaceSavingsAccounts(for: workspace, modelContext: modelContext).first else {
            return false
        }

        guard let autoCaptureThroughDate = account.autoCaptureThroughDate else {
            return true
        }

        return autoCaptureThroughDate < latestClosedPeriodEnd
    }

    static func latestClosedPeriodEnd(
        defaultBudgetingPeriodRaw: String,
        now: Date = .now
    ) -> Date? {
        let period = BudgetingPeriod(rawValue: defaultBudgetingPeriodRaw) ?? .monthly
        let currentRange = periodRange(containing: now, period: period)
        return previousRange(before: currentRange.start, period: period)?.end
    }

    // MARK: - Ledger CRUD

    static func addManualAdjustment(
        workspace: Workspace,
        account: SavingsAccount,
        date: Date,
        amount: Double,
        note: String,
        modelContext: ModelContext
    ) {
        let entry = SavingsLedgerEntry(
            date: date,
            amount: amount,
            note: note,
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
            workspace: workspace,
            account: account
        )
        modelContext.insert(entry)
        recalculateAccountTotal(account)
        try? modelContext.save()
    }

    static func upsertStandaloneReconciliationSettlement(
        workspace: Workspace,
        settlement: AllocationSettlement,
        modelContext: ModelContext
    ) {
        guard settlement.expense == nil, settlement.plannedExpense == nil else { return }
        removeStandaloneReconciliationSettlement(
            for: settlement,
            workspace: workspace,
            modelContext: modelContext
        )
    }

    static func removeStandaloneReconciliationSettlement(
        for settlement: AllocationSettlement,
        workspace: Workspace,
        modelContext: ModelContext
    ) {
        guard settlement.expense == nil, settlement.plannedExpense == nil else { return }
        guard let entry = standaloneReconciliationEntry(
            linkedTo: settlement.id,
            workspace: workspace,
            modelContext: modelContext
        ) else { return }

        let account = entry.account
        let accountID = account?.id
        modelContext.delete(entry)
        if let accountID {
            recalculateAccountTotal(accountID: accountID, modelContext: modelContext)
        }
    }

    @discardableResult
    static func upsertSavingsOffset(
        workspace: Workspace,
        variableExpense: VariableExpense,
        offsetAmount: Double,
        note: String,
        date: Date,
        modelContext: ModelContext
    ) -> Bool {
        guard offsetAmount > 0 else {
            removeSavingsOffset(for: variableExpense, modelContext: modelContext)
            return true
        }

        let account = ensureSavingsAccount(for: workspace, modelContext: modelContext)
        guard CurrencyFormatter.isLessThanOrEqualCurrency(
            offsetAmount,
            SavingsMathService.ownedAmount(for: variableExpense)
        ) else { return false }

        if let existing = variableExpense.savingsLedgerEntry {
            existing.date = date
            existing.amount = -offsetAmount
            existing.note = note
            existing.kind = .expenseOffset
            existing.workspace = workspace
            existing.account = account
            existing.variableExpense = variableExpense
            existing.plannedExpense = nil
            existing.updatedAt = .now
        } else {
            let entry = SavingsLedgerEntry(
                date: date,
                amount: -offsetAmount,
                note: note,
                kindRaw: SavingsLedgerEntryKind.expenseOffset.rawValue,
                workspace: workspace,
                account: account,
                variableExpense: variableExpense
            )
            modelContext.insert(entry)
            variableExpense.savingsLedgerEntry = entry
        }

        recalculateAccountTotal(account)
        try? modelContext.save()
        return true
    }

    @discardableResult
    static func upsertSavingsOffset(
        workspace: Workspace,
        plannedExpense: PlannedExpense,
        offsetAmount: Double,
        note: String,
        date: Date,
        modelContext: ModelContext
    ) -> Bool {
        guard offsetAmount > 0 else {
            removeSavingsOffset(for: plannedExpense, modelContext: modelContext)
            return true
        }

        let account = ensureSavingsAccount(for: workspace, modelContext: modelContext)
        guard CurrencyFormatter.isLessThanOrEqualCurrency(
            offsetAmount,
            SavingsMathService.ownedEffectiveAmount(for: plannedExpense)
        ) else { return false }

        if let existing = plannedExpense.savingsLedgerEntry {
            existing.date = date
            existing.amount = -offsetAmount
            existing.note = note
            existing.kind = .expenseOffset
            existing.workspace = workspace
            existing.account = account
            existing.variableExpense = nil
            existing.plannedExpense = plannedExpense
            existing.updatedAt = .now
        } else {
            let entry = SavingsLedgerEntry(
                date: date,
                amount: -offsetAmount,
                note: note,
                kindRaw: SavingsLedgerEntryKind.expenseOffset.rawValue,
                workspace: workspace,
                account: account,
                plannedExpense: plannedExpense
            )
            modelContext.insert(entry)
            plannedExpense.savingsLedgerEntry = entry
        }

        recalculateAccountTotal(account)
        try? modelContext.save()
        return true
    }

    static func removeSavingsOffset(
        for variableExpense: VariableExpense,
        modelContext: ModelContext
    ) {
        guard let entry = variableExpense.savingsLedgerEntry else { return }
        let account = entry.account
        variableExpense.savingsLedgerEntry = nil
        modelContext.delete(entry)
        if let account {
            recalculateAccountTotal(account)
        }
        try? modelContext.save()
    }

    static func removeSavingsOffset(
        for plannedExpense: PlannedExpense,
        modelContext: ModelContext
    ) {
        guard let entry = plannedExpense.savingsLedgerEntry else { return }
        let account = entry.account
        plannedExpense.savingsLedgerEntry = nil
        modelContext.delete(entry)
        if let account {
            recalculateAccountTotal(account)
        }
        try? modelContext.save()
    }

    static func recalculateAccountTotal(_ account: SavingsAccount) {
        let entries = (account.entries ?? []).sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.date < rhs.date
        }

        let total = entries.reduce(0) { partial, entry in
            partial + entry.amount
        }

        account.total = total
        account.updatedAt = .now
    }

    static func deleteEntry(
        _ entry: SavingsLedgerEntry,
        modelContext: ModelContext
    ) {
        let deletedKind = entry.kind
        let deletedDateText = AppDateFormat.abbreviatedDate(entry.date)
        let deletedPeriodStart = entry.periodStartDate.map { AppDateFormat.abbreviatedDate($0) } ?? "n/a"
        let deletedPeriodEnd = entry.periodEndDate.map { AppDateFormat.abbreviatedDate($0) } ?? "n/a"

        if let variableExpense = entry.variableExpense {
            variableExpense.savingsLedgerEntry = nil
        }

        if let plannedExpense = entry.plannedExpense {
            plannedExpense.savingsLedgerEntry = nil
        }

        let account = entry.account
        let accountID = account?.id
        let workspace = entry.workspace
        modelContext.delete(entry)

        if let accountID {
            recalculateAccountTotal(accountID: accountID, modelContext: modelContext)
        } else if let workspace {
            let accounts = workspaceSavingsAccounts(for: workspace, modelContext: modelContext)
            for account in accounts {
                recalculateAccountTotal(accountID: account.id, modelContext: modelContext)
            }
        }

        trace(
            "Deleted entry kind=\(deletedKind.rawValue) date=\(deletedDateText) " +
            "periodStart=\(deletedPeriodStart) periodEnd=\(deletedPeriodEnd)"
        )
        try? modelContext.save()
    }

    // MARK: - Internals

    private static func backfillHistory(
        workspace: Workspace,
        account: SavingsAccount,
        period: BudgetingPeriod,
        through latestClosedPeriodEnd: Date,
        incomes: [Income],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        modelContext: ModelContext
    ) {
        let activityDates: [Date] =
            incomes.map(\.date) +
            plannedExpenses.map(\.expenseDate) +
            variableExpenses.map(\.transactionDate)

        guard let firstActivity = activityDates.min() else {
            trace("Backfill skipped: no activity dates.")
            return
        }

        var cursor = periodRange(containing: firstActivity, period: period)
        let latest = periodRange(containing: latestClosedPeriodEnd, period: period)

        trace(
            "Backfill range firstActivity=\(AppDateFormat.abbreviatedDate(firstActivity)) " +
            "latestClosedEnd=\(AppDateFormat.abbreviatedDate(latest.end))"
        )

        while cursor.start <= latest.start {
            refreshOrInsertPeriodClose(
                workspace: workspace,
                workspaceID: workspace.id,
                account: account,
                range: cursor,
                incomes: incomes,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                modelContext: modelContext,
                isBackfill: true
            )

            guard let next = nextRange(after: cursor, period: period) else { break }
            cursor = next
        }

        recalculateAccountTotal(account)
    }

    private static func mergeAccountState(
        from source: SavingsAccount,
        into destination: SavingsAccount
    ) {
        if source.didBackfillHistory {
            destination.didBackfillHistory = true
        }

        guard let sourceThroughDate = source.autoCaptureThroughDate else {
            return
        }

        if let destinationThroughDate = destination.autoCaptureThroughDate {
            if sourceThroughDate > destinationThroughDate {
                destination.autoCaptureThroughDate = sourceThroughDate
            }
        } else {
            destination.autoCaptureThroughDate = sourceThroughDate
        }
    }

    private static func workspaceSavingsEntries(
        for workspace: Workspace,
        modelContext: ModelContext
    ) -> [SavingsLedgerEntry] {
        let workspaceID = workspace.id
        let descriptor = FetchDescriptor<SavingsLedgerEntry>(
            predicate: #Predicate<SavingsLedgerEntry> { entry in
                entry.workspace?.id == workspaceID
            },
            sortBy: [
                SortDescriptor(\SavingsLedgerEntry.date, order: .forward),
                SortDescriptor(\SavingsLedgerEntry.createdAt, order: .forward)
            ]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private struct DuplicateRepairReport {
        var periodCloseDeletedCount: Int = 0
        var manualDeletedCount: Int = 0

        var didMutate: Bool {
            periodCloseDeletedCount > 0 || manualDeletedCount > 0
        }
    }

    private struct PeriodCloseDeduplicationKey: Hashable {
        let periodStart: Date
        let periodEnd: Date
    }

    private struct ManualDeduplicationKey: Hashable {
        let accountID: UUID?
        let day: Date
        let roundedAmount: Double
        let normalizedNote: String
    }

    private static func repairDuplicateEntries(
        for workspace: Workspace,
        preferredAccount: SavingsAccount,
        modelContext: ModelContext
    ) -> DuplicateRepairReport {
        var report = DuplicateRepairReport()
        var entries = workspaceSavingsEntries(for: workspace, modelContext: modelContext)
        if entries.isEmpty { return report }

        entries.sort { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.createdAt < rhs.createdAt
        }

        var firstPeriodCloseByKey: [PeriodCloseDeduplicationKey: SavingsLedgerEntry] = [:]
        for entry in entries {
            guard entry.kind == .periodClose else { continue }
            guard
                let periodStartDate = entry.periodStartDate,
                let periodEndDate = entry.periodEndDate
            else {
                continue
            }
            let key = PeriodCloseDeduplicationKey(
                periodStart: Calendar.current.startOfDay(for: periodStartDate),
                periodEnd: Calendar.current.startOfDay(for: periodEndDate)
            )
            if firstPeriodCloseByKey[key] == nil {
                firstPeriodCloseByKey[key] = entry
                continue
            }
            modelContext.delete(entry)
            report.periodCloseDeletedCount += 1
        }

        entries = entries.filter { $0.kind == .manualAdjustment }
        var firstManualByKey: [ManualDeduplicationKey: SavingsLedgerEntry] = [:]
        for entry in entries {
            let key = ManualDeduplicationKey(
                accountID: entry.account?.id,
                day: Calendar.current.startOfDay(for: entry.date),
                roundedAmount: CurrencyFormatter.roundedToCurrency(entry.amount),
                normalizedNote: normalizeManualNoteForDeduplication(entry.note)
            )
            if firstManualByKey[key] == nil {
                firstManualByKey[key] = entry
                continue
            }
            modelContext.delete(entry)
            report.manualDeletedCount += 1
        }

        if report.didMutate {
            recalculateAccountTotal(accountID: preferredAccount.id, modelContext: modelContext)
            trace(
                "Duplicate repair removed periodClose=\(report.periodCloseDeletedCount) " +
                "manual=\(report.manualDeletedCount)"
            )
        }
        return report
    }

    private static func normalizeManualNoteForDeduplication(_ note: String) -> String {
        note
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    @discardableResult
    private static func removeMirroredReconciliationSettlements(
        for workspace: Workspace,
        preferredAccount: SavingsAccount,
        modelContext: ModelContext
    ) -> Int {
        let workspaceID = workspace.id
        let entryDescriptor = FetchDescriptor<SavingsLedgerEntry>(
            predicate: #Predicate<SavingsLedgerEntry> { entry in
                entry.workspace?.id == workspaceID
            }
        )
        let mirroredEntries = ((try? modelContext.fetch(entryDescriptor)) ?? []).filter {
            $0.kind == .reconciliationSettlement
        }

        guard mirroredEntries.isEmpty == false else { return 0 }

        for entry in mirroredEntries {
            modelContext.delete(entry)
        }

        recalculateAccountTotal(accountID: preferredAccount.id, modelContext: modelContext)
        return mirroredEntries.count
    }

    private static func standaloneReconciliationEntry(
        linkedTo settlementID: UUID,
        workspace: Workspace,
        modelContext: ModelContext
    ) -> SavingsLedgerEntry? {
        let workspaceID = workspace.id
        let descriptor = FetchDescriptor<SavingsLedgerEntry>(
            predicate: #Predicate<SavingsLedgerEntry> { entry in
                entry.workspace?.id == workspaceID
            }
        )
        let entries = (try? modelContext.fetch(descriptor)) ?? []
        return entries.first { entry in
            entry.linkedAllocationSettlementID == settlementID
        }
    }

    private static func periodCloseEntry(
        workspaceID: UUID,
        start: Date,
        end: Date,
        modelContext: ModelContext
    ) -> SavingsLedgerEntry? {
        let periodCloseRaw = SavingsLedgerEntryKind.periodClose.rawValue
        let descriptor = FetchDescriptor<SavingsLedgerEntry>(
            predicate: #Predicate<SavingsLedgerEntry> { entry in
                entry.workspace?.id == workspaceID &&
                entry.kindRaw == periodCloseRaw
            }
        )
        let entries = (try? modelContext.fetch(descriptor)) ?? []
        return entries.first { entry in
            Calendar.current.isDate(entry.periodStartDate ?? .distantPast, inSameDayAs: start)
            && Calendar.current.isDate(entry.periodEndDate ?? .distantPast, inSameDayAs: end)
        }
    }

    private static func refreshOrInsertPeriodClose(
        workspace: Workspace,
        workspaceID: UUID,
        account: SavingsAccount,
        range: (start: Date, end: Date),
        incomes: [Income],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        modelContext: ModelContext,
        allowInsert: Bool = true,
        isBackfill: Bool = false
    ) {
        let delta = periodDelta(
            in: range,
            incomes: incomes,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses
        )
        let note = periodCloseNote(start: range.start, end: range.end)

        if let entry = periodCloseEntry(
            workspaceID: workspaceID,
            start: range.start,
            end: range.end,
            modelContext: modelContext
        ) {
            let didChange = entry.date != range.end
                || entry.amount != delta
                || entry.note != note
                || entry.account?.id != account.id
                || entry.workspace?.id != workspace.id
                || !Calendar.current.isDate(entry.periodStartDate ?? .distantPast, inSameDayAs: range.start)
                || !Calendar.current.isDate(entry.periodEndDate ?? .distantPast, inSameDayAs: range.end)

            entry.date = range.end
            entry.amount = delta
            entry.note = note
            entry.kind = .periodClose
            entry.periodStartDate = range.start
            entry.periodEndDate = range.end
            entry.workspace = workspace
            entry.account = account

            if didChange {
                entry.updatedAt = .now
                trace(
                    "Refreshed period-close start=\(AppDateFormat.abbreviatedDate(range.start)) " +
                    "end=\(AppDateFormat.abbreviatedDate(range.end)) amount=\(delta)"
                )
            } else {
                trace(
                    "Period-close unchanged start=\(AppDateFormat.abbreviatedDate(range.start)) " +
                    "end=\(AppDateFormat.abbreviatedDate(range.end))"
                )
            }
            return
        }

        guard allowInsert else {
            trace(
                "Skipped missing period-close start=\(AppDateFormat.abbreviatedDate(range.start)) " +
                "end=\(AppDateFormat.abbreviatedDate(range.end))"
            )
            return
        }

        let entry = SavingsLedgerEntry(
            date: range.end,
            amount: delta,
            note: note,
            kindRaw: SavingsLedgerEntryKind.periodClose.rawValue,
            periodStartDate: range.start,
            periodEndDate: range.end,
            workspace: workspace,
            account: account
        )
        modelContext.insert(entry)
        trace(
            "\(isBackfill ? "Backfill inserted" : "Inserted") period-close start=\(AppDateFormat.abbreviatedDate(range.start)) " +
            "end=\(AppDateFormat.abbreviatedDate(range.end)) amount=\(delta)"
        )
    }

    private static func periodDelta(
        in range: (start: Date, end: Date),
        incomes: [Income],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense]
    ) -> Double {
        let actualIncome = incomes
            .filter { !$0.isPlanned }
            .filter { isInRange($0.date, start: range.start, end: range.end) }
            .reduce(0) { $0 + $1.amount }

        let plannedImpact = plannedExpenses
            .filter { isInRange($0.expenseDate, start: range.start, end: range.end) }
            .reduce(0) { $0 + SavingsMathService.plannedBudgetImpactAmount(for: $1) }

        let variableImpact = variableExpenses
            .filter { isInRange($0.transactionDate, start: range.start, end: range.end) }
            .reduce(0) { $0 + SavingsMathService.variableBudgetImpactAmount(for: $1) }

        return actualIncome - (plannedImpact + variableImpact)
    }

    private static func isInRange(_ date: Date, start: Date, end: Date) -> Bool {
        date >= start && date <= end
    }

    private static func recalculateAccountTotal(
        accountID: UUID,
        modelContext: ModelContext
    ) {
        let accountDescriptor = FetchDescriptor<SavingsAccount>(
            predicate: #Predicate<SavingsAccount> { $0.id == accountID }
        )
        guard let account = try? modelContext.fetch(accountDescriptor).first else { return }

        let entryDescriptor = FetchDescriptor<SavingsLedgerEntry>(
            predicate: #Predicate<SavingsLedgerEntry> { $0.account?.id == accountID },
            sortBy: [
                SortDescriptor(\SavingsLedgerEntry.date, order: .forward),
                SortDescriptor(\SavingsLedgerEntry.createdAt, order: .forward)
            ]
        )
        let entries = (try? modelContext.fetch(entryDescriptor)) ?? []
        account.total = entries.reduce(0) { $0 + $1.amount }
        account.updatedAt = .now
    }

    private static func periodCloseNote(start: Date, end: Date) -> String {
        "Period close \(AppDateFormat.abbreviatedDate(start)) - \(AppDateFormat.abbreviatedDate(end))"
    }

    private static func periodRange(containing date: Date, period: BudgetingPeriod) -> (start: Date, end: Date) {
        let range = period.defaultRange(containing: date, calendar: .current)
        let start = Calendar.current.startOfDay(for: range.start)
        let endStart = Calendar.current.startOfDay(for: range.end)
        let end = Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: endStart) ?? range.end
        return (start: start, end: end)
    }

    private static func nextRange(
        after current: (start: Date, end: Date),
        period: BudgetingPeriod
    ) -> (start: Date, end: Date)? {
        let nextDate: Date?
        switch period {
        case .daily:
            nextDate = Calendar.current.date(byAdding: .day, value: 1, to: current.start)
        case .weekly:
            nextDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: current.start)
        case .monthly:
            nextDate = Calendar.current.date(byAdding: .month, value: 1, to: current.start)
        case .quarterly:
            nextDate = Calendar.current.date(byAdding: .month, value: 3, to: current.start)
        case .yearly:
            nextDate = Calendar.current.date(byAdding: .year, value: 1, to: current.start)
        }

        guard let nextDate else { return nil }
        return periodRange(containing: nextDate, period: period)
    }

    private static func previousRange(before date: Date, period: BudgetingPeriod) -> (start: Date, end: Date)? {
        let previousDate: Date?
        switch period {
        case .daily:
            previousDate = Calendar.current.date(byAdding: .day, value: -1, to: date)
        case .weekly:
            previousDate = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: date)
        case .monthly:
            previousDate = Calendar.current.date(byAdding: .month, value: -1, to: date)
        case .quarterly:
            previousDate = Calendar.current.date(byAdding: .month, value: -3, to: date)
        case .yearly:
            previousDate = Calendar.current.date(byAdding: .year, value: -1, to: date)
        }

        guard let previousDate else { return nil }
        return periodRange(containing: previousDate, period: period)
    }

    private static func shouldInsertPeriodClose(
        _ range: (start: Date, end: Date),
        insertStartRange: (start: Date, end: Date)?,
        incomes: [Income],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense]
    ) -> Bool {
        if let insertStartRange, range.start >= insertStartRange.start {
            return true
        }

        return periodHasActivity(
            in: range,
            incomes: incomes,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses
        )
    }

    private static func periodHasActivity(
        in range: (start: Date, end: Date),
        incomes: [Income],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense]
    ) -> Bool {
        incomes.contains { !$0.isPlanned && isInRange($0.date, start: range.start, end: range.end) }
            || plannedExpenses.contains { isInRange($0.expenseDate, start: range.start, end: range.end) }
            || variableExpenses.contains { isInRange($0.transactionDate, start: range.start, end: range.end) }
    }
}
