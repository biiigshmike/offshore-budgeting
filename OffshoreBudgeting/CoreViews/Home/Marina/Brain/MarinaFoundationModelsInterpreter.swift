import Dispatch
import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macCatalyst 26.0, *)
nonisolated enum MarinaFoundationModelGenerationFailure: String, Equatable, Sendable {
    case decodingFailure
    case unsupportedGuide
    case cancelled
    case unexpected

    var rejectionCode: String { "generation.\(rawValue)" }

    var isRetryable: Bool {
        self == .decodingFailure
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
nonisolated enum MarinaFoundationModelInvalidOutcome: String, Equatable, Sendable {
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

    var rejectionCode: String { "compiler.\(rawValue)" }

    var reason: String {
        switch self {
        case .emptyNamedBudget: "The named budget wording was empty."
        case .emptyTarget: "The primary target wording was empty."
        case .emptyComparisonTarget: "The comparison target wording was empty."
        case .emptyNamedFilter: "A generated named-filter value was empty."
        case .invalidResultLimit: "The result limit was outside the supported range."
        case .dateContextWithoutPriorRequest: "A conversation-context date was generated without trusted prior context."
        case .continuationWithoutContext: "A show-more continuation was generated without trusted prior context."
        case .continuationWithoutOffset: "A show-more continuation had no trusted next offset."
        case .clarificationSelectionWithoutContext: "A clarification selection was generated without trusted choices."
        case .clarificationSelectionOutOfBounds: "The generated clarification selection was outside the trusted choices."
        case .followUpDecisionWithoutContext: "A follow-up decision was generated without a trusted offered follow-up."
        case .followUpAcceptanceWithoutExecutableRequest: "The accepted follow-up had no trusted executable request."
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
nonisolated enum MarinaFoundationModelInterpretationError: LocalizedError, Equatable, Sendable {
    case generationFailed(MarinaFoundationModelGenerationFailure)
    case invalidGeneratedOutcome(MarinaFoundationModelInvalidOutcome)

    var errorDescription: String? {
        switch self {
        case .generationFailed(.decodingFailure):
            return "Marina's on-device model could not decode a semantic request."
        case .generationFailed(.unsupportedGuide):
            return "Marina's on-device model does not support part of the semantic schema."
        case .generationFailed(.cancelled):
            return "Marina's on-device semantic request was cancelled."
        case .generationFailed(.unexpected):
            return "Marina's on-device model could not generate a semantic request."
        case .invalidGeneratedOutcome(let invalid):
            return "\(invalid.rejectionCode): \(invalid.reason)"
        }
    }

    var rejectionCode: String {
        attemptRejectionCode.rawValue
    }

    var attemptRejectionCode: MarinaFoundationModelAttemptRejectionCode {
        switch self {
        case .generationFailed(let failure):
            .generation(failure.attemptDiagnosticCode)
        case .invalidGeneratedOutcome(let invalid):
            .compiler(invalid.attemptDiagnosticCode)
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelGenerationFailure {
    nonisolated var attemptDiagnosticCode: MarinaFoundationModelAttemptRejectionCode.Generation {
        switch self {
        case .decodingFailure: .decodingFailure
        case .unsupportedGuide: .unsupportedGuide
        case .cancelled: .cancelled
        case .unexpected: .unexpected
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelInvalidOutcome {
    nonisolated var attemptDiagnosticCode: MarinaFoundationModelAttemptRejectionCode.Compiler {
        switch self {
        case .emptyNamedBudget: .emptyNamedBudget
        case .emptyTarget: .emptyTarget
        case .emptyComparisonTarget: .emptyComparisonTarget
        case .emptyNamedFilter: .emptyNamedFilter
        case .invalidResultLimit: .invalidResultLimit
        case .dateContextWithoutPriorRequest: .dateContextWithoutPriorRequest
        case .continuationWithoutContext: .continuationWithoutContext
        case .continuationWithoutOffset: .continuationWithoutOffset
        case .clarificationSelectionWithoutContext: .clarificationSelectionWithoutContext
        case .clarificationSelectionOutOfBounds: .clarificationSelectionOutOfBounds
        case .followUpDecisionWithoutContext: .followUpDecisionWithoutContext
        case .followUpAcceptanceWithoutExecutableRequest: .followUpAcceptanceWithoutExecutableRequest
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
nonisolated enum MarinaFoundationModelRuntimeResult: Equatable, Sendable {
    case generated(
        MarinaFoundationModelGeneratedOutcomeV3,
        generationMetadata: MarinaFoundationModelGenerationDiagnosticMetadata? = nil,
        diagnosticNotes: [String]
    )
    case unsupported(MarinaSemanticUnsupportedReason, diagnosticNotes: [String])
    case generationFailure(MarinaFoundationModelGenerationFailure, diagnosticNotes: [String])
    case stagedFailure(
        MarinaFoundationModelStagedRuntimeFailure,
        generatedIntent: MarinaFoundationModelGeneratedIntentDigest?,
        generationMetadata: MarinaFoundationModelGenerationDiagnosticMetadata? = nil,
        diagnosticNotes: [String]
    )
}

@available(iOS 26.0, macCatalyst 26.0, *)
nonisolated enum MarinaFoundationModelStagedRuntimeFailure: Equatable, Sendable {
    case unsupported(MarinaSemanticUnsupportedReason)
    case generation(MarinaFoundationModelGenerationFailure)
}

@available(iOS 26.0, macCatalyst 26.0, *)
protocol MarinaFoundationModelGenerating: Sendable {
    func generateOutcome(
        for prompt: String,
        localeConfiguration: MarinaFoundationModelLocaleConfiguration
    ) async -> MarinaFoundationModelRuntimeResult
}

@available(iOS 26.0, macCatalyst 26.0, *)
struct MarinaFoundationModelsInterpreter: MarinaModelInterpreting {
    private let runtime: any MarinaFoundationModelGenerating
    private let localeConfiguration: MarinaFoundationModelLocaleConfiguration
    private let alignmentValidator: MarinaSemanticPromptAlignmentValidator

    init(
        runtime: any MarinaFoundationModelGenerating = MarinaFoundationModelRuntime(),
        localeConfiguration: MarinaFoundationModelLocaleConfiguration = .current,
        alignmentValidator: MarinaSemanticPromptAlignmentValidator = MarinaSemanticPromptAlignmentValidator()
    ) {
        self.runtime = runtime
        self.localeConfiguration = localeConfiguration
        self.alignmentValidator = alignmentValidator
    }

    func interpretedSemanticRequest(
        for prompt: String,
        context: MarinaBrainContext
    ) async throws -> MarinaInterpretedSemanticRequest {
        let normalizedPrompt = MarinaPromptNormalizer.normalize(prompt)
        let turn = MarinaSemanticCompilerTurnV3(
            userInput: normalizedPrompt,
            conversationContext: context.conversationContext
        )
        var accumulatedNotes: [String] = []
        var attemptDiagnostics: [MarinaFoundationModelAttemptDiagnostic] = []
        var retryCode: String?

        for attempt in 1...2 {
            let attemptPrompt = retryCode.map { turn.promptForRetry(rejectionCode: $0) } ?? turn.prompt
            let result = await runtime.generateOutcome(
                for: attemptPrompt,
                localeConfiguration: localeConfiguration
            )

            switch result {
            case .generated(let outcome, let generationMetadata, let runtimeNotes):
                let generatedIntent = outcome.generatedIntentDigest
                do {
                    var interpreted = try MarinaFoundationModelOutcomeCompilerV3().interpretedRequest(
                        from: outcome,
                        turn: turn
                    )
                    let compiledRequest = MarinaFoundationModelCompiledRequestDigest(
                        request: interpreted.request
                    )
                    let alignment = alignmentValidator.validate(
                        userInput: normalizedPrompt,
                        request: interpreted.request,
                        localeIdentifier: localeConfiguration.identifier
                    )
                    switch alignment {
                    case .accepted:
                        let diagnostic = MarinaFoundationModelAttemptDiagnostic(
                            attempt: attempt,
                            compilerVersion: MarinaSemanticCompilerInstructionsV3.version,
                            generationPhase: generationMetadata?.phase,
                            generationPhaseCount: generationMetadata?.phaseCount,
                            generatedRoutePath: generationMetadata?.routePath,
                            generationPhaseDurations: generationMetadata?.phaseDurations ?? [],
                            stage: .alignment,
                            status: .accepted,
                            rejection: nil,
                            alignmentVerdict: .accepted,
                            generatedIntent: generatedIntent,
                            compiledRequest: compiledRequest,
                            alignment: nil
                        )
                        attemptDiagnostics.append(diagnostic)
                        interpreted.diagnosticNotes = accumulatedNotes + runtimeNotes + [diagnostic.diagnosticNote]
                        interpreted.attemptDiagnostics = attemptDiagnostics
                        return interpreted
                    case .inconclusive:
                        let diagnostic = MarinaFoundationModelAttemptDiagnostic(
                            attempt: attempt,
                            compilerVersion: MarinaSemanticCompilerInstructionsV3.version,
                            generationPhase: generationMetadata?.phase,
                            generationPhaseCount: generationMetadata?.phaseCount,
                            generatedRoutePath: generationMetadata?.routePath,
                            generationPhaseDurations: generationMetadata?.phaseDurations ?? [],
                            stage: .alignment,
                            status: .accepted,
                            rejection: nil,
                            alignmentVerdict: .inconclusive,
                            generatedIntent: generatedIntent,
                            compiledRequest: compiledRequest,
                            alignment: nil
                        )
                        attemptDiagnostics.append(diagnostic)
                        interpreted.diagnosticNotes = accumulatedNotes + runtimeNotes + [diagnostic.diagnosticNote]
                        interpreted.attemptDiagnostics = attemptDiagnostics
                        return interpreted
                    case .rejected(let rejection):
                        let canRetry = attempt == 1
                        let diagnostic = MarinaFoundationModelAttemptDiagnostic(
                            attempt: attempt,
                            compilerVersion: MarinaSemanticCompilerInstructionsV3.version,
                            generationPhase: generationMetadata?.phase,
                            generationPhaseCount: generationMetadata?.phaseCount,
                            generatedRoutePath: generationMetadata?.routePath,
                            generationPhaseDurations: generationMetadata?.phaseDurations ?? [],
                            stage: .alignment,
                            status: canRetry ? .rejected : .terminal,
                            rejection: .alignment(rejection.code),
                            alignmentVerdict: .rejected,
                            generatedIntent: generatedIntent,
                            compiledRequest: compiledRequest,
                            alignment: MarinaFoundationModelAlignmentDigest(
                                expected: rejection.expectedDigest,
                                actual: rejection.actualDigest
                            )
                        )
                        attemptDiagnostics.append(diagnostic)
                        accumulatedNotes.append(contentsOf: runtimeNotes + [diagnostic.diagnosticNote])
                        if canRetry {
                            retryCode = rejection.code.rawValue
                            continue
                        }
                        return generationFailureRequest(
                            diagnosticNotes: accumulatedNotes,
                            attemptDiagnostics: attemptDiagnostics
                        )
                    }
                } catch let error as MarinaFoundationModelInterpretationError {
                    let canRetry = attempt == 1
                    let diagnostic = MarinaFoundationModelAttemptDiagnostic(
                        attempt: attempt,
                        compilerVersion: MarinaSemanticCompilerInstructionsV3.version,
                        generationPhase: generationMetadata?.phase,
                        generationPhaseCount: generationMetadata?.phaseCount,
                        generatedRoutePath: generationMetadata?.routePath,
                        generationPhaseDurations: generationMetadata?.phaseDurations ?? [],
                        stage: .compilation,
                        status: canRetry ? .rejected : .terminal,
                        rejection: error.attemptRejectionCode,
                        alignmentVerdict: nil,
                        generatedIntent: generatedIntent,
                        compiledRequest: nil,
                        alignment: nil
                    )
                    attemptDiagnostics.append(diagnostic)
                    accumulatedNotes.append(contentsOf: runtimeNotes + [diagnostic.diagnosticNote])
                    if canRetry {
                        retryCode = error.rejectionCode
                        continue
                    }
                    return generationFailureRequest(
                        diagnosticNotes: accumulatedNotes,
                        attemptDiagnostics: attemptDiagnostics
                    )
                }
            case .unsupported(let reason, let runtimeNotes):
                let diagnostic = MarinaFoundationModelAttemptDiagnostic(
                    attempt: attempt,
                    compilerVersion: MarinaSemanticCompilerInstructionsV3.version,
                    stage: .generation,
                    status: .terminal,
                    rejection: .runtime(reason),
                    alignmentVerdict: nil,
                    generatedIntent: nil,
                    compiledRequest: nil,
                    alignment: nil
                )
                attemptDiagnostics.append(diagnostic)
                return MarinaInterpretedSemanticRequest(
                    request: systemUnsupportedRequest(reason: reason),
                    confidence: .low,
                    source: .unavailableFallback,
                    diagnosticNotes: accumulatedNotes + runtimeNotes + [diagnostic.diagnosticNote],
                    attemptDiagnostics: attemptDiagnostics
                )
            case .generationFailure(let failure, let runtimeNotes):
                let canRetry = attempt == 1 && failure.isRetryable
                let error = MarinaFoundationModelInterpretationError.generationFailed(failure)
                let diagnostic = MarinaFoundationModelAttemptDiagnostic(
                    attempt: attempt,
                    compilerVersion: MarinaSemanticCompilerInstructionsV3.version,
                    stage: .generation,
                    status: canRetry ? .rejected : .terminal,
                    rejection: error.attemptRejectionCode,
                    alignmentVerdict: nil,
                    generatedIntent: nil,
                    compiledRequest: nil,
                    alignment: nil
                )
                attemptDiagnostics.append(diagnostic)
                accumulatedNotes.append(contentsOf: runtimeNotes + [diagnostic.diagnosticNote])
                if canRetry {
                    retryCode = error.rejectionCode
                    continue
                }
                return generationFailureRequest(
                    diagnosticNotes: accumulatedNotes,
                    attemptDiagnostics: attemptDiagnostics
                )
            case .stagedFailure(let failure, let generatedIntent, let generationMetadata, let runtimeNotes):
                switch failure {
                case .unsupported(let reason):
                    let diagnostic = MarinaFoundationModelAttemptDiagnostic(
                        attempt: attempt,
                        compilerVersion: MarinaSemanticCompilerInstructionsV3.version,
                        generationPhase: generationMetadata?.phase,
                        generationPhaseCount: generationMetadata?.phaseCount,
                        generatedRoutePath: generationMetadata?.routePath,
                        generationPhaseDurations: generationMetadata?.phaseDurations ?? [],
                        stage: .generation,
                        status: .terminal,
                        rejection: .runtime(reason),
                        alignmentVerdict: nil,
                        generatedIntent: generatedIntent,
                        compiledRequest: nil,
                        alignment: nil
                    )
                    attemptDiagnostics.append(diagnostic)
                    return MarinaInterpretedSemanticRequest(
                        request: systemUnsupportedRequest(reason: reason),
                        confidence: .low,
                        source: .unavailableFallback,
                        diagnosticNotes: accumulatedNotes + runtimeNotes + [diagnostic.diagnosticNote],
                        attemptDiagnostics: attemptDiagnostics
                    )
                case .generation(let generationFailure):
                    let canRetry = attempt == 1 && generationFailure.isRetryable
                    let error = MarinaFoundationModelInterpretationError.generationFailed(
                        generationFailure
                    )
                    let diagnostic = MarinaFoundationModelAttemptDiagnostic(
                        attempt: attempt,
                        compilerVersion: MarinaSemanticCompilerInstructionsV3.version,
                        generationPhase: generationMetadata?.phase,
                        generationPhaseCount: generationMetadata?.phaseCount,
                        generatedRoutePath: generationMetadata?.routePath,
                        generationPhaseDurations: generationMetadata?.phaseDurations ?? [],
                        stage: .generation,
                        status: canRetry ? .rejected : .terminal,
                        rejection: error.attemptRejectionCode,
                        alignmentVerdict: nil,
                        generatedIntent: generatedIntent,
                        compiledRequest: nil,
                        alignment: nil
                    )
                    attemptDiagnostics.append(diagnostic)
                    accumulatedNotes.append(contentsOf: runtimeNotes + [diagnostic.diagnosticNote])
                    if canRetry {
                        retryCode = error.rejectionCode
                        continue
                    }
                    return generationFailureRequest(
                        diagnosticNotes: accumulatedNotes,
                        attemptDiagnostics: attemptDiagnostics
                    )
                }
            }
        }

        return generationFailureRequest(
            diagnosticNotes: accumulatedNotes,
            attemptDiagnostics: attemptDiagnostics
        )
    }

    private func generationFailureRequest(
        diagnosticNotes: [String],
        attemptDiagnostics: [MarinaFoundationModelAttemptDiagnostic]
    ) -> MarinaInterpretedSemanticRequest {
        MarinaInterpretedSemanticRequest(
            request: systemUnsupportedRequest(reason: .modelGenerationFailed),
            confidence: .low,
            source: .unavailableFallback,
            diagnosticNotes: diagnosticNotes,
            attemptDiagnostics: attemptDiagnostics
        )
    }

    private func systemUnsupportedRequest(
        reason: MarinaSemanticUnsupportedReason
    ) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .workspace,
            operation: .list,
            projection: .records,
            expectedAnswerShape: .unsupported,
            unsupportedReason: reason
        )
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private struct MarinaFoundationModelStagedGeneratedOutcomeV3 {
    let outcome: MarinaFoundationModelGeneratedOutcomeV3
    let generationMetadata: MarinaFoundationModelGenerationDiagnosticMetadata
}

@available(iOS 26.0, macCatalyst 26.0, *)
private struct MarinaFoundationModelTimedPhaseV3<Value> {
    let value: Value
    let generationMetadata: MarinaFoundationModelGenerationDiagnosticMetadata
}


@available(iOS 26.0, macCatalyst 26.0, *)
struct MarinaFoundationModelRuntime: MarinaFoundationModelGenerating {
    private typealias Generated = MarinaFoundationModelGeneratedOutcomeV3
    private typealias ActionRoute = MarinaFoundationModelGeneratedActionRouteV3

    private let model: SystemLanguageModel
    private let options: GenerationOptions
    private let instructionCatalog: MarinaFoundationModelInstructionCatalogV3

    init(
        model: SystemLanguageModel = SystemLanguageModel(useCase: .general, guardrails: .default),
        options: GenerationOptions = GenerationOptions(
            sampling: .greedy,
            temperature: 0.0
        ),
        instructionCatalog: MarinaFoundationModelInstructionCatalogV3 = .production
    ) {
        self.model = model
        self.options = options
        self.instructionCatalog = instructionCatalog
    }

    func generateOutcome(
        for prompt: String,
        localeConfiguration: MarinaFoundationModelLocaleConfiguration
    ) async -> MarinaFoundationModelRuntimeResult {
        guard model.isAvailable else {
            return .unsupported(
                .unavailableModel,
                diagnosticNotes: ["FoundationModels unavailable: \(availabilityDescription(model.availability))"]
            )
        }

        guard model.supportsLocale(localeConfiguration.locale) else {
            return .unsupported(
                .unsupportedLanguageOrLocale,
                diagnosticNotes: ["FoundationModels unsupported locale: \(localeConfiguration.identifier)"]
            )
        }

        do {
            let generated = try await stagedOutcome(
                for: prompt,
                localeConfiguration: localeConfiguration
            )
            return .generated(
                generated.outcome,
                generationMetadata: generated.generationMetadata,
                diagnosticNotes: [
                    "FoundationModels instructionVersion=\(MarinaFoundationModelInstructionCatalogV3.instructionVersion)",
                    "FoundationModels stagedGenerationPhases=\(generated.generationMetadata.phaseCount?.rawValue ?? 0)",
                    "FoundationModels stagedGenerationMaximumPhases=4",
                    "FoundationModels contextSize=\(model.contextSize)"
                ]
            )
        } catch let error as MarinaFoundationModelStagedPayloadErrorV3 {
            return stagedRuntimeResult(for: error)
        } catch let error as LanguageModelSession.GenerationError {
            return runtimeResult(for: error)
        } catch is CancellationError {
            return .generationFailure(
                .cancelled,
                diagnosticNotes: ["FoundationModels generation cancelled."]
            )
        } catch {
            return .generationFailure(
                .unexpected,
                diagnosticNotes: ["FoundationModels generationError=unexpected"]
            )
        }
    }

    /// Phase one chooses financial query, Workspace metadata, or a terminal
    /// outcome. Workspace is absent from the subsequent financial-domain schema.
    private func stagedOutcome(
        for prompt: String,
        localeConfiguration: MarinaFoundationModelLocaleConfiguration
    ) async throws -> MarinaFoundationModelStagedGeneratedOutcomeV3 {
        let routeSession = makeSession(
            instructions: instructionCatalog.outcomeRouteText(
                localeConfiguration: localeConfiguration
            )
        )
        let routePhase = try await performStagedPhase(
            generatedIntent: nil,
            metadata: MarinaFoundationModelGenerationDiagnosticMetadata(
                phase: .outcomeRoute
            ),
            priorPhaseDurations: []
        ) {
            try await routeSession.respond(
                to: prompt,
                generating: MarinaFoundationModelGeneratedOutcomeRouteV3.self,
                includeSchemaInPrompt: true,
                options: options
            )
        }
        let outcomeRoute = routePhase.value.content
        let outcomePlan = MarinaFoundationModelOutcomeGenerationPlanV3(
            modelAuthoredRoute: outcomeRoute
        )
        let outcomePath = MarinaFoundationModelGeneratedRoutePathDigest(
            outcome: outcomeRoute.diagnosticDigest
        )

        switch outcomePlan.payloadSchema {
        case .financialDomain:
            let financialDomainPhase = try await generateFinancialDomain(
                prompt: prompt,
                outcomePath: outcomePath,
                priorPhaseDurations: routePhase.generationMetadata.phaseDurations,
                localeConfiguration: localeConfiguration
            )
            let domainPlan = MarinaFoundationModelFinancialDomainGenerationPlanV3(
                modelAuthoredDomain: financialDomainPhase.value
            )
            let domainPath = MarinaFoundationModelGeneratedRoutePathDigest(
                outcome: .financialQuery,
                financialDomain: financialDomainPhase.value.diagnosticDigest
            )
            let actionRoutePhase = try await generateActionRoute(
                for: domainPlan.queryDomain,
                prompt: prompt,
                phaseCount: .four,
                routePath: domainPath,
                priorPhaseDurations: financialDomainPhase.generationMetadata.phaseDurations,
                localeConfiguration: localeConfiguration
            )
            return try await generateActionOutcome(
                for: actionRoutePhase.value,
                prompt: prompt,
                phaseCount: .four,
                baseRoutePath: domainPath,
                priorPhaseDurations: actionRoutePhase.generationMetadata.phaseDurations,
                localeConfiguration: localeConfiguration
            )
        case .workspaceMetadata:
            let actionRoutePhase = try await generateActionRoute(
                for: .workspaceMetadata,
                prompt: prompt,
                phaseCount: .three,
                routePath: outcomePath,
                priorPhaseDurations: routePhase.generationMetadata.phaseDurations,
                localeConfiguration: localeConfiguration
            )
            return try await generateActionOutcome(
                for: actionRoutePhase.value,
                prompt: prompt,
                phaseCount: .three,
                baseRoutePath: outcomePath,
                priorPhaseDurations: actionRoutePhase.generationMetadata.phaseDurations,
                localeConfiguration: localeConfiguration
            )
        case .clarificationSelection, .followUpDecision, .unsupported:
            return try await generateTerminalOutcome(
                for: outcomePlan.payloadSchema,
                prompt: prompt,
                routePath: outcomePath,
                priorPhaseDurations: routePhase.generationMetadata.phaseDurations,
                localeConfiguration: localeConfiguration
            )
        }
    }

    private func generateFinancialDomain(
        prompt: String,
        outcomePath: MarinaFoundationModelGeneratedRoutePathDigest,
        priorPhaseDurations: [MarinaFoundationModelGenerationPhaseDuration],
        localeConfiguration: MarinaFoundationModelLocaleConfiguration
    ) async throws -> MarinaFoundationModelTimedPhaseV3<MarinaFoundationModelGeneratedFinancialDomainV3> {
        let session = makeSession(
            instructions: instructionCatalog.financialDomainText(
                localeConfiguration: localeConfiguration
            )
        )
        return try await performStagedPhase(
            generatedIntent: MarinaFoundationModelGeneratedIntentDigest(intent: .query),
            metadata: MarinaFoundationModelGenerationDiagnosticMetadata(
                phase: .financialDomain,
                phaseCount: .four,
                routePath: outcomePath
            ),
            priorPhaseDurations: priorPhaseDurations
        ) {
            let response = try await session.respond(
                to: prompt,
                generating: MarinaFoundationModelGeneratedFinancialDomainV3.self,
                includeSchemaInPrompt: true,
                options: options
            )
            return response.content
        }
    }

    private func generateTerminalOutcome(
        for route: MarinaFoundationModelOutcomePayloadSchemaV3,
        prompt: String,
        routePath: MarinaFoundationModelGeneratedRoutePathDigest,
        priorPhaseDurations: [MarinaFoundationModelGenerationPhaseDuration],
        localeConfiguration: MarinaFoundationModelLocaleConfiguration
    ) async throws -> MarinaFoundationModelStagedGeneratedOutcomeV3 {
        let session = makeSession(
            instructions: instructionCatalog.terminalPayloadText(
                for: route,
                localeConfiguration: localeConfiguration
            )
        )
        let metadata = MarinaFoundationModelGenerationDiagnosticMetadata(
            phase: .terminalPayload,
            phaseCount: .two,
            routePath: routePath
        )
        let phase = try await performStagedPhase(
            generatedIntent: generatedIntent(for: route),
            metadata: metadata,
            priorPhaseDurations: priorPhaseDurations
        ) {
            switch route {
            case .clarificationSelection:
                let response = try await session.respond(
                    to: prompt,
                    generating: Generated.ClarificationSelection.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return Generated.clarificationSelection(response.content)
            case .followUpDecision:
                let response = try await session.respond(
                    to: prompt,
                    generating: Generated.FollowUpDecision.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return Generated.followUpDecision(response.content)
            case .unsupported:
                let response = try await session.respond(
                    to: prompt,
                    generating: Generated.Unsupported.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return Generated.unsupported(response.content)
            case .financialDomain, .workspaceMetadata:
                preconditionFailure("Only terminal outcome routes can generate terminal payloads.")
            }
        }
        return MarinaFoundationModelStagedGeneratedOutcomeV3(
            outcome: phase.value,
            generationMetadata: phase.generationMetadata
        )
    }

    private func generatedIntent(
        for route: MarinaFoundationModelOutcomePayloadSchemaV3
    ) -> MarinaFoundationModelGeneratedIntentDigest? {
        switch route {
        case .clarificationSelection:
            MarinaFoundationModelGeneratedIntentDigest(intent: .clarificationSelection)
        case .followUpDecision:
            MarinaFoundationModelGeneratedIntentDigest(intent: .followUpDecision)
        case .unsupported:
            MarinaFoundationModelGeneratedIntentDigest(intent: .unsupported)
        case .financialDomain:
            MarinaFoundationModelGeneratedIntentDigest(intent: .query)
        case .workspaceMetadata:
            MarinaFoundationModelGeneratedIntentDigest(
                intent: .workspaceMetadata,
                entity: .workspace
            )
        }
    }

    private func generateActionRoute(
        for domain: MarinaFoundationModelQueryDomainV3,
        prompt: String,
        phaseCount: MarinaFoundationModelGenerationPhaseCount,
        routePath: MarinaFoundationModelGeneratedRoutePathDigest,
        priorPhaseDurations: [MarinaFoundationModelGenerationPhaseDuration],
        localeConfiguration: MarinaFoundationModelLocaleConfiguration
    ) async throws -> MarinaFoundationModelTimedPhaseV3<MarinaFoundationModelAuthoredActionRouteV3> {
        let session = makeSession(
            instructions: instructionCatalog.actionRouteText(
                for: domain,
                localeConfiguration: localeConfiguration
            )
        )
        return try await performStagedPhase(
            generatedIntent: MarinaFoundationModelGeneratedIntentDigest(
                intent: domain == .workspaceMetadata ? .workspaceMetadata : .query,
                entity: domain.semanticEntity
            ),
            metadata: MarinaFoundationModelGenerationDiagnosticMetadata(
                phase: .actionRoute,
                phaseCount: phaseCount,
                routePath: routePath
            ),
            priorPhaseDurations: priorPhaseDurations
        ) {
            switch domain {
            case .workspaceMetadata:
                let response = try await session.respond(to: prompt, generating: ActionRoute.WorkspaceMetadata.self, includeSchemaInPrompt: true, options: options)
                return .workspaceMetadata(response.content)
            case .budget:
                let response = try await session.respond(to: prompt, generating: ActionRoute.Budget.self, includeSchemaInPrompt: true, options: options)
                return .budget(response.content)
            case .card:
                let response = try await session.respond(to: prompt, generating: ActionRoute.Card.self, includeSchemaInPrompt: true, options: options)
                return .card(response.content)
            case .plannedExpense:
                let response = try await session.respond(to: prompt, generating: ActionRoute.PlannedExpense.self, includeSchemaInPrompt: true, options: options)
                return .plannedExpense(response.content)
            case .variableExpense:
                let response = try await session.respond(to: prompt, generating: ActionRoute.VariableExpense.self, includeSchemaInPrompt: true, options: options)
                return .variableExpense(response.content)
            case .reconciliationAccount:
                let response = try await session.respond(to: prompt, generating: ActionRoute.ReconciliationAccount.self, includeSchemaInPrompt: true, options: options)
                return .reconciliationAccount(response.content)
            case .savingsAccount:
                let response = try await session.respond(to: prompt, generating: ActionRoute.SavingsAccount.self, includeSchemaInPrompt: true, options: options)
                return .savingsAccount(response.content)
            case .income:
                let response = try await session.respond(to: prompt, generating: ActionRoute.Income.self, includeSchemaInPrompt: true, options: options)
                return .income(response.content)
            case .incomeSeries:
                let response = try await session.respond(to: prompt, generating: ActionRoute.IncomeSeries.self, includeSchemaInPrompt: true, options: options)
                return .incomeSeries(response.content)
            case .category:
                let response = try await session.respond(to: prompt, generating: ActionRoute.Category.self, includeSchemaInPrompt: true, options: options)
                return .category(response.content)
            case .preset:
                let response = try await session.respond(to: prompt, generating: ActionRoute.Preset.self, includeSchemaInPrompt: true, options: options)
                return .preset(response.content)
            }
        }
    }

    private func generateActionOutcome(
        for actionRoute: MarinaFoundationModelAuthoredActionRouteV3,
        prompt: String,
        phaseCount: MarinaFoundationModelGenerationPhaseCount,
        baseRoutePath: MarinaFoundationModelGeneratedRoutePathDigest,
        priorPhaseDurations: [MarinaFoundationModelGenerationPhaseDuration],
        localeConfiguration: MarinaFoundationModelLocaleConfiguration
    ) async throws -> MarinaFoundationModelStagedGeneratedOutcomeV3 {
        let actionPlan = MarinaFoundationModelActionGenerationPlanV3(
            modelAuthoredActionRoute: actionRoute
        )
        let payloadSession = makeSession(
            instructions: instructionCatalog.actionPayloadText(
                for: actionPlan.payloadSchema,
                localeConfiguration: localeConfiguration
            )
        )
        let actionDigest = actionRoute.generatedIntentDigest
        let routePath = MarinaFoundationModelGeneratedRoutePathDigest(
            outcome: baseRoutePath.outcome,
            financialDomain: baseRoutePath.financialDomain,
            actionRoute: actionPlan.payloadSchema.diagnosticDigest,
            actionPayload: actionPlan.payloadSchema.diagnosticDigest
        )
        let metadata = MarinaFoundationModelGenerationDiagnosticMetadata(
            phase: .actionPayload,
            phaseCount: phaseCount,
            routePath: routePath
        )
        let startedAt = DispatchTime.now().uptimeNanoseconds

        do {
            let generated: MarinaFoundationModelStagedGeneratedOutcomeV3 = try await {
              switch actionPlan.payloadSchema {
            case .workspaceList:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.WorkspaceList.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.workspaceMetadata(Generated.WorkspaceMetadataQuery(action: .list(response.content)))),
                    generationMetadata: metadata
                )
            case .workspaceCount:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.WorkspaceCount.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.workspaceMetadata(Generated.WorkspaceMetadataQuery(action: .count(response.content)))),
                    generationMetadata: metadata
                )
            case .workspaceName:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.WorkspaceMetadataValue.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.workspaceMetadata(Generated.WorkspaceMetadataQuery(action: .name(response.content)))),
                    generationMetadata: metadata
                )
            case .workspaceColor:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.WorkspaceMetadataValue.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.workspaceMetadata(Generated.WorkspaceMetadataQuery(action: .color(response.content)))),
                    generationMetadata: metadata
                )
            case .budgetList:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.BudgetList.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.budget(Generated.BudgetQuery(action: .list(response.content)))),
                    generationMetadata: metadata
                )
            case .budgetSum:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.BudgetMetric.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.budget(Generated.BudgetQuery(action: .sum(response.content)))),
                    generationMetadata: metadata
                )
            case .budgetAverage:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.BudgetMetric.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.budget(Generated.BudgetQuery(action: .average(response.content)))),
                    generationMetadata: metadata
                )
            case .budgetCompare:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.BudgetComparison.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.budget(Generated.BudgetQuery(action: .compare(response.content)))),
                    generationMetadata: metadata
                )
            case .budgetForecast:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.BudgetForecast.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.budget(Generated.BudgetQuery(action: .forecast(response.content)))),
                    generationMetadata: metadata
                )
            case .budgetWhatIf:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.BudgetWhatIf.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.budget(Generated.BudgetQuery(action: .whatIf(response.content)))),
                    generationMetadata: metadata
                )
            case .cardList:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.CardList.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.card(Generated.CardQuery(action: .list(response.content)))),
                    generationMetadata: metadata
                )
            case .cardCount:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.CardCount.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.card(Generated.CardQuery(action: .count(response.content)))),
                    generationMetadata: metadata
                )
            case .cardSum:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.CardMetric.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.card(Generated.CardQuery(action: .sum(response.content)))),
                    generationMetadata: metadata
                )
            case .cardCompare:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.CardComparison.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.card(Generated.CardQuery(action: .compare(response.content)))),
                    generationMetadata: metadata
                )
            case .cardGroup:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.CardGroup.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.card(Generated.CardQuery(action: .group(response.content)))),
                    generationMetadata: metadata
                )
            case .plannedExpenseList:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.PlannedExpenseList.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.plannedExpense(Generated.PlannedExpenseQuery(action: .list(response.content)))),
                    generationMetadata: metadata
                )
            case .plannedExpenseCount:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.ExpenseCount.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.plannedExpense(Generated.PlannedExpenseQuery(action: .count(response.content)))),
                    generationMetadata: metadata
                )
            case .plannedExpenseSum:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.PlannedExpenseMetric.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.plannedExpense(Generated.PlannedExpenseQuery(action: .sum(response.content)))),
                    generationMetadata: metadata
                )
            case .plannedExpenseAverage:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.PlannedExpenseMetric.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.plannedExpense(Generated.PlannedExpenseQuery(action: .average(response.content)))),
                    generationMetadata: metadata
                )
            case .plannedExpenseLast:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.PlannedExpenseSingle.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.plannedExpense(Generated.PlannedExpenseQuery(action: .last(response.content)))),
                    generationMetadata: metadata
                )
            case .plannedExpenseNext:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.PlannedExpenseSingle.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.plannedExpense(Generated.PlannedExpenseQuery(action: .next(response.content)))),
                    generationMetadata: metadata
                )
            case .plannedExpenseGroup:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.PlannedExpenseGroup.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.plannedExpense(Generated.PlannedExpenseQuery(action: .group(response.content)))),
                    generationMetadata: metadata
                )
            case .variableExpenseList:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.VariableExpenseList.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.variableExpense(Generated.VariableExpenseQuery(action: .list(response.content)))),
                    generationMetadata: metadata
                )
            case .variableExpenseCount:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.ExpenseCount.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.variableExpense(Generated.VariableExpenseQuery(action: .count(response.content)))),
                    generationMetadata: metadata
                )
            case .variableExpenseSum:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.VariableExpenseMetric.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.variableExpense(Generated.VariableExpenseQuery(action: .sum(response.content)))),
                    generationMetadata: metadata
                )
            case .variableExpenseAverage:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.VariableExpenseMetric.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.variableExpense(Generated.VariableExpenseQuery(action: .average(response.content)))),
                    generationMetadata: metadata
                )
            case .variableExpenseLast:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.VariableExpenseSingle.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.variableExpense(Generated.VariableExpenseQuery(action: .last(response.content)))),
                    generationMetadata: metadata
                )
            case .variableExpenseGroup:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.VariableExpenseGroup.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.variableExpense(Generated.VariableExpenseQuery(action: .group(response.content)))),
                    generationMetadata: metadata
                )
            case .reconciliationList:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.ReconciliationList.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.reconciliationAccount(Generated.ReconciliationAccountQuery(action: .list(response.content)))),
                    generationMetadata: metadata
                )
            case .reconciliationCount:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.AccountCount.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.reconciliationAccount(Generated.ReconciliationAccountQuery(action: .count(response.content)))),
                    generationMetadata: metadata
                )
            case .reconciliationSum:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.ReconciliationMetric.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.reconciliationAccount(Generated.ReconciliationAccountQuery(action: .sum(response.content)))),
                    generationMetadata: metadata
                )
            case .reconciliationGroup:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.ReconciliationGroup.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.reconciliationAccount(Generated.ReconciliationAccountQuery(action: .group(response.content)))),
                    generationMetadata: metadata
                )
            case .savingsList:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.SavingsList.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.savingsAccount(Generated.SavingsAccountQuery(action: .list(response.content)))),
                    generationMetadata: metadata
                )
            case .savingsCount:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.AccountCount.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.savingsAccount(Generated.SavingsAccountQuery(action: .count(response.content)))),
                    generationMetadata: metadata
                )
            case .savingsSum:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.SavingsMetric.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.savingsAccount(Generated.SavingsAccountQuery(action: .sum(response.content)))),
                    generationMetadata: metadata
                )
            case .savingsLast:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.SavingsMetric.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.savingsAccount(Generated.SavingsAccountQuery(action: .last(response.content)))),
                    generationMetadata: metadata
                )
            case .savingsGroup:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.SavingsGroup.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.savingsAccount(Generated.SavingsAccountQuery(action: .group(response.content)))),
                    generationMetadata: metadata
                )
            case .savingsForecast:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.SavingsMetric.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.savingsAccount(Generated.SavingsAccountQuery(action: .forecast(response.content)))),
                    generationMetadata: metadata
                )
            case .incomeList:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.IncomeList.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.income(Generated.IncomeQuery(action: .list(response.content)))),
                    generationMetadata: metadata
                )
            case .incomeCount:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.IncomeCount.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.income(Generated.IncomeQuery(action: .count(response.content)))),
                    generationMetadata: metadata
                )
            case .incomeSum:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.IncomeMetric.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.income(Generated.IncomeQuery(action: .sum(response.content)))),
                    generationMetadata: metadata
                )
            case .incomeAverage:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.IncomeMetric.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.income(Generated.IncomeQuery(action: .average(response.content)))),
                    generationMetadata: metadata
                )
            case .incomeCompare:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.IncomeComparison.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.income(Generated.IncomeQuery(action: .compare(response.content)))),
                    generationMetadata: metadata
                )
            case .incomeGroup:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.IncomeGroup.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.income(Generated.IncomeQuery(action: .group(response.content)))),
                    generationMetadata: metadata
                )
            case .incomeProgress:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.IncomeProgress.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.income(Generated.IncomeQuery(action: .progress(response.content)))),
                    generationMetadata: metadata
                )
            case .incomeCoverage:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.IncomeCoverage.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.income(Generated.IncomeQuery(action: .coverage(response.content)))),
                    generationMetadata: metadata
                )
            case .incomeForecast:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.IncomeForecast.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.income(Generated.IncomeQuery(action: .forecast(response.content)))),
                    generationMetadata: metadata
                )
            case .incomeSeriesList:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.IncomeSeriesList.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.incomeSeries(Generated.IncomeSeriesQuery(action: .list(response.content)))),
                    generationMetadata: metadata
                )
            case .incomeSeriesCount:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.IncomeSeriesCount.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.incomeSeries(Generated.IncomeSeriesQuery(action: .count(response.content)))),
                    generationMetadata: metadata
                )
            case .incomeSeriesLast:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.IncomeSeriesSingle.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.incomeSeries(Generated.IncomeSeriesQuery(action: .last(response.content)))),
                    generationMetadata: metadata
                )
            case .incomeSeriesNext:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.IncomeSeriesSingle.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.incomeSeries(Generated.IncomeSeriesQuery(action: .next(response.content)))),
                    generationMetadata: metadata
                )
            case .categoryList:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.CategoryList.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.category(Generated.CategoryQuery(action: .list(response.content)))),
                    generationMetadata: metadata
                )
            case .categoryCount:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.CategoryCount.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.category(Generated.CategoryQuery(action: .count(response.content)))),
                    generationMetadata: metadata
                )
            case .categorySum:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.CategoryMetric.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.category(Generated.CategoryQuery(action: .sum(response.content)))),
                    generationMetadata: metadata
                )
            case .categoryAverage:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.CategoryMetric.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.category(Generated.CategoryQuery(action: .average(response.content)))),
                    generationMetadata: metadata
                )
            case .categoryCompare:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.CategoryComparison.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.category(Generated.CategoryQuery(action: .compare(response.content)))),
                    generationMetadata: metadata
                )
            case .categoryGroupedSpend:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.CategoryGroupedSpend.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.category(Generated.CategoryQuery(action: .groupedSpend(response.content)))),
                    generationMetadata: metadata
                )
            case .categoryShare:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.CategoryMetric.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.category(Generated.CategoryQuery(action: .share(response.content)))),
                    generationMetadata: metadata
                )
            case .categoryForecast:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.CategoryForecast.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.category(Generated.CategoryQuery(action: .forecast(response.content)))),
                    generationMetadata: metadata
                )
            case .categoryAvailabilitySummary:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.CategoryAvailabilitySummary.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.category(Generated.CategoryQuery(action: .availabilitySummary(response.content)))),
                    generationMetadata: metadata
                )
            case .categoryAvailabilityList:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.CategoryAvailabilityList.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.category(Generated.CategoryQuery(action: .availabilityList(response.content)))),
                    generationMetadata: metadata
                )
            case .presetList:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.PresetList.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.preset(Generated.PresetQuery(action: .list(response.content)))),
                    generationMetadata: metadata
                )
            case .presetSum:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.PresetMetric.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.preset(Generated.PresetQuery(action: .sum(response.content)))),
                    generationMetadata: metadata
                )
            case .presetNext:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.PresetSingle.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.preset(Generated.PresetQuery(action: .next(response.content)))),
                    generationMetadata: metadata
                )
            case .presetGroup:
                let response = try await payloadSession.respond(
                    to: prompt,
                    generating: Generated.PresetGroup.self,
                    includeSchemaInPrompt: true,
                    options: options
                )
                return MarinaFoundationModelStagedGeneratedOutcomeV3(
                    outcome: .query(.preset(Generated.PresetQuery(action: .group(response.content)))),
                    generationMetadata: metadata
                )
              }
            }()
            return MarinaFoundationModelStagedGeneratedOutcomeV3(
                outcome: generated.outcome,
                generationMetadata: appendingPhaseDuration(
                    metadata,
                    appendingElapsedSince: startedAt,
                    to: priorPhaseDurations
                )
            )
        } catch let error as LanguageModelSession.GenerationError {
            throw MarinaFoundationModelStagedPayloadErrorV3.generation(
                error,
                generatedIntent: actionDigest,
                generationMetadata: appendingPhaseDuration(
                    metadata,
                    appendingElapsedSince: startedAt,
                    to: priorPhaseDurations
                )
            )
        } catch is CancellationError {
            throw MarinaFoundationModelStagedPayloadErrorV3.cancelled(
                generatedIntent: actionDigest,
                generationMetadata: appendingPhaseDuration(
                    metadata,
                    appendingElapsedSince: startedAt,
                    to: priorPhaseDurations
                )
            )
        } catch {
            throw MarinaFoundationModelStagedPayloadErrorV3.unexpected(
                generatedIntent: actionDigest,
                generationMetadata: appendingPhaseDuration(
                    metadata,
                    appendingElapsedSince: startedAt,
                    to: priorPhaseDurations
                )
            )
        }
    }

    private func performStagedPhase<Value>(
        generatedIntent: MarinaFoundationModelGeneratedIntentDigest?,
        metadata: MarinaFoundationModelGenerationDiagnosticMetadata,
        priorPhaseDurations: [MarinaFoundationModelGenerationPhaseDuration],
        operation: () async throws -> Value
    ) async throws -> MarinaFoundationModelTimedPhaseV3<Value> {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        do {
            let value = try await operation()
            return MarinaFoundationModelTimedPhaseV3(
                value: value,
                generationMetadata: appendingPhaseDuration(
                    metadata,
                    appendingElapsedSince: startedAt,
                    to: priorPhaseDurations
                )
            )
        } catch let error as MarinaFoundationModelStagedPayloadErrorV3 {
            throw error.replacingGenerationMetadata(
                appendingPhaseDuration(
                    metadata,
                    appendingElapsedSince: startedAt,
                    to: priorPhaseDurations
                )
            )
        } catch let error as LanguageModelSession.GenerationError {
            throw MarinaFoundationModelStagedPayloadErrorV3.generation(
                error,
                generatedIntent: generatedIntent,
                generationMetadata: appendingPhaseDuration(
                    metadata,
                    appendingElapsedSince: startedAt,
                    to: priorPhaseDurations
                )
            )
        } catch is CancellationError {
            throw MarinaFoundationModelStagedPayloadErrorV3.cancelled(
                generatedIntent: generatedIntent,
                generationMetadata: appendingPhaseDuration(
                    metadata,
                    appendingElapsedSince: startedAt,
                    to: priorPhaseDurations
                )
            )
        } catch {
            throw MarinaFoundationModelStagedPayloadErrorV3.unexpected(
                generatedIntent: generatedIntent,
                generationMetadata: appendingPhaseDuration(
                    metadata,
                    appendingElapsedSince: startedAt,
                    to: priorPhaseDurations
                )
            )
        }
    }

    private func appendingPhaseDuration(
        _ metadata: MarinaFoundationModelGenerationDiagnosticMetadata,
        appendingElapsedSince startedAt: UInt64,
        to priorPhaseDurations: [MarinaFoundationModelGenerationPhaseDuration]
    ) -> MarinaFoundationModelGenerationDiagnosticMetadata {
        let endedAt = DispatchTime.now().uptimeNanoseconds
        let nanoseconds = endedAt >= startedAt ? endedAt - startedAt : 0
        let milliseconds = Int(min(UInt64(Int.max), nanoseconds / 1_000_000))
        return MarinaFoundationModelGenerationDiagnosticMetadata(
            phase: metadata.phase,
            phaseCount: metadata.phaseCount,
            routePath: metadata.routePath,
            phaseDurations: priorPhaseDurations + [
                MarinaFoundationModelGenerationPhaseDuration(
                    phase: metadata.phase,
                    milliseconds: milliseconds
                )
            ]
        )
    }

    /// Each phase is intentionally tool-free and transcript-free.
    private func makeSession(instructions: String) -> LanguageModelSession {
        LanguageModelSession(
            model: model,
            tools: [],
            instructions: instructions
        )
    }

    private func runtimeResult(
        for error: LanguageModelSession.GenerationError
    ) -> MarinaFoundationModelRuntimeResult {
        switch error {
        case .assetsUnavailable, .rateLimited, .concurrentRequests:
            return .unsupported(
                .unavailableModel,
                diagnosticNotes: ["FoundationModels generationError=runtimeUnavailable"]
            )
        case .exceededContextWindowSize:
            return .unsupported(
                .modelContextLimit,
                diagnosticNotes: ["FoundationModels generationError=contextLimit"]
            )
        case .guardrailViolation, .refusal:
            return .unsupported(
                .modelGuardrail,
                diagnosticNotes: ["FoundationModels generationError=guardrail"]
            )
        case .unsupportedLanguageOrLocale:
            return .unsupported(
                .unsupportedLanguageOrLocale,
                diagnosticNotes: ["FoundationModels generationError=unsupportedLocale"]
            )
        case .decodingFailure:
            return .generationFailure(
                .decodingFailure,
                diagnosticNotes: ["FoundationModels generationError=decodingFailure"]
            )
        case .unsupportedGuide:
            return .generationFailure(
                .unsupportedGuide,
                diagnosticNotes: ["FoundationModels generationError=unsupportedGuide"]
            )
        @unknown default:
            return .generationFailure(
                .unexpected,
                diagnosticNotes: ["FoundationModels generationError=unexpected"]
            )
        }
    }

    private func stagedRuntimeResult(
        for error: MarinaFoundationModelStagedPayloadErrorV3
    ) -> MarinaFoundationModelRuntimeResult {
        switch error {
        case .generation(let generationError, let generatedIntent, let generationMetadata):
            switch runtimeResult(for: generationError) {
            case .unsupported(let reason, let notes):
                return .stagedFailure(
                    .unsupported(reason),
                    generatedIntent: generatedIntent,
                    generationMetadata: generationMetadata,
                    diagnosticNotes: notes
                )
            case .generationFailure(let failure, let notes):
                return .stagedFailure(
                    .generation(failure),
                    generatedIntent: generatedIntent,
                    generationMetadata: generationMetadata,
                    diagnosticNotes: notes
                )
            case .generated, .stagedFailure:
                return .stagedFailure(
                    .generation(.unexpected),
                    generatedIntent: generatedIntent,
                    generationMetadata: generationMetadata,
                    diagnosticNotes: ["FoundationModels generationError=unexpected"]
                )
            }
        case .cancelled(let generatedIntent, let generationMetadata):
            return .stagedFailure(
                .generation(.cancelled),
                generatedIntent: generatedIntent,
                generationMetadata: generationMetadata,
                diagnosticNotes: ["FoundationModels generation cancelled."]
            )
        case .unexpected(let generatedIntent, let generationMetadata):
            return .stagedFailure(
                .generation(.unexpected),
                generatedIntent: generatedIntent,
                generationMetadata: generationMetadata,
                diagnosticNotes: ["FoundationModels generationError=unexpected"]
            )
        }
    }

    private func availabilityDescription(_ availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available:
            return "available"
        case .unavailable(.appleIntelligenceNotEnabled):
            return "appleIntelligenceNotEnabled"
        case .unavailable(.deviceNotEligible):
            return "deviceNotEligible"
        case .unavailable(.modelNotReady):
            return "modelNotReady"
        @unknown default:
            return "unavailable"
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private enum MarinaFoundationModelStagedPayloadErrorV3: Error {
    case generation(
        LanguageModelSession.GenerationError,
        generatedIntent: MarinaFoundationModelGeneratedIntentDigest?,
        generationMetadata: MarinaFoundationModelGenerationDiagnosticMetadata
    )
    case cancelled(
        generatedIntent: MarinaFoundationModelGeneratedIntentDigest?,
        generationMetadata: MarinaFoundationModelGenerationDiagnosticMetadata
    )
    case unexpected(
        generatedIntent: MarinaFoundationModelGeneratedIntentDigest?,
        generationMetadata: MarinaFoundationModelGenerationDiagnosticMetadata
    )
}

@available(iOS 26.0, macCatalyst 26.0, *)
private extension MarinaFoundationModelStagedPayloadErrorV3 {
    func replacingGenerationMetadata(
        _ generationMetadata: MarinaFoundationModelGenerationDiagnosticMetadata
    ) -> Self {
        switch self {
        case .generation(let error, let generatedIntent, _):
            .generation(
                error,
                generatedIntent: generatedIntent,
                generationMetadata: generationMetadata
            )
        case .cancelled(let generatedIntent, _):
            .cancelled(
                generatedIntent: generatedIntent,
                generationMetadata: generationMetadata
            )
        case .unexpected(let generatedIntent, _):
            .unexpected(
                generatedIntent: generatedIntent,
                generationMetadata: generationMetadata
            )
        }
    }
}

#endif

enum MarinaModelInterpreterFactory {
    @MainActor
    static func makeDefault() -> any MarinaModelInterpreting {
        makeDefault(modelBackedInterpreter: makeModelBackedInterpreter())
    }

    @MainActor
    static func makeDefault(modelBackedInterpreter: (any MarinaModelInterpreting)?) -> any MarinaModelInterpreting {
        modelBackedInterpreter ?? MarinaUnavailableModelInterpreter()
    }

    @MainActor
    static func makeModelBackedInterpreter() -> (any MarinaModelInterpreting)? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            return MarinaFoundationModelsInterpreter()
        }
        #endif
        return nil
    }
}
