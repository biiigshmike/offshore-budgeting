import Foundation

nonisolated enum MarinaFoundationModelAttemptStage: String, Equatable, Sendable {
  case generation
  case compilation
  case alignment
}

nonisolated enum MarinaFoundationModelAttemptStatus: String, Equatable, Sendable {
  case accepted
  case rejected
  case terminal
}

/// The model-generation phase associated with an attempt diagnostic. These
/// cases describe only the generated schema boundary; they cannot carry prompt
/// text or any model-authored field values.
nonisolated enum MarinaFoundationModelGenerationPhase: String, Equatable, Sendable {
  case outcomeRoute
  case financialDomain
  case actionRoute
  case actionPayload
  case terminalPayload
}

/// The complete phase count for a generated candidate. Restricting this to the
/// supported V3.1 paths prevents an unbounded model value from entering traces.
nonisolated enum MarinaFoundationModelGenerationPhaseCount: Int, Equatable, Sendable {
  case two = 2
  case three = 3
  case four = 4
}

/// A monotonic elapsed time for one generated phase. Durations carry no prompt,
/// semantic payload, or financial values and are safe to include in QA reports.
nonisolated struct MarinaFoundationModelGenerationPhaseDuration: Equatable, Sendable {
  let phase: MarinaFoundationModelGenerationPhase
  let milliseconds: Int

  init(phase: MarinaFoundationModelGenerationPhase, milliseconds: Int) {
    self.phase = phase
    self.milliseconds = max(0, milliseconds)
  }

  var rendered: String {
    "\(phase.rawValue):\(milliseconds)ms"
  }
}

nonisolated enum MarinaFoundationModelGeneratedOutcomeRouteDigest: String, Equatable, Sendable {
  case financialQuery
  case workspaceMetadata
  case clarificationSelection
  case followUpDecision
  case unsupported
}

/// Financial subjects available after the model has selected financialQuery.
/// Workspace is intentionally not representable here.
nonisolated enum MarinaFoundationModelGeneratedFinancialDomainDigest: String, Equatable, Sendable {
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

/// Redacted names of the action-specific generated schemas. The diagnostic
/// path records the selected schema, never any generated payload fields.
nonisolated enum MarinaFoundationModelGeneratedActionPayloadDigest: String, Equatable, Sendable {
  case workspaceList, workspaceCount, workspaceName, workspaceColor
  case budgetList, budgetSum, budgetAverage, budgetCompare, budgetForecast, budgetWhatIf
  case cardList, cardCount, cardSum, cardCompare, cardGroup
  case plannedExpenseList, plannedExpenseCount, plannedExpenseSum, plannedExpenseAverage
  case plannedExpenseLast, plannedExpenseNext, plannedExpenseGroup
  case variableExpenseList, variableExpenseCount, variableExpenseSum, variableExpenseAverage
  case variableExpenseLast, variableExpenseGroup
  case reconciliationList, reconciliationCount, reconciliationSum, reconciliationGroup
  case savingsList, savingsCount, savingsSum, savingsLast, savingsGroup, savingsForecast
  case incomeList, incomeCount, incomeSum, incomeAverage, incomeCompare, incomeGroup
  case incomeProgress, incomeCoverage, incomeForecast
  case incomeSeriesList, incomeSeriesCount, incomeSeriesLast, incomeSeriesNext
  case categoryList, categoryCount, categorySum, categoryAverage, categoryCompare
  case categoryGroupedSpend, categoryShare, categoryForecast
  case categoryAvailabilitySummary, categoryAvailabilityList
  case presetList, presetSum, presetNext, presetGroup
}

/// A typed, value-free trace of the model-authored narrowing decisions.
nonisolated struct MarinaFoundationModelGeneratedRoutePathDigest: Equatable, Sendable {
  let outcome: MarinaFoundationModelGeneratedOutcomeRouteDigest
  let financialDomain: MarinaFoundationModelGeneratedFinancialDomainDigest?
  let actionRoute: MarinaFoundationModelGeneratedActionPayloadDigest?
  let actionPayload: MarinaFoundationModelGeneratedActionPayloadDigest?

  init(
    outcome: MarinaFoundationModelGeneratedOutcomeRouteDigest,
    financialDomain: MarinaFoundationModelGeneratedFinancialDomainDigest? = nil,
    actionRoute: MarinaFoundationModelGeneratedActionPayloadDigest? = nil,
    actionPayload: MarinaFoundationModelGeneratedActionPayloadDigest? = nil
  ) {
    self.outcome = outcome
    self.financialDomain = financialDomain
    self.actionRoute = actionRoute
    self.actionPayload = actionPayload
  }

  var rendered: String {
    [
      "outcome=\(outcome.rawValue)",
      "financialDomain=\(financialDomain?.rawValue ?? "none")",
      "actionRoute=\(actionRoute?.rawValue ?? "none")",
      "actionPayload=\(actionPayload?.rawValue ?? "none")",
    ].joined(separator: ";")
  }
}

/// Typed provenance for one completed or failed generated phase. Production
/// runtime results carry this separately from free-form diagnostic notes.
nonisolated struct MarinaFoundationModelGenerationDiagnosticMetadata: Equatable, Sendable {
  let phase: MarinaFoundationModelGenerationPhase
  let phaseCount: MarinaFoundationModelGenerationPhaseCount?
  let routePath: MarinaFoundationModelGeneratedRoutePathDigest?
  let phaseDurations: [MarinaFoundationModelGenerationPhaseDuration]

  init(
    phase: MarinaFoundationModelGenerationPhase,
    phaseCount: MarinaFoundationModelGenerationPhaseCount? = nil,
    routePath: MarinaFoundationModelGeneratedRoutePathDigest? = nil,
    phaseDurations: [MarinaFoundationModelGenerationPhaseDuration] = []
  ) {
    self.phase = phase
    self.phaseCount = phaseCount
    self.routePath = routePath
    self.phaseDurations = phaseDurations
  }
}

nonisolated enum MarinaFoundationModelAlignmentVerdict: String, Equatable, Sendable {
  case accepted
  case inconclusive
  case rejected
}

/// Stable diagnostic codes are deliberately separate from model-authored text.
/// Adding a compiler failure requires adding a typed case here before it can be
/// emitted into Marina QA Trace.
nonisolated enum MarinaFoundationModelAttemptRejectionCode: Equatable, Sendable {
  enum Generation: String, Equatable, Sendable {
    case decodingFailure
    case unsupportedGuide
    case cancelled
    case unexpected
  }

  enum Compiler: String, Equatable, Sendable {
    case emptyNamedBudget
    case emptyTarget
    case emptyComparisonTarget
    case emptyNamedFilter
    case invalidResultLimit
    case dateContextWithoutPriorRequest
    case continuationWithoutContext
    case continuationWithoutOffset
    case clarificationSelectionWithoutContext
    case clarificationSelectionOutOfBounds
    case followUpDecisionWithoutContext
    case followUpAcceptanceWithoutExecutableRequest
  }

  case generation(Generation)
  case compiler(Compiler)
  case alignment(MarinaSemanticPromptAlignmentRejectionCode)
  case runtime(MarinaSemanticUnsupportedReason)

  var rawValue: String {
    switch self {
    case .generation(let code):
      "generation.\(code.rawValue)"
    case .compiler(let code):
      "compiler.\(code.rawValue)"
    case .alignment(let code):
      code.rawValue
    case .runtime(let reason):
      "runtime.\(reason.rawValue)"
    }
  }

  var humanReadableReason: String {
    switch self {
    case .generation(.decodingFailure):
      "The on-device model could not decode a typed semantic outcome."
    case .generation(.unsupportedGuide):
      "The on-device model does not support part of the generated schema."
    case .generation(.cancelled):
      "The on-device semantic generation was cancelled."
    case .generation(.unexpected):
      "The on-device model encountered an unexpected generation failure."
    case .compiler(let code):
      code.humanReadableReason
    case .alignment(let code):
      code.humanReadableReason
    case .runtime(let reason):
      "The on-device runtime returned the stable terminal reason \(reason.rawValue)."
    }
  }
}

extension MarinaFoundationModelAttemptRejectionCode.Compiler {
  fileprivate nonisolated var humanReadableReason: String {
    switch self {
    case .emptyNamedBudget: "The generated named-budget target was empty."
    case .emptyTarget: "The generated primary target was empty."
    case .emptyComparisonTarget: "The generated comparison target was empty."
    case .emptyNamedFilter: "A generated named-filter value was empty."
    case .invalidResultLimit: "The generated result limit was outside the supported range."
    case .dateContextWithoutPriorRequest:
      "A conversation-context date was generated without trusted prior context."
    case .continuationWithoutContext: "A continuation was generated without trusted prior context."
    case .continuationWithoutOffset: "A continuation had no trusted next offset."
    case .clarificationSelectionWithoutContext:
      "A clarification selection was generated without trusted choices."
    case .clarificationSelectionOutOfBounds:
      "The clarification selection was outside the trusted choices."
    case .followUpDecisionWithoutContext:
      "A follow-up decision was generated without a trusted offered follow-up."
    case .followUpAcceptanceWithoutExecutableRequest:
      "The accepted follow-up had no trusted executable request."
    }
  }
}

extension MarinaSemanticPromptAlignmentRejectionCode {
  nonisolated var humanReadableReason: String {
    switch self {
    case .safetyMismatch: "The compiled safety outcome did not match the strong prompt anchor."
    case .entityMismatch: "The compiled result entity did not match the strong prompt anchor."
    case .projectionMismatch: "The compiled projection did not match the strong prompt anchor."
    case .operationMismatch: "The compiled operation did not match the strong prompt anchor."
    case .measureMismatch: "The compiled measure did not match the strong prompt anchor."
    case .dimensionMismatch: "The compiled dimensions did not match the strong prompt anchor."
    case .dateRangeMismatch: "The compiled date range did not match the strong prompt anchor."
    case .dateSourceMismatch: "The compiled date source did not match the strong prompt anchor."
    case .targetMismatch:
      "The compiled target presence or classification did not match the strong prompt anchor."
    case .targetSourceMismatch:
      "The compiled target evidence did not match the strong prompt anchor."
    case .sortMismatch: "The compiled sort did not match the strong prompt anchor."
    case .countMismatch: "The compiled result count did not match the strong prompt anchor."
    case .expenseScopeMismatch: "The compiled expense scope did not match the strong prompt anchor."
    case .incomeStateMismatch: "The compiled income state did not match the strong prompt anchor."
    case .categoryFilterMismatch:
      "The compiled category filter did not match the strong prompt anchor."
    case .continuationMismatch: "The compiled continuation did not match the strong prompt anchor."
    case .scenarioMismatch: "The compiled scenario presence did not match the strong prompt anchor."
    case .answerShapeMismatch: "The compiled answer shape did not match the strong prompt anchor."
    }
  }
}

nonisolated enum MarinaFoundationModelGeneratedIntentKind: String, Equatable, Sendable {
  case query
  case workspaceMetadata
  case recordList
  case metric
  case groupedList
  case categoryAvailability
  case comparison
  case clarificationSelection
  case followUpDecision
  case followUpAccept
  case followUpDecline
  case unsupported
}

nonisolated enum MarinaFoundationModelGeneratedScopeDigest: String, Equatable, Sendable {
  case activeWorkspace
  case namedBudget
}

nonisolated enum MarinaFoundationModelGeneratedTargetEvidenceDigest: String, Equatable, Sendable {
  case absent
  case unresolved
  case explicit
  case inferred
}

nonisolated enum MarinaFoundationModelGeneratedDateDigest: Equatable, Sendable {
  case defaultCurrentPeriod
  case explicit(MarinaSemanticDateRangeToken)
  case conversationContext(MarinaSemanticDateRangeToken)

  var rendered: String {
    switch self {
    case .defaultCurrentPeriod: "defaultCurrentPeriod"
    case .explicit(let range): "explicit:\(range.rawValue)"
    case .conversationContext(let range): "conversationContext:\(range.rawValue)"
    }
  }
}

nonisolated struct MarinaFoundationModelGeneratedTargetDigest: Equatable, Sendable {
  let evidence: MarinaFoundationModelGeneratedTargetEvidenceDigest
  let dimension: MarinaSemanticDimension?

  static let absent = Self(evidence: .absent, dimension: nil)

  var rendered: String {
    "\(evidence.rawValue):\(dimension?.rawValue ?? "none")"
  }
}

nonisolated struct MarinaFoundationModelGeneratedConstraintDigest: Equatable, Sendable {
  let dimension: MarinaSemanticDimension
  let evidence: MarinaSemanticTargetKindSource

  var rendered: String {
    "\(dimension.rawValue):\(evidence.rawValue)"
  }
}

/// A redacted view of the model-authored intent. This type has no storage for
/// prompt text, target wording, constraint values, IDs, or financial amounts.
nonisolated struct MarinaFoundationModelGeneratedIntentDigest: Equatable, Sendable {
  let intent: MarinaFoundationModelGeneratedIntentKind
  let entity: MarinaSemanticEntity?
  let projection: MarinaSemanticProjection?
  let operation: MarinaSemanticOperation?
  let measure: MarinaSemanticMeasure?
  let scope: MarinaFoundationModelGeneratedScopeDigest?
  let target: MarinaFoundationModelGeneratedTargetDigest
  let comparisonTarget: MarinaFoundationModelGeneratedTargetDigest
  let constraints: [MarinaFoundationModelGeneratedConstraintDigest]
  let groupingDimension: MarinaSemanticDimension?
  let date: MarinaFoundationModelGeneratedDateDigest?
  let sort: MarinaSemanticSort?
  let resultLimit: Int?
  let continuation: MarinaSemanticContinuationIntent?
  let expenseScope: MarinaSemanticExpenseScope?
  let incomeState: MarinaSemanticIncomeState?
  let hasScenarioAmount: Bool
  let categoryFilter: MarinaCategoryAvailabilityFilter?
  let answerShape: MarinaSemanticAnswerShape?
  let unsupportedReason: MarinaSemanticUnsupportedReason?
  /// The bounded, zero-based selection only. Clarification wording and the
  /// selected request remain outside diagnostics.
  let clarificationSelectionIndex: Int?

  init(
    intent: MarinaFoundationModelGeneratedIntentKind,
    entity: MarinaSemanticEntity? = nil,
    projection: MarinaSemanticProjection? = nil,
    operation: MarinaSemanticOperation? = nil,
    measure: MarinaSemanticMeasure? = nil,
    scope: MarinaFoundationModelGeneratedScopeDigest? = nil,
    target: MarinaFoundationModelGeneratedTargetDigest = .absent,
    comparisonTarget: MarinaFoundationModelGeneratedTargetDigest = .absent,
    constraints: [MarinaFoundationModelGeneratedConstraintDigest] = [],
    groupingDimension: MarinaSemanticDimension? = nil,
    date: MarinaFoundationModelGeneratedDateDigest? = nil,
    sort: MarinaSemanticSort? = nil,
    resultLimit: Int? = nil,
    continuation: MarinaSemanticContinuationIntent? = nil,
    expenseScope: MarinaSemanticExpenseScope? = nil,
    incomeState: MarinaSemanticIncomeState? = nil,
    hasScenarioAmount: Bool = false,
    categoryFilter: MarinaCategoryAvailabilityFilter? = nil,
    answerShape: MarinaSemanticAnswerShape? = nil,
    unsupportedReason: MarinaSemanticUnsupportedReason? = nil,
    clarificationSelectionIndex: Int? = nil
  ) {
    self.intent = intent
    self.entity = entity
    self.projection = projection
    self.operation = operation
    self.measure = measure
    self.scope = scope
    self.target = target
    self.comparisonTarget = comparisonTarget
    self.constraints = constraints
    self.groupingDimension = groupingDimension
    self.date = date
    self.sort = sort
    self.resultLimit = resultLimit
    self.continuation = continuation
    self.expenseScope = expenseScope
    self.incomeState = incomeState
    self.hasScenarioAmount = hasScenarioAmount
    self.categoryFilter = categoryFilter
    self.answerShape = answerShape
    self.unsupportedReason = unsupportedReason
    self.clarificationSelectionIndex = clarificationSelectionIndex
  }

  var rendered: String {
    [
      "intent=\(intent.rawValue)",
      "entity=\(entity?.rawValue ?? "none")",
      "projection=\(projection?.rawValue ?? "none")",
      "operation=\(operation?.rawValue ?? "none")",
      "measure=\(measure?.rawValue ?? "none")",
      "scope=\(scope?.rawValue ?? "none")",
      "target=\(target.rendered)",
      "comparisonTarget=\(comparisonTarget.rendered)",
      "constraints=[\(constraints.map(\.rendered).joined(separator: ","))]",
      "groupingDimension=\(groupingDimension?.rawValue ?? "none")",
      "date=\(date?.rendered ?? "none")",
      "sort=\(sort?.rawValue ?? "none")",
      "limit=\(resultLimit.map(String.init) ?? "none")",
      "continuation=\(continuation?.rawValue ?? "none")",
      "expenseScope=\(expenseScope?.rawValue ?? "none")",
      "incomeState=\(incomeState?.rawValue ?? "none")",
      "scenario=\(hasScenarioAmount ? "present" : "absent")",
      "categoryFilter=\(categoryFilter?.rawValue ?? "none")",
      "shape=\(answerShape?.rawValue ?? "none")",
      "unsupported=\(unsupportedReason?.rawValue ?? "none")",
      "clarificationIndex=\(clarificationSelectionIndex.map(String.init) ?? "none")",
    ].joined(separator: ";")
  }

}

nonisolated struct MarinaFoundationModelCompiledTargetDigest: Equatable, Sendable {
  let isPresent: Bool
  let dimension: MarinaSemanticDimension?
  let evidence: MarinaSemanticTargetKindSource

  static let absent = Self(isPresent: false, dimension: nil, evidence: .unspecified)

  var rendered: String {
    guard isPresent else { return "absent" }
    return "present:\(dimension?.rawValue ?? "unspecified"):\(evidence.rawValue)"
  }
}

nonisolated struct MarinaFoundationModelCompiledConstraintDigest: Equatable, Sendable {
  let dimension: MarinaSemanticDimension
  let evidence: MarinaSemanticTargetKindSource

  var rendered: String {
    "\(dimension.rawValue):\(evidence.rawValue)"
  }
}

/// A value-free view of the compiled semantic request used for compiler and
/// alignment diagnostics.
nonisolated struct MarinaFoundationModelCompiledRequestDigest: Equatable, Sendable {
  let entity: MarinaSemanticEntity
  let projection: MarinaSemanticProjection
  let operation: MarinaSemanticOperation
  let measure: MarinaSemanticMeasure?
  let dimensions: [MarinaSemanticDimension]
  let constraints: [MarinaFoundationModelCompiledConstraintDigest]
  let dateRange: MarinaSemanticDateRangeToken
  let dateSource: MarinaSemanticDateRangeSource
  let target: MarinaFoundationModelCompiledTargetDigest
  let comparisonTarget: MarinaFoundationModelCompiledTargetDigest
  let hasTextQuery: Bool
  let sort: MarinaSemanticSort?
  let resultLimit: Int?
  let hasResultOffset: Bool
  let continuation: MarinaSemanticContinuationIntent
  let expenseScope: MarinaSemanticExpenseScope?
  let incomeState: MarinaSemanticIncomeState?
  let hasScenarioAmount: Bool
  let categoryFilter: MarinaCategoryAvailabilityFilter?
  let answerShape: MarinaSemanticAnswerShape
  let unsupportedReason: MarinaSemanticUnsupportedReason?

  init(request: MarinaSemanticRequest) {
    entity = request.entity
    projection = request.projection
    operation = request.operation
    measure = request.measure
    dimensions = request.dimensions
    constraints = request.constraints.map {
      MarinaFoundationModelCompiledConstraintDigest(
        dimension: $0.dimension,
        evidence: $0.kindSource
      )
    }
    dateRange = request.dateRangeToken
    dateSource = request.dateRangeSource
    target = Self.targetDigest(
      name: request.targetName,
      fallbackText: request.textQuery,
      dimension: nil,
      evidence: request.targetKindSource
    )
    comparisonTarget = Self.targetDigest(
      name: request.comparisonTargetName,
      fallbackText: nil,
      dimension: nil,
      evidence: request.comparisonTargetKindSource
    )
    hasTextQuery = request.textQuery?.isEmpty == false
    sort = request.sort
    resultLimit = request.resultLimit
    hasResultOffset = request.resultOffset != nil
    continuation = request.continuationIntent
    expenseScope = request.expenseScope
    incomeState = request.incomeState
    hasScenarioAmount = request.whatIfAmount != nil
    categoryFilter = request.categoryAvailabilityFilter
    answerShape = request.expectedAnswerShape
    unsupportedReason = request.unsupportedReason
  }

  init(contract: MarinaStarterPromptCatalog.Contract) {
    entity = contract.entity
    projection = contract.projection
    operation = contract.operation
    measure = contract.measure
    dimensions = contract.dimensions
    constraints = []
    dateRange = contract.dateRange
    dateSource = contract.dateRangeSource
    switch contract.target {
    case .absent:
      target = .absent
    case .named(_, let kind, let source):
      target = MarinaFoundationModelCompiledTargetDigest(
        isPresent: true,
        dimension: kind,
        evidence: source
      )
    }
    comparisonTarget = .absent
    hasTextQuery = false
    sort = contract.sort
    resultLimit = contract.resultLimit
    hasResultOffset = false
    continuation = .none
    expenseScope = contract.expenseScope
    incomeState = contract.incomeState
    hasScenarioAmount = false
    categoryFilter = contract.categoryAvailabilityFilter
    answerShape = contract.answerShape
    unsupportedReason = nil
  }

  var rendered: String {
    [
      "entity=\(entity.rawValue)",
      "projection=\(projection.rawValue)",
      "operation=\(operation.rawValue)",
      "measure=\(measure?.rawValue ?? "none")",
      "dimensions=\(dimensions.map(\.rawValue).joined(separator: ","))",
      "constraints=[\(constraints.map(\.rendered).joined(separator: ","))]",
      "date=\(dateRange.rawValue):\(dateSource.rawValue)",
      "target=\(target.rendered)",
      "comparisonTarget=\(comparisonTarget.rendered)",
      "textQuery=\(hasTextQuery ? "present" : "absent")",
      "sort=\(sort?.rawValue ?? "none")",
      "limit=\(resultLimit.map(String.init) ?? "none")",
      "offset=\(hasResultOffset ? "present" : "absent")",
      "continuation=\(continuation.rawValue)",
      "expenseScope=\(expenseScope?.rawValue ?? "none")",
      "incomeState=\(incomeState?.rawValue ?? "none")",
      "scenario=\(hasScenarioAmount ? "present" : "absent")",
      "categoryFilter=\(categoryFilter?.rawValue ?? "none")",
      "shape=\(answerShape.rawValue)",
      "unsupported=\(unsupportedReason?.rawValue ?? "none")",
    ].joined(separator: ";")
  }

  func contains(_ value: String) -> Bool {
    rendered.contains(value)
  }

  private static func targetDigest(
    name: String?,
    fallbackText: String?,
    dimension: MarinaSemanticDimension?,
    evidence: MarinaSemanticTargetKindSource
  ) -> MarinaFoundationModelCompiledTargetDigest {
    let isPresent = name?.isEmpty == false || fallbackText?.isEmpty == false
    return MarinaFoundationModelCompiledTargetDigest(
      isPresent: isPresent,
      dimension: isPresent ? dimension : nil,
      evidence: isPresent ? evidence : .unspecified
    )
  }
}

nonisolated struct MarinaFoundationModelAlignmentDigest: Equatable, Sendable {
  let expected: MarinaFoundationModelCompiledRequestDigest
  let actual: MarinaFoundationModelCompiledRequestDigest

  var rendered: String {
    "expected={\(expected.rendered)} actual={\(actual.rendered)}"
  }
}

/// One typed, redacted semantic compiler attempt. Human-readable reasons are
/// derived exclusively from stable codes or verdicts; callers cannot inject
/// model-authored or user-authored strings.
nonisolated struct MarinaFoundationModelAttemptDiagnostic: Equatable, Sendable {
  let attempt: Int
  let compilerVersion: String
  let instructionVersion: String
  let generationPhase: MarinaFoundationModelGenerationPhase?
  let generationPhaseCount: MarinaFoundationModelGenerationPhaseCount?
  let generatedRoutePath: MarinaFoundationModelGeneratedRoutePathDigest?
  let generationPhaseDurations: [MarinaFoundationModelGenerationPhaseDuration]
  let stage: MarinaFoundationModelAttemptStage
  let status: MarinaFoundationModelAttemptStatus
  let rejection: MarinaFoundationModelAttemptRejectionCode?
  let alignmentVerdict: MarinaFoundationModelAlignmentVerdict?
  let generatedIntent: MarinaFoundationModelGeneratedIntentDigest?
  let compiledRequest: MarinaFoundationModelCompiledRequestDigest?
  let alignment: MarinaFoundationModelAlignmentDigest?

  init(
    attempt: Int,
    compilerVersion: String,
    instructionVersion: String = MarinaFoundationModelInstructionCatalogV3.instructionVersion,
    generationPhase: MarinaFoundationModelGenerationPhase? = nil,
    generationPhaseCount: MarinaFoundationModelGenerationPhaseCount? = nil,
    generatedRoutePath: MarinaFoundationModelGeneratedRoutePathDigest? = nil,
    generationPhaseDurations: [MarinaFoundationModelGenerationPhaseDuration] = [],
    stage: MarinaFoundationModelAttemptStage,
    status: MarinaFoundationModelAttemptStatus,
    rejection: MarinaFoundationModelAttemptRejectionCode?,
    alignmentVerdict: MarinaFoundationModelAlignmentVerdict?,
    generatedIntent: MarinaFoundationModelGeneratedIntentDigest?,
    compiledRequest: MarinaFoundationModelCompiledRequestDigest?,
    alignment: MarinaFoundationModelAlignmentDigest?
  ) {
    self.attempt = attempt
    self.compilerVersion = compilerVersion
    self.instructionVersion = instructionVersion
    self.generationPhase = generationPhase
    self.generationPhaseCount = generationPhaseCount
    self.generatedRoutePath = generatedRoutePath
    self.generationPhaseDurations = generationPhaseDurations
    self.stage = stage
    self.status = status
    self.rejection = rejection
    self.alignmentVerdict = alignmentVerdict
    self.generatedIntent = generatedIntent
    self.compiledRequest = compiledRequest
    self.alignment = alignment
  }

  var rejectionCode: String? { rejection?.rawValue }

  var reason: String {
    if let rejection {
      return rejection.humanReadableReason
    }
    switch alignmentVerdict {
    case .accepted:
      return "The compiled outcome matched a strong deterministic prompt anchor."
    case .inconclusive:
      return "No strong deterministic prompt anchor contradicted the compiled outcome."
    case .rejected:
      return "The compiled outcome was rejected by deterministic prompt alignment."
    case nil:
      return "The semantic compiler attempt completed without a rejection."
    }
  }

  var diagnosticNote: String {
    var components = [
      "FoundationModels attempt=\(attempt)",
      "compilerVersion=\(compilerVersion)",
      "instructionVersion=\(instructionVersion)",
      "stage=\(stage.rawValue)",
      "status=\(status.rawValue)",
    ]
    if let generationPhase {
      components.append("generationPhase=\(generationPhase.rawValue)")
    }
    if let generationPhaseCount {
      components.append("generationPhaseCount=\(generationPhaseCount.rawValue)")
    }
    if let generatedRoutePath {
      components.append("generatedRoutePath={\(generatedRoutePath.rendered)}")
    }
    if generationPhaseDurations.isEmpty == false {
      components.append(
        "generationPhaseDurations=[\(generationPhaseDurations.map(\.rendered).joined(separator: ","))]"
      )
      components.append(
        "generationDurationMilliseconds=\(generationPhaseDurations.reduce(0) { $0 + $1.milliseconds })"
      )
    }
    if let rejectionCode {
      components.append("rejectionCode=\(rejectionCode)")
    }
    if let alignmentVerdict {
      components.append("alignmentVerdict=\(alignmentVerdict.rawValue)")
    }
    components.append("reason=\(reason)")
    if let generatedIntent {
      components.append("generatedIntent={\(bounded(generatedIntent.rendered))}")
    }
    if let compiledRequest {
      components.append("compiledRequest={\(bounded(compiledRequest.rendered))}")
    }
    if let alignment {
      components.append("alignment={\(bounded(alignment.rendered))}")
    }
    return components.joined(separator: " ")
  }

  private func bounded(_ value: String) -> String {
    String(value.prefix(512))
  }
}
