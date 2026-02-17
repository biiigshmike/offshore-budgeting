import Foundation
import SwiftData

@MainActor
enum SavingsAccountService {

    // MARK: - Account

    static func ensureSavingsAccount(
        for workspace: Workspace,
        modelContext: ModelContext
    ) -> SavingsAccount {
        if let existing = workspaceSavingsAccounts(for: workspace, modelContext: modelContext).first {
            return existing
        }

        let account = SavingsAccount(workspace: workspace)
        modelContext.insert(account)
        return account
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

        let currentRange = periodRange(containing: now, period: period)
        guard let latestClosedRange = previousRange(before: currentRange.start, period: period) else {
            return
        }

        if !account.didBackfillHistory {
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

        let captureStartDate = account.autoCaptureThroughDate ?? latestClosedRange.start
        var cursor = periodRange(containing: captureStartDate, period: period)

        while cursor.start <= latestClosedRange.start {
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
            }

            guard let next = nextRange(after: cursor, period: period) else { break }
            cursor = next
        }

        account.autoCaptureThroughDate = latestClosedRange.end
        recalculateAccountTotal(account)
        account.updatedAt = .now
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

        guard let firstActivity = activityDates.min() else { return }

        var cursor = periodRange(containing: firstActivity, period: period)
        let latest = periodRange(containing: latestClosedPeriodEnd, period: period)

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
            }

            guard let next = nextRange(after: cursor, period: period) else { break }
            cursor = next
        }

        recalculateAccountTotal(account)
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
        return requested <= available && requested <= expenseAmount
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
