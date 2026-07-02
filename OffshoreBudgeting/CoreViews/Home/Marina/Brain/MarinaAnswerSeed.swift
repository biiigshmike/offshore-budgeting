import Foundation

struct MarinaAnswerSeed: Equatable {
    let answer: HomeAnswer
    let insightContext: MarinaInsightContext?
    let finalExplanationSuffix: String?
    let scriptedNarration: String?
    let debugTrace: MarinaAnswerDebugTrace?

    init(
        answer: HomeAnswer,
        insightContext: MarinaInsightContext?,
        finalExplanationSuffix: String?,
        scriptedNarration: String? = nil,
        debugTrace: MarinaAnswerDebugTrace? = nil
    ) {
        self.answer = answer
        self.insightContext = insightContext
        self.finalExplanationSuffix = finalExplanationSuffix
        self.scriptedNarration = scriptedNarration
        self.debugTrace = debugTrace
    }
}

struct MarinaAnswerDebugTrace: Equatable, Sendable {
    enum PromptTreatment: String, Equatable, Sendable {
        case standalone
        case contextualFollowUp
        case recommendedFollowUpConfirmation
        case declinedFollowUp
    }

    enum ExecutionRoute: String, Equatable, Sendable {
        case legacy
        case universal
        case legacyFallback
    }

    let originalPrompt: String
    let promptTreatment: PromptTreatment
    let priorContextChangedRequest: Bool
    let interpretedRequest: MarinaSemanticRequest
    let interpretedSource: MarinaSemanticSource
    let interpretedConfidence: MarinaSemanticConfidence
    let interpretedNotes: [String]
    let explicitPromptTargets: [String]
    let candidateSearches: [MarinaCandidateSearchTrace]
    let resolverOutput: MarinaSemanticRequest
    let validatorOutput: MarinaSemanticRequest
    let validatorAccepted: Bool
    let validatorNotes: [String]
    let queryPlan: MarinaQueryPlanTrace
    let executionRoute: ExecutionRoute
    let universalScenario: MarinaUniversalRoutingScenario?
    let universalFallbackReason: MarinaUniversalFallbackReason?
    let universalNotes: [String]
    let rowCount: Int
    let evidenceRowSummaries: [String]
    let answerKind: HomeAnswerKind
    let answerTitle: String
    let answerPrimaryValue: String?
    let narrationRequested: Bool

    var debugDescription: String {
        [
            "prompt=\(originalPrompt)",
            "promptTreatment=\(promptTreatment.rawValue)",
            "priorContextChangedRequest=\(priorContextChangedRequest)",
            "source=\(interpretedSource.rawValue)",
            "confidence=\(interpretedConfidence.rawValue)",
            "interpreted=\(Self.summary(interpretedRequest))",
            "interpretedNotes=\(Self.list(interpretedNotes))",
            "explicitPromptTargets=\(explicitPromptTargets.joined(separator: ", "))",
            "candidateSearches=\(candidateSearches.map(\.debugDescription).joined(separator: " || "))",
            "resolverOutput=\(Self.summary(resolverOutput))",
            "validatorOutput=\(Self.summary(validatorOutput))",
            "validatorAccepted=\(validatorAccepted)",
            "validatorNotes=\(Self.list(validatorNotes))",
            "queryPlan=\(queryPlan.debugDescription)",
            "executionRoute=\(executionRoute.rawValue)",
            "universalScenario=\(universalScenario?.rawValue ?? "none")",
            "universalFallbackReason=\(universalFallbackReason?.rawValue ?? "none")",
            "universalNotes=\(Self.list(universalNotes))",
            "rowCount=\(rowCount)",
            "evidenceRows=\(evidenceRowSummaries.joined(separator: " | "))",
            "answer=\(answerKind.rawValue) title=\(answerTitle) value=\(answerPrimaryValue ?? "none")",
            "narrationRequested=\(narrationRequested)"
        ].joined(separator: "\n")
    }

    private static func summary(_ request: MarinaSemanticRequest) -> String {
        [
            "entity=\(request.entity.rawValue)",
            "operation=\(request.operation.rawValue)",
            "measure=\(request.measure?.rawValue ?? "none")",
            "dimensions=\(request.dimensions.map(\.rawValue).joined(separator: ","))",
            "dateToken=\(request.dateRangeToken.rawValue)",
            "target=\(request.targetName ?? "none")",
            "comparison=\(request.comparisonTargetName ?? "none")",
            "textQuery=\(request.textQuery ?? "none")",
            "targetDisplay=\(request.targetDisplayName ?? "none")",
            "expenseScope=\(request.expenseScope?.rawValue ?? "none")",
            "whatIfAmount=\(request.whatIfAmount.map { "\($0)" } ?? "none")",
            "shape=\(request.expectedAnswerShape.rawValue)",
            "unsupported=\(request.unsupportedReason?.rawValue ?? "none")"
        ].joined(separator: " ")
    }

    private static func list(_ values: [String]) -> String {
        values.isEmpty ? "none" : values.joined(separator: " | ")
    }
}

struct MarinaQueryPlanTrace: Equatable, Sendable {
    let entity: MarinaSemanticEntity
    let operation: MarinaSemanticOperation
    let measure: MarinaSemanticMeasure?
    let dimensions: [MarinaSemanticDimension]
    let dateRangeToken: MarinaSemanticDateRangeToken
    let dateRangeDescription: String?
    let comparisonDateRangeDescription: String?
    let targetName: String?
    let comparisonTargetName: String?
    let textQuery: String?
    let targetDisplayName: String?
    let expenseScope: MarinaSemanticExpenseScope?
    let whatIfAmount: Double?
    let expectedAnswerShape: MarinaSemanticAnswerShape

    init(plan: MarinaQueryPlan) {
        entity = plan.entity
        operation = plan.operation
        measure = plan.measure
        dimensions = plan.dimensions
        dateRangeToken = plan.semanticRequest.dateRangeToken
        dateRangeDescription = Self.description(for: plan.dateRange)
        comparisonDateRangeDescription = Self.description(for: plan.comparisonDateRange)
        targetName = plan.targetName
        comparisonTargetName = plan.comparisonTargetName
        textQuery = plan.semanticRequest.textQuery
        targetDisplayName = plan.semanticRequest.targetDisplayName
        expenseScope = plan.semanticRequest.expenseScope
        whatIfAmount = plan.semanticRequest.whatIfAmount
        expectedAnswerShape = plan.semanticRequest.expectedAnswerShape
    }

    var debugDescription: String {
        [
            "entity=\(entity.rawValue)",
            "operation=\(operation.rawValue)",
            "measure=\(measure?.rawValue ?? "none")",
            "dimensions=\(dimensions.map(\.rawValue).joined(separator: ","))",
            "dateToken=\(dateRangeToken.rawValue)",
            "dateRange=\(dateRangeDescription ?? "none")",
            "comparisonDateRange=\(comparisonDateRangeDescription ?? "none")",
            "target=\(targetName ?? "none")",
            "comparison=\(comparisonTargetName ?? "none")",
            "textQuery=\(textQuery ?? "none")",
            "targetDisplay=\(targetDisplayName ?? "none")",
            "expenseScope=\(expenseScope?.rawValue ?? "none")",
            "whatIfAmount=\(whatIfAmount.map { "\($0)" } ?? "none")",
            "shape=\(expectedAnswerShape.rawValue)"
        ].joined(separator: " ")
    }

    private static func description(for range: HomeQueryDateRange?) -> String? {
        guard let range else { return nil }
        return "\(range.startDate.timeIntervalSince1970)-\(range.endDate.timeIntervalSince1970)"
    }
}
