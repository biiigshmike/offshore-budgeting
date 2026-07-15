import Foundation
import FoundationModels
import SwiftData
import UIKit
import XCTest

@testable import Offshore

final class MarinaFoundationModelDeviceGateTests: XCTestCase {
  private typealias Corpus = MarinaFoundationModelReleaseCorpusV1

  @MainActor
  func testCalibrationObservedFailuresOnSupportedPhysicalDevice() async throws {
    let cases = MarinaFoundationModelDeviceCaseCatalog.calibrationCases()
    XCTAssertEqual(cases.count, 2, "Calibration must contain the two observed QA failures.")
    try await runGate(
      mode: .calibration,
      cases: cases,
      repetitions: 10,
      attachmentName: "MarinaFoundationModelDeviceCalibration"
    )
  }

  @MainActor
  func testBlockingStarterAndQAMatrixOnSupportedPhysicalDevice() async throws {
    let cases = MarinaFoundationModelDeviceCaseCatalog.blockingCases()
    XCTAssertEqual(
      cases.count, 16,
      "The blocking matrix must contain 8 starters, 2 QA regressions, and 6 localized prompts.")
    try await runGate(
      mode: .blocking,
      cases: cases,
      repetitions: 3,
      attachmentName: "MarinaFoundationModelDeviceBlocking"
    )
  }

  @MainActor
  private func runGate(
    mode: MarinaFoundationModelDeviceTestMode,
    cases: [MarinaFoundationModelDevicePromptCase],
    repetitions: Int,
    attachmentName: String
  ) async throws {
    let expectedInvocationCount = cases.count * repetitions
    let evaluation = inspectPreflight()
    guard evaluation.observation.passed, let model = evaluation.model else {
      let report = MarinaFoundationModelDeviceGateReport(
        mode: mode,
        modelAvailability: evaluation.observation.modelAvailability,
        preflight: evaluation.observation,
        expectedInvocationCount: expectedInvocationCount,
        results: []
      )
      try MarinaFoundationModelDeviceReportAttachment.add(
        report: report,
        to: self,
        baseName: attachmentName
      )
      XCTFail(
        "Device-gate preflight failed: \(evaluation.observation.failures.joined(separator: ", "))")
      return
    }

    let fixture: MarinaFoundationModelDeviceFixture
    let expectedFixture: MarinaFoundationModelDeviceFixture
    let baselineFingerprint: String
    do {
      fixture = try MarinaFoundationModelDeviceFixture.make()
      expectedFixture = try MarinaFoundationModelDeviceFixture.make(includeSentinelWorkspace: false)
      baselineFingerprint = try fixture.dataStateFingerprint()
    } catch {
      let preflight = evaluation.observation.addingFailure("fixtureCreationFailed")
      let report = MarinaFoundationModelDeviceGateReport(
        mode: mode,
        modelAvailability: preflight.modelAvailability,
        preflight: preflight,
        expectedInvocationCount: expectedInvocationCount,
        results: []
      )
      try MarinaFoundationModelDeviceReportAttachment.add(
        report: report,
        to: self,
        baseName: attachmentName
      )
      XCTFail("Device-gate fixture creation failed.")
      return
    }

    var results: [MarinaFoundationModelDeviceCaseResult] = []
    for repetition in 1...repetitions {
      for testCase in cases {
        results.append(
          await evaluate(
            testCase,
            repetition: repetition,
            fixture: fixture,
            expectedFixture: expectedFixture,
            model: model,
            baselineFingerprint: baselineFingerprint
          ))
      }
    }

    let report = MarinaFoundationModelDeviceGateReport(
      mode: mode,
      modelAvailability: evaluation.observation.modelAvailability,
      preflight: evaluation.observation,
      expectedInvocationCount: expectedInvocationCount,
      results: results
    )
    try MarinaFoundationModelDeviceReportAttachment.add(
      report: report,
      to: self,
      baseName: attachmentName
    )
    print("Marina \(mode.rawValue): \(report.passedCount)/\(report.expectedInvocationCount) passed")

    for result in results where result.passed == false {
      XCTFail(
        "\(result.caseID)#\(result.repetition) [\(result.localeIdentifier)]: "
          + result.failures.joined(separator: " | ")
      )
    }
    XCTAssertEqual(results.count, expectedInvocationCount)
    XCTAssertEqual(report.passedCount, expectedInvocationCount)
  }

  @MainActor
  func testFullReleaseCorpusSoakOnSupportedPhysicalDevice() async throws {
    let evaluation = inspectPreflight()
    guard evaluation.observation.passed, let model = evaluation.model else {
      let report = MarinaFoundationModelCorpusSoakReport(
        modelAvailability: evaluation.observation.modelAvailability,
        preflight: evaluation.observation,
        observations: []
      )
      try MarinaFoundationModelCorpusSoakAttachment.add(report: report, to: self)
      XCTFail(
        "Corpus-soak preflight failed: \(evaluation.observation.failures.joined(separator: ", "))")
      return
    }

    let fixture: MarinaFoundationModelDeviceFixture
    let baselineFingerprint: String
    do {
      fixture = try MarinaFoundationModelDeviceFixture.make()
      baselineFingerprint = try fixture.dataStateFingerprint()
    } catch {
      let preflight = evaluation.observation.addingFailure("fixtureCreationFailed")
      let report = MarinaFoundationModelCorpusSoakReport(
        modelAvailability: preflight.modelAvailability,
        preflight: preflight,
        observations: []
      )
      try MarinaFoundationModelCorpusSoakAttachment.add(report: report, to: self)
      XCTFail("Corpus-soak fixture creation failed.")
      return
    }

    var observations: [MarinaFoundationModelCorpusSoakObservation] = []

    for testCase in Corpus.allCases {
      observations.append(
        try await evaluateCorpusCase(
          testCase,
          fixture: fixture,
          model: model,
          baselineFingerprint: baselineFingerprint
        ))
    }

    let report = MarinaFoundationModelCorpusSoakReport(
      modelAvailability: evaluation.observation.modelAvailability,
      preflight: evaluation.observation,
      observations: observations
    )
    try MarinaFoundationModelCorpusSoakAttachment.add(report: report, to: self)
    print(
      "Marina corpus soak: \(observations.count(where: \.exactMatch))/\(observations.count) exact"
    )

    XCTAssertEqual(observations.count, Corpus.inventory.totalCount)
    for observation in observations
    where observation.writeSideEffect || observation.workspaceBoundaryViolation {
      XCTFail(
        "\(observation.caseID) violated a blocking safety invariant: "
          + "writeSideEffect=\(observation.writeSideEffect) "
          + "workspaceBoundaryViolation=\(observation.workspaceBoundaryViolation)"
      )
    }
  }

  @MainActor
  private func evaluate(
    _ testCase: MarinaFoundationModelDevicePromptCase,
    repetition: Int,
    fixture: MarinaFoundationModelDeviceFixture,
    expectedFixture: MarinaFoundationModelDeviceFixture,
    model: SystemLanguageModel,
    baselineFingerprint: String
  ) async -> MarinaFoundationModelDeviceCaseResult {
    let expectedBrain = MarinaBrain(
      interpreter: MarinaFoundationModelDeviceExpectedInterpreter(
        request: testCase.expected.evaluationRequest
      )
    )
    let expectedSeed = await expectedBrain.answerSeed(
      prompt: testCase.prompt,
      workspace: expectedFixture.workspace,
      modelContext: expectedFixture.modelContext,
      ambientDateRange: expectedFixture.currentRange,
      homeContext: MarinaPanelHomeContext(dateRange: expectedFixture.currentRange),
      defaultBudgetingPeriod: .monthly,
      conversationContext: .empty,
      now: expectedFixture.now
    )
    let start = Date.now
    let locale = Locale(identifier: testCase.localeIdentifier)
    let interpreter = MarinaFoundationModelsInterpreter(
      runtime: MarinaFoundationModelRuntime(model: model),
      localeConfiguration: MarinaFoundationModelLocaleConfiguration(locale: locale)
    )
    let brain = MarinaBrain(interpreter: interpreter)
    let seed = await brain.answerSeed(
      prompt: testCase.prompt,
      workspace: fixture.workspace,
      modelContext: fixture.modelContext,
      ambientDateRange: fixture.currentRange,
      homeContext: MarinaPanelHomeContext(dateRange: fixture.currentRange),
      defaultBudgetingPeriod: .monthly,
      conversationContext: .empty,
      now: fixture.now
    )
    let duration = Int(Date.now.timeIntervalSince(start) * 1_000)
    let trace = seed.debugTrace
    let expectedTrace = expectedSeed.debugTrace
    let request = trace?.interpretedRequest
    var failures =
      request.map(testCase.expected.mismatches(with:)) ?? [
        "Marina did not return a structured QA trace."
      ]

    if expectedTrace?.validatorAccepted != true
      || expectedTrace?.executionRoute != .universal
      || expectedTrace?.executionSucceeded != true
    {
      failures.append("The deterministic expected request did not execute successfully.")
    }

    let attempts = trace?.compilerAttempts ?? []
    let firstAttemptAccepted =
      attempts.isEmpty == false
      && attempts.allSatisfy { $0.attempt == 1 }
      && attempts.last?.status == .accepted
    if firstAttemptAccepted == false {
      failures.append("The semantic request was not accepted on its first model attempt.")
    }
    if trace?.interpretedSource != .foundationModel {
      failures.append(
        "interpretedSource expected=foundationModel actual=\(trace?.interpretedSource.rawValue ?? "none")"
      )
    }
    let alignmentAccepted: Bool
    if let request {
      switch MarinaSemanticPromptAlignmentValidator().validate(
        userInput: testCase.prompt,
        request: request,
        localeIdentifier: testCase.localeIdentifier
      ) {
      case .accepted:
        alignmentAccepted = true
      case .inconclusive:
        alignmentAccepted = false
        failures.append("The blocking prompt alignment result was inconclusive.")
      case .rejected(let rejection):
        alignmentAccepted = false
        failures.append("Prompt alignment rejected the request: \(rejection.code.rawValue).")
      }
    } else {
      alignmentAccepted = false
    }
    if trace?.validatorAccepted != true {
      failures.append("The deterministic semantic validator rejected the request.")
    }
    if trace?.executionRoute != .universal || trace?.executionSucceeded != true {
      failures.append("The universal query path did not execute successfully.")
    }

    let expectedKind: HomeAnswerKind = testCase.expected.answerShape == .list ? .list : .metric
    if seed.answer.kind != expectedKind {
      failures.append(
        "answerKind expected=\(expectedKind.rawValue) actual=\(seed.answer.kind.rawValue)")
    }
    let titleStatus = Self.answerTitleStatus(seed.answer.title)
    if titleStatus != "nonError" {
      failures.append("Marina returned an answer title with status=\(titleStatus).")
    }
    let evidenceRowCount = trace?.evidenceRowSummaries.count ?? 0
    if evidenceRowCount == 0 {
      failures.append("The executed answer contained no seeded evidence rows.")
    }
    let expectedAnswerSignature = MarinaFoundationModelDeviceSignature.answer(expectedSeed.answer)
    let actualAnswerSignature = MarinaFoundationModelDeviceSignature.answer(seed.answer)
    let answerSignatureMatched = expectedAnswerSignature == actualAnswerSignature
    if answerSignatureMatched == false {
      failures.append("The answer did not match the exact deterministic seeded signature.")
    }
    let expectedEvidenceSignature = MarinaFoundationModelDeviceSignature.evidence(
      expectedTrace?.evidenceRowSummaries ?? []
    )
    let actualEvidenceSignature = MarinaFoundationModelDeviceSignature.evidence(
      trace?.evidenceRowSummaries ?? []
    )
    let evidenceSignatureMatched = expectedEvidenceSignature == actualEvidenceSignature
    if evidenceSignatureMatched == false {
      failures.append("The evidence did not match the exact deterministic seeded signature.")
    }

    let primaryValuePresent = seed.answer.primaryValue?.isEmpty == false
    if expectedKind == .metric, primaryValuePresent == false {
      failures.append("The metric answer had no primary value.")
    }
    if expectedKind == .list, seed.answer.rows.isEmpty {
      failures.append("The list answer contained no rows.")
    }

    let writeSideEffect =
      (try? fixture.dataStateFingerprint()) != baselineFingerprint
      || fixture.modelContext.hasChanges
    if writeSideEffect {
      failures.append("The read-only evaluation changed the seeded workspace.")
    }
    let workspaceBoundaryViolation = Self.containsWorkspaceSentinel(seed: seed)
    if workspaceBoundaryViolation {
      failures.append("The answer, evidence, or candidate trace exposed the sentinel Workspace.")
    }

    return MarinaFoundationModelDeviceCaseResult(
      caseID: testCase.id,
      repetition: repetition,
      localeIdentifier: testCase.localeIdentifier,
      expectedSemanticDigest: testCase.expected.digest,
      actualSemanticDigest: request.map(Self.semanticDigest),
      compilerAttempts: attempts.map(MarinaFoundationModelDeviceAttemptResult.init),
      interpretedSource: trace?.interpretedSource.rawValue,
      alignmentAccepted: alignmentAccepted,
      validatorAccepted: trace?.validatorAccepted == true,
      executionRoute: trace?.executionRoute.rawValue,
      executionSucceeded: trace?.executionSucceeded == true,
      answer: MarinaFoundationModelDeviceAnswerObservation(
        expectedKind: expectedKind.rawValue,
        actualKind: seed.answer.kind.rawValue,
        titleStatus: titleStatus,
        primaryValuePresent: primaryValuePresent,
        answerRowCount: seed.answer.rows.count,
        expectedSignature: expectedAnswerSignature,
        actualSignature: actualAnswerSignature,
        signatureMatched: answerSignatureMatched
      ),
      evidence: MarinaFoundationModelDeviceEvidenceObservation(
        rowCount: evidenceRowCount,
        expectedSignature: expectedEvidenceSignature,
        actualSignature: actualEvidenceSignature,
        signatureMatched: evidenceSignatureMatched
      ),
      writeSideEffect: writeSideEffect,
      workspaceBoundaryViolation: workspaceBoundaryViolation,
      durationMilliseconds: duration,
      failures: failures
    )
  }

  @MainActor
  private func evaluateCorpusCase(
    _ testCase: Corpus.Case,
    fixture: MarinaFoundationModelDeviceFixture,
    model: SystemLanguageModel,
    baselineFingerprint: String
  ) async throws -> MarinaFoundationModelCorpusSoakObservation {
    let start = Date.now
    let interpreter = MarinaFoundationModelsInterpreter(
      runtime: MarinaFoundationModelRuntime(model: model),
      localeConfiguration: MarinaFoundationModelLocaleConfiguration(
        locale: Locale(identifier: testCase.localeIdentifier)
      )
    )
    let brain = MarinaBrain(interpreter: interpreter)
    var answers: [HomeAnswer] = []
    var turnObservations: [MarinaFoundationModelCorpusSoakTurnObservation] = []
    var finalOutcome: Corpus.ExpectedOutcome?

    for (offset, turn) in testCase.turns.enumerated() {
      let turnStart = Date.now
      let seed = await brain.answerSeed(
        prompt: turn,
        workspace: fixture.workspace,
        modelContext: fixture.modelContext,
        ambientDateRange: fixture.currentRange,
        homeContext: MarinaPanelHomeContext(dateRange: fixture.currentRange),
        defaultBudgetingPeriod: .monthly,
        conversationContext: MarinaConversationContext(recentAnswers: answers),
        now: fixture.now
      )
      let trace = seed.debugTrace
      let turnOutcome = trace.flatMap(Self.corpusOutcome)
      let writeSideEffect =
        try fixture.dataStateFingerprint() != baselineFingerprint
        || fixture.modelContext.hasChanges
      let workspaceBoundaryViolation = Self.containsWorkspaceSentinel(seed: seed)
      turnObservations.append(
        MarinaFoundationModelCorpusSoakTurnObservation(
          turnIndex: offset + 1,
          actualOutcome: turnOutcome.map(Self.corpusReportDigest),
          compilerAttempts: trace?.compilerAttempts.map(
            MarinaFoundationModelDeviceAttemptResult.init) ?? [],
          interpretedSource: trace?.interpretedSource.rawValue,
          executionRoute: trace?.executionRoute.rawValue,
          executionSucceeded: trace?.executionSucceeded == true,
          answer: MarinaFoundationModelDeviceAnswerObservation(
            expectedKind: "notSpecified",
            actualKind: seed.answer.kind.rawValue,
            titleStatus: Self.answerTitleStatus(seed.answer.title),
            primaryValuePresent: seed.answer.primaryValue?.isEmpty == false,
            answerRowCount: seed.answer.rows.count,
            expectedSignature: nil,
            actualSignature: MarinaFoundationModelDeviceSignature.answer(seed.answer),
            signatureMatched: nil
          ),
          evidence: MarinaFoundationModelDeviceEvidenceObservation(
            rowCount: trace?.evidenceRowSummaries.count ?? 0,
            expectedSignature: nil,
            actualSignature: MarinaFoundationModelDeviceSignature.evidence(
              trace?.evidenceRowSummaries ?? []
            ),
            signatureMatched: nil
          ),
          durationMilliseconds: Int(Date.now.timeIntervalSince(turnStart) * 1_000),
          writeSideEffect: writeSideEffect,
          workspaceBoundaryViolation: workspaceBoundaryViolation
        ))
      answers.append(seed.answer)
      finalOutcome = turnOutcome
    }

    let exactMatch =
      finalOutcome.map {
        Corpus.outcomesMatch(expected: testCase.expectedOutcome, actual: $0)
      } ?? false
    let writeSideEffect = turnObservations.contains(where: \.writeSideEffect)
    let workspaceBoundaryViolation = turnObservations.contains(where: \.workspaceBoundaryViolation)

    return MarinaFoundationModelCorpusSoakObservation(
      caseID: testCase.id,
      group: testCase.group.rawValue,
      localeIdentifier: testCase.localeIdentifier,
      expectedOutcome: Self.corpusReportDigest(testCase.expectedOutcome),
      actualOutcome: finalOutcome.map(Self.corpusReportDigest),
      exactMatch: exactMatch,
      turns: turnObservations,
      durationMilliseconds: Int(Date.now.timeIntervalSince(start) * 1_000),
      writeSideEffect: writeSideEffect,
      workspaceBoundaryViolation: workspaceBoundaryViolation
    )
  }

  @MainActor
  private func inspectPreflight() -> MarinaFoundationModelDevicePreflightEvaluation {
    let sourceMetadataAvailable = MarinaFoundationModelDeviceRunMetadata.sourceMetadataIsAvailable()
    var failures = sourceMetadataAvailable ? [] : ["sourceMetadataUnavailable"]

    #if targetEnvironment(simulator) || targetEnvironment(macCatalyst)
      failures.append("physicalDeviceRequired")
      return MarinaFoundationModelDevicePreflightEvaluation(
        observation: MarinaFoundationModelDevicePreflight(
          physicalDevice: false,
          supportedOperatingSystem: false,
          modelAvailability: "unsupportedDestination",
          sourceMetadataAvailable: sourceMetadataAvailable,
          failures: failures
        ),
        model: nil
      )
    #else
      let physicalDevice =
        UIDevice.current.userInterfaceIdiom == .phone
        || UIDevice.current.userInterfaceIdiom == .pad
      if physicalDevice == false {
        failures.append("physicalDeviceRequired")
      }
      let supportedOperatingSystem = ProcessInfo.processInfo.isOperatingSystemAtLeast(
        OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
      )
      if supportedOperatingSystem == false {
        failures.append("iOS26OrNewerRequired")
      }

      let model = SystemLanguageModel(useCase: .general, guardrails: .default)
      let availability = Self.availabilityDescription(model.availability)
      guard case .available = model.availability else {
        failures.append("systemLanguageModelUnavailable.\(availability)")
        return MarinaFoundationModelDevicePreflightEvaluation(
          observation: MarinaFoundationModelDevicePreflight(
            physicalDevice: physicalDevice,
            supportedOperatingSystem: supportedOperatingSystem,
            modelAvailability: availability,
            sourceMetadataAvailable: sourceMetadataAvailable,
            failures: failures
          ),
          model: nil
        )
      }
      return MarinaFoundationModelDevicePreflightEvaluation(
        observation: MarinaFoundationModelDevicePreflight(
          physicalDevice: physicalDevice,
          supportedOperatingSystem: supportedOperatingSystem,
          modelAvailability: availability,
          sourceMetadataAvailable: sourceMetadataAvailable,
          failures: failures
        ),
        model: model
      )
    #endif
  }

  private static func semanticDigest(_ request: MarinaSemanticRequest) -> String {
    [
      "entity=\(request.entity.rawValue)",
      "projection=\(request.projection.rawValue)",
      "operation=\(request.operation.rawValue)",
      "measure=\(request.measure?.rawValue ?? "none")",
      "dimensions=\(request.dimensions.map(\.rawValue).sorted().joined(separator: ","))",
      "date=\(request.dateRangeToken.rawValue):\(request.dateRangeSource.rawValue)",
      "target=\(request.targetName == nil ? "absent" : "present"):\(request.targetKindSource.rawValue)",
      "sort=\(request.sort?.rawValue ?? "none")",
      "limit=\(request.resultLimit.map(String.init) ?? "none")",
      "expenseScope=\(request.expenseScope?.rawValue ?? "none")",
      "incomeState=\(request.incomeState?.rawValue ?? "none")",
      "availability=\(request.categoryAvailabilityFilter?.rawValue ?? "none")",
      "shape=\(request.expectedAnswerShape.rawValue)",
      "unsupported=\(request.unsupportedReason?.rawValue ?? "none")",
    ].joined(separator: " ")
  }

  private static func corpusOutcome(
    _ trace: MarinaAnswerDebugTrace
  ) -> Corpus.ExpectedOutcome? {
    if trace.interpretedRequest.expectedAnswerShape == .unsupported,
      let reason = trace.interpretedRequest.unsupportedReason
    {
      return .unsupported(reason)
    }

    if let generatedIntent = trace.compilerAttempts.last(where: { $0.generatedIntent != nil })?
      .generatedIntent
    {
      switch generatedIntent.intent {
      case .clarificationSelection:
        guard let index = generatedIntent.clarificationSelectionIndex else { return nil }
        return .clarificationSelection(index)
      case .followUpAccept:
        return .followUpDecision(.accept)
      case .followUpDecline:
        return .followUpDecision(.decline)
      case .query, .workspaceMetadata, .recordList, .metric, .groupedList,
        .categoryAvailability, .comparison, .unsupported:
        break
      }
    }

    let request = trace.interpretedRequest
    let scope: Corpus.ScopeExpectation
    if let budgetName = request.constraints.first(where: { $0.dimension == .budget })?.value {
      scope = .namedBudget(budgetName)
    } else {
      scope = .workspace
    }

    let target = request.targetName.map { name in
      Corpus.TargetExpectation(
        name,
        kind: targetDimension(for: request),
        kindSource: request.targetKindSource
      )
    }
    let comparisonTarget = request.comparisonTargetName.map { name in
      Corpus.TargetExpectation(
        name,
        kind: comparisonTargetDimension(for: request),
        kindSource: request.comparisonTargetKindSource
      )
    }
    let constraints = request.constraints.map {
      Corpus.ConstraintExpectation($0.dimension, $0.value, kindSource: $0.kindSource)
    }

    return .semantic(
      Corpus.SemanticTuple(
        request.entity,
        request.operation,
        request.measure,
        projection: request.projection,
        shape: request.expectedAnswerShape,
        scope: scope,
        target: target,
        comparisonTarget: comparisonTarget,
        constraints: constraints,
        dateRange: request.dateRangeToken,
        dateRangeSource: request.dateRangeSource,
        sort: request.sort,
        requestedCount: request.resultLimit,
        resultOffset: request.resultOffset,
        continuation: request.continuationIntent,
        expenseScope: request.expenseScope,
        incomeState: request.incomeState,
        whatIfAmount: request.whatIfAmount,
        categoryAvailabilityFilter: request.categoryAvailabilityFilter
      ))
  }

  private static func targetDimension(for request: MarinaSemanticRequest)
    -> MarinaSemanticDimension?
  {
    if request.dimensions.contains(.merchantText) { return .merchantText }
    switch request.entity {
    case .budget: return request.dimensions.contains(.budget) ? .budget : nil
    case .card: return request.dimensions.contains(.card) ? .card : nil
    case .category: return request.dimensions.contains(.category) ? .category : nil
    case .income: return request.dimensions.contains(.incomeSource) ? .incomeSource : nil
    case .incomeSeries: return request.dimensions.contains(.incomeSeries) ? .incomeSeries : nil
    case .preset: return request.dimensions.contains(.preset) ? .preset : nil
    case .savingsAccount:
      return request.dimensions.contains(.savingsAccount) ? .savingsAccount : nil
    case .reconciliationAccount:
      return request.dimensions.contains(.reconciliationAccount) ? .reconciliationAccount : nil
    case .workspace, .plannedExpense, .variableExpense:
      return nil
    }
  }

  private static func comparisonTargetDimension(
    for request: MarinaSemanticRequest
  ) -> MarinaSemanticDimension? {
    targetDimension(for: request)
  }

  private static func answerTitleStatus(_ title: String) -> String {
    let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if normalized.isEmpty { return "empty" }
    if normalized.contains("can't answer") || normalized.contains("cannot answer") {
      return "cannotAnswer"
    }
    if normalized.contains("hit a snag") { return "error" }
    return "nonError"
  }

  private static func containsWorkspaceSentinel(seed: MarinaAnswerSeed) -> Bool {
    let trace = seed.debugTrace
    return [
      seed.answer.title,
      seed.answer.subtitle,
      seed.answer.primaryValue,
      seed.answer.rows.map { "\($0.title) \($0.value)" }.joined(separator: " "),
      trace?.evidenceRowSummaries.joined(separator: " "),
      trace?.candidateSearches.map(\.debugDescription).joined(separator: " "),
    ]
    .compactMap { $0 }
    .contains { $0.localizedStandardContains("Workspace Leak Sentinel") }
  }

  private static func corpusReportDigest(_ outcome: Corpus.ExpectedOutcome) -> String {
    switch outcome {
    case .semantic(let tuple):
      let scope: String
      switch tuple.scope {
      case .workspace: scope = "activeWorkspace"
      case .namedBudget: scope = "explicitNamedBudget"
      }
      return [
        "outcome=semantic",
        "entity=\(tuple.entity.rawValue)",
        "projection=\(tuple.projection.rawValue)",
        "operation=\(tuple.operation.rawValue)",
        "measure=\(tuple.measure?.rawValue ?? "none")",
        "shape=\(tuple.answerShape.rawValue)",
        "scope=\(scope)",
        "target=\(tuple.target == nil ? "absent" : "present")",
        "comparisonTarget=\(tuple.comparisonTarget == nil ? "absent" : "present")",
        "filters=\(tuple.constraints.map { $0.dimension.rawValue }.sorted().joined(separator: ","))",
        "date=\(tuple.dateRange.rawValue):\(tuple.dateRangeSource.rawValue)",
        "sort=\(tuple.sort?.rawValue ?? "none")",
        "count=\(tuple.requestedCount.map(String.init) ?? "none")",
        "continuation=\(tuple.continuation.rawValue)",
        "expenseScope=\(tuple.expenseScope?.rawValue ?? "none")",
        "incomeState=\(tuple.incomeState?.rawValue ?? "none")",
        "whatIfAmount=\(tuple.whatIfAmount == nil ? "absent" : "present")",
        "availability=\(tuple.categoryAvailabilityFilter?.rawValue ?? "none")",
      ].joined(separator: " ")
    case .clarificationSelection(let index):
      "outcome=clarificationSelection index=\(index)"
    case .followUpDecision(let decision):
      "outcome=followUpDecision decision=\(decision.rawValue)"
    case .unsupported(let reason):
      "outcome=unsupported reason=\(reason.rawValue)"
    }
  }

  private static func availabilityDescription(_ availability: SystemLanguageModel.Availability)
    -> String
  {
    switch availability {
    case .available:
      "available"
    case .unavailable(.appleIntelligenceNotEnabled):
      "appleIntelligenceNotEnabled"
    case .unavailable(.deviceNotEligible):
      "deviceNotEligible"
    case .unavailable(.modelNotReady):
      "modelNotReady"
    @unknown default:
      "unavailable"
    }
  }
}

private struct MarinaFoundationModelDevicePreflightEvaluation {
  let observation: MarinaFoundationModelDevicePreflight
  let model: SystemLanguageModel?
}

/// Test-only semantic oracle for answer/evidence evaluation. It receives the
/// case contract after model generation and is never reachable from production
/// interpretation or retry code.
@MainActor
private struct MarinaFoundationModelDeviceExpectedInterpreter: MarinaModelInterpreting {
  let request: MarinaSemanticRequest

  func interpretedSemanticRequest(
    for prompt: String,
    context: MarinaBrainContext
  ) async throws -> MarinaInterpretedSemanticRequest {
    MarinaInterpretedSemanticRequest(
      request: request,
      confidence: .high,
      source: .foundationModel,
      diagnosticNotes: ["device.expectedContract"]
    )
  }
}
