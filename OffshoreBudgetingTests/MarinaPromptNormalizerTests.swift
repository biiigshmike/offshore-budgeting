import Testing
@testable import Offshore

struct MarinaPromptNormalizerTests {
    @Test func normalizationIsMechanicalAndMeaningPreserving() {
        let normalized = MarinaPromptNormalizer.normalize(
            "  How much did CAFÉ\nBusiness spend—YTD?  "
        )

        #expect(normalized == "How much did CAFÉ Business spend—YTD?")
    }

    @Test func normalizationDoesNotStripPluralSuffixesOrPunctuation() {
        #expect(MarinaPromptNormalizer.normalize("gas, status, businesses") == "gas, status, businesses")
    }

    @Test func normalizationPreservesNonLatinText() {
        #expect(MarinaPromptNormalizer.normalize("  مصروفات   البقالة  ") == "مصروفات البقالة")
        #expect(MarinaPromptNormalizer.normalize("本月\t杂货支出") == "本月 杂货支出")
    }
}
