import Foundation

struct MarinaFoundationModelLocaleConfiguration: Equatable, Sendable {
    static var current: MarinaFoundationModelLocaleConfiguration {
        MarinaFoundationModelLocaleConfiguration(locale: .current)
    }

    let identifier: String

    init(locale: Locale = .current) {
        self.identifier = locale.identifier
    }

    var locale: Locale {
        Locale(identifier: identifier)
    }

    var localeInstruction: String? {
        guard isUSEnglish == false else { return nil }
        return "The person's locale is \(identifier)."
    }

    var responseLanguageInstruction: String {
        "You MUST respond in \(responseLanguageName)."
    }

    func instructionsPrefix() -> String {
        [localeInstruction, responseLanguageInstruction]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    func appending(to instructions: String) -> String {
        let prefix = instructionsPrefix()
        guard prefix.isEmpty == false else { return instructions }
        return "\(prefix)\n\(instructions)"
    }

    func appendingSemanticCompiler(to instructions: String) -> String {
        let compilerPrefix = """
        Interpret the request using \(responseLanguageName) and \(identifier) locale conventions.
        Preserve named target and scope wording exactly as supplied. Typed schema cases remain canonical and are never translated.
        """
        return "\(compilerPrefix)\n\(instructions)"
    }

    private var isUSEnglish: Bool {
        let normalized = identifier.replacingOccurrences(of: "-", with: "_")
        return normalized == "en_US" || normalized.hasPrefix("en_US@")
    }

    private var responseLanguageName: String {
        let normalized = identifier.replacingOccurrences(of: "-", with: "_")

        if normalized.hasPrefix("pt_BR") {
            return "Brazilian Portuguese"
        }
        if normalized.hasPrefix("zh_Hans") {
            return "Simplified Chinese"
        }
        if normalized.hasPrefix("en_US") {
            return "U.S. English"
        }

        let languageCode = Locale(identifier: identifier).language.languageCode?.identifier ?? normalized
        switch languageCode {
        case "ar":
            return "Arabic"
        case "de":
            return "German"
        case "en":
            return "English"
        case "es":
            return "Spanish"
        case "fr":
            return "French"
        case "pt":
            return "Portuguese"
        case "zh":
            return "Chinese"
        default:
            return Locale(identifier: "en_US").localizedString(forLanguageCode: languageCode) ?? "the app's current language"
        }
    }
}
