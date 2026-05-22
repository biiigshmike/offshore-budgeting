import Foundation

enum MarinaMetricContractID: String, Codable, Equatable, CaseIterable, Sendable {
    case periodOverview
    case safeSpendRemaining
    case safeSpendToday
    case forecastSavings
    case periodCashFlow
    case spendingIncreaseDrivers
    case spendTrendSummary
    case largestTransactions
    case mostFrequentTransactions
    case categoryOverPace
    case upcomingExpensesBeforeNextIncome
    case nextPlannedExpense
    case plannedVsActualSpend
    case unrecordedPlannedExpenses
    case unusualMerchantSpend
    case recurringExpenseIncrease
    case subscriptionSpend
    case budgetSavingsSummary
    case budgetIncomeSummary
    case budgetExpenseMix
    case budgetLinkedCardSpend
    case budgetLinkedPresetForecast
    case budgetCategoryLimitStatus
    case budgetOverlapImpact
    case budgetDeletionImpactPreview
    case reconciliationOwedThisMonth
    case reconciliationBalance
    case reconciliationPeriodActivity
    case reconciliationSettlementHistory
    case reconciliationUnsettledItems
    case reconciliationCategoryMix
    case allocatedCategorySpend
    case allocationGrossVsOwnedImpact
    case trueOwnedSpend
    case grossVsOwnedSpendBridge
    case cardSpendTotal
    case cardLedgerSummary
    case cardBudgetImpactSummary
    case cardPlannedVsActual
    case cardCategoryMix
    case cardMerchantMix
    case cardOverspendingDriver
    case cardFutureCommitments
    case cardCreditRefundImpact
    case cardDeletionImpactPreview
    case categorySpendSummary
    case categoryTrend
    case categoryMerchantDrivers
    case categoryCutImpact
    case skipCategoryScenario
    case incomeActualVsExpected
    case incomeBySource
    case incomeTimingVariance
    case incomeAverageActual
    case incomeSourceShare
    case savingsRunningTotal
    case savingsPeriodMovement
    case savingsAdjustmentTotal
    case savingsOffsetUsage
    case savingsTrackVsLastMonth
    case savingsLedgerByKind
    case budgetSharedLinks
    case categorizationReview
    case presetDueSoon
    case presetHighestCost
    case presetBudgetCoverage
    case presetActualVariance
    case presetSchedulePreview
    case presetArchiveImpact
    case presetDeletionImpactPreview
    case sinceLastCheckIn
}

enum MarinaMetricContractSupport: String, Codable, Equatable, Sendable {
    case executable
    case partial
    case contractOnly
    case missing
}

struct MarinaMetricSlotContract: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let role: MarinaResolvedTargetRole
    let allowedEntityTypes: [MarinaCandidateEntityTypeHint]
    let isRequired: Bool
    let relationship: MarinaRelationshipField

    init(
        _ id: String,
        role: MarinaResolvedTargetRole,
        allowedEntityTypes: [MarinaCandidateEntityTypeHint],
        isRequired: Bool,
        relationship: MarinaRelationshipField
    ) {
        self.id = id
        self.role = role
        self.allowedEntityTypes = allowedEntityTypes
        self.isRequired = isRequired
        self.relationship = relationship
    }
}

struct MarinaMetricContract: Codable, Equatable, Identifiable, Sendable {
    let id: MarinaMetricContractID
    let seedPrompt: String
    let formulaName: String
    let acceptedSubjects: [MarinaSubject]
    let acceptedOperations: [MarinaCandidateOperation]
    let requiredInputs: [MarinaMetricSlotContract]
    let optionalInputs: [MarinaMetricSlotContract]
    let sourceModels: [String]
    let amountBasis: MarinaFinancialAmountBasis?
    let amountBasisDescription: String
    let dateRangeBehavior: String
    let legalJoins: [String]
    let ambiguityRules: [String]
    let neverSilentlySubstituteRules: [String]
    let responseShape: MarinaResponseShapeHint
    let supportStatus: MarinaMetricContractSupport
    let missingExecutorPolicy: String
    let regressionFixtureIdea: String
    let workspaceScope: String

    var stableID: String { id.rawValue }
}

struct MarinaMetricContractResolution: Equatable, Sendable {
    enum Match: String, Equatable, Sendable {
        case seedPrompt
        case formulaPhrase
        case formulaMetadata
        case routeIntent
        case semanticShape
    }

    let contract: MarinaMetricContract
    let match: Match

    var shouldBlockExecution: Bool {
        switch contract.supportStatus {
        case .executable:
            return false
        case .partial, .contractOnly, .missing:
            return match == .seedPrompt || match == .formulaPhrase || match == .semanticShape || match == .routeIntent
        }
    }

    var isDirectFormulaSummon: Bool {
        match == .formulaPhrase
    }
}

struct MarinaMetricContractRegistry {
    static let current = MarinaMetricContractRegistry(contracts: makeContracts())

    let contracts: [MarinaMetricContract]

    func contract(for id: MarinaMetricContractID) -> MarinaMetricContract? {
        contracts.first { $0.id == id }
    }

    func contract(forSeedPrompt prompt: String) -> MarinaMetricContract? {
        let normalizedPrompt = normalized(prompt)
        return contracts.first { normalized($0.seedPrompt) == normalizedPrompt }
    }

    func contract(forFormulaPhrase prompt: String) -> MarinaMetricContract? {
        let normalizedPrompt = normalized(prompt)
        let compactPrompt = normalizedPrompt.replacingOccurrences(of: " ", with: "")
        return contracts.first { contract in
            formulaPhraseVariants(for: contract).contains { variant in
                normalizedPrompt == variant
                    || normalizedPrompt.hasPrefix("\(variant) ")
                    || normalizedPrompt.hasSuffix(" \(variant)")
                    || normalizedPrompt.contains(" \(variant) ")
                    || compactPrompt.contains(variant.replacingOccurrences(of: " ", with: ""))
            }
        }
    }

    private static func makeContracts() -> [MarinaMetricContract] {
        let seedContracts: [MarinaMetricContract] = [
            contract(.safeSpendRemaining, seed: "How much can I safely spend for the rest of this month?", formula: "safeSpendRemaining", subjects: [.budgets], operations: [.lookupDetails, .forecast], required: [], optional: [slot("budget", .filter, [.budget], .budget)], sources: ["Budget", "Income", "PlannedExpense", "VariableExpense", "SavingsLedgerEntry"], basis: .budgetImpact, date: "Current selected period through period end; not a per-day answer unless the contract explicitly asks for safe-spend today.", joins: ["Budget date range to workspace rows", "SavingsLedgerEntry linked offsets by expense when present"], ambiguity: ["Clarify active budget if overlapping budgets both cover the period."], never: ["Do not substitute savings account balance.", "Do not answer with Safe Spend Today for a rest-of-period question."], shape: .summaryCard, status: .executable, missing: "Executable through the rest-of-period safe-spend contract executor.", fixture: "Same savings balance but different upcoming planned expenses changes the answer."),
            contract(.spendingIncreaseDrivers, seed: "Why is my spending higher this month than last month?", formula: "spendingIncreaseDrivers", subjects: [.variableExpenses, .plannedExpenses], operations: [.compare], required: [], optional: [slot("grouping", .groupingDimension, [.category, .merchant, .card, .transaction], .unknown)], sources: ["VariableExpense", "PlannedExpense"], basis: .budgetImpact, date: "Primary current period plus explicit comparison period, defaulting to previous matching period only when requested.", joins: ["Expenses joined to category, merchant text, and card for driver grouping."], ambiguity: ["Clarify whether the user wants category, merchant, card, or transaction drivers when not inferable."], never: ["Do not collapse to a scalar month comparison.", "Do not use ledger-signed totals for driver ranking."], shape: .rankedList, status: .executable, missing: "Executable through the category delta-driver contract executor.", fixture: "Total delta is +300, but one category contributes +250 and must be visible."),
            contract(.categoryOverPace, seed: "What categories are over pace for this point in the month?", formula: "categoryLimitBurnRate", subjects: [.variableExpenses, .budgets], operations: [.rank, .simulate], required: [], optional: [slot("category", .filter, [.category], .category)], sources: ["Budget", "BudgetCategoryLimit", "VariableExpense", "PlannedExpense"], basis: .budgetImpact, date: "Budget/current period from start through today, projected to inclusive period end.", joins: ["BudgetCategoryLimit by active budget and category", "Expense category within workspace and period"], ambiguity: ["A named category can execute through the burn-rate recipe; broad category ranking needs its own executor."], never: ["Do not use gross ledger amount.", "Do not treat categories without max limits as over-pace."], shape: .rankedList, status: .executable, missing: "Executable through broad category over-pace ranking.", fixture: "A split expense gross 100 allocated 60 must pace on owned budget impact."),
            contract(.upcomingExpensesBeforeNextIncome, seed: "What upcoming expenses will hit before my next income?", formula: "upcomingExpensesBeforeNextIncome", subjects: [.plannedExpenses, .income], operations: [.listRows], required: [], optional: [slot("card", .filter, [.card], .card)], sources: ["PlannedExpense", "Income"], basis: .budgetImpact, date: "Starts now and ends at the next planned or actual income date.", joins: ["PlannedExpense date compared with next Income date"], ambiguity: ["Clarify whether planned or actual income should define next income if both exist on different dates."], never: ["Do not list all upcoming expenses.", "Do not treat IncomeSeries rules as received income."], shape: .rankedList, status: .executable, missing: "Executable when a next Income row exists; otherwise asks for income setup.", fixture: "A bill after payday must be excluded."),
            contract(.plannedVsActualSpend, seed: "What did I plan to spend versus what I actually spent?", formula: "plannedVsActualSpend", subjects: [.plannedExpenses, .variableExpenses], operations: [.compare], required: [], optional: [slot("category", .filter, [.category], .category), slot("card", .filter, [.card], .card)], sources: ["PlannedExpense", "VariableExpense"], basis: .budgetImpact, date: "Selected period; planned side uses planned projected amount, actual side uses recorded actual/budget-impact rows.", joins: ["Optional category/card filters across planned and variable rows."], ambiguity: ["Clarify spend vs income if the prompt mentions income."], never: ["Do not answer with income planned-vs-actual.", "Do not treat PlannedExpense.actualAmount == 0 as actual zero."], shape: .comparison, status: .executable, missing: "Executable through the spend-specific planned-vs-actual executor.", fixture: "Planned spend 500 and actual spend 350 while income planned-vs-actual is unrelated."),
            contract(.unrecordedPlannedExpenses, seed: "Which planned expenses have no actual transaction yet?", formula: "unrecordedPlannedExpenses", subjects: [.plannedExpenses], operations: [.listRows], required: [], optional: [slot("category", .filter, [.category], .category), slot("card", .filter, [.card], .card)], sources: ["PlannedExpense", "VariableExpense"], basis: .budgetImpact, date: "Selected period or future window; planned rows remain candidates while actualAmount is zero and no linked actual exists.", joins: ["Optional matching between planned title/date/card and actual transaction only after explicit policy exists."], ambiguity: ["Clarify matching policy if the user asks for fuzzy transaction matching."], never: ["Do not treat actualAmount == 0 as actual zero spend.", "Do not delete or mutate planned rows."], shape: .rankedList, status: .executable, missing: "Executable with the v1 actualAmount == 0 policy; fuzzy matching remains future work.", fixture: "One planned row with actualAmount 0 remains unrecorded while another with actualAmount > 0 is excluded."),
            contract(.unusualMerchantSpend, seed: "What merchants are unusually high this month?", formula: "unusualMerchantSpend", subjects: [.variableExpenses], operations: [.rank], required: [], optional: [slot("merchant", .filter, [.merchant], .merchant)], sources: ["VariableExpense"], basis: .budgetImpact, date: "Current period against completed baseline periods.", joins: ["Merchant text normalized from VariableExpense description/import merchant rules."], ambiguity: ["Clarify merchant vs card/category when a name collides."], never: ["Do not substitute category or card ranking.", "Do not use future planned rows."], shape: .rankedList, status: .executable, missing: "Executable with a deterministic prior-3-month merchant baseline.", fixture: "A merchant doubles while its category total stays flat."),
            contract(.recurringExpenseIncrease, seed: "What recurring expenses increased?", formula: "recurringChargeAnomaly", subjects: [.variableExpenses, .plannedExpenses], operations: [.rank], required: [], optional: [slot("merchant", .filter, [.merchant], .merchant), slot("preset", .filter, [.preset], .preset)], sources: ["VariableExpense", "PlannedExpense"], basis: .budgetImpact, date: "Current month against recent completed-month baseline.", joins: ["Repeated merchant text", "PlannedExpense actual-vs-planned variance"], ambiguity: ["Clarify subscriptions vs all recurring merchants when the user distinguishes them."], never: ["Do not answer as generic month comparison.", "Do not include one-off merchants without recurrence evidence."], shape: .rankedList, status: .executable, missing: "Executable through recurringChargeAnomaly recipe.", fixture: "StreamBox baseline 10 and current 25 appears as anomaly."),
            contract(.subscriptionSpend, seed: "How much did I spend on subscriptions this quarter?", formula: "subscriptionSpend", subjects: [.variableExpenses, .plannedExpenses, .presets], operations: [.sum], required: [], optional: [slot("category", .filter, [.category], .category), slot("preset", .filter, [.preset], .preset), slot("merchant", .filter, [.merchant], .merchant)], sources: ["VariableExpense", "PlannedExpense", "Preset", "ImportMerchantRule"], basis: .budgetImpact, date: "Explicit quarter range; defaults to current quarter only after date policy is set.", joins: ["Explicit subscription category/preset/merchant set to expense rows."], ambiguity: ["Ask what identifies subscriptions unless a stored category, preset, or merchant set is explicit."], never: ["Do not infer subscriptions from arbitrary merchant text.", "Do not substitute all recurring expenses."], shape: .scalarCurrency, status: .partial, missing: "Executes with a subscription category/preset identity; otherwise asks for setup.", fixture: "Category Subscriptions differs from merchant Apple; answer must not merge them silently."),
            contract(.reconciliationOwedThisMonth, seed: "What did Alejandro owe me this month?", formula: "reconciliationOwedThisMonth", subjects: [.reconciliationAccounts, .reconciliationItems], operations: [.sum], required: [slot("allocationAccount", .filter, [.allocationAccount], .allocationAccount, required: true)], optional: [], sources: ["AllocationAccount", "ExpenseAllocation", "AllocationSettlement"], basis: .reconciliationBalance, date: "Selected month for allocations plus signed settlements.", joins: ["ExpenseAllocation.account", "AllocationSettlement.account"], ambiguity: ["Clarify allocation account if the person name collides with merchant text."], never: ["Do not use savings ledger entries.", "Do not report gross expense spend as amount owed."], shape: .summaryCard, status: .executable, missing: "Executable when the reconciliation account resolves; otherwise asks for the account.", fixture: "Allocated 100 and settlement -40 yields owed 60."),
            contract(.allocatedCategorySpend, seed: "What had Alejandro spent on Cannabis?", formula: "allocatedCategorySpend", subjects: [.variableExpenses, .plannedExpenses, .reconciliationItems], operations: [.sum], required: [slot("allocationAccount", .filter, [.allocationAccount], .allocationAccount, required: true), slot("spendFilter", .filter, [.category, .merchant, .card, .preset, .transaction], .unknown, required: true)], optional: [], sources: ["ExpenseAllocation", "VariableExpense", "PlannedExpense", "AllocationAccount", "Category"], basis: .allocated, date: "Selected period, defaulting to current month in current executor.", joins: ["ExpenseAllocation.account", "ExpenseAllocation.expense or plannedExpense", "Linked expense category/card/merchant/preset"], ambiguity: ["If person name can be allocation account or merchant, ask instead of guessing."], never: ["Do not substitute gross category spend.", "Do not use reconciliation balance or savings as allocated spend."], shape: .scalarCurrency, status: .executable, missing: "Executable through composable allocated spend.", fixture: "Gross Cannabis spend is 100 but Alejandro allocation is 30, answer must be 30."),
            contract(.trueOwnedSpend, seed: "What is my true owned spend after splits and savings offsets?", formula: "trueOwnedSpend", subjects: [.variableExpenses, .plannedExpenses], operations: [.sum], required: [], optional: [slot("category", .filter, [.category], .category), slot("card", .filter, [.card], .card)], sources: ["VariableExpense", "PlannedExpense", "ExpenseAllocation", "SavingsLedgerEntry"], basis: .budgetImpact, date: "Selected period.", joins: ["Expense allocations and savings offset ledger entries linked to expenses."], ambiguity: ["Clarify gross vs owned if the user asks for both."], never: ["Do not use ledger-signed amount.", "Do not use gross amount.", "Do not include reconciliation settlements as savings."], shape: .scalarCurrency, status: .executable, missing: "Executable through the contract-first owned-spend executor.", fixture: "Gross 100 minus split 40 minus savings offset 20 leaves owned impact 40."),
            contract(.cardOverspendingDriver, seed: "Which card is driving the most overspending?", formula: "cardOverspendingDriver", subjects: [.cards, .variableExpenses, .plannedExpenses], operations: [.rank], required: [], optional: [slot("budget", .filter, [.budget], .budget)], sources: ["Card", "BudgetCardLink", "VariableExpense", "PlannedExpense", "BudgetCategoryLimit"], basis: .budgetImpact, date: "Current budget or selected period.", joins: ["Card to budget links and expense rows; baseline must come from budget/plan."], ambiguity: ["Ask for baseline if no budget or planned comparison is available."], never: ["Do not call raw card spend overspending.", "Do not use card display spend as budget variance."], shape: .rankedList, status: .executable, missing: "Executable when planned card baselines exist; otherwise asks for plan setup.", fixture: "Card A spends more but is under plan; Card B spends less but is over plan."),
            contract(.categoryCutImpact, seed: "What category would save me the most if I cut 20%?", formula: "categoryCutImpact", subjects: [.variableExpenses], operations: [.simulate, .rank], required: [slot("percentage", .simulationInput, [.category], .category, required: true)], optional: [], sources: ["VariableExpense", "PlannedExpense", "Category"], basis: .budgetImpact, date: "Selected period or remaining current period; percentage applies to category spend.", joins: ["Expense rows grouped by category."], ambiguity: ["Clarify whether the cut applies to current actuals, remaining forecast, or planned spend."], never: ["Do not treat 20% as $20.", "Do not mutate budgets or expenses."], shape: .rankedList, status: .executable, missing: "Executable through the percentage what-if ranking executor.", fixture: "Dining 500 cut 20% produces 100 impact."),
            contract(.skipCategoryScenario, seed: "If I skip restaurants for two weeks, where does my month land?", formula: "skipCategoryScenario", subjects: [.variableExpenses], operations: [.simulate, .forecast], required: [slot("category", .simulationInput, [.category, .merchant], .category, required: true)], optional: [], sources: ["VariableExpense", "PlannedExpense", "Income", "Budget"], basis: .budgetImpact, date: "Two-week horizon projected into current month.", joins: ["Category/merchant spend rate to budget forecast rows."], ambiguity: ["Clarify category vs merchant if restaurants is both a category and merchant text."], never: ["Do not delete planned expenses.", "Do not assume the scenario affects income."], shape: .summaryCard, status: .executable, missing: "Executable through the category/merchant skip scenario executor.", fixture: "Restaurants weekly rate changes projected month landing without mutating rows."),
            contract(.incomeActualVsExpected, seed: "How much income have I actually received versus expected?", formula: "incomeActualVsExpected", subjects: [.income], operations: [.sum, .compare], required: [], optional: [slot("incomeSource", .filter, [.incomeSource], .incomeSource)], sources: ["Income"], basis: .actualIncome, date: "Selected period; actual rows are isPlanned false and expected rows are isPlanned true.", joins: ["Optional income source text."], ambiguity: ["Clarify source if a source name collides."], never: ["Do not treat IncomeSeries as received income.", "Do not merge spending rows into income variance.", "Do not substitute planned income for actual income."], shape: .comparison, status: .executable, missing: "Executable through income planned-vs-actual summary.", fixture: "Expected 3000 and actual 2000 yields a -1000 gap."),
            contract(.savingsTrackVsLastMonth, seed: "Am I on track to save more than last month?", formula: "savingsTrackVsLastMonth", subjects: [.savingsLedgerEntries, .income, .variableExpenses, .plannedExpenses], operations: [.forecast, .compare], required: [], optional: [], sources: ["SavingsLedgerEntry", "Income", "VariableExpense", "PlannedExpense"], basis: .budgetImpact, date: "Current period forecast compared with previous period actual savings.", joins: ["Savings formula rows across income, expenses, and savings ledger entries."], ambiguity: ["Clarify actual savings vs projected savings when the prompt asks for both."], never: ["Do not use SavingsAccount.total alone.", "Do not revive reconciliation savings mirrors."], shape: .comparison, status: .executable, missing: "Executable through the forecast-vs-prior savings executor.", fixture: "Same account total but different period ledger entries yields different result."),
            contract(.budgetSharedLinks, seed: "Which budgets share the same card or preset?", formula: "budgetSharedLinks", subjects: [.budgets, .cards, .presets], operations: [.listRows], required: [], optional: [slot("budget", .filter, [.budget], .budget)], sources: ["Budget", "BudgetCardLink", "BudgetPresetLink", "Card", "Preset"], basis: nil, date: "All budgets or selected overlapping period.", joins: ["BudgetCardLink by card", "BudgetPresetLink by preset"], ambiguity: ["Clarify card-only vs preset-only if the user narrows the object type."], never: ["Do not infer shared links from expense card alone.", "Do not require budgets to be non-overlapping."], shape: .relationshipList, status: .executable, missing: "Executable through the budget link overlap executor.", fixture: "Two budgets share Apple Card, but only one shares Rent preset."),
            contract(.categorizationReview, seed: "Show expenses that look uncategorized or miscategorized.", formula: "categorizationReview", subjects: [.variableExpenses, .plannedExpenses], operations: [.listRows], required: [], optional: [slot("category", .filter, [.category], .category)], sources: ["VariableExpense", "PlannedExpense", "Category", "ImportMerchantRule"], basis: .budgetImpact, date: "Recent or selected period.", joins: ["Nil category rows and merchant-rule/category mismatch heuristics."], ambiguity: ["Clarify whether the user wants only uncategorized rows or heuristic miscategorized rows too."], never: ["Do not create a stored Uncategorized category.", "Do not recategorize automatically."], shape: .rankedList, status: .executable, missing: "Executable for nil-category rows and deterministic merchant-rule mismatches.", fixture: "Nil category row plus merchant-rule mismatch row must both be visible when heuristic support lands."),
            contract(.sinceLastCheckIn, seed: "What changed since my last check-in?", formula: "sinceLastCheckIn", subjects: [.variableExpenses, .plannedExpenses, .income, .savingsLedgerEntries, .reconciliationItems], operations: [.compare, .listRows], required: [], optional: [], sources: ["MarinaConversationStore", "VariableExpense", "PlannedExpense", "Income", "SavingsLedgerEntry", "ExpenseAllocation", "AllocationSettlement"], basis: .budgetImpact, date: "Since persisted check-in timestamp or snapshot.", joins: ["Check-in snapshot timestamp to changed workspace rows."], ambiguity: ["Ask for a starting point if no check-in snapshot exists."], never: ["Do not default to this-month changes.", "Do not use another workspace's check-in state."], shape: .summaryCard, status: .partial, missing: "Executes when a workspace check-in timestamp exists; otherwise asks to start tracking.", fixture: "Only rows after the saved check-in appear.")
        ]
        return seedContracts + expandedContracts()
    }

    private static func expandedContracts() -> [MarinaMetricContract] {
        [
            catalog(.periodOverview, seed: "Give me a budget overview for this month.", formula: "periodOverview", subjects: [.plannedExpenses, .variableExpenses], operations: [.lookupDetails], sources: ["PlannedExpense", "VariableExpense", "Category"], basis: .homeSpend, date: "Selected period, defaulting to the current month.", never: ["Do not use owned/budget-impact spend unless requested.", "Do not omit planned versus variable evidence."], shape: .summaryCard, fixture: "Planned and variable totals differ and both must be visible."),
            catalog(.safeSpendToday, seed: "How much is safe to spend today?", formula: "safeSpendToday", subjects: [.budgets], operations: [.forecast], sources: ["Budget", "Income", "PlannedExpense", "VariableExpense", "SavingsLedgerEntry"], basis: .budgetImpact, date: "Current selected period divided by inclusive days left.", never: ["Do not answer rest-of-period safe spend with this per-day value.", "Do not use savings account balance."], shape: .scalarCurrency, status: .contractOnly, fixture: "Rest-of-month room is 1000 while daily safe spend is 50."),
            catalog(.forecastSavings, seed: "What will I save by the end of this month?", formula: "forecastSavings", subjects: [.savingsLedgerEntries, .income, .plannedExpenses, .variableExpenses], operations: [.forecast], sources: ["Income", "PlannedExpense", "VariableExpense", "SavingsLedgerEntry"], basis: .budgetImpact, date: "Current period to date plus remaining planned income and expenses.", never: ["Do not use SavingsAccount.total alone.", "Do not include reconciliation settlement mirrors."], shape: .summaryCard, fixture: "Same savings total but different remaining planned expenses changes the forecast."),
            catalog(.periodCashFlow, seed: "What is my cash flow this month?", formula: "periodCashFlow", subjects: [.income, .plannedExpenses, .variableExpenses, .savingsLedgerEntries], operations: [.sum], sources: ["Income", "PlannedExpense", "VariableExpense", "SavingsLedgerEntry"], basis: .budgetImpact, date: "Selected period, defaulting to the current month.", never: ["Do not treat planned income as received income.", "Do not mix ledger gross spend with budget-impact spend."], shape: .summaryCard, fixture: "Actual income minus owned spend differs from ledger cash flow."),
            catalog(.spendTrendSummary, seed: "How is my spending trending lately?", formula: "spendTrendSummary", subjects: [.variableExpenses, .plannedExpenses], operations: [.trend], sources: ["VariableExpense", "PlannedExpense", "Category"], basis: .budgetImpact, date: "Recent completed periods plus current period to date.", never: ["Do not collapse a trend into one scalar total.", "Do not rank categories when the user asks for overall trend."], shape: .chartRows, fixture: "Three monthly totals show a rising trend even when current month is not highest."),
            catalog(.largestTransactions, seed: "What are my largest transactions this month?", formula: "largestTransactions", subjects: [.variableExpenses, .plannedExpenses], operations: [.rank], sources: ["VariableExpense", "PlannedExpense"], basis: .budgetImpact, date: "Selected period, defaulting to the current month.", never: ["Do not include unrecorded planned rows unless requested.", "Do not rank by gross when owned impact is requested."], shape: .rankedList, fixture: "A split transaction gross 500 but owned 100 must rank by chosen basis."),
            catalog(.mostFrequentTransactions, seed: "What transactions happen most often?", formula: "mostFrequentTransactions", subjects: [.variableExpenses, .plannedExpenses], operations: [.rank], sources: ["VariableExpense", "PlannedExpense"], basis: .count, date: "Selected recent period or explicit range.", never: ["Do not rank by amount.", "Do not merge unrelated merchants without normalized-key evidence."], shape: .rankedList, fixture: "Five small coffee rows outrank one large airline row."),
            catalog(.nextPlannedExpense, seed: "What is my next planned expense?", formula: "nextPlannedExpense", subjects: [.plannedExpenses], operations: [.lookupDetails], sources: ["PlannedExpense", "Preset"], basis: .plannedEffectiveAmount, date: "Next future planned expense from now unless a range is explicit.", never: ["Do not use preset templates when materialized planned rows exist.", "Do not include past planned expenses."], shape: .summaryCard, fixture: "A future planned row beats a higher-cost row after it."),

            catalog(.budgetSavingsSummary, seed: "How did this budget do on savings?", formula: "budgetSavingsSummary", subjects: [.budgets, .income, .plannedExpenses, .variableExpenses, .savingsLedgerEntries], operations: [.lookupDetails], required: [slot("budget", .primaryTarget, [.budget], .budget, required: true)], sources: ["Budget", "Income", "PlannedExpense", "VariableExpense", "SavingsLedgerEntry"], basis: .budgetImpact, date: "Inclusive budget start through end.", never: ["Do not use SavingsAccount.total.", "Do not ignore manual savings adjustments."], shape: .summaryCard, fixture: "Projected, max, and actual savings all differ."),
            catalog(.budgetIncomeSummary, seed: "What income is tied to this budget?", formula: "budgetIncomeSummary", subjects: [.budgets, .income], operations: [.sum], required: [slot("budget", .primaryTarget, [.budget], .budget, required: true)], sources: ["Budget", "Income"], basis: .actualIncome, date: "Inclusive budget start through end.", never: ["Do not use IncomeSeries as received income.", "Do not mix planned and actual without labeling both."], shape: .comparison, fixture: "Budget planned income is 3000 while actual income is 2200."),
            catalog(.budgetExpenseMix, seed: "What is the expense mix for this budget?", formula: "budgetExpenseMix", subjects: [.budgets, .plannedExpenses, .variableExpenses], operations: [.sum], required: [slot("budget", .primaryTarget, [.budget], .budget, required: true)], sources: ["Budget", "BudgetPlannedExpenseStore", "PlannedExpense", "VariableExpense"], basis: .budgetImpact, date: "Inclusive budget range with budget planned-expense scoping rules.", never: ["Do not include planned rows outside sourceBudgetID/link/date scope.", "Do not use card display spend."], shape: .groupedBreakdown, fixture: "Unlinked-card expense in the same date range is excluded."),
            catalog(.budgetLinkedCardSpend, seed: "How much did the linked cards spend in this budget?", formula: "budgetLinkedCardSpend", subjects: [.budgets, .cards, .variableExpenses], operations: [.sum], required: [slot("budget", .primaryTarget, [.budget], .budget, required: true)], sources: ["Budget", "BudgetCardLink", "Card", "VariableExpense"], basis: .budgetImpact, date: "Inclusive budget range.", never: ["Do not infer linked cards from expense card alone.", "Do not include unlinked cards in the same period."], shape: .rankedList, fixture: "Unlinked card has spend in range but must be excluded."),
            catalog(.budgetLinkedPresetForecast, seed: "What will linked presets cost in this budget?", formula: "budgetLinkedPresetForecast", subjects: [.budgets, .presets, .plannedExpenses], operations: [.forecast], required: [slot("budget", .primaryTarget, [.budget], .budget, required: true)], sources: ["Budget", "BudgetPresetLink", "Preset", "PlannedExpense"], basis: .plannedAmount, date: "Inclusive budget range.", never: ["Do not infer preset links from matching planned titles.", "Do not include archived presets unless asked."], shape: .rankedList, fixture: "Preset title matches a row but only linked preset counts."),
            catalog(.budgetCategoryLimitStatus, seed: "How are my budget category limits doing?", formula: "budgetCategoryLimitStatus", subjects: [.budgets, .categories], operations: [.lookupDetails], required: [slot("budget", .filter, [.budget], .budget)], sources: ["Budget", "BudgetCategoryLimit", "VariableExpense", "PlannedExpense"], basis: .budgetImpact, date: "Inclusive budget range or active budget.", never: ["Do not treat categories without limits as over budget.", "Do not use gross spend for max/min status."], shape: .rankedList, fixture: "Category is over on gross but under on owned impact."),
            catalog(.budgetOverlapImpact, seed: "Which budgets overlap this month?", formula: "budgetOverlapImpact", subjects: [.budgets], operations: [.listRows], sources: ["Budget", "BudgetRangeOverlap", "BudgetCardLink", "BudgetPresetLink"], basis: .dateWindow, date: "Explicit range or all budget ranges.", never: ["Do not assume overlapping budgets are invalid.", "Do not merge budgets with same name."], shape: .relationshipList, fixture: "Two overlapping budgets share dates but not cards."),
            catalog(.budgetDeletionImpactPreview, seed: "What would deleting this budget affect?", formula: "budgetDeletionImpactPreview", subjects: [.budgets], operations: [.lookupDetails], required: [slot("budget", .primaryTarget, [.budget], .budget, required: true)], sources: ["Budget", "BudgetCardLink", "BudgetPresetLink", "BudgetCategoryLimit", "PlannedExpense"], basis: .count, date: "All rows linked to the budget.", never: ["Do not delete anything during preview.", "Do not hide recorded generated planned expenses."], shape: .summaryCard, fixture: "Generated recorded planned rows are flagged, not deleted."),

            catalog(.cardSpendTotal, seed: "How much did I spend on this card?", formula: "cardSpendTotal", subjects: [.cards, .variableExpenses, .plannedExpenses], operations: [.sum], required: [slot("card", .primaryTarget, [.card], .card, required: true)], sources: ["Card", "VariableExpense", "PlannedExpense"], basis: .cardDisplaySpend, date: "Selected period, defaulting to the current month.", never: ["Do not use owned spend unless requested.", "Do not call card display spend overspending."], shape: .scalarCurrency, fixture: "Card display spend differs from budget impact because of splits."),
            catalog(.cardLedgerSummary, seed: "Show the ledger summary for this card.", formula: "cardLedgerSummary", subjects: [.cards, .variableExpenses], operations: [.sum], required: [slot("card", .primaryTarget, [.card], .card, required: true)], sources: ["Card", "VariableExpense"], basis: .ledgerSigned, date: "Selected period, defaulting to the current month.", never: ["Do not drop credits or adjustments.", "Do not use planned expenses in ledger-only summary."], shape: .summaryCard, fixture: "Debit, credit, and adjustment rows all produce different ledger lines."),
            catalog(.cardBudgetImpactSummary, seed: "What is this card's budget impact?", formula: "cardBudgetImpactSummary", subjects: [.cards, .variableExpenses, .plannedExpenses], operations: [.sum], required: [slot("card", .primaryTarget, [.card], .card, required: true)], sources: ["Card", "VariableExpense", "PlannedExpense", "ExpenseAllocation", "SavingsLedgerEntry"], basis: .budgetImpact, date: "Selected period, defaulting to the current month.", never: ["Do not use card display spend.", "Do not ignore splits or savings offsets."], shape: .summaryCard, fixture: "Same card total differs between display spend and budget impact."),
            catalog(.cardPlannedVsActual, seed: "What did this card plan versus actually spend?", formula: "cardPlannedVsActual", subjects: [.cards, .plannedExpenses, .variableExpenses], operations: [.compare], required: [slot("card", .primaryTarget, [.card], .card, required: true)], sources: ["Card", "PlannedExpense", "VariableExpense"], basis: .budgetImpact, date: "Selected period, defaulting to the current month.", never: ["Do not use income planned-vs-actual.", "Do not treat actualAmount zero as recorded actual zero."], shape: .comparison, fixture: "Card planned baseline is higher than actual spend."),
            catalog(.cardCategoryMix, seed: "What categories make up this card's spending?", formula: "cardCategoryMix", subjects: [.cards, .categories], operations: [.rank], required: [slot("card", .primaryTarget, [.card], .card, required: true)], sources: ["Card", "Category", "VariableExpense", "PlannedExpense"], basis: .cardDisplaySpend, date: "Selected period, defaulting to the current month.", never: ["Do not use budget-impact category mix unless requested.", "Do not hide uncategorized rows."], shape: .groupedBreakdown, fixture: "Uncategorized card row appears as virtual Uncategorized."),
            catalog(.cardMerchantMix, seed: "Which merchants are on this card?", formula: "cardMerchantMix", subjects: [.cards, .merchant], operations: [.rank], required: [slot("card", .primaryTarget, [.card], .card, required: true)], sources: ["Card", "VariableExpense", "MerchantNormalizer"], basis: .budgetImpact, date: "Selected period, defaulting to the current month.", never: ["Do not use planned preset names as merchants.", "Do not merge merchant and card names without clarification."], shape: .rankedList, fixture: "Merchant text matching card name asks for clarification."),
            catalog(.cardFutureCommitments, seed: "What future commitments are on this card?", formula: "cardFutureCommitments", subjects: [.cards, .plannedExpenses], operations: [.listRows], required: [slot("card", .primaryTarget, [.card], .card, required: true)], sources: ["Card", "PlannedExpense", "VariableExpense"], basis: .plannedAmount, date: "Now through explicit horizon or next 30 days.", never: ["Do not include past transactions.", "Do not mix future variable expenses without the future-variable policy."], shape: .rankedList, fixture: "Future planned row included while past planned row is excluded."),
            catalog(.cardCreditRefundImpact, seed: "How much did credits or refunds affect this card?", formula: "cardCreditRefundImpact", subjects: [.cards, .variableExpenses], operations: [.sum], required: [slot("card", .primaryTarget, [.card], .card, required: true)], sources: ["Card", "VariableExpense"], basis: .ledgerSigned, date: "Selected period, defaulting to the current month.", never: ["Do not count debit purchases.", "Do not convert credits to positive spend."], shape: .summaryCard, fixture: "Credit -40 and adjustment 10 are shown separately."),
            catalog(.cardDeletionImpactPreview, seed: "What would deleting this card affect?", formula: "cardDeletionImpactPreview", subjects: [.cards], operations: [.lookupDetails], required: [slot("card", .primaryTarget, [.card], .card, required: true)], sources: ["Card", "VariableExpense", "PlannedExpense", "Income", "BudgetCardLink", "Preset"], basis: .count, date: "All rows linked to the card.", never: ["Do not delete anything during preview.", "Do not summarize only spend when linked income or presets exist."], shape: .summaryCard, fixture: "Card has expenses, incomes, presets, and budget links affected."),

            catalog(.reconciliationBalance, seed: "What is Alejandro's reconciliation balance?", formula: "reconciliationBalance", subjects: [.reconciliationAccounts], operations: [.lookupDetails], required: [slot("allocationAccount", .primaryTarget, [.allocationAccount], .allocationAccount, required: true)], sources: ["AllocationAccount", "ExpenseAllocation", "AllocationSettlement"], basis: .reconciliationBalance, date: "All-history balance; period filters switch to activity.", never: ["Do not use SavingsAccount.total.", "Do not include savings ledger entries."], shape: .summaryCard, fixture: "Allocation 100 plus settlement -40 yields balance 60."),
            catalog(.reconciliationPeriodActivity, seed: "Show Alejandro's reconciliation activity this month.", formula: "reconciliationPeriodActivity", subjects: [.reconciliationAccounts, .reconciliationItems], operations: [.listRows], required: [slot("allocationAccount", .primaryTarget, [.allocationAccount], .allocationAccount, required: true)], sources: ["AllocationAccount", "ExpenseAllocation", "AllocationSettlement", "AllocationLedgerService"], basis: .reconciliationBalance, date: "Selected period, defaulting to the current month.", never: ["Do not collapse charges and settlements into savings movement.", "Do not lose signed settlement direction."], shape: .rankedList, fixture: "Charge 100 and settlement -40 both appear."),
            catalog(.reconciliationSettlementHistory, seed: "Show reconciliation settlements this month.", formula: "reconciliationSettlementHistory", subjects: [.reconciliationItems], operations: [.listRows], sources: ["AllocationSettlement", "AllocationAccount"], basis: .reconciliationSettlement, date: "Selected period, defaulting to the current month.", never: ["Do not infer settlements from savings ledger mirrors.", "Do not include allocation charges."], shape: .rankedList, fixture: "Standalone settlement appears without a linked expense."),
            catalog(.reconciliationUnsettledItems, seed: "Which shared charges are still unsettled?", formula: "reconciliationUnsettledItems", subjects: [.reconciliationItems], operations: [.listRows], required: [slot("allocationAccount", .filter, [.allocationAccount], .allocationAccount)], sources: ["ExpenseAllocation", "AllocationSettlement"], basis: .allocated, date: "Selected period or all open items.", never: ["Do not assert item-level unsettled status when settlements are account-level.", "Do not use savings offsets."], shape: .rankedList, status: .partial, fixture: "Account-level settlement triggers clarification for item-level unsettled status."),
            catalog(.reconciliationCategoryMix, seed: "What categories make up Alejandro's shared balance?", formula: "reconciliationCategoryMix", subjects: [.reconciliationAccounts, .categories], operations: [.rank], required: [slot("allocationAccount", .filter, [.allocationAccount], .allocationAccount)], sources: ["ExpenseAllocation", "VariableExpense", "PlannedExpense", "Category"], basis: .allocated, date: "Selected period, defaulting to the current month.", never: ["Do not use gross category spend.", "Do not count savings offsets."], shape: .groupedBreakdown, fixture: "Gross category spend differs from allocated category mix."),
            catalog(.allocationGrossVsOwnedImpact, seed: "How did splits change my owned spend?", formula: "allocationGrossVsOwnedImpact", subjects: [.variableExpenses, .plannedExpenses, .reconciliationItems], operations: [.compare], sources: ["VariableExpense", "PlannedExpense", "ExpenseAllocation", "SavingsLedgerEntry"], basis: .ownedSpend, date: "Selected period, defaulting to the current month.", never: ["Do not treat settlements as split reductions.", "Do not hide gross and allocated comparison rows."], shape: .summaryCard, fixture: "Gross 100, allocated 40, savings offset 20, owned impact 40."),

            catalog(.savingsRunningTotal, seed: "What is my savings running total?", formula: "savingsRunningTotal", subjects: [.savingsAccounts, .savingsLedgerEntries], operations: [.lookupDetails], sources: ["SavingsAccount", "SavingsLedgerEntry"], basis: .savingsRunningTotal, date: "All-history running total.", never: ["Do not use reconciliation balances.", "Do not treat a date range as account total."], shape: .summaryCard, fixture: "Running total persists outside the selected date range."),
            catalog(.savingsPeriodMovement, seed: "What savings movement happened this month?", formula: "savingsPeriodMovement", subjects: [.savingsLedgerEntries], operations: [.listRows], sources: ["SavingsLedgerEntry", "SavingsAccount"], basis: .savingsMovement, date: "Selected period, defaulting to the current month.", never: ["Do not include reconciliation settlement mirrors in normal savings answers.", "Do not use account total as movement."], shape: .rankedList, fixture: "Manual and period-close entries appear as movement rows."),
            catalog(.savingsAdjustmentTotal, seed: "How much did I manually adjust savings this month?", formula: "savingsAdjustmentTotal", subjects: [.savingsLedgerEntries], operations: [.sum], sources: ["SavingsLedgerEntry", "SavingsMathService"], basis: .savingsAdjustment, date: "Selected period, defaulting to the current month.", never: ["Manual adjustments only.", "Exclude period close, expense offset, and reconciliation settlement entries."], shape: .scalarCurrency, fixture: "Only manual -125 counts while offset -80 is excluded."),
            catalog(.savingsOffsetUsage, seed: "How much savings did I use to offset expenses?", formula: "savingsOffsetUsage", subjects: [.savingsLedgerEntries, .variableExpenses, .plannedExpenses], operations: [.sum], sources: ["SavingsLedgerEntry", "VariableExpense", "PlannedExpense"], basis: .savingsOffset, date: "Savings offset entry date in selected period.", never: ["Do not include manual adjustments.", "Display negative ledger offsets as positive offset usage."], shape: .rankedList, fixture: "Expense offset -80 displays as 80 used."),
            catalog(.savingsLedgerByKind, seed: "Break down savings by ledger kind.", formula: "savingsLedgerByKind", subjects: [.savingsLedgerEntries], operations: [.sum], sources: ["SavingsLedgerEntry"], basis: .savingsMovement, date: "Selected period, defaulting to the current month.", never: ["Do not merge ledger kinds.", "Do not revive reconciliation settlement mirrors as true savings."], shape: .groupedBreakdown, fixture: "Manual, period close, and expense offset are separate groups."),

            catalog(.incomeBySource, seed: "How much income came from each source?", formula: "incomeBySource", subjects: [.income, .incomeSource], operations: [.rank], sources: ["Income"], basis: .actualIncome, date: "Selected period, defaulting to the current month.", never: ["Default to actual income unless planned/expected is requested.", "Do not include IncomeSeries alone."], shape: .rankedList, status: .executable, missing: "Executable through the income-by-source aggregation contract.", fixture: "Actual income source rows exclude planned-only source rows."),
            catalog(.incomeTimingVariance, seed: "Which income was late or missing?", formula: "incomeTimingVariance", subjects: [.income, .incomeSource], operations: [.compare], sources: ["Income", "IncomeSeries"], basis: .actualIncome, date: "Selected period comparing planned dates to actual dates.", never: ["Do not fuzzy-match multiple same-source rows without a policy.", "Do not treat planned income as received income."], shape: .rankedList, status: .partial, fixture: "Two planned and two actual rows from same source require clarification."),
            catalog(.incomeAverageActual, seed: "What is my average actual income?", formula: "incomeAverageActual", subjects: [.income], operations: [.average], sources: ["Income"], basis: .actualIncome, date: "Explicit multi-period window or last completed periods.", never: ["Exclude planned income.", "Do not average IncomeSeries templates."], shape: .scalarCurrency, fixture: "Actual rows average differently from planned rows."),
            catalog(.incomeSourceShare, seed: "What share of income comes from each source?", formula: "incomeSourceShare", subjects: [.income, .incomeSource], operations: [.rank], sources: ["Income"], basis: .actualIncome, date: "Selected period, defaulting to the current month.", never: ["Denominator must match actual/planned status filter.", "Do not mix planned and actual silently."], shape: .rankedList, fixture: "Actual source share differs from planned source share."),

            catalog(.categorySpendSummary, seed: "How much did I spend by category?", formula: "categorySpendSummary", subjects: [.categories, .variableExpenses, .plannedExpenses], operations: [.rank], sources: ["Category", "VariableExpense", "PlannedExpense", "SavingsMathService"], basis: .budgetImpact, date: "Selected period, defaulting to the current month.", never: ["Do not use widget ledger/effective math for owned spend.", "Do not create a stored Uncategorized category."], shape: .rankedList, fixture: "Owned category spend differs from Home widget display spend."),
            catalog(.categoryTrend, seed: "How has Dining changed over time?", formula: "categoryTrend", subjects: [.categories, .variableExpenses, .plannedExpenses], operations: [.trend], required: [slot("category", .primaryTarget, [.category], .category, required: true)], sources: ["Category", "VariableExpense", "PlannedExpense"], basis: .budgetImpact, date: "Selected periods or recent completed periods.", never: ["Do not collapse trend into a current total.", "Do not substitute top categories."], shape: .chartRows, fixture: "Same current total but different prior periods changes trend."),
            catalog(.categoryMerchantDrivers, seed: "Which merchants are driving Dining?", formula: "categoryMerchantDrivers", subjects: [.categories, .merchant, .variableExpenses], operations: [.rank], required: [slot("category", .filter, [.category], .category, required: true)], sources: ["Category", "VariableExpense", "MerchantNormalizer"], basis: .budgetImpact, date: "Current period versus previous matching period.", never: ["Do not substitute category ranking.", "Do not include merchants outside the category."], shape: .rankedList, fixture: "One merchant drives the category delta."),
            catalog(.grossVsOwnedSpendBridge, seed: "Why does gross spend differ from owned spend?", formula: "grossVsOwnedSpendBridge", subjects: [.variableExpenses, .plannedExpenses], operations: [.compare], sources: ["VariableExpense", "PlannedExpense", "ExpenseAllocation", "SavingsLedgerEntry"], basis: .gross, date: "Selected period, defaulting to the current month.", never: ["Do not return only one total.", "Do not count settlements as savings offsets."], shape: .summaryCard, fixture: "Gross, ledger, allocated, savings offset, and owned rows all differ."),

            catalog(.presetDueSoon, seed: "Which presets are due soon?", formula: "presetDueSoon", subjects: [.presets, .plannedExpenses], operations: [.listRows], sources: ["Preset", "PlannedExpense"], basis: .plannedEffectiveAmount, date: "Next 30 days or explicit range.", never: ["Do not use schedule preview when materialized rows answer the question.", "Do not include archived presets unless asked."], shape: .rankedList, fixture: "Materialized planned row in window beats template preview."),
            catalog(.presetHighestCost, seed: "Which presets cost the most?", formula: "presetHighestCost", subjects: [.presets], operations: [.rank], sources: ["Preset"], basis: .plannedAmount, date: "Active preset templates; no transaction date range unless requested.", never: ["Archived presets are excluded unless requested.", "Do not rank generated planned rows for template cost."], shape: .rankedList, fixture: "Archived high-cost preset is excluded."),
            catalog(.presetBudgetCoverage, seed: "Which budgets use this preset?", formula: "presetBudgetCoverage", subjects: [.presets, .budgets], operations: [.listRows], required: [slot("preset", .primaryTarget, [.preset], .preset)], sources: ["Preset", "BudgetPresetLink", "Budget"], basis: .count, date: "All budgets or explicit range.", never: ["Do not infer links from planned row titles.", "Do not require budgets to be active."], shape: .relationshipList, fixture: "Matching title without BudgetPresetLink is excluded."),
            catalog(.presetActualVariance, seed: "How did this preset perform versus actual?", formula: "presetActualVariance", subjects: [.presets, .plannedExpenses], operations: [.compare], required: [slot("preset", .primaryTarget, [.preset], .preset)], sources: ["Preset", "PlannedExpense"], basis: .recordedActualAmount, date: "Selected period, defaulting to the current month.", never: ["actualAmount == 0 is unrecorded, not zero actual.", "Do not use income planned-vs-actual."], shape: .comparison, fixture: "ActualAmount above planned produces positive variance while zero is excluded."),
            catalog(.presetSchedulePreview, seed: "Preview this preset's schedule.", formula: "presetSchedulePreview", subjects: [.presets], operations: [.forecast], required: [slot("preset", .primaryTarget, [.preset], .preset, required: true)], sources: ["Preset", "PresetScheduleEngine"], basis: .plannedAmount, date: "Explicit preview window or next 90 days.", never: ["Preview only; do not materialize rows.", "Do not include generated planned expenses as template dates."], shape: .rankedList, fixture: "Preview dates are returned without creating planned expenses."),
            catalog(.presetArchiveImpact, seed: "What happens if I archive this preset?", formula: "presetArchiveImpact", subjects: [.presets], operations: [.lookupDetails], required: [slot("preset", .primaryTarget, [.preset], .preset, required: true)], sources: ["Preset", "BudgetPresetLink", "PlannedExpense"], basis: .count, date: "All linked rows.", never: ["Archive never deletes existing planned expenses.", "Do not mutate during preview."], shape: .summaryCard, fixture: "Archive hides template but leaves generated rows."),
            catalog(.presetDeletionImpactPreview, seed: "What would deleting this preset affect?", formula: "presetDeletionImpactPreview", subjects: [.presets], operations: [.lookupDetails], required: [slot("preset", .primaryTarget, [.preset], .preset, required: true)], sources: ["Preset", "BudgetPresetLink", "PlannedExpense"], basis: .count, date: "All linked rows.", never: ["Preview only; do not delete.", "Flag recorded planned rows instead of silently deleting them."], shape: .summaryCard, fixture: "Recorded generated planned row is flagged.")
        ]
    }

    private static func catalog(
        _ id: MarinaMetricContractID,
        seed: String,
        formula: String,
        subjects: [MarinaSubject],
        operations: [MarinaCandidateOperation],
        required: [MarinaMetricSlotContract] = [],
        optional: [MarinaMetricSlotContract] = [],
        sources: [String],
        basis: MarinaFinancialAmountBasis?,
        date: String,
        joins: [String] = ["Workspace-scoped source rows only."],
        ambiguity: [String] = ["Clarify ambiguous entity names before executing."],
        never: [String],
        shape: MarinaResponseShapeHint,
        status: MarinaMetricContractSupport = .contractOnly,
        missing: String? = nil,
        fixture: String
    ) -> MarinaMetricContract {
        contract(
            id,
            seed: seed,
            formula: formula,
            subjects: subjects,
            operations: operations,
            required: required,
            optional: optional,
            sources: sources,
            basis: basis,
            date: date,
            joins: joins,
            ambiguity: ambiguity,
            never: never,
            shape: shape,
            status: status,
            missing: missing ?? "Known formula contract; executor wiring is planned for a later batch.",
            fixture: fixture
        )
    }

    private static func contract(
        _ id: MarinaMetricContractID,
        seed: String,
        formula: String,
        subjects: [MarinaSubject],
        operations: [MarinaCandidateOperation],
        required: [MarinaMetricSlotContract],
        optional: [MarinaMetricSlotContract],
        sources: [String],
        basis: MarinaFinancialAmountBasis?,
        date: String,
        joins: [String],
        ambiguity: [String],
        never: [String],
        shape: MarinaResponseShapeHint,
        status: MarinaMetricContractSupport,
        missing: String,
        fixture: String,
        workspaceScope: String = "selected workspace"
    ) -> MarinaMetricContract {
        MarinaMetricContract(
            id: id,
            seedPrompt: seed,
            formulaName: formula,
            acceptedSubjects: subjects,
            acceptedOperations: operations,
            requiredInputs: required,
            optionalInputs: optional,
            sourceModels: sources,
            amountBasis: basis,
            amountBasisDescription: basis.map(displayName) ?? "none",
            dateRangeBehavior: date,
            legalJoins: joins,
            ambiguityRules: ambiguity,
            neverSilentlySubstituteRules: never,
            responseShape: shape,
            supportStatus: status,
            missingExecutorPolicy: missing,
            regressionFixtureIdea: fixture,
            workspaceScope: workspaceScope
        )
    }

    private static func slot(
        _ id: String,
        _ role: MarinaResolvedTargetRole,
        _ types: [MarinaCandidateEntityTypeHint],
        _ relationship: MarinaRelationshipField,
        required: Bool = false
    ) -> MarinaMetricSlotContract {
        MarinaMetricSlotContract(id, role: role, allowedEntityTypes: types, isRequired: required, relationship: relationship)
    }

    nonisolated private static func displayName(for basis: MarinaFinancialAmountBasis) -> String {
        switch basis {
        case .homeSpend:
            return "home spend"
        case .cardDisplaySpend:
            return "card display spend"
        case .debitSpend:
            return "debit spend"
        case .budgetImpact:
            return "budget impact"
        case .ownedSpend:
            return "owned spend"
        case .ledgerSigned:
            return "ledger signed"
        case .gross:
            return "gross"
        case .allocated:
            return "allocated"
        case .plannedAmount:
            return "planned amount"
        case .plannedEffectiveAmount:
            return "planned effective amount"
        case .recordedActualAmount:
            return "recorded actual amount"
        case .actualIncome:
            return "actual income"
        case .plannedIncome:
            return "planned income"
        case .savingsRunningTotal:
            return "savings running total"
        case .savingsMovement:
            return "savings movement"
        case .savingsAdjustment:
            return "savings adjustment"
        case .savingsOffset:
            return "savings offset"
        case .reconciliationBalance:
            return "reconciliation balance"
        case .reconciliationSettlement:
            return "reconciliation settlement"
        case .count:
            return "count"
        case .dateWindow:
            return "date window"
        }
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s&%]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formulaPhraseVariants(for contract: MarinaMetricContract) -> [String] {
        let rawValues = [
            contract.id.rawValue,
            contract.formulaName
        ]
        let variants = rawValues.flatMap { raw -> [String] in
            let spaced = raw
                .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
                .replacingOccurrences(of: "[-_]", with: " ", options: .regularExpression)
            return [normalized(raw), normalized(spaced)]
        }
        return Array(Set(variants.filter { $0.isEmpty == false }))
    }
}

struct MarinaMetricContractResolver {
    private let registry: MarinaMetricContractRegistry

    init(registry: MarinaMetricContractRegistry = .current) {
        self.registry = registry
    }

    func resolve(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        semanticResolved: MarinaResolvedSemanticQuery?,
        outcome: MarinaPlanValidationOutcome
    ) -> MarinaMetricContractResolution? {
        if let contract = registry.contract(forSeedPrompt: candidate.rawPrompt) {
            return MarinaMetricContractResolution(contract: contract, match: .seedPrompt)
        }

        if let contract = registry.contract(forFormulaPhrase: candidate.rawPrompt) {
            return MarinaMetricContractResolution(contract: contract, match: .formulaPhrase)
        }

        if let id = contractIDFromFormula(candidate: candidate),
           let contract = registry.contract(for: id) {
            return MarinaMetricContractResolution(contract: contract, match: .formulaMetadata)
        }

        if let id = contractIDFromRoute(candidate: candidate, semanticResolved: semanticResolved),
           let contract = registry.contract(for: id) {
            return MarinaMetricContractResolution(contract: contract, match: .routeIntent)
        }

        if let id = contractIDFromShape(
            candidate: candidate,
            resolved: resolved,
            semanticResolved: semanticResolved,
            outcome: outcome
        ),
           let contract = registry.contract(for: id) {
            return MarinaMetricContractResolution(contract: contract, match: .semanticShape)
        }

        return nil
    }

    private func contractIDFromFormula(candidate: MarinaQueryPlanCandidate) -> MarinaMetricContractID? {
        switch candidate.formulaKind ?? candidate.semanticCommand?.formulaKind {
        case .categoryLimitBurnRate:
            return .categoryOverPace
        case .recurringChargeAnomaly:
            return .recurringExpenseIncrease
        case .cardSavingsDrag:
            return .cardOverspendingDriver
        case .earlyPlannedExpenseStress:
            return .upcomingExpensesBeforeNextIncome
        case .expenseOnlySavingsRunway, nil:
            return nil
        }
    }

    private func contractIDFromRoute(
        candidate: MarinaQueryPlanCandidate,
        semanticResolved: MarinaResolvedSemanticQuery?
    ) -> MarinaMetricContractID? {
        let routeKind = semanticResolved?.query.routeIntent?.kind
            ?? candidate.routeIntent?.kind
            ?? candidate.semanticCommand.flatMap { command in
                MarinaRouteIntent.inferred(
                    requestFamily: command.family,
                    rawPrompt: candidate.rawPrompt,
                    operation: candidate.operation,
                    measure: candidate.measure,
                    entityMentions: candidate.entityMentions,
                    grouping: candidate.grouping,
                    responseShapeHint: candidate.responseShapeHint,
                    databaseLookupRequest: candidate.databaseLookupRequest,
                    semanticCommand: command,
                    requestShape: candidate.requestShape
                )?.kind
            }

        switch routeKind {
        case .incomePlannedVsActual:
            return .incomeActualVsExpected
        default:
            return nil
        }
    }

    private func contractIDFromShape(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        semanticResolved: MarinaResolvedSemanticQuery?,
        outcome: MarinaPlanValidationOutcome
    ) -> MarinaMetricContractID? {
        let targets = resolved.resolvedTargets
            + (semanticResolved?.resolvedFilters.map { filter in
                MarinaResolvedEntityMention(
                    id: filter.id,
                    mention: MarinaUnresolvedEntityMention(
                        role: MarinaEntityMentionRole(rawValue: filter.role.rawValue) ?? .filter,
                        rawText: filter.displayName,
                        typeHint: filter.entityType
                    ),
                    role: filter.role,
                    entityType: filter.entityType,
                    displayName: filter.displayName,
                    sourceID: filter.sourceID
                )
            } ?? [])

        if (candidate.measure == .spend || plan(from: outcome)?.measure == .spend),
           targets.contains(where: { $0.entityType == .allocationAccount }),
           targets.contains(where: { [.category, .merchant, .card, .preset, .transaction, .expense].contains($0.entityType) }) {
            return .allocatedCategorySpend
        }

        if candidate.measure == .income || plan(from: outcome)?.measure == .income,
           (candidate.semanticCommand?.incomeStatusScope == .all || semanticResolved?.query.incomeStatusScope == .all) {
            return .incomeActualVsExpected
        }

        return nil
    }

    private func plan(from outcome: MarinaPlanValidationOutcome) -> MarinaAggregationPlan? {
        if case .executable(let plan) = outcome { return plan }
        return nil
    }
}

struct MarinaMetricContractResponseBuilder {
    func summonedFormulaAnswer(
        contract: MarinaMetricContract,
        candidate: MarinaQueryPlanCandidate
    ) -> HomeAnswer {
        HomeAnswer(
            queryID: UUID(),
            kind: .message,
            userPrompt: candidate.rawPrompt,
            title: "Marina found this formula contract",
            subtitle: contract.formulaName,
            primaryValue: summonPrimaryValue(for: contract),
            rows: contractRows(contract) + [
                HomeAnswerRow(title: "Required inputs", value: slotSummary(contract.requiredInputs)),
                HomeAnswerRow(title: "Optional inputs", value: slotSummary(contract.optionalInputs)),
                HomeAnswerRow(title: "Required support", value: contract.missingExecutorPolicy),
                HomeAnswerRow(title: "Refused substitution", value: contract.neverSilentlySubstituteRules.first ?? "No unsafe substitute is allowed.")
            ]
        )
    }

    func summonedFormulaUnsupportedResponse(
        contract: MarinaMetricContract,
        candidate: MarinaQueryPlanCandidate
    ) -> MarinaTypedUnsupportedResponse {
        MarinaTypedUnsupportedResponse(
            kind: .unsupportedCombination,
            message: "\(contract.formulaName) is a known Marina metric contract. Marina surfaced the contract instead of substituting a nearby metric.",
            candidate: candidate
        )
    }

    func unsupportedAnswer(
        contract: MarinaMetricContract,
        candidate: MarinaQueryPlanCandidate
    ) -> HomeAnswer {
        HomeAnswer(
            queryID: UUID(),
            kind: .message,
            userPrompt: candidate.rawPrompt,
            title: "Marina knows this metric, but cannot run it yet",
            subtitle: contract.formulaName,
            primaryValue: contract.supportStatus.rawValue,
            rows: contractRows(contract) + [
                HomeAnswerRow(title: "Required support", value: contract.missingExecutorPolicy),
                HomeAnswerRow(title: "Refused substitution", value: contract.neverSilentlySubstituteRules.first ?? "No unsafe substitute is allowed."),
                HomeAnswerRow(title: "Regression fixture", value: contract.regressionFixtureIdea)
            ]
        )
    }

    func unsupportedResponse(
        contract: MarinaMetricContract,
        candidate: MarinaQueryPlanCandidate
    ) -> MarinaTypedUnsupportedResponse {
        MarinaTypedUnsupportedResponse(
            kind: .unsupportedCombination,
            message: "\(contract.formulaName) is a known Marina metric contract, but it is not executable safely yet. \(contract.missingExecutorPolicy)",
            candidate: candidate
        )
    }

    func evidenceRows(for contract: MarinaMetricContract) -> [HomeAnswerRow] {
        contractRows(contract)
    }

    private func contractRows(_ contract: MarinaMetricContract) -> [HomeAnswerRow] {
        [
            HomeAnswerRow(title: "Metric contract", value: contract.id.rawValue),
            HomeAnswerRow(title: "Formula", value: contract.formulaName),
            HomeAnswerRow(title: "Contract status", value: contract.supportStatus.rawValue),
            HomeAnswerRow(title: "Amount basis", value: contract.amountBasisDescription),
            HomeAnswerRow(title: "Source rows", value: contract.sourceModels.joined(separator: ", ")),
            HomeAnswerRow(title: "Date policy", value: contract.dateRangeBehavior),
            HomeAnswerRow(title: "Workspace scope", value: contract.workspaceScope)
        ]
    }

    private func summonPrimaryValue(for contract: MarinaMetricContract) -> String {
        switch contract.supportStatus {
        case .executable:
            return contract.requiredInputs.isEmpty ? "ready" : "needs inputs"
        case .partial, .contractOnly, .missing:
            return contract.supportStatus.rawValue
        }
    }

    private func slotSummary(_ slots: [MarinaMetricSlotContract]) -> String {
        guard slots.isEmpty == false else { return "none" }
        return slots.map { slot in
            let types = slot.allowedEntityTypes.map(\.rawValue).joined(separator: "/")
            return "\(slot.id): \(types)"
        }
        .joined(separator: ", ")
    }
}

enum MarinaEntityQueryContractID: String, Codable, Equatable, CaseIterable, Sendable {
    case entityList
    case entityFind
    case entitySummary
    case relationshipSummary
    case deletionImpactPreview
}

struct MarinaEntityQueryContract: Codable, Equatable, Identifiable, Sendable {
    let id: MarinaEntityQueryContractID
    let operationName: String
    let acceptedObjectTypes: [MarinaLookupObjectType]
    let sourceModels: [String]
    let requiredInputs: [String]
    let optionalInputs: [String]
    let dateRangeBehavior: String
    let ambiguityRules: [String]
    let neverSilentlySubstituteRules: [String]
    let responseShape: MarinaResponseShapeHint
    let supportStatus: MarinaMetricContractSupport
    let workspaceScope: String
}

struct MarinaEntityQueryContractRegistry {
    static let current = MarinaEntityQueryContractRegistry(contracts: makeContracts())

    let contracts: [MarinaEntityQueryContract]

    func contract(for id: MarinaEntityQueryContractID) -> MarinaEntityQueryContract? {
        contracts.first { $0.id == id }
    }

    private static func makeContracts() -> [MarinaEntityQueryContract] {
        [
            contract(
                .entityList,
                operation: "entityList",
                types: MarinaLookupObjectType.safeDefaultSearchTypes,
                sources: ["Workspace", "Budget", "Card", "Category", "Preset", "Income", "VariableExpense", "PlannedExpense", "SavingsAccount", "SavingsLedgerEntry", "AllocationAccount", "ExpenseAllocation", "AllocationSettlement", "ImportMerchantRule", "AssistantAliasRule"],
                required: ["object type or safe default search scope"],
                optional: ["date range", "search text", "limit"],
                date: "Optional date range only filters dated row types; entity templates remain all-history unless the object type defines dates.",
                ambiguity: ["Clarify when a broad list request could mean multiple object types and the prompt does not supply a safe default."],
                never: ["Do not compute a financial formula for a list request.", "Do not cross workspace boundaries."],
                shape: .rankedList,
                status: .executable
            ),
            contract(
                .entityFind,
                operation: "entityFind",
                types: MarinaLookupObjectType.safeDefaultSearchTypes,
                sources: ["MarinaDatabaseLookupExecutor", "MarinaEntityMatcher", "AssistantAliasRule"],
                required: ["search text"],
                optional: ["object type", "date range", "requested detail"],
                date: "Date filters apply only to dated object types.",
                ambiguity: ["Ask for clarification when the same text exactly matches multiple entity types, such as a card and merchant."],
                never: ["Do not guess a target when equally plausible entities exist.", "Do not substitute category spend for an entity lookup."],
                shape: .clarification,
                status: .executable
            ),
            contract(
                .entitySummary,
                operation: "entitySummary",
                types: MarinaLookupObjectType.safeDefaultSearchTypes,
                sources: ["MarinaDatabaseLookupResponseBuilder", "Workspace models"],
                required: ["resolved entity"],
                optional: ["requested detail"],
                date: "All-history entity details unless the entity detail itself has a date.",
                ambiguity: ["Clarify ambiguous names before showing details."],
                never: ["Do not summarize a similarly named financial metric.", "Do not mutate the entity."],
                shape: .summaryCard,
                status: .executable
            ),
            contract(
                .relationshipSummary,
                operation: "relationshipSummary",
                types: [.budget, .card, .category, .preset, .reconciliationAccount, .savingsAccount, .importMerchantRule],
                sources: ["BudgetCardLink", "BudgetPresetLink", "BudgetCategoryLimit", "Preset", "Card", "Category", "ImportMerchantRule", "ExpenseAllocation", "SavingsLedgerEntry"],
                required: ["resolved entity or relationship type"],
                optional: ["date range", "direction"],
                date: "Relationship rows are all-history unless the relationship or linked row is dated.",
                ambiguity: ["Clarify relationship direction when the prompt could mean both parent and child links."],
                never: ["Do not infer links from matching display text alone.", "Do not substitute spend totals for relationship membership."],
                shape: .relationshipList,
                status: .partial
            ),
            contract(
                .deletionImpactPreview,
                operation: "deletionImpactPreview",
                types: [.budget, .card, .category, .preset, .reconciliationAccount, .savingsAccount, .workspace],
                sources: ["Deletion services", "Workspace relationships", "BudgetCardLink", "BudgetPresetLink", "BudgetCategoryLimit", "VariableExpense", "PlannedExpense", "Income", "SavingsLedgerEntry", "ExpenseAllocation", "AllocationSettlement"],
                required: ["resolved entity"],
                optional: ["preserve history policy"],
                date: "All rows that would be deleted, unlinked, archived, or need review.",
                ambiguity: ["Ask for the target entity before previewing destructive impact."],
                never: ["Preview only; do not delete, archive, unlink, or recategorize.", "Do not hide historical financial rows affected by the action."],
                shape: .summaryCard,
                status: .contractOnly
            )
        ]
    }

    private static func contract(
        _ id: MarinaEntityQueryContractID,
        operation: String,
        types: [MarinaLookupObjectType],
        sources: [String],
        required: [String],
        optional: [String],
        date: String,
        ambiguity: [String],
        never: [String],
        shape: MarinaResponseShapeHint,
        status: MarinaMetricContractSupport
    ) -> MarinaEntityQueryContract {
        MarinaEntityQueryContract(
            id: id,
            operationName: operation,
            acceptedObjectTypes: types,
            sourceModels: sources,
            requiredInputs: required,
            optionalInputs: optional,
            dateRangeBehavior: date,
            ambiguityRules: ambiguity,
            neverSilentlySubstituteRules: never,
            responseShape: shape,
            supportStatus: status,
            workspaceScope: "selected workspace"
        )
    }
}
