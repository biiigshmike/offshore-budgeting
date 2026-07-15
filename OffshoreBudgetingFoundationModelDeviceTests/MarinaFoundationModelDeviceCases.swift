import Foundation

@testable import Offshore

struct MarinaFoundationModelDeviceExpectedSemantic: Codable, Sendable {
  let entity: MarinaSemanticEntity
  let projection: MarinaSemanticProjection
  let operation: MarinaSemanticOperation
  let measure: MarinaSemanticMeasure?
  let dimensions: [MarinaSemanticDimension]
  let dateRange: MarinaSemanticDateRangeToken
  let dateRangeSource: MarinaSemanticDateRangeSource
  let targetName: String?
  let targetKindSource: MarinaSemanticTargetKindSource
  let sort: MarinaSemanticSort?
  let resultLimit: Int?
  let expenseScope: MarinaSemanticExpenseScope?
  let incomeState: MarinaSemanticIncomeState?
  let categoryAvailabilityFilter: MarinaCategoryAvailabilityFilter?
  let answerShape: MarinaSemanticAnswerShape

  init(
    entity: MarinaSemanticEntity,
    projection: MarinaSemanticProjection = .records,
    operation: MarinaSemanticOperation,
    measure: MarinaSemanticMeasure?,
    dimensions: [MarinaSemanticDimension] = [],
    dateRange: MarinaSemanticDateRangeToken = .currentPeriod,
    dateRangeSource: MarinaSemanticDateRangeSource = .defaulted,
    targetName: String? = nil,
    targetKindSource: MarinaSemanticTargetKindSource = .unspecified,
    sort: MarinaSemanticSort? = nil,
    resultLimit: Int? = nil,
    expenseScope: MarinaSemanticExpenseScope? = nil,
    incomeState: MarinaSemanticIncomeState? = nil,
    categoryAvailabilityFilter: MarinaCategoryAvailabilityFilter? = nil,
    answerShape: MarinaSemanticAnswerShape
  ) {
    self.entity = entity
    self.projection = projection
    self.operation = operation
    self.measure = measure
    self.dimensions = dimensions
    self.dateRange = dateRange
    self.dateRangeSource = dateRangeSource
    self.targetName = targetName
    self.targetKindSource = targetKindSource
    self.sort = sort
    self.resultLimit = resultLimit
    self.expenseScope = expenseScope
    self.incomeState = incomeState
    self.categoryAvailabilityFilter = categoryAvailabilityFilter
    self.answerShape = answerShape
  }

  init(contract: MarinaStarterPromptCatalog.Contract) {
    let targetName: String?
    let targetKindSource: MarinaSemanticTargetKindSource
    switch contract.target {
    case .absent:
      targetName = nil
      targetKindSource = .unspecified
    case .named(let name, _, let source):
      targetName = name
      targetKindSource = source
    }

    var dimensions = contract.dimensions
    if targetName != nil, contract.entity == .card, dimensions.contains(.card) == false {
      dimensions.append(.card)
    }

    self.init(
      entity: contract.entity,
      projection: contract.projection,
      operation: contract.operation,
      measure: contract.measure,
      dimensions: dimensions,
      dateRange: contract.dateRange,
      dateRangeSource: contract.dateRangeSource,
      targetName: targetName,
      targetKindSource: targetKindSource,
      sort: contract.sort,
      resultLimit: contract.resultLimit,
      expenseScope: contract.expenseScope,
      incomeState: contract.incomeState,
      categoryAvailabilityFilter: contract.categoryAvailabilityFilter,
      answerShape: contract.answerShape
    )
  }

  var digest: String {
    [
      "entity=\(entity.rawValue)",
      "projection=\(projection.rawValue)",
      "operation=\(operation.rawValue)",
      "measure=\(measure?.rawValue ?? "none")",
      "dimensions=\(dimensions.map(\.rawValue).sorted().joined(separator: ","))",
      "date=\(dateRange.rawValue):\(dateRangeSource.rawValue)",
      "target=\(targetName == nil ? "absent" : "present"):" + targetKindSource.rawValue,
      "sort=\(sort?.rawValue ?? "none")",
      "limit=\(resultLimit.map(String.init) ?? "none")",
      "expenseScope=\(expenseScope?.rawValue ?? "none")",
      "incomeState=\(incomeState?.rawValue ?? "none")",
      "availability=\(categoryAvailabilityFilter?.rawValue ?? "none")",
      "shape=\(answerShape.rawValue)",
    ].joined(separator: " ")
  }

  /// The deterministic evaluation request for the known device contract.
  /// This exists only in the test target and is never available to model
  /// generation, retry instructions, or the production compiler.
  var evaluationRequest: MarinaSemanticRequest {
    MarinaSemanticRequest(
      entity: entity,
      operation: operation,
      measure: measure,
      projection: projection,
      dimensions: dimensions,
      dateRangeToken: dateRange,
      dateRangeSource: dateRangeSource,
      targetName: targetName,
      targetKindSource: targetKindSource,
      resultLimit: resultLimit,
      sort: sort,
      expenseScope: expenseScope,
      incomeState: incomeState,
      categoryAvailabilityFilter: categoryAvailabilityFilter,
      expectedAnswerShape: answerShape
    )
  }

  func mismatches(with request: MarinaSemanticRequest) -> [String] {
    var failures: [String] = []
    check("entity", entity.rawValue, request.entity.rawValue, into: &failures)
    check("projection", projection.rawValue, request.projection.rawValue, into: &failures)
    check("operation", operation.rawValue, request.operation.rawValue, into: &failures)
    check("measure", measure?.rawValue, request.measure?.rawValue, into: &failures)
    check(
      "dimensions",
      dimensions.map(\.rawValue).sorted(),
      request.dimensions.map(\.rawValue).sorted(),
      into: &failures
    )
    check("dateRange", dateRange.rawValue, request.dateRangeToken.rawValue, into: &failures)
    check(
      "dateRangeSource", dateRangeSource.rawValue, request.dateRangeSource.rawValue, into: &failures
    )
    check("targetPresence", targetName != nil, request.targetName != nil, into: &failures)
    check(
      "targetKindSource", targetKindSource.rawValue, request.targetKindSource.rawValue,
      into: &failures)
    check("sort", sort?.rawValue, request.sort?.rawValue, into: &failures)
    check("resultLimit", resultLimit, request.resultLimit, into: &failures)
    check("expenseScope", expenseScope?.rawValue, request.expenseScope?.rawValue, into: &failures)
    check("incomeState", incomeState?.rawValue, request.incomeState?.rawValue, into: &failures)
    check(
      "categoryAvailabilityFilter",
      categoryAvailabilityFilter?.rawValue,
      request.categoryAvailabilityFilter?.rawValue,
      into: &failures
    )
    check(
      "answerShape", answerShape.rawValue, request.expectedAnswerShape.rawValue, into: &failures)
    return failures
  }

  private func check<Value: Equatable>(
    _ field: String,
    _ expected: Value,
    _ actual: Value,
    into failures: inout [String]
  ) {
    guard expected != actual else { return }
    failures.append(
      "\(field) expected=\(String(describing: expected)) actual=\(String(describing: actual))")
  }
}

struct MarinaFoundationModelDevicePromptCase: Sendable {
  let id: String
  let prompt: String
  let localeIdentifier: String
  let expected: MarinaFoundationModelDeviceExpectedSemantic

  init(
    id: String,
    prompt: String,
    localeIdentifier: String,
    expected: MarinaFoundationModelDeviceExpectedSemantic
  ) {
    self.id = id
    self.prompt = prompt
    self.localeIdentifier = localeIdentifier
    self.expected = expected
  }
}

enum MarinaFoundationModelDeviceCaseCatalog {
  static let version = "marina.starter-prompt-catalog.device-contract.v1"
  static let evaluationCardName = "Evaluation Card"

  /// Prompts and contracts come from the same production catalog used by Marina's UI
  /// and alignment validator, preventing the on-device matrix from drifting.
  @MainActor
  static func blockingCases() -> [MarinaFoundationModelDevicePromptCase] {
    let starters = MarinaStarterPromptCatalog.baseEntries.map { entry in
      MarinaFoundationModelDevicePromptCase(
        id: "english-starter-\(entry.id.rawValue)",
        prompt: entry.prompt(localeIdentifier: "en_US"),
        localeIdentifier: "en_US",
        expected: MarinaFoundationModelDeviceExpectedSemantic(contract: entry.contract)
      )
    }
    let cardPrompt = MarinaStarterPromptCatalog.cardSummaryEntry
      .prompt(localeIdentifier: "en_US")
      .replacing("%@", with: evaluationCardName)
    guard
      let cardMatch = MarinaStarterPromptCatalog.match(
        prompt: cardPrompt,
        localeIdentifier: "en_US"
      )
    else {
      preconditionFailure(
        "The production card-summary starter must match its shared catalog contract.")
    }
    let cardStarter = MarinaFoundationModelDevicePromptCase(
      id: "english-starter-cardSummary",
      prompt: cardPrompt,
      localeIdentifier: "en_US",
      expected: MarinaFoundationModelDeviceExpectedSemantic(contract: cardMatch.contract)
    )

    return starters + [cardStarter] + regressionCases() + localizedSafeSpendCases()
  }

  /// The shortest real-model calibration loop exercises the exact two prompts
  /// that exposed V2's Workspace-subject and missing-measure failure mode.
  static func calibrationCases() -> [MarinaFoundationModelDevicePromptCase] {
    regressionCases()
  }

  private static func regressionCases() -> [MarinaFoundationModelDevicePromptCase] {
    [
      MarinaFoundationModelDevicePromptCase(
        id: "qa-over-limit-last-month",
        prompt: "Which categories were over the limit for last month?",
        localeIdentifier: "en_US",
        expected: .init(
          entity: .category,
          operation: .list,
          measure: .categoryAvailability,
          dateRange: .previousMonth,
          dateRangeSource: .explicit,
          categoryAvailabilityFilter: .over,
          answerShape: .list
        )
      ),
      MarinaFoundationModelDevicePromptCase(
        id: "qa-income-current-period",
        prompt: "What is my income for the current period?",
        localeIdentifier: "en_US",
        expected: .init(
          entity: .income,
          operation: .sum,
          measure: .incomeAmount,
          dateRangeSource: .explicit,
          incomeState: .actual,
          answerShape: .metric
        )
      ),
    ]
  }

  private static func localizedSafeSpendCases() -> [MarinaFoundationModelDevicePromptCase] {
    guard
      let safeSpend = MarinaStarterPromptCatalog.baseEntries.first(where: { $0.id == .safeSpend })
    else {
      preconditionFailure("The shared starter catalog must contain safe spend.")
    }
    return ["ar", "de", "es", "fr", "pt-BR", "zh-Hans"].map { localeIdentifier in
      MarinaFoundationModelDevicePromptCase(
        id: "localized-safe-spend-\(localeIdentifier)",
        prompt: safeSpend.prompt(localeIdentifier: localeIdentifier),
        localeIdentifier: localeIdentifier,
        expected: MarinaFoundationModelDeviceExpectedSemantic(contract: safeSpend.contract)
      )
    }
  }
}
