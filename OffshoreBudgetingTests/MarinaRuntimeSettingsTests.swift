import Foundation
import Testing
@testable import Offshore

struct MarinaRuntimeSettingsTests {
    @Test func defaultRuntime_usesSharedPipelineWithoutLaunchArguments() throws {
        let defaults = try makeDefaults(suiteName: "MarinaRuntimeSettingsTests.defaultRuntime")
        defer { defaults.removePersistentDomain(forName: "MarinaRuntimeSettingsTests.defaultRuntime") }

        let settings = MarinaRuntimeSettings.resolve(
            defaults: defaults,
            arguments: [],
            environment: [:]
        )

        #expect(settings.routingMode == .sharedPipeline)
        #expect(settings.sharedPipeline.isEnabled)
        #expect(settings.sharedPipeline.source == .fallback)
        #expect(settings.aiOptIn.isEnabled)
        #expect(settings.aiOptIn.source == .fallback)
    }

    @Test func aiOptInDefaults_controlModelEligibilityWithoutChangingSharedPipelineGate() throws {
        let defaults = try makeDefaults(suiteName: "MarinaRuntimeSettingsTests.aiOptInDefaults")
        defer { defaults.removePersistentDomain(forName: "MarinaRuntimeSettingsTests.aiOptInDefaults") }
        defaults.set(true, forKey: MarinaRuntimeSettings.aiOptInKey)

        let settings = MarinaRuntimeSettings.resolve(
            defaults: defaults,
            arguments: [],
            environment: [:]
        )

        #expect(settings.routingMode == .sharedPipeline)
        #expect(settings.sharedPipeline.isEnabled)
        #expect(settings.sharedPipeline.source == .fallback)
        #expect(settings.aiOptIn.isEnabled)
        #expect(settings.aiOptIn.source == .userDefaults)
        #expect(settings.traceSummary.contains("aiOptInDefaultsPresent=true"))
    }

    @Test func explicitSharedPipelineDefault_noLongerForcesLegacyRouteForDebugging() throws {
        let defaults = try makeDefaults(suiteName: "MarinaRuntimeSettingsTests.sharedPipelineDefaultDisabled")
        defer { defaults.removePersistentDomain(forName: "MarinaRuntimeSettingsTests.sharedPipelineDefaultDisabled") }
        defaults.set(false, forKey: MarinaRuntimeSettings.sharedPipelineKey)
        defaults.set(true, forKey: MarinaRuntimeSettings.aiOptInKey)

        let settings = MarinaRuntimeSettings.resolve(
            defaults: defaults,
            arguments: [],
            environment: [:]
        )

        #expect(settings.routingMode == .sharedPipeline)
        #expect(settings.sharedPipeline.isEnabled == false)
        #expect(settings.sharedPipeline.source == .userDefaults)
        #expect(settings.aiOptIn.isEnabled)
    }

    @Test func checkedLaunchArguments_selectSharedPipelineRoute() throws {
        let defaults = try makeDefaults(suiteName: "MarinaRuntimeSettingsTests.checkedLaunchArguments")
        defer { defaults.removePersistentDomain(forName: "MarinaRuntimeSettingsTests.checkedLaunchArguments") }

        let settings = MarinaRuntimeSettings.resolve(
            nlqV1Fallback: false,
            sharedPipelineFallback: false,
            aiOptInFallback: false,
            defaults: defaults,
            arguments: [
                "App",
                MarinaRuntimeSettings.sharedPipelineKey,
                MarinaRuntimeSettings.aiOptInKey
            ],
            environment: [:]
        )

        #expect(settings.routingMode == .sharedPipeline)
        #expect(settings.sharedPipeline.isEnabled)
        #expect(settings.sharedPipeline.source == .arguments)
        #expect(settings.sharedPipeline.argumentValueWasPresent)
        #expect(settings.aiOptIn.isEnabled)
        #expect(settings.aiOptIn.source == .arguments)
        #expect(settings.aiOptIn.argumentValueWasPresent)
        #expect(settings.traceSummary.contains("sharedPipelineArgPresent=true"))
        #expect(settings.traceSummary.contains("aiOptInArgPresent=true"))
    }

    @Test func schemeEnvironmentFlags_selectSharedPipelineRoute() throws {
        let defaults = try makeDefaults(suiteName: "MarinaRuntimeSettingsTests.schemeEnvironment")
        defer { defaults.removePersistentDomain(forName: "MarinaRuntimeSettingsTests.schemeEnvironment") }

        let settings = MarinaRuntimeSettings.resolve(
            nlqV1Fallback: false,
            sharedPipelineFallback: false,
            aiOptInFallback: false,
            defaults: defaults,
            arguments: [],
            environment: [
                MarinaRuntimeSettings.sharedPipelineKey: "yes",
                MarinaRuntimeSettings.aiOptInKey: "on"
            ]
        )

        #expect(settings.routingMode == .sharedPipeline)
        #expect(settings.sharedPipeline.isEnabled)
        #expect(settings.sharedPipeline.source == .environment)
        #expect(settings.aiOptIn.isEnabled)
        #expect(settings.aiOptIn.source == .environment)
        #expect(settings.traceSummary.contains("sharedPipeline=true"))
        #expect(settings.traceSummary.contains("sharedPipelineSource=environment"))
    }

    @Test func runtimeSettings_staysFoundationOnlyWhenSharedPipelineDisabled() throws {
        let defaults = try makeDefaults(suiteName: "MarinaRuntimeSettingsTests.modelRouter")
        defer { defaults.removePersistentDomain(forName: "MarinaRuntimeSettingsTests.modelRouter") }

        let settings = MarinaRuntimeSettings.resolve(
            nlqV1Fallback: false,
            sharedPipelineFallback: false,
            aiOptInFallback: true,
            defaults: defaults,
            arguments: [],
            environment: [:]
        )

        #expect(settings.routingMode == .sharedPipeline)
        #expect(settings.sharedPipeline.isEnabled == false)
    }

    @Test func traceRecorder_capturesRuntimeSettingsSummary() {
        MarinaTraceRecorder.shared.reset()
        MarinaTraceRecorder.shared.begin(
            prompt: "When did I purchase Litter Robot?",
            routingMode: .sharedPipeline,
            marinaNLQv1Enabled: false,
            runtimeSettingsSummary: "sharedPipeline=true,sharedPipelineSource=environment,aiOptIn=true"
        )
        MarinaTraceRecorder.shared.recordSelectedRoute(.sharedHeuristic, reason: "test")
        let trace = MarinaTraceRecorder.shared.finish()

        #expect(trace?.runtimeSettingsSummary?.contains("sharedPipelineSource=environment") == true)
        #expect(trace?.sanitizedLogLine.contains("runtime=sharedPipeline=true") == true)
    }

    private func makeDefaults(suiteName: String) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
