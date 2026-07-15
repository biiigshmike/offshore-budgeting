import Foundation
import SwiftData

@testable import Offshore

@MainActor
struct MarinaFoundationModelDeviceFixture {
  let modelContext: ModelContext
  let workspace: Workspace
  let currentRange: HomeQueryDateRange
  let now: Date

  func dataCounts() throws -> [String: Int] {
    [
      "workspaces": try modelContext.fetchCount(FetchDescriptor<Workspace>()),
      "budgets": try modelContext.fetchCount(FetchDescriptor<Budget>()),
      "budgetCategoryLimits": try modelContext.fetchCount(FetchDescriptor<BudgetCategoryLimit>()),
      "budgetCardLinks": try modelContext.fetchCount(FetchDescriptor<BudgetCardLink>()),
      "budgetPresetLinks": try modelContext.fetchCount(FetchDescriptor<BudgetPresetLink>()),
      "cards": try modelContext.fetchCount(FetchDescriptor<Card>()),
      "categories": try modelContext.fetchCount(FetchDescriptor<Offshore.Category>()),
      "presets": try modelContext.fetchCount(FetchDescriptor<Preset>()),
      "plannedExpenses": try modelContext.fetchCount(FetchDescriptor<PlannedExpense>()),
      "variableExpenses": try modelContext.fetchCount(FetchDescriptor<VariableExpense>()),
      "incomes": try modelContext.fetchCount(FetchDescriptor<Income>()),
      "incomeSeries": try modelContext.fetchCount(FetchDescriptor<IncomeSeries>()),
      "allocationAccounts": try modelContext.fetchCount(FetchDescriptor<AllocationAccount>()),
      "expenseAllocations": try modelContext.fetchCount(FetchDescriptor<ExpenseAllocation>()),
      "allocationSettlements": try modelContext.fetchCount(FetchDescriptor<AllocationSettlement>()),
      "savingsAccounts": try modelContext.fetchCount(FetchDescriptor<SavingsAccount>()),
      "savingsEntries": try modelContext.fetchCount(FetchDescriptor<SavingsLedgerEntry>()),
      "importMerchantRules": try modelContext.fetchCount(FetchDescriptor<ImportMerchantRule>()),
      "assistantAliasRules": try modelContext.fetchCount(FetchDescriptor<AssistantAliasRule>()),
      "chatSessions": try modelContext.fetchCount(FetchDescriptor<MarinaChatSession>()),
    ]
  }

  /// A read-only snapshot used only for equality. It is intentionally never
  /// attached to reports because it contains the fixed fixture's record data.
  func dataStateFingerprint() throws -> String {
    var rows = try dataCounts().map { "count|\($0.key)|\($0.value)" }

    rows += try modelContext.fetch(FetchDescriptor<Workspace>()).map {
      "workspace|\($0.id.uuidString)|\($0.name)|\($0.hexColor)"
    }
    rows += try modelContext.fetch(FetchDescriptor<Budget>()).map {
      "budget|\($0.id.uuidString)|\($0.name)|\($0.startDate.timeIntervalSinceReferenceDate)|\($0.endDate.timeIntervalSinceReferenceDate)|\($0.workspace?.id.uuidString ?? "nil")"
    }
    rows += try modelContext.fetch(FetchDescriptor<Card>()).map {
      "card|\($0.id.uuidString)|\($0.name)|\($0.theme)|\($0.effect)|\($0.workspace?.id.uuidString ?? "nil")"
    }
    rows += try modelContext.fetch(FetchDescriptor<BudgetCardLink>()).map {
      "budgetCardLink|\($0.id.uuidString)|\($0.budget?.id.uuidString ?? "nil")|\($0.card?.id.uuidString ?? "nil")"
    }
    rows += try modelContext.fetch(FetchDescriptor<BudgetPresetLink>()).map {
      "budgetPresetLink|\($0.id.uuidString)|\($0.budget?.id.uuidString ?? "nil")|\($0.preset?.id.uuidString ?? "nil")"
    }
    rows += try modelContext.fetch(FetchDescriptor<Offshore.Category>()).map {
      "category|\($0.id.uuidString)|\($0.name)|\($0.hexColor)|\($0.isArchived)|\($0.archivedAt?.timeIntervalSinceReferenceDate.description ?? "nil")|\($0.workspace?.id.uuidString ?? "nil")"
    }
    rows += try modelContext.fetch(FetchDescriptor<BudgetCategoryLimit>()).map {
      "categoryLimit|\($0.id.uuidString)|\($0.minAmount?.description ?? "nil")|\($0.maxAmount?.description ?? "nil")|\($0.budget?.id.uuidString ?? "nil")|\($0.category?.id.uuidString ?? "nil")"
    }
    rows += try modelContext.fetch(FetchDescriptor<Preset>()).map {
      "preset|\($0.id.uuidString)|\($0.title)|\($0.plannedAmount)|\($0.frequencyRaw)|\($0.interval)|\($0.weeklyWeekday)|\($0.monthlyDayOfMonth)|\($0.monthlyIsLastDay)|\($0.yearlyMonth)|\($0.yearlyDayOfMonth)|\($0.isArchived)|\($0.archivedAt?.timeIntervalSinceReferenceDate.description ?? "nil")|\($0.workspace?.id.uuidString ?? "nil")|\($0.defaultCard?.id.uuidString ?? "nil")|\($0.defaultCategory?.id.uuidString ?? "nil")"
    }
    rows += try modelContext.fetch(FetchDescriptor<PlannedExpense>()).map {
      "plannedExpense|\($0.id.uuidString)|\($0.title)|\($0.plannedAmount)|\($0.actualAmount)|\($0.expenseDate.timeIntervalSinceReferenceDate)|\($0.workspace?.id.uuidString ?? "nil")|\($0.card?.id.uuidString ?? "nil")|\($0.category?.id.uuidString ?? "nil")|\($0.sourcePresetID?.uuidString ?? "nil")|\($0.sourceBudgetID?.uuidString ?? "nil")"
    }
    rows += try modelContext.fetch(FetchDescriptor<VariableExpense>()).map {
      "variableExpense|\($0.id.uuidString)|\($0.descriptionText)|\($0.amount)|\($0.kindRaw)|\($0.transactionDate.timeIntervalSinceReferenceDate)|\($0.workspace?.id.uuidString ?? "nil")|\($0.card?.id.uuidString ?? "nil")|\($0.category?.id.uuidString ?? "nil")"
    }
    rows += try modelContext.fetch(FetchDescriptor<Income>()).map {
      "income|\($0.id.uuidString)|\($0.source)|\($0.amount)|\($0.date.timeIntervalSinceReferenceDate)|\($0.isPlanned)|\($0.isException)|\($0.workspace?.id.uuidString ?? "nil")|\($0.series?.id.uuidString ?? "nil")|\($0.card?.id.uuidString ?? "nil")"
    }
    rows += try modelContext.fetch(FetchDescriptor<IncomeSeries>()).map {
      "incomeSeries|\($0.id.uuidString)|\($0.source)|\($0.amount)|\($0.isPlanned)|\($0.frequencyRaw)|\($0.interval)|\($0.weeklyWeekday)|\($0.monthlyDayOfMonth)|\($0.monthlyIsLastDay)|\($0.yearlyMonth)|\($0.yearlyDayOfMonth)|\($0.startDate.timeIntervalSinceReferenceDate)|\($0.endDate.timeIntervalSinceReferenceDate)|\($0.workspace?.id.uuidString ?? "nil")"
    }
    rows += try modelContext.fetch(FetchDescriptor<AllocationAccount>()).map {
      "allocationAccount|\($0.id.uuidString)|\($0.name)|\($0.hexColor)|\($0.isArchived)|\($0.archivedAt?.timeIntervalSinceReferenceDate.description ?? "nil")|\($0.workspace?.id.uuidString ?? "nil")"
    }
    rows += try modelContext.fetch(FetchDescriptor<ExpenseAllocation>()).map {
      "expenseAllocation|\($0.id.uuidString)|\($0.allocatedAmount)|\($0.preservesGrossAmount)|\($0.createdAt.timeIntervalSinceReferenceDate)|\($0.updatedAt.timeIntervalSinceReferenceDate)|\($0.workspace?.id.uuidString ?? "nil")|\($0.account?.id.uuidString ?? "nil")|\($0.expense?.id.uuidString ?? "nil")|\($0.plannedExpense?.id.uuidString ?? "nil")"
    }
    rows += try modelContext.fetch(FetchDescriptor<AllocationSettlement>()).map {
      "allocationSettlement|\($0.id.uuidString)|\($0.date.timeIntervalSinceReferenceDate)|\($0.note)|\($0.amount)|\($0.workspace?.id.uuidString ?? "nil")|\($0.account?.id.uuidString ?? "nil")|\($0.expense?.id.uuidString ?? "nil")|\($0.plannedExpense?.id.uuidString ?? "nil")"
    }
    rows += try modelContext.fetch(FetchDescriptor<SavingsAccount>()).map {
      "savingsAccount|\($0.id.uuidString)|\($0.name)|\($0.total)|\($0.didBackfillHistory)|\($0.autoCaptureThroughDate?.timeIntervalSinceReferenceDate.description ?? "nil")|\($0.createdAt.timeIntervalSinceReferenceDate)|\($0.updatedAt.timeIntervalSinceReferenceDate)|\($0.workspace?.id.uuidString ?? "nil")"
    }
    rows += try modelContext.fetch(FetchDescriptor<SavingsLedgerEntry>()).map {
      "savingsEntry|\($0.id.uuidString)|\($0.date.timeIntervalSinceReferenceDate)|\($0.amount)|\($0.note)|\($0.kindRaw)|\($0.linkedAllocationSettlementID?.uuidString ?? "nil")|\($0.periodStartDate?.timeIntervalSinceReferenceDate.description ?? "nil")|\($0.periodEndDate?.timeIntervalSinceReferenceDate.description ?? "nil")|\($0.createdAt.timeIntervalSinceReferenceDate)|\($0.updatedAt.timeIntervalSinceReferenceDate)|\($0.workspace?.id.uuidString ?? "nil")|\($0.account?.id.uuidString ?? "nil")|\($0.variableExpense?.id.uuidString ?? "nil")|\($0.plannedExpense?.id.uuidString ?? "nil")"
    }
    rows += try modelContext.fetch(FetchDescriptor<ImportMerchantRule>()).map {
      "importRule|\($0.id.uuidString)|\($0.merchantKey)|\($0.preferredName ?? "nil")|\($0.preferredCategory?.id.uuidString ?? "nil")|\($0.workspace?.id.uuidString ?? "nil")|\($0.createdAt.timeIntervalSinceReferenceDate)|\($0.updatedAt.timeIntervalSinceReferenceDate)"
    }
    rows += try modelContext.fetch(FetchDescriptor<AssistantAliasRule>()).map {
      "aliasRule|\($0.id.uuidString)|\($0.aliasKey)|\($0.targetValue)|\($0.entityTypeRaw)|\($0.workspace?.id.uuidString ?? "nil")|\($0.createdAt.timeIntervalSinceReferenceDate)|\($0.updatedAt.timeIntervalSinceReferenceDate)"
    }
    rows += try modelContext.fetch(FetchDescriptor<MarinaChatSession>()).map {
      "chatSession|\($0.id.uuidString)|\($0.title)|\($0.hasCustomTitle)|\($0.visibleAnswersData.base64EncodedString())|\($0.followUpContextData.base64EncodedString())|\($0.workspace?.id.uuidString ?? "nil")|\($0.createdAt.timeIntervalSinceReferenceDate)|\($0.updatedAt.timeIntervalSinceReferenceDate)|\($0.lastOpenedAt.timeIntervalSinceReferenceDate)"
    }

    return rows.sorted().joined(separator: "\n")
  }

  static func make(includeSentinelWorkspace: Bool = true) throws
    -> MarinaFoundationModelDeviceFixture
  {
    let schema = Schema([
      Workspace.self,
      Budget.self,
      BudgetCategoryLimit.self,
      Card.self,
      BudgetCardLink.self,
      BudgetPresetLink.self,
      Category.self,
      Preset.self,
      PlannedExpense.self,
      VariableExpense.self,
      AllocationAccount.self,
      ExpenseAllocation.self,
      AllocationSettlement.self,
      SavingsAccount.self,
      SavingsLedgerEntry.self,
      ImportMerchantRule.self,
      AssistantAliasRule.self,
      MarinaChatSession.self,
      IncomeSeries.self,
      Income.self,
    ])
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: configuration)
    let context = ModelContext(container)

    let now = try date(2026, 4, 20)
    let currentRange = HomeQueryDateRange(
      startDate: try date(2026, 4, 1),
      endDate: try date(2026, 4, 30)
    )
    let previousRange = HomeQueryDateRange(
      startDate: try date(2026, 3, 1),
      endDate: try date(2026, 3, 31)
    )

    let workspace = Workspace(name: "Evaluation Workspace", hexColor: "#3B82F6")
    let card = Card(
      name: "Evaluation Card",
      theme: "ruby",
      effect: "plastic",
      workspace: workspace
    )
    let groceries = Category(name: "Groceries", hexColor: "#22C55E", workspace: workspace)
    let dining = Category(name: "Dining", hexColor: "#F97316", workspace: workspace)
    let housing = Category(name: "Housing", hexColor: "#8B5CF6", workspace: workspace)

    let currentBudget = Budget(
      name: "April Evaluation Budget",
      startDate: currentRange.startDate,
      endDate: currentRange.endDate,
      workspace: workspace
    )
    let previousBudget = Budget(
      name: "March Evaluation Budget",
      startDate: previousRange.startDate,
      endDate: previousRange.endDate,
      workspace: workspace
    )

    let currentCardLink = BudgetCardLink(budget: currentBudget, card: card)
    let previousCardLink = BudgetCardLink(budget: previousBudget, card: card)
    let groceriesLimit = BudgetCategoryLimit(
      maxAmount: 300, budget: currentBudget, category: groceries)
    let diningLimit = BudgetCategoryLimit(maxAmount: 200, budget: currentBudget, category: dining)
    let housingLimit = BudgetCategoryLimit(
      maxAmount: 1_200, budget: currentBudget, category: housing)
    let previousGroceriesLimit = BudgetCategoryLimit(
      maxAmount: 100, budget: previousBudget, category: groceries)
    let groceriesExpense = VariableExpense(
      descriptionText: "Evaluation Groceries",
      amount: 120,
      transactionDate: try date(2026, 4, 8),
      workspace: workspace,
      card: card,
      category: groceries
    )
    let diningExpense = VariableExpense(
      descriptionText: "Evaluation Dining",
      amount: 80,
      transactionDate: try date(2026, 4, 12),
      workspace: workspace,
      card: card,
      category: dining
    )
    let previousGroceriesExpense = VariableExpense(
      descriptionText: "Previous Month Groceries",
      amount: 140,
      transactionDate: try date(2026, 3, 10),
      workspace: workspace,
      card: card,
      category: groceries
    )
    let rent = PlannedExpense(
      title: "Evaluation Rent",
      plannedAmount: 900,
      expenseDate: try date(2026, 4, 25),
      workspace: workspace,
      card: card,
      category: housing,
      sourceBudgetID: currentBudget.id
    )
    let plannedIncome = Income(
      source: "Evaluation Salary",
      amount: 4_000,
      date: try date(2026, 4, 1),
      isPlanned: true,
      workspace: workspace,
      card: card
    )
    let actualIncome = Income(
      source: "Evaluation Salary",
      amount: 3_200,
      date: try date(2026, 4, 5),
      isPlanned: false,
      workspace: workspace,
      card: card
    )

    context.insert(workspace)
    context.insert(card)
    context.insert(groceries)
    context.insert(dining)
    context.insert(housing)
    context.insert(currentBudget)
    context.insert(previousBudget)
    context.insert(currentCardLink)
    context.insert(previousCardLink)
    context.insert(groceriesLimit)
    context.insert(diningLimit)
    context.insert(housingLimit)
    context.insert(previousGroceriesLimit)
    context.insert(groceriesExpense)
    context.insert(diningExpense)
    context.insert(previousGroceriesExpense)
    context.insert(rent)
    context.insert(plannedIncome)
    context.insert(actualIncome)

    let savings = SavingsAccount(name: "Evaluation Savings", total: 800, workspace: workspace)
    context.insert(savings)
    context.insert(
      SavingsLedgerEntry(
        date: try date(2026, 4, 2),
        amount: 800,
        note: "Evaluation opening balance",
        kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
        workspace: workspace,
        account: savings
      ))

    // High-value records in every query domain make an accidental
    // cross-Workspace read observable without changing production behavior.
    // The isolated expected-answer fixture omits these records so numeric
    // contamination also changes the exact answer/evidence signatures.
    if includeSentinelWorkspace {
      let otherWorkspace = Workspace(name: "Workspace Leak Sentinel Workspace", hexColor: "#EF4444")
      let otherCard = Card(name: "Workspace Leak Sentinel Card", workspace: otherWorkspace)
      let otherCategory = Category(
        name: "Workspace Leak Sentinel Category",
        hexColor: "#EF4444",
        workspace: otherWorkspace
      )
      let otherBudget = Budget(
        name: "Workspace Leak Sentinel Budget",
        startDate: currentRange.startDate,
        endDate: currentRange.endDate,
        workspace: otherWorkspace
      )
      let otherPreset = Preset(
        title: "Workspace Leak Sentinel Preset",
        plannedAmount: 99_999,
        workspace: otherWorkspace,
        defaultCard: otherCard,
        defaultCategory: otherCategory
      )
      let otherSavings = SavingsAccount(
        name: "Workspace Leak Sentinel Savings",
        total: 99_999,
        workspace: otherWorkspace
      )
      let otherReconciliation = AllocationAccount(
        name: "Workspace Leak Sentinel Reconciliation",
        workspace: otherWorkspace
      )
      let otherIncomeSeries = IncomeSeries(
        source: "Workspace Leak Sentinel Income Series",
        amount: 99_999,
        isPlanned: true,
        frequencyRaw: RecurrenceFrequency.monthly.rawValue,
        interval: 1,
        weeklyWeekday: 1,
        monthlyDayOfMonth: 1,
        monthlyIsLastDay: false,
        yearlyMonth: 1,
        yearlyDayOfMonth: 1,
        startDate: currentRange.startDate,
        endDate: currentRange.endDate,
        workspace: otherWorkspace
      )
      context.insert(otherWorkspace)
      context.insert(otherCard)
      context.insert(otherCategory)
      context.insert(otherBudget)
      context.insert(BudgetCardLink(budget: otherBudget, card: otherCard))
      context.insert(
        BudgetCategoryLimit(maxAmount: 1, budget: otherBudget, category: otherCategory))
      context.insert(otherPreset)
      context.insert(BudgetPresetLink(budget: otherBudget, preset: otherPreset))
      context.insert(
        VariableExpense(
          descriptionText: "Workspace Leak Sentinel",
          amount: 99_999,
          transactionDate: try date(2026, 4, 8),
          workspace: otherWorkspace,
          card: otherCard,
          category: otherCategory
        ))
      context.insert(
        PlannedExpense(
          title: "Workspace Leak Sentinel Planned Expense",
          plannedAmount: 99_999,
          expenseDate: try date(2026, 4, 9),
          workspace: otherWorkspace,
          card: otherCard,
          category: otherCategory,
          sourcePresetID: otherPreset.id,
          sourceBudgetID: otherBudget.id
        ))
      context.insert(
        Income(
          source: "Workspace Leak Sentinel Actual Income",
          amount: 99_999,
          date: try date(2026, 4, 5),
          isPlanned: false,
          workspace: otherWorkspace,
          card: otherCard
        ))
      context.insert(
        Income(
          source: "Workspace Leak Sentinel Planned Income",
          amount: 99_999,
          date: try date(2026, 4, 1),
          isPlanned: true,
          workspace: otherWorkspace,
          card: otherCard
        ))
      context.insert(otherIncomeSeries)
      context.insert(otherSavings)
      context.insert(
        SavingsLedgerEntry(
          date: try date(2026, 4, 2),
          amount: 99_999,
          note: "Workspace Leak Sentinel Savings Entry",
          kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
          workspace: otherWorkspace,
          account: otherSavings
        ))
      context.insert(otherReconciliation)
      context.insert(
        AllocationSettlement(
          date: try date(2026, 4, 3),
          note: "Workspace Leak Sentinel Settlement",
          amount: 99_999,
          workspace: otherWorkspace,
          account: otherReconciliation
        ))
    }

    try context.save()
    return MarinaFoundationModelDeviceFixture(
      modelContext: context,
      workspace: workspace,
      currentRange: currentRange,
      now: now
    )
  }

  private static func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .autoupdatingCurrent
    guard let value = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
      throw MarinaFoundationModelDeviceFixtureError.invalidDate(year: year, month: month, day: day)
    }
    return value
  }
}

private enum MarinaFoundationModelDeviceFixtureError: Error {
  case invalidDate(year: Int, month: Int, day: Int)
}
