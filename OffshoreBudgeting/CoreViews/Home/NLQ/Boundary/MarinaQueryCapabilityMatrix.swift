import Foundation

enum MarinaQueryCapability: String, Codable, Equatable, CaseIterable, Sendable {
    case lookupDetails
    case listRows
    case total
    case average
    case rank
    case compare
    case groupedBreakdown
    case linkedObjectSummary
    case filter
    case relationshipFilter
    case derivedMetricSource
    case nextLatestPrevious
    case balanceStatus
    case remainingAvailable
    case projectedActualPlanned
    case unsupportedWithClarification
}

enum MarinaEntityCapabilitySupport: String, Codable, Equatable, Sendable {
    case supported
    case derived
    case lookupOnly
    case relationshipOnly
    case sourceOnly
    case gap
    case intentionallyUnsupported
}

struct MarinaEntityQuestionCapabilities: Codable, Equatable, Sendable {
    let find: MarinaEntityCapabilitySupport
    let summarize: MarinaEntityCapabilitySupport
    let aggregate: MarinaEntityCapabilitySupport
    let filterBy: MarinaEntityCapabilitySupport
    let compareOverTime: MarinaEntityCapabilitySupport
    let rank: MarinaEntityCapabilitySupport
    let nextLatestPrevious: MarinaEntityCapabilitySupport
    let explainDerivedValues: MarinaEntityCapabilitySupport
    let balanceStatus: MarinaEntityCapabilitySupport
    let remainingAvailable: MarinaEntityCapabilitySupport
    let projectedActualPlanned: MarinaEntityCapabilitySupport
}

struct MarinaEntityCapabilityRecord: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let entityName: String
    let displayFields: [String]
    let amountFields: [String]
    let dateFields: [String]
    let workspaceScope: String
    let relationships: [String]
    let isSearchable: Bool
    let isQueryable: Bool
    let isAggregatable: Bool
    let canBeTargetFilter: Bool
    let canBeRelationshipFilter: Bool
    let contributesToDerivedMetrics: Bool
    let supportedOperations: [String]
    let missingOperations: [String]
    let intentionallyUnsupportedOperations: [String]
    let questionCapabilities: MarinaEntityQuestionCapabilities
}

enum MarinaAppSurfaceSupportStatus: String, Codable, Equatable, Sendable {
    case supportedRoute
    case structuredClarificationRoute
    case typedUnsupportedGap
}

struct MarinaAppSurfaceMetricRecord: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let surfaceName: String
    let sourcePath: String
    let sourceTypeName: String
    let sourceFunctionOrProperty: String
    let displayedMetric: String
    let sourceEntities: [String]
    let dateRangeBehavior: String
    let filterBehavior: String
    let workspaceScopeBehavior: String
    let marinaSupportStatus: MarinaAppSurfaceSupportStatus
    let marinaRoute: String?
    let unsupportedReason: String?
}

struct MarinaQueryCapabilityMatrix {
    static var catalog: MarinaEntityCatalog { .current }

    static var modelEntityNames: Set<String> {
        catalog.persistentModelEntityNames
    }

    static var records: [MarinaEntityCapabilityRecord] {
        catalog.capabilityRecords()
    }

    static let appSurfaceMetrics: [MarinaAppSurfaceMetricRecord] = [
        surface(
            id: "home.overview",
            surfaceName: "Home period overview",
            sourcePath: "OffshoreBudgeting/CoreViews/Home/HomeQueryEngine.swift",
            sourceTypeName: "HomeQueryEngine",
            sourceFunctionOrProperty: "periodOverviewAnswer(_:context:now:calendar:)",
            displayedMetric: "Period income, spending, planned expenses, savings context",
            sourceEntities: ["Budget", "VariableExpense", "PlannedExpense", "Income", "SavingsLedgerEntry"],
            dateRangeBehavior: "HomeQuery date range or active/current period",
            filterBehavior: "workspace-wide unless query target is provided",
            marinaSupportStatus: .typedUnsupportedGap,
            marinaRoute: nil,
            unsupportedReason: "Shared pipeline does not yet map overview requests to HomeQueryMetric.overview."
        ),
        surface(
            id: "home.spend.total",
            surfaceName: "Home spend total",
            sourcePath: "OffshoreBudgeting/CoreViews/Home/HomeQueryEngine.swift",
            sourceTypeName: "HomeQueryEngine",
            sourceFunctionOrProperty: "spendThisMonthAnswer(_:context:now:calendar:)",
            displayedMetric: "Total spend for a date range",
            sourceEntities: ["VariableExpense", "PlannedExpense"],
            dateRangeBehavior: "query range, otherwise current month/current period",
            filterBehavior: "workspace-wide broad spend",
            marinaSupportStatus: .supportedRoute,
            marinaRoute: "MarinaAggregationPlanHomeQueryAdapter -> HomeQueryMetric.spendTotal",
            unsupportedReason: nil
        ),
        surface(
            id: "home.spend.average",
            surfaceName: "Home spend average per period",
            sourcePath: "OffshoreBudgeting/CoreViews/Home/HomeQueryEngine.swift",
            sourceTypeName: "HomeQueryEngine",
            sourceFunctionOrProperty: "spendAveragePerPeriodAnswer(_:context:now:calendar:)",
            displayedMetric: "Average spend per period",
            sourceEntities: ["VariableExpense", "PlannedExpense"],
            dateRangeBehavior: "query range with period unit/default month denominator",
            filterBehavior: "broad average in HomeQueryEngine; targeted average via composable executor",
            marinaSupportStatus: .supportedRoute,
            marinaRoute: "HomeQueryMetric.spendAveragePerPeriod for broad; MarinaComposableWorkspaceQueryExecutor.targetedPeriodicAverage for filtered",
            unsupportedReason: nil
        ),
        surface(
            id: "home.category.total",
            surfaceName: "Home category spend total",
            sourcePath: "OffshoreBudgeting/CoreViews/Home/HomeQueryEngine.swift",
            sourceTypeName: "HomeQueryEngine",
            sourceFunctionOrProperty: "categorySpendTotalAnswer(_:context:now:calendar:)",
            displayedMetric: "Category spend total",
            sourceEntities: ["Category", "VariableExpense", "PlannedExpense"],
            dateRangeBehavior: "query range",
            filterBehavior: "category target",
            marinaSupportStatus: .supportedRoute,
            marinaRoute: "HomeQueryMetric.categorySpendTotal",
            unsupportedReason: nil
        ),
        surface(
            id: "home.card.total",
            surfaceName: "Home card spend total",
            sourcePath: "OffshoreBudgeting/CoreViews/Home/HomeQueryEngine.swift",
            sourceTypeName: "HomeQueryEngine",
            sourceFunctionOrProperty: "cardSpendTotalAnswer(_:context:now:calendar:)",
            displayedMetric: "Card spend total",
            sourceEntities: ["Card", "VariableExpense", "PlannedExpense"],
            dateRangeBehavior: "query range",
            filterBehavior: "card target",
            marinaSupportStatus: .supportedRoute,
            marinaRoute: "HomeQueryMetric.cardSpendTotal",
            unsupportedReason: nil
        ),
        surface(
            id: "home.merchant.total",
            surfaceName: "Home merchant spend total",
            sourcePath: "OffshoreBudgeting/CoreViews/Home/HomeQueryEngine.swift",
            sourceTypeName: "HomeQueryEngine",
            sourceFunctionOrProperty: "merchantSpendTotalAnswer(_:context:now:calendar:)",
            displayedMetric: "Merchant/object spend total",
            sourceEntities: ["VariableExpense", "ImportMerchantRule"],
            dateRangeBehavior: "query range",
            filterBehavior: "merchant text target",
            marinaSupportStatus: .supportedRoute,
            marinaRoute: "HomeQueryMetric.merchantSpendTotal",
            unsupportedReason: nil
        ),
        surface(
            id: "home.comparison.category",
            surfaceName: "Home category comparison",
            sourcePath: "OffshoreBudgeting/CoreViews/Home/HomeQueryEngine.swift",
            sourceTypeName: "HomeQueryEngine",
            sourceFunctionOrProperty: "categoryMonthComparisonAnswer(_:context:now:calendar:)",
            displayedMetric: "Category spend comparison",
            sourceEntities: ["Category", "VariableExpense", "PlannedExpense"],
            dateRangeBehavior: "primary and comparison ranges required",
            filterBehavior: "category target",
            marinaSupportStatus: .supportedRoute,
            marinaRoute: "HomeQueryMetric.categoryMonthComparison",
            unsupportedReason: nil
        ),
        surface(
            id: "home.income.average",
            surfaceName: "Home actual income average",
            sourcePath: "OffshoreBudgeting/CoreViews/Home/HomeQueryEngine.swift",
            sourceTypeName: "HomeQueryEngine",
            sourceFunctionOrProperty: "incomeAverageActualAnswer(_:context:now:calendar:)",
            displayedMetric: "Average actual income",
            sourceEntities: ["Income"],
            dateRangeBehavior: "query range",
            filterBehavior: "actual income rows; optional source in related routes",
            marinaSupportStatus: .supportedRoute,
            marinaRoute: "HomeQueryMetric.incomeAverageActual or workspace income executor",
            unsupportedReason: nil
        ),
        surface(
            id: "home.savings.status",
            surfaceName: "Home savings status card",
            sourcePath: "OffshoreBudgeting/CoreViews/Home/HomeQueryEngine.swift",
            sourceTypeName: "HomeQueryEngine",
            sourceFunctionOrProperty: "savingsStatusAnswer(_:context:now:calendar:)",
            displayedMetric: "Actual savings status for period",
            sourceEntities: ["SavingsAccount", "SavingsLedgerEntry", "Income", "VariableExpense", "PlannedExpense"],
            dateRangeBehavior: "query range or active/current period",
            filterBehavior: "workspace/primary savings context",
            marinaSupportStatus: .supportedRoute,
            marinaRoute: "HomeQueryMetric.savingsStatus",
            unsupportedReason: nil
        ),
        surface(
            id: "home.forecast.savings",
            surfaceName: "Home forecast savings card",
            sourcePath: "OffshoreBudgeting/CoreViews/Home/HomeQueryEngine.swift",
            sourceTypeName: "HomeQueryEngine",
            sourceFunctionOrProperty: "forecastSavingsAnswer(_:context:now:calendar:)",
            displayedMetric: "Projected savings",
            sourceEntities: ["SavingsAccount", "SavingsLedgerEntry", "Income", "VariableExpense", "PlannedExpense", "Budget"],
            dateRangeBehavior: "query range or current period",
            filterBehavior: "workspace/primary savings context",
            marinaSupportStatus: .supportedRoute,
            marinaRoute: "HomeQueryMetric.forecastSavings",
            unsupportedReason: nil
        ),
        surface(
            id: "home.safe.spend.today",
            surfaceName: "Home safe spend today card",
            sourcePath: "OffshoreBudgeting/CoreViews/Home/HomeQueryEngine.swift",
            sourceTypeName: "HomeQueryEngine",
            sourceFunctionOrProperty: "safeSpendTodayAnswer(_:context:now:calendar:)",
            displayedMetric: "Safe spend today",
            sourceEntities: ["Budget", "Income", "VariableExpense", "PlannedExpense", "SavingsLedgerEntry"],
            dateRangeBehavior: "active/current budget period",
            filterBehavior: "workspace broad",
            marinaSupportStatus: .supportedRoute,
            marinaRoute: "HomeQueryMetric.safeSpendToday",
            unsupportedReason: nil
        ),
        surface(
            id: "home.next.planned.expense",
            surfaceName: "Home next planned expense tile",
            sourcePath: "OffshoreBudgeting/CoreViews/Home/HomeQueryEngine.swift",
            sourceTypeName: "HomeQueryEngine",
            sourceFunctionOrProperty: "nextPlannedExpenseAnswer(_:context:now:calendar:)",
            displayedMetric: "Next planned expense",
            sourceEntities: ["PlannedExpense", "Card", "Category"],
            dateRangeBehavior: "future from now",
            filterBehavior: "workspace broad; optional filters should clarify until supported",
            marinaSupportStatus: .supportedRoute,
            marinaRoute: "HomeQueryMetric.nextPlannedExpense",
            unsupportedReason: nil
        ),
        surface(
            id: "budget.linked.summary",
            surfaceName: "Budget linked summary",
            sourcePath: "OffshoreBudgeting/CoreViews/Home/NLQ/Boundary/MarinaComposableWorkspaceQueryExecutor.swift",
            sourceTypeName: "MarinaComposableWorkspaceQueryExecutor",
            sourceFunctionOrProperty: "budgetLinkedSummary(budget:plan:provider:)",
            displayedMetric: "Budget linked cards, presets, limits, variable/planned spend",
            sourceEntities: ["Budget", "BudgetCardLink", "BudgetPresetLink", "BudgetCategoryLimit", "VariableExpense", "PlannedExpense"],
            dateRangeBehavior: "budget inclusive range unless query range provided",
            filterBehavior: "budget target",
            marinaSupportStatus: .supportedRoute,
            marinaRoute: "MarinaComposableWorkspaceQueryExecutor.budgetLinkedSummary",
            unsupportedReason: nil
        ),
        surface(
            id: "reconciliation.shared.balances",
            surfaceName: "Shared balances summary",
            sourcePath: "OffshoreBudgeting/CoreViews/Home/NLQ/Boundary/MarinaWorkspaceAggregationExecutor.swift",
            sourceTypeName: "MarinaWorkspaceAggregationExecutor",
            sourceFunctionOrProperty: "sharedBalances(plan:provider:)",
            displayedMetric: "Reconciliation account balances",
            sourceEntities: ["AllocationAccount", "ExpenseAllocation", "AllocationSettlement"],
            dateRangeBehavior: "all-time/account ledger unless executor range applies",
            filterBehavior: "allocation account grouping",
            marinaSupportStatus: .supportedRoute,
            marinaRoute: "MarinaWorkspaceAggregationExecutor shared balances",
            unsupportedReason: nil
        ),
        surface(
            id: "whatif.simulation",
            surfaceName: "What If simulation",
            sourcePath: "OffshoreBudgeting/CoreViews/Home/NLQ/Boundary/MarinaComposableWorkspaceQueryExecutor.swift",
            sourceTypeName: "MarinaComposableWorkspaceQueryExecutor",
            sourceFunctionOrProperty: "simulate(candidate:resolved:plan:provider:now:)",
            displayedMetric: "Scenario budget impact",
            sourceEntities: ["Budget", "BudgetCategoryLimit", "Income", "VariableExpense", "PlannedExpense"],
            dateRangeBehavior: "query range or current month",
            filterBehavior: "category/simulation input",
            marinaSupportStatus: .structuredClarificationRoute,
            marinaRoute: "MarinaComposableWorkspaceQueryExecutor.simulate when amount and target are resolved",
            unsupportedReason: "Ambiguous or missing simulation amount/target requires structured clarification."
        )
    ]

    static func record(for entityName: String) -> MarinaEntityCapabilityRecord? {
        records.first { $0.entityName == entityName }
    }

    static func surfaceMetric(for id: String) -> MarinaAppSurfaceMetricRecord? {
        appSurfaceMetrics.first { $0.id == id }
    }

    static func supports(
        operation: MarinaCandidateOperation,
        measure: MarinaCandidateMeasure,
        targetTypes: [MarinaCandidateEntityTypeHint],
        grouping: MarinaGroupingDimensionCandidate?
    ) -> Bool {
        switch operation {
        case .sum:
            return [.spend, .income, .categoryShare, .presetAmount, .transactionAmount].contains(measure)
        case .average:
            return [.spend, .income, .savings].contains(measure)
        case .count:
            return measure == .transactionFrequency
        case .rank:
            return grouping != nil || measure == .reconciliationBalance || measure == .savingsMovement
        case .listRows:
            return [
                .transactionAmount,
                .income,
                .presetAmount,
                .savingsMovement,
                .reconciliationBalance,
                .remainingBudget
            ].contains(measure)
        case .compare:
            return [.spend, .income, .savings, .categoryShare].contains(measure)
        case .simulate:
            return measure == .remainingBudget
        case .forecast:
            return measure == .savings
        case .lookupDetails:
            return measure == .transactionAmount || measure == .savings || measure == .presetAmount || measure == .remainingBudget
        case .minimum, .maximum, .trend:
            return false
        }
    }

    static func capabilities(for type: MarinaLookupObjectType) -> Set<MarinaQueryCapability> {
        switch type {
        case .workspace:
            return [.lookupDetails, .linkedObjectSummary]
        case .budget:
            return [.lookupDetails, .listRows, .total, .compare, .linkedObjectSummary]
        case .card:
            return [.lookupDetails, .listRows, .total, .average, .rank, .compare, .groupedBreakdown, .linkedObjectSummary]
        case .category:
            return [.lookupDetails, .listRows, .total, .average, .rank, .compare, .groupedBreakdown, .linkedObjectSummary]
        case .preset:
            return [.lookupDetails, .listRows, .total, .rank, .groupedBreakdown, .linkedObjectSummary]
        case .variableExpense, .plannedExpense:
            return [.lookupDetails, .listRows, .rank, .compare]
        case .income:
            return [.lookupDetails, .listRows, .total, .average, .rank, .compare, .groupedBreakdown]
        case .incomeSeries:
            return [.lookupDetails, .listRows, .linkedObjectSummary]
        case .savingsAccount:
            return [.lookupDetails, .listRows, .total, .rank, .linkedObjectSummary]
        case .savingsLedgerEntry:
            return [.lookupDetails, .listRows, .rank, .compare]
        case .reconciliationAccount:
            return [.lookupDetails, .listRows, .total, .rank, .linkedObjectSummary]
        case .reconciliationItem, .expenseAllocation:
            return [.lookupDetails, .listRows, .rank, .compare]
        case .importMerchantRule, .assistantAliasRule:
            return [.lookupDetails, .listRows]
        case .unknown:
            return [.unsupportedWithClarification]
        }
    }

    private static func surface(
        id: String,
        surfaceName: String,
        sourcePath: String,
        sourceTypeName: String,
        sourceFunctionOrProperty: String,
        displayedMetric: String,
        sourceEntities: [String],
        dateRangeBehavior: String,
        filterBehavior: String,
        workspaceScopeBehavior: String = "MarinaDataProvider workspaceID / selected workspace",
        marinaSupportStatus: MarinaAppSurfaceSupportStatus,
        marinaRoute: String?,
        unsupportedReason: String?
    ) -> MarinaAppSurfaceMetricRecord {
        MarinaAppSurfaceMetricRecord(
            id: id,
            surfaceName: surfaceName,
            sourcePath: sourcePath,
            sourceTypeName: sourceTypeName,
            sourceFunctionOrProperty: sourceFunctionOrProperty,
            displayedMetric: displayedMetric,
            sourceEntities: sourceEntities,
            dateRangeBehavior: dateRangeBehavior,
            filterBehavior: filterBehavior,
            workspaceScopeBehavior: workspaceScopeBehavior,
            marinaSupportStatus: marinaSupportStatus,
            marinaRoute: marinaRoute,
            unsupportedReason: unsupportedReason
        )
    }
}
