import Foundation

enum MarinaMetricContractID: String, Codable, Equatable, CaseIterable, Sendable {
    case safeSpendRemaining
    case spendingIncreaseDrivers
    case categoryOverPace
    case upcomingExpensesBeforeNextIncome
    case plannedVsActualSpend
    case unrecordedPlannedExpenses
    case unusualMerchantSpend
    case recurringExpenseIncrease
    case subscriptionSpend
    case reconciliationOwedThisMonth
    case allocatedCategorySpend
    case trueOwnedSpend
    case cardOverspendingDriver
    case categoryCutImpact
    case skipCategoryScenario
    case incomeActualVsExpected
    case savingsTrackVsLastMonth
    case budgetSharedLinks
    case categorizationReview
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
            return match == .seedPrompt || match == .semanticShape || match == .routeIntent
        }
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

    private static func makeContracts() -> [MarinaMetricContract] {
        [
            contract(.safeSpendRemaining, seed: "How much can I safely spend for the rest of this month?", formula: "safeSpendRemaining", subjects: [.budgets], operations: [.lookupDetails, .forecast], required: [], optional: [slot("budget", .filter, [.budget], .budget)], sources: ["Budget", "Income", "PlannedExpense", "VariableExpense", "SavingsLedgerEntry"], basis: .budgetImpact, date: "Current selected period through period end; not a per-day answer unless the contract explicitly asks for safe-spend today.", joins: ["Budget date range to workspace rows", "SavingsLedgerEntry linked offsets by expense when present"], ambiguity: ["Clarify active budget if overlapping budgets both cover the period."], never: ["Do not substitute savings account balance.", "Do not answer with Safe Spend Today for a rest-of-period question."], shape: .summaryCard, status: .partial, missing: "Needs a rest-of-period safe-spend executor distinct from the existing Safe Spend Today adapter.", fixture: "Same savings balance but different upcoming planned expenses changes the answer."),
            contract(.spendingIncreaseDrivers, seed: "Why is my spending higher this month than last month?", formula: "spendingIncreaseDrivers", subjects: [.variableExpenses, .plannedExpenses], operations: [.compare], required: [], optional: [slot("grouping", .groupingDimension, [.category, .merchant, .card, .transaction], .unknown)], sources: ["VariableExpense", "PlannedExpense"], basis: .budgetImpact, date: "Primary current period plus explicit comparison period, defaulting to previous matching period only when requested.", joins: ["Expenses joined to category, merchant text, and card for driver grouping."], ambiguity: ["Clarify whether the user wants category, merchant, card, or transaction drivers when not inferable."], never: ["Do not collapse to a scalar month comparison.", "Do not use ledger-signed totals for driver ranking."], shape: .rankedList, status: .partial, missing: "Needs a contract-first delta-driver executor for broad why questions.", fixture: "Total delta is +300, but one category contributes +250 and must be visible."),
            contract(.categoryOverPace, seed: "What categories are over pace for this point in the month?", formula: "categoryLimitBurnRate", subjects: [.variableExpenses, .budgets], operations: [.rank, .simulate], required: [], optional: [slot("category", .filter, [.category], .category)], sources: ["Budget", "BudgetCategoryLimit", "VariableExpense", "PlannedExpense"], basis: .budgetImpact, date: "Budget/current period from start through today, projected to inclusive period end.", joins: ["BudgetCategoryLimit by active budget and category", "Expense category within workspace and period"], ambiguity: ["A named category can execute through the burn-rate recipe; broad category ranking needs its own executor."], never: ["Do not use gross ledger amount.", "Do not treat categories without max limits as over-pace."], shape: .rankedList, status: .partial, missing: "Needs broad category over-pace ranking; named category burn-rate already executes.", fixture: "A split expense gross 100 allocated 60 must pace on owned budget impact."),
            contract(.upcomingExpensesBeforeNextIncome, seed: "What upcoming expenses will hit before my next income?", formula: "upcomingExpensesBeforeNextIncome", subjects: [.plannedExpenses, .income], operations: [.listRows], required: [], optional: [slot("card", .filter, [.card], .card)], sources: ["PlannedExpense", "Income"], basis: .budgetImpact, date: "Starts now and ends at the next planned or actual income date.", joins: ["PlannedExpense date compared with next Income date"], ambiguity: ["Clarify whether planned or actual income should define next income if both exist on different dates."], never: ["Do not list all upcoming expenses.", "Do not treat IncomeSeries rules as received income."], shape: .rankedList, status: .missing, missing: "Needs next-income window calculation before planned-expense row execution.", fixture: "A bill after payday must be excluded."),
            contract(.plannedVsActualSpend, seed: "What did I plan to spend versus what I actually spent?", formula: "plannedVsActualSpend", subjects: [.plannedExpenses, .variableExpenses], operations: [.compare], required: [], optional: [slot("category", .filter, [.category], .category), slot("card", .filter, [.card], .card)], sources: ["PlannedExpense", "VariableExpense"], basis: .budgetImpact, date: "Selected period; planned side uses planned projected amount, actual side uses recorded actual/budget-impact rows.", joins: ["Optional category/card filters across planned and variable rows."], ambiguity: ["Clarify spend vs income if the prompt mentions income."], never: ["Do not answer with income planned-vs-actual.", "Do not treat PlannedExpense.actualAmount == 0 as actual zero."], shape: .comparison, status: .contractOnly, missing: "Needs spend-specific planned-vs-actual executor.", fixture: "Planned spend 500 and actual spend 350 while income planned-vs-actual is unrelated."),
            contract(.unrecordedPlannedExpenses, seed: "Which planned expenses have no actual transaction yet?", formula: "unrecordedPlannedExpenses", subjects: [.plannedExpenses], operations: [.listRows], required: [], optional: [slot("category", .filter, [.category], .category), slot("card", .filter, [.card], .card)], sources: ["PlannedExpense", "VariableExpense"], basis: .budgetImpact, date: "Selected period or future window; planned rows remain candidates while actualAmount is zero and no linked actual exists.", joins: ["Optional matching between planned title/date/card and actual transaction only after explicit policy exists."], ambiguity: ["Clarify matching policy if the user asks for fuzzy transaction matching."], never: ["Do not treat actualAmount == 0 as actual zero spend.", "Do not delete or mutate planned rows."], shape: .rankedList, status: .missing, missing: "Needs unrecorded planned-expense matching policy.", fixture: "One planned row with actualAmount 0 remains unrecorded while another with actualAmount > 0 is excluded."),
            contract(.unusualMerchantSpend, seed: "What merchants are unusually high this month?", formula: "unusualMerchantSpend", subjects: [.variableExpenses], operations: [.rank], required: [], optional: [slot("merchant", .filter, [.merchant], .merchant)], sources: ["VariableExpense"], basis: .budgetImpact, date: "Current period against completed baseline periods.", joins: ["Merchant text normalized from VariableExpense description/import merchant rules."], ambiguity: ["Clarify merchant vs card/category when a name collides."], never: ["Do not substitute category or card ranking.", "Do not use future planned rows."], shape: .rankedList, status: .missing, missing: "Needs merchant anomaly executor and baseline policy.", fixture: "A merchant doubles while its category total stays flat."),
            contract(.recurringExpenseIncrease, seed: "What recurring expenses increased?", formula: "recurringChargeAnomaly", subjects: [.variableExpenses, .plannedExpenses], operations: [.rank], required: [], optional: [slot("merchant", .filter, [.merchant], .merchant), slot("preset", .filter, [.preset], .preset)], sources: ["VariableExpense", "PlannedExpense"], basis: .budgetImpact, date: "Current month against recent completed-month baseline.", joins: ["Repeated merchant text", "PlannedExpense actual-vs-planned variance"], ambiguity: ["Clarify subscriptions vs all recurring merchants when the user distinguishes them."], never: ["Do not answer as generic month comparison.", "Do not include one-off merchants without recurrence evidence."], shape: .rankedList, status: .executable, missing: "Executable through recurringChargeAnomaly recipe.", fixture: "StreamBox baseline 10 and current 25 appears as anomaly."),
            contract(.subscriptionSpend, seed: "How much did I spend on subscriptions this quarter?", formula: "subscriptionSpend", subjects: [.variableExpenses, .plannedExpenses, .presets], operations: [.sum], required: [], optional: [slot("category", .filter, [.category], .category), slot("preset", .filter, [.preset], .preset), slot("merchant", .filter, [.merchant], .merchant)], sources: ["VariableExpense", "PlannedExpense", "Preset", "ImportMerchantRule"], basis: .budgetImpact, date: "Explicit quarter range; defaults to current quarter only after date policy is set.", joins: ["Explicit subscription category/preset/merchant set to expense rows."], ambiguity: ["Ask what identifies subscriptions unless a stored category, preset, or merchant set is explicit."], never: ["Do not infer subscriptions from arbitrary merchant text.", "Do not substitute all recurring expenses."], shape: .scalarCurrency, status: .missing, missing: "Needs subscription identity policy or clarification flow.", fixture: "Category Subscriptions differs from merchant Apple; answer must not merge them silently."),
            contract(.reconciliationOwedThisMonth, seed: "What did Alejandro owe me this month?", formula: "reconciliationOwedThisMonth", subjects: [.reconciliationAccounts, .reconciliationItems], operations: [.sum], required: [slot("allocationAccount", .filter, [.allocationAccount], .allocationAccount, required: true)], optional: [], sources: ["AllocationAccount", "ExpenseAllocation", "AllocationSettlement"], basis: .reconciliationBalance, date: "Selected month for allocations plus signed settlements.", joins: ["ExpenseAllocation.account", "AllocationSettlement.account"], ambiguity: ["Clarify allocation account if the person name collides with merchant text."], never: ["Do not use savings ledger entries.", "Do not report gross expense spend as amount owed."], shape: .summaryCard, status: .partial, missing: "Needs period net owed executor combining allocations and settlements.", fixture: "Allocated 100 and settlement -40 yields owed 60."),
            contract(.allocatedCategorySpend, seed: "What had Alejandro spent on Cannabis?", formula: "allocatedCategorySpend", subjects: [.variableExpenses, .plannedExpenses, .reconciliationItems], operations: [.sum], required: [slot("allocationAccount", .filter, [.allocationAccount], .allocationAccount, required: true), slot("spendFilter", .filter, [.category, .merchant, .card, .preset, .transaction], .unknown, required: true)], optional: [], sources: ["ExpenseAllocation", "VariableExpense", "PlannedExpense", "AllocationAccount", "Category"], basis: .allocated, date: "Selected period, defaulting to current month in current executor.", joins: ["ExpenseAllocation.account", "ExpenseAllocation.expense or plannedExpense", "Linked expense category/card/merchant/preset"], ambiguity: ["If person name can be allocation account or merchant, ask instead of guessing."], never: ["Do not substitute gross category spend.", "Do not use reconciliation balance or savings as allocated spend."], shape: .scalarCurrency, status: .executable, missing: "Executable through composable allocated spend.", fixture: "Gross Cannabis spend is 100 but Alejandro allocation is 30, answer must be 30."),
            contract(.trueOwnedSpend, seed: "What is my true owned spend after splits and savings offsets?", formula: "trueOwnedSpend", subjects: [.variableExpenses, .plannedExpenses], operations: [.sum], required: [], optional: [slot("category", .filter, [.category], .category), slot("card", .filter, [.card], .card)], sources: ["VariableExpense", "PlannedExpense", "ExpenseAllocation", "SavingsLedgerEntry"], basis: .budgetImpact, date: "Selected period.", joins: ["Expense allocations and savings offset ledger entries linked to expenses."], ambiguity: ["Clarify gross vs owned if the user asks for both."], never: ["Do not use ledger-signed amount.", "Do not use gross amount.", "Do not include reconciliation settlements as savings."], shape: .scalarCurrency, status: .partial, missing: "Needs a contract-first owned-spend executor to avoid HomeQuery gross/ledger fallback.", fixture: "Gross 100 minus split 40 minus savings offset 20 leaves owned impact 40."),
            contract(.cardOverspendingDriver, seed: "Which card is driving the most overspending?", formula: "cardOverspendingDriver", subjects: [.cards, .variableExpenses, .plannedExpenses], operations: [.rank], required: [], optional: [slot("budget", .filter, [.budget], .budget)], sources: ["Card", "BudgetCardLink", "VariableExpense", "PlannedExpense", "BudgetCategoryLimit"], basis: .budgetImpact, date: "Current budget or selected period.", joins: ["Card to budget links and expense rows; baseline must come from budget/plan."], ambiguity: ["Ask for baseline if no budget or planned comparison is available."], never: ["Do not call raw card spend overspending.", "Do not use card display spend as budget variance."], shape: .rankedList, status: .partial, missing: "Needs card overspending baseline policy.", fixture: "Card A spends more but is under plan; Card B spends less but is over plan."),
            contract(.categoryCutImpact, seed: "What category would save me the most if I cut 20%?", formula: "categoryCutImpact", subjects: [.variableExpenses], operations: [.simulate, .rank], required: [slot("percentage", .simulationInput, [.category], .category, required: true)], optional: [], sources: ["VariableExpense", "PlannedExpense", "Category"], basis: .budgetImpact, date: "Selected period or remaining current period; percentage applies to category spend.", joins: ["Expense rows grouped by category."], ambiguity: ["Clarify whether the cut applies to current actuals, remaining forecast, or planned spend."], never: ["Do not treat 20% as $20.", "Do not mutate budgets or expenses."], shape: .rankedList, status: .missing, missing: "Needs percentage what-if ranking executor.", fixture: "Dining 500 cut 20% produces 100 impact."),
            contract(.skipCategoryScenario, seed: "If I skip restaurants for two weeks, where does my month land?", formula: "skipCategoryScenario", subjects: [.variableExpenses], operations: [.simulate, .forecast], required: [slot("category", .simulationInput, [.category, .merchant], .category, required: true)], optional: [], sources: ["VariableExpense", "PlannedExpense", "Income", "Budget"], basis: .budgetImpact, date: "Two-week horizon projected into current month.", joins: ["Category/merchant spend rate to budget forecast rows."], ambiguity: ["Clarify category vs merchant if restaurants is both a category and merchant text."], never: ["Do not delete planned expenses.", "Do not assume the scenario affects income."], shape: .summaryCard, status: .missing, missing: "Needs category skip forecast executor.", fixture: "Restaurants weekly rate changes projected month landing without mutating rows."),
            contract(.incomeActualVsExpected, seed: "How much income have I actually received versus expected?", formula: "incomeActualVsExpected", subjects: [.income], operations: [.sum, .compare], required: [], optional: [slot("incomeSource", .filter, [.incomeSource], .incomeSource)], sources: ["Income"], basis: .homeSpend, date: "Selected period; actual rows are isPlanned false and expected rows are isPlanned true.", joins: ["Optional income source text."], ambiguity: ["Clarify source if a source name collides."], never: ["Do not treat IncomeSeries as received income.", "Do not merge spending rows into income variance."], shape: .comparison, status: .executable, missing: "Executable through income planned-vs-actual summary.", fixture: "Expected 3000 and actual 2000 yields a -1000 gap."),
            contract(.savingsTrackVsLastMonth, seed: "Am I on track to save more than last month?", formula: "savingsTrackVsLastMonth", subjects: [.savingsLedgerEntries, .income, .variableExpenses, .plannedExpenses], operations: [.forecast, .compare], required: [], optional: [], sources: ["SavingsLedgerEntry", "Income", "VariableExpense", "PlannedExpense"], basis: .budgetImpact, date: "Current period forecast compared with previous period actual savings.", joins: ["Savings formula rows across income, expenses, and savings ledger entries."], ambiguity: ["Clarify actual savings vs projected savings when the prompt asks for both."], never: ["Do not use SavingsAccount.total alone.", "Do not revive reconciliation savings mirrors."], shape: .comparison, status: .missing, missing: "Needs savings forecast-vs-prior executor.", fixture: "Same account total but different period ledger entries yields different result."),
            contract(.budgetSharedLinks, seed: "Which budgets share the same card or preset?", formula: "budgetSharedLinks", subjects: [.budgets, .cards, .presets], operations: [.listRows], required: [], optional: [slot("budget", .filter, [.budget], .budget)], sources: ["Budget", "BudgetCardLink", "BudgetPresetLink", "Card", "Preset"], basis: nil, date: "All budgets or selected overlapping period.", joins: ["BudgetCardLink by card", "BudgetPresetLink by preset"], ambiguity: ["Clarify card-only vs preset-only if the user narrows the object type."], never: ["Do not infer shared links from expense card alone.", "Do not require budgets to be non-overlapping."], shape: .relationshipList, status: .missing, missing: "Needs budget-link overlap executor.", fixture: "Two budgets share Apple Card, but only one shares Rent preset."),
            contract(.categorizationReview, seed: "Show expenses that look uncategorized or miscategorized.", formula: "categorizationReview", subjects: [.variableExpenses, .plannedExpenses], operations: [.listRows], required: [], optional: [slot("category", .filter, [.category], .category)], sources: ["VariableExpense", "PlannedExpense", "Category", "ImportMerchantRule"], basis: .budgetImpact, date: "Recent or selected period.", joins: ["Nil category rows and merchant-rule/category mismatch heuristics."], ambiguity: ["Clarify whether the user wants only uncategorized rows or heuristic miscategorized rows too."], never: ["Do not create a stored Uncategorized category.", "Do not recategorize automatically."], shape: .rankedList, status: .partial, missing: "Uncategorized rows exist; miscategorized heuristic review needs an executor.", fixture: "Nil category row plus merchant-rule mismatch row must both be visible when heuristic support lands."),
            contract(.sinceLastCheckIn, seed: "What changed since my last check-in?", formula: "sinceLastCheckIn", subjects: [.variableExpenses, .plannedExpenses, .income, .savingsLedgerEntries, .reconciliationItems], operations: [.compare, .listRows], required: [], optional: [], sources: ["MarinaConversationStore", "VariableExpense", "PlannedExpense", "Income", "SavingsLedgerEntry", "ExpenseAllocation", "AllocationSettlement"], basis: .budgetImpact, date: "Since persisted check-in timestamp or snapshot.", joins: ["Check-in snapshot timestamp to changed workspace rows."], ambiguity: ["Ask for a starting point if no check-in snapshot exists."], never: ["Do not default to this-month changes.", "Do not use another workspace's check-in state."], shape: .summaryCard, status: .missing, missing: "Needs persisted check-in snapshot/timestamp support.", fixture: "Only rows after the saved check-in appear.")
        ]
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

    private static func displayName(for basis: MarinaFinancialAmountBasis) -> String {
        switch basis {
        case .homeSpend:
            return "home spend"
        case .cardDisplaySpend:
            return "card display spend"
        case .budgetImpact:
            return "budget impact"
        case .ledgerSigned:
            return "ledger signed"
        case .gross:
            return "gross"
        case .allocated:
            return "allocated"
        case .reconciliationBalance:
            return "reconciliation balance"
        }
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s&%]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
}
