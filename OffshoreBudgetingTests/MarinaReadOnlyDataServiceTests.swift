import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
final class MarinaReadOnlyDataServiceTests {
    private var containers: [ModelContainer] = []

    private func context() throws -> ModelContext {
        let schema = Schema([Workspace.self, Budget.self, Card.self, BudgetCardLink.self, Category.self, Preset.self, BudgetPresetLink.self, BudgetCategoryLimit.self, PlannedExpense.self, VariableExpense.self, AllocationAccount.self, ExpenseAllocation.self, AllocationSettlement.self, SavingsAccount.self, SavingsLedgerEntry.self, ImportMerchantRule.self, AssistantAliasRule.self, IncomeSeries.self, Income.self, MarinaChatSession.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(
            "MarinaDataServiceFixture-\(UUID().uuidString)", schema: schema,
            isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        containers.append(container)
        return ModelContext(container)
    }
    private func date(_ day: Int, hour: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }
    private func total(_ result: MarinaDataResult) -> Double? { result.metrics.first { $0.label == "Total" }?.value }

    @Test func namedTargetRequirementsUseFreshWorkspaceScopedLookupCatalog() throws {
        let context = try context()
        let workspace = Workspace(name: "Personal", hexColor: "#FFFFFF")
        let other = Workspace(name: "Other", hexColor: "#000000")
        let category = Category(name: "Hair Care", hexColor: "#FFFFFF", workspace: workspace)
        let foreignCategory = Category(name: "Hair Care", hexColor: "#FFFFFF", workspace: other)
        let foreignCard = Card(name: "Foreign Card", workspace: other)
        context.insert(workspace); context.insert(other); context.insert(category)
        context.insert(foreignCategory); context.insert(foreignCard)
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: date(17))
        let current = try #require(service.namedTargetRequirements(prompt: "Show the Hair Care category").first)
        #expect(current.recordKind == "category" && !current.isAmbiguous)
        #expect(current.candidates.map(\.id) == [category.id.uuidString])
        let lookup = try service.execute(.init(tool: .findRecords, recordKind: "category", search: current.search))
        #expect(lookup.records.map(\.id) == current.candidates.map(\.id))
        let foreign = try service.namedTargetRequirements(prompt: "Show spending on Foreign Card")
        #expect(!foreign.flatMap(\.candidates).contains { $0.id == foreignCard.id.uuidString })

        category.name = "Salon"
        try context.save()
        #expect(try service.namedTargetRequirements(prompt: "Show the Hair Care category").flatMap(\.candidates).isEmpty)
        let renamed = try #require(service.namedTargetRequirements(prompt: "Show the Salon category").first)
        #expect(renamed.candidates.map(\.id) == [category.id.uuidString])
        context.delete(category)
        try context.save()
        #expect(try service.namedTargetRequirements(prompt: "Show the Salon category").flatMap(\.candidates).isEmpty)
    }

    @Test func accountDomainNameRequirementsAgreeWithFreshTypedLookupAndScopeValidation() throws {
        let context = try context()
        let workspace = Workspace(name: "Personal", hexColor: "#FFFFFF")
        let other = Workspace(name: "Other", hexColor: "#000000")
        let savings = SavingsAccount(name: "Alex", total: 1_000, workspace: workspace)
        let reconciliation = AllocationAccount(name: "Alex", workspace: workspace)
        let foreign = AllocationAccount(name: "Alex", workspace: other)
        context.insert(workspace); context.insert(other); context.insert(savings)
        context.insert(reconciliation); context.insert(foreign)
        context.insert(SavingsLedgerEntry(date: date(17), amount: 1_000, note: "Saved",
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue, workspace: workspace, account: savings))
        context.insert(AllocationSettlement(date: date(17), note: "Shared balance", amount: 25,
            workspace: workspace, account: reconciliation))
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: date(17))
        let required = try #require(service.namedTargetRequirements(
            prompt: "What is my current reconciliation balance with Alex?").first)
        #expect(required.recordKind == "reconciliationAccount" && !required.isAmbiguous)
        #expect(required.candidates.map(\.id) == [reconciliation.id.uuidString])
        let lookup = try service.execute(.init(tool: .findRecords, recordKind: required.recordKind, search: required.search))
        #expect(lookup.status == "success" && lookup.records.map(\.id) == [reconciliation.id.uuidString])
        let request = MarinaDataRequest(tool: .accounts, accountID: reconciliation.id.uuidString, scope: .reconciliation)
        #expect(required.includes(in: request))
        #expect(metric("Alex current reconciliation balance", try service.execute(request)) == 25)
        let wrongDomain = try service.execute(.init(tool: .accounts, accountID: savings.id.uuidString, scope: .reconciliation))
        #expect(wrongDomain.status == "invalidRequest" && wrongDomain.metrics.isEmpty)
        let saved = try #require(service.namedTargetRequirements(prompt: "Show savings balance in Alex").first)
        #expect(saved.recordKind == "savingsAccount" && saved.candidates.map(\.id) == [savings.id.uuidString])
    }

    #if canImport(FoundationModels)
    @Test func ambiguousLookupBlocksFinancialReadsUntilTheNextTurn() throws {
        let context = try context()
        let workspace = Workspace(name: "Personal", hexColor: "#FFFFFF")
        let card = Card(name: "Apple Card", workspace: workspace)
        context.insert(workspace); context.insert(card)
        context.insert(VariableExpense(descriptionText: "Apple", amount: 20, transactionDate: date(17), workspace: workspace, card: card))
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: date(17))
        let bridge = MarinaToolBridge()
        bridge.begin(service: service, onResult: {})
        var lookup = MarinaDataRequest(tool: .findRecords)
        lookup.search = "Apple"
        #expect(try bridge.call(lookup).contains("candidates"))
        let spending = MarinaDataRequest(tool: .expenses)
        #expect(try bridge.call(spending).contains("needsClarification"))
        #expect(bridge.requests.count == 1)
        bridge.end()
        bridge.begin(service: service, onResult: {})
        _ = try bridge.call(spending)
        let first = bridge.answer(id: UUID(), prompt: "Total", narration: "")
        let updated = bridge.answer(id: first.id, prompt: "Total", narration: "Updated narration")
        #expect(first.rows.map(\.id) == updated.rows.map(\.id))
        #expect(first.rows.contains { $0.title == "Total" && $0.amount == 20 })
        bridge.end()
        bridge.begin(service: service, onResult: {})
        var invalid = spending
        invalid.cardID = UUID().uuidString
        _ = try bridge.call(invalid)
        let errorAnswer = bridge.answer(id: UUID(), prompt: "Total", narration: "")
        #expect(errorAnswer.presentations?.isEmpty == true)
        #expect(!errorAnswer.rows.contains { $0.title == "Total" })
        bridge.end()
        #expect(throws: CancellationError.self) { try bridge.call(spending) }
    }
    #endif

    @Test func previousCalendarPeriodDoesNotIncludeThePriorMonthsExtraDay() throws {
        let context = try context()
        let workspace = Workspace(name: "Personal", hexColor: "#FFFFFF")
        context.insert(workspace)
        for (month, day, amount) in [(8, 31, 900.0), (9, 1, 10.0), (9, 30, 20.0), (10, 1, 800.0)] {
            let transactionDate = Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
            context.insert(VariableExpense(descriptionText: "Purchase", amount: amount, transactionDate: transactionDate, workspace: workspace))
        }
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: date(17))
        var request = MarinaDataRequest(tool: .expenses)
        request.relativePeriod = .previousPeriod
        #expect(total(try service.execute(request)) == 30)
        request.relativePeriod = .previousMonth
        #expect(total(try service.execute(request)) == 30)
    }

    @Test func isolatesWorkspaceRejectsForeignIdentifiersAndKeepsTotalsAcrossPages() throws {
        let context = try context()
        let selected = Workspace(name: "Personal", hexColor: "#FFFFFF")
        let other = Workspace(name: "Other", hexColor: "#FFFFFF")
        let card = Card(name: "Personal card", workspace: selected)
        let foreignCard = Card(name: "Other card", workspace: other)
        context.insert(selected); context.insert(other); context.insert(card); context.insert(foreignCard)
        for amount in [10.0, 20.0, 30.0] { context.insert(VariableExpense(descriptionText: "Coffee", amount: amount, transactionDate: date(17), workspace: selected, card: card)) }
        context.insert(VariableExpense(descriptionText: "Secret", amount: 999, transactionDate: date(17), workspace: other, card: foreignCard))
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: selected, modelContext: context, now: date(17))
        var request = MarinaDataRequest(tool: .expenses)
        request.limit = 1
        let first = try service.execute(request)
        #expect(total(first) == 60)
        #expect(first.totalCount == 3)
        #expect(first.records.count == 1)
        #expect(first.nextOffset == 1)
        request.offset = 1
        #expect(total(try service.execute(request)) == 60)
        request.cardID = foreignCard.id.uuidString
        #expect(try service.execute(request).status == "invalidRequest")
    }

    @Test func usesInclusiveDatesFreshFetchesAndExplicitFutureOverride() throws {
        let context = try context()
        let workspace = Workspace(name: "Personal", hexColor: "#FFFFFF")
        context.insert(workspace)
        context.insert(VariableExpense(descriptionText: "Late", amount: 20, transactionDate: date(18, hour: 23), workspace: workspace))
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, homeContext: .init(dateRange: nil, excludeFutureVariableExpensesFromCalculations: true), now: date(17))
        var request = MarinaDataRequest(tool: .expenses)
        request.startDate = "2026-10-18"; request.endDate = "2026-10-18"
        #expect(total(try service.execute(request)) == 0)
        request.includeFuture = true
        #expect(total(try service.execute(request)) == 20)
        context.insert(VariableExpense(descriptionText: "New", amount: 5, transactionDate: date(18), workspace: workspace))
        try context.save()
        #expect(total(try service.execute(request)) == 25)
        request.endDate = "2026-10-17"
        #expect(try service.execute(request).status == "invalidRequest")
    }

    @Test func differentiatesCreditsAdjustmentsAndUnrecordedPlannedExpenses() throws {
        let context = try context()
        let workspace = Workspace(name: "Personal", hexColor: "#FFFFFF")
        context.insert(workspace)
        context.insert(VariableExpense(descriptionText: "Debit", amount: 100, transactionDate: date(17), workspace: workspace))
        context.insert(VariableExpense(descriptionText: "Refund", amount: 20, kindRaw: VariableExpenseKind.credit.rawValue, transactionDate: date(17), workspace: workspace))
        context.insert(VariableExpense(descriptionText: "Adjustment", amount: 10, kindRaw: VariableExpenseKind.adjustment.rawValue, transactionDate: date(17), workspace: workspace))
        context.insert(PlannedExpense(title: "Unrecorded", plannedAmount: 50, expenseDate: date(17), workspace: workspace))
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: date(17))
        var request = MarinaDataRequest(tool: .expenses)
        #expect(total(try service.execute(request)) == 130)
        request.state = .actual
        #expect(total(try service.execute(request)) == 80)
        request.state = .all; request.scope = .variable; request.expenseMeasure = .spending
        #expect(total(try service.execute(request)) == 100)
        request.grouping = .category
        let grouped = try service.execute(request)
        #expect(grouped.records.count == 1)
        #expect(grouped.records.first?.title == "Uncategorized")
        #expect(grouped.metrics.first { $0.label == "Count" }?.value == 3)
    }

    @Test func returnsCandidatesForAmbiguousNamesAndNeverUsesMissingNamesAsAllData() throws {
        let context = try context()
        let workspace = Workspace(name: "Personal", hexColor: "#FFFFFF")
        context.insert(workspace)
        context.insert(Card(name: "Apple Card", workspace: workspace))
        context.insert(VariableExpense(descriptionText: "Apple", amount: 100, transactionDate: date(17), workspace: workspace))
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: date(17))
        var request = MarinaDataRequest(tool: .findRecords)
        request.search = "Apple"
        let candidates = try service.execute(request)
        #expect(candidates.status == "candidates")
        #expect(Set(candidates.records.map(\.kind)) == ["card", "merchant"])
        request.tool = .expenses; request.search = "Missing merchant"
        #expect(total(try service.execute(request)) == 0)
        #expect(try service.execute(request).status == "empty")
    }

    @Test func namedLookupRespectsRecordKindAndPreservesUnresolvedAmbiguity() throws {
        let context = try context()
        let workspace = Workspace(name: "Personal", hexColor: "#FFFFFF")
        let card = Card(name: "Apple", workspace: workspace)
        let savings = SavingsAccount(name: "Apple", workspace: workspace)
        let reconciliation = AllocationAccount(name: "Apple", workspace: workspace)
        context.insert(workspace); context.insert(card); context.insert(savings); context.insert(reconciliation)
        context.insert(VariableExpense(descriptionText: "Apple", amount: 20, transactionDate: date(17), workspace: workspace, card: card))
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: date(17))
        var request = MarinaDataRequest(tool: .findRecords)
        request.search = "Apple"
        let ambiguous = try service.execute(request)
        #expect(ambiguous.status == "candidates")
        #expect(ambiguous.totalCount == 4)
        #expect(Set(ambiguous.records.map(\.kind)) == ["card", "merchant", "savingsAccount", "reconciliationAccount"])

        for (kind, id) in [("card", card.id.uuidString), ("merchant", "Apple"),
                           ("savingsAccount", savings.id.uuidString), ("reconciliationAccount", reconciliation.id.uuidString)] {
            request.recordKind = kind
            let selected = try service.execute(request)
            #expect(selected.status == "success")
            #expect(selected.totalCount == 1)
            #expect(selected.records.map(\.id) == [id])
            #expect(selected.records.map(\.kind) == [kind])
        }

        let duplicate = Card(name: "Apple", workspace: workspace)
        context.insert(duplicate)
        try context.save()
        request.recordKind = "card"
        let sameKindAmbiguity = try service.execute(request)
        #expect(sameKindAmbiguity.status == "candidates")
        #expect(Set(sameKindAmbiguity.records.map(\.id)) == [card.id.uuidString, duplicate.id.uuidString])
        #expect(sameKindAmbiguity.records.allSatisfy { $0.kind == "card" })
        request.search = "Missing card"
        let missing = try service.execute(request)
        #expect(missing.status == "empty")
        #expect(missing.records.isEmpty)
    }

    @Test func unknownRecordKindsAreInvalidForNamedAndInventoryLookups() throws {
        let context = try context()
        let workspace = Workspace(name: "Personal", hexColor: "#FFFFFF")
        context.insert(workspace)
        context.insert(Card(name: "Apple", workspace: workspace))
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: date(17))
        for kind in ["", "cards", "Card", "unknown"] {
            for search: String? in [nil, "Apple"] {
                var request = MarinaDataRequest(tool: .findRecords)
                request.recordKind = kind
                request.search = search
                let result = try service.execute(request)
                #expect(result.status == "invalidRequest")
                #expect(result.records.isEmpty && result.metrics.isEmpty)
                #expect(result.presentation == nil)
            }
        }
    }

    @Test func accountSelectionsMustMatchRequestedKindWithoutFallingBackToOtherAccounts() throws {
        let context = try context()
        let workspace = Workspace(name: "Personal", hexColor: "#FFFFFF")
        let savings = SavingsAccount(name: "Shared", workspace: workspace)
        let reconciliation = AllocationAccount(name: "Shared", workspace: workspace)
        context.insert(workspace); context.insert(savings); context.insert(reconciliation)
        context.insert(SavingsLedgerEntry(date: date(17), amount: 30, note: "Saved", kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue, workspace: workspace, account: savings))
        context.insert(AllocationSettlement(date: date(17), note: "Shared activity", amount: -7, workspace: workspace, account: reconciliation))
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: date(17))
        let cases: [(UUID, MarinaDataRequest.Scope, MarinaDataRequest.Scope, String, Double)] = [
            (savings.id, .savings, .reconciliation, "savingsLedgerEntry", 30),
            (reconciliation.id, .reconciliation, .savings, "reconciliationItem", -7)
        ]
        for (id, matchingScope, wrongScope, kind, amount) in cases {
            var request = MarinaDataRequest(tool: .accounts)
            request.accountID = id.uuidString
            request.scope = wrongScope
            let wrongKind = try service.execute(request)
            #expect(wrongKind.status == "invalidRequest")
            #expect(wrongKind.records.isEmpty && wrongKind.metrics.isEmpty)
            #expect(wrongKind.presentation == nil)
            for scope in [matchingScope, .all] {
                request.scope = scope
                let selected = try service.execute(request)
                #expect(selected.status == "success")
                #expect(selected.records.map(\.kind) == [kind])
                #expect(metric("Selected period activity total", selected) == amount)
            }
        }
        for scope: MarinaDataRequest.Scope in [.planned, .variable] {
            var request = MarinaDataRequest(tool: .accounts)
            request.scope = scope
            #expect(try service.execute(request).status == "invalidRequest")
        }
    }

    @Test func namedLookupsAndAccountSelectionsStayInsideTheCurrentWorkspace() throws {
        let context = try context()
        let selected = Workspace(name: "Personal", hexColor: "#FFFFFF")
        let other = Workspace(name: "Other", hexColor: "#000000")
        let card = Card(name: "Shared", workspace: selected)
        let foreignCard = Card(name: "Shared", workspace: other)
        let savings = SavingsAccount(name: "Shared", workspace: selected)
        let foreignSavings = SavingsAccount(name: "Shared", workspace: other)
        let reconciliation = AllocationAccount(name: "Shared", workspace: selected)
        let foreignReconciliation = AllocationAccount(name: "Shared", workspace: other)
        context.insert(selected); context.insert(other); context.insert(card); context.insert(foreignCard)
        context.insert(savings); context.insert(foreignSavings); context.insert(reconciliation); context.insert(foreignReconciliation)
        context.insert(VariableExpense(descriptionText: "Foreign merchant", amount: 900001, transactionDate: date(17), workspace: other, card: foreignCard))
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: selected, modelContext: context, now: date(17))
        var lookup = MarinaDataRequest(tool: .findRecords)
        lookup.search = "Shared"
        let candidates = try service.execute(lookup)
        #expect(candidates.status == "candidates")
        #expect(Set(candidates.records.map(\.id)) == [card.id.uuidString, savings.id.uuidString, reconciliation.id.uuidString])
        for (kind, id) in [("card", card.id.uuidString), ("savingsAccount", savings.id.uuidString), ("reconciliationAccount", reconciliation.id.uuidString)] {
            lookup.recordKind = kind
            #expect(try service.execute(lookup).records.map(\.id) == [id])
        }
        lookup.recordKind = "merchant"
        lookup.search = "Foreign merchant"
        #expect(try service.execute(lookup).status == "empty")
        for id in [foreignSavings.id, foreignReconciliation.id] {
            for scope: MarinaDataRequest.Scope in [.all, .savings, .reconciliation] {
                var request = MarinaDataRequest(tool: .accounts)
                request.accountID = id.uuidString
                request.scope = scope
                let result = try service.execute(request)
                #expect(result.status == "invalidRequest")
                #expect(result.records.isEmpty && result.metrics.isEmpty)
                #expect(result.presentation == nil)
            }
        }
    }

    private func metric(_ label: String, _ result: MarinaDataResult) -> Double? {
        result.metrics.first { $0.label == label }?.value
    }

    @Test func grossPlannedAndOwnedImpactStayDistinctWithAllocationsAndSavingsOffsets() throws {
        let context = try context()
        let workspace = Workspace(name: "Personal", hexColor: "#FFFFFF")
        let account = AllocationAccount(name: "Alex", workspace: workspace)
        let savings = SavingsAccount(workspace: workspace)
        let planned = PlannedExpense(title: "Shared bill", plannedAmount: 100, expenseDate: date(17), workspace: workspace)
        let allocation = ExpenseAllocation(allocatedAmount: 40, workspace: workspace, account: account, plannedExpense: planned)
        let variable = VariableExpense(descriptionText: "Saved purchase", amount: 80, transactionDate: date(17), workspace: workspace)
        let offset = SavingsLedgerEntry(date: date(17), amount: -30, note: "Offset", kindRaw: SavingsLedgerEntryKind.expenseOffset.rawValue,
                                       workspace: workspace, account: savings, variableExpense: variable)
        context.insert(workspace); context.insert(account); context.insert(savings)
        context.insert(planned); context.insert(allocation); context.insert(variable); context.insert(offset)
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: date(17))
        var request = MarinaDataRequest(tool: .expenses)
        #expect(total(try service.execute(request)) == 110)
        request.expenseMeasure = .planned
        #expect(total(try service.execute(request)) == 100)
        request.scope = .variable; request.expenseMeasure = .ledger
        #expect(total(try service.execute(request)) == 80)
    }

    @Test func budgetFilteringRequiresSourceLinkedCardAndInclusiveBudgetDates() throws {
        let context = try context()
        let workspace = Workspace(name: "Personal", hexColor: "#FFFFFF")
        let card = Card(name: "Linked", workspace: workspace)
        let other = Card(name: "Unlinked", workspace: workspace)
        let budget = Budget(name: "Trip", startDate: date(10), endDate: date(20), workspace: workspace)
        context.insert(workspace); context.insert(card); context.insert(other); context.insert(budget)
        context.insert(BudgetCardLink(budget: budget, card: card))
        context.insert(VariableExpense(descriptionText: "Inside", amount: 10, transactionDate: date(20, hour: 23), workspace: workspace, card: card))
        context.insert(VariableExpense(descriptionText: "Outside", amount: 1000, transactionDate: date(21), workspace: workspace, card: card))
        context.insert(PlannedExpense(title: "Generated", plannedAmount: 20, expenseDate: date(10, hour: 0), workspace: workspace, card: card, sourceBudgetID: budget.id))
        context.insert(PlannedExpense(title: "Not generated here", plannedAmount: 2000, expenseDate: date(17), workspace: workspace, card: card))
        context.insert(PlannedExpense(title: "Wrong card", plannedAmount: 3000, expenseDate: date(17), workspace: workspace, card: other, sourceBudgetID: budget.id))
        context.insert(PlannedExpense(title: "Orphan", plannedAmount: 4000, expenseDate: date(17), workspace: workspace, card: card, sourceBudgetID: UUID()))
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: date(21))
        var request = MarinaDataRequest(tool: .expenses)
        request.budgetID = budget.id.uuidString; request.startDate = "2026-10-01"; request.endDate = "2026-10-31"
        #expect(total(try service.execute(request)) == 30)
        request.tool = .budgetSummary
        let summary = try service.execute(request)
        #expect(metric("Projected spending", summary) == 30)
        #expect(metric("Spending pace difference", summary) == 10)
    }

    @Test func categoryAvailabilityUsesSharedAggregatorAndIncludesUncappedCategories() throws {
        let context = try context()
        let workspace = Workspace(name: "Personal", hexColor: "#FFFFFF")
        let food = Category(name: "Food", hexColor: "#FFFFFF", workspace: workspace)
        let uncapped = Category(name: "Travel", hexColor: "#FFFFFF", workspace: workspace)
        let budget = Budget(name: "October", startDate: date(1), endDate: date(31), workspace: workspace)
        let expense = VariableExpense(descriptionText: "Food", amount: 120, transactionDate: date(17), workspace: workspace, category: food)
        context.insert(workspace); context.insert(food); context.insert(uncapped); context.insert(budget); context.insert(expense)
        context.insert(BudgetCategoryLimit(maxAmount: 100, budget: budget, category: food))
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: date(17))
        let result = try service.execute(.init(tool: .budgetSummary))
        #expect(metric("Categories over limit", result) == 1)
        #expect(result.records.first { $0.title == "Food" }?.amount == -20)
        #expect(result.records.first { $0.title == "Travel" }?.detail?.contains("unlimited") == true)
    }

    @Test func accountBalancesAndPeriodActivityUseFullLedgerBeforePagination() throws {
        let context = try context()
        let workspace = Workspace(name: "Personal", hexColor: "#FFFFFF")
        let savings = SavingsAccount(total: 9999, workspace: workspace)
        let account = AllocationAccount(name: "Alex", workspace: workspace)
        let expense = VariableExpense(descriptionText: "Shared", amount: 100, transactionDate: date(17), workspace: workspace)
        context.insert(workspace); context.insert(savings); context.insert(account); context.insert(expense)
        context.insert(SavingsLedgerEntry(date: date(1), amount: 100, note: "Saved", kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue, workspace: workspace, account: savings))
        context.insert(SavingsLedgerEntry(date: date(17), amount: -10, note: "Withdrawal", kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue, workspace: workspace, account: savings))
        context.insert(ExpenseAllocation(allocatedAmount: 40, workspace: workspace, account: account, expense: expense))
        context.insert(AllocationSettlement(date: date(18), note: "Paid", amount: -15, workspace: workspace, account: account))
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: date(19))
        var request = MarinaDataRequest(tool: .accounts)
        request.accountID = savings.id.uuidString; request.startDate = "2026-10-17"; request.endDate = "2026-10-18"
        let saved = try service.execute(request)
        #expect(metric("Savings Account current balance", saved) == 90)
        #expect(metric("Selected period activity total", saved) == -10)
        let savedPresentation = try #require(saved.presentation)
        #expect(savedPresentation.operation == .transactions && savedPresentation.title == "Account activity")
        #expect(savedPresentation.records.count == 1)
        #expect(savedPresentation.records.first?.kind == "savingsLedgerEntry")
        #expect(savedPresentation.records.first?.amount == -10)
        #expect(savedPresentation.metrics.contains { $0.label == "Savings Account current balance" && $0.value == 90 })
        var selectedPeriod = request
        selectedPeriod.startDate = nil; selectedPeriod.endDate = nil
        selectedPeriod.relativePeriod = .selectedPeriod
        #expect(metric("Selected period activity total", try service.execute(selectedPeriod)) == 90)
        selectedPeriod.relativePeriod = .previousPeriod
        #expect(metric("Selected period activity total", try service.execute(selectedPeriod)) == 0)
        request.accountID = account.id.uuidString; request.limit = 1
        let reconciliation = try service.execute(request)
        #expect(metric("Alex current reconciliation balance", reconciliation) == 25)
        #expect(metric("Selected period activity total", reconciliation) == 25)
        #expect(reconciliation.totalCount == 2)
        #expect(reconciliation.records.count == 1)
        #expect(reconciliation.explanation?.contains("positive reconciliation balance means money is owed to you") == true)
        let firstActivity = try #require(reconciliation.presentation)
        #expect(firstActivity.operation == .transactions && firstActivity.title == "Account activity")
        #expect(firstActivity.records.count == 1 && firstActivity.totalCount == 2)
        #expect(firstActivity.records.first?.kind == "reconciliationItem" && firstActivity.records.first?.amount == -15)
        #expect(firstActivity.metrics.contains { $0.label == "Alex current reconciliation balance" && $0.value == 25 })
        #expect(firstActivity.pagination?.workspaceID == workspace.id)
        #expect(firstActivity.pagination?.request.accountID == account.id.uuidString)
        #expect(firstActivity.pagination?.request.startDate == "2026-10-17")
        #expect(firstActivity.pagination?.request.endDate == "2026-10-18")
        let allActivity = try #require(service.loadMore(presentation: firstActivity).presentation)
        #expect(allActivity.id == firstActivity.id && allActivity.operation == .transactions)
        #expect(allActivity.records.count == 2 && allActivity.totalCount == 2)
        #expect(Set(allActivity.records.map(\.kind)) == ["expenseAllocation", "reconciliationItem"])
        #expect(Set(allActivity.records.compactMap(\.amount)) == [40, -15])
        #expect(allActivity.metrics == firstActivity.metrics)
        #expect(allActivity.pagination == nil)
        #expect(MarinaPresentationDisplayPolicy.shouldShow(allActivity, after: [allActivity]))
    }

    @Test func accountInventoryPresentationsPreserveFullBalancesAndPageAccountRows() throws {
        let context = try context()
        let workspace = Workspace(name: "Personal", hexColor: "#FFFFFF")
        let other = Workspace(name: "Other", hexColor: "#000000")
        let savings = SavingsAccount(name: "Saved", total: 9999, workspace: workspace)
        context.insert(workspace); context.insert(other); context.insert(savings)
        context.insert(SavingsLedgerEntry(date: date(17), amount: 2000, note: "Saved amount",
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue, workspace: workspace, account: savings))
        var accountIDs: Set<String> = []
        for index in 1...7 {
            let account = AllocationAccount(name: "Shared \(index)", workspace: workspace)
            accountIDs.insert(account.id.uuidString)
            context.insert(account)
            context.insert(AllocationSettlement(date: date(17), note: "Activity", amount: Double(index),
                workspace: workspace, account: account))
        }
        let foreign = AllocationAccount(name: "Foreign", workspace: other)
        context.insert(foreign)
        context.insert(AllocationSettlement(date: date(17), note: "Foreign activity", amount: 900001,
            workspace: other, account: foreign))
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: date(19))
        for scope: MarinaDataRequest.Scope in [.reconciliation, .all] {
            var request = MarinaDataRequest(tool: .accounts)
            request.scope = scope
            request.limit = 5
            let first = try #require(service.execute(request).presentation)
            let expectedCount = scope == .all ? 8 : 7
            #expect(first.operation == .inventory && first.title == "Account balances")
            #expect(first.records.count == 5 && first.totalCount == expectedCount)
            #expect(first.metrics.count == expectedCount)
            for index in 1...7 {
                #expect(first.metrics.contains { $0.label == "Shared \(index) current reconciliation balance" && $0.value == Double(index) })
            }
            #expect(first.metrics.contains { $0.label == "Saved current balance" && $0.value == 2000 } == (scope == .all))
            #expect(!first.metrics.contains { $0.value == 900001 })
            #expect(first.pagination?.workspaceID == workspace.id)
            #expect(first.pagination?.request.scope == scope && first.pagination?.request.accountID == nil)
            let complete = try #require(service.loadMore(presentation: first).presentation)
            let expectedIDs = scope == .all ? accountIDs.union([savings.id.uuidString]) : accountIDs
            #expect(complete.id == first.id && complete.operation == .inventory)
            #expect(complete.records.count == expectedCount && complete.totalCount == expectedCount)
            #expect(Set(complete.records.map(\.id)) == expectedIDs)
            #expect(complete.records.allSatisfy { ["savingsAccount", "reconciliationAccount"].contains($0.kind) })
            #expect(complete.metrics == first.metrics)
            #expect(complete.pagination == nil)
            #expect(MarinaPresentationDisplayPolicy.shouldShow(complete, after: [complete]))
        }
    }

    @Test func comparisonsSharesAndEmptyCalendarPeriodsAreCalculatedByTools() throws {
        let context = try context()
        let workspace = Workspace(name: "Personal", hexColor: "#FFFFFF")
        let card = Card(name: "One", workspace: workspace)
        let other = Card(name: "Two", workspace: workspace)
        context.insert(workspace); context.insert(card); context.insert(other)
        context.insert(VariableExpense(descriptionText: "One", amount: 60, transactionDate: date(17), workspace: workspace, card: card))
        context.insert(VariableExpense(descriptionText: "Two", amount: 40, transactionDate: date(17), workspace: workspace, card: other))
        try context.save()
        let service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: date(17))
        var request = MarinaDataRequest(tool: .expenses)
        request.cardID = card.id.uuidString; request.comparisonFilter = .init(cardID: other.id.uuidString)
        let compared = try service.execute(request)
        #expect(metric("Difference", compared) == 20)
        #expect(metric("Share of unfiltered period total percent", compared) == 60)
        request.comparisonFilter = nil; request.periodUnit = .month
        request.startDate = "2026-09-01"; request.endDate = "2026-10-31"
        let averaged = try service.execute(request)
        #expect(metric("Average per month", averaged) == 30)
        #expect(averaged.records.count == 2)
        #expect(averaged.records.first?.amount == 0)
    }

}
