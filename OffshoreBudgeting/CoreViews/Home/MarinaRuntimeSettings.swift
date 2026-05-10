import Foundation

struct MarinaRuntimeSettings: Equatable {
    static let nlqV1Key = "debug_marina_nlq_v1_enabled"
    static let sharedPipelineKey = "debug_marina_shared_pipeline_enabled"
    static let aiOptInKey = "marina_ai_opt_in_enabled"

    let nlqV1: DebugFeatureFlagResolver.ResolvedFlag
    let sharedPipeline: DebugFeatureFlagResolver.ResolvedFlag
    let aiOptIn: DebugFeatureFlagResolver.ResolvedFlag

    var routingMode: MarinaExecutionRoutingMode {
        if sharedPipeline.isEnabled {
            return .sharedPipeline
        }
        if nlqV1.isEnabled {
            return .nlqAuthoritative
        }
        return .modelRouter
    }

    var traceSummary: String {
        [
            "sharedPipeline=\(sharedPipeline.isEnabled)",
            "sharedPipelineSource=\(sharedPipeline.source.rawValue)",
            "sharedPipelineEnvPresent=\(sharedPipeline.environmentValueWasPresent)",
            "sharedPipelineArgPresent=\(sharedPipeline.argumentValueWasPresent)",
            "sharedPipelineDefaultsPresent=\(sharedPipeline.userDefaultsValueWasPresent)",
            "nlqV1=\(nlqV1.isEnabled)",
            "nlqV1Source=\(nlqV1.source.rawValue)",
            "aiOptIn=\(aiOptIn.isEnabled)",
            "aiOptInSource=\(aiOptIn.source.rawValue)",
            "aiOptInEnvPresent=\(aiOptIn.environmentValueWasPresent)",
            "aiOptInArgPresent=\(aiOptIn.argumentValueWasPresent)",
            "aiOptInDefaultsPresent=\(aiOptIn.userDefaultsValueWasPresent)"
        ].joined(separator: ",")
    }

    static func resolve(
        nlqV1Fallback: Bool,
        sharedPipelineFallback: Bool,
        aiOptInFallback: Bool,
        defaults: UserDefaults = .standard,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> MarinaRuntimeSettings {
        MarinaRuntimeSettings(
            nlqV1: DebugFeatureFlagResolver.resolve(
                key: nlqV1Key,
                fallback: nlqV1Fallback,
                defaults: defaults,
                arguments: arguments,
                environment: environment
            ),
            sharedPipeline: DebugFeatureFlagResolver.resolve(
                key: sharedPipelineKey,
                fallback: sharedPipelineFallback,
                defaults: defaults,
                arguments: arguments,
                environment: environment
            ),
            aiOptIn: DebugFeatureFlagResolver.resolve(
                key: aiOptInKey,
                fallback: aiOptInFallback,
                defaults: defaults,
                arguments: arguments,
                environment: environment
            )
        )
    }
}
