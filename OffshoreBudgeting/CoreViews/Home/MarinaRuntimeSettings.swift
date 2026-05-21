import Foundation

struct MarinaRuntimeSettings: Equatable {
    static let nlqV1Key = "debug_marina_nlq_v1_enabled"
    static let sharedPipelineKey = "debug_marina_shared_pipeline_enabled"
    static let aiOptInKey = "marina_ai_opt_in_enabled"
    static let fixedNowEnvironmentKey = "MARINA_UI_FIXED_NOW_ISO8601"
    static let traceOutputPathEnvironmentKey = "MARINA_UI_TRACE_OUTPUT_PATH"
    static let realDeviceSmokeEnvironmentKey = "MARINA_REAL_DEVICE_SMOKE"
    static let realDeviceSmokeOutputPathEnvironmentKey = "MARINA_REAL_DEVICE_SMOKE_OUTPUT_PATH"
    static let realDeviceSmokeKey = "debug_marina_real_device_smoke_enabled"
    static let uiFakeAIInterpreterEnvironmentKey = "MARINA_UI_FAKE_AI_INTERPRETER"
    static let defaultNLQv1Enabled = false
    static let defaultSharedPipelineEnabled = true
    static let defaultAIOptInEnabled = true

    let nlqV1: DebugFeatureFlagResolver.ResolvedFlag
    let sharedPipeline: DebugFeatureFlagResolver.ResolvedFlag
    let aiOptIn: DebugFeatureFlagResolver.ResolvedFlag
    let realDeviceSmoke: DebugFeatureFlagResolver.ResolvedFlag
    let fixedNow: Date?
    let traceOutputPath: String?
    let realDeviceSmokeOutputPath: String?

    var now: Date {
        fixedNow ?? Date()
    }

    var routingMode: MarinaExecutionRoutingMode {
        .sharedPipeline
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
            "aiOptInDefaultsPresent=\(aiOptIn.userDefaultsValueWasPresent)",
            "realDeviceSmoke=\(realDeviceSmoke.isEnabled)",
            "realDeviceSmokeSource=\(realDeviceSmoke.source.rawValue)",
            "foundationInterpretationPrompt=\(MarinaFoundationPromptVersion.interpretationV3.rawValue)",
            "foundationPresentationPrompt=\(MarinaFoundationPromptVersion.presentationV1.rawValue)",
            "foundationModelBand=\(MarinaFoundationModelBand.current.rawValue)",
            "foundationLocale=\(Locale.current.identifier)",
            "fixedNow=\(fixedNow.map(Self.iso8601String(from:)) ?? "nil")",
            "traceOutputPathPresent=\((traceOutputPath?.isEmpty == false))",
            "realDeviceSmokeOutputPathPresent=\((realDeviceSmokeOutputPath?.isEmpty == false))"
        ].joined(separator: ",")
    }

    static func resolve(
        nlqV1Fallback: Bool = defaultNLQv1Enabled,
        sharedPipelineFallback: Bool = defaultSharedPipelineEnabled,
        aiOptInFallback: Bool = defaultAIOptInEnabled,
        defaults: UserDefaults = .standard,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> MarinaRuntimeSettings {
        let fixedNow = environment[fixedNowEnvironmentKey].flatMap(Self.date(fromISO8601:))
        let traceOutputPath = environment[traceOutputPathEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let realDeviceSmokeOutputPath = environment[realDeviceSmokeOutputPathEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines)

        return MarinaRuntimeSettings(
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
            ),
            realDeviceSmoke: DebugFeatureFlagResolver.resolve(
                key: realDeviceSmokeKey,
                fallback: false,
                environmentKey: realDeviceSmokeEnvironmentKey,
                defaults: defaults,
                arguments: arguments,
                environment: environment
            ),
            fixedNow: fixedNow,
            traceOutputPath: traceOutputPath?.isEmpty == false ? traceOutputPath : nil,
            realDeviceSmokeOutputPath: realDeviceSmokeOutputPath?.isEmpty == false ? realDeviceSmokeOutputPath : nil
        )
    }

    nonisolated private static func date(fromISO8601 rawValue: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: rawValue) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: rawValue)
    }

    nonisolated private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
