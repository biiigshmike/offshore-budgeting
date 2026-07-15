import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// The V3 model-facing grammar. Query subjects and executable actions are
/// selected together so the generated payload cannot confuse the active
/// Workspace data boundary with the subject of the answer.
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable(description: "Exactly one read-only Marina semantic compiler V3 outcome.")
enum MarinaFoundationModelGeneratedOutcomeV3: Equatable, Sendable {
    case query(Query)
    case clarificationSelection(ClarificationSelection)
    case followUpDecision(FollowUpDecision)
    case unsupported(Unsupported)

    @Generable(description: "A domain-first read-only query. Choose the subject the answer is about, not the active Workspace data boundary.")
    enum Query: Equatable, Sendable {
        case workspaceMetadata(WorkspaceMetadataQuery)
        case budget(BudgetQuery)
        case card(CardQuery)
        case plannedExpense(PlannedExpenseQuery)
        case variableExpense(VariableExpenseQuery)
        case reconciliationAccount(ReconciliationAccountQuery)
        case savingsAccount(SavingsAccountQuery)
        case income(IncomeQuery)
        case incomeSeries(IncomeSeriesQuery)
        case category(CategoryQuery)
        case preset(PresetQuery)
    }

    @Generable(description: "A user's selection from the numbered clarification options supplied in trusted context.")
    struct ClarificationSelection: Equatable, Sendable {
        @Guide(description: "The zero-based option index shown in trusted prompt context.", .range(0...5))
        var index: Int
    }

    @Generable(description: "A user's decision about the single trusted follow-up supplied in prompt context.")
    struct FollowUpDecision: Equatable, Sendable {
        var decision: Decision

        @Generable
        enum Decision: Equatable, Sendable {
            case accept
            case decline
        }
    }

    @Generable(description: "A typed explanation that the request is outside Marina's read-only query contract.")
    struct Unsupported: Equatable, Sendable {
        var reason: UnsupportedReason
        var subject: Subject
        var attemptedOperation: AttemptedOperation
        var attemptedMeasure: AttemptedMeasure?
    }

    // MARK: - Shared query selections

    @Generable(description: "The trusted data boundary. This never identifies what the answer is about.")
    enum DataBoundary: Equatable, Sendable {
        case activeWorkspace
        case explicitNamedBudget(String)
    }

    @Generable(description: "Shared target, filters, and date semantics for one model-authored action.")
    struct Selection: Equatable, Sendable {
        @Guide(description: "The data boundary only. activeWorkspace means search within the active Workspace; it does not make Workspace the query subject.")
        var dataBoundary: DataBoundary

        @Guide(description: "The named record or concept the action is about, when the person supplied one.")
        var target: NamedTarget?

        @Guide(description: "Zero to six separately named restrictions. A filter is never the requested answer subject and never represents a date.", .maximumCount(6))
        var namedFilters: [NamedFilter]

        @Guide(description: "The requested date and its evidence source. previousMonth means the previous calendar month, not the previous budgeting period.")
        var dateSelection: DateSelection
    }

    @Generable(description: "A comparison selection. The comparison target exists only for compare actions.")
    struct ComparisonSelection: Equatable, Sendable {
        var selection: Selection
        @Guide(description: "A second named target only when the request compares named entities. Leave nil for period-only comparisons.")
        var comparisonTarget: NamedTarget?
    }

    @Generable(description: "Modifiers supported by record-list actions.")
    struct ListModifiers: Equatable, Sendable {
        var sort: Sort?

        @Guide(description: "Requested row count from 1 through 20, or nil when no count was requested.")
        var resultLimit: Int?

        var continuation: Continuation
    }

    @Generable(description: "Modifiers supported by group actions.")
    struct GroupModifiers: Equatable, Sendable {
        @Guide(description: "The single dimension used to group records.")
        var dimension: GroupDimension
        var sort: Sort?

        @Guide(description: "Requested group count from 1 through 20, or nil when no count was requested.")
        var resultLimit: Int?

        var continuation: Continuation
    }

    @Generable(description: "A named target preserving the person's wording and one internally consistent classification.")
    struct NamedTarget: Equatable, Sendable {
        var wording: String
        var classification: TargetClassification
    }

    @Generable(description: "A separately named query restriction. It is not the answer subject.")
    struct NamedFilter: Equatable, Sendable {
        var kind: FilterKind
        var value: String
        var evidence: Evidence
    }

    @Generable
    enum TargetKind: Equatable, Sendable {
        case budget
        case card
        case category
        case merchantText
        case incomeSource
        case incomeSeries
        case preset
        case savingsAccount
        case reconciliationAccount
    }

    @Generable
    enum TargetClassification: Equatable, Sendable {
        case unresolved
        case explicit(TargetKind)
        case inferred(TargetKind)
    }

    @Generable
    enum FilterKind: Equatable, Sendable {
        case category
        case card
        case merchantText
        case budget
        case incomeSource
        case incomeSeries
        case preset
        case savingsAccount
        case reconciliationAccount
    }

    @Generable
    enum Evidence: Equatable, Sendable {
        case explicit
        case inferred
    }

    @Generable
    enum GroupDimension: Equatable, Sendable {
        case category
        case card
        case incomeSource
        case incomeSeries
        case preset
        case budget
    }

    @Generable
    enum DateRange: Equatable, Sendable {
        case currentPeriod
        case previousPeriod
        case currentMonth
        case previousMonth
        case yearToDate
        case nextSevenDays
        case allTime
    }

    @Generable(description: "A date range paired with its only valid evidence source.")
    enum DateSelection: Equatable, Sendable {
        case defaultCurrentPeriod
        case explicit(DateRange)
        case conversationContext(DateRange)
    }

    @Generable
    enum Sort: Equatable, Sendable {
        case dateAscending
        case dateDescending
        case amountAscending
        case amountDescending
        case nameAscending
    }

    @Generable(description: "showMore continues trusted prior semantics; deterministic code supplies its offset.")
    enum Continuation: Equatable, Sendable {
        case none
        case showMore
    }

    @Generable
    enum ExpenseScope: Equatable, Sendable {
        case planned
        case variable
        case unified
    }

    @Generable
    enum IncomeState: Equatable, Sendable {
        case planned
        case actual
        case all
    }

    // MARK: - Workspace metadata

    @Generable(description: "Metadata about the active Workspace itself. Never use this merely because all queries are Workspace-scoped.")
    struct WorkspaceMetadataQuery: Equatable, Sendable {
        var action: WorkspaceMetadataAction
    }

    @Generable
    enum WorkspaceMetadataAction: Equatable, Sendable {
        case list(WorkspaceList)
        case count(WorkspaceCount)
        case name(WorkspaceMetadataValue)
        case color(WorkspaceMetadataValue)
    }

    @Generable
    struct WorkspaceList: Equatable, Sendable {
        var modifiers: ListModifiers
    }

    @Generable
    struct WorkspaceCount: Equatable, Sendable {}

    @Generable
    struct WorkspaceMetadataValue: Equatable, Sendable {}

    // MARK: - Budget

    @Generable(description: "A query whose answer subject is a budget or budget-period summary.")
    struct BudgetQuery: Equatable, Sendable {
        var action: BudgetAction
    }

    @Generable
    enum BudgetAction: Equatable, Sendable {
        case list(BudgetList)
        case sum(BudgetMetric)
        case average(BudgetMetric)
        case compare(BudgetComparison)
        case forecast(BudgetForecast)
        case whatIf(BudgetWhatIf)
    }

    @Generable
    struct BudgetList: Equatable, Sendable {
        var projection: BudgetListProjection
        var selection: Selection
        var modifiers: ListModifiers
    }

    @Generable
    enum BudgetListProjection: Equatable, Sendable {
        case records
        case summary
        case income
        case expenses
        case linkedCards
        case linkedPresets
    }

    @Generable
    struct BudgetMetric: Equatable, Sendable {
        var measure: BudgetMetricMeasure
        var selection: Selection
    }

    @Generable
    struct BudgetComparison: Equatable, Sendable {
        var measure: BudgetComparisonMeasure
        var selection: ComparisonSelection
    }

    @Generable(description: "A budget forecast. safeDailySpend is the safe amount to spend today, not total remainingRoom.")
    struct BudgetForecast: Equatable, Sendable {
        var measure: BudgetForecastMeasure
        var selection: Selection
    }

    @Generable
    struct BudgetWhatIf: Equatable, Sendable {
        var measure: BudgetWhatIfMeasure
        var selection: Selection
        var amount: Double
    }

    @Generable
    enum BudgetMetricMeasure: Equatable, Sendable {
        case budgetImpact
        case projectedBudgetImpact
        case plannedIncomeTotal
        case actualIncomeTotal
        case plannedExpenseProjectedTotal
        case plannedExpenseActualTotal
        case plannedExpenseEffectiveTotal
        case variableExpenseTotal
        case unifiedExpenseTotal
        case maximumSavings
        case projectedSavings
        case actualSavings
        case remainingRoom
        case burnRate
        case projectedSpend
        case safeDailySpend
        case paceDifference
        case coverageRatio
    }

    @Generable
    enum BudgetComparisonMeasure: Equatable, Sendable {
        case budgetImpact
        case projectedBudgetImpact
        case plannedIncomeTotal
        case actualIncomeTotal
        case plannedExpenseProjectedTotal
        case plannedExpenseActualTotal
        case plannedExpenseEffectiveTotal
        case variableExpenseTotal
        case unifiedExpenseTotal
        case maximumSavings
        case projectedSavings
        case actualSavings
        case remainingRoom
        case burnRate
        case projectedSpend
        case safeDailySpend
        case paceDifference
        case coverageRatio
    }

    @Generable
    enum BudgetForecastMeasure: Equatable, Sendable {
        case projectedBudgetImpact
        case projectedSpend
        case projectedSavings
        case maximumSavings
        case remainingRoom
        case burnRate
        case safeDailySpend
        case paceDifference
        case coverageRatio
    }

    @Generable
    enum BudgetWhatIfMeasure: Equatable, Sendable {
        case remainingRoom
        case projectedSavings
        case projectedSpend
        case safeDailySpend
    }

    // MARK: - Card

    @Generable(description: "A query whose answer subject is a spending card.")
    struct CardQuery: Equatable, Sendable {
        var action: CardAction
    }

    @Generable
    enum CardAction: Equatable, Sendable {
        case list(CardList)
        case count(CardCount)
        case sum(CardMetric)
        case compare(CardComparison)
        case group(CardGroup)
    }

    @Generable
    struct CardList: Equatable, Sendable {
        var measure: CardMeasure?
        var selection: Selection
        var modifiers: ListModifiers
        var expenseScope: ExpenseScope?
    }

    @Generable
    struct CardCount: Equatable, Sendable {
        var selection: Selection
    }

    @Generable
    struct CardMetric: Equatable, Sendable {
        var measure: CardMeasure
        var selection: Selection
        var expenseScope: ExpenseScope?
    }

    @Generable
    struct CardComparison: Equatable, Sendable {
        var measure: CardMeasure
        var selection: ComparisonSelection
        var expenseScope: ExpenseScope?
    }

    @Generable
    struct CardGroup: Equatable, Sendable {
        var measure: CardMeasure
        var selection: Selection
        var modifiers: GroupModifiers
        var expenseScope: ExpenseScope?
    }

    @Generable
    enum CardMeasure: Equatable, Sendable {
        case budgetImpact
        case name
    }

    // MARK: - Expenses

    @Generable(description: "A query whose answer subject is a planned expense.")
    struct PlannedExpenseQuery: Equatable, Sendable {
        var action: PlannedExpenseAction
    }

    @Generable
    enum PlannedExpenseAction: Equatable, Sendable {
        case list(PlannedExpenseList)
        case count(ExpenseCount)
        case sum(PlannedExpenseMetric)
        case average(PlannedExpenseMetric)
        case last(PlannedExpenseSingle)
        case next(PlannedExpenseSingle)
        case group(PlannedExpenseGroup)
    }

    @Generable
    struct PlannedExpenseList: Equatable, Sendable {
        var measure: PlannedExpenseMeasure?
        var selection: Selection
        var modifiers: ListModifiers
        var expenseScope: ExpenseScope?
    }

    @Generable
    struct PlannedExpenseMetric: Equatable, Sendable {
        var measure: PlannedExpenseMeasure
        var selection: Selection
        var expenseScope: ExpenseScope?
    }

    @Generable
    struct PlannedExpenseSingle: Equatable, Sendable {
        var measure: PlannedExpenseMeasure
        var selection: Selection
        var sort: Sort?
        var expenseScope: ExpenseScope?
    }

    @Generable
    struct PlannedExpenseGroup: Equatable, Sendable {
        var measure: PlannedExpenseMeasure
        var selection: Selection
        var modifiers: GroupModifiers
        var expenseScope: ExpenseScope?
    }

    @Generable
    enum PlannedExpenseMeasure: Equatable, Sendable {
        case amount
        case plannedAmount
        case actualAmount
        case effectiveAmount
        case budgetImpact
        case projectedBudgetImpact
    }

    @Generable(description: "A query whose answer subject is an actual variable expense or transaction.")
    struct VariableExpenseQuery: Equatable, Sendable {
        var action: VariableExpenseAction
    }

    @Generable
    enum VariableExpenseAction: Equatable, Sendable {
        case list(VariableExpenseList)
        case count(ExpenseCount)
        case sum(VariableExpenseMetric)
        case average(VariableExpenseMetric)
        case last(VariableExpenseSingle)
        case group(VariableExpenseGroup)
    }

    @Generable
    struct ExpenseCount: Equatable, Sendable {
        var selection: Selection
        var expenseScope: ExpenseScope?
    }

    @Generable
    struct VariableExpenseList: Equatable, Sendable {
        var measure: VariableExpenseMeasure?
        var selection: Selection
        var modifiers: ListModifiers
        var expenseScope: ExpenseScope?
    }

    @Generable
    struct VariableExpenseMetric: Equatable, Sendable {
        var measure: VariableExpenseMeasure
        var selection: Selection
        var expenseScope: ExpenseScope?
    }

    @Generable
    struct VariableExpenseSingle: Equatable, Sendable {
        var measure: VariableExpenseMeasure
        var selection: Selection
        var sort: Sort?
        var expenseScope: ExpenseScope?
    }

    @Generable
    struct VariableExpenseGroup: Equatable, Sendable {
        var measure: VariableExpenseMeasure
        var selection: Selection
        var modifiers: GroupModifiers
        var expenseScope: ExpenseScope?
    }

    @Generable
    enum VariableExpenseMeasure: Equatable, Sendable {
        case amount
        case budgetImpact
        case ledgerSignedAmount
    }

    // MARK: - Reconciliation and savings

    @Generable(description: "A query whose answer subject is a reconciliation or allocation account.")
    struct ReconciliationAccountQuery: Equatable, Sendable {
        var action: ReconciliationAccountAction
    }

    @Generable
    enum ReconciliationAccountAction: Equatable, Sendable {
        case list(ReconciliationList)
        case count(AccountCount)
        case sum(ReconciliationMetric)
        case group(ReconciliationGroup)
    }

    @Generable
    struct ReconciliationList: Equatable, Sendable {
        var projection: AccountProjection
        var measure: ReconciliationMeasure?
        var selection: Selection
        var modifiers: ListModifiers
    }

    @Generable
    struct ReconciliationMetric: Equatable, Sendable {
        var measure: ReconciliationMeasure
        var selection: Selection
    }

    @Generable
    struct ReconciliationGroup: Equatable, Sendable {
        var measure: ReconciliationMeasure
        var selection: Selection
        var modifiers: GroupModifiers
    }

    @Generable
    enum ReconciliationMeasure: Equatable, Sendable {
        case name
        case color
        case reconciliationBalance
    }

    @Generable(description: "A query whose answer subject is a true savings account, never a reconciliation account.")
    struct SavingsAccountQuery: Equatable, Sendable {
        var action: SavingsAccountAction
    }

    @Generable
    enum SavingsAccountAction: Equatable, Sendable {
        case list(SavingsList)
        case count(AccountCount)
        case sum(SavingsMetric)
        case last(SavingsMetric)
        case group(SavingsGroup)
        case forecast(SavingsMetric)
    }

    @Generable
    struct SavingsList: Equatable, Sendable {
        var projection: AccountProjection
        var measure: SavingsMeasure?
        var selection: Selection
        var modifiers: ListModifiers
    }

    @Generable
    struct SavingsMetric: Equatable, Sendable {
        var measure: SavingsMeasure
        var selection: Selection
    }

    @Generable
    struct SavingsGroup: Equatable, Sendable {
        var measure: SavingsMeasure
        var selection: Selection
        var modifiers: GroupModifiers
    }

    @Generable
    enum SavingsMeasure: Equatable, Sendable {
        case name
        case savingsTotal
    }

    @Generable
    struct AccountCount: Equatable, Sendable {
        var selection: Selection
    }

    @Generable
    enum AccountProjection: Equatable, Sendable {
        case records
        case activity
    }

    // MARK: - Income

    @Generable(description: "A query whose answer subject is an income record. Actual means received income; planned means expected income.")
    struct IncomeQuery: Equatable, Sendable {
        var action: IncomeAction
    }

    @Generable
    enum IncomeAction: Equatable, Sendable {
        case list(IncomeList)
        case count(IncomeCount)
        case sum(IncomeMetric)
        case average(IncomeMetric)
        case compare(IncomeComparison)
        case group(IncomeGroup)
        case progress(IncomeProgress)
        case coverage(IncomeCoverage)
        case forecast(IncomeForecast)
    }

    @Generable
    struct IncomeList: Equatable, Sendable {
        var measure: IncomeAmountMeasure?
        var state: IncomeState?
        var selection: Selection
        var modifiers: ListModifiers
    }

    @Generable
    struct IncomeCount: Equatable, Sendable {
        var state: IncomeState?
        var selection: Selection
    }

    @Generable(description: "An income amount metric. The planned/actual/all state is required.")
    struct IncomeMetric: Equatable, Sendable {
        var measure: IncomeAmountMeasure
        var state: IncomeState
        var selection: Selection
    }

    @Generable(description: "An income amount comparison. The planned/actual/all state is required.")
    struct IncomeComparison: Equatable, Sendable {
        var measure: IncomeAmountMeasure
        var state: IncomeState
        var selection: ComparisonSelection
    }

    @Generable
    struct IncomeGroup: Equatable, Sendable {
        var measure: IncomeAmountMeasure
        var state: IncomeState
        var selection: Selection
        var modifiers: GroupModifiers
    }

    @Generable(description: "Income progress: actual income divided by planned income for the selected inclusive period.")
    struct IncomeProgress: Equatable, Sendable {
        var selection: Selection
    }

    @Generable(description: "Income coverage compared with planned expenses.")
    struct IncomeCoverage: Equatable, Sendable {
        var selection: Selection
    }

    @Generable
    struct IncomeForecast: Equatable, Sendable {
        var measure: IncomeForecastMeasure
        var state: IncomeState?
        var selection: Selection
    }

    @Generable
    enum IncomeAmountMeasure: Equatable, Sendable {
        case amount
        case incomeAmount
    }

    @Generable
    enum IncomeForecastMeasure: Equatable, Sendable {
        case incomeAmount
        case coverageRatio
    }

    @Generable(description: "A query whose answer subject is an income recurrence definition or its occurrences.")
    struct IncomeSeriesQuery: Equatable, Sendable {
        var action: IncomeSeriesAction
    }

    @Generable
    enum IncomeSeriesAction: Equatable, Sendable {
        case list(IncomeSeriesList)
        case count(IncomeSeriesCount)
        case last(IncomeSeriesSingle)
        case next(IncomeSeriesSingle)
    }

    @Generable
    struct IncomeSeriesList: Equatable, Sendable {
        var projection: IncomeSeriesProjection
        var measure: IncomeAmountMeasure?
        var selection: Selection
        var modifiers: ListModifiers
    }

    @Generable
    struct IncomeSeriesCount: Equatable, Sendable {
        var projection: IncomeSeriesProjection
        var selection: Selection
    }

    @Generable
    struct IncomeSeriesSingle: Equatable, Sendable {
        var projection: IncomeSeriesProjection
        var measure: IncomeAmountMeasure
        var selection: Selection
        var sort: Sort?
    }

    @Generable
    enum IncomeSeriesProjection: Equatable, Sendable {
        case records
        case occurrences
    }

    // MARK: - Category

    @Generable(description: "A query whose answer subject is a category. Category availability is distinct from ordinary category spending.")
    struct CategoryQuery: Equatable, Sendable {
        var action: CategoryAction
    }

    @Generable
    enum CategoryAction: Equatable, Sendable {
        case list(CategoryList)
        case count(CategoryCount)
        case sum(CategoryMetric)
        case average(CategoryMetric)
        case compare(CategoryComparison)
        case groupedSpend(CategoryGroupedSpend)
        case share(CategoryMetric)
        case forecast(CategoryForecast)
        case availabilitySummary(CategoryAvailabilitySummary)
        case availabilityList(CategoryAvailabilityList)
    }

    @Generable
    struct CategoryList: Equatable, Sendable {
        var measure: CategoryMetadataMeasure?
        var selection: Selection
        var modifiers: ListModifiers
    }

    @Generable
    struct CategoryCount: Equatable, Sendable {
        var selection: Selection
    }

    @Generable
    struct CategoryMetric: Equatable, Sendable {
        var measure: CategoryMetricMeasure
        var selection: Selection
        var expenseScope: ExpenseScope?
    }

    @Generable
    struct CategoryComparison: Equatable, Sendable {
        var measure: CategoryMetricMeasure
        var selection: ComparisonSelection
        var expenseScope: ExpenseScope?
    }

    @Generable(description: "Current-period spending grouped by a required dimension, sort, count, and expense scope.")
    struct CategoryGroupedSpend: Equatable, Sendable {
        var selection: Selection
        var dimension: GroupDimension
        var sort: Sort

        @Guide(description: "Requested group count from 1 through 20.", .range(1...20))
        var resultLimit: Int

        var continuation: Continuation
        var expenseScope: ExpenseScope
    }

    @Generable
    struct CategoryForecast: Equatable, Sendable {
        var measure: CategoryForecastMeasure
        var selection: Selection
    }

    @Generable(description: "A metric summary of category limit availability across all categories.")
    struct CategoryAvailabilitySummary: Equatable, Sendable {
        var selection: Selection
    }

    @Generable(description: "A list of categories filtered to exactly one availability state.")
    struct CategoryAvailabilityList: Equatable, Sendable {
        var status: CategoryAvailabilityStatus
        var selection: Selection
        var modifiers: ListModifiers
    }

    @Generable
    enum CategoryMetadataMeasure: Equatable, Sendable {
        case name
        case color
    }

    @Generable
    enum CategoryMetricMeasure: Equatable, Sendable {
        case budgetImpact
        case concentration
        case name
        case color
    }

    @Generable
    enum CategoryForecastMeasure: Equatable, Sendable {
        case concentration
    }

    @Generable
    enum CategoryAvailabilityStatus: Equatable, Sendable {
        case over
        case near
        case underLimit
    }

    // MARK: - Preset

    @Generable(description: "A query whose answer subject is a recurring planned-expense preset.")
    struct PresetQuery: Equatable, Sendable {
        var action: PresetAction
    }

    @Generable
    enum PresetAction: Equatable, Sendable {
        case list(PresetList)
        case sum(PresetMetric)
        case next(PresetSingle)
        case group(PresetGroup)
    }

    @Generable
    struct PresetList: Equatable, Sendable {
        var projection: PresetProjection
        var measure: PresetMeasure?
        var selection: Selection
        var modifiers: ListModifiers
    }

    @Generable
    struct PresetMetric: Equatable, Sendable {
        var measure: PresetMeasure
        var selection: Selection
    }

    @Generable
    struct PresetSingle: Equatable, Sendable {
        var measure: PresetMeasure
        var selection: Selection
        var sort: Sort?
    }

    @Generable
    struct PresetGroup: Equatable, Sendable {
        var measure: PresetMeasure
        var selection: Selection
        var modifiers: GroupModifiers
    }

    @Generable
    enum PresetProjection: Equatable, Sendable {
        case records
        case linkedBudgets
    }

    @Generable
    enum PresetMeasure: Equatable, Sendable {
        case plannedAmount
        case actualAmount
        case recurringBurden
        case name
    }

    // MARK: - Unsupported diagnostics

    @Generable
    enum Subject: Equatable, Sendable {
        case workspaceMetadata
        case budget
        case card
        case plannedExpense
        case variableExpense
        case reconciliationAccount
        case savingsAccount
        case income
        case incomeSeries
        case category
        case preset
    }

    @Generable
    enum AttemptedOperation: Equatable, Sendable {
        case list
        case count
        case sum
        case average
        case compare
        case last
        case next
        case group
        case share
        case forecast
        case whatIf
    }

    @Generable
    enum AttemptedMeasure: Equatable, Sendable {
        case amount
        case plannedAmount
        case actualAmount
        case effectiveAmount
        case budgetImpact
        case projectedBudgetImpact
        case ledgerSignedAmount
        case plannedIncomeTotal
        case actualIncomeTotal
        case plannedExpenseProjectedTotal
        case plannedExpenseActualTotal
        case plannedExpenseEffectiveTotal
        case variableExpenseTotal
        case unifiedExpenseTotal
        case savingsTotal
        case maximumSavings
        case projectedSavings
        case actualSavings
        case incomeAmount
        case reconciliationBalance
        case categoryAvailability
        case remainingRoom
        case burnRate
        case projectedSpend
        case safeDailySpend
        case paceDifference
        case coverageRatio
        case recurringBurden
        case concentration
        case color
        case name
    }

    @Generable
    enum UnsupportedReason: Equatable, Sendable {
        case readOnly
        case unsupportedCombination
        case incomeSavingsWhatIfUnsupported
    }
}
#endif
