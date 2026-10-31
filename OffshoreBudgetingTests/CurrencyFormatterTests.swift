import Foundation
import Testing
@testable import Offshore

struct CurrencyFormatterTests {
    @Test(arguments: [nil, "", "SYSTEM"] as [String?])
    func usesRegionalCurrencyWithoutExplicitChoice(storedCode: String?) {
        #expect(CurrencyFormatter.resolveCurrencyCode(
            storedCode: storedCode, regionalCurrencyCode: "EUR"
        ) == "EUR")
    }

    @Test(arguments: ["USD", "JPY", "GBP"])
    func preservesExplicitCurrency(storedCode: String) {
        #expect(CurrencyFormatter.resolveCurrencyCode(
            storedCode: storedCode, regionalCurrencyCode: "EUR"
        ) == storedCode)
        #expect(CurrencyFormatter.resolveCurrencyCode(
            storedCode: storedCode, regionalCurrencyCode: nil
        ) == storedCode)
    }

    @Test(arguments: [nil, "", "SYSTEM"] as [String?])
    func fallsBackToUSDWhenRegionHasNoCurrency(storedCode: String?) {
        #expect(CurrencyFormatter.resolveCurrencyCode(
            storedCode: storedCode, regionalCurrencyCode: nil
        ) == "USD")
        #expect(CurrencyFormatter.resolveCurrencyCode(
            storedCode: storedCode, regionalCurrencyCode: ""
        ) == "USD")
    }

    @Test
    func displayStyleRespectsRegionalSeparatorsAndSymbolPlacement() {
        // Fix precision to isolate locale behavior from the user's saved currency.
        let style = CurrencyFormatter.currencyStyle().precision(.fractionLength(2))
        let us = 1234.56.formatted(style.locale(Locale(identifier: "en_US")))
        let french = 1234.56.formatted(style.locale(Locale(identifier: "fr_FR")))

        #expect(us.contains("1,234.56"))
        #expect(french.contains("1\u{202F}234,56"))
        #expect(!us.hasPrefix("1,234.56"))
        #expect(french.hasPrefix("1\u{202F}234,56"))
    }
}
