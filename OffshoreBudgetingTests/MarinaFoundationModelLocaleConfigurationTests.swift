import Foundation
import Testing
@testable import Offshore

struct MarinaFoundationModelLocaleConfigurationTests {
    @Test func usEnglish_skipsLocalePhraseButSetsResponseLanguage() {
        let configuration = MarinaFoundationModelLocaleConfiguration(locale: Locale(identifier: "en_US"))

        #expect(configuration.localeInstruction == nil)
        #expect(configuration.instructionsPrefix() == "You MUST respond in U.S. English.")
    }

    @Test func nonUSEnglish_includesExactAppleLocalePhrase() {
        let configuration = MarinaFoundationModelLocaleConfiguration(locale: Locale(identifier: "en_AU"))

        #expect(configuration.localeInstruction == "The person's locale is en_AU.")
        #expect(configuration.instructionsPrefix().contains("You MUST respond in English."))
    }

    @Test func supportedAppLocales_setExpectedResponseLanguageNames() {
        let expectations = [
            ("es", "Spanish"),
            ("fr", "French"),
            ("de", "German"),
            ("ar", "Arabic"),
            ("pt_BR", "Brazilian Portuguese"),
            ("zh_Hans", "Simplified Chinese")
        ]

        for (identifier, languageName) in expectations {
            let configuration = MarinaFoundationModelLocaleConfiguration(locale: Locale(identifier: identifier))
            #expect(configuration.localeInstruction == "The person's locale is \(configuration.identifier).")
            #expect(configuration.instructionsPrefix().contains("You MUST respond in \(languageName)."))
        }
    }

    @Test func semanticCompilerLocaleInstructionsPreserveCanonicalSchemaAndTargetWording() {
        let configuration = MarinaFoundationModelLocaleConfiguration(
            locale: Locale(identifier: "es_MX")
        )
        let instructions = configuration.appendingSemanticCompiler(to: "ROLE")

        #expect(instructions.contains("Spanish and es_MX locale conventions"))
        #expect(instructions.contains("Preserve named target and scope wording exactly as supplied"))
        #expect(instructions.contains("Typed schema cases remain canonical"))
        #expect(instructions.hasSuffix("ROLE"))
    }
}
