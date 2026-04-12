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

    enum ManualSavingsSyncReason: String {
        case upToDate
        case closedPeriodsNeedRefresh
        case runningTotalNeedsRebuild
        case savingsDataNeedsRepair
        case processingStateNeedsRefresh

        var message: String {
            switch self {
            case .upToDate:
                return "Savings Account is up to date."
            case .closedPeriodsNeedRefresh:
                return "Closed periods need to be refreshed."
            case .runningTotalNeedsRebuild:
                return "Running total needs to be rebuilt."
            case .savingsDataNeedsRepair:
                return "Savings data needs repair."
            case .processingStateNeedsRefresh:
                return "Savings sync state needs to be refreshed."
            }
        }
    }

    struct ManualSavingsSyncStatus {
        let isUpToDate: Bool
        let canSync: Bool
        let reason: ManualSavingsSyncReason
        let expectedChangeCount: Int
        let wouldChangeRunningTotal: Bool
        let currentTotal: Double
        let projectedTotal: Double
    }

    struct ManualSavingsSyncResult {
        let status: ManualSavingsSyncStatus
        let didApplyChanges: Bool
        let insertedPeriodCloseCount: Int
        let refreshedPeriodCloseCount: Int
        let repairedSavingsDataCount: Int
        let rebuiltRunningTotal: Bool
        let refreshedProcessingState: Bool

        var meaningfulChangeCount: Int {
            insertedPeriodCloseCount
                + refreshedPeriodCloseCount
                + repairedSavingsDataCount
                + (rebuiltRunningTotal ? 1 : 0)
                + (refreshedProcessingState ? 1 : 0)
        }
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

    static func manualSyncStatus(
        for workspace: Workspace,
        defaultBudgetingPeriodRaw: String,
        incomes: [Income],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        modelContext: ModelContext,
        now: Date = .now
    ) -> ManualSavingsSyncStatus {
        manualSyncEvaluation(
            for: workspace,
            defaultBudgetingPeriodRaw: defaultBudgetingPeriodRaw,
            incomes: incomes,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            modelContext: modelContext,
            now: now
        ).status
    }

    static func runManualSyncIfNeeded(
        for workspace: Workspace,
        defaultBudgetingPeriodRaw: String,
        incomes: [Income],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        modelContext: ModelContext,
        now: Date = .now
    ) -> ManualSavingsSyncResult {
        let evaluation = manualSyncEvaluation(
            for: workspace,
            defaultBudgetingPeriodRaw: defaultBudgetingPeriodRaw,
            incomes: incomes,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            modelContext: modelContext,
            now: now
        )

        guard evaluation.status.canSync else {
            trace("Manual savings sync skipped: already up to date.")
            return ManualSavingsSyncResult(
                status: evaluation.status,
                didApplyChanges: false,
                insertedPeriodCloseCount: 0,
                refreshedPeriodCloseCount: 0,
                repairedSavingsDataCount: 0,
                rebuiltRunningTotal: false,
                refreshedProcessingState: false
            )
        }

        let didNeedPrimaryAccount = evaluation.expectedPeriodCloseMutations.isEmpty == false
            || evaluation.normalizationPreview.didMutate
            || evaluation.shouldRebuildRunningTotal
            || evaluation.shouldRefreshProcessingState
        if didNeedPrimaryAccount {
            _ = ensureSavingsAccount(for: workspace, modelContext: modelContext)
        }

        var repairedSavingsDataCount = 0
        if evaluation.normalizationPreview.didMutate {
            let normalizationReport = normalizeSavingsData(for: workspace, modelContext: modelContext)
            repairedSavingsDataCount =
                normalizationReport.mergedAccountsCount +
                normalizationReport.reassignedEntriesCount +
                normalizationReport.dedupedPeriodCloseCount +
                normalizationReport.dedupedManualAdjustmentCount +
                normalizationReport.removedReconciliationSettlementCount
        }

        let refreshedAccount = ensureSavingsAccount(for: workspace, modelContext: modelContext)
        let period = BudgetingPeriod(rawValue: defaultBudgetingPeriodRaw) ?? .monthly
        let workspaceID = workspace.id

        var insertedPeriodCloseCount = 0
        var refreshedPeriodCloseCount = 0
        if let firstClosedRange = evaluation.firstClosedRange,
           let latestClosedRange = evaluation.latestClosedRange {
            var cursor: (start: Date, end: Date)? = firstClosedRange
            while let currentRange = cursor, currentRange.start <= latestClosedRange.start {
                let mutation = refreshOrInsertPeriodClose(
                    workspace: workspace,
                    workspaceID: workspaceID,
                    account: refreshedAccount,
                    range: currentRange,
                    incomes: incomes,
                    plannedExpenses: plannedExpenses,
                    variableExpenses: variableExpenses,
                    modelContext: modelContext,
                    allowInsert: periodHasActivity(
                        in: currentRange,
                        incomes: incomes,
                        plannedExpenses: plannedExpenses,
                        variableExpenses: variableExpenses
                    )
                )

                switch mutation {
                case .inserted:
                    insertedPeriodCloseCount += 1
                case .refreshed:
                    refreshedPeriodCloseCount += 1
                case .unchanged, .skipped:
                    break
                }

                guard let next = nextRange(after: currentRange, period: period) else { break }
                cursor = next
            }
        }

        let previousTotal = refreshedAccount.total
        recalculateAccountTotal(accountID: refreshedAccount.id, modelContext: modelContext)
        let rebuiltRunningTotal = !currencyEquals(previousTotal, refreshedAccount.total)

        var refreshedProcessingState = false
        if evaluation.shouldRefreshProcessingState, let latestClosedRange = evaluation.latestClosedRange {
            if refreshedAccount.didBackfillHistory == false {
                refreshedAccount.didBackfillHistory = true
                refreshedProcessingState = true
            }
            if !isSameDay(refreshedAccount.autoCaptureThroughDate, latestClosedRange.end) {
                refreshedAccount.autoCaptureThroughDate = latestClosedRange.end
                refreshedProcessingState = true
            }
        }

        let didApplyChanges = insertedPeriodCloseCount > 0
            || refreshedPeriodCloseCount > 0
            || repairedSavingsDataCount > 0
            || rebuiltRunningTotal
            || refreshedProcessingState

        if didApplyChanges {
            refreshedAccount.updatedAt = .now
            try? modelContext.save()
        }

        let finalStatus = manualSyncStatus(
            for: workspace,
            defaultBudgetingPeriodRaw: defaultBudgetingPeriodRaw,
            incomes: incomes,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            modelContext: modelContext,
            now: now
        )

        trace(
            "Manual savings sync applied inserted=\(insertedPeriodCloseCount) " +
            "refreshed=\(refreshedPeriodCloseCount) repaired=\(repairedSavingsDataCount) " +
            "rebuilt=\(rebuiltRunningTotal) state=\(refreshedProcessingState)"
        )

        return ManualSavingsSyncResult(
            status: finalStatus,
            didApplyChanges: didApplyChanges,
            insertedPeriodCloseCount: insertedPeriodCloseCount,
            refreshedPeriodCloseCount: refreshedPeriodCloseCount,
            repairedSavingsDataCount: repairedSavingsDataCount,
            rebuiltRunningTotal: rebuiltRunningTotal,
            refreshedProcessingState: refreshedProcessingState
        )
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

    private struct ManualSavingsSyncEvaluation {
        let status: ManualSavingsSyncStatus
        let normalizationPreview: SavingsNormalizationPreview
        let expectedPeriodCloseMutations: [ExpectedPeriodCloseMutation]
        let shouldRebuildRunningTotal: Bool
        let shouldRefreshProcessingState: Bool
        let firstClosedRange: (start: Date, end: Date)?
        let latestClosedRange: (start: Date, end: Date)?
    }

    private struct SavingsNormalizationPreview {
        let mergedAccountsCount: Int
        let reassignedEntriesCount: Int
        let dedupedPeriodCloseCount: Int
        let dedupedManualAdjustmentCount: Int
        let removedReconciliationSettlementCount: Int

        var totalRepairCount: Int {
            mergedAccountsCount
                + reassignedEntriesCount
                + dedupedPeriodCloseCount
                + dedupedManualAdjustmentCount
                + removedReconciliationSettlementCount
        }

        var didMutate: Bool {
            totalRepairCount > 0
        }
    }

    private enum ExpectedPeriodCloseMutationKind {
        case insert
        case refresh
    }

    private struct ExpectedPeriodCloseMutation {
        let range: (start: Date, end: Date)
        let amount: Double
        let kind: ExpectedPeriodCloseMutationKind
    }

    private static func manualSyncEvaluation(
        for workspace: Workspace,
        defaultBudgetingPeriodRaw: String,
        incomes: [Income],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        modelContext: ModelContext,
        now: Date
    ) -> ManualSavingsSyncEvaluation {
        let accounts = workspaceSavingsAccounts(for: workspace, modelContext: modelContext)
        let primaryAccount = accounts.first
        let workspaceEntries = workspaceSavingsEntries(for: workspace, modelContext: modelContext)
        let normalizationPreview = previewNormalization(
            accounts: accounts,
            workspaceEntries: workspaceEntries,
            primaryAccountID: primaryAccount?.id
        )

        let canonicalPeriodCloseEntries = canonicalPeriodCloseEntriesByKey(from: workspaceEntries)
        let canonicalManualAdjustments = canonicalManualAdjustmentsByKey(from: workspaceEntries)
        let canonicalKeys = Set(canonicalPeriodCloseEntries.keys)
        let keptEntries = workspaceEntries.filter { entry in
            if entry.kind == .reconciliationSettlement {
                return false
            }
            if entry.kind == .periodClose {
                guard
                    let key = periodCloseKey(for: entry),
                    canonicalKeys.contains(key)
                else {
                    return false
                }
            }
            if entry.kind == .manualAdjustment {
                let key = manualDeduplicationKey(for: entry)
                if canonicalManualAdjustments[key]?.id != entry.id {
                    return false
                }
            }
            return true
        }

        let period = BudgetingPeriod(rawValue: defaultBudgetingPeriodRaw) ?? .monthly
        let latestClosedRange = latestClosedPeriodRange(
            defaultBudgetingPeriodRaw: defaultBudgetingPeriodRaw,
            now: now
        )
        let firstActivityDate = firstSavingsActivityDate(
            incomes: incomes,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses
        )

        var expectedPeriodCloseMutations: [ExpectedPeriodCloseMutation] = []
        var expectedPeriodCloseAmounts: [PeriodCloseDeduplicationKey: Double] = [:]
        var hasClosedActivityPastProcessingState = false
        var firstClosedRange: (start: Date, end: Date)? = nil

        if let latestClosedRange, let firstActivityDate {
            let firstRange = periodRange(containing: firstActivityDate, period: period)
            firstClosedRange = firstRange.start <= latestClosedRange.start ? firstRange : nil

            var cursor = firstClosedRange
            while let currentRange = cursor, currentRange.start <= latestClosedRange.start {
                let key = PeriodCloseDeduplicationKey(
                    periodStart: Calendar.current.startOfDay(for: currentRange.start),
                    periodEnd: Calendar.current.startOfDay(for: currentRange.end)
                )
                let hasActivity = periodHasActivity(
                    in: currentRange,
                    incomes: incomes,
                    plannedExpenses: plannedExpenses,
                    variableExpenses: variableExpenses
                )
                if hasActivity, shouldTreatRangeAsUnprocessed(currentRange, account: primaryAccount) {
                    hasClosedActivityPastProcessingState = true
                }

                let expectedAmount = periodDelta(
                    in: currentRange,
                    incomes: incomes,
                    plannedExpenses: plannedExpenses,
                    variableExpenses: variableExpenses
                )
                let note = periodCloseNote(start: currentRange.start, end: currentRange.end)

                if let entry = canonicalPeriodCloseEntries[key] {
                    expectedPeriodCloseAmounts[key] = expectedAmount
                    if periodCloseNeedsRefresh(
                        entry,
                        range: currentRange,
                        expectedAmount: expectedAmount,
                        note: note,
                        workspaceID: workspace.id,
                        accountID: primaryAccount?.id
                    ) {
                        expectedPeriodCloseMutations.append(
                            ExpectedPeriodCloseMutation(
                                range: currentRange,
                                amount: expectedAmount,
                                kind: .refresh
                            )
                        )
                    }
                } else if hasActivity {
                    expectedPeriodCloseAmounts[key] = expectedAmount
                    expectedPeriodCloseMutations.append(
                        ExpectedPeriodCloseMutation(
                            range: currentRange,
                            amount: expectedAmount,
                            kind: .insert
                        )
                    )
                }

                guard let next = nextRange(after: currentRange, period: period) else { break }
                cursor = next
            }
        }

        let projectedTotal = projectedManualSyncTotal(
            workspaceEntries: keptEntries,
            canonicalPeriodCloseEntries: canonicalPeriodCloseEntries,
            expectedPeriodCloseAmounts: expectedPeriodCloseAmounts
        )
        let currentTotal = primaryAccount?.total ?? 0
        let shouldRebuildRunningTotal = !currencyEquals(currentTotal, projectedTotal)
        let shouldRefreshProcessingState = hasClosedActivityPastProcessingState

        let expectedChangeCount = normalizationPreview.totalRepairCount
            + expectedPeriodCloseMutations.count
            + (shouldRebuildRunningTotal ? 1 : 0)
            + (shouldRefreshProcessingState ? 1 : 0)

        let reason: ManualSavingsSyncReason
        if expectedChangeCount == 0 {
            reason = .upToDate
        } else if expectedPeriodCloseMutations.isEmpty == false {
            reason = .closedPeriodsNeedRefresh
        } else if normalizationPreview.didMutate {
            reason = .savingsDataNeedsRepair
        } else if shouldRebuildRunningTotal {
            reason = .runningTotalNeedsRebuild
        } else {
            reason = .processingStateNeedsRefresh
        }

        let status = ManualSavingsSyncStatus(
            isUpToDate: expectedChangeCount == 0,
            canSync: expectedChangeCount > 0,
            reason: reason,
            expectedChangeCount: expectedChangeCount,
            wouldChangeRunningTotal: !currencyEquals(currentTotal, projectedTotal),
            currentTotal: currentTotal,
            projectedTotal: projectedTotal
        )

        return ManualSavingsSyncEvaluation(
            status: status,
            normalizationPreview: normalizationPreview,
            expectedPeriodCloseMutations: expectedPeriodCloseMutations,
            shouldRebuildRunningTotal: shouldRebuildRunningTotal,
            shouldRefreshProcessingState: shouldRefreshProcessingState,
            firstClosedRange: firstClosedRange,
            latestClosedRange: latestClosedRange
        )
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
            _ = refreshOrInsertPeriodClose(
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
            _ = refreshOrInsertPeriodClose(
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

    private enum PeriodCloseRefreshMutation {
        case inserted
        case refreshed
        case unchanged
        case skipped
    }

    private static func previewNormalization(
        accounts: [SavingsAccount],
        workspaceEntries: [SavingsLedgerEntry],
        primaryAccountID: UUID?
    ) -> SavingsNormalizationPreview {
        let reassignedEntriesCount = workspaceEntries.reduce(into: 0) { partial, entry in
            if entry.account?.id != primaryAccountID {
                partial += 1
            }
        }

        let canonicalPeriodCloseEntries = canonicalPeriodCloseEntriesByKey(from: workspaceEntries)
        let dedupedPeriodCloseCount = workspaceEntries.reduce(into: 0) { partial, entry in
            guard entry.kind == .periodClose else { return }
            guard let key = periodCloseKey(for: entry) else { return }
            if canonicalPeriodCloseEntries[key]?.id != entry.id {
                partial += 1
            }
        }

        let canonicalManualAdjustments = canonicalManualAdjustmentsByKey(from: workspaceEntries)
        let dedupedManualAdjustmentCount = workspaceEntries.reduce(into: 0) { partial, entry in
            guard entry.kind == .manualAdjustment else { return }
            let key = manualDeduplicationKey(for: entry)
            if canonicalManualAdjustments[key]?.id != entry.id {
                partial += 1
            }
        }

        let removedReconciliationSettlementCount = workspaceEntries.reduce(into: 0) { partial, entry in
            if entry.kind == .reconciliationSettlement {
                partial += 1
            }
        }

        return SavingsNormalizationPreview(
            mergedAccountsCount: max(accounts.count - 1, 0),
            reassignedEntriesCount: primaryAccountID == nil ? 0 : reassignedEntriesCount,
            dedupedPeriodCloseCount: dedupedPeriodCloseCount,
            dedupedManualAdjustmentCount: dedupedManualAdjustmentCount,
            removedReconciliationSettlementCount: removedReconciliationSettlementCount
        )
    }

    private static func canonicalPeriodCloseEntriesByKey(
        from entries: [SavingsLedgerEntry]
    ) -> [PeriodCloseDeduplicationKey: SavingsLedgerEntry] {
        let sortedEntries = entries.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.createdAt < rhs.createdAt
        }

        var canonicalEntries: [PeriodCloseDeduplicationKey: SavingsLedgerEntry] = [:]
        for entry in sortedEntries {
            guard entry.kind == .periodClose, let key = periodCloseKey(for: entry) else { continue }
            if canonicalEntries[key] == nil {
                canonicalEntries[key] = entry
            }
        }
        return canonicalEntries
    }

    private static func canonicalManualAdjustmentsByKey(
        from entries: [SavingsLedgerEntry]
    ) -> [ManualDeduplicationKey: SavingsLedgerEntry] {
        let sortedEntries = entries.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.createdAt < rhs.createdAt
        }

        var canonicalEntries: [ManualDeduplicationKey: SavingsLedgerEntry] = [:]
        for entry in sortedEntries where entry.kind == .manualAdjustment {
            let key = manualDeduplicationKey(for: entry)
            if canonicalEntries[key] == nil {
                canonicalEntries[key] = entry
            }
        }
        return canonicalEntries
    }

    private static func periodCloseKey(
        for entry: SavingsLedgerEntry
    ) -> PeriodCloseDeduplicationKey? {
        guard
            let periodStartDate = entry.periodStartDate,
            let periodEndDate = entry.periodEndDate
        else {
            return nil
        }

        return PeriodCloseDeduplicationKey(
            periodStart: Calendar.current.startOfDay(for: periodStartDate),
            periodEnd: Calendar.current.startOfDay(for: periodEndDate)
        )
    }

    private static func manualDeduplicationKey(
        for entry: SavingsLedgerEntry
    ) -> ManualDeduplicationKey {
        ManualDeduplicationKey(
            accountID: entry.account?.id,
            day: Calendar.current.startOfDay(for: entry.date),
            roundedAmount: CurrencyFormatter.roundedToCurrency(entry.amount),
            normalizedNote: normalizeManualNoteForDeduplication(entry.note)
        )
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

    private static func firstSavingsActivityDate(
        incomes: [Income],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense]
    ) -> Date? {
        (
            incomes.filter { !$0.isPlanned }.map(\.date)
                + plannedExpenses.map(\.expenseDate)
                + variableExpenses.map(\.transactionDate)
        ).min()
    }

    private static func latestClosedPeriodRange(
        defaultBudgetingPeriodRaw: String,
        now: Date
    ) -> (start: Date, end: Date)? {
        guard let latestClosedPeriodEnd = latestClosedPeriodEnd(
            defaultBudgetingPeriodRaw: defaultBudgetingPeriodRaw,
            now: now
        ) else {
            return nil
        }

        let period = BudgetingPeriod(rawValue: defaultBudgetingPeriodRaw) ?? .monthly
        return periodRange(containing: latestClosedPeriodEnd, period: period)
    }

    private static func shouldTreatRangeAsUnprocessed(
        _ range: (start: Date, end: Date),
        account: SavingsAccount?
    ) -> Bool {
        guard let account else { return true }
        if account.didBackfillHistory == false {
            return true
        }
        guard let autoCaptureThroughDate = account.autoCaptureThroughDate else {
            return true
        }
        return autoCaptureThroughDate < range.end
    }

    private static func periodCloseNeedsRefresh(
        _ entry: SavingsLedgerEntry,
        range: (start: Date, end: Date),
        expectedAmount: Double,
        note: String,
        workspaceID: UUID,
        accountID: UUID?
    ) -> Bool {
        if !currencyEquals(entry.amount, expectedAmount) {
            return true
        }
        if entry.note != note {
            return true
        }
        if entry.workspace?.id != workspaceID {
            return true
        }
        if entry.account?.id != accountID {
            return true
        }
        if entry.date != range.end {
            return true
        }
        guard
            let periodStartDate = entry.periodStartDate,
            let periodEndDate = entry.periodEndDate
        else {
            return true
        }
        return !isSameDay(periodStartDate, range.start)
            || !isSameDay(periodEndDate, range.end)
    }

    private static func projectedManualSyncTotal(
        workspaceEntries: [SavingsLedgerEntry],
        canonicalPeriodCloseEntries: [PeriodCloseDeduplicationKey: SavingsLedgerEntry],
        expectedPeriodCloseAmounts: [PeriodCloseDeduplicationKey: Double]
    ) -> Double {
        let nonPeriodCloseTotal = workspaceEntries.reduce(into: 0.0) { partial, entry in
            if entry.kind != .periodClose {
                partial += entry.amount
            }
        }

        var retainedPeriodCloseTotal = 0.0
        for (key, entry) in canonicalPeriodCloseEntries {
            retainedPeriodCloseTotal += expectedPeriodCloseAmounts[key] ?? entry.amount
        }

        return CurrencyFormatter.roundedToCurrency(nonPeriodCloseTotal + retainedPeriodCloseTotal)
    }

    private static func currencyEquals(_ lhs: Double, _ rhs: Double) -> Bool {
        CurrencyFormatter.roundedToCurrency(lhs) == CurrencyFormatter.roundedToCurrency(rhs)
    }

    private static func isSameDay(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case let (.some(left), .some(right)):
            return Calendar.current.isDate(left, inSameDayAs: right)
        default:
            return false
        }
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
            },
            sortBy: [
                SortDescriptor(\SavingsLedgerEntry.createdAt, order: .forward),
                SortDescriptor(\SavingsLedgerEntry.id, order: .forward)
            ]
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
    ) -> PeriodCloseRefreshMutation {
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
                return .refreshed
            } else {
                trace(
                    "Period-close unchanged start=\(AppDateFormat.abbreviatedDate(range.start)) " +
                    "end=\(AppDateFormat.abbreviatedDate(range.end))"
                )
                return .unchanged
            }
        }

        guard allowInsert else {
            trace(
                "Skipped missing period-close start=\(AppDateFormat.abbreviatedDate(range.start)) " +
                "end=\(AppDateFormat.abbreviatedDate(range.end))"
            )
            return .skipped
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
        return .inserted
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
