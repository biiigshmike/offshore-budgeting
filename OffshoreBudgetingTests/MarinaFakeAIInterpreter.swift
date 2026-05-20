import Foundation
@testable import Offshore

final actor MarinaFakeAIInterpreter: MarinaAIInterpreter {
    private let scriptedIntents: [String: MarinaAIIntentV2]
    private let defaultIntent: MarinaAIIntentV2
    private(set) var receivedPrompts: [String] = []

    init(
        scriptedIntents: [String: MarinaAIIntentV2] = [:],
        defaultIntent: MarinaAIIntentV2 = .unsupported(
            MarinaAIUnsupportedIntentV2(
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
        context _: MarinaLanguageRouterContext
    ) async throws -> MarinaAIIntentV2 {
        receivedPrompts.append(prompt)
        return scriptedIntents[prompt] ?? defaultIntent
    }
}
