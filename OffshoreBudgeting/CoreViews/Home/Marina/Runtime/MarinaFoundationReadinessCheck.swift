import Foundation

struct MarinaFoundationReadinessReport: Equatable {
    let generatedAt: Date
    let prompt: String
    let steps: [MarinaFoundationReadinessStep]

    var passed: Bool {
        steps.allSatisfy { $0.status == .passed }
    }

    var failedStep: MarinaFoundationReadinessStep? {
        steps.first { $0.status == .failed }
    }
}

struct MarinaFoundationReadinessStep: Identifiable, Equatable {
    enum Kind: String, CaseIterable, Equatable {
        case marinaPreference
        case foundationRuntime
        case appleIntelligenceEligibility
        case appleIntelligenceEnabled
        case localeSupport
        case modelReadiness
        case typedInterpretation
        case deterministicExecution
    }

    enum Status: String, Equatable {
        case passed
        case failed
        case skipped
    }

    let kind: Kind
    let status: Status
    let title: String
    let detail: String

    var id: Kind { kind }
}

@MainActor
struct MarinaFoundationReadinessCheck {
    static let diagnosticPrompt = "What workspace am I in?"

    private let availability: MarinaModelAvailabilityProviding
    private let interpreter: MarinaCanonicalAIInterpreting
    private let resolver: MarinaQueryResolver
    private let validator: MarinaQueryValidator
    private let queryExecutor: MarinaQueryExecutor
    private let responseBuilder: MarinaResponseBuilder
    private let now: () -> Date

    init(
        availability: MarinaModelAvailabilityProviding? = nil,
        interpreter: MarinaCanonicalAIInterpreting? = nil,
        resolver: MarinaQueryResolver? = nil,
        validator: MarinaQueryValidator? = nil,
        queryExecutor: MarinaQueryExecutor? = nil,
        responseBuilder: MarinaResponseBuilder? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.availability = availability ?? MarinaModelAvailability()
        self.interpreter = interpreter ?? MarinaFoundationAIInterpreter()
        self.resolver = resolver ?? MarinaQueryResolver()
        self.validator = validator ?? MarinaQueryValidator()
        self.queryExecutor = queryExecutor ?? MarinaQueryExecutor(
            adapter: MarinaAggregationPlanHomeQueryAdapter(),
            executor: MarinaAggregationExecutor(),
            composableWorkspaceQueryExecutor: MarinaComposableWorkspaceQueryExecutor(),
            workspaceAggregationExecutor: MarinaWorkspaceAggregationExecutor(),
            databaseLookupExecutor: MarinaDatabaseLookupExecutor(),
            databaseLookupResponseBuilder: MarinaDatabaseLookupResponseBuilder()
        )
        self.responseBuilder = responseBuilder ?? MarinaResponseBuilder()
        self.now = now
    }

    func run(context: MarinaTurnContext) async -> MarinaFoundationReadinessReport {
        let generatedAt = now()
        var steps: [MarinaFoundationReadinessStep] = []

        guard context.aiEnabled else {
            steps.append(step(
                .marinaPreference,
                .failed,
                "Marina Foundation setting",
                "Marina is turned off in app settings."
            ))
            steps.append(contentsOf: skippedSteps(after: .marinaPreference))
            return report(generatedAt: generatedAt, steps: steps)
        }

        steps.append(step(
            .marinaPreference,
            .passed,
            "Marina Foundation setting",
            "Marina is enabled for Foundation Models."
        ))

        let availabilityStatus = availability.currentStatus()
        steps.append(contentsOf: availabilitySteps(for: availabilityStatus))
        guard availabilityStatus == .available else {
            steps.append(contentsOf: [
                step(.typedInterpretation, .skipped, "Typed interpretation", "Skipped because Foundation Models are unavailable."),
                step(.deterministicExecution, .skipped, "Deterministic execution", "Skipped because typed interpretation did not run.")
            ])
            return report(generatedAt: generatedAt, steps: steps)
        }

        let interpretation: MarinaCanonicalReadInterpretation
        do {
            interpretation = try await interpreter.interpretCanonical(
                prompt: Self.diagnosticPrompt,
                context: context.routerContext
            )
            steps.append(step(
                .typedInterpretation,
                .passed,
                "Typed interpretation",
                "Foundation Models returned a typed Marina interpretation."
            ))
        } catch {
            steps.append(step(
                .typedInterpretation,
                .failed,
                "Typed interpretation",
                String(describing: error)
            ))
            steps.append(step(
                .deterministicExecution,
                .skipped,
                "Deterministic execution",
                "Skipped because typed interpretation failed."
            ))
            return report(generatedAt: generatedAt, steps: steps)
        }

        let deterministicResult = await deterministicCoordinator(
            interpretation: interpretation
        ).run(
            prompt: Self.diagnosticPrompt,
            context: MarinaTurnContext(
                provider: context.provider,
                routerContext: context.routerContext,
                defaultPeriodUnit: context.defaultPeriodUnit,
                aiEnabled: true,
                now: context.now,
                turnClassification: .freshQuestion
            )
        )

        steps.append(deterministicExecutionStep(from: deterministicResult))
        return report(generatedAt: generatedAt, steps: steps)
    }

    private func deterministicCoordinator(
        interpretation: MarinaCanonicalReadInterpretation
    ) -> MarinaTurnCoordinator {
        MarinaTurnCoordinator(
            availability: MarinaReadinessAvailableAvailability(),
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: [
                Self.diagnosticPrompt: interpretation
            ]),
            resolver: resolver,
            validator: validator,
            queryExecutor: queryExecutor,
            responseBuilder: responseBuilder
        )
    }

    private func availabilitySteps(
        for status: MarinaModelAvailability.Status
    ) -> [MarinaFoundationReadinessStep] {
        switch status {
        case .available:
            return [
                step(.foundationRuntime, .passed, "Foundation Models runtime", "Foundation Models are present on this OS."),
                step(.appleIntelligenceEligibility, .passed, "Apple Intelligence eligibility", "This device is eligible."),
                step(.appleIntelligenceEnabled, .passed, "Apple Intelligence enabled", "Apple Intelligence is enabled."),
                step(.localeSupport, .passed, "Locale support", "The current locale is supported."),
                step(.modelReadiness, .passed, "Model readiness", "The on-device model is ready.")
            ]
        case .unavailable(let reason):
            return unavailableAvailabilitySteps(reason: reason)
        }
    }

    private func unavailableAvailabilitySteps(
        reason: MarinaModelAvailability.UnavailableReason
    ) -> [MarinaFoundationReadinessStep] {
        switch reason {
        case .runtimeUnavailable, .frameworkUnavailable:
            return [
                step(.foundationRuntime, .failed, "Foundation Models runtime", reason.rawValue),
                step(.appleIntelligenceEligibility, .skipped, "Apple Intelligence eligibility", "Skipped because Foundation Models runtime is unavailable."),
                step(.appleIntelligenceEnabled, .skipped, "Apple Intelligence enabled", "Skipped because Foundation Models runtime is unavailable."),
                step(.localeSupport, .skipped, "Locale support", "Skipped because Foundation Models runtime is unavailable."),
                step(.modelReadiness, .skipped, "Model readiness", "Skipped because Foundation Models runtime is unavailable.")
            ]
        case .deviceNotEligible:
            return [
                step(.foundationRuntime, .passed, "Foundation Models runtime", "Foundation Models are present on this OS."),
                step(.appleIntelligenceEligibility, .failed, "Apple Intelligence eligibility", reason.rawValue),
                step(.appleIntelligenceEnabled, .skipped, "Apple Intelligence enabled", "Skipped because this device is not eligible."),
                step(.localeSupport, .skipped, "Locale support", "Skipped because this device is not eligible."),
                step(.modelReadiness, .skipped, "Model readiness", "Skipped because this device is not eligible.")
            ]
        case .appleIntelligenceNotEnabled:
            return [
                step(.foundationRuntime, .passed, "Foundation Models runtime", "Foundation Models are present on this OS."),
                step(.appleIntelligenceEligibility, .passed, "Apple Intelligence eligibility", "This device is eligible."),
                step(.appleIntelligenceEnabled, .failed, "Apple Intelligence enabled", reason.rawValue),
                step(.localeSupport, .skipped, "Locale support", "Skipped because Apple Intelligence is not enabled."),
                step(.modelReadiness, .skipped, "Model readiness", "Skipped because Apple Intelligence is not enabled.")
            ]
        case .unsupportedLocale:
            return [
                step(.foundationRuntime, .passed, "Foundation Models runtime", "Foundation Models are present on this OS."),
                step(.appleIntelligenceEligibility, .passed, "Apple Intelligence eligibility", "This device is eligible."),
                step(.appleIntelligenceEnabled, .passed, "Apple Intelligence enabled", "Apple Intelligence is enabled."),
                step(.localeSupport, .failed, "Locale support", reason.rawValue),
                step(.modelReadiness, .skipped, "Model readiness", "Skipped because the current locale is unsupported.")
            ]
        case .modelNotReady:
            return [
                step(.foundationRuntime, .passed, "Foundation Models runtime", "Foundation Models are present on this OS."),
                step(.appleIntelligenceEligibility, .passed, "Apple Intelligence eligibility", "This device is eligible."),
                step(.appleIntelligenceEnabled, .passed, "Apple Intelligence enabled", "Apple Intelligence is enabled."),
                step(.localeSupport, .passed, "Locale support", "The current locale is supported."),
                step(.modelReadiness, .failed, "Model readiness", reason.rawValue)
            ]
        case .unknown:
            return [
                step(.foundationRuntime, .passed, "Foundation Models runtime", "Foundation Models are present on this OS."),
                step(.appleIntelligenceEligibility, .failed, "Apple Intelligence eligibility", reason.rawValue),
                step(.appleIntelligenceEnabled, .skipped, "Apple Intelligence enabled", "Skipped because availability returned an unknown reason."),
                step(.localeSupport, .skipped, "Locale support", "Skipped because availability returned an unknown reason."),
                step(.modelReadiness, .skipped, "Model readiness", "Skipped because availability returned an unknown reason.")
            ]
        }
    }

    private func skippedSteps(after kind: MarinaFoundationReadinessStep.Kind) -> [MarinaFoundationReadinessStep] {
        MarinaFoundationReadinessStep.Kind.allCases
            .drop { $0 != kind }
            .dropFirst()
            .map { skippedKind in
                step(
                    skippedKind,
                    .skipped,
                    title(for: skippedKind),
                    "Skipped because \(title(for: kind).lowercased()) failed."
                )
            }
    }

    private func deterministicExecutionStep(from result: MarinaTurnResult) -> MarinaFoundationReadinessStep {
        switch result {
        case .handled(let answer, _, _, _, _):
            return step(
                .deterministicExecution,
                .passed,
                "Deterministic execution",
                answer.title
            )
        case .clarification(let answer, _):
            return step(
                .deterministicExecution,
                .failed,
                "Deterministic execution",
                "Expected an evidence-backed answer, but got clarification: \(answer.title)"
            )
        case .blocked(let answer, _):
            return step(
                .deterministicExecution,
                .failed,
                "Deterministic execution",
                answer.title
            )
        case .unavailable(let answer):
            return step(
                .deterministicExecution,
                .failed,
                "Deterministic execution",
                answer.title
            )
        }
    }

    private func report(
        generatedAt: Date,
        steps: [MarinaFoundationReadinessStep]
    ) -> MarinaFoundationReadinessReport {
        MarinaFoundationReadinessReport(
            generatedAt: generatedAt,
            prompt: Self.diagnosticPrompt,
            steps: steps
        )
    }

    private func step(
        _ kind: MarinaFoundationReadinessStep.Kind,
        _ status: MarinaFoundationReadinessStep.Status,
        _ title: String,
        _ detail: String
    ) -> MarinaFoundationReadinessStep {
        MarinaFoundationReadinessStep(
            kind: kind,
            status: status,
            title: title,
            detail: detail
        )
    }

    private func title(for kind: MarinaFoundationReadinessStep.Kind) -> String {
        switch kind {
        case .marinaPreference:
            return "Marina Foundation setting"
        case .foundationRuntime:
            return "Foundation Models runtime"
        case .appleIntelligenceEligibility:
            return "Apple Intelligence eligibility"
        case .appleIntelligenceEnabled:
            return "Apple Intelligence enabled"
        case .localeSupport:
            return "Locale support"
        case .modelReadiness:
            return "Model readiness"
        case .typedInterpretation:
            return "Typed interpretation"
        case .deterministicExecution:
            return "Deterministic execution"
        }
    }
}

private struct MarinaReadinessAvailableAvailability: MarinaModelAvailabilityProviding {
    func currentStatus() -> MarinaModelAvailability.Status { .available }
}
