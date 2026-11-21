import CryptoKit
import Foundation
import SwiftData

@MainActor
enum SavingsPeriodReviewService {
    enum ReviewError: LocalizedError {
        case missingWorkspace, stalePreview, acknowledgementRequired, invalidAmount, overlap

        var errorDescription: String? {
            switch self {
            case .missingWorkspace: String(localized: "This workspace is no longer available.")
            case .stalePreview: String(localized: "Some details changed while you were here. Check the updated totals and try again.")
            case .acknowledgementRequired: String(localized: "Turn on Update Savings when you’re ready to save this period.")
            case .invalidAmount: String(localized: "Enter a valid amount.")
            case .overlap: String(localized: "Some of these dates are already included in Savings. Check the other period first so nothing gets counted twice.")
            }
        }
    }

    static func summaries(
        workspaceID: UUID,
        defaultBudgetingPeriodRaw: String,
        modelContext: ModelContext,
        now: Date = .now
    ) throws -> [SavingsPeriodReviewSummary] {
        let incomes = try modelContext.fetch(FetchDescriptor<Income>(
            predicate: #Predicate { $0.workspace?.id == workspaceID }
        ))
        let planned = try modelContext.fetch(FetchDescriptor<PlannedExpense>(
            predicate: #Predicate { $0.workspace?.id == workspaceID }
        ))
        let variable = try modelContext.fetch(FetchDescriptor<VariableExpense>(
            predicate: #Predicate { $0.workspace?.id == workspaceID }
        ))
        let budgets = try modelContext.fetch(FetchDescriptor<Budget>(
            predicate: #Predicate { $0.workspace?.id == workspaceID }
        ))
        let entries = try modelContext.fetch(FetchDescriptor<SavingsLedgerEntry>(
            predicate: #Predicate { $0.workspace?.id == workspaceID }
        )).filter { !$0.isDeleted }
        let closes = entries.filter { $0.kind == .periodClose }
        let total = entries.reduce(0) { $0 + $1.amount }
        let period = BudgetingPeriod(rawValue: defaultBudgetingPeriodRaw) ?? .monthly
        let currentRange = SavingsAccountService.periodRange(containing: now, period: period)

        // Store bounds as days in the key: older closes may have used start-of-day end dates.
        var ranges: [String: (start: Date, end: Date)] = [:]
        for entry in closes {
            guard let start = entry.periodStartDate, let end = entry.periodEndDate else { continue }
            let normalized = normalizedRange(start: start, end: end)
            if normalized.end < Calendar.current.startOfDay(for: now) {
                ranges[key(start: start, end: end)] = normalized
            }
        }
        let activityDates = incomes.filter { !$0.isPlanned }.map(\.date)
            + planned.map(\.expenseDate) + variable.map(\.transactionDate)
        for date in activityDates where date < currentRange.start {
            let range = SavingsAccountService.periodRange(containing: date, period: period)
            ranges[key(start: range.start, end: range.end)] = range
        }

        return ranges.values.sorted { $0.start < $1.start }.map { range in
            let id = key(start: range.start, end: range.end)
            let samePeriodEntries = closes.filter { entry in
                guard let start = entry.periodStartDate, let end = entry.periodEndDate else { return false }
                return key(start: start, end: end) == id
            }.sorted(by: SavingsAccountService.preferredPeriodClose)
            let existing = samePeriodEntries.first
            let postedAmount = samePeriodEntries.reduce(0) { $0 + $1.amount }
            let periodIncome = incomes.filter { $0.date >= range.start && $0.date <= range.end }
            let periodPlanned = planned.filter { $0.expenseDate >= range.start && $0.expenseDate <= range.end }
            let periodVariable = variable.filter { $0.transactionDate >= range.start && $0.transactionDate <= range.end }
            let periodBudgets = budgets.filter {
                Calendar.current.startOfDay(for: $0.startDate) <= range.end
                    && Calendar.current.startOfDay(for: $0.endDate) >= range.start
            }.sorted { $0.startDate < $1.startDate }
            let fingerprint = financialFingerprint(
                incomes: periodIncome, planned: periodPlanned, variable: periodVariable, budgets: periodBudgets
            )
            let overlap = closes.contains { entry in
                guard let start = entry.periodStartDate, let end = entry.periodEndDate,
                      key(start: start, end: end) != id else { return false }
                return Calendar.current.startOfDay(for: start) <= range.end
                    && Calendar.current.startOfDay(for: end) >= range.start
            }
            let token = digest([id, fingerprint, String(total), existing?.id.uuidString ?? "",
                                String(existing?.amount ?? 0), String(existing?.updatedAt.timeIntervalSince1970 ?? 0),
                                String(overlap)] + samePeriodEntries.map {
                                    "\($0.id.uuidString):\($0.amount):\($0.updatedAt.timeIntervalSince1970)"
                                })
            return SavingsPeriodReviewSummary(
                id: id, workspaceID: workspaceID, start: range.start, end: range.end, incomes: periodIncome,
                plannedExpenses: periodPlanned, variableExpenses: periodVariable, budgets: periodBudgets,
                calculatedAmount: SavingsAccountService.periodDelta(
                    in: range, incomes: periodIncome, plannedExpenses: periodPlanned, variableExpenses: periodVariable
                ),
                currentTotal: total, postedAmount: postedAmount, existingEntry: existing, inputFingerprint: fingerprint,
                confirmationToken: token, hasOverlapConflict: overlap
            )
        }
    }

    static func confirm(
        _ summary: SavingsPeriodReviewSummary,
        workspaceID: UUID,
        defaultBudgetingPeriodRaw: String,
        correctedAmount: Double?,
        explanation: String,
        acknowledged: Bool,
        modelContext: ModelContext,
        now: Date = .now,
        persist: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        guard summary.workspaceID == workspaceID else { throw ReviewError.missingWorkspace }
        guard acknowledged else { throw ReviewError.acknowledgementRequired }
        guard correctedAmount?.isFinite != false else { throw ReviewError.invalidAmount }
        let reason = explanation.trimmingCharacters(in: .whitespacesAndNewlines)

        // Isolate the write so a failed save cannot leave an unposted approval in the UI context,
        // or roll back unrelated edits. Re-fetch persisted inputs rather than trusting UI models.
        let writeContext = ModelContext(modelContext.container)
        writeContext.autosaveEnabled = false
        guard let workspace = try writeContext.fetch(FetchDescriptor<Workspace>(
            predicate: #Predicate { $0.id == workspaceID }
        )).first else { throw ReviewError.missingWorkspace }
        let previews = try summaries(
            workspaceID: workspaceID, defaultBudgetingPeriodRaw: defaultBudgetingPeriodRaw,
            modelContext: writeContext, now: now
        )
        guard let fresh = previews.first(where: { $0.id == summary.id }),
              fresh.confirmationToken == summary.confirmationToken else { throw ReviewError.stalePreview }
        guard !fresh.hasOverlapConflict else { throw ReviewError.overlap }
        guard fresh.calculatedAmount.isFinite else { throw ReviewError.invalidAmount }
        let postingAmount = CurrencyFormatter.roundedToCurrency(correctedAmount ?? fresh.calculatedAmount)
        let projectedTotal = fresh.currentTotal - fresh.postedAmount + postingAmount
        guard postingAmount.isFinite, projectedTotal.isFinite else { throw ReviewError.invalidAmount }

        let account = SavingsAccountService.ensureSavingsAccount(for: workspace, modelContext: writeContext)
        let entry = fresh.existingEntry ?? SavingsLedgerEntry(
            date: fresh.end, amount: 0, note: SavingsAccountService.periodCloseNote(start: fresh.start, end: fresh.end),
            kindRaw: SavingsLedgerEntryKind.periodClose.rawValue,
            periodStartDate: fresh.start, periodEndDate: fresh.end, workspace: workspace, account: account
        )
        if fresh.existingEntry == nil { writeContext.insert(entry) }
        entry.account = account
        entry.amount = postingAmount
        entry.reviewedAt = now
        entry.reviewedCalculatedAmount = fresh.calculatedAmount
        entry.reviewedInputFingerprint = fresh.inputFingerprint
        entry.correctedCloseAmount = correctedAmount.map { CurrencyFormatter.roundedToCurrency($0) }
        let note = correctedAmount != nil && !reason.isEmpty ? reason : nil
        entry.correctionExplanation = note
        entry.note = note ?? SavingsAccountService.periodCloseNote(start: fresh.start, end: fresh.end)
        entry.updatedAt = now
        // Fold duplicate same-period rows into the confirmed close without altering other history.
        let entries = try writeContext.fetch(FetchDescriptor<SavingsLedgerEntry>(
            predicate: #Predicate { $0.workspace?.id == workspaceID }
        ))
        for other in entries where other.kind == .periodClose && other.id != entry.id {
            if let start = other.periodStartDate, let end = other.periodEndDate,
               key(start: start, end: end) == fresh.id { writeContext.delete(other) }
        }
        // The app has one primary Savings account per workspace. Cloud sync can temporarily
        // leave duplicate accounts or orphaned relationships; retain every ledger amount while
        // bringing ownership into agreement with the workspace-wide preview in this same save.
        for other in entries where !other.isDeleted { other.account = account }
        for secondary in SavingsAccountService.workspaceSavingsAccounts(for: workspace, modelContext: writeContext)
            where secondary.id != account.id {
            SavingsAccountService.recalculateAccountTotal(secondary)
        }
        SavingsAccountService.recalculateAccountTotal(account)
        try persist(writeContext)
    }

    static func setRequiresReview(
        _ enabled: Bool, workspace: Workspace, modelContext: ModelContext, now: Date = .now
    ) throws {
        let account = SavingsAccountService.ensureSavingsAccount(for: workspace, modelContext: modelContext)
        let previous = account.requiresPeriodReview
        let previousBoundary = account.automaticPostingStartsAt
        if previous && !enabled { account.automaticPostingStartsAt = now }
        account.requiresPeriodReview = enabled
        do { try modelContext.save() }
        catch {
            account.requiresPeriodReview = previous
            account.automaticPostingStartsAt = previousBoundary
            throw error
        }
    }

    private static func normalizedRange(start: Date, end: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let endDay = calendar.startOfDay(for: end)
        return (calendar.startOfDay(for: start),
                calendar.date(byAdding: DateComponents(day: 1, second: -1), to: endDay) ?? end)
    }

    private static func key(start: Date, end: Date) -> String {
        "\(Calendar.current.startOfDay(for: start).timeIntervalSince1970):\(Calendar.current.startOfDay(for: end).timeIntervalSince1970)"
    }

    private static func digest(_ parts: [String]) -> String {
        // JSON preserves field boundaries even if a user-entered name contains delimiters.
        let data = (try? JSONEncoder().encode(parts)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func financialFingerprint(
        incomes: [Income], planned: [PlannedExpense], variable: [VariableExpense], budgets: [Budget]
    ) -> String {
        var rows: [String] = []
        for income in incomes {
            rows.append(digest(["income", income.id.uuidString, String(income.amount),
                                String(income.date.timeIntervalSince1970), String(income.isPlanned), income.source]))
        }
        for expense in planned {
            rows.append(digest(["planned", expense.id.uuidString, String(expense.plannedAmount),
                                String(expense.actualAmount), String(expense.expenseDate.timeIntervalSince1970),
                                expense.title, expense.card?.id.uuidString ?? "", expense.category?.id.uuidString ?? "",
                                expense.sourceBudgetID?.uuidString ?? "", expense.sourcePresetID?.uuidString ?? "",
                                String(expense.allocation?.allocatedAmount ?? 0),
                                String(expense.allocation?.preservesGrossAmount ?? true),
                                String(SavingsMathService.offsetAmount(for: expense))]))
        }
        for expense in variable {
            rows.append(digest(["variable", expense.id.uuidString, String(expense.amount), expense.kindRaw,
                                String(expense.transactionDate.timeIntervalSince1970), expense.descriptionText,
                                expense.card?.id.uuidString ?? "", expense.category?.id.uuidString ?? "",
                                String(expense.allocation?.allocatedAmount ?? 0),
                                String(expense.allocation?.preservesGrossAmount ?? true),
                                String(SavingsMathService.offsetAmount(for: expense))]))
        }
        for budget in budgets {
            rows.append(digest(["budget", budget.id.uuidString, budget.name,
                                String(budget.startDate.timeIntervalSince1970), String(budget.endDate.timeIntervalSince1970)]))
        }
        return digest(rows.sorted())
    }
}
