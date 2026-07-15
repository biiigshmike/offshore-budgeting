import Foundation
import XCTest

@testable import Offshore

final class MarinaFoundationModelDeviceReportPrivacyTests: XCTestCase {
  @MainActor
  func testSerializedReportContainsNoPromptOrFinancialFixtureValues() throws {
    let privateName = "Private Merchant Name"
    let privateUUID = "11111111-2222-3333-4444-555555555555"
    let privateAmount = "98765.43"
    let request = MarinaSemanticRequest(
      entity: .variableExpense,
      operation: .sum,
      measure: .budgetImpact,
      dimensions: [.merchantText],
      constraints: [
        MarinaSemanticConstraint(
          dimension: .card,
          value: privateUUID,
          kindSource: .explicit
        )
      ],
      targetName: privateName,
      textQuery: privateName,
      targetKindSource: .explicit,
      whatIfAmount: 98_765.43,
      expectedAnswerShape: .metric
    )
    let compiled = MarinaFoundationModelCompiledRequestDigest(request: request)
    let diagnostic = MarinaFoundationModelAttemptDiagnostic(
      attempt: 1,
      compilerVersion: MarinaSemanticCompilerInstructionsV3.version,
      instructionVersion: MarinaFoundationModelInstructionCatalogV3.instructionVersion,
      generationPhase: .actionPayload,
      generationPhaseCount: .four,
      generatedRoutePath: MarinaFoundationModelGeneratedRoutePathDigest(
        outcome: .financialQuery,
        financialDomain: .variableExpense,
        actionRoute: .variableExpenseSum,
        actionPayload: .variableExpenseSum
      ),
      generationPhaseDurations: [
        .init(phase: .outcomeRoute, milliseconds: 7),
        .init(phase: .financialDomain, milliseconds: 5),
        .init(phase: .actionRoute, milliseconds: 3),
        .init(phase: .actionPayload, milliseconds: 11),
      ],
      stage: .alignment,
      status: .accepted,
      rejection: nil,
      alignmentVerdict: .accepted,
      generatedIntent: nil,
      compiledRequest: compiled,
      alignment: nil
    )
    let result = MarinaFoundationModelDeviceCaseResult(
      caseID: "privacy-fixture",
      repetition: 1,
      localeIdentifier: "en_US",
      expectedSemanticDigest: compiled.rendered,
      actualSemanticDigest: compiled.rendered,
      compilerAttempts: [MarinaFoundationModelDeviceAttemptResult(diagnostic)],
      interpretedSource: MarinaSemanticSource.foundationModel.rawValue,
      alignmentAccepted: true,
      validatorAccepted: true,
      executionRoute: "universal",
      executionSucceeded: true,
      answer: MarinaFoundationModelDeviceAnswerObservation(
        expectedKind: "metric",
        actualKind: "metric",
        titleStatus: "nonError",
        primaryValuePresent: true,
        answerRowCount: 0,
        expectedSignature: "sha256:expected",
        actualSignature: "sha256:actual",
        signatureMatched: true
      ),
      evidence: MarinaFoundationModelDeviceEvidenceObservation(
        rowCount: 1,
        expectedSignature: "sha256:expectedEvidence",
        actualSignature: "sha256:actualEvidence",
        signatureMatched: true
      ),
      writeSideEffect: false,
      workspaceBoundaryViolation: false,
      durationMilliseconds: 1,
      failures: []
    )
    let report = MarinaFoundationModelDeviceGateReport(
      mode: .blocking,
      modelAvailability: "available",
      preflight: MarinaFoundationModelDevicePreflight(
        physicalDevice: true,
        supportedOperatingSystem: true,
        modelAvailability: "available",
        sourceMetadataAvailable: true,
        failures: []
      ),
      expectedInvocationCount: 1,
      results: [result]
    )

    let serialized = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
    let renderedReport = serialized + "\n" + report.textSummary
    for sensitiveValue in [privateName, privateUUID, privateAmount] {
      XCTAssertFalse(renderedReport.contains(sensitiveValue))
    }
    XCTAssertFalse(serialized.contains("\"prompt\":"))
    XCTAssertFalse(report.textSummary.contains("\nprompt="))
    XCTAssertTrue(serialized.contains("marina.foundation-model.device-report.v4"))
    XCTAssertTrue(serialized.contains("marina.semantic-generation.v3.1"))
    XCTAssertTrue(serialized.contains("outcomeRoute/financialDomain/actionRoute/actionPayload"))
    XCTAssertTrue(serialized.contains("\"maximumGenerationPhasesPerAttempt\":4"))
    XCTAssertTrue(serialized.contains("\"generatedRoutePathDigest\""))
    XCTAssertTrue(serialized.contains("financialDomain=variableExpense"))
    XCTAssertTrue(serialized.contains("actionRoute=variableExpenseSum"))
    XCTAssertTrue(serialized.contains("actionPayload=variableExpenseSum"))
    XCTAssertTrue(serialized.contains("\"generationDurationMilliseconds\":26"))
    XCTAssertTrue(serialized.contains("\"phase\":\"actionPayload\""))
  }

  func testExactSignatureIsValueSensitiveButExcludesRecordIdentifiers() {
    let sourceID = UUID()
    let baseline = HomeAnswer(
      queryID: UUID(),
      kind: .metric,
      title: "Summary",
      primaryValue: "$120.00",
      rows: [
        HomeAnswerRow(
          title: "Actual",
          value: "$120.00",
          sourceID: sourceID,
          amount: 120,
          role: .evidence
        )
      ]
    )
    let sameFinancialAnswerWithFreshIDs = HomeAnswer(
      queryID: UUID(),
      kind: .metric,
      title: "Summary",
      primaryValue: "$120.00",
      rows: [
        HomeAnswerRow(
          title: "Actual",
          value: "$120.00",
          sourceID: UUID(),
          amount: 120,
          role: .evidence
        )
      ]
    )
    let contaminatedAnswer = HomeAnswer(
      queryID: UUID(),
      kind: .metric,
      title: "Summary",
      primaryValue: "$99,999.00",
      rows: [
        HomeAnswerRow(
          title: "Actual",
          value: "$99,999.00",
          sourceID: sourceID,
          amount: 99_999,
          role: .evidence
        )
      ]
    )

    XCTAssertEqual(
      MarinaFoundationModelDeviceSignature.answer(baseline),
      MarinaFoundationModelDeviceSignature.answer(sameFinancialAnswerWithFreshIDs)
    )
    XCTAssertNotEqual(
      MarinaFoundationModelDeviceSignature.answer(baseline),
      MarinaFoundationModelDeviceSignature.answer(contaminatedAnswer)
    )
  }

  @MainActor
  func testCorpusReportRetainsEveryTurnsSafetyAndCompilerObservation() throws {
    let diagnostic = MarinaFoundationModelAttemptDiagnostic(
      attempt: 1,
      compilerVersion: MarinaSemanticCompilerInstructionsV3.version,
      instructionVersion: MarinaFoundationModelInstructionCatalogV3.instructionVersion,
      generationPhase: .terminalPayload,
      generationPhaseCount: .two,
      generatedRoutePath: MarinaFoundationModelGeneratedRoutePathDigest(
        outcome: .clarificationSelection
      ),
      generationPhaseDurations: [
        .init(phase: .outcomeRoute, milliseconds: 4),
        .init(phase: .terminalPayload, milliseconds: 6),
      ],
      stage: .alignment,
      status: .accepted,
      rejection: nil,
      alignmentVerdict: .accepted,
      generatedIntent: MarinaFoundationModelGeneratedIntentDigest(
        intent: .clarificationSelection,
        clarificationSelectionIndex: 1
      ),
      compiledRequest: nil,
      alignment: nil
    )
    let answer = MarinaFoundationModelDeviceAnswerObservation(
      expectedKind: "notSpecified",
      actualKind: "message",
      titleStatus: "nonError",
      primaryValuePresent: false,
      answerRowCount: 0,
      expectedSignature: nil,
      actualSignature: "sha256:answer",
      signatureMatched: nil
    )
    let evidence = MarinaFoundationModelDeviceEvidenceObservation(
      rowCount: 0,
      expectedSignature: nil,
      actualSignature: "sha256:evidence",
      signatureMatched: nil
    )
    let turns = [
      MarinaFoundationModelCorpusSoakTurnObservation(
        turnIndex: 1,
        actualOutcome: "outcome=semantic",
        compilerAttempts: [MarinaFoundationModelDeviceAttemptResult(diagnostic)],
        interpretedSource: "foundationModel",
        executionRoute: "universal",
        executionSucceeded: true,
        answer: answer,
        evidence: evidence,
        durationMilliseconds: 1,
        writeSideEffect: false,
        workspaceBoundaryViolation: false
      ),
      MarinaFoundationModelCorpusSoakTurnObservation(
        turnIndex: 2,
        actualOutcome: "outcome=clarificationSelection index=1",
        compilerAttempts: [MarinaFoundationModelDeviceAttemptResult(diagnostic)],
        interpretedSource: "foundationModel",
        executionRoute: "universal",
        executionSucceeded: true,
        answer: answer,
        evidence: evidence,
        durationMilliseconds: 1,
        writeSideEffect: false,
        workspaceBoundaryViolation: true
      ),
    ]
    let observation = MarinaFoundationModelCorpusSoakObservation(
      caseID: "two-turn-fixture",
      group: "conversation",
      localeIdentifier: "en_US",
      expectedOutcome: "outcome=clarificationSelection index=1",
      actualOutcome: "outcome=clarificationSelection index=1",
      exactMatch: true,
      turns: turns,
      durationMilliseconds: 2,
      writeSideEffect: false,
      workspaceBoundaryViolation: true
    )
    let report = MarinaFoundationModelCorpusSoakReport(
      modelAvailability: "available",
      preflight: MarinaFoundationModelDevicePreflight(
        physicalDevice: true,
        supportedOperatingSystem: true,
        modelAvailability: "available",
        sourceMetadataAvailable: true,
        failures: []
      ),
      observations: [observation]
    )

    XCTAssertEqual(report.evaluatedTurnCount, 2)
    XCTAssertEqual(report.workspaceBoundaryViolationCount, 1)
    let serialized = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
    XCTAssertTrue(serialized.contains("\"turnIndex\":1"))
    XCTAssertTrue(serialized.contains("\"turnIndex\":2"))
    XCTAssertFalse(serialized.contains("\"prompt\":"))
    XCTAssertTrue(serialized.contains("marina.foundation-model.corpus-soak-report.v4"))
    XCTAssertTrue(serialized.contains("outcome=clarificationSelection"))
    XCTAssertTrue(serialized.contains("\"generationPhaseCount\":2"))
    XCTAssertTrue(serialized.contains("\"generationDurationMilliseconds\":10"))
  }
}
