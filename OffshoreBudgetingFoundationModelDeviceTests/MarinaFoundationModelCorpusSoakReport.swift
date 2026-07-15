import Foundation
import XCTest

@testable import Offshore

struct MarinaFoundationModelCorpusSoakTurnObservation: Encodable, Sendable {
  let turnIndex: Int
  let actualOutcome: String?
  let compilerAttempts: [MarinaFoundationModelDeviceAttemptResult]
  let interpretedSource: String?
  let executionRoute: String?
  let executionSucceeded: Bool
  let answer: MarinaFoundationModelDeviceAnswerObservation
  let evidence: MarinaFoundationModelDeviceEvidenceObservation
  let durationMilliseconds: Int
  let writeSideEffect: Bool
  let workspaceBoundaryViolation: Bool
}

struct MarinaFoundationModelCorpusSoakObservation: Encodable, Sendable {
  let caseID: String
  let group: String
  let localeIdentifier: String
  let expectedOutcome: String
  let actualOutcome: String?
  let exactMatch: Bool
  let turns: [MarinaFoundationModelCorpusSoakTurnObservation]
  let durationMilliseconds: Int
  let writeSideEffect: Bool
  let workspaceBoundaryViolation: Bool
}

struct MarinaFoundationModelCorpusSoakReport: Encodable, Sendable {
  let formatVersion = "marina.foundation-model.corpus-soak-report.v4"
  let metadata: MarinaFoundationModelDeviceRunMetadata
  let preflight: MarinaFoundationModelDevicePreflight
  let expectedInvocationCount: Int
  let observations: [MarinaFoundationModelCorpusSoakObservation]
  let evaluatedTurnCount: Int
  let exactMatchesByGroup: [String: Int]
  let evaluatedByGroup: [String: Int]
  let exactMatchesByLocale: [String: Int]
  let evaluatedByLocale: [String: Int]
  let writeSideEffectCount: Int
  let workspaceBoundaryViolationCount: Int

  init(
    modelAvailability: String,
    preflight: MarinaFoundationModelDevicePreflight,
    observations: [MarinaFoundationModelCorpusSoakObservation]
  ) {
    metadata = MarinaFoundationModelDeviceRunMetadata(
      mode: .corpusSoak,
      modelAvailability: modelAvailability
    )
    self.preflight = preflight
    expectedInvocationCount = MarinaFoundationModelReleaseCorpusV1.inventory.totalCount
    self.observations = observations
    evaluatedTurnCount = observations.reduce(into: 0) { count, observation in
      count += observation.turns.count
    }
    exactMatchesByGroup = Dictionary(grouping: observations, by: \.group).mapValues {
      $0.count(where: \.exactMatch)
    }
    evaluatedByGroup = Dictionary(grouping: observations, by: \.group).mapValues(\.count)
    exactMatchesByLocale = Dictionary(grouping: observations, by: \.localeIdentifier).mapValues {
      $0.count(where: \.exactMatch)
    }
    evaluatedByLocale = Dictionary(grouping: observations, by: \.localeIdentifier).mapValues(
      \.count)
    writeSideEffectCount = observations.count(where: \.writeSideEffect)
    workspaceBoundaryViolationCount = observations.count(where: \.workspaceBoundaryViolation)
  }

  var textSummary: String {
    var lines = [
      "Marina Foundation Model release-corpus soak",
      "format=\(formatVersion)",
      "corpus=\(metadata.corpusVersion)",
      "catalog=\(metadata.starterCatalogVersion)",
      "device=\(metadata.deviceName) (\(metadata.deviceModel))",
      "os=\(metadata.operatingSystem)",
      "app=\(metadata.appVersion) (\(metadata.appBuild))",
      "modelAvailability=\(metadata.modelAvailability)",
      "sourceRevision=\(metadata.sourceRevision)",
      "sourceDirtyState=\(metadata.sourceDirtyState)",
      "generation=\(metadata.generationSampling) temperature=\(metadata.generationTemperature) compiler=\(metadata.compilerVersion) instructions=\(metadata.instructionVersion) architecture=\(metadata.generationArchitecture) maximumPhasesPerAttempt=\(metadata.maximumGenerationPhasesPerAttempt) freshSessionPerCase=\(metadata.freshSessionPerCase) freshSessionPerPhase=\(metadata.freshSessionPerPhase)",
      "preflight=\(preflight.passed ? "passed" : "failed")",
      "evaluated=\(observations.count)/\(expectedInvocationCount)",
      "turnsEvaluated=\(evaluatedTurnCount)",
      "exact=\(observations.count(where: \.exactMatch))",
      "writeSideEffects=\(writeSideEffectCount)",
      "workspaceBoundaryViolations=\(workspaceBoundaryViolationCount)",
    ]
    for failure in preflight.failures {
      lines.append("PREFLIGHT FAIL: \(failure)")
    }
    for group in evaluatedByGroup.keys.sorted() {
      lines.append(
        "group.\(group)=\(exactMatchesByGroup[group, default: 0])/\(evaluatedByGroup[group, default: 0])"
      )
    }
    for locale in evaluatedByLocale.keys.sorted() {
      lines.append(
        "locale.\(locale)=\(exactMatchesByLocale[locale, default: 0])/\(evaluatedByLocale[locale, default: 0])"
      )
    }
    for observation in observations {
      lines.append(
        "CASE \(observation.caseID) [\(observation.localeIdentifier)] group=\(observation.group) exact=\(observation.exactMatch) expected={\(observation.expectedOutcome)} actual={\(observation.actualOutcome ?? "none")}"
      )
      for turn in observation.turns {
        lines.append(
          "  TURN \(turn.turnIndex) outcome={\(turn.actualOutcome ?? "none")} source=\(turn.interpretedSource ?? "none") route=\(turn.executionRoute ?? "none") executed=\(turn.executionSucceeded) answerSignature=\(turn.answer.actualSignature) evidenceSignature=\(turn.evidence.actualSignature) write=\(turn.writeSideEffect) boundary=\(turn.workspaceBoundaryViolation)"
        )
        for attempt in turn.compilerAttempts {
          lines.append(attempt.textSummary(prefix: "    ATTEMPT"))
        }
      }
    }
    for observation in observations {
      for turn in observation.turns where turn.writeSideEffect || turn.workspaceBoundaryViolation {
        lines.append(
          "SAFETY FAIL \(observation.caseID)#turn\(turn.turnIndex): "
            + "writeSideEffect=\(turn.writeSideEffect) "
            + "workspaceBoundaryViolation=\(turn.workspaceBoundaryViolation)"
        )
      }
    }
    return lines.joined(separator: "\n")
  }
}

@MainActor
enum MarinaFoundationModelCorpusSoakAttachment {
  static func add(report: MarinaFoundationModelCorpusSoakReport, to testCase: XCTestCase) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    let json = XCTAttachment(
      data: try encoder.encode(report),
      uniformTypeIdentifier: "public.json"
    )
    json.name = "MarinaFoundationModelCorpusSoak.json"
    json.lifetime = .keepAlways
    testCase.add(json)

    let text = XCTAttachment(
      data: Data(report.textSummary.utf8),
      uniformTypeIdentifier: "public.plain-text"
    )
    text.name = "MarinaFoundationModelCorpusSoak.txt"
    text.lifetime = .keepAlways
    testCase.add(text)
  }
}
