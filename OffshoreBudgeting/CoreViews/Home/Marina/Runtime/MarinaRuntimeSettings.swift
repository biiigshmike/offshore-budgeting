import Foundation

struct MarinaRuntimeSettings: Equatable {
    static let aiOptInKey = "marina_ai_opt_in_enabled"
    static let fixedNowEnvironmentKey = "MARINA_UI_FIXED_NOW_ISO8601"
    static let traceOutputPathEnvironmentKey = "MARINA_UI_TRACE_OUTPUT_PATH"
    static let uiFakeAIInterpreterEnvironmentKey = "MARINA_UI_FAKE_AI_INTERPRETER"
    static let defaultAIOptInEnabled = true

    let aiOptIn: DebugFeatureFlagResolver.ResolvedFlag
    let fixedNow: Date?
    let traceOutputPath: String?

    var now: Date {
        fixedNow ?? Date()
    }

    var routingMode: MarinaExecutionRoutingMode {
        .foundationPipeline
    }

    var traceSummary: String {
        [
            "foundationPipeline=true",
            "aiOptIn=\(aiOptIn.isEnabled)",
            "aiOptInSource=\(aiOptIn.source.rawValue)",
            "aiOptInEnvPresent=\(aiOptIn.environmentValueWasPresent)",
            "aiOptInArgPresent=\(aiOptIn.argumentValueWasPresent)",
            "aiOptInDefaultsPresent=\(aiOptIn.userDefaultsValueWasPresent)",
            "foundationInterpretationPrompt=\(MarinaFoundationPromptVersion.interpretation.rawValue)",
            "foundationPresentationPrompt=\(MarinaFoundationPromptVersion.presentation.rawValue)",
            "foundationModelBand=\(MarinaFoundationModelBand.current.rawValue)",
            "foundationLocale=\(Locale.current.identifier)",
            "fixedNow=\(fixedNow.map(Self.iso8601String(from:)) ?? "nil")",
            "traceOutputPathPresent=\((traceOutputPath?.isEmpty == false))"
        ].joined(separator: ",")
    }

    static func resolve(
        aiOptInFallback: Bool = defaultAIOptInEnabled,
        defaults: UserDefaults = .standard,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> MarinaRuntimeSettings {
        let fixedNow = environment[fixedNowEnvironmentKey].flatMap(Self.date(fromISO8601:))
        let traceOutputPath = environment[traceOutputPathEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines)

        return MarinaRuntimeSettings(
            aiOptIn: DebugFeatureFlagResolver.resolve(
                key: aiOptInKey,
                fallback: aiOptInFallback,
                defaults: defaults,
                arguments: arguments,
                environment: environment
            ),
            fixedNow: fixedNow,
            traceOutputPath: traceOutputPath?.isEmpty == false ? traceOutputPath : nil
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
