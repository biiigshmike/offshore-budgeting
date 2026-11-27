import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct SavingsPeriodReviewServiceTests {
    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let workspace: Workspace
        let card: Card
        let income: Income
        let planned: PlannedExpense
        let variable: VariableExpense
    }

    private func date(_ month: Int, _ day: Int = 1) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
    }

    private func fixture() throws -> Fixture {
        let schema = Schema([
            Workspace.self, Budget.self, BudgetCategoryLimit.self, Card.self,
            BudgetCardLink.self, BudgetPresetLink.self, Category.self, Preset.self,
            PlannedExpense.self, VariableExpense.self, AllocationAccount.self,
            ExpenseAllocation.self, AllocationSettlement.self, SavingsAccount.self,
            SavingsLedgerEntry.self, ImportMerchantRule.self, AssistantAliasRule.self,
            MarinaChatSession.self, IncomeSeries.self, Income.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let workspace = Workspace(name: "Personal", hexColor: "#336699")
        let card = Card(name: "Daily", workspace: workspace)
        let income = Income(source: "Salary", amount: 1000, date: date(1, 5), isPlanned: false, workspace: workspace, card: card)
        let planned = PlannedExpense(title: "Rent", plannedAmount: 200, expenseDate: date(1, 10), workspace: workspace, card: card)
        let variable = VariableExpense(descriptionText: "Food", amount: 100, transactionDate: date(1, 15), workspace: workspace, card: card)
        context.insert(workspace)
        context.insert(card)
        context.insert(income)
        context.insert(planned)
        context.insert(variable)
        try context.save()
        return Fixture(
            container: container, context: context, workspace: workspace,
            card: card, income: income, planned: planned, variable: variable
        )
    }

    private func summaries(_ fixture: Fixture, period: String = "monthly", now: Date? = nil) throws -> [SavingsPeriodReviewSummary] {
        try SavingsPeriodReviewService.summaries(
            workspaceID: fixture.workspace.id,
            defaultBudgetingPeriodRaw: period,
            modelContext: ModelContext(fixture.container),
            now: now ?? date(4, 10)
        )
    }

    private func january(_ fixture: Fixture) throws -> SavingsPeriodReviewSummary {
        try #require(summaries(fixture).first { Calendar.current.component(.month, from: $0.start) == 1 && Calendar.current.component(.month, from: $0.end) == 1 })
    }

    private func confirm(_ summary: SavingsPeriodReviewSummary, fixture: Fixture, corrected: Double? = nil, explanation: String = "", acknowledged: Bool = true) throws {
        try SavingsPeriodReviewService.confirm(
            summary,
            workspaceID: fixture.workspace.id,
            defaultBudgetingPeriodRaw: "monthly",
            correctedAmount: corrected,
            explanation: explanation,
            acknowledged: acknowledged,
            modelContext: fixture.context,
            now: date(4, 10)
        )
    }

    private func entries(_ fixture: Fixture) throws -> [SavingsLedgerEntry] {
        let context = ModelContext(fixture.container)
        return try context.fetch(FetchDescriptor<SavingsLedgerEntry>()).filter { $0.workspace?.id == fixture.workspace.id }
    }

    private func account(_ fixture: Fixture) throws -> SavingsAccount {
        let context = ModelContext(fixture.container)
        return try #require(context.fetch(FetchDescriptor<SavingsAccount>()).first { $0.workspace?.id == fixture.workspace.id })
    }

    @Test func defaultReviewBlocksAutomaticCaptureAndManualSync() throws {
        let fixture = try fixture()
        SavingsAccountService.runAutoCaptureIfNeeded(
            for: fixture.workspace, defaultBudgetingPeriodRaw: "monthly",
            incomes: [fixture.income], plannedExpenses: [fixture.planned], variableExpenses: [fixture.variable],
            modelContext: fixture.context, now: date(4, 10)
        )
        _ = SavingsAccountService.runManualSyncIfNeeded(
            for: fixture.workspace, defaultBudgetingPeriodRaw: "monthly",
            incomes: [fixture.income], plannedExpenses: [fixture.planned], variableExpenses: [fixture.variable],
            modelContext: fixture.context, now: date(4, 10)
        )
        try fixture.context.save()
        #expect(try entries(fixture).isEmpty)
        #expect(try account(fixture).requiresPeriodReview)
        #expect(try account(fixture).total == 0)
        #expect(try january(fixture).isPending)
    }

    @Test func reviewIncludesOnlyClosedWorkspaceActivityAndOverlappingBudgets() throws {
        let fixture = try fixture()
        let budget = Budget(name: "January", startDate: date(1), endDate: date(1, 31), workspace: fixture.workspace)
        let overlap = Budget(name: "Winter", startDate: date(1, 20), endDate: date(2, 20), workspace: fixture.workspace)
        let other = Workspace(name: "Work", hexColor: "#AAAAAA")
        fixture.context.insert(budget)
        fixture.context.insert(overlap)
        fixture.context.insert(other)
        fixture.context.insert(Income(source: "Other workspace", amount: 9000, date: date(1, 5), isPlanned: false, workspace: other))
        fixture.context.insert(Income(source: "Expected", amount: 5000, date: date(1, 5), isPlanned: true, workspace: fixture.workspace))
        fixture.context.insert(Income(source: "Current", amount: 5000, date: date(4, 5), isPlanned: false, workspace: fixture.workspace))
        try fixture.context.save()
        let january = try january(fixture)
        #expect(january.receivedIncome == 1000)
        #expect(january.plannedImpact == 200)
        #expect(january.variableImpact == 100)
        #expect(january.calculatedAmount == 700)
        #expect(Set(january.budgets.map(\.id)) == Set([budget.id, overlap.id]))
        #expect(try summaries(fixture).allSatisfy { $0.end < Calendar.current.startOfDay(for: date(4)) })
    }

    @Test func confirmationCreatesOneCloseAndRecalculatesSavings() throws {
        let fixture = try fixture()
        let pending = try january(fixture)
        try confirm(pending, fixture: fixture)
        let entry = try #require(entries(fixture).first)
        #expect(entry.kind == .periodClose)
        #expect(entry.amount == 700)
        #expect(entry.reviewedAt != nil)
        #expect(entry.reviewedCalculatedAmount == 700)
        #expect(entry.reviewedInputFingerprint == pending.inputFingerprint)
        #expect(try account(fixture).total == 700)
        #expect(try !january(fixture).isPending)
        #expect(try !january(fixture).needsReview)

        #expect(throws: (any Error).self) {
            try confirm(pending, fixture: fixture)
        }
        #expect(try entries(fixture).filter { $0.kind == .periodClose }.count == 1)
        #expect(try account(fixture).total == 700)
    }

    @Test(arguments: [0.0, -150.0, 850.0])
    func correctedCloseAllowsZeroNegativeAndPositiveAmounts(amount: Double) throws {
        let fixture = try fixture()
        try confirm(january(fixture), fixture: fixture, corrected: amount, explanation: "Reconciled to my records")
        let entry = try #require(entries(fixture).first)
        #expect(entry.amount == amount)
        #expect(entry.correctedCloseAmount == amount)
        #expect(entry.correctionExplanation == "Reconciled to my records")
        #expect(entry.reviewedCalculatedAmount == 700)
        #expect(try account(fixture).total == amount)
    }

    @Test func confirmationRequiresAcknowledgementAndValidAmount() throws {
        let fixture = try fixture()
        let pending = try january(fixture)
        #expect(throws: (any Error).self) {
            try confirm(pending, fixture: fixture, acknowledged: false)
        }
        #expect(throws: (any Error).self) {
            try confirm(pending, fixture: fixture, corrected: .nan, explanation: "Invalid amount")
        }
        #expect(try entries(fixture).isEmpty)
    }

    @Test(arguments: ["", " \n ", "  Starting fresh  "])
    func correctedCloseUsesOptionalNoteOrGeneratedPeriodText(note: String) throws {
        let fixture = try fixture()
        let review = try january(fixture)
        try confirm(review, fixture: fixture, corrected: 0, explanation: note)
        let entry = try #require(entries(fixture).first)
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(entry.correctedCloseAmount == 0)
        #expect(entry.amount == 0)
        #expect(entry.correctionExplanation == (trimmed.isEmpty ? nil : trimmed))
        #expect(entry.note == (trimmed.isEmpty
            ? SavingsAccountService.periodCloseNote(start: review.start, end: review.end)
            : trimmed))
    }

    @Test func changedInputsRejectStalePreviewWithoutPosting() throws {
        let fixture = try fixture()
        let pending = try january(fixture)
        fixture.variable.amount = 175
        try fixture.context.save()
        #expect(throws: (any Error).self) {
            try confirm(pending, fixture: fixture)
        }
        #expect(try entries(fixture).isEmpty)
        let refreshed = try january(fixture)
        #expect(refreshed.calculatedAmount == 625)
        try confirm(refreshed, fixture: fixture)
        #expect(try account(fixture).total == 625)
    }

    @Test func changingRecordedInputsRequiresReviewAndPreservesPostedAmount() throws {
        let fixture = try fixture()
        try confirm(january(fixture), fixture: fixture)
        fixture.planned.actualAmount = 250
        try fixture.context.save()
        let revised = try january(fixture)
        #expect(revised.needsReview)
        #expect(revised.postedAmount == 700)
        #expect(revised.calculatedAmount == 650)
        #expect(try account(fixture).total == 700)
        try confirm(revised, fixture: fixture)
        #expect(try entries(fixture).filter { $0.kind == .periodClose }.count == 1)
        #expect(try account(fixture).total == 650)
    }

    @Test func allocationAndOffsetChangesInvalidateReview() throws {
        let fixture = try fixture()
        let shared = AllocationAccount(name: "Shared", workspace: fixture.workspace)
        let allocation = ExpenseAllocation(allocatedAmount: 25, preservesGrossAmount: true, workspace: fixture.workspace, account: shared, expense: fixture.variable)
        fixture.variable.allocation = allocation
        fixture.context.insert(shared)
        fixture.context.insert(allocation)
        try fixture.context.save()
        #expect(try january(fixture).calculatedAmount == 725)
        try confirm(january(fixture), fixture: fixture)

        allocation.allocatedAmount = 40
        try fixture.context.save()
        let afterSplit = try january(fixture)
        #expect(afterSplit.needsReview)
        #expect(afterSplit.calculatedAmount == 740)
        try confirm(afterSplit, fixture: fixture)

        let savingsAccount = try account(fixture)
        let offset = SavingsLedgerEntry(date: date(1, 15), amount: -10, note: "Pay from Savings", kindRaw: SavingsLedgerEntryKind.expenseOffset.rawValue, workspace: fixture.workspace)
        offset.variableExpense = fixture.variable
        fixture.variable.savingsLedgerEntry = offset
        fixture.context.insert(offset)
        // Resolve the account in this write context instead of crossing ModelContexts.
        offset.account = try fixture.context.fetch(FetchDescriptor<SavingsAccount>()).first { $0.id == savingsAccount.id }
        try fixture.context.save()
        let afterOffset = try january(fixture)
        #expect(afterOffset.needsReview)
        #expect(afterOffset.calculatedAmount == 750)
        #expect(afterOffset.inputFingerprint != afterSplit.inputFingerprint)
    }

    @Test func closeMathRetainsCreditsAdjustmentsPlannedFallbackAndOwnedShare() throws {
        let fixture = try fixture()
        let shared = AllocationAccount(name: "Shared", workspace: fixture.workspace)
        let allocation = ExpenseAllocation(allocatedAmount: 25, preservesGrossAmount: true, workspace: fixture.workspace, account: shared, expense: fixture.variable)
        fixture.variable.allocation = allocation
        let offset = SavingsLedgerEntry(date: date(1, 15), amount: -10, note: "Offset", kindRaw: SavingsLedgerEntryKind.expenseOffset.rawValue, workspace: fixture.workspace)
        offset.variableExpense = fixture.variable
        fixture.variable.savingsLedgerEntry = offset
        fixture.context.insert(shared)
        fixture.context.insert(allocation)
        fixture.context.insert(offset)
        fixture.context.insert(VariableExpense(descriptionText: "Refund", amount: 40, kindRaw: VariableExpenseKind.credit.rawValue, transactionDate: date(1, 16), workspace: fixture.workspace, card: fixture.card))
        fixture.context.insert(VariableExpense(descriptionText: "Ledger adjustment", amount: 999, kindRaw: VariableExpenseKind.adjustment.rawValue, transactionDate: date(1, 17), workspace: fixture.workspace, card: fixture.card))
        try fixture.context.save()
        #expect(try january(fixture).calculatedAmount == 775)
    }

    @Test func confirmationCannotUseAnotherWorkspaceSummary() throws {
        let fixture = try fixture()
        let other = Workspace(name: "Work", hexColor: "#888888")
        fixture.context.insert(other)
        try fixture.context.save()
        let pending = try january(fixture)
        #expect(throws: (any Error).self) {
            try SavingsPeriodReviewService.confirm(pending, workspaceID: other.id, defaultBudgetingPeriodRaw: "monthly", correctedAmount: nil, explanation: "", acknowledged: true, modelContext: fixture.context, now: date(4, 10))
        }
        #expect(try fixture.context.fetch(FetchDescriptor<SavingsLedgerEntry>()).isEmpty)
    }

    @Test func legacyHistoryAndManualWriteOffRemainUnchanged() throws {
        let fixture = try fixture()
        let account = SavingsAccount(workspace: fixture.workspace)
        let start = Calendar.current.startOfDay(for: date(1))
        let end = Calendar.current.date(byAdding: .second, value: -1, to: Calendar.current.startOfDay(for: date(2)))!
        let legacy = SavingsLedgerEntry(date: end, amount: 900, note: "Original close", kindRaw: SavingsLedgerEntryKind.periodClose.rawValue, periodStartDate: start, periodEndDate: end, workspace: fixture.workspace, account: account)
        let writeOff = SavingsLedgerEntry(date: date(2, 2), amount: -900, note: "Write-off", kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue, workspace: fixture.workspace, account: account)
        fixture.context.insert(account)
        fixture.context.insert(legacy)
        fixture.context.insert(writeOff)
        account.total = 0
        try fixture.context.save()
        let history = try january(fixture)
        #expect(!history.isPending)
        #expect(!history.needsReview)
        #expect(history.postedAmount == 900)
        #expect(history.calculatedAmount == 700)
        #expect(try entries(fixture).map(\.amount).sorted() == [-900, 900])
        #expect(try self.account(fixture).total == 0)
    }

    @Test func disablingReviewAutomatesOnlyPeriodsEndingAfterSwitch() throws {
        let fixture = try fixture()
        let februaryIncome = Income(source: "February salary", amount: 1200, date: date(2, 5), isPlanned: false, workspace: fixture.workspace, card: fixture.card)
        fixture.context.insert(februaryIncome)
        try fixture.context.save()
        try SavingsPeriodReviewService.setRequiresReview(false, workspace: fixture.workspace, modelContext: fixture.context, now: date(2, 10))
        SavingsAccountService.runAutoCaptureIfNeeded(
            for: fixture.workspace, defaultBudgetingPeriodRaw: "monthly",
            incomes: [fixture.income, februaryIncome], plannedExpenses: [fixture.planned], variableExpenses: [fixture.variable],
            modelContext: fixture.context, now: date(3, 10)
        )
        try fixture.context.save()
        let closes = try entries(fixture).filter { $0.kind == .periodClose }
        #expect(closes.count == 1)
        #expect(closes.first?.amount == 1200)
        #expect(closes.first.map { Calendar.current.component(.month, from: $0.periodStartDate!) } == 2)
        #expect(try january(fixture).isPending)
        #expect(try !account(fixture).requiresPeriodReview)
        #expect(try account(fixture).automaticPostingStartsAt == date(2, 10))
    }

    @Test func correctedCloseSurvivesAutomaticAndManualRefresh() throws {
        let fixture = try fixture()
        try confirm(january(fixture), fixture: fixture, corrected: 0, explanation: "Cannot reconstruct this old period")
        try SavingsPeriodReviewService.setRequiresReview(false, workspace: fixture.workspace, modelContext: fixture.context, now: date(1))
        fixture.variable.amount = 300
        try fixture.context.save()
        SavingsAccountService.runAutoCaptureIfNeeded(
            for: fixture.workspace, defaultBudgetingPeriodRaw: "monthly",
            incomes: [fixture.income], plannedExpenses: [fixture.planned], variableExpenses: [fixture.variable],
            modelContext: fixture.context, now: date(4, 10)
        )
        _ = SavingsAccountService.runManualSyncIfNeeded(
            for: fixture.workspace, defaultBudgetingPeriodRaw: "monthly",
            incomes: [fixture.income], plannedExpenses: [fixture.planned], variableExpenses: [fixture.variable],
            modelContext: fixture.context, now: date(4, 10)
        )
        try fixture.context.save()
        let close = try #require(entries(fixture).first { $0.kind == .periodClose })
        #expect(close.amount == 0)
        #expect(close.correctedCloseAmount == 0)
        #expect(close.correctionExplanation == "Cannot reconstruct this old period")
        #expect(try january(fixture).needsReview)
    }

    @Test func twoWeekScheduleKeepsWeeklyCloseAndPostsNextUncoveredPeriod() throws {
        let fixture = try fixture()
        let period = DefaultBudgetingPeriod(.weekly, weeklyInterval: 2)
        let firstRange = SavingsAccountService.periodRange(containing: fixture.income.date, period: period)
        let secondRange = try #require(SavingsAccountService.nextRange(after: firstRange, period: period))
        let thirdRange = try #require(SavingsAccountService.nextRange(after: secondRange, period: period))
        let now = thirdRange.start
        let firstUncoveredDay = Calendar.current.date(byAdding: .second, value: 1, to: firstRange.end)
        #expect(secondRange.start == firstUncoveredDay)

        let legacyRange = SavingsAccountService.periodRange(
            containing: fixture.income.date, period: DefaultBudgetingPeriod(.weekly)
        )
        let account = SavingsAccountService.ensureSavingsAccount(for: fixture.workspace, modelContext: fixture.context)
        let legacy = SavingsLedgerEntry(
            date: legacyRange.end, amount: 125, note: "Prior weekly close",
            kindRaw: SavingsLedgerEntryKind.periodClose.rawValue,
            periodStartDate: legacyRange.start, periodEndDate: legacyRange.end,
            workspace: fixture.workspace, account: account
        )
        let legacyID = legacy.id
        fixture.context.insert(legacy)
        let income = Income(source: "Next paycheck", amount: 500, date: secondRange.start,
                            isPlanned: false, workspace: fixture.workspace, card: fixture.card)
        fixture.context.insert(income)
        try fixture.context.save()
        let review = try summaries(fixture, period: period.rawValue, now: now)
        #expect(review.contains { $0.start == firstRange.start && $0.end == firstRange.end && $0.hasOverlapConflict })
        #expect(review.contains { $0.start == secondRange.start && $0.end == secondRange.end && !$0.hasOverlapConflict })

        try SavingsPeriodReviewService.setRequiresReview(
            false, workspace: fixture.workspace, modelContext: fixture.context, now: firstRange.start
        )
        for _ in 0..<2 {
            SavingsAccountService.runAutoCaptureIfNeeded(
                for: fixture.workspace, defaultBudgetingPeriodRaw: period.rawValue,
                incomes: [fixture.income, income], plannedExpenses: [fixture.planned], variableExpenses: [fixture.variable],
                modelContext: fixture.context, now: now
            )
        }
        let closes = try entries(fixture).filter { $0.kind == .periodClose }
        #expect(closes.count == 2)
        let preserved = try #require(closes.first { $0.id == legacyID })
        #expect(preserved.periodStartDate == legacyRange.start)
        #expect(preserved.periodEndDate == legacyRange.end)
        #expect(preserved.amount == 125)
        #expect(closes.contains { $0.periodStartDate == secondRange.start && $0.periodEndDate == secondRange.end })
    }

    @Test func incomeWidgetAndSafeSpendUseTheSharedTwoWeekDefault() throws {
        let fixture = try fixture()
        let defaults = try #require(UserDefaults(suiteName: IncomeWidgetSnapshotStore.appGroupID))
        let key = "general_defaultBudgetingPeriod"
        let original = defaults.object(forKey: key)
        defer { defaults.set(original, forKey: key) }
        let period = DefaultBudgetingPeriod(.weekly, weeklyInterval: 2)
        defaults.set(period.rawValue, forKey: key)
        let now = date(1, 12)
        let snapshot = try #require(IncomeWidgetSnapshotBuilder.buildSnapshot(
            modelContext: fixture.context, workspaceID: fixture.workspace.id,
            period: .period, now: now, maxRecent: 3
        ))
        let expected = SavingsAccountService.periodRange(containing: now, period: period)
        #expect(snapshot.rangeStart == expected.start)
        #expect(snapshot.rangeEnd == expected.end)
        let safeSpend = SafeSpendTodayCalculator.calculate(
            workspace: fixture.workspace, budgetingPeriod: period.period,
            weeklyInterval: period.weeklyInterval, now: now
        )
        #expect(safeSpend.rangeStart == expected.start)
        #expect(safeSpend.rangeEnd == expected.end)
    }

    @Test func scheduleChangePreservesExistingBoundsAndBlocksOverlappingNewClose() throws {
        let fixture = try fixture()
        try confirm(january(fixture), fixture: fixture)
        let quarterly = try summaries(fixture, period: "quarterly")
        let conflict = try #require(quarterly.first { Calendar.current.component(.month, from: $0.start) == 1 && Calendar.current.component(.month, from: $0.end) == 3 })
        #expect(conflict.hasOverlapConflict)
        #expect(quarterly.contains { $0.existingEntry != nil && Calendar.current.component(.month, from: $0.end) == 1 })
        #expect(throws: (any Error).self) {
            try SavingsPeriodReviewService.confirm(conflict, workspaceID: fixture.workspace.id, defaultBudgetingPeriodRaw: "quarterly", correctedAmount: nil, explanation: "", acknowledged: true, modelContext: fixture.context, now: date(4, 10))
        }
        #expect(try entries(fixture).filter { $0.kind == .periodClose }.count == 1)
        #expect(try account(fixture).total == 700)
    }

    @Test(arguments: [300.0, 200.0])
    func calculatedClosesAllowZeroAndNegativeOutcomes(incomeAmount: Double) throws {
        let fixture = try fixture()
        fixture.income.amount = incomeAmount
        try fixture.context.save()
        let pending = try january(fixture)
        #expect(pending.calculatedAmount == incomeAmount - 300)
        try confirm(pending, fixture: fixture)
        #expect(try account(fixture).total == incomeAmount - 300)
        #expect(try entries(fixture).first?.correctedCloseAmount == nil)
    }

    @Test func removingAllActivityStillOffersExistingCloseForReview() throws {
        let fixture = try fixture()
        try confirm(january(fixture), fixture: fixture)
        fixture.context.delete(fixture.income)
        fixture.context.delete(fixture.planned)
        fixture.context.delete(fixture.variable)
        try fixture.context.save()
        let revised = try january(fixture)
        #expect(revised.calculatedAmount == 0)
        #expect(revised.needsReview)
        #expect(revised.postedAmount == 700)
        try confirm(revised, fixture: fixture)
        #expect(try account(fixture).total == 0)
    }

    @Test func repeatedDisableKeepsBoundaryAndReenableStopsPosting() throws {
        let fixture = try fixture()
        try SavingsPeriodReviewService.setRequiresReview(false, workspace: fixture.workspace, modelContext: fixture.context, now: date(2, 10))
        try SavingsPeriodReviewService.setRequiresReview(false, workspace: fixture.workspace, modelContext: fixture.context, now: date(2, 20))
        #expect(try account(fixture).automaticPostingStartsAt == date(2, 10))
        try SavingsPeriodReviewService.setRequiresReview(true, workspace: fixture.workspace, modelContext: fixture.context, now: date(2, 21))
        let february = Income(source: "February", amount: 1200, date: date(2, 5), isPlanned: false, workspace: fixture.workspace)
        fixture.context.insert(february)
        try fixture.context.save()
        SavingsAccountService.runAutoCaptureIfNeeded(
            for: fixture.workspace, defaultBudgetingPeriodRaw: "monthly",
            incomes: [fixture.income, february], plannedExpenses: [fixture.planned], variableExpenses: [fixture.variable],
            modelContext: fixture.context, now: date(3, 10)
        )
        try fixture.context.save()
        #expect(try entries(fixture).isEmpty)
        #expect(try account(fixture).requiresPeriodReview)
    }

    @Test func duplicateNormalizationRetainsReviewedCorrectionAndMetadata() throws {
        let fixture = try fixture()
        try confirm(january(fixture), fixture: fixture, corrected: 0, explanation: "Unreliable historical records")
        let context = ModelContext(fixture.container)
        let workspace = try #require(context.fetch(FetchDescriptor<Workspace>()).first { $0.id == fixture.workspace.id })
        let account = try #require(context.fetch(FetchDescriptor<SavingsAccount>()).first { $0.workspace?.id == workspace.id })
        let reviewed = try #require(context.fetch(FetchDescriptor<SavingsLedgerEntry>()).first { $0.kind == .periodClose })
        let duplicate = SavingsLedgerEntry(date: reviewed.date, amount: 999, note: "Older duplicate", kindRaw: SavingsLedgerEntryKind.periodClose.rawValue, periodStartDate: reviewed.periodStartDate, periodEndDate: reviewed.periodEndDate, createdAt: date(1), workspace: workspace, account: account)
        context.insert(duplicate)
        try context.save()
        _ = SavingsAccountService.normalizeSavingsData(for: workspace, modelContext: context)
        try context.save()
        let closes = try entries(fixture).filter { $0.kind == .periodClose }
        #expect(closes.count == 1)
        #expect(closes.first?.amount == 0)
        #expect(closes.first?.correctedCloseAmount == 0)
        #expect(closes.first?.correctionExplanation == "Unreliable historical records")
        #expect(closes.first?.reviewedInputFingerprint != nil)
        #expect(try self.account(fixture).total == 0)
    }

    @Test func duplicateClosePreviewMatchesConfirmedTotalAfterReplacingAllDuplicates() throws {
        let fixture = try fixture()
        let bounds = try january(fixture)
        let account = SavingsAccount(workspace: fixture.workspace)
        let first = SavingsLedgerEntry(date: bounds.end, amount: 300, note: "First duplicate", kindRaw: SavingsLedgerEntryKind.periodClose.rawValue, periodStartDate: bounds.start, periodEndDate: bounds.end, workspace: fixture.workspace, account: account)
        let second = SavingsLedgerEntry(date: bounds.end, amount: 400, note: "Second duplicate", kindRaw: SavingsLedgerEntryKind.periodClose.rawValue, periodStartDate: bounds.start, periodEndDate: bounds.end, workspace: fixture.workspace, account: account)
        let adjustment = SavingsLedgerEntry(date: date(2, 5), amount: 20, note: "Keep this adjustment", kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue, workspace: fixture.workspace, account: account)
        fixture.context.insert(account)
        fixture.context.insert(first)
        fixture.context.insert(second)
        fixture.context.insert(adjustment)
        account.total = 720
        try fixture.context.save()
        let review = try january(fixture)
        #expect(review.currentTotal == 720)
        #expect(review.postedAmount == 700)
        let proposedAmount = 500.0
        let projectedTotal = review.currentTotal - review.postedAmount + proposedAmount
        try confirm(review, fixture: fixture, corrected: proposedAmount, explanation: "Verified closing amount")
        let persisted = try entries(fixture)
        #expect(persisted.filter { $0.kind == .periodClose }.count == 1)
        #expect(persisted.first { $0.kind == .periodClose }?.amount == proposedAmount)
        #expect(persisted.first { $0.id == adjustment.id }?.amount == 20)
        #expect(try self.account(fixture).total == projectedTotal)
        #expect(projectedTotal == 520)
    }

    @Test func finiteCorrectionWhoseCurrencyRoundingOverflowsIsRejected() throws {
        let fixture = try fixture()
        let review = try january(fixture)
        #expect(Double.greatestFiniteMagnitude.isFinite)
        #expect(throws: (any Error).self) {
            try confirm(review, fixture: fixture, corrected: Double.greatestFiniteMagnitude, explanation: "Overflow regression")
        }
        #expect(try entries(fixture).isEmpty)
        #expect(try fixture.context.fetch(FetchDescriptor<SavingsAccount>()).isEmpty)
    }

    @Test func confirmationConsolidatesWorkspaceLedgerAndRecalculatesSecondaryAccounts() throws {
        let fixture = try fixture()
        let bounds = try january(fixture)
        let primary = SavingsAccount(name: "Primary", createdAt: date(1), workspace: fixture.workspace)
        let secondary = SavingsAccount(name: "Secondary", createdAt: date(2), workspace: fixture.workspace)
        let close = SavingsLedgerEntry(date: bounds.end, amount: 400, note: "Historical close", kindRaw: SavingsLedgerEntryKind.periodClose.rawValue, periodStartDate: bounds.start, periodEndDate: bounds.end, workspace: fixture.workspace, account: secondary)
        let primaryAdjustment = SavingsLedgerEntry(date: date(2, 2), amount: 10, note: "Primary history", kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue, workspace: fixture.workspace, account: primary)
        let secondaryAdjustment = SavingsLedgerEntry(date: date(2, 3), amount: 30, note: "Secondary history", kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue, workspace: fixture.workspace, account: secondary)
        let unassignedAdjustment = SavingsLedgerEntry(date: date(2, 4), amount: 50, note: "Unassigned history", kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue, workspace: fixture.workspace)
        fixture.context.insert(primary)
        fixture.context.insert(secondary)
        fixture.context.insert(close)
        fixture.context.insert(primaryAdjustment)
        fixture.context.insert(secondaryAdjustment)
        fixture.context.insert(unassignedAdjustment)
        primary.total = 10
        secondary.total = 430
        try fixture.context.save()
        let review = try january(fixture)
        #expect(review.currentTotal == 490)
        #expect(review.postedAmount == 400)
        let projectedTotal = review.currentTotal - review.postedAmount + review.calculatedAmount
        try confirm(review, fixture: fixture)
        let verificationContext = ModelContext(fixture.container)
        let accounts = try verificationContext.fetch(FetchDescriptor<SavingsAccount>())
        #expect(accounts.first { $0.id == primary.id }?.total == projectedTotal)
        #expect(accounts.first { $0.id == secondary.id }?.total == 0)
        let persisted = try entries(fixture)
        #expect(persisted.count == 4)
        #expect(persisted.allSatisfy { $0.account?.id == primary.id })
        #expect(persisted.first { $0.id == close.id }?.amount == 700)
        #expect(persisted.first { $0.id == primaryAdjustment.id }?.amount == 10)
        #expect(persisted.first { $0.id == secondaryAdjustment.id }?.amount == 30)
        #expect(persisted.first { $0.id == unassignedAdjustment.id }?.amount == 50)
        #expect(projectedTotal == 790)
    }

    @Test func mainContextReloadSeesReconfirmedAmountAndFingerprint() throws {
        let fixture = try fixture()
        try confirm(january(fixture), fixture: fixture)
        // Register the existing close in the long-lived UI context before another isolated save.
        let registered = try #require(SavingsPeriodReviewService.summaries(
            workspaceID: fixture.workspace.id, defaultBudgetingPeriodRaw: "monthly",
            modelContext: fixture.context, now: date(4, 10)
        ).first)
        #expect(registered.existingEntry?.amount == 700)
        #expect(!registered.needsReview)
        fixture.variable.amount = 150
        try fixture.context.save()
        let revised = try january(fixture)
        #expect(revised.needsReview)
        #expect(revised.calculatedAmount == 650)
        try confirm(revised, fixture: fixture)
        let reloaded = try #require(SavingsPeriodReviewService.summaries(
            workspaceID: fixture.workspace.id, defaultBudgetingPeriodRaw: "monthly",
            modelContext: fixture.context, now: date(4, 10)
        ).first { $0.id == registered.id })
        #expect(reloaded.existingEntry?.amount == 650)
        #expect(reloaded.postedAmount == 650)
        #expect(reloaded.existingEntry?.reviewedInputFingerprint == revised.inputFingerprint)
        #expect(!reloaded.needsReview)
        #expect(reloaded.currentTotal == 650)
    }

    @Test func failedConfirmationSaveLeavesNoApprovalAndSamePreviewCanRetry() throws {
        enum PersistFailure: Error { case unavailable }
        let fixture = try fixture()
        let account = SavingsAccount(workspace: fixture.workspace)
        let adjustment = SavingsLedgerEntry(date: date(1, 2), amount: 50, note: "Existing Savings", kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue, workspace: fixture.workspace, account: account)
        fixture.context.insert(account)
        fixture.context.insert(adjustment)
        account.total = 50
        try fixture.context.save()
        let review = try january(fixture)
        #expect(throws: PersistFailure.self) {
            try SavingsPeriodReviewService.confirm(
                review, workspaceID: fixture.workspace.id,
                defaultBudgetingPeriodRaw: "monthly", correctedAmount: nil,
                explanation: "", acknowledged: true, modelContext: fixture.context,
                now: date(4, 10), persist: { _ in throw PersistFailure.unavailable }
            )
        }
        let persisted = try entries(fixture)
        #expect(persisted.count == 1)
        #expect(persisted.first?.id == adjustment.id)
        #expect(persisted.first?.amount == 50)
        #expect(persisted.allSatisfy { $0.reviewedAt == nil && $0.reviewedInputFingerprint == nil })
        #expect(try self.account(fixture).total == 50)
        #expect(try january(fixture).isPending)
        #expect(try january(fixture).confirmationToken == review.confirmationToken)
        try confirm(review, fixture: fixture)
        #expect(try entries(fixture).filter { $0.kind == .periodClose }.count == 1)
        #expect(try self.account(fixture).total == 750)
    }

    @Test func storedDailyCloseRemainsInHistoryInsideCurrentMonthlyWindow() throws {
        let fixture = try fixture()
        let account = SavingsAccount(workspace: fixture.workspace)
        let start = Calendar.current.startOfDay(for: date(4, 3))
        let end = Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: start)!
        let daily = SavingsLedgerEntry(date: end, amount: 60, note: "Daily close before schedule change", kindRaw: SavingsLedgerEntryKind.periodClose.rawValue, periodStartDate: start, periodEndDate: end, workspace: fixture.workspace, account: account)
        fixture.context.insert(account)
        fixture.context.insert(daily)
        account.total = 60
        try fixture.context.save()
        let reviews = try summaries(fixture, period: "monthly", now: date(4, 10))
        let history = try #require(reviews.first { $0.existingEntry?.id == daily.id })
        #expect(history.start == start)
        #expect(history.end == end)
        #expect(!history.isPending)
        #expect(!history.needsReview)
        #expect(history.postedAmount == 60)
        #expect(!reviews.contains { $0.isPending && Calendar.current.component(.month, from: $0.start) == 4 })
        #expect(try self.account(fixture).total == 60)
    }
}
