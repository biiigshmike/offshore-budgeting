import Foundation

enum MarinaL10n {
    static func string(_ key: String, defaultValue: String, comment: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: .main, value: defaultValue, comment: comment)
    }

    static func format(_ key: String, defaultValue: String, comment: String, _ arguments: CVarArg...) -> String {
        String(
            format: string(key, defaultValue: defaultValue, comment: comment),
            locale: Locale.current,
            arguments: arguments
        )
    }

    static func common(_ key: String, defaultValue: String, comment: String) -> String {
        string("marina.common.\(key)", defaultValue: defaultValue, comment: comment)
    }
}
