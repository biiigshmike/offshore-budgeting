import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
final class MarinaCapabilityDataTests {
    private var containers: [ModelContainer] = []

    private func fixture() throws -> (ModelContext, Workspace, Card) {
        let schema = Schema([Workspace.self, Budget.self, Card.self, BudgetCardLink.self, Offshore.Category.self,
            Preset.self, BudgetPresetLink.self, BudgetCategoryLimit.self, PlannedExpense.self, VariableExpense.self,
            AllocationAccount.self, ExpenseAllocation.self, AllocationSettlement.self, SavingsAccount.self,
            SavingsLedgerEntry.self, ImportMerchantRule.self, AssistantAliasRule.self, IncomeSeries.self, Income.self,
            MarinaChatSession.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(
            "MarinaCapabilities-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        containers.append(container)
        let context = ModelContext(container)
        let workspace = Workspace(name: "Personal", hexColor: "#FFFFFF")
        let card = Card(name: "Apple Card", workspace: workspace)
        context.insert(workspace); context.insert(card)
        return (context, workspace, card)
    }

    private func date(_ day: Int, month: Int = 10, hour: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }
    private func metric(_ label: String, _ result: MarinaDataResult) -> Double? {
        result.metrics.first { $0.label == label }?.value
    }
    private func request(_ tool: MarinaDataRequest.Tool, purpose: MarinaDataRequest.Purpose? = nil) -> MarinaDataRequest {
        var value = MarinaDataRequest(tool: tool); value.purpose = purpose
        value.startDate = "2026-10-01"; value.endDate = "2026-10-31"
        return value
    }

    @Test func peakDrilldownReadsFreshScopedExpensesWithoutReplacingSavedReport() throws {
        let (context, workspace, card) = try fixture()
        let category = Category(name: "Dining", hexColor: "#123456", workspace: workspace)
        let otherCard = Card(name: "Other card", workspace: workspace)
        let otherWorkspace = Workspace(name: "Work", hexColor: "#654321")
        let foreignCard = Card(name: "Work card", workspace: otherWorkspace)
        context.insert(category); context.insert(otherCard); context.insert(otherWorkspace); context.insert(foreignCard)
        var expenses: [VariableExpense] = []
        for index in 0..<8 {
            let expense = VariableExpense(descriptionText: "Dining \(index)", amount: 10,
                transactionDate: date(10), workspace: workspace, card: card, category: category)
            context.insert(expense); expenses.append(expense)
        }
        context.insert(VariableExpense(descriptionText: "Other card", amount: 1000,
            transactionDate: date(10), workspace: workspace, card: otherCard, category: category))
        context.insert(VariableExpense(descriptionText: "Foreign", amount: 2000,
            transactionDate: date(10), workspace: otherWorkspace, card: foreignCard))
        try context.save()
        var query = request(.expenses, purpose: .spendingPatterns)
        query.cardID = card.id.uuidString; query.categoryID = category.id.uuidString
        query.expenseMeasure = .spending; query.periodUnit = .day
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: date(17))
        let snapshot = try #require(service.execute(query).presentation)
        let drilldown = MarinaPeakDrilldown(workspaceID: workspace.id, presentation: snapshot)
        let selected = try #require(drilldown.request(for: workspace.id))
        #expect(selected.startDate == "2026-10-10" && selected.endDate == "2026-10-10")
        #expect(selected.cardID == card.id.uuidString && selected.categoryID == category.id.uuidString)
        #expect(selected.expenseMeasure == .spending && selected.operation == .transactions)
        #expect(drilldown.request(for: otherWorkspace.id) == nil)
        expenses[0].amount = 20
        try context.save()
        let fresh = try drilldown.read(workspace: workspace, modelContext: context, homeContext: nil,
                                      defaultBudgetingPeriod: .monthly, now: date(17))
        #expect(metric("Total", fresh) == 90 && fresh.totalCount == 8)
        #expect(fresh.records.count == 5)
        #expect(snapshot.report?.peak?.amount == 80)
        let page = try #require(fresh.presentation)
        #expect(try service.loadMore(presentation: page).records.count == 8)
        var wrongPeriod = snapshot
        wrongPeriod.report?.peak?.drilldownRequest?.startDate = "2026-10-01"
        #expect(MarinaPeakDrilldown(workspaceID: workspace.id, presentation: wrongPeriod).request(for: workspace.id) == nil)
        var missingCard = snapshot
        missingCard.report?.peak?.drilldownRequest?.cardID = UUID().uuidString
        let unavailable = try MarinaPeakDrilldown(workspaceID: workspace.id, presentation: missingCard)
            .read(workspace: workspace, modelContext: context, homeContext: nil,
                  defaultBudgetingPeriod: .monthly, now: date(17))
        #expect(unavailable.status == "invalidRequest" && unavailable.presentation == nil)
    }

    @Test(arguments: [true, false])
    func peakDrilldownPaginationKeepsIndependentSavedFuturePolicies(_ excludesPlanned: Bool) throws {
        let (context, workspace, card) = try fixture()
        for index in 0..<6 {
            context.insert(VariableExpense(descriptionText: "Recorded \(index)", amount: 10,
                transactionDate: date(10), workspace: workspace, card: card))
            context.insert(VariableExpense(descriptionText: "Future variable \(index)", amount: 50,
                transactionDate: date(20), workspace: workspace, card: card))
            context.insert(PlannedExpense(title: "Future planned \(index)", plannedAmount: 100,
                expenseDate: date(20), workspace: workspace, card: card))
        }
        try context.save()
        let savedContext = MarinaPanelHomeContext(dateRange: nil,
            excludeFuturePlannedExpensesFromCalculations: excludesPlanned,
            excludeFutureVariableExpensesFromCalculations: !excludesPlanned)
        let currentContext = MarinaPanelHomeContext(dateRange: nil,
            excludeFuturePlannedExpensesFromCalculations: !excludesPlanned,
            excludeFutureVariableExpensesFromCalculations: excludesPlanned)
        var query = request(.expenses, purpose: .spendingPatterns)
        query.cardID = card.id.uuidString; query.periodUnit = .month
        let savedService = MarinaReadOnlyDataService(workspace: workspace, modelContext: context,
                                                    homeContext: savedContext, now: date(17))
        let snapshot = try #require(savedService.execute(query).presentation)
        let drilldown = MarinaPeakDrilldown(workspaceID: workspace.id, presentation: snapshot)
        let first = try drilldown.read(workspace: workspace, modelContext: context, homeContext: currentContext,
                                      defaultBudgetingPeriod: .monthly, now: date(17))
        let expectedTotal = excludesPlanned ? 360.0 : 660.0
        #expect(metric("Total", first) == expectedTotal && first.totalCount == 12)
        let firstPage = try #require(first.presentation)
        #expect(firstPage.pagination?.excludeFuturePlanned == excludesPlanned)
        #expect(firstPage.pagination?.excludeFutureVariable == !excludesPlanned)
        // The outer service has changed settings and clock. loadMore must use the
        // first read's frozen calculation policy and date, not these live defaults.
        let currentService = MarinaReadOnlyDataService(workspace: workspace, modelContext: context,
            homeContext: currentContext, now: date(25))
        let second = try currentService.loadMore(presentation: firstPage)
        let secondPage = try #require(second.presentation)
        let final = try currentService.loadMore(presentation: secondPage)
        #expect(second.records.count == 10 && final.records.count == 12)
        #expect(metric("Total", second) == expectedTotal && metric("Total", final) == expectedTotal)
        let excludedPrefix = excludesPlanned ? "Future planned" : "Future variable"
        #expect(final.records.allSatisfy { !$0.title.hasPrefix(excludedPrefix) })
        #expect(snapshot.report?.peak?.amount == expectedTotal)
    }

    @Test func cardReportSeparatesScreenSpendingFromOwnedBudgetImpact() throws {
        let (context, workspace, card) = try fixture()
        let shared = VariableExpense(descriptionText: "Shared dinner", amount: 100, transactionDate: date(10), workspace: workspace, card: card)
        let account = AllocationAccount(name: "Alex", workspace: workspace)
        let refund = VariableExpense(descriptionText: "Refund", amount: 25, transactionDate: date(11), workspace: workspace, card: card)
        refund.kind = .credit
        context.insert(shared); context.insert(account); context.insert(refund)
        context.insert(ExpenseAllocation(allocatedAmount: 40, preservesGrossAmount: true, workspace: workspace, account: account, expense: shared))
        context.insert(PlannedExpense(title: "Bill", plannedAmount: 50, expenseDate: date(12), workspace: workspace, card: card))
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: date(17))
        var cardRequest = request(.expenses, purpose: .cardSummary); cardRequest.cardID = card.id.uuidString
        let report = try service.execute(cardRequest)
        #expect(metric("Total", report) == 150)
        #expect(metric("Planned card spending", report) == 50)
        #expect(metric("Variable card spending", report) == 100)
        cardRequest.purpose = nil
        #expect(metric("Total", try service.execute(cardRequest)) == 85)
        cardRequest.operation = .transactions; cardRequest.transactionFilter = .split
        let detail = try #require(service.execute(cardRequest).report?.transactions?.first)
        #expect(detail.grossAmount == 100 && detail.splitAmount == 40 && detail.budgetImpact == 60)
        #expect(detail.transactionKind == "debit" && detail.accountName == "Alex")
        cardRequest.transactionFilter = .credit
        #expect(try service.execute(cardRequest).records.map(\.title) == ["Refund"])
    }

    @Test func extremaCountsAveragesAndCategoryUnionsUseAllMatchingRows() throws {
        let (context, workspace, card) = try fixture()
        let dining = Category(name: "Dining", hexColor: "#123456", workspace: workspace)
        let groceries = Category(name: "Groceries", hexColor: "#654321", workspace: workspace)
        context.insert(dining); context.insert(groceries)
        for value in 1...8 {
            context.insert(VariableExpense(descriptionText: "Purchase \(value)", amount: Double(value), transactionDate: date(value), workspace: workspace, card: card, category: value % 2 == 0 ? dining : groceries))
        }
        let credit = VariableExpense(descriptionText: "Refund", amount: 100, transactionDate: date(10), workspace: workspace, card: card)
        credit.kind = .credit; context.insert(credit)
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: date(17))
        var query = request(.expenses); query.categoryIDs = [dining.id.uuidString, groceries.id.uuidString]
        query.operation = .transactions; query.limit = 1; query.sort = .smallest; query.positiveOnly = true
        let result = try service.execute(query)
        #expect(result.records.first?.amount == 1)
        #expect(metric("Count", result) == 8 && metric("Average per record", result) == 4.5)
        #expect(metric("Total", result) == 36)
        #expect(result.presentation?.pagination == nil)
        query.metric = .average
        #expect(try service.execute(query).presentation?.metrics.first?.value == 4.5)
        query.metric = .count; query.grouping = .category; query.operation = .ranking
        let grouped = try service.execute(query)
        #expect(metric("Count", grouped) == 8 && metric("Group count", grouped) == 2)
        #expect(grouped.report?.groups?.first?.sharePercent == 16.0 / 36.0 * 100)
        query.metric = .groupCount
        #expect(try service.execute(query).presentation?.metrics.first?.value == 2)
        query.metric = .averagePerPeriod; query.grouping = .none; query.periodUnit = .day; query.operation = .trend
        let dailyMean = try service.execute(query)
        #expect(metric("Average per period", dailyMean) == 36.0 / 31.0)
        #expect(dailyMean.presentation?.metrics.first?.value == 36.0 / 31.0)
        query.categoryIDs = [UUID().uuidString]
        #expect(try service.execute(query).status == "invalidRequest")
    }

    @Test func periodLeaderComparisonUsesEachWinnerAndDoesNotCompareEntireTotals() throws {
        let (context, workspace, card) = try fixture()
        let dining = Category(name: "Dining", hexColor: "#123456", workspace: workspace)
        let travel = Category(name: "Travel", hexColor: "#654321", workspace: workspace)
        context.insert(dining); context.insert(travel)
        for (month, category, amount) in [(10, dining, 500.0), (10, travel, 100.0), (6, travel, 800.0), (6, dining, 300.0)] {
            context.insert(VariableExpense(descriptionText: category.name, amount: amount, transactionDate: date(10, month: month), workspace: workspace, card: card, category: category))
        }
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: date(17))
        var query = request(.expenses); query.operation = .comparison; query.grouping = .category; query.compareLeaders = true
        query.comparisonStartDate = "2026-06-01"; query.comparisonEndDate = "2026-06-30"
        let result = try service.execute(query)
        #expect(result.report?.leaders?.map(\.title) == ["Dining", "Travel"])
        #expect(metric("Total", result) == 500 && metric("Comparison total", result) == 800)
        #expect(metric("Difference", result) == -300)
        query.comparisonStartDate = "2026-05-01"; query.comparisonEndDate = "2026-05-31"
        let emptyComparison = try service.execute(query)
        #expect(emptyComparison.report?.leaders?.last?.amount == nil)
        #expect(metric("Difference", emptyComparison) == nil)
    }

    @Test func budgetReportAndCategoryAvailabilityRespectBudgetPopulation() throws {
        let (context, workspace, card) = try fixture()
        let other = Card(name: "Other", workspace: workspace)
        let food = Category(name: "Food", hexColor: "#123456", workspace: workspace)
        let budget = Budget(name: "October", startDate: date(1), endDate: date(31), workspace: workspace)
        context.insert(other); context.insert(food); context.insert(budget)
        context.insert(BudgetCardLink(budget: budget, card: card))
        context.insert(BudgetCategoryLimit(minAmount: 20, maxAmount: 100, budget: budget, category: food))
        context.insert(Income(source: "Pay", amount: 1000, date: date(1), isPlanned: true, workspace: workspace))
        context.insert(Income(source: "Pay", amount: 900, date: date(1), isPlanned: false, workspace: workspace))
        context.insert(PlannedExpense(title: "Bill", plannedAmount: 50, actualAmount: 40, expenseDate: date(2), workspace: workspace, card: card, category: food, sourceBudgetID: budget.id))
        context.insert(VariableExpense(descriptionText: "Food", amount: 55, transactionDate: date(3), workspace: workspace, card: card, category: food))
        context.insert(VariableExpense(descriptionText: "Unrelated", amount: 500, transactionDate: date(3), workspace: workspace, card: other, category: food))
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: date(17))
        var query = request(.budgetSummary, purpose: .budgetDetails); query.budgetID = budget.id.uuidString
        let detail = try service.execute(query)
        #expect(metric("Total", detail) == 95 && metric("Recorded planned expenses", detail) == 40)
        #expect(metric("Max savings", detail) == 960 && metric("Projected savings", detail) == 950)
        #expect(metric("Actual savings", detail) == 805)
        for (focus, expected) in [(MarinaDataRequest.MetricFocus.plannedIncome, 1000.0), (.receivedIncome, 900.0),
                                  (.plannedSpending, 50.0), (.recordedPlannedSpending, 40.0),
                                  (.effectivePlannedSpending, 40.0), (.variableSpending, 55.0)] {
            var focused = query; focused.metric = focus
            #expect(try service.execute(focused).presentation?.metrics.first?.value == expected)
        }
        query.purpose = .categoryAvailability; query.availabilityFilter = .overOrNear
        let category = try #require(service.execute(query).report?.categories?.first)
        #expect(category.minimum == 20 && category.maximum == 100)
        #expect(category.planned == 40 && category.variable == 55 && category.available == 5 && category.status == "near")
        query.availabilityFilter = .over
        #expect(try service.execute(query).report?.categories?.isEmpty == true)
    }

    @Test func activeDateDefaultDoesNotFilterCardsAndExplicitMonthsBypassAmbiguity() throws {
        let (context, workspace, card) = try fixture()
        let budget = Budget(name: "Trip", startDate: date(10), endDate: date(20), workspace: workspace)
        context.insert(budget)
        context.insert(VariableExpense(descriptionText: "Not a linked card", amount: 20, transactionDate: date(17), workspace: workspace, card: card))
        context.insert(VariableExpense(descriptionText: "Outside dates", amount: 30, transactionDate: date(3), workspace: workspace, card: card))
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: date(17))
        let implicit = try service.execute(.init(tool: .expenses))
        #expect(metric("Total", implicit) == 20 && implicit.resolvedRequest?.budgetID == nil)
        #expect(implicit.resolvedRequest?.startDate == "2026-10-10")
        context.insert(Budget(name: "Other active", startDate: date(1), endDate: date(31), workspace: workspace))
        try context.save()
        #expect(try service.execute(.init(tool: .expenses)).status == "needsPeriodChoice")
        var query = MarinaDataRequest(tool: .expenses); query.relativePeriod = .currentMonth
        #expect(metric("Total", try service.execute(query)) == 50)
        query.relativePeriod = nil; query.periodBudgetID = budget.id.uuidString
        #expect(metric("Total", try service.execute(query)) == 20)
    }

    @Test func nextPlannedExpenseIncludesManualRecordedItemsAndLinkedInventoryIsBudgetSpecific() throws {
        let (context, workspace, card) = try fixture()
        let budget = Budget(name: "October", startDate: date(1), endDate: date(31), workspace: workspace)
        let preset = Preset(title: "Archived bill", plannedAmount: 30, workspace: workspace, defaultCard: card, isArchived: true)
        let unrelated = Preset(title: "Unlinked", plannedAmount: 90, workspace: workspace)
        context.insert(budget); context.insert(preset); context.insert(unrelated)
        context.insert(BudgetPresetLink(budget: budget, preset: preset))
        context.insert(BudgetCardLink(budget: budget, card: card))
        context.insert(PlannedExpense(title: "Manual paid", plannedAmount: 20, actualAmount: 25, expenseDate: date(18), workspace: workspace, card: card))
        context.insert(PlannedExpense(title: "Preset due", plannedAmount: 30, expenseDate: date(19), workspace: workspace, card: card, sourcePresetID: preset.id, sourceBudgetID: budget.id))
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: date(17))
        let next = try service.execute(request(.expenses, purpose: .nextPlannedExpense))
        #expect(next.records.first?.title == "Manual paid" && next.records.first?.amount == 25)
        var query = request(.budgetSummary, purpose: .budgetPresets); query.budgetID = budget.id.uuidString
        let inventory = try service.execute(query)
        #expect(inventory.records.map(\.title) == ["Archived bill"])
        #expect(inventory.records.first?.detail?.contains("Archived") == true)
        query.purpose = .budgetCards
        #expect(try service.execute(query).records.map(\.title) == ["Apple Card"])
    }

    @Test func richerTimelinesKeepStatesSeparateAndFindPeakBeyondFirstPage() throws {
        let (context, workspace, card) = try fixture()
        let category = Category(name: "Travel", hexColor: "#123456", workspace: workspace)
        context.insert(category)
        for day in 1...8 {
            context.insert(VariableExpense(descriptionText: day == 8 ? "Hotel" : "Cafe", amount: day == 8 ? 100 : 1, transactionDate: date(day), workspace: workspace, card: card, category: category))
        }
        context.insert(Income(source: "Pay", amount: 500, date: date(1), isPlanned: true, workspace: workspace))
        context.insert(Income(source: "Pay", amount: 400, date: date(1), isPlanned: false, workspace: workspace))
        let savings = SavingsAccount(name: "Savings", workspace: workspace); context.insert(savings)
        context.insert(SavingsLedgerEntry(date: date(31, hour: 23), amount: 10, note: "Manual", kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue, workspace: workspace, account: savings))
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: date(17))
        var query = request(.expenses, purpose: .spendingPatterns); query.periodUnit = .day; query.limit = 5
        let patterns = try service.execute(query)
        #expect(patterns.report?.series?.first?.points.count == 5)
        #expect(patterns.report?.peak?.startDate == "2026-10-08" && patterns.report?.peak?.amount == 100)
        #expect(patterns.report?.peak?.contributors?.first?.amount == 100)
        let drilldown = try #require(patterns.report?.peak?.drilldownRequest)
        #expect(try service.execute(drilldown).records.map(\.title) == ["Hotel"])
        #expect(patterns.report?.frequentMerchants?.first?.title == "Cafe")
        query = request(.income, purpose: .incomeTimeline); query.periodUnit = .month
        let income = try service.execute(query)
        #expect(income.report?.series?.map { $0.points.first?.value } == [400, 500])
        #expect(income.records.allSatisfy { $0.amount == nil })
        #expect(metric("Total", income) == nil)
        query.periodUnit = .day; query.limit = 5
        let firstIncomePage = try #require(service.execute(query).presentation)
        #expect(firstIncomePage.pagination?.visibleCount == 5)
        let nextIncomePage = try service.loadMore(presentation: firstIncomePage)
        #expect(nextIncomePage.report?.series?.allSatisfy { $0.points.count == 10 } == true)
        #expect(nextIncomePage.records.allSatisfy { $0.amount == nil })
        query = request(.budgetSummary, purpose: .savingsTimeline); query.periodUnit = .month
        let outlook = try service.execute(query)
        #expect(outlook.report?.cumulative == true)
        #expect(outlook.report?.series?.first?.points.last?.value == metric("Actual savings", outlook))
        #expect(metric("Actual savings", outlook) == 303)
        #expect(outlook.report?.series?.last?.points.last?.value == 500)
        #expect(outlook.records.first?.amount == 303)
    }

    @Test func independentFutureExclusionCountsAndSnapshotsSurviveEncoding() throws {
        let (context, workspace, card) = try fixture()
        context.insert(VariableExpense(descriptionText: "Future debit", amount: 50, transactionDate: date(25), workspace: workspace, card: card))
        context.insert(PlannedExpense(title: "Future plan", plannedAmount: 20, expenseDate: date(25), workspace: workspace, card: card))
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context,
            homeContext: .init(dateRange: nil, excludeFuturePlannedExpensesFromCalculations: true, excludeFutureVariableExpensesFromCalculations: false), now: date(17))
        let result = try service.execute(request(.expenses, purpose: .cardSummary))
        #expect(result.report?.policy?.excludedPlannedCount == 1 && result.report?.policy?.excludedVariableCount == 0)
        #expect(metric("Total", result) == 50)
        var budgetQuery = request(.budgetSummary)
        #expect(metric("Total", try service.execute(budgetQuery)) == 50)
        budgetQuery.includeFuture = true
        let withFuture = try service.execute(budgetQuery)
        #expect(metric("Total", withFuture) == 70)
        #expect(withFuture.report?.policy?.excludedPlannedCount == 0)
        let encoded = try JSONEncoder().encode(result.presentation)
        #expect(try JSONDecoder().decode(MarinaPresentation?.self, from: encoded)?.report == result.report)
    }

    @Test func virtualUncategorizedAvailabilityAndEmptyAveragesStayExplicit() throws {
        let (context, workspace, card) = try fixture()
        context.insert(VariableExpense(descriptionText: "No category", amount: 25, transactionDate: date(10), workspace: workspace, card: card))
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: date(17))
        var query = request(.budgetSummary, purpose: .categoryAvailability)
        query.categoryID = "uncategorized"
        let result = try service.execute(query)
        let category = try #require(result.report?.categories?.first)
        #expect(category.id == "uncategorized" && category.variable == 25)
        #expect(category.maximum == nil && category.percentUsed == nil && category.status == "unlimited")
        #expect(metric("Count", result) == 1)
        query = request(.expenses); query.search = "No matching merchant"; query.metric = .average
        let empty = try service.execute(query)
        #expect(empty.status == "empty" && metric("Average per record", empty) == nil)
        #expect(empty.explanation?.contains("average is unavailable") == true)
    }

    @Test func legacySplitsAndLedgerKindsKeepGrossRecordedAndImpactDistinct() throws {
        let (context, workspace, card) = try fixture()
        let account = AllocationAccount(name: "Partner", workspace: workspace)
        let planned = PlannedExpense(title: "Legacy shared bill", plannedAmount: 100, actualAmount: 60,
            expenseDate: date(10), workspace: workspace, card: card)
        let adjustment = VariableExpense(descriptionText: "Adjustment", amount: 15,
            transactionDate: date(11), workspace: workspace, card: card)
        adjustment.kind = .adjustment
        context.insert(account); context.insert(planned); context.insert(adjustment)
        context.insert(ExpenseAllocation(allocatedAmount: 40, preservesGrossAmount: false,
            workspace: workspace, account: account, plannedExpense: planned))
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: date(17))
        var query = request(.expenses, purpose: .cardSummary); query.cardID = card.id.uuidString
        #expect(metric("Total", try service.execute(query)) == 60)
        query.purpose = nil; query.operation = .transactions; query.transactionFilter = .split
        let detail = try #require(service.execute(query).report?.transactions?.first)
        #expect(detail.grossAmount == 100 && detail.recordedAmount == 60 && detail.effectiveAmount == 100)
        #expect(detail.splitAmount == 40 && detail.budgetImpact == 60)
        query.transactionFilter = .adjustment; query.expenseMeasure = .ledger
        let ledger = try service.execute(query)
        #expect(metric("Total", ledger) == 15)
        #expect(ledger.report?.transactions?.first?.budgetImpact == 0)
    }

    @Test func categorySharesKeepTheRequestedCardAsTheirPopulation() throws {
        let (context, workspace, card) = try fixture()
        let other = Card(name: "Other", workspace: workspace)
        let dining = Category(name: "Dining", hexColor: "#123456", workspace: workspace)
        let travel = Category(name: "Travel", hexColor: "#654321", workspace: workspace)
        context.insert(other); context.insert(dining); context.insert(travel)
        for (title, amount, owner, category) in [("Meal", 40.0, card, dining), ("Hotel", 60.0, card, travel), ("Other", 900.0, other, travel)] {
            context.insert(VariableExpense(descriptionText: title, amount: amount, transactionDate: date(10), workspace: workspace, card: owner, category: category))
        }
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: date(17))
        var query = request(.expenses); query.cardID = card.id.uuidString
        query.operation = .ranking; query.grouping = .category; query.metric = .share
        let grouped = try service.execute(query)
        #expect(grouped.report?.groups?.first?.title == "Travel")
        #expect(metric(MarinaDataRequest.MetricFocus.share.metricLabel, grouped) == 60)
        query.operation = .summary; query.grouping = .none; query.categoryID = dining.id.uuidString
        #expect(metric(MarinaDataRequest.MetricFocus.share.metricLabel, try service.execute(query)) == 40)
        query.categoryID = nil
        #expect(metric(MarinaDataRequest.MetricFocus.share.metricLabel, try service.execute(query)) == 10)
    }

    @Test func distinctComparisonBudgetsUseTheirOwnDatesUnlessComparisonDatesAreExplicit() throws {
        let (context, workspace, card) = try fixture()
        let october = Budget(name: "October", startDate: date(1), endDate: date(31), workspace: workspace)
        let june = Budget(name: "June", startDate: date(1, month: 6), endDate: date(30, month: 6), workspace: workspace)
        context.insert(october); context.insert(june)
        context.insert(BudgetCardLink(budget: october, card: card)); context.insert(BudgetCardLink(budget: june, card: card))
        context.insert(VariableExpense(descriptionText: "October purchase", amount: 50, transactionDate: date(10), workspace: workspace, card: card))
        context.insert(VariableExpense(descriptionText: "June purchase", amount: 30, transactionDate: date(10, month: 6), workspace: workspace, card: card))
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: date(17))
        var query = request(.expenses); query.operation = .comparison; query.budgetID = october.id.uuidString
        query.comparisonFilter = .init(budgetID: june.id.uuidString)
        let result = try service.execute(query)
        #expect(result.status == "success" && metric("Total", result) == 50 && metric("Comparison total", result) == 30)
        #expect(result.resolvedRequest?.comparisonStartDate == "2026-06-01" && result.resolvedRequest?.comparisonEndDate == "2026-06-30")
        query.comparisonStartDate = "2026-06-20"; query.comparisonEndDate = "2026-08-31"
        let explicit = try service.execute(query)
        #expect(metric("Comparison total", explicit) == 0)
        #expect(explicit.resolvedRequest?.comparisonStartDate == "2026-06-20" && explicit.resolvedRequest?.comparisonEndDate == "2026-06-30")
        query.comparisonStartDate = "2026-05-01"; query.comparisonEndDate = "2026-05-31"
        #expect(try service.execute(query).status == "invalidRequest")
    }
}
