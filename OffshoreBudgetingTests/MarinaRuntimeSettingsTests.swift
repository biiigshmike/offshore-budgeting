import Foundation
import Testing
@testable import Offshore

struct MarinaRuntimeSettingsTests {
    @Test func defaultRuntime_isFoundationPipelineWithAIEnabled() throws {
        let defaults = try makeDefaults(suiteName: "MarinaRuntimeSettingsTests.defaultRuntime")
        defer { defaults.removePersistentDomain(forName: "MarinaRuntimeSettingsTests.defaultRuntime") }

        let settings = MarinaRuntimeSettings.resolve(
            defaults: defaults,
            arguments: [],
            environment: [:]
        )

        #expect(settings.routingMode == .foundationPipeline)
        #expect(settings.aiOptIn.isEnabled)
        #expect(settings.aiOptIn.source == .fallback)
        #expect(settings.traceSummary.contains("foundationPipeline=true"))
    }

    @Test func aiOptIn_canBeDisabledWithoutChangingFoundationPipeline() throws {
        let defaults = try makeDefaults(suiteName: "MarinaRuntimeSettingsTests.aiOptInDisabled")
        defer { defaults.removePersistentDomain(forName: "MarinaRuntimeSettingsTests.aiOptInDisabled") }
        defaults.set(false, forKey: MarinaRuntimeSettings.aiOptInKey)

        let settings = MarinaRuntimeSettings.resolve(
            defaults: defaults,
            arguments: [],
            environment: [:]
        )

        #expect(settings.routingMode == .foundationPipeline)
        #expect(settings.aiOptIn.isEnabled == false)
        #expect(settings.aiOptIn.source == .userDefaults)
        #expect(settings.traceSummary.contains("aiOptInDefaultsPresent=true"))
    }

    @Test func launchArgument_canEnableAIOptIn() throws {
        let defaults = try makeDefaults(suiteName: "MarinaRuntimeSettingsTests.launchArguments")
        defer { defaults.removePersistentDomain(forName: "MarinaRuntimeSettingsTests.launchArguments") }

        let settings = MarinaRuntimeSettings.resolve(
            aiOptInFallback: false,
            defaults: defaults,
            arguments: ["App", MarinaRuntimeSettings.aiOptInKey],
            environment: [:]
        )

        #expect(settings.routingMode == .foundationPipeline)
        #expect(settings.aiOptIn.isEnabled)
        #expect(settings.aiOptIn.source == .arguments)
        #expect(settings.aiOptIn.argumentValueWasPresent)
    }

    @Test func environment_canEnableAIOptInAndFixedNow() throws {
        let defaults = try makeDefaults(suiteName: "MarinaRuntimeSettingsTests.environment")
        defer { defaults.removePersistentDomain(forName: "MarinaRuntimeSettingsTests.environment") }

        let settings = MarinaRuntimeSettings.resolve(
            aiOptInFallback: false,
            defaults: defaults,
            arguments: [],
            environment: [
                MarinaRuntimeSettings.aiOptInKey: "on",
                MarinaRuntimeSettings.fixedNowEnvironmentKey: "2026-05-15T12:34:56Z"
            ]
        )

        #expect(settings.routingMode == .foundationPipeline)
        #expect(settings.aiOptIn.isEnabled)
        #expect(settings.aiOptIn.source == .environment)
        #expect(settings.fixedNow != nil)
        #expect(settings.traceSummary.contains("fixedNow=2026-05-15T12:34:56Z"))
    }

    @Test func traceRecorder_capturesRuntimeSettingsSummary() {
        MarinaTraceRecorder.shared.reset()
        MarinaTraceRecorder.shared.begin(
            prompt: "When did I purchase Litter Robot?",
            routingMode: .foundationPipeline,
            runtimeSettingsSummary: "foundationPipeline=true,aiOptIn=true"
        )
        MarinaTraceRecorder.shared.recordSelectedRoute(.foundationModels, reason: "test")
        let trace = MarinaTraceRecorder.shared.finish()

        #expect(trace?.runtimeSettingsSummary?.contains("foundationPipeline=true") == true)
        #expect(trace?.sanitizedLogLine.contains("runtime=foundationPipeline=true") == true)
    }

    private func makeDefaults(suiteName: String) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
