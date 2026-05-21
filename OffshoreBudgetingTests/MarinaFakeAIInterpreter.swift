import Foundation
@testable import Offshore

final actor MarinaFakeAIInterpreter: MarinaAIInterpreter {
    private let scriptedIntents: [String: MarinaAIIntent]
    private let defaultIntent: MarinaAIIntent
    private(set) var receivedPrompts: [String] = []

    init(
        scriptedIntents: [String: MarinaAIIntent] = [:],
        defaultIntent: MarinaAIIntent = .unsupported(
            MarinaAIUnsupportedIntent(
                reasoning: "No scripted fake response.",
                reasonRaw: "unscripted",
                message: nil
            )
        )
    ) {
        self.scriptedIntents = scriptedIntents
        self.defaultIntent = defaultIntent
    }

    func interpretAI(
        prompt: String,
        context _: MarinaInterpretationContext
    ) async throws -> MarinaAIIntent {
        receivedPrompts.append(prompt)
        return scriptedIntents[prompt] ?? defaultIntent
    }
}
