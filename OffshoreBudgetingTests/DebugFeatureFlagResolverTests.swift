import Foundation
import Testing
@testable import Offshore

struct DebugFeatureFlagResolverTests {
    @Test func isEnabled_acceptsStringEnabledValuesFromDefaults() throws {
        let defaults = try makeDefaults(suiteName: "DebugFeatureFlagResolverTests.enabledDefaults")
        defer { defaults.removePersistentDomain(forName: "DebugFeatureFlagResolverTests.enabledDefaults") }

        for rawValue in ["true", "YES", "on", "1", "enabled"] {
            defaults.set(rawValue, forKey: "debug_marina_shared_pipeline_enabled")

            #expect(DebugFeatureFlagResolver.isEnabled(
                key: "debug_marina_shared_pipeline_enabled",
                fallback: false,
                defaults: defaults,
                arguments: []
            ))
        }
    }

    @Test func isEnabled_acceptsLaunchArgumentEnabledValues() throws {
        let defaults = try makeDefaults(suiteName: "DebugFeatureFlagResolverTests.launchArguments")
        defer { defaults.removePersistentDomain(forName: "DebugFeatureFlagResolverTests.launchArguments") }

        #expect(DebugFeatureFlagResolver.isEnabled(
            key: "marina_ai_opt_in_enabled",
            fallback: false,
            defaults: defaults,
            arguments: ["App", "-marina_ai_opt_in_enabled", "on"]
        ))

        #expect(DebugFeatureFlagResolver.isEnabled(
            key: "debug_marina_shared_pipeline_enabled",
            fallback: false,
            defaults: defaults,
            arguments: ["App", "-debug_marina_shared_pipeline_enabled=yes"]
        ))
    }

    @Test func isEnabled_acceptsBareCheckedLaunchArguments() throws {
        let defaults = try makeDefaults(suiteName: "DebugFeatureFlagResolverTests.bareLaunchArguments")
        defer { defaults.removePersistentDomain(forName: "DebugFeatureFlagResolverTests.bareLaunchArguments") }

        let sharedPipeline = DebugFeatureFlagResolver.resolve(
            key: "debug_marina_shared_pipeline_enabled",
            fallback: false,
            defaults: defaults,
            arguments: ["App", "debug_marina_shared_pipeline_enabled"]
        )
        let aiOptIn = DebugFeatureFlagResolver.resolve(
            key: "marina_ai_opt_in_enabled",
            fallback: false,
            defaults: defaults,
            arguments: ["App", "-marina_ai_opt_in_enabled"]
        )

        #expect(sharedPipeline.isEnabled)
        #expect(sharedPipeline.source == .arguments)
        #expect(sharedPipeline.argumentValueWasPresent)
        #expect(aiOptIn.isEnabled)
        #expect(aiOptIn.source == .arguments)
        #expect(aiOptIn.argumentValueWasPresent)
    }

    @Test func isEnabled_acceptsSchemeEnvironmentEnabledValues() throws {
        let defaults = try makeDefaults(suiteName: "DebugFeatureFlagResolverTests.environment")
        defer { defaults.removePersistentDomain(forName: "DebugFeatureFlagResolverTests.environment") }

        let sharedPipeline = DebugFeatureFlagResolver.resolve(
            key: "debug_marina_shared_pipeline_enabled",
            fallback: false,
            defaults: defaults,
            arguments: [],
            environment: ["debug_marina_shared_pipeline_enabled": "yes"]
        )
        #expect(sharedPipeline.isEnabled)
        #expect(sharedPipeline.source == .environment)
        #expect(sharedPipeline.environmentValueWasPresent)

        #expect(DebugFeatureFlagResolver.isEnabled(
            key: "marina_ai_opt_in_enabled",
            fallback: false,
            defaults: defaults,
            arguments: [],
            environment: ["marina_ai_opt_in_enabled": "on"]
        ))
    }

    @Test func isEnabled_respectsExplicitDisabledValues() throws {
        let defaults = try makeDefaults(suiteName: "DebugFeatureFlagResolverTests.disabledDefaults")
        defer { defaults.removePersistentDomain(forName: "DebugFeatureFlagResolverTests.disabledDefaults") }

        defaults.set("off", forKey: "debug_marina_shared_pipeline_enabled")

        #expect(DebugFeatureFlagResolver.isEnabled(
            key: "debug_marina_shared_pipeline_enabled",
            fallback: true,
            defaults: defaults,
            arguments: []
        ) == false)
    }

    private func makeDefaults(suiteName: String) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
