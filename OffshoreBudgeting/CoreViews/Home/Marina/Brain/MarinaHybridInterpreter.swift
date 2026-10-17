import Foundation

struct MarinaHybridInterpreter: MarinaModelInterpreting {
    private let ruleBasedInterpreter: MarinaRuleBasedInterpreter
    private let modelBackedInterpreter: (any MarinaModelInterpreting)?

    init(
        ruleBasedInterpreter: MarinaRuleBasedInterpreter = MarinaRuleBasedInterpreter(),
        modelBackedInterpreter: (any MarinaModelInterpreting)? = nil
    ) {
        self.ruleBasedInterpreter = ruleBasedInterpreter
        self.modelBackedInterpreter = modelBackedInterpreter
    }

    func interpretedSemanticRequest(for prompt: String, context: MarinaBrainContext) async throws -> MarinaInterpretedSemanticRequest {
        let deterministic = ruleBasedInterpreter.interpretWithConfidence(prompt)
        if shouldUseDeterministicResult(deterministic) {
            return deterministic
        }

        guard let modelBackedInterpreter else {
            return MarinaInterpretedSemanticRequest(
                request: MarinaSemanticRequest(
                    entity: .workspace,
                    operation: .list,
                    expectedAnswerShape: .unsupported,
                    unsupportedReason: .unavailableModel
                ),
                confidence: .low,
                source: .unavailableFallback,
                diagnosticNotes: deterministic.diagnosticNotes + ["No Foundation Models interpreter configured."]
            )
        }

        let generated = try await modelBackedInterpreter.interpretedSemanticRequest(for: prompt, context: context)
        if generated.request.unsupportedReason == .unavailableModel,
           deterministic.request.unsupportedReason != .unsupportedCombination {
            return deterministic
        }
        return generated
    }

    private func shouldUseDeterministicResult(_ interpreted: MarinaInterpretedSemanticRequest) -> Bool {
        guard interpreted.confidence == .high else { return false }
        if interpreted.request.unsupportedReason == .unsupportedCombination {
            return false
        }
        return true
    }
}
