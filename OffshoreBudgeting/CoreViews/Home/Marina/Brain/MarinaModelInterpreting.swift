import Foundation

protocol MarinaModelInterpreting {
    func interpretedSemanticRequest(for prompt: String, context: MarinaBrainContext) async throws -> MarinaInterpretedSemanticRequest
}

extension MarinaModelInterpreting {
    func semanticRequest(for prompt: String, context: MarinaBrainContext) async throws -> MarinaSemanticRequest {
        try await interpretedSemanticRequest(for: prompt, context: context).request
    }
}

struct MarinaUnavailableModelInterpreter: MarinaModelInterpreting {
    func interpretedSemanticRequest(for prompt: String, context: MarinaBrainContext) async throws -> MarinaInterpretedSemanticRequest {
        MarinaInterpretedSemanticRequest(
            request: MarinaSemanticRequest(
                entity: .workspace,
                operation: .list,
                expectedAnswerShape: .unsupported,
                unsupportedReason: .unavailableModel
            ),
            confidence: .low,
            source: .unavailableFallback
        )
    }
}
