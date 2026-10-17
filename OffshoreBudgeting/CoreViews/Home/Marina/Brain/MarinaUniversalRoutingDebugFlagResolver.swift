import Foundation

enum MarinaUniversalRoutingDebugFlagResolver {
    static let key = "debug_marinaUniversalRoutingEnabled"

    static func policy(
        defaults: UserDefaults = .standard,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isDebugBuild: Bool = Self.isDebugBuild
    ) -> MarinaUniversalRoutingPolicy {
        guard isDebugBuild else {
            return .disabled
        }

        guard DebugFeatureFlagResolver.isEnabled(
            key: key,
            fallback: false,
            defaults: defaults,
            arguments: arguments,
            environment: environment
        ) else {
            return .disabled
        }

        return .internalParityProven
    }

    #if DEBUG
    private static var isDebugBuild: Bool { true }
    #else
    private static var isDebugBuild: Bool { false }
    #endif
}
