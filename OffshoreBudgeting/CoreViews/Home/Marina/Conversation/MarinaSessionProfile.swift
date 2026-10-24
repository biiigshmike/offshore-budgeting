#if canImport(FoundationModels)
import FoundationModels

@available(iOS 27.0, macCatalyst 27.0, *)
extension SessionPropertyValues {
    @SessionPropertyEntry var marinaRequiresRead: Bool = false
    @SessionPropertyEntry var marinaAllowsTools: Bool = true
}

/// Changing tool policy does not alter the stable instructions, tools, or cached history.
@available(iOS 27.0, macCatalyst 27.0, *)
nonisolated struct MarinaSessionProfile: LanguageModelSession.DynamicProfile {
    @SessionProperty(\.marinaRequiresRead) var requiresRead
    @SessionProperty(\.marinaAllowsTools) var allowsTools
    let instructions: String
    let tools: [any Tool]
    let historyTokenLimit: Int

    var body: some LanguageModelSession.DynamicProfile {
        Profile {
            Instructions(instructions)
            tools
        }
        .model(SystemLanguageModel.default)
        .toolCallingMode(!allowsTools ? .disallowed : requiresRead ? .required : .allowed)
        .historyTransform { MarinaTranscriptWindow.bounded($0, tokenLimit: historyTokenLimit) }
    }
}
#endif
