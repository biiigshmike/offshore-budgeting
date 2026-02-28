import Foundation
import SwiftData

@MainActor
enum SavingsAccountService {

    // MARK: - Account

    struct SavingsNormalizationReport {
        let mergedAccountsCount: Int
        let reassignedEntriesCount: Int
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
            "reassignedEntries=\(reassignedEntriesCount) total=\(primaryAccount.total)"
        )

        return SavingsNormalizationReport(
            mergedAccountsCount: mergedAccountsCount,
            reassignedEntriesCount: reassignedEntriesCount,
            recalculatedTotal: primaryAccount.total
        )
    }

    @discardableResult
    static func rebuildRunningTotal(
        for workspace: Workspace,
        modelContext: ModelContext
    ) -> Double {
        let account = ensureSavingsAccount(for: workspace, modelContext: modelContext)
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

        trace(
            "Auto-capture start workspace=\(workspace.name) period=\(period.rawValue) " +
            "incomes=\(incomes.count) planned=\(plannedExpenses.count) variable=\(variableExpenses.count)"
        )

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

        var captureStartRange: (start: Date, end: Date)?
        if let autoCaptureThroughDate = account.autoCaptureThroughDate {
            let processedRange = periodRange(containing: autoCaptureThroughDate, period: period)
            let isRangeEnd = Calendar.current.isDate(autoCaptureThroughDate, inSameDayAs: processedRange.end)
            captureStartRange = isRangeEnd ? nextRange(after: processedRange, period: period) : processedRange
        } else {
            captureStartRange = latestClosedRange
        }

        if let captureStartRange {
            trace(
                "Capture window start=\(AppDateFormat.abbreviatedDate(captureStartRange.start)) " +
                "latestClosedEnd=\(AppDateFormat.abbreviatedDate(latestClosedRange.end))"
            )
        } else {
            trace(
                "Capture window is empty latestClosedEnd=\(AppDateFormat.abbreviatedDate(latestClosedRange.end))"
            )
        }

        var cursor = captureStartRange
        while let currentRange = cursor, currentRange.start <= latestClosedRange.start {
            if !periodCloseExists(account: account, start: currentRange.start, end: currentRange.end) {
                let delta = periodDelta(
                    in: currentRange,
                    incomes: incomes,
                    plannedExpenses: plannedExpenses,
                    variableExpenses: variableExpenses
                )
                let entry = SavingsLedgerEntry(
                    date: currentRange.end,
                    amount: delta,
                    note: periodCloseNote(start: currentRange.start, end: currentRange.end),
                    kindRaw: SavingsLedgerEntryKind.periodClose.rawValue,
                    periodStartDate: currentRange.start,
                    periodEndDate: currentRange.end,
                    workspace: workspace,
                    account: account
                )
                modelContext.insert(entry)
                trace(
                    "Inserted period-close start=\(AppDateFormat.abbreviatedDate(currentRange.start)) " +
                    "end=\(AppDateFormat.abbreviatedDate(currentRange.end)) amount=\(delta)"
                )
            } else {
                trace(
                    "Period-close already exists start=\(AppDateFormat.abbreviatedDate(currentRange.start)) " +
                    "end=\(AppDateFormat.abbreviatedDate(currentRange.end))"
                )
            }

            guard let next = nextRange(after: currentRange, period: period) else { break }
            cursor = next
        }

        account.autoCaptureThroughDate = latestClosedRange.end
        recalculateAccountTotal(account)
        account.updatedAt = .now
        trace("Auto-capture end runningTotal=\(account.total)")
        try? modelContext.save()
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
        let existingLinkedOffset = max(0, -(variableExpense.savingsLedgerEntry?.amount ?? 0))
        let available = availableBalance(for: account, existingLinkedOffset: existingLinkedOffset)
        let isValid = canApplyOffset(
            requested: offsetAmount,
            available: available,
            expenseAmount: max(0, variableExpense.amount)
        )
        guard isValid else { return false }

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
        let existingLinkedOffset = max(0, -(plannedExpense.savingsLedgerEntry?.amount ?? 0))
        let available = availableBalance(for: account, existingLinkedOffset: existingLinkedOffset)
        let isValid = canApplyOffset(
            requested: offsetAmount,
            available: available,
            expenseAmount: max(0, plannedExpense.effectiveAmount())
        )
        guard isValid else { return false }

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
            if !periodCloseExists(account: account, start: cursor.start, end: cursor.end) {
                let delta = periodDelta(
                    in: cursor,
                    incomes: incomes,
                    plannedExpenses: plannedExpenses,
                    variableExpenses: variableExpenses
                )
                let entry = SavingsLedgerEntry(
                    date: cursor.end,
                    amount: delta,
                    note: periodCloseNote(start: cursor.start, end: cursor.end),
                    kindRaw: SavingsLedgerEntryKind.periodClose.rawValue,
                    periodStartDate: cursor.start,
                    periodEndDate: cursor.end,
                    workspace: workspace,
                    account: account
                )
                modelContext.insert(entry)
                trace(
                    "Backfill inserted period-close start=\(AppDateFormat.abbreviatedDate(cursor.start)) " +
                    "end=\(AppDateFormat.abbreviatedDate(cursor.end)) amount=\(delta)"
                )
            }

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

    private static func periodCloseExists(account: SavingsAccount, start: Date, end: Date) -> Bool {
        (account.entries ?? []).contains { entry in
            entry.kind == .periodClose
            && Calendar.current.isDate(entry.periodStartDate ?? .distantPast, inSameDayAs: start)
            && Calendar.current.isDate(entry.periodEndDate ?? .distantPast, inSameDayAs: end)
        }
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

    private static func availableBalance(
        for account: SavingsAccount,
        existingLinkedOffset: Double
    ) -> Double {
        max(0, account.total + existingLinkedOffset)
    }

    private static func canApplyOffset(
        requested: Double,
        available: Double,
        expenseAmount: Double
    ) -> Bool {
        guard requested > 0 else { return false }
        guard available > 0 else { return false }
        return CurrencyFormatter.isLessThanOrEqualCurrency(requested, available)
            && CurrencyFormatter.isLessThanOrEqualCurrency(requested, expenseAmount)
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
}
