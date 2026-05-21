import XCTest

struct MarinaAppSurfaceReport: Codable {
    let model: String?
    let prompt: String
    let expectedOutcome: String?
    let expectedRequestShape: String?
    let expectedResponseShape: String?
    let visibleAnswer: MarinaVisibleAnswer
    let responseKind: String?
    let clarificationChips: [String]
    let recoveryChips: [String]
    let followUpChips: [String]
    let runtimePath: String?
    let selectedRoute: String?
    let interpreter: String?
    let turnClassification: String?
    let priorContextUsed: Bool?
    let executorRoute: String?
    let diagnostics: MarinaSurfaceDiagnostics?
    let trace: MarinaTraceSnapshot?
    let result: MarinaSurfaceResult
}

typealias MarinaSurfaceReport = MarinaAppSurfaceReport

struct MarinaVisibleAnswer: Codable {
    let title: String?
    let value: String
    let label: String
    let text: String
    let rowTitles: [String]
    let rowValues: [String]

    func containsAll(_ requiredText: [String]) -> Bool {
        requiredText.allSatisfy { text.localizedCaseInsensitiveContains($0) }
    }

    var topRowTitle: String? {
        rowTitles.first
    }
}

struct MarinaTraceSnapshot: Codable {
    let originalPrompt: String
    let routingMode: String
    let marinaNLQv1Enabled: Bool?
    let runtimeSettingsSummary: String?
    let selectedRoute: String
    let selectedRouteReason: String?
    let aggregationPath: String?
    let responseType: String?
    let finalAnswerSummary: String?
    let sharedPipelineEnabled: Bool?
    let sharedPipelinePath: String?
    let sharedPipelineInterpreterSource: String?
    let sharedPipelineHeuristicAttempted: Bool?
    let sharedPipelineHeuristicUsedAsFallback: Bool?
    let sharedPipelineCandidateSummary: String?
    let sharedPipelineResolverSummary: String?
    let sharedPipelineValidatorSummary: String?
    let sharedPipelineExecutorSummary: String?
    let sharedPipelineResponseBridgeSummary: String?
    let sharedPipelineResponseShapeSummary: String?
    let sharedPipelineSemanticInterpretationSummary: String?
    let sharedPipelineSemanticResolverSummary: String?
    let sharedPipelineSemanticValidationSummary: String?
    let sharedPipelineFallbackReason: String?
    let sharedPipelineDisagreementSummary: String?
    let turnClassification: String?
    let priorContextIncluded: Bool?

    init(accessibilityValue: String) {
        let fields = Dictionary(
            uniqueKeysWithValues: accessibilityValue
                .components(separatedBy: " | ")
                .compactMap { component -> (String, String)? in
                    guard let separator = component.firstIndex(of: "=") else { return nil }
                    let key = String(component[..<separator])
                    let value = String(component[component.index(after: separator)...])
                    return (key, value)
                }
        )
        self.originalPrompt = fields["prompt"] ?? ""
        self.routingMode = fields["routingMode"] ?? ""
        self.marinaNLQv1Enabled = nil
        self.runtimeSettingsSummary = nil
        self.selectedRoute = fields["selectedRoute"] ?? ""
        self.selectedRouteReason = nil
        self.aggregationPath = fields["aggregationPath"]
        self.responseType = fields["responseType"]
        self.finalAnswerSummary = nil
        self.sharedPipelineEnabled = nil
        self.sharedPipelinePath = fields["sharedPath"]
        self.sharedPipelineInterpreterSource = fields["interpreter"]
        self.sharedPipelineHeuristicAttempted = fields["heuristicAttempted"].flatMap(Bool.init)
        self.sharedPipelineHeuristicUsedAsFallback = fields["heuristicUsedAsFallback"].flatMap(Bool.init)
        self.sharedPipelineCandidateSummary = fields["candidate"]
        self.sharedPipelineResolverSummary = nil
        self.sharedPipelineValidatorSummary = nil
        self.sharedPipelineExecutorSummary = fields["executor"]
        self.sharedPipelineResponseBridgeSummary = fields["bridge"]
        self.sharedPipelineResponseShapeSummary = nil
        self.sharedPipelineSemanticInterpretationSummary = nil
        self.sharedPipelineSemanticResolverSummary = nil
        self.sharedPipelineSemanticValidationSummary = nil
        self.sharedPipelineFallbackReason = fields["fallback"]
        self.sharedPipelineDisagreementSummary = nil
        self.turnClassification = fields["turnClassification"]
        self.priorContextIncluded = fields["priorContextIncluded"].flatMap(Bool.init)
    }
}

struct MarinaSurfaceResult: Codable {
    let passed: Bool
    let category: MarinaSurfaceFailureCategory
    let reason: String
}

struct MarinaSurfaceDiagnostics: Codable {
    let candidateSummary: String?
    let resolverSummary: String?
    let semanticResolverSummary: String?
    let validatorSummary: String?
    let unsupportedReason: String?
}

enum MarinaSurfaceFailureCategory: String, Codable {
    case pass
    case noAssistantSurface
    case promptNotSubmitted
    case noVisibleAnswer
    case wrongRuntimeRoute
    case stalePriorContext
    case priorContextDropped
    case unexpectedClarification
    case unsupportedDespiteSemanticSupport
    case responseBridgeMismatch
    case suggestionChipRecursion
    case fixtureDataMismatch
    case foundationModelsNondeterminism
    case legacyRouteInterception
    case traceUnavailable
    case responseShapeMismatch
    case requestShapeMismatch
    case missingClarificationChips
    case ambiguityCollapsedToUnsupported
    case ambiguityCollapsedToSingleType
}

@MainActor
final class MarinaAppSurfaceReporter {
    private var reports: [MarinaAppSurfaceReport] = []

    func record(_ report: MarinaAppSurfaceReport) {
        reports.append(report)
        if let line = encodeLine(report) {
            print("[MarinaSurfaceReport] \(line)")
        }
    }

    func attach(to testCase: XCTestCase) {
        let lines = reports.compactMap(encodeLine).joined(separator: "\n")
        let attachment = XCTAttachment(string: lines)
        attachment.name = "MarinaAppSurfaceReport.jsonl"
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }

    var failures: [MarinaAppSurfaceReport] {
        reports.filter { $0.result.passed == false }
    }

    private func encodeLine(_ report: MarinaAppSurfaceReport) -> String? {
        guard let data = try? JSONEncoder().encode(report) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
