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
        #expect(semanticQuery.dateRange?.resolvedRange == range)
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
        #expect(plan.dateRange == primary)
        #expect(plan.comparisonDateRange == comparison)
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

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }
}
