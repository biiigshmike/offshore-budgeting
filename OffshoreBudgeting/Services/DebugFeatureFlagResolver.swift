import Foundation

enum DebugFeatureFlagResolver {
    enum Source: String, Equatable {
        case environment
        case arguments
        case userDefaults
        case fallback
    }

    struct ResolvedFlag: Equatable {
        let key: String
        let isEnabled: Bool
        let source: Source
        let environmentValueWasPresent: Bool
        let argumentValueWasPresent: Bool
        let userDefaultsValueWasPresent: Bool

        var traceSummary: String {
            [
                "\(key)=\(isEnabled)",
                "source=\(source.rawValue)",
                "envPresent=\(environmentValueWasPresent)",
                "argPresent=\(argumentValueWasPresent)",
                "defaultsPresent=\(userDefaultsValueWasPresent)"
            ].joined(separator: ",")
        }
    }

    static func isEnabled(
        key: String,
        fallback: Bool,
        defaults: UserDefaults = .standard,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        resolve(
            key: key,
            fallback: fallback,
            defaults: defaults,
            arguments: arguments,
            environment: environment
        ).isEnabled
    }

    static func resolve(
        key: String,
        fallback: Bool,
        defaults: UserDefaults = .standard,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ResolvedFlag {
        let environmentValueWasPresent = environment[key] != nil
        let argumentValue = valueForArgument(key: key, arguments: arguments)
        let argumentValueWasPresent = argumentValue != nil
        let storedValue = defaults.object(forKey: key)
        let userDefaultsValueWasPresent = storedValue != nil

        if let environmentValue = environment[key],
           let parsed = parseBool(environmentValue) {
            return ResolvedFlag(
                key: key,
                isEnabled: parsed,
                source: .environment,
                environmentValueWasPresent: environmentValueWasPresent,
                argumentValueWasPresent: argumentValueWasPresent,
                userDefaultsValueWasPresent: userDefaultsValueWasPresent
            )
        }

        if let argumentValue,
           let parsed = parseBool(argumentValue) {
            return ResolvedFlag(
                key: key,
                isEnabled: parsed,
                source: .arguments,
                environmentValueWasPresent: environmentValueWasPresent,
                argumentValueWasPresent: argumentValueWasPresent,
                userDefaultsValueWasPresent: userDefaultsValueWasPresent
            )
        }

        guard let storedValue else {
            return ResolvedFlag(
                key: key,
                isEnabled: fallback,
                source: .fallback,
                environmentValueWasPresent: environmentValueWasPresent,
                argumentValueWasPresent: argumentValueWasPresent,
                userDefaultsValueWasPresent: userDefaultsValueWasPresent
            )
        }

        if let boolValue = storedValue as? Bool {
            return ResolvedFlag(
                key: key,
                isEnabled: boolValue,
                source: .userDefaults,
                environmentValueWasPresent: environmentValueWasPresent,
                argumentValueWasPresent: argumentValueWasPresent,
                userDefaultsValueWasPresent: userDefaultsValueWasPresent
            )
        }

        if let numberValue = storedValue as? NSNumber {
            return ResolvedFlag(
                key: key,
                isEnabled: numberValue.boolValue,
                source: .userDefaults,
                environmentValueWasPresent: environmentValueWasPresent,
                argumentValueWasPresent: argumentValueWasPresent,
                userDefaultsValueWasPresent: userDefaultsValueWasPresent
            )
        }

        if let stringValue = storedValue as? String,
           let parsed = parseBool(stringValue) {
            return ResolvedFlag(
                key: key,
                isEnabled: parsed,
                source: .userDefaults,
                environmentValueWasPresent: environmentValueWasPresent,
                argumentValueWasPresent: argumentValueWasPresent,
                userDefaultsValueWasPresent: userDefaultsValueWasPresent
            )
        }

        return ResolvedFlag(
            key: key,
            isEnabled: fallback,
            source: .fallback,
            environmentValueWasPresent: environmentValueWasPresent,
            argumentValueWasPresent: argumentValueWasPresent,
            userDefaultsValueWasPresent: userDefaultsValueWasPresent
        )
    }

    private static func valueForArgument(key: String, arguments: [String]) -> String? {
        for (index, argument) in arguments.enumerated() {
            if argument == key || argument == "-\(key)" {
                if arguments.indices.contains(index + 1),
                   parseBool(arguments[index + 1]) != nil {
                    return arguments[index + 1]
                }
                return "true"
            }

            let supportedPrefixes = ["-\(key)=", "\(key)="]
            for prefix in supportedPrefixes where argument.hasPrefix(prefix) {
                return String(argument.dropFirst(prefix.count))
            }
        }
        return nil
    }

    private static func parseBool(_ rawValue: String) -> Bool? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y", "on", "enabled":
            return true
        case "0", "false", "no", "n", "off", "disabled":
            return false
        default:
            return nil
        }
    }
}
