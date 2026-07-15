import Foundation
import UIKit
import XCTest

@testable import Offshore

enum MarinaFoundationModelDeviceTestMode: String, Encodable, Sendable {
  case calibration
  case blocking
  case corpusSoak
}

struct MarinaFoundationModelDevicePreflight: Encodable, Sendable {
  let physicalDevice: Bool
  let supportedOperatingSystem: Bool
  let modelAvailability: String
  let sourceMetadataAvailable: Bool
  let failures: [String]

  var passed: Bool { failures.isEmpty }

  func addingFailure(_ failure: String) -> Self {
    Self(
      physicalDevice: physicalDevice,
      supportedOperatingSystem: supportedOperatingSystem,
      modelAvailability: modelAvailability,
      sourceMetadataAvailable: sourceMetadataAvailable,
      failures: failures + [failure]
    )
  }
}

struct MarinaFoundationModelDeviceRunMetadata: Encodable, Sendable {
  let testMode: String
  let generatedAt: Date
  let deviceName: String
  let deviceModel: String
  let operatingSystem: String
  let appVersion: String
  let appBuild: String
  let modelAvailability: String
  let generationSampling: String
  let generationTemperature: Double
  let compilerVersion: String
  let instructionVersion: String
  let generationArchitecture: String
  let maximumGenerationPhasesPerAttempt: Int
  let freshSessionPerCase: Bool
  let freshSessionPerPhase: Bool
  let starterCatalogVersion: String
  let corpusVersion: String
  let sourceRevision: String
  let sourceDirtyState: String

  init(
    mode: MarinaFoundationModelDeviceTestMode,
    modelAvailability: String,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    let info = Bundle.main.infoDictionary ?? [:]
    testMode = mode.rawValue
    generatedAt = .now
    deviceName = UIDevice.current.name
    deviceModel = UIDevice.current.model
    operatingSystem = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    appVersion = info["CFBundleShortVersionString"] as? String ?? "unknown"
    appBuild = info["CFBundleVersion"] as? String ?? "unknown"
    self.modelAvailability = modelAvailability
    generationSampling = "greedy"
    generationTemperature = 0
    compilerVersion = MarinaFoundationModelInstructionCatalogV3.compilerVersion
    instructionVersion = MarinaFoundationModelInstructionCatalogV3.instructionVersion
    generationArchitecture = "outcomeRoute/financialDomain/actionRoute/actionPayload"
    maximumGenerationPhasesPerAttempt = 4
    freshSessionPerCase = true
    freshSessionPerPhase = true
    starterCatalogVersion = MarinaFoundationModelDeviceCaseCatalog.version
    corpusVersion = MarinaFoundationModelReleaseCorpusV1.version
    sourceRevision = Self.metadataValue(
      environment["MARINA_SOURCE_REVISION"],
      fallback: "unavailable"
    )
    sourceDirtyState = Self.metadataValue(
      environment["MARINA_SOURCE_DIRTY"],
      fallback: "unknown"
    )
  }

  static func sourceMetadataIsAvailable(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Bool {
    metadataValue(environment["MARINA_SOURCE_REVISION"], fallback: "").isEmpty == false
      && metadataValue(environment["MARINA_SOURCE_DIRTY"], fallback: "").isEmpty == false
  }

  private static func metadataValue(_ value: String?, fallback: String) -> String {
    guard let value else { return fallback }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false, trimmed.contains("$(") == false else { return fallback }
    return String(trimmed.prefix(128))
  }
}

struct MarinaFoundationModelDeviceAnswerObservation: Encodable, Sendable {
  let expectedKind: String
  let actualKind: String
  let titleStatus: String
  let primaryValuePresent: Bool
  let answerRowCount: Int
  let expectedSignature: String?
  let actualSignature: String
  let signatureMatched: Bool?
}

struct MarinaFoundationModelDeviceEvidenceObservation: Encodable, Sendable {
  let rowCount: Int
  let expectedSignature: String?
  let actualSignature: String
  let signatureMatched: Bool?
}

struct MarinaFoundationModelDeviceCaseResult: Encodable, Sendable {
  let caseID: String
  let repetition: Int
  let localeIdentifier: String
  let expectedSemanticDigest: String
  let actualSemanticDigest: String?
  let compilerAttempts: [MarinaFoundationModelDeviceAttemptResult]
  let interpretedSource: String?
  let alignmentAccepted: Bool
  let validatorAccepted: Bool
  let executionRoute: String?
  let executionSucceeded: Bool
  let answer: MarinaFoundationModelDeviceAnswerObservation
  let evidence: MarinaFoundationModelDeviceEvidenceObservation
  let writeSideEffect: Bool
  let workspaceBoundaryViolation: Bool
  let durationMilliseconds: Int
  let failures: [String]

  var passed: Bool { failures.isEmpty }
}

struct MarinaFoundationModelDeviceAttemptResult: Encodable, Sendable {
  struct PhaseDuration: Encodable, Sendable {
    let phase: String
    let milliseconds: Int
  }

  let attempt: Int
  let compilerVersion: String
  let instructionVersion: String
  let generationPhase: String?
  let generationPhaseCount: Int?
  let generatedRoutePathDigest: String?
  let generationPhaseDurations: [PhaseDuration]
  let generationDurationMilliseconds: Int
  let stage: String
  let status: String
  let rejectionCode: String?
  let reason: String
  let alignmentVerdict: String?
  let generatedIntentDigest: String?
  let compiledRequestDigest: String?
  let expectedAlignmentDigest: String?
  let actualAlignmentDigest: String?

  init(_ diagnostic: MarinaFoundationModelAttemptDiagnostic) {
    attempt = diagnostic.attempt
    compilerVersion = diagnostic.compilerVersion
    instructionVersion = diagnostic.instructionVersion
    generationPhase = diagnostic.generationPhase?.rawValue
    generationPhaseCount = diagnostic.generationPhaseCount?.rawValue
    generatedRoutePathDigest = diagnostic.generatedRoutePath?.rendered
    generationPhaseDurations = diagnostic.generationPhaseDurations.map {
      PhaseDuration(phase: $0.phase.rawValue, milliseconds: $0.milliseconds)
    }
    generationDurationMilliseconds = diagnostic.generationPhaseDurations.reduce(0) {
      $0 + $1.milliseconds
    }
    stage = diagnostic.stage.rawValue
    status = diagnostic.status.rawValue
    rejectionCode = diagnostic.rejectionCode
    reason = diagnostic.reason
    alignmentVerdict = diagnostic.alignmentVerdict?.rawValue
    generatedIntentDigest = diagnostic.generatedIntent?.rendered
    compiledRequestDigest = diagnostic.compiledRequest?.rendered
    expectedAlignmentDigest = diagnostic.alignment?.expected.rendered
    actualAlignmentDigest = diagnostic.alignment?.actual.rendered
  }
}

struct MarinaFoundationModelDeviceGateReport: Encodable, Sendable {
  let formatVersion: String
  let metadata: MarinaFoundationModelDeviceRunMetadata
  let preflight: MarinaFoundationModelDevicePreflight
  let expectedInvocationCount: Int
  let totalCount: Int
  let passedCount: Int
  let results: [MarinaFoundationModelDeviceCaseResult]

  init(
    mode: MarinaFoundationModelDeviceTestMode,
    modelAvailability: String,
    preflight: MarinaFoundationModelDevicePreflight,
    expectedInvocationCount: Int,
    results: [MarinaFoundationModelDeviceCaseResult]
  ) {
    formatVersion = "marina.foundation-model.device-report.v4"
    metadata = MarinaFoundationModelDeviceRunMetadata(
      mode: mode,
      modelAvailability: modelAvailability
    )
    self.preflight = preflight
    self.expectedInvocationCount = expectedInvocationCount
    totalCount = results.count
    passedCount = results.count(where: \.passed)
    self.results = results
  }

  var textSummary: String {
    var lines = [
      "Marina Foundation Model physical-device \(metadata.testMode)",
      "format=\(formatVersion)",
      "generatedAt=\(metadata.generatedAt.formatted(.iso8601))",
      "device=\(metadata.deviceName) (\(metadata.deviceModel))",
      "os=\(metadata.operatingSystem)",
      "app=\(metadata.appVersion) (\(metadata.appBuild))",
      "modelAvailability=\(metadata.modelAvailability)",
      "sourceRevision=\(metadata.sourceRevision)",
      "sourceDirtyState=\(metadata.sourceDirtyState)",
      "catalog=\(metadata.starterCatalogVersion)",
      "corpus=\(metadata.corpusVersion)",
      "generation=\(metadata.generationSampling) temperature=\(metadata.generationTemperature) compiler=\(metadata.compilerVersion) instructions=\(metadata.instructionVersion) architecture=\(metadata.generationArchitecture) maximumPhasesPerAttempt=\(metadata.maximumGenerationPhasesPerAttempt) freshSessionPerCase=\(metadata.freshSessionPerCase) freshSessionPerPhase=\(metadata.freshSessionPerPhase)",
      "preflight=\(preflight.passed ? "passed" : "failed")",
      "result=\(passedCount)/\(expectedInvocationCount) required invocations passed",
    ]
    for failure in preflight.failures {
      lines.append("PREFLIGHT FAIL: \(failure)")
    }
    for result in results {
      lines.append(
        "CASE \(result.caseID)#\(result.repetition) [\(result.localeIdentifier)] passed=\(result.passed)"
      )
      lines.append(
        "  semantic expected={\(result.expectedSemanticDigest)} actual={\(result.actualSemanticDigest ?? "none")}"
      )
      lines.append(
        "  execution source=\(result.interpretedSource ?? "none") alignment=\(result.alignmentAccepted) validator=\(result.validatorAccepted) route=\(result.executionRoute ?? "none") succeeded=\(result.executionSucceeded)"
      )
      lines.append(
        "  answer expectedKind=\(result.answer.expectedKind) actualKind=\(result.answer.actualKind) expectedSignature=\(result.answer.expectedSignature ?? "none") actualSignature=\(result.answer.actualSignature) matched=\(result.answer.signatureMatched.map(String.init) ?? "none")"
      )
      lines.append(
        "  evidence rows=\(result.evidence.rowCount) expectedSignature=\(result.evidence.expectedSignature ?? "none") actualSignature=\(result.evidence.actualSignature) matched=\(result.evidence.signatureMatched.map(String.init) ?? "none")"
      )
      for attempt in result.compilerAttempts {
        lines.append(attempt.textSummary(prefix: "  ATTEMPT"))
      }
    }
    for result in results where result.passed == false {
      lines.append(
        "FAIL \(result.caseID)#\(result.repetition) [\(result.localeIdentifier)]: "
          + result.failures.joined(separator: " | ")
      )
    }
    return lines.joined(separator: "\n")
  }
}

extension MarinaFoundationModelDeviceAttemptResult {
  func textSummary(prefix: String) -> String {
    [
      prefix,
      "number=\(attempt)",
      "compiler=\(compilerVersion)",
      "instructions=\(instructionVersion)",
      "generationPhase=\(generationPhase ?? "none")",
      "generationPhaseCount=\(generationPhaseCount.map(String.init) ?? "none")",
      "generatedRoutePath={\(generatedRoutePathDigest ?? "none")}",
      "generationPhaseDurations=[\(generationPhaseDurations.map { "\($0.phase):\($0.milliseconds)ms" }.joined(separator: ","))]",
      "generationDurationMilliseconds=\(generationDurationMilliseconds)",
      "stage=\(stage)",
      "status=\(status)",
      "rejection=\(rejectionCode ?? "none")",
      "reason={\(reason)}",
      "alignment=\(alignmentVerdict ?? "none")",
      "generated={\(generatedIntentDigest ?? "none")}",
      "compiled={\(compiledRequestDigest ?? "none")}",
      "expectedAlignment={\(expectedAlignmentDigest ?? "none")}",
      "actualAlignment={\(actualAlignmentDigest ?? "none")}",
    ].joined(separator: " ")
  }
}

@MainActor
enum MarinaFoundationModelDeviceReportAttachment {
  static func add(
    report: MarinaFoundationModelDeviceGateReport,
    to testCase: XCTestCase,
    baseName: String
  ) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    let jsonAttachment = XCTAttachment(
      data: try encoder.encode(report),
      uniformTypeIdentifier: "public.json"
    )
    jsonAttachment.name = "\(baseName).json"
    jsonAttachment.lifetime = .keepAlways
    testCase.add(jsonAttachment)

    let textAttachment = XCTAttachment(
      data: Data(report.textSummary.utf8),
      uniformTypeIdentifier: "public.plain-text"
    )
    textAttachment.name = "\(baseName).txt"
    textAttachment.lifetime = .keepAlways
    testCase.add(textAttachment)
  }
}
