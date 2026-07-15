import Testing
@testable import Offshore

struct MarinaCanonicalTextNormalizerTests {
    @Test func canonicalFormPreservesUnicodeLettersAndUsesPunctuationBoundaries() {
        let result = MarinaCanonicalTextNormalizer.canonical("  CAFÉ—杂货店 • ２  ")

        #expect(result == "cafe 杂货店 2")
    }

    @Test func naturalLanguageLemmaEquatesGroceryAndGroceries() {
        #expect(MarinaCanonicalTextNormalizer.areStronglyEquivalent("Grocery", "Groceries"))
        #expect(MarinaCanonicalTextNormalizer.areStronglyEquivalent("GROCERY", "groceries"))
    }

    @Test func canonicalFormDoesNotDestructivelyStripTrailingS() {
        #expect(MarinaCanonicalTextNormalizer.areStronglyEquivalent("gas", "ga") == false)
        #expect(MarinaCanonicalTextNormalizer.areStronglyEquivalent("status", "statu") == false)
        #expect(MarinaCanonicalTextNormalizer.areStronglyEquivalent("business", "busines") == false)
    }

    @Test func foldedExactHandlesWidthDiacriticsAndSmartPunctuation() {
        #expect(
            MarinaCanonicalTextNormalizer.canonical("Ｃafé’s Budget")
                == MarinaCanonicalTextNormalizer.canonical("cafe s budget")
        )
    }
}
