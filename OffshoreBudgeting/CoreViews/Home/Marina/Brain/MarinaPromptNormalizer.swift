import Foundation

/// Mechanical prompt cleanup before semantic interpretation.
///
/// This intentionally preserves casing, wording, punctuation, and numbers. It
/// only normalizes Unicode composition and whitespace so meaning remains the
/// Foundation Models compiler's responsibility.
nonisolated enum MarinaPromptNormalizer {
    static func normalize(_ input: String) -> String {
        input
            .precomposedStringWithCanonicalMapping
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .joined(separator: " ")
    }
}
