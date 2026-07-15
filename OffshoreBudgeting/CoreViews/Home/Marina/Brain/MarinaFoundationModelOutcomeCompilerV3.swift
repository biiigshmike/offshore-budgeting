import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macCatalyst 26.0, *)
struct MarinaFoundationModelOutcomeCompilerV3 {
    typealias Generated = MarinaFoundationModelGeneratedOutcomeV3

    func interpretedRequest(
        from outcome: Generated,
        turn: MarinaSemanticCompilerTurnV3,
        diagnosticNotes: [String] = []
    ) throws -> MarinaInterpretedSemanticRequest {
        switch outcome {
        case .query(let query):
            return MarinaInterpretedSemanticRequest(
                request: try semanticRequest(from: query, turn: turn),
                confidence: .medium,
                source: .foundationModel,
                diagnosticNotes: diagnosticNotes
            )
        case .clarificationSelection(let selection):
            return MarinaInterpretedSemanticRequest(
                request: try semanticRequest(from: selection, turn: turn),
                confidence: .medium,
                source: .foundationModel,
                diagnosticNotes: diagnosticNotes + [
                    "FoundationModels V3 selected clarification index \(selection.index)."
                ]
            )
        case .followUpDecision(let decision):
            return MarinaInterpretedSemanticRequest(
                request: try semanticRequest(from: decision, turn: turn),
                confidence: .medium,
                source: .foundationModel,
                diagnosticNotes: diagnosticNotes + [
                    "FoundationModels V3 followUpDecision=\(decision.decision.diagnosticName)."
                ]
            )
        case .unsupported(let unsupported):
            return MarinaInterpretedSemanticRequest(
                request: semanticRequest(from: unsupported),
                confidence: .medium,
                source: .foundationModel,
                diagnosticNotes: diagnosticNotes
            )
        }
    }

    private func semanticRequest(
        from query: Generated.Query,
        turn: MarinaSemanticCompilerTurnV3
    ) throws -> MarinaSemanticRequest {
        try semanticRequest(from: draft(from: query), turn: turn)
    }

    private func semanticRequest(
        from draft: QueryDraft,
        turn: MarinaSemanticCompilerTurnV3
    ) throws -> MarinaSemanticRequest {
        try validate(draft.selection.target, emptyError: .emptyTarget)
        try validate(draft.comparisonTarget, emptyError: .emptyComparisonTarget)
        if let resultLimit = draft.resultLimit,
           (1...HomeQuery.maxResultLimit).contains(resultLimit) == false {
            throw MarinaFoundationModelInterpretationError.invalidGeneratedOutcome(.invalidResultLimit)
        }

        let (dateRange, dateSource) = try dateSelection(
            draft.selection.dateSelection,
            turn: turn
        )
        var constraints = try draft.selection.namedFilters.map(semanticConstraint)
        switch draft.selection.dataBoundary {
        case .activeWorkspace:
            break
        case .explicitNamedBudget(let rawName):
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.isEmpty == false else {
                throw MarinaFoundationModelInterpretationError.invalidGeneratedOutcome(.emptyNamedBudget)
            }
            if constraints.contains(where: { $0.dimension == .budget && $0.value == name }) == false {
                constraints.append(
                    MarinaSemanticConstraint(
                        dimension: .budget,
                        value: name,
                        kindSource: .explicit
                    )
                )
            }
        }

        let offset = try continuationOffset(for: draft.continuation, turn: turn)
        let primaryTarget = draft.selection.target.map(trimmed)
        let comparisonTarget = draft.comparisonTarget.map(trimmed)
        let merchantText = primaryTarget.flatMap { target in
            target.classification.kind == .merchantText ? target.wording : nil
        } ?? constraints.first { $0.dimension == .merchantText }?.value

        var dimensions = constraints.map(\.dimension)
        if let groupingDimension = draft.groupingDimension?.semanticDimension {
            dimensions.append(groupingDimension)
        }
        if let dimension = primaryTarget?.classification.kind?.semanticDimension {
            dimensions.append(dimension)
        }
        if let dimension = comparisonTarget?.classification.kind?.semanticDimension {
            dimensions.append(dimension)
        }

        return MarinaSemanticRequest(
            entity: draft.entity,
            operation: draft.operation,
            measure: draft.measure,
            projection: draft.projection,
            dimensions: unique(dimensions),
            constraints: constraints,
            dateRangeToken: dateRange,
            dateRangeSource: dateSource,
            targetName: primaryTarget?.wording,
            comparisonTargetName: comparisonTarget?.wording,
            textQuery: merchantText,
            targetKindSource: primaryTarget?.classification.semanticTargetKindSource ?? .unspecified,
            comparisonTargetKindSource: comparisonTarget?.classification.semanticTargetKindSource ?? .unspecified,
            continuationIntent: draft.continuation.semanticContinuation,
            resultLimit: draft.resultLimit,
            resultOffset: offset,
            sort: draft.sort?.semanticSort,
            expenseScope: draft.expenseScope?.semanticExpenseScope,
            incomeState: draft.incomeState?.semanticIncomeState,
            whatIfAmount: draft.whatIfAmount,
            categoryAvailabilityFilter: draft.categoryAvailabilityFilter,
            expectedAnswerShape: draft.answerShape
        )
    }

    private func semanticRequest(
        from selection: Generated.ClarificationSelection,
        turn: MarinaSemanticCompilerTurnV3
    ) throws -> MarinaSemanticRequest {
        guard turn.clarificationChoices.isEmpty == false else {
            throw MarinaFoundationModelInterpretationError.invalidGeneratedOutcome(.clarificationSelectionWithoutContext)
        }
        guard turn.clarificationChoices.indices.contains(selection.index) else {
            throw MarinaFoundationModelInterpretationError.invalidGeneratedOutcome(.clarificationSelectionOutOfBounds)
        }
        return turn.clarificationChoices[selection.index].executableRequest
    }

    private func semanticRequest(
        from followUpDecision: Generated.FollowUpDecision,
        turn: MarinaSemanticCompilerTurnV3
    ) throws -> MarinaSemanticRequest {
        guard let offeredFollowUp = turn.offeredFollowUp else {
            throw MarinaFoundationModelInterpretationError.invalidGeneratedOutcome(.followUpDecisionWithoutContext)
        }
        switch followUpDecision.decision {
        case .accept:
            guard offeredFollowUp.executionMode == .executable,
                  let storedRequest = offeredFollowUp.semanticRequest else {
                throw MarinaFoundationModelInterpretationError.invalidGeneratedOutcome(.followUpAcceptanceWithoutExecutableRequest)
            }
            return storedRequest
        case .decline:
            return MarinaSemanticRequest(
                entity: .workspace,
                operation: .list,
                expectedAnswerShape: .acknowledgement
            )
        }
    }

    private func semanticRequest(from unsupported: Generated.Unsupported) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: unsupported.subject.semanticEntity,
            operation: unsupported.attemptedOperation.semanticOperation,
            measure: unsupported.attemptedMeasure?.semanticMeasure,
            projection: .records,
            expectedAnswerShape: .unsupported,
            unsupportedReason: unsupported.reason.semanticReason
        )
    }

    private func dateSelection(
        _ selection: Generated.DateSelection,
        turn: MarinaSemanticCompilerTurnV3
    ) throws -> (MarinaSemanticDateRangeToken, MarinaSemanticDateRangeSource) {
        switch selection {
        case .defaultCurrentPeriod:
            return (.currentPeriod, .defaulted)
        case .explicit(let range):
            return (range.semanticDateRange, .explicit)
        case .conversationContext(let range):
            guard turn.priorRequest != nil else {
                throw MarinaFoundationModelInterpretationError.invalidGeneratedOutcome(.dateContextWithoutPriorRequest)
            }
            return (range.semanticDateRange, .conversationContext)
        }
    }

    private func semanticConstraint(
        _ filter: Generated.NamedFilter
    ) throws -> MarinaSemanticConstraint {
        let value = filter.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false else {
            throw MarinaFoundationModelInterpretationError.invalidGeneratedOutcome(.emptyNamedFilter)
        }
        return MarinaSemanticConstraint(
            dimension: filter.kind.semanticDimension,
            value: value,
            kindSource: filter.evidence.semanticTargetKindSource
        )
    }

    private func continuationOffset(
        for continuation: Generated.Continuation,
        turn: MarinaSemanticCompilerTurnV3
    ) throws -> Int? {
        switch continuation {
        case .none:
            return nil
        case .showMore:
            guard turn.priorRequest != nil else {
                throw MarinaFoundationModelInterpretationError.invalidGeneratedOutcome(.continuationWithoutContext)
            }
            guard let offset = turn.continuationOffset else {
                throw MarinaFoundationModelInterpretationError.invalidGeneratedOutcome(.continuationWithoutOffset)
            }
            return offset
        }
    }

    private func validate(
        _ target: Generated.NamedTarget?,
        emptyError: MarinaFoundationModelInvalidOutcome
    ) throws {
        guard let target else { return }
        guard target.wording.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw MarinaFoundationModelInterpretationError.invalidGeneratedOutcome(emptyError)
        }
    }

    private func trimmed(_ target: Generated.NamedTarget) -> Generated.NamedTarget {
        Generated.NamedTarget(
            wording: target.wording.trimmingCharacters(in: .whitespacesAndNewlines),
            classification: target.classification
        )
    }

    private func unique(_ dimensions: [MarinaSemanticDimension]) -> [MarinaSemanticDimension] {
        dimensions.reduce(into: []) { result, dimension in
            if result.contains(dimension) == false {
                result.append(dimension)
            }
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelOutcomeCompilerV3 {
    struct QueryDraft {
        let entity: MarinaSemanticEntity
        let operation: MarinaSemanticOperation
        let measure: MarinaSemanticMeasure?
        let projection: MarinaSemanticProjection
        let answerShape: MarinaSemanticAnswerShape
        let selection: Generated.Selection
        let comparisonTarget: Generated.NamedTarget?
        let groupingDimension: Generated.GroupDimension?
        let sort: Generated.Sort?
        let resultLimit: Int?
        let continuation: Generated.Continuation
        let expenseScope: Generated.ExpenseScope?
        let incomeState: Generated.IncomeState?
        let whatIfAmount: Double?
        let categoryAvailabilityFilter: MarinaCategoryAvailabilityFilter?

        init(
            entity: MarinaSemanticEntity,
            operation: MarinaSemanticOperation,
            measure: MarinaSemanticMeasure? = nil,
            projection: MarinaSemanticProjection = .records,
            answerShape: MarinaSemanticAnswerShape,
            selection: Generated.Selection,
            comparisonTarget: Generated.NamedTarget? = nil,
            groupingDimension: Generated.GroupDimension? = nil,
            sort: Generated.Sort? = nil,
            resultLimit: Int? = nil,
            continuation: Generated.Continuation = .none,
            expenseScope: Generated.ExpenseScope? = nil,
            incomeState: Generated.IncomeState? = nil,
            whatIfAmount: Double? = nil,
            categoryAvailabilityFilter: MarinaCategoryAvailabilityFilter? = nil
        ) {
            self.entity = entity
            self.operation = operation
            self.measure = measure
            self.projection = projection
            self.answerShape = answerShape
            self.selection = selection
            self.comparisonTarget = comparisonTarget
            self.groupingDimension = groupingDimension
            self.sort = sort
            self.resultLimit = resultLimit
            self.continuation = continuation
            self.expenseScope = expenseScope
            self.incomeState = incomeState
            self.whatIfAmount = whatIfAmount
            self.categoryAvailabilityFilter = categoryAvailabilityFilter
        }
    }

    func draft(from query: Generated.Query) -> QueryDraft {
        switch query {
        case .workspaceMetadata(let query): workspaceDraft(from: query)
        case .budget(let query): budgetDraft(from: query)
        case .card(let query): cardDraft(from: query)
        case .plannedExpense(let query): plannedExpenseDraft(from: query)
        case .variableExpense(let query): variableExpenseDraft(from: query)
        case .reconciliationAccount(let query): reconciliationDraft(from: query)
        case .savingsAccount(let query): savingsDraft(from: query)
        case .income(let query): incomeDraft(from: query)
        case .incomeSeries(let query): incomeSeriesDraft(from: query)
        case .category(let query): categoryDraft(from: query)
        case .preset(let query): presetDraft(from: query)
        }
    }

    func workspaceDraft(from query: Generated.WorkspaceMetadataQuery) -> QueryDraft {
        let selection = Generated.Selection(
            dataBoundary: .activeWorkspace,
            target: nil,
            namedFilters: [],
            dateSelection: .defaultCurrentPeriod
        )
        switch query.action {
        case .list(let list):
            return listDraft(entity: .workspace, measure: nil, selection: selection, modifiers: list.modifiers)
        case .count:
            return QueryDraft(entity: .workspace, operation: .count, answerShape: .metric, selection: selection)
        case .name:
            return QueryDraft(entity: .workspace, operation: .list, measure: .name, answerShape: .metric, selection: selection)
        case .color:
            return QueryDraft(entity: .workspace, operation: .list, measure: .color, answerShape: .metric, selection: selection)
        }
    }

    func budgetDraft(from query: Generated.BudgetQuery) -> QueryDraft {
        switch query.action {
        case .list(let list):
            return listDraft(
                entity: .budget,
                measure: nil,
                projection: list.projection.semanticProjection,
                selection: list.selection,
                modifiers: list.modifiers
            )
        case .sum(let metric):
            return metricDraft(entity: .budget, operation: .sum, measure: metric.measure.semanticMeasure, projection: .summary, selection: metric.selection)
        case .average(let metric):
            return metricDraft(entity: .budget, operation: .average, measure: metric.measure.semanticMeasure, projection: .summary, selection: metric.selection)
        case .compare(let comparison):
            return comparisonDraft(entity: .budget, measure: comparison.measure.semanticMeasure, projection: .summary, selection: comparison.selection)
        case .forecast(let forecast):
            return metricDraft(entity: .budget, operation: .forecast, measure: forecast.measure.semanticMeasure, projection: .summary, selection: forecast.selection)
        case .whatIf(let whatIf):
            return QueryDraft(
                entity: .budget,
                operation: .whatIf,
                measure: whatIf.measure.semanticMeasure,
                projection: .summary,
                answerShape: .comparison,
                selection: whatIf.selection,
                whatIfAmount: whatIf.amount
            )
        }
    }

    func cardDraft(from query: Generated.CardQuery) -> QueryDraft {
        switch query.action {
        case .list(let list):
            return listDraft(entity: .card, measure: list.measure?.semanticMeasure, selection: list.selection, modifiers: list.modifiers, expenseScope: list.expenseScope)
        case .count(let count):
            return QueryDraft(entity: .card, operation: .count, answerShape: .metric, selection: count.selection)
        case .sum(let metric):
            return metricDraft(entity: .card, operation: .sum, measure: metric.measure.semanticMeasure, selection: metric.selection, expenseScope: metric.expenseScope)
        case .compare(let comparison):
            return comparisonDraft(entity: .card, measure: comparison.measure.semanticMeasure, selection: comparison.selection, expenseScope: comparison.expenseScope)
        case .group(let group):
            return groupDraft(entity: .card, measure: group.measure.semanticMeasure, selection: group.selection, modifiers: group.modifiers, expenseScope: group.expenseScope)
        }
    }

    func plannedExpenseDraft(from query: Generated.PlannedExpenseQuery) -> QueryDraft {
        switch query.action {
        case .list(let list):
            return listDraft(entity: .plannedExpense, measure: list.measure?.semanticMeasure, selection: list.selection, modifiers: list.modifiers, expenseScope: list.expenseScope)
        case .count(let count):
            return countDraft(entity: .plannedExpense, count: count)
        case .sum(let metric):
            return metricDraft(entity: .plannedExpense, operation: .sum, measure: metric.measure.semanticMeasure, selection: metric.selection, expenseScope: metric.expenseScope)
        case .average(let metric):
            return metricDraft(entity: .plannedExpense, operation: .average, measure: metric.measure.semanticMeasure, selection: metric.selection, expenseScope: metric.expenseScope)
        case .last(let single):
            return singleDraft(entity: .plannedExpense, operation: .last, measure: single.measure.semanticMeasure, selection: single.selection, sort: single.sort, expenseScope: single.expenseScope)
        case .next(let single):
            return singleDraft(entity: .plannedExpense, operation: .next, measure: single.measure.semanticMeasure, selection: single.selection, sort: single.sort, expenseScope: single.expenseScope)
        case .group(let group):
            return groupDraft(entity: .plannedExpense, measure: group.measure.semanticMeasure, selection: group.selection, modifiers: group.modifiers, expenseScope: group.expenseScope)
        }
    }

    func variableExpenseDraft(from query: Generated.VariableExpenseQuery) -> QueryDraft {
        switch query.action {
        case .list(let list):
            return listDraft(entity: .variableExpense, measure: list.measure?.semanticMeasure, selection: list.selection, modifiers: list.modifiers, expenseScope: list.expenseScope)
        case .count(let count):
            return countDraft(entity: .variableExpense, count: count)
        case .sum(let metric):
            return metricDraft(entity: .variableExpense, operation: .sum, measure: metric.measure.semanticMeasure, selection: metric.selection, expenseScope: metric.expenseScope)
        case .average(let metric):
            return metricDraft(entity: .variableExpense, operation: .average, measure: metric.measure.semanticMeasure, selection: metric.selection, expenseScope: metric.expenseScope)
        case .last(let single):
            return singleDraft(entity: .variableExpense, operation: .last, measure: single.measure.semanticMeasure, selection: single.selection, sort: single.sort, expenseScope: single.expenseScope)
        case .group(let group):
            return groupDraft(entity: .variableExpense, measure: group.measure.semanticMeasure, selection: group.selection, modifiers: group.modifiers, expenseScope: group.expenseScope)
        }
    }

    func reconciliationDraft(from query: Generated.ReconciliationAccountQuery) -> QueryDraft {
        switch query.action {
        case .list(let list):
            return listDraft(entity: .reconciliationAccount, measure: list.measure?.semanticMeasure, projection: list.projection.semanticProjection, selection: list.selection, modifiers: list.modifiers)
        case .count(let count):
            return QueryDraft(entity: .reconciliationAccount, operation: .count, answerShape: .metric, selection: count.selection)
        case .sum(let metric):
            return metricDraft(entity: .reconciliationAccount, operation: .sum, measure: metric.measure.semanticMeasure, selection: metric.selection)
        case .group(let group):
            return groupDraft(entity: .reconciliationAccount, measure: group.measure.semanticMeasure, selection: group.selection, modifiers: group.modifiers)
        }
    }

    func savingsDraft(from query: Generated.SavingsAccountQuery) -> QueryDraft {
        switch query.action {
        case .list(let list):
            return listDraft(entity: .savingsAccount, measure: list.measure?.semanticMeasure, projection: list.projection.semanticProjection, selection: list.selection, modifiers: list.modifiers)
        case .count(let count):
            return QueryDraft(entity: .savingsAccount, operation: .count, answerShape: .metric, selection: count.selection)
        case .sum(let metric):
            return metricDraft(entity: .savingsAccount, operation: .sum, measure: metric.measure.semanticMeasure, selection: metric.selection)
        case .last(let metric):
            return metricDraft(entity: .savingsAccount, operation: .last, measure: metric.measure.semanticMeasure, selection: metric.selection)
        case .group(let group):
            return groupDraft(entity: .savingsAccount, measure: group.measure.semanticMeasure, selection: group.selection, modifiers: group.modifiers)
        case .forecast(let metric):
            return metricDraft(entity: .savingsAccount, operation: .forecast, measure: metric.measure.semanticMeasure, selection: metric.selection)
        }
    }

    func incomeDraft(from query: Generated.IncomeQuery) -> QueryDraft {
        switch query.action {
        case .list(let list):
            return listDraft(entity: .income, measure: list.measure?.semanticMeasure, selection: list.selection, modifiers: list.modifiers, incomeState: list.state)
        case .count(let count):
            return QueryDraft(entity: .income, operation: .count, answerShape: .metric, selection: count.selection, incomeState: count.state)
        case .sum(let metric):
            return incomeMetricDraft(operation: .sum, metric: metric)
        case .average(let metric):
            return incomeMetricDraft(operation: .average, metric: metric)
        case .compare(let comparison):
            return QueryDraft(
                entity: .income,
                operation: .compare,
                measure: comparison.measure.semanticMeasure,
                answerShape: .comparison,
                selection: comparison.selection.selection,
                comparisonTarget: comparison.selection.comparisonTarget,
                incomeState: comparison.state
            )
        case .group(let group):
            return groupDraft(entity: .income, measure: group.measure.semanticMeasure, selection: group.selection, modifiers: group.modifiers, incomeState: group.state)
        case .progress(let progress):
            return metricDraft(entity: .income, operation: .share, measure: .incomeAmount, selection: progress.selection, incomeState: .all)
        case .coverage(let coverage):
            return metricDraft(entity: .income, operation: .share, measure: .coverageRatio, selection: coverage.selection)
        case .forecast(let forecast):
            return metricDraft(entity: .income, operation: .forecast, measure: forecast.measure.semanticMeasure, selection: forecast.selection, incomeState: forecast.state)
        }
    }

    func incomeSeriesDraft(from query: Generated.IncomeSeriesQuery) -> QueryDraft {
        switch query.action {
        case .list(let list):
            return listDraft(entity: .incomeSeries, measure: list.measure?.semanticMeasure, projection: list.projection.semanticProjection, selection: list.selection, modifiers: list.modifiers)
        case .count(let count):
            return QueryDraft(entity: .incomeSeries, operation: .count, projection: count.projection.semanticProjection, answerShape: .metric, selection: count.selection)
        case .last(let single):
            return singleDraft(entity: .incomeSeries, operation: .last, measure: single.measure.semanticMeasure, projection: single.projection.semanticProjection, selection: single.selection, sort: single.sort)
        case .next(let single):
            return singleDraft(entity: .incomeSeries, operation: .next, measure: single.measure.semanticMeasure, projection: single.projection.semanticProjection, selection: single.selection, sort: single.sort)
        }
    }

    func categoryDraft(from query: Generated.CategoryQuery) -> QueryDraft {
        switch query.action {
        case .list(let list):
            return listDraft(entity: .category, measure: list.measure?.semanticMeasure, selection: list.selection, modifiers: list.modifiers)
        case .count(let count):
            return QueryDraft(entity: .category, operation: .count, answerShape: .metric, selection: count.selection)
        case .sum(let metric):
            return metricDraft(entity: .category, operation: .sum, measure: metric.measure.semanticMeasure, selection: metric.selection, expenseScope: metric.expenseScope)
        case .average(let metric):
            return metricDraft(entity: .category, operation: .average, measure: metric.measure.semanticMeasure, selection: metric.selection, expenseScope: metric.expenseScope)
        case .compare(let comparison):
            return comparisonDraft(entity: .category, measure: comparison.measure.semanticMeasure, selection: comparison.selection, expenseScope: comparison.expenseScope)
        case .groupedSpend(let group):
            return QueryDraft(
                entity: .category,
                operation: .group,
                measure: .budgetImpact,
                answerShape: .list,
                selection: group.selection,
                groupingDimension: group.dimension,
                sort: group.sort,
                resultLimit: group.resultLimit,
                continuation: group.continuation,
                expenseScope: group.expenseScope
            )
        case .share(let metric):
            return metricDraft(entity: .category, operation: .share, measure: metric.measure.semanticMeasure, selection: metric.selection, expenseScope: metric.expenseScope)
        case .forecast(let forecast):
            return metricDraft(entity: .category, operation: .forecast, measure: forecast.measure.semanticMeasure, selection: forecast.selection)
        case .availabilitySummary(let summary):
            return metricDraft(entity: .category, operation: .forecast, measure: .categoryAvailability, selection: summary.selection)
        case .availabilityList(let list):
            return QueryDraft(
                entity: .category,
                operation: .list,
                measure: .categoryAvailability,
                answerShape: .list,
                selection: list.selection,
                sort: list.modifiers.sort,
                resultLimit: list.modifiers.resultLimit,
                continuation: list.modifiers.continuation,
                categoryAvailabilityFilter: list.status.semanticFilter
            )
        }
    }

    func presetDraft(from query: Generated.PresetQuery) -> QueryDraft {
        switch query.action {
        case .list(let list):
            return listDraft(entity: .preset, measure: list.measure?.semanticMeasure, projection: list.projection.semanticProjection, selection: list.selection, modifiers: list.modifiers)
        case .sum(let metric):
            return metricDraft(entity: .preset, operation: .sum, measure: metric.measure.semanticMeasure, selection: metric.selection)
        case .next(let single):
            return singleDraft(entity: .preset, operation: .next, measure: single.measure.semanticMeasure, selection: single.selection, sort: single.sort)
        case .group(let group):
            return groupDraft(entity: .preset, measure: group.measure.semanticMeasure, selection: group.selection, modifiers: group.modifiers)
        }
    }

    func listDraft(
        entity: MarinaSemanticEntity,
        measure: MarinaSemanticMeasure?,
        projection: MarinaSemanticProjection = .records,
        selection: Generated.Selection,
        modifiers: Generated.ListModifiers,
        expenseScope: Generated.ExpenseScope? = nil,
        incomeState: Generated.IncomeState? = nil
    ) -> QueryDraft {
        QueryDraft(
            entity: entity,
            operation: .list,
            measure: measure,
            projection: projection,
            answerShape: .list,
            selection: selection,
            sort: modifiers.sort,
            resultLimit: modifiers.resultLimit,
            continuation: modifiers.continuation,
            expenseScope: expenseScope,
            incomeState: incomeState
        )
    }

    func countDraft(entity: MarinaSemanticEntity, count: Generated.ExpenseCount) -> QueryDraft {
        QueryDraft(
            entity: entity,
            operation: .count,
            answerShape: .metric,
            selection: count.selection,
            expenseScope: count.expenseScope
        )
    }

    func metricDraft(
        entity: MarinaSemanticEntity,
        operation: MarinaSemanticOperation,
        measure: MarinaSemanticMeasure,
        projection: MarinaSemanticProjection = .records,
        selection: Generated.Selection,
        expenseScope: Generated.ExpenseScope? = nil,
        incomeState: Generated.IncomeState? = nil
    ) -> QueryDraft {
        QueryDraft(
            entity: entity,
            operation: operation,
            measure: measure,
            projection: projection,
            answerShape: .metric,
            selection: selection,
            expenseScope: expenseScope,
            incomeState: incomeState
        )
    }

    func incomeMetricDraft(operation: MarinaSemanticOperation, metric: Generated.IncomeMetric) -> QueryDraft {
        metricDraft(
            entity: .income,
            operation: operation,
            measure: metric.measure.semanticMeasure,
            selection: metric.selection,
            incomeState: metric.state
        )
    }

    func comparisonDraft(
        entity: MarinaSemanticEntity,
        measure: MarinaSemanticMeasure,
        projection: MarinaSemanticProjection = .records,
        selection: Generated.ComparisonSelection,
        expenseScope: Generated.ExpenseScope? = nil
    ) -> QueryDraft {
        QueryDraft(
            entity: entity,
            operation: .compare,
            measure: measure,
            projection: projection,
            answerShape: .comparison,
            selection: selection.selection,
            comparisonTarget: selection.comparisonTarget,
            expenseScope: expenseScope
        )
    }

    func groupDraft(
        entity: MarinaSemanticEntity,
        measure: MarinaSemanticMeasure,
        selection: Generated.Selection,
        modifiers: Generated.GroupModifiers,
        expenseScope: Generated.ExpenseScope? = nil,
        incomeState: Generated.IncomeState? = nil
    ) -> QueryDraft {
        QueryDraft(
            entity: entity,
            operation: .group,
            measure: measure,
            answerShape: .list,
            selection: selection,
            groupingDimension: modifiers.dimension,
            sort: modifiers.sort,
            resultLimit: modifiers.resultLimit,
            continuation: modifiers.continuation,
            expenseScope: expenseScope,
            incomeState: incomeState
        )
    }

    func singleDraft(
        entity: MarinaSemanticEntity,
        operation: MarinaSemanticOperation,
        measure: MarinaSemanticMeasure,
        projection: MarinaSemanticProjection = .records,
        selection: Generated.Selection,
        sort: Generated.Sort?,
        expenseScope: Generated.ExpenseScope? = nil
    ) -> QueryDraft {
        QueryDraft(
            entity: entity,
            operation: operation,
            measure: measure,
            projection: projection,
            answerShape: .metric,
            selection: selection,
            sort: sort,
            resultLimit: 1,
            expenseScope: expenseScope
        )
    }
}

// MARK: - Generated-to-semantic mappings

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.FollowUpDecision.Decision {
    var diagnosticName: String {
        switch self {
        case .accept: "accept"
        case .decline: "decline"
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.TargetClassification {
    var semanticTargetKindSource: MarinaSemanticTargetKindSource {
        switch self {
        case .unresolved: .unspecified
        case .explicit: .explicit
        case .inferred: .inferred
        }
    }

    var kind: MarinaFoundationModelGeneratedOutcomeV3.TargetKind? {
        switch self {
        case .unresolved: nil
        case .explicit(let kind), .inferred(let kind): kind
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.TargetKind {
    var semanticDimension: MarinaSemanticDimension {
        switch self {
        case .budget: .budget
        case .card: .card
        case .category: .category
        case .merchantText: .merchantText
        case .incomeSource: .incomeSource
        case .incomeSeries: .incomeSeries
        case .preset: .preset
        case .savingsAccount: .savingsAccount
        case .reconciliationAccount: .reconciliationAccount
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.FilterKind {
    var semanticDimension: MarinaSemanticDimension {
        switch self {
        case .category: .category
        case .card: .card
        case .merchantText: .merchantText
        case .budget: .budget
        case .incomeSource: .incomeSource
        case .incomeSeries: .incomeSeries
        case .preset: .preset
        case .savingsAccount: .savingsAccount
        case .reconciliationAccount: .reconciliationAccount
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.Evidence {
    var semanticTargetKindSource: MarinaSemanticTargetKindSource {
        switch self {
        case .explicit: .explicit
        case .inferred: .inferred
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.GroupDimension {
    var semanticDimension: MarinaSemanticDimension {
        switch self {
        case .category: .category
        case .card: .card
        case .incomeSource: .incomeSource
        case .incomeSeries: .incomeSeries
        case .preset: .preset
        case .budget: .budget
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.DateRange {
    var semanticDateRange: MarinaSemanticDateRangeToken {
        switch self {
        case .currentPeriod: .currentPeriod
        case .previousPeriod: .previousPeriod
        case .currentMonth: .currentMonth
        case .previousMonth: .previousMonth
        case .yearToDate: .yearToDate
        case .nextSevenDays: .nextSevenDays
        case .allTime: .allTime
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.Sort {
    var semanticSort: MarinaSemanticSort {
        switch self {
        case .dateAscending: .dateAscending
        case .dateDescending: .dateDescending
        case .amountAscending: .amountAscending
        case .amountDescending: .amountDescending
        case .nameAscending: .nameAscending
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.Continuation {
    var semanticContinuation: MarinaSemanticContinuationIntent {
        switch self {
        case .none: .none
        case .showMore: .showMore
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.ExpenseScope {
    var semanticExpenseScope: MarinaSemanticExpenseScope {
        switch self {
        case .planned: .planned
        case .variable: .variable
        case .unified: .unified
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.IncomeState {
    var semanticIncomeState: MarinaSemanticIncomeState {
        switch self {
        case .planned: .planned
        case .actual: .actual
        case .all: .all
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.BudgetListProjection {
    var semanticProjection: MarinaSemanticProjection {
        switch self {
        case .records: .records
        case .summary: .summary
        case .income: .income
        case .expenses: .expenses
        case .linkedCards: .linkedCards
        case .linkedPresets: .linkedPresets
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.AccountProjection {
    var semanticProjection: MarinaSemanticProjection {
        switch self {
        case .records: .records
        case .activity: .activity
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.IncomeSeriesProjection {
    var semanticProjection: MarinaSemanticProjection {
        switch self {
        case .records: .records
        case .occurrences: .occurrences
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.PresetProjection {
    var semanticProjection: MarinaSemanticProjection {
        switch self {
        case .records: .records
        case .linkedBudgets: .linkedBudgets
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.CardMeasure {
    var semanticMeasure: MarinaSemanticMeasure {
        switch self {
        case .budgetImpact: .budgetImpact
        case .name: .name
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.PlannedExpenseMeasure {
    var semanticMeasure: MarinaSemanticMeasure {
        switch self {
        case .amount: .amount
        case .plannedAmount: .plannedAmount
        case .actualAmount: .actualAmount
        case .effectiveAmount: .effectiveAmount
        case .budgetImpact: .budgetImpact
        case .projectedBudgetImpact: .projectedBudgetImpact
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.VariableExpenseMeasure {
    var semanticMeasure: MarinaSemanticMeasure {
        switch self {
        case .amount: .amount
        case .budgetImpact: .budgetImpact
        case .ledgerSignedAmount: .ledgerSignedAmount
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.ReconciliationMeasure {
    var semanticMeasure: MarinaSemanticMeasure {
        switch self {
        case .name: .name
        case .color: .color
        case .reconciliationBalance: .reconciliationBalance
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.SavingsMeasure {
    var semanticMeasure: MarinaSemanticMeasure {
        switch self {
        case .name: .name
        case .savingsTotal: .savingsTotal
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.IncomeAmountMeasure {
    var semanticMeasure: MarinaSemanticMeasure {
        switch self {
        case .amount: .amount
        case .incomeAmount: .incomeAmount
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.IncomeForecastMeasure {
    var semanticMeasure: MarinaSemanticMeasure {
        switch self {
        case .incomeAmount: .incomeAmount
        case .coverageRatio: .coverageRatio
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.CategoryMetadataMeasure {
    var semanticMeasure: MarinaSemanticMeasure {
        switch self {
        case .name: .name
        case .color: .color
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.CategoryMetricMeasure {
    var semanticMeasure: MarinaSemanticMeasure {
        switch self {
        case .budgetImpact: .budgetImpact
        case .concentration: .concentration
        case .name: .name
        case .color: .color
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.CategoryForecastMeasure {
    var semanticMeasure: MarinaSemanticMeasure {
        switch self {
        case .concentration: .concentration
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.CategoryAvailabilityStatus {
    var semanticFilter: MarinaCategoryAvailabilityFilter {
        switch self {
        case .over: .over
        case .near: .near
        case .underLimit: .underLimit
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.PresetMeasure {
    var semanticMeasure: MarinaSemanticMeasure {
        switch self {
        case .plannedAmount: .plannedAmount
        case .actualAmount: .actualAmount
        case .recurringBurden: .recurringBurden
        case .name: .name
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.BudgetMetricMeasure {
    var semanticMeasure: MarinaSemanticMeasure { semanticBudgetMeasure }

    private var semanticBudgetMeasure: MarinaSemanticMeasure {
        switch self {
        case .budgetImpact: .budgetImpact
        case .projectedBudgetImpact: .projectedBudgetImpact
        case .plannedIncomeTotal: .plannedIncomeTotal
        case .actualIncomeTotal: .actualIncomeTotal
        case .plannedExpenseProjectedTotal: .plannedExpenseProjectedTotal
        case .plannedExpenseActualTotal: .plannedExpenseActualTotal
        case .plannedExpenseEffectiveTotal: .plannedExpenseEffectiveTotal
        case .variableExpenseTotal: .variableExpenseTotal
        case .unifiedExpenseTotal: .unifiedExpenseTotal
        case .maximumSavings: .maximumSavings
        case .projectedSavings: .projectedSavings
        case .actualSavings: .actualSavings
        case .remainingRoom: .remainingRoom
        case .burnRate: .burnRate
        case .projectedSpend: .projectedSpend
        case .safeDailySpend: .safeDailySpend
        case .paceDifference: .paceDifference
        case .coverageRatio: .coverageRatio
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.BudgetComparisonMeasure {
    var semanticMeasure: MarinaSemanticMeasure {
        switch self {
        case .budgetImpact: .budgetImpact
        case .projectedBudgetImpact: .projectedBudgetImpact
        case .plannedIncomeTotal: .plannedIncomeTotal
        case .actualIncomeTotal: .actualIncomeTotal
        case .plannedExpenseProjectedTotal: .plannedExpenseProjectedTotal
        case .plannedExpenseActualTotal: .plannedExpenseActualTotal
        case .plannedExpenseEffectiveTotal: .plannedExpenseEffectiveTotal
        case .variableExpenseTotal: .variableExpenseTotal
        case .unifiedExpenseTotal: .unifiedExpenseTotal
        case .maximumSavings: .maximumSavings
        case .projectedSavings: .projectedSavings
        case .actualSavings: .actualSavings
        case .remainingRoom: .remainingRoom
        case .burnRate: .burnRate
        case .projectedSpend: .projectedSpend
        case .safeDailySpend: .safeDailySpend
        case .paceDifference: .paceDifference
        case .coverageRatio: .coverageRatio
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.BudgetForecastMeasure {
    var semanticMeasure: MarinaSemanticMeasure {
        switch self {
        case .projectedBudgetImpact: .projectedBudgetImpact
        case .projectedSpend: .projectedSpend
        case .projectedSavings: .projectedSavings
        case .maximumSavings: .maximumSavings
        case .remainingRoom: .remainingRoom
        case .burnRate: .burnRate
        case .safeDailySpend: .safeDailySpend
        case .paceDifference: .paceDifference
        case .coverageRatio: .coverageRatio
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.BudgetWhatIfMeasure {
    var semanticMeasure: MarinaSemanticMeasure {
        switch self {
        case .remainingRoom: .remainingRoom
        case .projectedSavings: .projectedSavings
        case .projectedSpend: .projectedSpend
        case .safeDailySpend: .safeDailySpend
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.Subject {
    var semanticEntity: MarinaSemanticEntity {
        switch self {
        case .workspaceMetadata: .workspace
        case .budget: .budget
        case .card: .card
        case .plannedExpense: .plannedExpense
        case .variableExpense: .variableExpense
        case .reconciliationAccount: .reconciliationAccount
        case .savingsAccount: .savingsAccount
        case .income: .income
        case .incomeSeries: .incomeSeries
        case .category: .category
        case .preset: .preset
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.AttemptedOperation {
    var semanticOperation: MarinaSemanticOperation {
        switch self {
        case .list: .list
        case .count: .count
        case .sum: .sum
        case .average: .average
        case .compare: .compare
        case .last: .last
        case .next: .next
        case .group: .group
        case .share: .share
        case .forecast: .forecast
        case .whatIf: .whatIf
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.AttemptedMeasure {
    var semanticMeasure: MarinaSemanticMeasure {
        switch self {
        case .amount: .amount
        case .plannedAmount: .plannedAmount
        case .actualAmount: .actualAmount
        case .effectiveAmount: .effectiveAmount
        case .budgetImpact: .budgetImpact
        case .projectedBudgetImpact: .projectedBudgetImpact
        case .ledgerSignedAmount: .ledgerSignedAmount
        case .plannedIncomeTotal: .plannedIncomeTotal
        case .actualIncomeTotal: .actualIncomeTotal
        case .plannedExpenseProjectedTotal: .plannedExpenseProjectedTotal
        case .plannedExpenseActualTotal: .plannedExpenseActualTotal
        case .plannedExpenseEffectiveTotal: .plannedExpenseEffectiveTotal
        case .variableExpenseTotal: .variableExpenseTotal
        case .unifiedExpenseTotal: .unifiedExpenseTotal
        case .savingsTotal: .savingsTotal
        case .maximumSavings: .maximumSavings
        case .projectedSavings: .projectedSavings
        case .actualSavings: .actualSavings
        case .incomeAmount: .incomeAmount
        case .reconciliationBalance: .reconciliationBalance
        case .categoryAvailability: .categoryAvailability
        case .remainingRoom: .remainingRoom
        case .burnRate: .burnRate
        case .projectedSpend: .projectedSpend
        case .safeDailySpend: .safeDailySpend
        case .paceDifference: .paceDifference
        case .coverageRatio: .coverageRatio
        case .recurringBurden: .recurringBurden
        case .concentration: .concentration
        case .color: .color
        case .name: .name
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.UnsupportedReason {
    var semanticReason: MarinaSemanticUnsupportedReason {
        switch self {
        case .readOnly: .readOnly
        case .unsupportedCombination: .unsupportedCombination
        case .incomeSavingsWhatIfUnsupported: .incomeSavingsWhatIfUnsupported
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
extension MarinaFoundationModelGeneratedOutcomeV3 {
    var generatedIntentDigest: MarinaFoundationModelGeneratedIntentDigest {
        switch self {
        case .query(let query):
            let draft = MarinaFoundationModelOutcomeCompilerV3().draft(from: query)
            return MarinaFoundationModelGeneratedIntentDigest(
                intent: generatedIntentKind(for: draft, query: query),
                entity: draft.entity,
                projection: draft.projection,
                operation: draft.operation,
                measure: draft.measure,
                scope: draft.selection.dataBoundary.generatedScopeDigest,
                target: draft.selection.target?.generatedTargetDigest ?? .absent,
                comparisonTarget: draft.comparisonTarget?.generatedTargetDigest ?? .absent,
                constraints: draft.selection.namedFilters.map {
                    MarinaFoundationModelGeneratedConstraintDigest(
                        dimension: $0.kind.semanticDimension,
                        evidence: $0.evidence.semanticTargetKindSource
                    )
                },
                groupingDimension: draft.groupingDimension?.semanticDimension,
                date: draft.selection.dateSelection.generatedDateDigest,
                sort: draft.sort?.semanticSort,
                resultLimit: draft.resultLimit,
                continuation: draft.continuation.semanticContinuation,
                expenseScope: draft.expenseScope?.semanticExpenseScope,
                incomeState: draft.incomeState?.semanticIncomeState,
                hasScenarioAmount: draft.whatIfAmount != nil,
                categoryFilter: draft.categoryAvailabilityFilter,
                answerShape: draft.answerShape
            )
        case .clarificationSelection(let selection):
            return MarinaFoundationModelGeneratedIntentDigest(
                intent: .clarificationSelection,
                clarificationSelectionIndex: selection.index
            )
        case .followUpDecision(let decision):
            let intent: MarinaFoundationModelGeneratedIntentKind = switch decision.decision {
            case .accept: .followUpAccept
            case .decline: .followUpDecline
            }
            return MarinaFoundationModelGeneratedIntentDigest(intent: intent)
        case .unsupported(let unsupported):
            return MarinaFoundationModelGeneratedIntentDigest(
                intent: .unsupported,
                entity: unsupported.subject.semanticEntity,
                operation: unsupported.attemptedOperation.semanticOperation,
                measure: unsupported.attemptedMeasure?.semanticMeasure,
                answerShape: .unsupported,
                unsupportedReason: unsupported.reason.semanticReason
            )
        }
    }

    private func generatedIntentKind(
        for draft: MarinaFoundationModelOutcomeCompilerV3.QueryDraft,
        query: Query
    ) -> MarinaFoundationModelGeneratedIntentKind {
        if case .workspaceMetadata = query {
            return .workspaceMetadata
        }
        if draft.measure == .categoryAvailability {
            return .categoryAvailability
        }
        switch draft.answerShape {
        case .comparison:
            return .comparison
        case .list where draft.operation == .group:
            return .groupedList
        case .list:
            return .recordList
        case .metric:
            return .metric
        case .clarification, .acknowledgement, .unsupported:
            return .query
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.DataBoundary {
    var generatedScopeDigest: MarinaFoundationModelGeneratedScopeDigest {
        switch self {
        case .activeWorkspace: .activeWorkspace
        case .explicitNamedBudget: .namedBudget
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.NamedTarget {
    var generatedTargetDigest: MarinaFoundationModelGeneratedTargetDigest {
        switch classification {
        case .unresolved:
            MarinaFoundationModelGeneratedTargetDigest(evidence: .unresolved, dimension: nil)
        case .explicit(let kind):
            MarinaFoundationModelGeneratedTargetDigest(
                evidence: .explicit,
                dimension: kind.semanticDimension
            )
        case .inferred(let kind):
            MarinaFoundationModelGeneratedTargetDigest(
                evidence: .inferred,
                dimension: kind.semanticDimension
            )
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGeneratedOutcomeV3.DateSelection {
    var generatedDateDigest: MarinaFoundationModelGeneratedDateDigest {
        switch self {
        case .defaultCurrentPeriod: .defaultCurrentPeriod
        case .explicit(let range): .explicit(range.semanticDateRange)
        case .conversationContext(let range): .conversationContext(range.semanticDateRange)
        }
    }
}
#endif
