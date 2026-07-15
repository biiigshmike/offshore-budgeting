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
}
