import Foundation
import Testing
@testable import Offshore

struct MarinaSemanticQueryTests {
    private let adapter = MarinaSemanticQueryAdapter()

    @Test func candidateToSemanticQuery_preservesAverageCategoryShape() {
        let range = HomeQueryDateRange(startDate: date(2026, 2, 1), endDate: date(2026, 4, 30))
        let mention = MarinaUnresolvedEntityMention(
            role: .primaryTarget,
            rawText: "Groceries",
            typeHint: .category,
            confidence: .high
        )
        let candidate = MarinaQueryPlanCandidate(
            source: .heuristic,
            rawPrompt: "What is my average grocery spend?",
            operation: .average,
            measure: .spend,
            entityMentions: [mention],
            timeScopes: [
                MarinaUnresolvedTimeScope(
                    role: .lookbackWindow,
                    rawText: "last three months",
                    resolvedRangeHint: range,
                    periodUnitHint: .month
                )
            ],
            grouping: MarinaGroupingCandidate(dimension: .month),
            responseShapeHint: .scalarCurrency,
            confidence: .high
        )

        guard case .query(let semanticQuery) = adapter.interpretationResult(from: candidate) else {
            Issue.record("Expected semantic query")
            return
        }

        #expect(semanticQuery.subject == .variableExpenses)
        #expect(semanticQuery.operation == .average)
        #expect(semanticQuery.amountField == .budgetImpactAmount)
        #expect(semanticQuery.averageBasis == .perMonth)
        assertDateRange(semanticQuery.dateRange?.resolvedRange, equals: range)
        #expect(semanticQuery.filters.count == 1)
        #expect(semanticQuery.filters.first?.relationship == .category)
        #expect(semanticQuery.filters.first?.value == "Groceries")
        #expect(semanticQuery.responseShape == .scalarCurrency)
    }

    @Test func candidateToSemanticQuery_preservesSemanticCommandListRowsShape() {
        let command = MarinaSemanticCommand(
            family: .analytics,
            action: .listRows,
            datasets: [.variableExpenses, .plannedExpenses],
            measure: nil,
            includeFilters: [
                MarinaSemanticCommandFilter(rawText: "Cannabis", allowedTypes: [.category, .merchant, .expense])
            ],
            excludeFilters: [],
            grouping: .transaction,
            sort: .newest,
            dateRange: nil,
            comparisonDateRange: nil,
            periodUnit: nil,
            limit: 5,
            requestedDetail: nil
        )
        let candidate = MarinaFoundationModelsInterpreter().candidate(
            from: .semanticCommand(command),
            prompt: "List my last 5 Cannabis purchases",
            defaultPeriodUnit: .month
        )

        guard case .query(let semanticQuery) = adapter.interpretationResult(from: candidate) else {
            Issue.record("Expected semantic query")
            return
        }

        #expect(semanticQuery.subject == .variableExpenses)
        #expect(semanticQuery.operation == .list)
        #expect(semanticQuery.amountField == .budgetImpactAmount)
        #expect(semanticQuery.grouping?.dimension == .transaction)
        #expect(semanticQuery.ranking?.direction == .newest)
        #expect(semanticQuery.limit == 5)
        #expect(semanticQuery.filters.first?.relationship == .unknown)
        #expect(semanticQuery.filters.first?.value == "Cannabis")
        #expect(semanticQuery.filters.first?.allowedEntityTypeHints == [.category, .merchant, .expense])
    }

    @Test func heuristicCanProduceCanonicalSemanticQuery() {
        let result = MarinaHeuristicInterpreter().interpretSemantic(
            prompt: "What did I spend on groceries this month?",
            defaultPeriodUnit: .month
        )

        guard case .query(let semanticQuery) = result else {
            Issue.record("Expected semantic query")
            return
        }

        #expect(semanticQuery.subject == .variableExpenses)
        #expect(semanticQuery.operation == .sum)
        #expect(semanticQuery.amountField == .budgetImpactAmount)
        #expect(semanticQuery.filters.first?.value.localizedCaseInsensitiveContains("grocer") == true)
        #expect(semanticQuery.filters.first?.entityTypeHint == .category)
    }

    @Test func heuristicCanonicalInterpretationMapsIncomeStatusWordsToScopeNotTargets() {
        let cases: [(String, MarinaIncomeStatusScope)] = [
            ("What is my actual income this month?", .actual),
            ("What is my planned income this month?", .planned),
            ("What is my income so far this month?", .all)
        ]

        for testCase in cases {
            let result = MarinaHeuristicInterpreter().interpretSemantic(
                prompt: testCase.0,
                defaultPeriodUnit: .month
            )

            guard case .query(let semanticQuery) = result else {
                Issue.record("Expected semantic query for \(testCase.0)")
                continue
            }

            #expect(semanticQuery.subject == .income)
            #expect(semanticQuery.operation == .sum)
            #expect(semanticQuery.amountField == .incomeAmount)
            #expect(semanticQuery.incomeStatusScope == testCase.1)
            #expect(semanticQuery.filters.isEmpty)
        }
    }

    @Test func semanticCommandIncomeStatusFilterDoesNotBecomeResolvedTarget() {
        let command = MarinaSemanticCommand(
            family: .analytics,
            action: .total,
            datasets: [.income],
            measure: .income,
            includeFilters: [
                MarinaSemanticCommandFilter(rawText: "actual", allowedTypes: [.incomeSource])
            ],
            incomeStatusScope: .actual
        )
        let candidate = MarinaFoundationModelsInterpreter().candidate(
            from: .semanticCommand(command),
            prompt: "What is my actual income this month?",
            defaultPeriodUnit: .month
        )

        guard case .query(let semanticQuery) = adapter.interpretationResult(from: candidate) else {
            Issue.record("Expected semantic query")
            return
        }

        #expect(semanticQuery.subject == .income)
        #expect(semanticQuery.incomeStatusScope == .actual)
        #expect(semanticQuery.filters.isEmpty)
    }

    @Test func heuristicCanonicalInterpretationCarriesCandidateOnlyAsShim() {
        let interpretation = MarinaHeuristicInterpreter().interpretCanonical(
            prompt: "What did I spend on groceries this month?",
            defaultPeriodUnit: .month
        )

        guard case .query(let semanticQuery) = interpretation.result else {
            Issue.record("Expected semantic query")
            return
        }

        #expect(semanticQuery.operation == .sum)
        #expect(semanticQuery.amountField == .budgetImpactAmount)
        #expect(interpretation.compatibilityCandidate.source == .heuristic)
        #expect(interpretation.compatibilityCandidate.operation == .sum)
        #expect(interpretation.compatibilityCandidate.measure == .spend)
    }

    @Test func foundationModelsCanProduceCanonicalSemanticQueryFromSemanticCommand() {
        let command = MarinaSemanticCommand(
            family: .analytics,
            action: .compare,
            datasets: [.variableExpenses],
            measure: .spend,
            includeFilters: [
                MarinaSemanticCommandFilter(rawText: "Groceries", allowedTypes: [.category])
            ],
            excludeFilters: [],
            grouping: .category,
            sort: nil,
            dateRange: HomeQueryDateRange(startDate: date(2026, 5, 1), endDate: date(2026, 5, 31)),
            comparisonDateRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30)),
            periodUnit: .month,
            limit: nil,
            requestedDetail: nil
        )

        let result = MarinaFoundationModelsInterpreter().semanticInterpretation(
            from: .semanticCommand(command),
            prompt: "Compare groceries this month to last month",
            defaultPeriodUnit: .month
        )

        guard case .query(let semanticQuery) = result else {
            Issue.record("Expected semantic query")
            return
        }

        #expect(semanticQuery.subject == .variableExpenses)
        #expect(semanticQuery.operation == .compare)
        #expect(semanticQuery.filters.first?.allowedEntityTypeHints == [.category])
        assertDateRange(semanticQuery.dateRange?.resolvedRange, equals: command.dateRange)
        assertDateRange(semanticQuery.comparisonDateRange?.resolvedRange, equals: command.comparisonDateRange)
        #expect(semanticQuery.grouping?.dimension == .category)
        #expect(semanticQuery.responseShape == .comparison)
    }

    @Test func semanticQueryToAggregationPlan_preservesComparisonTargetAndRanges() {
        let primary = HomeQueryDateRange(startDate: date(2026, 5, 1), endDate: date(2026, 5, 31))
        let comparison = HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30))
        let semanticQuery = MarinaSemanticQuery(
            subject: .variableExpenses,
            operation: .compare,
            filters: [
                MarinaFilter(
                    role: .primaryTarget,
                    relationship: .category,
                    value: "Groceries",
                    entityTypeHint: .category
                )
            ],
            amountField: .budgetImpactAmount,
            dateRange: MarinaDateRangeRequest(role: .primary, resolvedRange: primary, periodUnit: .month),
            comparisonDateRange: MarinaDateRangeRequest(role: .comparison, resolvedRange: comparison, periodUnit: .month),
            responseShape: .comparison
        )

        let plan = adapter.aggregationPlan(from: semanticQuery)

        #expect(plan.operation == .compare)
        #expect(plan.measure == .spend)
        #expect(plan.targets.first?.entityType == .category)
        #expect(plan.targets.first?.displayName == "Groceries")
        assertDateRange(plan.dateRange, equals: primary)
        assertDateRange(plan.comparisonDateRange, equals: comparison)
        #expect(plan.responseShape == .comparison)
    }

    @Test func semanticQueryToAggregationPlan_mapsPercentageShareToCategoryShareMeasure() {
        let semanticQuery = MarinaSemanticQuery(
            subject: .variableExpenses,
            operation: .percentageShare,
            filters: [
                MarinaFilter(
                    role: .primaryTarget,
                    relationship: .category,
                    value: "Groceries",
                    entityTypeHint: .category
                )
            ],
            amountField: .budgetImpactAmount,
            responseShape: .groupedBreakdown
        )

        let plan = adapter.aggregationPlan(from: semanticQuery)

        #expect(plan.operation == .sum)
        #expect(plan.measure == .categoryShare)
        #expect(plan.targets.first?.entityType == .category)
        #expect(plan.responseShape == .groupedBreakdown)
    }

    @Test func candidateToSemanticQuery_missingOperationReturnsTypedUnsupported() {
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: "groceries",
            measure: .spend,
            confidence: .medium
        )

        guard case .unsupported(let unsupported) = adapter.interpretationResult(from: candidate) else {
            Issue.record("Expected typed unsupported")
            return
        }

        #expect(unsupported.kind == .unsupportedOperation)
        #expect(unsupported.candidate?.rawPrompt == "groceries")
    }

    @Test func semanticExecutionRouter_classifiesValidatedSemanticRoutes() {
        let router = MarinaSemanticExecutionRouter()

        assertRoute(
            router.route(
                validationOutcome: outcome(
                    operation: .sum,
                    measure: .spend,
                    query: MarinaSemanticQuery(
                        subject: .variableExpenses,
                        operation: .sum,
                        amountField: .budgetImpactAmount
                    )
                ),
                semanticResolved: resolved(
                    MarinaSemanticQuery(
                        subject: .variableExpenses,
                        operation: .sum,
                        amountField: .budgetImpactAmount
                    )
                )
            ),
            "aggregate"
        )

        assertRoute(
            router.route(
                validationOutcome: outcome(
                    operation: .lookupDetails,
                    measure: .spend,
                    query: MarinaSemanticQuery(subject: .variableExpenses, operation: .lookupDetails)
                ),
                semanticResolved: resolved(MarinaSemanticQuery(subject: .variableExpenses, operation: .lookupDetails))
            ),
            "lookupDetail"
        )

        assertRoute(
            router.route(
                validationOutcome: outcome(
                    operation: .listRows,
                    measure: .transactionAmount,
                    grouping: MarinaGroupingCandidate(dimension: .transaction),
                    query: MarinaSemanticQuery(
                        subject: .variableExpenses,
                        operation: .list,
                        grouping: MarinaGrouping(dimension: .transaction, rawText: nil),
                        responseShape: .rankedList
                    )
                ),
                semanticResolved: resolved(
                    MarinaSemanticQuery(
                        subject: .variableExpenses,
                        operation: .list,
                        grouping: MarinaGrouping(dimension: .transaction, rawText: nil),
                        responseShape: .rankedList
                    )
                )
            ),
            "list"
        )

        assertRoute(
            router.route(
                validationOutcome: outcome(
                    operation: .compare,
                    measure: .spend,
                    query: MarinaSemanticQuery(subject: .variableExpenses, operation: .compare)
                ),
                semanticResolved: resolved(MarinaSemanticQuery(subject: .variableExpenses, operation: .compare))
            ),
            "comparison"
        )

        assertRoute(
            router.route(
                validationOutcome: outcome(
                    operation: .rank,
                    measure: .spend,
                    grouping: MarinaGroupingCandidate(dimension: .category),
                    responseShape: .rankedList,
                    query: MarinaSemanticQuery(
                        subject: .variableExpenses,
                        operation: .rank,
                        grouping: MarinaGrouping(dimension: .category, rawText: nil),
                        responseShape: .rankedList
                    )
                ),
                semanticResolved: resolved(
                    MarinaSemanticQuery(
                        subject: .variableExpenses,
                        operation: .rank,
                        grouping: MarinaGrouping(dimension: .category, rawText: nil),
                        responseShape: .rankedList
                    )
                )
            ),
            "groupedRanked"
        )

        assertRoute(
            router.route(
                validationOutcome: outcome(
                    operation: .simulate,
                    measure: .spend,
                    query: MarinaSemanticQuery(subject: .variableExpenses, operation: .simulate)
                ),
                semanticResolved: resolved(MarinaSemanticQuery(subject: .variableExpenses, operation: .simulate))
            ),
            "scenario"
        )
    }

    @Test func semanticExecutionRouter_returnsRouteAndAmountBasisDecision() {
        let router = MarinaSemanticExecutionRouter()
        let query = MarinaSemanticQuery(
            subject: .reconciliationAccounts,
            operation: .rank,
            amountField: .reconciliationBalance,
            responseShape: .rankedList
        )
        let decision = router.decision(
            validationOutcome: outcome(
                operation: .rank,
                measure: .reconciliationBalance,
                grouping: MarinaGroupingCandidate(dimension: .allocationAccount),
                responseShape: .rankedList,
                query: query
            ),
            semanticResolved: resolved(query)
        )

        #expect(decision.route.traceName == "groupedRanked")
        #expect(decision.amountBasis == .reconciliationBalance)
        #expect(decision.route.traceName == "groupedRanked")
    }

    @Test func amountBasisAdapter_namesFinancialMathBasisWithoutChangingFormulas() {
        let adapter = MarinaAmountBasisAdapter()

        #expect(
            adapter.basis(
                plan: MarinaAggregationPlan(operation: .sum, measure: .spend),
                semanticQuery: MarinaSemanticQuery(
                    subject: .variableExpenses,
                    operation: .sum,
                    amountField: .budgetImpactAmount
                )
            ) == .budgetImpact
        )
        #expect(
            adapter.basis(
                plan: MarinaAggregationPlan(
                    operation: .rank,
                    measure: .spend,
                    grouping: MarinaGroupingCandidate(dimension: .card)
                ),
                semanticQuery: MarinaSemanticQuery(subject: .cards, operation: .rank)
            ) == .budgetImpact
        )
        #expect(
            adapter.basis(
                plan: MarinaAggregationPlan(operation: .lookupDetails, measure: .remainingBudget),
                semanticQuery: MarinaSemanticQuery(subject: .budgets, operation: .lookupDetails)
            ) == .budgetImpact
        )
        #expect(
            adapter.basis(
                plan: MarinaAggregationPlan(operation: .rank, measure: .reconciliationBalance),
                semanticQuery: MarinaSemanticQuery(subject: .reconciliationAccounts, operation: .rank)
            ) == .reconciliationBalance
        )
        #expect(
            adapter.basis(
                plan: MarinaAggregationPlan(operation: .listRows, measure: .transactionAmount),
                semanticQuery: MarinaSemanticQuery(subject: .variableExpenses, operation: .list)
            ) == .budgetImpact
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func assertDateRange(
        _ actual: HomeQueryDateRange?,
        equals expected: HomeQueryDateRange?
    ) {
        guard let expected else {
            #expect(actual?.startDate == nil)
            #expect(actual?.endDate == nil)
            return
        }
        guard let actual else {
            Issue.record("Expected date range")
            return
        }
        #expect(actual.startDate == expected.startDate)
        #expect(actual.endDate == expected.endDate)
    }

    private func assertRoute(
        _ actual: MarinaSemanticExecutionRoute,
        _ expectedTraceName: String
    ) {
        #expect(actual.traceName == expectedTraceName)
    }

    private func outcome(
        operation: MarinaCandidateOperation,
        measure: MarinaCandidateMeasure,
        grouping: MarinaGroupingCandidate? = nil,
        responseShape: MarinaResponseShapeHint? = nil,
        query: MarinaSemanticQuery
    ) -> MarinaPlanValidationOutcome {
        .executable(
            MarinaAggregationPlan(
                operation: operation,
                measure: measure,
                grouping: grouping,
                responseShape: responseShape ?? query.responseShape.flatMap { shape in
                    switch shape {
                    case .scalarCurrency:
                        return .scalarCurrency
                    case .summaryCard:
                        return .summaryCard
                    case .comparison:
                        return .comparison
                    case .rankedList:
                        return .rankedList
                    case .groupedBreakdown:
                        return .groupedBreakdown
                    case .chartRows:
                        return .chartRows
                    case .clarification, .unsupported:
                        return nil
                    }
                }
            )
        )
    }

    private func resolved(_ query: MarinaSemanticQuery) -> MarinaResolvedSemanticQuery {
        MarinaResolvedSemanticQuery(
            query: query,
            candidate: nil,
            resolvedFilters: [],
            unresolvedFilters: [],
            ambiguousFilters: [],
            primaryDateRange: nil,
            comparisonDateRange: nil,
            databaseLookupRequest: nil
        )
    }
}
