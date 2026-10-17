import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct MarinaQueryServiceTests {
    private func context() throws -> ModelContext {
        let schema = Schema([Workspace.self, Budget.self, BudgetCategoryLimit.self, Card.self, BudgetCardLink.self, BudgetPresetLink.self, Category.self, Preset.self, PlannedExpense.self, VariableExpense.self, AllocationAccount.self, ExpenseAllocation.self, AllocationSettlement.self, SavingsAccount.self, SavingsLedgerEntry.self, ImportMerchantRule.self, AssistantAliasRule.self, MarinaChatSession.self, IncomeSeries.self, Income.self])
        return ModelContext(try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }
    private func day(_ offset: Int = 0) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: .now))! }

    @Test func workspaceIsolationInclusiveDayAndDebitMath() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = try context()
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        let other = Workspace(name: "Work", hexColor: "#654321")
        context.insert(workspace); context.insert(other)
        context.insert(VariableExpense(descriptionText: "Dinner", amount: 100, transactionDate: day().addingTimeInterval(3600), workspace: workspace))
        context.insert(VariableExpense(descriptionText: "Refund", amount: 20, kindRaw: VariableExpenseKind.credit.rawValue, transactionDate: day(), workspace: workspace))
        context.insert(VariableExpense(descriptionText: "Other workspace", amount: 900, transactionDate: day(), workspace: other))
        context.insert(VariableExpense(descriptionText: "Tomorrow", amount: 800, transactionDate: day(1), workspace: workspace))
        let service = MarinaQueryService(context: context, workspaceID: workspace.id, startDate: day(), endDate: day())
        _ = try service.statistics(MarinaQueryRequest())
        #expect(service.results.last?.total == 100)
        #expect(service.results.last?.count == 1)
        var ledger = MarinaQueryRequest(); ledger.metric = .ledger
        _ = try service.statistics(ledger)
        #expect(service.results.last?.total == 80)
        _ = try service.find(MarinaQueryRequest())
        #expect(service.results.last?.count == 2)
    }

    @Test func plannedFallbackAndIncomeStatesRemainDistinct() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = try context(); let workspace = Workspace(name: "Personal", hexColor: "#123456"); context.insert(workspace)
        context.insert(PlannedExpense(title: "Expected", plannedAmount: 50, expenseDate: day(), workspace: workspace))
        context.insert(PlannedExpense(title: "Recorded", plannedAmount: 100, actualAmount: 80, expenseDate: day(), workspace: workspace))
        context.insert(Income(source: "Received", amount: 200, date: day(), isPlanned: false, workspace: workspace))
        context.insert(Income(source: "Expected", amount: 500, date: day(), isPlanned: true, workspace: workspace))
        let service = MarinaQueryService(context: context, workspaceID: workspace.id, startDate: day(), endDate: day())
        var request = MarinaQueryRequest(); request.domain = .plannedExpenses
        _ = try service.statistics(request); #expect(service.results.last?.total == 130)
        request.state = .actual
        _ = try service.statistics(request); #expect(service.results.last?.total == 80)
        request.domain = .income; request.state = .all
        _ = try service.statistics(request); #expect(service.results.last?.total == 200)
        request.state = .planned
        _ = try service.statistics(request); #expect(service.results.last?.total == 500)
    }

    @Test func ambiguousNamesAndInvalidDatesCannotProduceResults() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = try context(); let workspace = Workspace(name: "Personal", hexColor: "#123456"); context.insert(workspace)
        context.insert(Card(name: "Daily", workspace: workspace)); context.insert(Card(name: " daily ", workspace: workspace))
        let service = MarinaQueryService(context: context, workspaceID: workspace.id, startDate: day(), endDate: day())
        var request = MarinaQueryRequest(); request.cardName = "Daily"
        _ = try service.find(request)
        #expect(service.results.isEmpty); #expect(service.clarificationMessage != nil)
        service.resetResults(); request.cardName = nil; request.startDate = "2026-02-30"
        _ = try service.find(request)
        #expect(service.results.isEmpty); #expect(service.clarificationMessage != nil)
    }

    @Test func amountFiltersAndComparisonAreCalculatedInSwift() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = try context(); let workspace = Workspace(name: "Personal", hexColor: "#123456"); context.insert(workspace)
        for amount in [89.0, 90, 100, 110, 111] { context.insert(VariableExpense(descriptionText: "Purchase", amount: amount, transactionDate: day(), workspace: workspace)) }
        let service = MarinaQueryService(context: context, workspaceID: workspace.id, startDate: day(), endDate: day())
        var request = MarinaQueryRequest(); request.minAmount = 90; request.maxAmount = 110
        _ = try service.find(request); #expect(service.results.last?.count == 3)
        request.metric = .categoryBreakdown
        _ = try service.statistics(request); #expect(service.results.last?.points.first?.value == 300)
        request.metric = .average
        _ = try service.statistics(request); #expect(service.results.last?.total == 100)
    }
    @Test func budgetScopingDoesNotMixGeneratedRows() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = try context(); let workspace = Workspace(name: "Personal", hexColor: "#123456"); context.insert(workspace)
        let card = Card(name: "Daily", workspace: workspace); context.insert(card)
        let budget = Budget(name: "Current", startDate: day(), endDate: day(), workspace: workspace); context.insert(budget)
        context.insert(BudgetCardLink(budget: budget, card: card))
        context.insert(PlannedExpense(title: "This budget", plannedAmount: 50, expenseDate: day(), workspace: workspace, card: card, sourceBudgetID: budget.id))
        context.insert(PlannedExpense(title: "Another budget", plannedAmount: 900, expenseDate: day(), workspace: workspace, card: card, sourceBudgetID: UUID()))
        let service = MarinaQueryService(context: context, workspaceID: workspace.id, startDate: day(), endDate: day())
        var request = MarinaQueryRequest(); request.domain = .plannedExpenses; request.budgetName = "Current"
        _ = try service.statistics(request); #expect(service.results.last?.total == 50)
    }

    @Test func balanceUsesLedgerRatherThanCachedAccountTotal() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = try context(); let workspace = Workspace(name: "Personal", hexColor: "#123456"); context.insert(workspace)
        let account = SavingsAccount(name: "Savings", total: 9999, workspace: workspace); context.insert(account)
        context.insert(SavingsLedgerEntry(date: day(-5), amount: 100, note: "Saved", kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue, workspace: workspace, account: account))
        context.insert(SavingsLedgerEntry(date: day(), amount: -20, note: "Offset", kindRaw: SavingsLedgerEntryKind.expenseOffset.rawValue, workspace: workspace, account: account))
        context.insert(SavingsLedgerEntry(date: day(), amount: 500, note: "Legacy mirrored settlement", kindRaw: SavingsLedgerEntryKind.reconciliationSettlement.rawValue, workspace: workspace, account: account))
        let service = MarinaQueryService(context: context, workspaceID: workspace.id, startDate: day(), endDate: day())
        var request = MarinaQueryRequest(); request.domain = .savings; request.metric = .balance
        _ = try service.statistics(request); #expect(service.results.last?.total == 80)
        request.metric = .total
        _ = try service.statistics(request); #expect(service.results.last?.total == -20)
    }

    @Test func futureVisibilityAndCalculationSettingsRemainIndependent() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = try context(); let workspace = Workspace(name: "Personal", hexColor: "#123456"); context.insert(workspace)
        context.insert(VariableExpense(descriptionText: "Today", amount: 100, transactionDate: day(), workspace: workspace))
        context.insert(VariableExpense(descriptionText: "Tomorrow", amount: 200, transactionDate: day(1), workspace: workspace))
        let suiteName = "MarinaQueryTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "general_hideFutureVariableExpenses")
        defaults.set(false, forKey: "general_excludeFutureVariableExpensesFromCalculations")
        let service = MarinaQueryService(context: context, workspaceID: workspace.id, startDate: day(), endDate: day(1), defaults: defaults)
        _ = try service.find(MarinaQueryRequest()); #expect(service.results.last?.count == 1)
        _ = try service.statistics(MarinaQueryRequest()); #expect(service.results.last?.total == 300)
        var request = MarinaQueryRequest(); request.includeFuture = true
        _ = try service.find(request); #expect(service.results.last?.count == 2)
    }

    @Test func ownedAndBudgetImpactReuseAllocationAndOffsetMath() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = try context(); let workspace = Workspace(name: "Personal", hexColor: "#123456"); context.insert(workspace)
        let expense = VariableExpense(descriptionText: "Split", amount: 100, transactionDate: day(), workspace: workspace); context.insert(expense)
        let allocation = ExpenseAllocation(allocatedAmount: 30, preservesGrossAmount: true, workspace: workspace, expense: expense); context.insert(allocation); expense.allocation = allocation
        let offset = SavingsLedgerEntry(date: day(), amount: -20, note: "Offset", kindRaw: SavingsLedgerEntryKind.expenseOffset.rawValue, workspace: workspace, variableExpense: expense); context.insert(offset); expense.savingsLedgerEntry = offset
        context.insert(VariableExpense(descriptionText: "Refund", amount: 10, kindRaw: VariableExpenseKind.credit.rawValue, transactionDate: day(), workspace: workspace))
        context.insert(VariableExpense(descriptionText: "Adjustment", amount: 500, kindRaw: VariableExpenseKind.adjustment.rawValue, transactionDate: day(), workspace: workspace))
        let service = MarinaQueryService(context: context, workspaceID: workspace.id, startDate: day(), endDate: day())
        var request = MarinaQueryRequest(); request.metric = .budgetImpact
        _ = try service.statistics(request); #expect(service.results.last?.total == 40)
        request.metric = .owned
        _ = try service.statistics(request); #expect(service.results.last?.total == 60)
        request.metric = .total
        _ = try service.statistics(request); #expect(service.results.last?.total == 100)
        request.metric = .count
        _ = try service.statistics(request); #expect(service.results.last?.total == 3)
    }

    @Test func reconciliationBalanceKeepsSettlementsSeparateFromSavings() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = try context(); let workspace = Workspace(name: "Personal", hexColor: "#123456"); context.insert(workspace)
        let account = AllocationAccount(name: "Shared", workspace: workspace); context.insert(account)
        context.insert(ExpenseAllocation(allocatedAmount: 100, createdAt: day(-2), workspace: workspace, account: account))
        context.insert(ExpenseAllocation(allocatedAmount: -100, createdAt: day(-2), workspace: workspace, account: account))
        context.insert(AllocationSettlement(date: day(), note: "Settled", amount: -30, workspace: workspace, account: account))
        let service = MarinaQueryService(context: context, workspaceID: workspace.id, startDate: day(), endDate: day())
        var request = MarinaQueryRequest(); request.domain = .reconciliation; request.metric = .balance
        _ = try service.statistics(request); #expect(service.results.last?.total == 70)
        request.metric = .total
        _ = try service.statistics(request); #expect(service.results.last?.total == -30)
    }

    @Test func namedBudgetUsesItsRangeAndUnsupportedMetricsClarify() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = try context(); let workspace = Workspace(name: "Personal", hexColor: "#123456"); context.insert(workspace)
        let card = Card(name: "Daily", workspace: workspace); context.insert(card)
        let budget = Budget(name: "Last week", startDate: day(-7), endDate: day(-1), workspace: workspace); context.insert(budget)
        context.insert(BudgetCardLink(budget: budget, card: card))
        context.insert(VariableExpense(descriptionText: "Last week", amount: 100, transactionDate: day(-5), workspace: workspace, card: card))
        context.insert(VariableExpense(descriptionText: "Today", amount: 200, transactionDate: day(), workspace: workspace, card: card))
        let service = MarinaQueryService(context: context, workspaceID: workspace.id, startDate: day(), endDate: day())
        var request = MarinaQueryRequest(); request.budgetName = "Last week"
        _ = try service.statistics(request); #expect(service.results.last?.total == 100)
        #expect(service.followUpSummary.contains("\"budget\"")); #expect(service.followUpSummary.contains("Last week"))
        service.resetResults(); request = MarinaQueryRequest(); request.domain = .income; request.metric = .owned
        _ = try service.statistics(request); #expect(service.results.isEmpty); #expect(service.clarificationMessage != nil)
        service.resetResults(); request.metric = .categoryBreakdown
        _ = try service.statistics(request); #expect(service.results.isEmpty); #expect(service.clarificationMessage != nil)
    }

    @Test func isoDatesRemainGregorianUnderOtherCalendars() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = try context(); let workspace = Workspace(name: "Personal", hexColor: "#123456"); context.insert(workspace)
        var gregorian = Calendar(identifier: .gregorian); gregorian.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = gregorian.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        context.insert(VariableExpense(descriptionText: "September", amount: 100, transactionDate: date, workspace: workspace))
        var buddhist = Calendar(identifier: .buddhist); buddhist.timeZone = gregorian.timeZone
        let service = MarinaQueryService(context: context, workspaceID: workspace.id, startDate: date, endDate: date, calendar: buddhist)
        var request = MarinaQueryRequest(); request.startDate = "2026-09-01"; request.endDate = "2026-09-01"
        _ = try service.statistics(request); #expect(service.results.last?.total == 100)
    }

    @Test func savingsOutlookMatchesHomeDeterministicMath() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = try context(); let workspace = Workspace(name: "Personal", hexColor: "#123456"); context.insert(workspace)
        context.insert(Income(source: "Expected", amount: 1000, date: day(), isPlanned: true, workspace: workspace))
        context.insert(Income(source: "Received", amount: 900, date: day(), isPlanned: false, workspace: workspace))
        context.insert(PlannedExpense(title: "Rent", plannedAmount: 100, actualAmount: 80, expenseDate: day(), workspace: workspace))
        context.insert(PlannedExpense(title: "Expected fallback", plannedAmount: 50, expenseDate: day(), workspace: workspace))
        context.insert(VariableExpense(descriptionText: "Debit", amount: 200, transactionDate: day(), workspace: workspace))
        context.insert(VariableExpense(descriptionText: "Refund", amount: 20, kindRaw: VariableExpenseKind.credit.rawValue, transactionDate: day(), workspace: workspace))
        context.insert(SavingsLedgerEntry(date: day(), amount: 10, note: "Manual", kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue, workspace: workspace))
        context.insert(SavingsLedgerEntry(date: day(), amount: 500, note: "Period close", kindRaw: SavingsLedgerEntryKind.periodClose.rawValue, workspace: workspace))
        let service = MarinaQueryService(context: context, workspaceID: workspace.id, startDate: day(), endDate: day())
        var request = MarinaQueryRequest(); request.domain = .budgets; request.metric = .projectedSavings
        _ = try service.statistics(request); #expect(service.results.last?.total == 850)
        request.metric = .actualSurplus
        _ = try service.statistics(request); #expect(service.results.last?.total == 600)
    }

    @Test func stableIDsResolveDuplicateNamesWithoutCrossingWorkspace() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = try context(); let workspace = Workspace(name: "Personal", hexColor: "#123456"); context.insert(workspace)
        let other = Workspace(name: "Other", hexColor: "#654321"); context.insert(other)
        let chosen = Card(name: "Daily", workspace: workspace); context.insert(chosen)
        context.insert(Card(name: "Daily", workspace: workspace))
        let foreign = Card(name: "Daily", workspace: other); context.insert(foreign)
        context.insert(VariableExpense(descriptionText: "Chosen", amount: 50, transactionDate: day(), workspace: workspace, card: chosen))
        let service = MarinaQueryService(context: context, workspaceID: workspace.id, startDate: day(), endDate: day())
        let choices = try service.resolve(MarinaEntityRequest(kind: .card, name: "Daily")); #expect(choices.contains(chosen.id.uuidString))
        service.resetResults()
        var request = MarinaQueryRequest(); request.cardName = "Daily"; request.cardID = chosen.id.uuidString
        _ = try service.find(request); #expect(service.results.last?.count == 1)
        service.resetResults(); request.cardID = foreign.id.uuidString
        _ = try service.find(request); #expect(service.results.isEmpty); #expect(service.clarificationMessage != nil)
        service.resetResults(); request = MarinaQueryRequest(); request.domain = .savings; request.metric = .balance; request.text = "Filtered"
        _ = try service.statistics(request); #expect(service.results.isEmpty); #expect(service.clarificationMessage != nil)
    }

    @Test func compactToolAdapterResolvesCalendarPeriodsAndExplicitFilters() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!; calendar.firstWeekday = 2; calendar.minimumDaysInFirstWeek = 4
        var query = MarinaToolQuery(); query.periodKind = .day; query.startDate = "2026-09-01"
        var request = try query.request(calendar: calendar)
        #expect(request.startDate == "2026-09-01"); #expect(request.endDate == "2026-09-01"); #expect(request.text == nil)
        query.periodKind = .week; query.startDate = "2026-09-01"
        request = try query.request(calendar: calendar)
        #expect(request.startDate == "2026-08-31"); #expect(request.endDate == "2026-09-06")
        query.periodKind = .month; query.startDate = "2026-09-01"
        request = try query.request(calendar: calendar)
        #expect(request.startDate == "2026-09-01"); #expect(request.endDate == "2026-09-30")
        query.domain = .plannedExpenses; query.amountScope = .range; query.minAmount = 90; query.maxAmount = 110
        request = try query.request(calendar: calendar)
        #expect(request.domain == .plannedExpenses); #expect(request.state == .all); #expect(request.minAmount == 90); #expect(request.maxAmount == 110)
    }

    @Test func flatToolAdapterRejectsInvalidDatesAndAmounts() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        var query = MarinaToolQuery(); query.periodKind = .day; query.startDate = "2026-02-30"
        #expect(throws: MarinaQueryError.self) { try query.request() }
        query.periodKind = .range; query.startDate = "2026-09-01"; query.endDate = nil
        #expect(throws: MarinaQueryError.self) { try query.request() }
        query.startDate = nil; query.amountScope = .range; query.minAmount = .nan
        #expect(throws: MarinaQueryError.self) { try query.request() }
        query.minAmount = 110; query.maxAmount = 90
        #expect(throws: MarinaQueryError.self) { try query.request() }
    }

    @Test func toolStatesAndFollowupShapeRoundTripWithoutDomainConfusion() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        var query = MarinaToolQuery(); query.domain = .plannedExpenses
        query.periodKind = .week; query.startDate = "2026-09-01"; query.endDate = "2026-09-01"
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!; calendar.firstWeekday = 2
        var request = try query.request(calendar: calendar)
        #expect(request.state == .all); #expect(request.endDate == "2026-09-06")
        query.state = .recorded; request = try query.request(calendar: calendar); #expect(request.state == .actual)
        query.state = .expectedOnly; request = try query.request(calendar: calendar); #expect(request.state == .planned)
        request.cardID = UUID().uuidString
        let compact = MarinaToolQuery(query: request)
        let decoded = try JSONDecoder().decode(MarinaToolQuery.self, from: JSONEncoder().encode(compact))
        let restored = try decoded.request(calendar: calendar)
        #expect(restored.cardID == request.cardID); #expect(restored.startDate == request.startDate); #expect(restored.state == .planned)
    }

    @Test func recoverableFilterErrorsClearAfterSuccessfulCorrection() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = try context(); let workspace = Workspace(name: "Personal", hexColor: "#123456"); context.insert(workspace)
        let card = Card(name: "Daily", workspace: workspace); context.insert(card)
        context.insert(VariableExpense(descriptionText: "Purchase", amount: 50, transactionDate: day(), workspace: workspace, card: card))
        let service = MarinaQueryService(context: context, workspaceID: workspace.id, startDate: day(), endDate: day())
        var request = MarinaQueryRequest(); request.cardName = "Invented"
        _ = try service.find(request); #expect(service.clarificationMessage != nil); #expect(service.results.isEmpty)
        request.cardName = "Daily"
        _ = try service.find(request); #expect(service.clarificationMessage == nil); #expect(service.results.last?.count == 1)
        service.resetResults()
        _ = try service.resolve(MarinaEntityRequest(kind: .card, name: "Invented")); #expect(service.clarificationMessage != nil)
        _ = try service.find(request); #expect(service.clarificationMessage == nil)
    }

    @Test func duplicateResolutionStaysStickyUntilNextUserTurn() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = try context(); let workspace = Workspace(name: "Personal", hexColor: "#123456"); context.insert(workspace)
        let card = Card(name: "Daily", workspace: workspace); context.insert(card); context.insert(Card(name: "Daily", workspace: workspace))
        context.insert(VariableExpense(descriptionText: "Purchase", amount: 50, transactionDate: day(), workspace: workspace, card: card))
        let service = MarinaQueryService(context: context, workspaceID: workspace.id, startDate: day(), endDate: day())
        _ = try service.resolve(MarinaEntityRequest(kind: .card, name: "Daily"))
        let ambiguity = service.clarificationMessage; #expect(ambiguity != nil)
        var request = MarinaQueryRequest(); request.cardID = card.id.uuidString
        _ = try service.find(request); #expect(service.clarificationMessage == ambiguity)
        service.resetResults()
        _ = try service.find(request); #expect(service.clarificationMessage == nil); #expect(service.results.last?.count == 1)
    }

    @Test func emptyNameResolutionListsOnlySelectedWorkspaceEntities() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = try context(); let workspace = Workspace(name: "Personal", hexColor: "#123456"); context.insert(workspace)
        let other = Workspace(name: "Other", hexColor: "#654321"); context.insert(other)
        context.insert(Card(name: "Personal Card", workspace: workspace)); context.insert(Card(name: "Foreign Card", workspace: other))
        let service = MarinaQueryService(context: context, workspaceID: workspace.id, startDate: day(), endDate: day())
        let available = try service.resolve(MarinaEntityRequest(kind: .card, name: ""))
        #expect(available.contains("Personal Card")); #expect(!available.contains("Foreign Card")); #expect(service.clarificationMessage == nil)
        let catalog = try service.entityCatalog()
        #expect(catalog.contains("Personal Card")); #expect(!catalog.contains("Foreign Card"))
    }

    @Test func categoryChartKeepsDuplicateNamesAndVirtualUncategorizedDistinct() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = try context(); let workspace = Workspace(name: "Personal", hexColor: "#123456"); context.insert(workspace)
        let first = Category(name: "Food", hexColor: "#123456", workspace: workspace)
        let second = Category(name: "Food", hexColor: "#654321", workspace: workspace)
        let stored = Category(name: "Uncategorized", hexColor: "#ABCDEF", workspace: workspace)
        context.insert(first); context.insert(second); context.insert(stored)
        for (amount, category) in [(10.0, Optional(first)), (20.0, Optional(second)), (30.0, Optional(stored)), (40.0, nil)] {
            context.insert(VariableExpense(descriptionText: "Purchase", amount: amount, transactionDate: day(), workspace: workspace, category: category))
        }
        let service = MarinaQueryService(context: context, workspaceID: workspace.id, startDate: day(), endDate: day())
        var request = MarinaQueryRequest(); request.metric = .categoryBreakdown
        _ = try service.statistics(request)
        let points = service.results.last!.points
        #expect(points.count == 4); #expect(Set(points.map(\.id)).count == 4); #expect(Set(points.map(\.label)).count == 4)
        #expect(points.reduce(0) { $0 + $1.value } == 100); #expect(service.results.last?.total == 100)
    }

    @Test func namedBudgetWithOnlyExplicitEndUsesBudgetStart() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = try context(); let workspace = Workspace(name: "Personal", hexColor: "#123456"); context.insert(workspace)
        let card = Card(name: "Daily", workspace: workspace); context.insert(card)
        let budget = Budget(name: "Previous", startDate: day(-7), endDate: day(-1), workspace: workspace); context.insert(budget)
        context.insert(BudgetCardLink(budget: budget, card: card))
        context.insert(VariableExpense(descriptionText: "Included", amount: 50, transactionDate: day(-6), workspace: workspace, card: card))
        context.insert(VariableExpense(descriptionText: "After end", amount: 100, transactionDate: day(-2), workspace: workspace, card: card))
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = Calendar.current.timeZone
        let service = MarinaQueryService(context: context, workspaceID: workspace.id, startDate: day(), endDate: day())
        var request = MarinaQueryRequest(); request.budgetName = "Previous"; request.endDate = formatter.string(from: day(-4))
        _ = try service.statistics(request)
        #expect(service.clarificationMessage == nil); #expect(service.results.last?.total == 50)
    }

    @Test func storedUncategorizedAndMissingCategoryRequireExplicitChoice() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = try context(); let workspace = Workspace(name: "Personal", hexColor: "#123456"); context.insert(workspace)
        let stored = Category(name: "Uncategorized", hexColor: "#ABCDEF", workspace: workspace); context.insert(stored)
        context.insert(VariableExpense(descriptionText: "Stored", amount: 30, transactionDate: day(), workspace: workspace, category: stored))
        context.insert(VariableExpense(descriptionText: "Missing", amount: 40, transactionDate: day(), workspace: workspace))
        let service = MarinaQueryService(context: context, workspaceID: workspace.id, startDate: day(), endDate: day())
        var request = MarinaQueryRequest(); request.categoryName = "Uncategorized"
        _ = try service.find(request); #expect(service.results.isEmpty); #expect(service.clarificationMessage != nil)
        service.resetResults(); request.categoryID = stored.id.uuidString
        _ = try service.find(request); #expect(service.results.last?.records.first?.title == "Stored"); #expect(service.results.last?.count == 1)
        service.resetResults(); request.categoryID = nil; request.categoryName = "Unclassified"
        _ = try service.find(request); #expect(service.results.last?.records.first?.title == "Missing"); #expect(service.results.last?.count == 1)
    }

    @Test func comparisonPreservesBothPeriodValuesAndDisplayedDates() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        let context = try context(); let workspace = Workspace(name: "Personal", hexColor: "#123456"); context.insert(workspace)
        context.insert(VariableExpense(descriptionText: "Current", amount: 50, transactionDate: day(), workspace: workspace))
        context.insert(VariableExpense(descriptionText: "Prior", amount: 20, transactionDate: day(-7), workspace: workspace))
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = Calendar.current.timeZone
        let service = MarinaQueryService(context: context, workspaceID: workspace.id, startDate: day(), endDate: day())
        var request = MarinaQueryRequest(); request.metric = .comparison
        request.comparisonStartDate = formatter.string(from: day(-7)); request.comparisonEndDate = request.comparisonStartDate
        _ = try service.statistics(request)
        let result = service.results.last!
        #expect(service.results.count == 1); #expect(result.total == 50)
        #expect(result.points.map(\.value) == [50, 20]); #expect(result.detail.contains("Compared with"))
        #expect(result.detail.contains(day(-7).formatted(date: .abbreviated, time: .omitted)))
    }

    @Test func amountScopeIgnoresIncidentalNumbersAndCalculatesApproximateBounds() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { return }
        var query = MarinaToolQuery(); query.maxAmount = 100
        let all = try query.request(); #expect(all.minAmount == nil); #expect(all.maxAmount == nil)
        query.amountScope = .around
        let approximate = try query.request(); #expect(approximate.minAmount == 90); #expect(abs(approximate.maxAmount! - 110) < 0.0001)
        query.amountScope = .range; query.minAmount = 95
        let range = try query.request(); #expect(range.minAmount == 95); #expect(range.maxAmount == 100)
        let restored = try MarinaToolQuery(query: range).request(); #expect(restored.minAmount == 95); #expect(restored.maxAmount == 100)
    }

}
